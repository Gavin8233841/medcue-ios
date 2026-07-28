import { spawn } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, extname, resolve } from "node:path";

export const DEFAULT_MODEL = "gpt-image-2";
export const DEFAULT_OUTPUT_DIR = "artifacts/openai-images";
export const DEFAULT_LOCAL_HOST = "127.0.0.1";
export const DEFAULT_LOCAL_PORT = 8787;
export const KEYCHAIN_SERVICE = "appcontest-openai-image";
export const KEYCHAIN_ACCOUNT = "openai-image-api";
export const OPENAI_IMAGE_ENDPOINT = "https://api.openai.com/v1/images/generations";

const VALID_OUTPUT_FORMATS = new Set(["png", "jpeg", "webp"]);

export function parseArgs(argv) {
  const result = { _: [] };

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith("--")) {
      result._.push(token);
      continue;
    }

    const withoutPrefix = token.slice(2);
    const equalsIndex = withoutPrefix.indexOf("=");
    if (equalsIndex >= 0) {
      result[withoutPrefix.slice(0, equalsIndex)] = withoutPrefix.slice(equalsIndex + 1);
      continue;
    }

    const next = argv[index + 1];
    if (next === undefined || next.startsWith("--")) {
      result[withoutPrefix] = true;
      continue;
    }

    result[withoutPrefix] = next;
    index += 1;
  }

  return result;
}

export function extensionForOutputFormat(format) {
  if (!format) {
    return "png";
  }

  if (!VALID_OUTPUT_FORMATS.has(format)) {
    throw new Error(`Unsupported output_format: ${format}`);
  }

  return format === "jpeg" ? "jpg" : format;
}

export function buildImageRequest(input) {
  const prompt = input.prompt?.trim();
  if (!prompt) {
    throw new Error("Missing required prompt.");
  }

  const body = {
    model: input.model || DEFAULT_MODEL,
    prompt,
  };

  copyOptional(body, input, "n", (value) => toNumber(value, "n"));
  copyOptional(body, input, "size");
  copyOptional(body, input, "quality");
  copyOptional(body, input, "background");
  copyOptional(body, input, "output_format");
  copyOptional(body, input, "output_compression", (value) => toNumber(value, "output_compression"));
  copyOptional(body, input, "user");

  if (input.extra_json) {
    const extra = JSON.parse(input.extra_json);
    if (!extra || Array.isArray(extra) || typeof extra !== "object") {
      throw new Error("--extra-json must be a JSON object.");
    }
    Object.assign(body, extra);
  }

  return body;
}

export async function resolveOpenAIAPIKey() {
  const envKey = process.env.OPENAI_API_KEY?.trim();
  if (envKey) {
    return { key: envKey, source: "OPENAI_API_KEY" };
  }

  const keychainKey = await readKeychainPassword();
  if (keychainKey) {
    return { key: keychainKey, source: `Keychain:${KEYCHAIN_SERVICE}/${KEYCHAIN_ACCOUNT}` };
  }

  throw new Error(
    `OpenAI API key not found. Set OPENAI_API_KEY or run tools/install-openai-image-key.sh to store it in macOS Keychain.`
  );
}

export async function requestImageGeneration(requestBody, apiKey) {
  const response = await fetch(OPENAI_IMAGE_ENDPOINT, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(requestBody),
  });

  const text = await response.text();
  let payload;
  try {
    payload = text ? JSON.parse(text) : {};
  } catch {
    payload = { raw: text };
  }

  if (!response.ok) {
    const message = payload?.error?.message || `OpenAI image request failed with HTTP ${response.status}.`;
    const error = new Error(message);
    error.status = response.status;
    error.payload = payload;
    throw error;
  }

  return payload;
}

export async function saveImagesFromResponse(responsePayload, outputPath, requestedFormat) {
  const images = responsePayload?.data;
  if (!Array.isArray(images) || images.length === 0) {
    throw new Error("OpenAI response did not contain data[].");
  }

  const saved = [];
  const hasMultipleImages = images.length > 1;

  for (let index = 0; index < images.length; index += 1) {
    const image = images[index];
    let bytes;
    if (image?.b64_json) {
      bytes = Buffer.from(image.b64_json, "base64");
    } else if (image?.url) {
      const response = await fetch(image.url);
      if (!response.ok) {
        throw new Error(`Failed to download OpenAI response image at index ${index}.`);
      }
      bytes = Buffer.from(await response.arrayBuffer());
    } else {
      throw new Error(`OpenAI response image at index ${index} did not contain b64_json or url.`);
    }

    const format = image.output_format || requestedFormat || "png";
    const extension = extensionForOutputFormat(format);
    const resolvedOutput = resolveOutputPath(outputPath, extension, hasMultipleImages, index);
    await mkdir(dirname(resolvedOutput), { recursive: true });
    await writeFile(resolvedOutput, bytes);
    saved.push(resolvedOutput);
  }

  return saved;
}

export function sanitizeError(error) {
  const message = error?.message || String(error);
  const status = Number.isInteger(error?.status) ? error.status : 500;
  return {
    error: {
      message,
      type: "local_openai_image_proxy_error",
    },
    status,
  };
}

async function readKeychainPassword() {
  if (process.platform !== "darwin") {
    return undefined;
  }

  return new Promise((resolvePromise) => {
    const child = spawn("security", [
      "find-generic-password",
      "-a",
      KEYCHAIN_ACCOUNT,
      "-s",
      KEYCHAIN_SERVICE,
      "-w",
    ]);

    let stdout = "";
    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });

    child.on("error", () => resolvePromise(undefined));
    child.on("close", (code) => {
      if (code !== 0) {
        resolvePromise(undefined);
        return;
      }
      resolvePromise(stdout.trim() || undefined);
    });
  });
}

function copyOptional(target, source, key, transform = String) {
  const value = source[key];
  if (value === undefined || value === true || value === "") {
    return;
  }

  target[key] = transform(value);
}

function toNumber(value, key) {
  const number = Number(value);
  if (!Number.isFinite(number)) {
    throw new Error(`Invalid numeric value for ${key}: ${value}`);
  }
  return number;
}

function resolveOutputPath(outputPath, extension, hasMultipleImages, index) {
  const requested = resolve(outputPath);
  const requestedExtension = extname(requested);
  const withExtension = requestedExtension ? requested : `${requested}.${extension}`;

  if (!hasMultipleImages) {
    return withExtension;
  }

  const extensionToUse = extname(withExtension);
  const base = withExtension.slice(0, -extensionToUse.length);
  return `${base}-${index + 1}${extensionToUse}`;
}
