#!/usr/bin/env node
import {
  DEFAULT_MODEL,
  DEFAULT_OUTPUT_DIR,
  buildImageRequest,
  extensionForOutputFormat,
  parseArgs,
  requestImageGeneration,
  resolveOpenAIAPIKey,
  saveImagesFromResponse,
} from "./openai-image-shared.mjs";

const args = parseArgs(process.argv.slice(2));

if (args.help) {
  printHelp();
  process.exit(0);
}

try {
  const requestBody = buildImageRequest({
    model: args.model || DEFAULT_MODEL,
    prompt: args.prompt || args._.join(" "),
    n: args.n,
    size: args.size,
    quality: args.quality,
    background: args.background,
    output_format: args["output-format"] || args.output_format,
    output_compression: args["output-compression"] || args.output_compression,
    user: args.user,
    extra_json: args["extra-json"],
  });

  const requestedFormat = requestBody.output_format || "png";
  const extension = extensionForOutputFormat(requestedFormat);
  const outputPath =
    args.output ||
    `${DEFAULT_OUTPUT_DIR}/openai-image-${new Date().toISOString().replace(/[:.]/g, "-")}.${extension}`;

  const credential = await resolveOpenAIAPIKey();
  const responsePayload = await requestImageGeneration(requestBody, credential.key);
  const savedPaths = await saveImagesFromResponse(responsePayload, outputPath, requestedFormat);

  console.log(
    JSON.stringify(
      {
        ok: true,
        model: requestBody.model,
        keySource: credential.source,
        files: savedPaths,
      },
      null,
      2
    )
  );
} catch (error) {
  console.error(`openai-image-generate failed: ${error.message}`);
  process.exit(1);
}

function printHelp() {
  console.log(`Usage:
  node tools/openai-image-generate.mjs --prompt "一张..."

Options:
  --prompt <text>                 Required unless prompt is passed as positional text.
  --output <path>                 Output file path. Default: ${DEFAULT_OUTPUT_DIR}/openai-image-<timestamp>.png
  --model <id>                    Default: ${DEFAULT_MODEL}
  --size <value>                  Passed through to OpenAI Image API.
  --quality <value>               Passed through to OpenAI Image API.
  --background <value>            Passed through to OpenAI Image API.
  --output-format <png|jpeg|webp> Passed through as output_format.
  --output-compression <number>   Passed through as output_compression.
  --n <number>                    Number of images.
  --extra-json <json>             Merge exact JSON fields into the OpenAI request body.

Credentials:
  Reads OPENAI_API_KEY first, then macOS Keychain service appcontest-openai-image account openai-image-api.
`);
}
