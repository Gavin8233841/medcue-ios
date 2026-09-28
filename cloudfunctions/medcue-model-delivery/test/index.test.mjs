import assert from "node:assert/strict";
import { timingSafeEqual } from "node:crypto";
import test from "node:test";
import worker from "../src/index.mjs";

crypto.subtle.timingSafeEqual = (a, b) => timingSafeEqual(Buffer.from(a), Buffer.from(b));

const token = "a".repeat(32);
const path = "https://model.example/v1/model/minicpm4-0.5b";
const size = 265_307_040;

function fixture() {
  const calls = [];
  const env = {
    DOWNLOAD_TOKEN: token,
    DOWNLOAD_LIMITER: { limit: async ({ key }) => { calls.push(["limit", key]); return { success: true }; } },
    MODEL_BUCKET: {
      head: async (key) => { calls.push(["head", key]); return { size, httpEtag: '"etag"' }; },
      get: async (key, options) => {
        calls.push(["get", key, options.range?.get("range")]);
        return {
          size,
          httpEtag: '"etag"',
          range: options.range ? { offset: 4, length: 3 } : undefined,
          body: new Uint8Array([1, 2, 3]),
        };
      },
    },
  };
  return { env, calls };
}

function request(url = path, method = "GET", headers = {}) {
  return new Request(url, { method, headers: { authorization: `Bearer ${token}`, "cf-connecting-ip": "192.0.2.1", ...headers } });
}

test("unknown path, missing code, and invalid range never read R2", async () => {
  const { env, calls } = fixture();
  assert.equal((await worker.fetch(request(`${path}/extra`), env)).status, 404);
  assert.equal((await worker.fetch(request(path, "GET", { authorization: "Bearer wrong" }), env)).status, 404);
  assert.equal((await worker.fetch(request(path, "GET", { range: "bytes=0-999999999" }), env)).status, 416);
  assert.deepEqual(calls, []);
});

test("authorized HEAD and ranged GET expose only the pinned object", async () => {
  const { env, calls } = fixture();
  const head = await worker.fetch(request(path, "HEAD"), env);
  assert.equal(head.status, 200);
  assert.equal(head.headers.get("content-length"), String(size));
  const ranged = await worker.fetch(request(path, "GET", { range: "bytes=4-6" }), env);
  assert.equal(ranged.status, 206);
  assert.equal(ranged.headers.get("content-range"), `bytes 4-6/${size}`);
  assert.deepEqual([...new Uint8Array(await ranged.arrayBuffer())], [1, 2, 3]);
  assert.deepEqual(calls.map((call) => call[0]), ["limit", "head", "limit", "get"]);
  assert.equal(calls[1][1], "MiniCPM4-0.5B-QAT-Int4_gptq_aware_q4_0.gguf");
});

test("rate limit rejects before reading R2", async () => {
  const { env, calls } = fixture();
  env.DOWNLOAD_LIMITER.limit = async () => ({ success: false });
  const response = await worker.fetch(request(), env);
  assert.equal(response.status, 429);
  assert.equal(response.headers.get("retry-after"), "60");
  assert.deepEqual(calls, []);
});
