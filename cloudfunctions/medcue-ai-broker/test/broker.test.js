"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const { createBrokerHandler } = require("../src/broker");

test("rejects an unauthenticated request without calling the provider", async () => {
  let providerCallCount = 0;
  const handler = createBrokerHandler({
    config: {
      clientToken: "test-client-token",
      providerAPIKey: "test-provider-key",
      providerModel: "test-model",
    },
    fetchProvider: async () => {
      providerCallCount += 1;
      throw new Error("provider must not be called");
    },
  });

  const response = await handler({
    method: "POST",
    path: "/v1/respond",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      request_id: "9efaf74f-7b86-4e02-af9a-bc24951cfb07",
      prompt: "请解释如何查看用药记录。",
    }),
  });

  assert.equal(response.status, 401);
  assert.deepEqual(JSON.parse(response.body), {
    error: { code: "unauthorized", message: "Request authentication failed." },
  });
  assert.equal(providerCallCount, 0);
});

test("rejects unsupported routes before calling the provider", async () => {
  let providerCallCount = 0;
  const handler = createBrokerHandler({
    config: {
      clientToken: "test-client-token",
      providerAPIKey: "test-provider-key",
      providerModel: "test-model",
    },
    fetchProvider: async () => {
      providerCallCount += 1;
      throw new Error("provider must not be called");
    },
  });

  const response = await handler({
    method: "GET",
    path: "/health",
    headers: { authorization: "Bearer test-client-token" },
    body: "",
  });

  assert.equal(response.status, 404);
  assert.deepEqual(JSON.parse(response.body), {
    error: { code: "not_found", message: "Route not found." },
  });
  assert.equal(providerCallCount, 0);
});

test("rejects unsupported methods on the response route", async () => {
  const handler = createBrokerHandler({
    config: {
      clientToken: "test-client-token",
      providerAPIKey: "test-provider-key",
      providerModel: "test-model",
    },
    fetchProvider: async () => {
      throw new Error("provider must not be called");
    },
  });

  const response = await handler({
    method: "GET",
    path: "/v1/respond",
    headers: { authorization: "Bearer test-client-token" },
    body: "",
  });

  assert.equal(response.status, 405);
  assert.equal(response.headers.allow, "POST");
  assert.deepEqual(JSON.parse(response.body), {
    error: { code: "method_not_allowed", message: "Method not allowed." },
  });
});

test("requires an application/json request body", async () => {
  const handler = createBrokerHandler({
    config: {
      clientToken: "test-client-token",
      providerAPIKey: "test-provider-key",
      providerModel: "test-model",
    },
    fetchProvider: async () => {
      throw new Error("provider must not be called");
    },
  });

  const response = await handler({
    method: "POST",
    path: "/v1/respond",
    headers: {
      authorization: "Bearer test-client-token",
      "content-type": "text/plain",
    },
    body: "{}",
  });

  assert.equal(response.status, 415);
  assert.deepEqual(JSON.parse(response.body), {
    error: {
      code: "unsupported_media_type",
      message: "Content-Type must be application/json.",
    },
  });
});

test("rejects malformed JSON", async () => {
  const handler = createBrokerHandler({
    config: {
      clientToken: "test-client-token",
      providerAPIKey: "test-provider-key",
      providerModel: "test-model",
    },
    fetchProvider: async () => {
      throw new Error("provider must not be called");
    },
  });

  const response = await handler({
    method: "POST",
    path: "/v1/respond",
    headers: {
      authorization: "Bearer test-client-token",
      "content-type": "application/json; charset=utf-8",
    },
    body: "{",
  });

  assert.equal(response.status, 400);
  assert.deepEqual(JSON.parse(response.body), {
    error: { code: "invalid_json", message: "Request body must be valid JSON." },
  });
});

test("requires a canonical UUID request_id", async () => {
  const handler = createBrokerHandler({
    config: {
      clientToken: "test-client-token",
      providerAPIKey: "test-provider-key",
      providerModel: "test-model",
    },
    fetchProvider: async () => {
      throw new Error("provider must not be called");
    },
  });

  const response = await handler({
    method: "POST",
    path: "/v1/respond",
    headers: {
      authorization: "Bearer test-client-token",
      "content-type": "application/json",
    },
    body: JSON.stringify({ request_id: "not-a-uuid", prompt: "hello" }),
  });

  assert.equal(response.status, 422);
  assert.deepEqual(JSON.parse(response.body), {
    error: {
      code: "invalid_request",
      message: "request_id must be a canonical UUID.",
    },
  });
});

test("requires a non-empty prompt no longer than 12000 characters", async () => {
  const handler = createBrokerHandler({
    config: {
      clientToken: "test-client-token",
      providerAPIKey: "test-provider-key",
      providerModel: "test-model",
    },
    fetchProvider: async () => {
      throw new Error("provider must not be called");
    },
  });

  const response = await handler({
    method: "POST",
    path: "/v1/respond",
    headers: {
      authorization: "Bearer test-client-token",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      request_id: "9efaf74f-7b86-4e02-af9a-bc24951cfb07",
      prompt: "x".repeat(12001),
    }),
  });

  assert.equal(response.status, 422);
  assert.deepEqual(JSON.parse(response.body), {
    error: {
      code: "invalid_request",
      message: "prompt must contain 1 to 12000 characters.",
    },
  });
});

test("sends a fixed Doubao request and returns only the normalized answer", async () => {
  let capturedURL;
  let capturedOptions;
  const handler = createBrokerHandler({
    config: {
      clientToken: "test-client-token",
      providerAPIKey: "test-provider-key",
      providerModel: "doubao-seed-2-0-lite-260428",
    },
    fetchProvider: async (url, options) => {
      capturedURL = url;
      capturedOptions = options;
      return {
        status: 200,
        headers: { get: () => "provider-request-id" },
        json: async () => ({ output_text: "  安全回答。  " }),
      };
    },
  });

  const response = await handler({
    method: "POST",
    path: "/v1/respond",
    headers: {
      authorization: "Bearer test-client-token",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      request_id: "9efaf74f-7b86-4e02-af9a-bc24951cfb07",
      prompt: "如何查看用药记录？",
      provider: "attacker",
      model: "attacker-model",
      endpoint: "https://example.invalid/",
    }),
  });

  assert.equal(
    capturedURL,
    "https://ark.cn-beijing.volces.com/api/v3/responses",
  );
  assert.equal(capturedOptions.method, "POST");
  assert.equal(
    capturedOptions.headers.authorization,
    "Bearer test-provider-key",
  );
  assert.deepEqual(JSON.parse(capturedOptions.body), {
    model: "doubao-seed-2-0-lite-260428",
    input: [
      {
        role: "user",
        content: [{ type: "input_text", text: "如何查看用药记录？" }],
      },
    ],
  });
  assert.equal(response.status, 200);
  assert.deepEqual(JSON.parse(response.body), {
    request_id: "9efaf74f-7b86-4e02-af9a-bc24951cfb07",
    answer: "安全回答。",
  });
});

test("fails closed when provider configuration is incomplete", async () => {
  const handler = createBrokerHandler({
    config: { clientToken: "test-client-token" },
    fetchProvider: async () => {
      throw new Error("provider must not be called");
    },
  });

  const response = await handler({
    method: "POST",
    path: "/v1/respond",
    headers: {
      authorization: "Bearer test-client-token",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      request_id: "9efaf74f-7b86-4e02-af9a-bc24951cfb07",
      prompt: "hello",
    }),
  });

  assert.equal(response.status, 503);
  assert.deepEqual(JSON.parse(response.body), {
    error: {
      code: "service_unavailable",
      message: "AI service is not configured.",
    },
  });
});

test("maps provider failures without exposing provider response bodies", async () => {
  const cases = [
    [401, 502, "provider_authentication_failed"],
    [403, 502, "provider_authentication_failed"],
    [429, 429, "rate_limited"],
    [500, 502, "provider_unavailable"],
  ];

  for (const [providerStatus, expectedStatus, expectedCode] of cases) {
    const handler = createBrokerHandler({
      config: {
        clientToken: "test-client-token",
        providerAPIKey: "test-provider-key",
        providerModel: "test-model",
      },
      fetchProvider: async () => ({
        status: providerStatus,
        headers: { get: () => "provider-request-id" },
        json: async () => ({ secret_provider_body: "must not leak" }),
      }),
    });

    const response = await handler({
      method: "POST",
      path: "/v1/respond",
      headers: {
        authorization: "Bearer test-client-token",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        request_id: "9efaf74f-7b86-4e02-af9a-bc24951cfb07",
        prompt: "hello",
      }),
    });

    assert.equal(response.status, expectedStatus);
    assert.equal(JSON.parse(response.body).error.code, expectedCode);
    assert.equal(response.body.includes("secret_provider_body"), false);
  }
});

test("maps a provider timeout to a stable gateway timeout response", async () => {
  const handler = createBrokerHandler({
    config: {
      clientToken: "test-client-token",
      providerAPIKey: "test-provider-key",
      providerModel: "test-model",
    },
    fetchProvider: async (_url, options) => {
      assert.ok(options.signal);
      const error = new Error("timed out with sensitive request details");
      error.name = "AbortError";
      throw error;
    },
  });

  const response = await handler({
    method: "POST",
    path: "/v1/respond",
    headers: {
      authorization: "Bearer test-client-token",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      request_id: "9efaf74f-7b86-4e02-af9a-bc24951cfb07",
      prompt: "hello",
    }),
  });

  assert.equal(response.status, 504);
  assert.deepEqual(JSON.parse(response.body), {
    error: {
      code: "provider_timeout",
      message: "AI provider timed out.",
    },
  });
});

test("reuses a completed response for the same request_id", async () => {
  let providerCallCount = 0;
  const handler = createBrokerHandler({
    config: {
      clientToken: "test-client-token",
      providerAPIKey: "test-provider-key",
      providerModel: "test-model",
    },
    fetchProvider: async () => {
      providerCallCount += 1;
      return {
        status: 200,
        headers: { get: () => "provider-request-id" },
        json: async () => ({ output_text: "answer" }),
      };
    },
  });
  const request = {
    method: "POST",
    path: "/v1/respond",
    headers: {
      authorization: "Bearer test-client-token",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      request_id: "9efaf74f-7b86-4e02-af9a-bc24951cfb07",
      prompt: "hello",
    }),
  };

  const first = await handler(request);
  const retry = await handler(request);

  assert.deepEqual(retry, first);
  assert.equal(providerCallCount, 1);
});

test("rejects request bodies larger than 32768 bytes", async () => {
  const handler = createBrokerHandler({
    config: {
      clientToken: "test-client-token",
      providerAPIKey: "test-provider-key",
      providerModel: "test-model",
    },
    fetchProvider: async () => {
      throw new Error("provider must not be called");
    },
  });

  const response = await handler({
    method: "POST",
    path: "/v1/respond",
    headers: {
      authorization: "Bearer test-client-token",
      "content-type": "application/json",
    },
    body: "x".repeat(32769),
  });

  assert.equal(response.status, 413);
  assert.deepEqual(JSON.parse(response.body), {
    error: {
      code: "payload_too_large",
      message: "Request body is too large.",
    },
  });
});

test("rate limits distinct requests while allowing an idempotent retry", async () => {
  const handler = createBrokerHandler({
    config: {
      clientToken: "test-client-token",
      providerAPIKey: "test-provider-key",
      providerModel: "test-model",
      rateLimitMax: 1,
      rateLimitWindowMs: 60_000,
    },
    fetchProvider: async () => ({
      status: 200,
      headers: { get: () => "provider-request-id" },
      json: async () => ({ output_text: "answer" }),
    }),
  });
  const headers = {
    authorization: "Bearer test-client-token",
    "content-type": "application/json",
  };
  const first = await handler({
    method: "POST",
    path: "/v1/respond",
    headers,
    body: JSON.stringify({
      request_id: "9efaf74f-7b86-4e02-af9a-bc24951cfb07",
      prompt: "hello",
    }),
  });
  const retry = await handler({
    method: "POST",
    path: "/v1/respond",
    headers,
    body: JSON.stringify({
      request_id: "9efaf74f-7b86-4e02-af9a-bc24951cfb07",
      prompt: "hello",
    }),
  });
  const next = await handler({
    method: "POST",
    path: "/v1/respond",
    headers,
    body: JSON.stringify({
      request_id: "aa8dddc3-5096-4e76-865d-dfae9a43ea7d",
      prompt: "second",
    }),
  });

  assert.equal(retry.status, first.status);
  assert.equal(next.status, 429);
  assert.deepEqual(JSON.parse(next.body), {
    error: {
      code: "rate_limited",
      message: "Too many requests. Try again later.",
    },
  });
});

test("rejects an empty provider answer instead of returning false success", async () => {
  const handler = createBrokerHandler({
    config: {
      clientToken: "test-client-token",
      providerAPIKey: "test-provider-key",
      providerModel: "test-model",
    },
    fetchProvider: async () => ({
      status: 200,
      headers: { get: () => "provider-request-id" },
      json: async () => ({ output_text: "   " }),
    }),
  });

  const response = await handler({
    method: "POST",
    path: "/v1/respond",
    headers: {
      authorization: "Bearer test-client-token",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      request_id: "9efaf74f-7b86-4e02-af9a-bc24951cfb07",
      prompt: "hello",
    }),
  });

  assert.equal(response.status, 502);
  assert.deepEqual(JSON.parse(response.body), {
    error: {
      code: "invalid_provider_response",
      message: "AI provider returned an invalid response.",
    },
  });
});

test("rejects reuse of a request_id with a different prompt", async () => {
  let providerCallCount = 0;
  const handler = createBrokerHandler({
    config: {
      clientToken: "test-client-token",
      providerAPIKey: "test-provider-key",
      providerModel: "test-model",
    },
    fetchProvider: async () => {
      providerCallCount += 1;
      return {
        status: 200,
        headers: { get: () => "provider-request-id" },
        json: async () => ({ output_text: "answer" }),
      };
    },
  });
  const headers = {
    authorization: "Bearer test-client-token",
    "content-type": "application/json",
  };
  await handler({
    method: "POST",
    path: "/v1/respond",
    headers,
    body: JSON.stringify({
      request_id: "9efaf74f-7b86-4e02-af9a-bc24951cfb07",
      prompt: "first",
    }),
  });
  const conflict = await handler({
    method: "POST",
    path: "/v1/respond",
    headers,
    body: JSON.stringify({
      request_id: "9efaf74f-7b86-4e02-af9a-bc24951cfb07",
      prompt: "different",
    }),
  });

  assert.equal(conflict.status, 409);
  assert.equal(JSON.parse(conflict.body).error.code, "idempotency_conflict");
  assert.equal(providerCallCount, 1);
});
