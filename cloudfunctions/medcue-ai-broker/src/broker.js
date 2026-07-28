"use strict";

function jsonResponse(status, payload, headers = {}) {
  return {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      ...headers,
    },
    body: JSON.stringify(payload),
  };
}

const DOUBAO_RESPONSES_ENDPOINT =
  "https://ark.cn-beijing.volces.com/api/v3/responses";

function createBrokerHandler({ config, fetchProvider }) {
  const completedResponses = new Map();
  const requestTimestamps = [];

  return async function handle(request) {
    const authorization = request.headers?.authorization;
    if (authorization !== `Bearer ${config.clientToken}`) {
      return jsonResponse(401, {
        error: {
          code: "unauthorized",
          message: "Request authentication failed.",
        },
      });
    }

    if (request.path !== "/v1/respond") {
      return jsonResponse(404, {
        error: { code: "not_found", message: "Route not found." },
      });
    }

    if (request.method !== "POST") {
      return jsonResponse(
        405,
        {
          error: {
            code: "method_not_allowed",
            message: "Method not allowed.",
          },
        },
        { allow: "POST" },
      );
    }

    const contentType = request.headers?.["content-type"] ?? "";
    if (!contentType.toLowerCase().startsWith("application/json")) {
      return jsonResponse(415, {
        error: {
          code: "unsupported_media_type",
          message: "Content-Type must be application/json.",
        },
      });
    }

    if (
      typeof request.body !== "string" ||
      Buffer.byteLength(request.body, "utf8") > 32768
    ) {
      return jsonResponse(413, {
        error: {
          code: "payload_too_large",
          message: "Request body is too large.",
        },
      });
    }

    let payload;
    try {
      payload = JSON.parse(request.body);
    } catch {
      return jsonResponse(400, {
        error: {
          code: "invalid_json",
          message: "Request body must be valid JSON.",
        },
      });
    }

    const canonicalUUID =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    if (
      typeof payload.request_id !== "string" ||
      !canonicalUUID.test(payload.request_id)
    ) {
      return jsonResponse(422, {
        error: {
          code: "invalid_request",
          message: "request_id must be a canonical UUID.",
        },
      });
    }

    if (
      typeof payload.prompt !== "string" ||
      payload.prompt.trim().length === 0 ||
      payload.prompt.length > 12000
    ) {
      return jsonResponse(422, {
        error: {
          code: "invalid_request",
          message: "prompt must contain 1 to 12000 characters.",
        },
      });
    }

    if (
      typeof config.providerAPIKey !== "string" ||
      config.providerAPIKey.trim().length === 0 ||
      typeof config.providerModel !== "string" ||
      config.providerModel.trim().length === 0
    ) {
      return jsonResponse(503, {
        error: {
          code: "service_unavailable",
          message: "AI service is not configured.",
        },
      });
    }

    const now = Date.now();
    const completed = completedResponses.get(payload.request_id);
    if (completed && completed.expiresAt > now) {
      if (completed.prompt !== payload.prompt) {
        return jsonResponse(409, {
          error: {
            code: "idempotency_conflict",
            message: "request_id was already used for another request.",
          },
        });
      }
      return completed.response;
    }
    if (completed) {
      completedResponses.delete(payload.request_id);
    }

    const rateLimitWindowMs = config.rateLimitWindowMs ?? 60_000;
    const rateLimitMax = config.rateLimitMax ?? 30;
    while (
      requestTimestamps.length > 0 &&
      requestTimestamps[0] <= now - rateLimitWindowMs
    ) {
      requestTimestamps.shift();
    }
    if (requestTimestamps.length >= rateLimitMax) {
      return jsonResponse(429, {
        error: {
          code: "rate_limited",
          message: "Too many requests. Try again later.",
        },
      });
    }
    requestTimestamps.push(now);

    const abortController = new AbortController();
    const timeout = setTimeout(
      () => abortController.abort(),
      config.providerTimeoutMs ?? 20000,
    );
    let providerResponse;
    try {
      providerResponse = await fetchProvider(DOUBAO_RESPONSES_ENDPOINT, {
        method: "POST",
        headers: {
          authorization: `Bearer ${config.providerAPIKey}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          model: config.providerModel,
          input: [
            {
              role: "user",
              content: [{ type: "input_text", text: payload.prompt }],
            },
          ],
        }),
        signal: abortController.signal,
      });
    } catch (error) {
      if (error?.name === "AbortError") {
        return jsonResponse(504, {
          error: {
            code: "provider_timeout",
            message: "AI provider timed out.",
          },
        });
      }
      return jsonResponse(502, {
        error: {
          code: "provider_unavailable",
          message: "AI provider is temporarily unavailable.",
        },
      });
    } finally {
      clearTimeout(timeout);
    }
    if (providerResponse.status === 401 || providerResponse.status === 403) {
      return jsonResponse(502, {
        error: {
          code: "provider_authentication_failed",
          message: "AI provider authentication failed.",
        },
      });
    }
    if (providerResponse.status === 429) {
      return jsonResponse(429, {
        error: {
          code: "rate_limited",
          message: "Too many requests. Try again later.",
        },
      });
    }
    if (providerResponse.status < 200 || providerResponse.status >= 300) {
      return jsonResponse(502, {
        error: {
          code: "provider_unavailable",
          message: "AI provider is temporarily unavailable.",
        },
      });
    }
    let providerPayload;
    try {
      providerPayload = await providerResponse.json();
    } catch {
      return jsonResponse(502, {
        error: {
          code: "invalid_provider_response",
          message: "AI provider returned an invalid response.",
        },
      });
    }
    const outputText =
      typeof providerPayload.output_text === "string"
        ? providerPayload.output_text
        : providerPayload.output
            ?.flatMap((item) => item?.content ?? [])
            .map((content) => content?.text)
            .filter((text) => typeof text === "string")
            .join("\n");
    const answer = typeof outputText === "string" ? outputText.trim() : "";
    if (answer.length === 0) {
      return jsonResponse(502, {
        error: {
          code: "invalid_provider_response",
          message: "AI provider returned an invalid response.",
        },
      });
    }

    const response = jsonResponse(200, {
      request_id: payload.request_id,
      answer,
    });
    const cacheMax = config.idempotencyCacheMax ?? 1000;
    if (completedResponses.size >= cacheMax) {
      const oldestKey = completedResponses.keys().next().value;
      completedResponses.delete(oldestKey);
    }
    completedResponses.set(payload.request_id, {
      prompt: payload.prompt,
      response,
      expiresAt: now + (config.idempotencyTTLms ?? 300_000),
    });
    return response;
  };
}

module.exports = { createBrokerHandler };
