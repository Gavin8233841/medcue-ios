# MedCue model delivery pilot

This Cloudflare Worker serves the pinned MiniCPM4 GGUF from the private
`medcue-model-pilot` R2 bucket to a small competition test group. It does not
receive medication records or prompts. The app's final byte-count and SHA-256
check remains authoritative; the Worker checks the object size before serving.

The endpoint accepts only `GET` or `HEAD` at `/v1/model/minicpm4-0.5b` with
`Authorization: Bearer <32 lowercase hex characters>`. The code is a Worker
secret named `DOWNLOAD_TOKEN`. Never put it in Git, a URL, a build setting, or
an app package. A tester pastes it into the app once for the download; the app
keeps it in memory only. This is a shared demo gate, not user identity or a
commercial abuse-control system. Rotate the Worker secret if it leaks.

The R2 bucket's public access and r2.dev address remain disabled. The Worker
uses only the single pinned key and supports byte ranges for download clients.
Its rate-limiting binding allows six authorized requests per minute per client
IP per Cloudflare location; this is a local throttle, not a global byte quota.
Cloudflare still receives the connection metadata and the access code in the
HTTPS request header. The Worker does not log the code.

## Local checks

```sh
node --test
npx wrangler deploy --dry-run
```

## Deployment and rollback

Create the Worker under the intended Cloudflare account and bind
`MODEL_BUCKET` to `medcue-model-pilot` and `DOWNLOAD_LIMITER` as declared in
`wrangler.jsonc`. Create `DOWNLOAD_TOKEN` as an encrypted Worker secret using
a newly generated 32-character lowercase hexadecimal code. Deploy the source
only after checking these bindings and the Free plan. Verify a request without
the code returns no model, then test `HEAD` and two small ranged `GET` requests
with the code. Avoid a full model transfer until the planned app acceptance
run. To stop distribution, disable the Worker route; the original model source
remains available in the app's standard download option.

The Worker is limited to the competition pilot. A publicly distributed app
would need a stronger issuance and abuse-control design before using this
endpoint as the default model source.
