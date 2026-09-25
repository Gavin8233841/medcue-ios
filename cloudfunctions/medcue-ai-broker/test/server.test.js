"use strict";

const assert = require("node:assert/strict");
const net = require("node:net");
const path = require("node:path");
const { once } = require("node:events");
const { spawn } = require("node:child_process");
const { spawnSync } = require("node:child_process");
const test = require("node:test");

const { createServer } = require("../index");

function waitForChildMessage(child, predicate, timeoutMs = 2_000) {
  return new Promise((resolve, reject) => {
    let timer;
    const cleanup = () => {
      clearTimeout(timer);
      child.off("message", onMessage);
      child.off("exit", onExit);
    };
    const onMessage = (message) => {
      if (!predicate(message)) return;
      cleanup();
      resolve(message);
    };
    const onExit = (code, signal) => {
      cleanup();
      reject(new Error(`broker child exited early: ${code}/${signal}`));
    };

    timer = setTimeout(() => {
      cleanup();
      reject(new Error("timed out waiting for broker child event"));
    }, timeoutMs);
    child.on("message", onMessage);
    child.once("exit", onExit);
  });
}

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

test("returns generic responses for malformed URLs and unexpected handler errors", { timeout: 10_000 }, async (t) => {
  const config = {
    clientToken: "test-client-token",
    providerAPIKey: "test-provider-key",
    providerModel: "test-model",
  };
  let rateLimitWindowReads = 0;
  Object.defineProperty(config, "rateLimitWindowMs", {
    get() {
      rateLimitWindowReads += 1;
      if (rateLimitWindowReads === 1) {
        throw new Error("sensitive handler detail");
      }
      return 60_000;
    },
  });
  const server = createServer({
    config,
    fetchProvider: async () =>
      new Response(JSON.stringify({ output_text: "answer" }), {
        headers: { "content-type": "application/json" },
      }),
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  t.after(() => server.close());
  const address = server.address();

  const malformedURL = await new Promise((resolve, reject) => {
    const socket = net.createConnection(address.port, address.address, () => {
      socket.end(
        "POST http://[::1 HTTP/1.1\r\n" +
          "Host: 127.0.0.1\r\n" +
          "Authorization: Bearer test-client-token\r\n" +
          "Content-Type: application/json\r\n" +
          "Content-Length: 2\r\n\r\n{}",
      );
    });
    let output = "";
    socket.on("data", (chunk) => {
      output += chunk;
    });
    socket.on("end", () => resolve(output));
    socket.on("error", reject);
  });
  assert.match(malformedURL, /400 Bad Request/);
  assert.match(malformedURL, /"code":"invalid_url"/);
  assert.doesNotMatch(malformedURL, /sensitive|stack|TypeError/);

  const unexpectedHandler = await fetch(
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
  assert.equal(unexpectedHandler.status, 500);
  const unexpectedBody = await unexpectedHandler.text();
  assert.deepEqual(JSON.parse(unexpectedBody), {
    error: {
      code: "internal_error",
      message: "The broker could not process the request.",
    },
  });
  assert.doesNotMatch(unexpectedBody, /sensitive|stack|TypeError/);

  const valid = await fetch(
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
  assert.equal(valid.status, 200);
});

test("survives a disconnected request under strict unhandled-rejection mode", { timeout: 10_000 }, async (t) => {
  const entry = path.join(__dirname, "..");
  const child = spawn(
    process.execPath,
    [
      "--unhandled-rejections=strict",
      "-e",
      `const { createServer } = require(${JSON.stringify(path.join(entry, "index.js"))});
const server = createServer({
  config: { clientToken: "test-client-token", providerAPIKey: "test-provider-key", providerModel: "test-model" },
  fetchProvider: async () => new Response(JSON.stringify({ output_text: "answer" }), { headers: { "content-type": "application/json" } }),
});
server.on("request", (req) => {
  if (req.url !== "/v1/respond?disconnect=1") return;
  req.once("data", () => process.send?.({ event: "body-received" }));
  req.once("aborted", () => process.send?.({ event: "request-aborted" }));
  req.once("error", () => process.send?.({ event: "request-error" }));
});
process.on("message", (message) => {
  if (message !== "close") return;
  server.close(() => process.exit(0));
  server.closeAllConnections?.();
});
server.listen(0, "127.0.0.1", () => process.stdout.write(String(server.address().port) + "\\n"));`,
    ],
    { stdio: ["ignore", "pipe", "pipe", "ipc"] },
  );
  t.after(() => {
    if (child.exitCode === null && child.signalCode === null) {
      child.kill("SIGTERM");
    }
  });

  let port;
  let stdout = "";
  child.stdout.setEncoding("utf8");
  child.stdout.on("data", (chunk) => {
    stdout += chunk;
  });
  await new Promise((resolve, reject) => {
    let timer;
    const onData = () => {
      const line = stdout.split("\n")[0];
      if (!line) return;
      clearTimeout(timer);
      port = Number(line);
      child.stdout.off("data", onData);
      child.off("exit", onExit);
      resolve();
    };
    const onExit = (code, signal) => {
      clearTimeout(timer);
      if (port === undefined) {
        reject(new Error(`broker child exited before listening: ${code}/${signal}`));
      }
    };
    timer = setTimeout(() => {
      child.stdout.off("data", onData);
      child.off("exit", onExit);
      reject(new Error("timed out waiting for broker child to listen"));
    }, 2_000);
    child.stdout.on("data", onData);
    child.once("error", reject);
    child.once("exit", onExit);
  });

  const invalid = await fetch(`http://127.0.0.1:${port}/v1/respond`, {
    method: "POST",
    headers: {
      authorization: "Bearer test-client-token",
      "content-type": "application/json",
    },
    body: "null",
  });
  assert.equal(invalid.status, 422);
  assert.deepEqual(await invalid.json(), {
    error: {
      code: "invalid_request",
      message: "Request body must be a JSON object.",
    },
  });

  const socket = net.createConnection(port, "127.0.0.1");
  await once(socket, "connect");
  const bodyReceived = waitForChildMessage(
    child,
    ({ event }) => event === "body-received",
  );
  socket.write(
    "POST /v1/respond?disconnect=1 HTTP/1.1\r\n" +
      "Host: 127.0.0.1\r\n" +
      "Authorization: Bearer test-client-token\r\n" +
      "Content-Type: application/json\r\n" +
      "Content-Length: 100\r\n\r\n{",
  );
  await bodyReceived;
  const requestAborted = waitForChildMessage(
    child,
    ({ event }) => event === "request-aborted" || event === "request-error",
  );
  const socketClosed = once(socket, "close");
  socket.destroy();
  await Promise.all([socketClosed, requestAborted]);

  const valid = await fetch(`http://127.0.0.1:${port}/v1/respond`, {
    method: "POST",
    headers: {
      authorization: "Bearer test-client-token",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      request_id: "9efaf74f-7b86-4e02-af9a-bc24951cfb07",
      prompt: "hello",
    }),
  });
  assert.equal(valid.status, 200);

  const childExited = once(child, "exit");
  child.send("close");
  const [exitCode, exitSignal] = await childExited;
  assert.equal(exitCode, 0);
  assert.equal(exitSignal, null);
});
