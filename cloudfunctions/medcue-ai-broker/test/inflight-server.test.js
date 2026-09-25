"use strict";

const assert = require("node:assert/strict");
const http = require("node:http");
const test = require("node:test");

const { createServer } = require("../index");

const REQUEST_ID = "9efaf74f-7b86-4e02-af9a-bc24951cfb07";

test(
  "a disconnected HTTP waiter does not cancel shared provider work",
  { timeout: 5_000 },
  async (t) => {
    let providerCallCount = 0;
    let signalProviderStarted;
    let releaseProvider;
    const providerStarted = new Promise((resolve) => {
      signalProviderStarted = resolve;
    });
    const providerBarrier = new Promise((resolve) => {
      releaseProvider = resolve;
    });
    const server = createServer({
      config: {
        clientToken: "test-client-token",
        providerAPIKey: "test-provider-key",
        providerModel: "test-model",
      },
      fetchProvider: async () => {
        providerCallCount += 1;
        signalProviderStarted();
        await providerBarrier;
        return new Response(JSON.stringify({ output_text: "shared answer" }), {
          headers: { "content-type": "application/json" },
        });
      },
    });
    let requestCount = 0;
    let signalSecondRequest;
    const secondRequestReceived = new Promise((resolve) => {
      signalSecondRequest = resolve;
    });
    server.on("request", () => {
      requestCount += 1;
      if (requestCount === 2) {
        signalSecondRequest();
      }
    });
    await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
    t.after(() => server.close());
    const { port } = server.address();
    const body = JSON.stringify({ request_id: REQUEST_ID, prompt: "hello" });

    const disconnected = http.request({
      host: "127.0.0.1",
      port,
      path: "/v1/respond",
      method: "POST",
      headers: {
        authorization: "Bearer test-client-token",
        "content-type": "application/json",
        "content-length": Buffer.byteLength(body),
      },
    });
    disconnected.on("error", () => {});
    disconnected.end(body);
    await providerStarted;
    disconnected.destroy();

    const waiter = fetch(`http://127.0.0.1:${port}/v1/respond`, {
      method: "POST",
      headers: {
        authorization: "Bearer test-client-token",
        "content-type": "application/json",
      },
      body,
    });
    await secondRequestReceived;
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(providerCallCount, 1);
    releaseProvider();
    const response = await waiter;

    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
      request_id: REQUEST_ID,
      answer: "shared answer",
    });
    assert.equal(providerCallCount, 1);
  },
);
