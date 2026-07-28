#!/usr/bin/env node
import { createServer } from "node:http";
import {
  DEFAULT_LOCAL_HOST,
  DEFAULT_LOCAL_PORT,
  DEFAULT_MODEL,
  buildImageRequest,
  parseArgs,
  requestImageGeneration,
  resolveOpenAIAPIKey,
  sanitizeError,
} from "./openai-image-shared.mjs";

const args = parseArgs(process.argv.slice(2));

if (args.help) {
  printHelp();
  process.exit(0);
}

const host = args.host || process.env.OPENAI_IMAGE_LOCAL_HOST || DEFAULT_LOCAL_HOST;
const port = Number(args.port || process.env.OPENAI_IMAGE_LOCAL_PORT || DEFAULT_LOCAL_PORT);
const credential = await resolveOpenAIAPIKey();

const server = createServer(async (request, response) => {
  try {
    await route(request, response);
  } catch (error) {
    const sanitized = sanitizeError(error);
    sendJSON(response, sanitized.status, sanitized);
  }
});

server.listen(port, host, () => {
  console.log(
    JSON.stringify(
      {
        ok: true,
        service: "openai-image-api-server",
        baseURL: `http://${host}:${port}`,
        generationPath: "/v1/images/generations",
        modelDefault: DEFAULT_MODEL,
        keySource: credential.source,
      },
      null,
      2
    )
  );
});

async function route(request, response) {
  const url = new URL(request.url || "/", `http://${host}:${port}`);

  if (request.method === "GET" && (url.pathname === "/" || url.pathname === "/health")) {
    sendJSON(response, 200, {
      ok: true,
      modelDefault: DEFAULT_MODEL,
      generationPath: "/v1/images/generations",
      keySource: credential.source,
    });
    return;
  }

  if (request.method === "POST" && url.pathname === "/v1/images/generations") {
    const requestPayload = await readJSON(request);
    const requestBody = buildImageRequest({
      ...requestPayload,
      model: requestPayload.model || DEFAULT_MODEL,
      extra_json: undefined,
    });
    const openAIResponse = await requestImageGeneration(requestBody, credential.key);
    sendJSON(response, 200, openAIResponse);
    return;
  }

  sendJSON(response, 404, {
    error: {
      message: `No local route for ${request.method} ${url.pathname}`,
      type: "local_openai_image_proxy_not_found",
    },
  });
}

async function readJSON(request) {
  const chunks = [];
  let totalLength = 0;

  for await (const chunk of request) {
    totalLength += chunk.length;
    if (totalLength > 1024 * 1024) {
      throw new Error("Request body is larger than 1 MiB.");
    }
    chunks.push(chunk);
  }

  if (chunks.length === 0) {
    return {};
  }

  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    const error = new Error("Request body must be valid JSON.");
    error.status = 400;
    throw error;
  }
}

function sendJSON(response, status, payload) {
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
  });
  response.end(JSON.stringify(payload, null, 2));
}

function printHelp() {
  console.log(`Usage:
  node tools/openai-image-api-server.mjs

Options:
  --host <host>  Default: ${DEFAULT_LOCAL_HOST}
  --port <port>  Default: ${DEFAULT_LOCAL_PORT}

Routes:
  GET  /health
  POST /v1/images/generations

Credentials:
  Reads OPENAI_API_KEY first, then macOS Keychain service appcontest-openai-image account openai-image-api.
`);
}
