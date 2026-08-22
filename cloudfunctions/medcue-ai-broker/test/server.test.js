"use strict";

const assert = require("node:assert/strict");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const test = require("node:test");

const { createServer } = require("../index");

test("serves the broker contract through the native HTTP adapter", async (t) => {
  const server = createServer({
    config: {
      clientToken: "test-client-token",
      providerAPIKey: "test-provider-key",
      providerModel: "test-model",
    },
    fetchProvider: async () =>
      new Response(JSON.stringify({ output_text: "answer" }), {
        headers: { "content-type": "application/json" },
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

test("refuses to create a server with incomplete security configuration", () => {
  const valid = {
    clientToken: "test-client-token",
    providerAPIKey: "test-provider-key",
    providerModel: "test-model",
  };
  const invalidConfigs = [
    { ...valid, clientToken: undefined },
    { ...valid, clientToken: "" },
    { ...valid, providerAPIKey: undefined },
    { ...valid, providerAPIKey: "   " },
    { ...valid, providerModel: undefined },
    { ...valid, providerModel: "" },
  ];

  for (const config of invalidConfigs) {
    assert.throws(
      () => createServer({ config, fetchProvider: async () => null }),
      {
        name: "BrokerConfigurationError",
        message: "Broker security configuration is incomplete.",
      },
    );
  }
});

test("exits before listening when environment configuration is incomplete", () => {
  const entry = path.join(__dirname, "..", "index.js");
  const result = spawnSync(process.execPath, [entry], {
    encoding: "utf8",
    env: {
      ...process.env,
      MEDCUE_BROKER_CLIENT_TOKEN: "",
      ARK_API_KEY: "",
      ARK_MODEL: "",
    },
    timeout: 2_000,
  });

  assert.notEqual(result.status, 0);
  assert.equal(result.signal, null);
  assert.match(result.stderr, /Broker security configuration is incomplete/);
});
