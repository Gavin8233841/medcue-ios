"use strict";

const http = require("node:http");
const { createBrokerHandler } = require("./src/broker");

function createServer({
  config = {
    clientToken: process.env.MEDCUE_BROKER_CLIENT_TOKEN,
    providerAPIKey: process.env.ARK_API_KEY,
    providerModel: process.env.ARK_MODEL,
  },
  fetchProvider = globalThis.fetch,
} = {}) {
  const handleBrokerRequest = createBrokerHandler({ config, fetchProvider });

  return http.createServer(async (req, res) => {
    const chunks = [];
    let byteCount = 0;

    for await (const chunk of req) {
      byteCount += chunk.length;
      if (byteCount > 32768) {
        res.writeHead(413, {
          "content-type": "application/json; charset=utf-8",
        });
        res.end(
          JSON.stringify({
            error: {
              code: "payload_too_large",
              message: "Request body is too large.",
            },
          }),
        );
        return;
      }
      chunks.push(chunk);
    }

    const response = await handleBrokerRequest({
      method: req.method,
      path: new URL(req.url || "/", "http://127.0.0.1").pathname,
      headers: req.headers,
      body: Buffer.concat(chunks).toString("utf8"),
    });

    res.writeHead(response.status, response.headers);
    res.end(response.body);
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
