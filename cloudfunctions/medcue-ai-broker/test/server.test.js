"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const { createServer } = require("../index");

test("serves the broker contract through the native HTTP adapter", async (t) => {
  const server = createServer({
    config: {
      clientToken: "test-client-token",
      providerAPIKey: "test-provider-key",
      providerModel: "test-model",
    },
    fetchProvider: async () => ({
      status: 200,
      headers: { get: () => "provider-request-id" },
      json: async () => ({ output_text: "answer" }),
    }),
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  t.after(() => server.close());
  const address = server.address();

  const response = await fetch(
    `http://127.0.0.1:${address.port}/v1/respond`,
    {
      method: "POST",
      headers: {
        authorization: "Bearer test-client-token",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        request_id: "9efaf74f-7b86-4e02-af9a-bc24951cfb07",
        prompt: "hello",
      }),
    },
  );

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    request_id: "9efaf74f-7b86-4e02-af9a-bc24951cfb07",
    answer: "answer",
  });
});
