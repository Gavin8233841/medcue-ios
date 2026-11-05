"use strict";

const http = require("node:http");
const { createBrokerHandler } = require("./src/broker");

const INTERNAL_ERROR_RESPONSE = {
  status: 500,
  headers: { "content-type": "application/json; charset=utf-8" },
  body: JSON.stringify({
    error: {
      code: "internal_error",
      message: "The broker could not process the request.",
    },
  }),
};

const INVALID_URL_RESPONSE = {
  status: 400,
  headers: { "content-type": "application/json; charset=utf-8" },
  body: JSON.stringify({
    error: {
      code: "invalid_url",
      message: "Request URL is invalid.",
    },
  }),
};

function isDisconnected(request, response) {
  return (
    request.aborted ||
    (request.destroyed && !request.complete) ||
    response.destroyed ||
    response.writableEnded
  );
}

function writeResponse(response, payload) {
  if (response.destroyed || response.writableEnded || response.headersSent) {
    return;
  }

  try {
    response.writeHead(payload.status, payload.headers);
    response.end(payload.body);
  } catch {
    // A client can disconnect between the state check and the write.
    try {
      response.destroy();
    } catch {
      // The response may already be closed.
    }
  }
}

async function serveRequest(request, response, handleBrokerRequest) {
  try {
    const chunks = [];
    let byteCount = 0;

    for await (const chunk of request) {
      byteCount += chunk.length;
      if (byteCount > 32768) {
        writeResponse(response, {
          status: 413,
          headers: { "content-type": "application/json; charset=utf-8" },
          body: JSON.stringify({
            error: {
              code: "payload_too_large",
              message: "Request body is too large.",
            },
          }),
        });
        return;
      }
      chunks.push(chunk);
    }

    let path;
    try {
      path = new URL(request.url || "/", "http://127.0.0.1").pathname;
    } catch {
      writeResponse(response, INVALID_URL_RESPONSE);
      return;
    }

    const brokerResponse = await handleBrokerRequest({
      method: request.method,
      path,
      headers: request.headers,
      body: Buffer.concat(chunks).toString("utf8"),
    });
    writeResponse(response, brokerResponse);
  } catch (error) {
    if (isDisconnected(request, response)) {
      return;
    }
    writeResponse(response, INTERNAL_ERROR_RESPONSE);
  }
}

function createServer({
  config = {
    clientToken: process.env.MEDCUE_BROKER_CLIENT_TOKEN,
    providerAPIKey: process.env.ARK_API_KEY,
    providerModel: process.env.ARK_MODEL,
  },
  fetchProvider = globalThis.fetch,
} = {}) {
  const handleBrokerRequest = createBrokerHandler({ config, fetchProvider });

  return http.createServer((req, res) => {
    // Keep stream errors from becoming unhandled when a peer disconnects.
    req.on("error", () => {});
    res.on("error", () => {});
    void serveRequest(req, res, handleBrokerRequest);
  });
}

if (require.main === module) {
  try {
    createServer().listen(9000);
  } catch (error) {
    if (error?.name !== "BrokerConfigurationError") {
      throw error;
    }
    console.error(error.message);
    process.exitCode = 1;
  }
}

module.exports = { createServer };
