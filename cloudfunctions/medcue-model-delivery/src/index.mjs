const MODEL_KEY = "MiniCPM4-0.5B-QAT-Int4_gptq_aware_q4_0.gguf";
const MODEL_SIZE = 265_307_040;
const MODEL_PATH = "/v1/model/minicpm4-0.5b";
const encoder = new TextEncoder();

function empty(status, extraHeaders = {}) {
  return new Response(null, {
    status,
    headers: {
      "cache-control": "private, no-store",
      "x-content-type-options": "nosniff",
      ...extraHeaders,
    },
  });
}

function authorized(request, expectedToken) {
  const header = request.headers.get("authorization") || "";
  const supplied = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (!/^[a-f0-9]{32}$/.test(expectedToken || "") || !/^[a-f0-9]{32}$/.test(supplied)) {
    return false;
  }
  return crypto.subtle.timingSafeEqual(encoder.encode(supplied), encoder.encode(expectedToken));
}

function validRange(value) {
  if (value === null) return true;
  const match = /^bytes=(\d+)-(\d*)$/.exec(value);
  if (!match) return false;
  const start = Number(match[1]);
  const end = match[2] ? Number(match[2]) : MODEL_SIZE - 1;
  return Number.isSafeInteger(start) && Number.isSafeInteger(end)
    && start <= end && end < MODEL_SIZE;
}

export default {
  async fetch(request, env) {
    try {
      const url = new URL(request.url);
      if (url.pathname !== MODEL_PATH || url.search || !["GET", "HEAD"].includes(request.method)) {
        return empty(404);
      }
      if (!authorized(request, env.DOWNLOAD_TOKEN)) return empty(404);
      const requestedRange = request.headers.get("range");
      if (!validRange(requestedRange) || (request.method === "HEAD" && requestedRange !== null)) {
        return empty(416);
      }

      const actor = request.headers.get("cf-connecting-ip") || "unknown";
      const { success } = await env.DOWNLOAD_LIMITER.limit({ key: actor });
      if (!success) return empty(429, { "retry-after": "60" });

      const object = request.method === "HEAD"
        ? await env.MODEL_BUCKET.head(MODEL_KEY)
        : await env.MODEL_BUCKET.get(MODEL_KEY, {
          range: requestedRange === null ? undefined : new Headers({ Range: requestedRange }),
        });
      if (!object || object.size !== MODEL_SIZE) return empty(503);

      const headers = new Headers({
        "accept-ranges": "bytes",
        "cache-control": "private, no-store",
        "content-type": "application/octet-stream",
        "x-content-type-options": "nosniff",
        etag: object.httpEtag,
      });
      const range = requestedRange === null ? undefined : object.range;
      if (requestedRange !== null && !range) return empty(503);
      if (range) {
        headers.set("content-length", String(range.length));
        headers.set("content-range", `bytes ${range.offset}-${range.offset + range.length - 1}/${MODEL_SIZE}`);
      } else {
        headers.set("content-length", String(MODEL_SIZE));
      }
      return new Response(request.method === "HEAD" ? null : object.body, {
        status: range ? 206 : 200,
        headers,
      });
    } catch {
      return empty(503);
    }
  },
};
