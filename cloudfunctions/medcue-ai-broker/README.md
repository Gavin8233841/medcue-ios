# MedCue AI Broker

CloudBase HTTP function for the MedCue cloud-AI boundary. It is intentionally
limited to the current Doubao Responses upstream and does not act as a general
proxy.

## Runtime contract

- CloudBase runtime: `Nodejs18.15`
- Entry: `scf_bootstrap`, listening on port `9000`
- Route: `POST /v1/respond`
- Required request headers: `Authorization: Bearer <client-token>` and
  `Content-Type: application/json`
- Required JSON body: a non-null object with `request_id` (canonical UUID) and
  `prompt` (1 to 12000 characters)
- Maximum request body: 32768 bytes
- Malformed URLs and unexpected request-processing failures return generic JSON
  errors; disconnected clients are terminated safely.

The function uses these environment variables:

- `MEDCUE_BROKER_CLIENT_TOKEN`
- `ARK_API_KEY`
- `ARK_MODEL`

Set their values in CloudBase function configuration. Do not place values in
source control, iOS configuration, test fixtures, or logs.

## Local verification

```bash
node --test
```

## Operational limits

The broker denies arbitrary upstream URLs, providers, and model identifiers.
It refuses to start when any required security configuration is missing or
empty. Provider requests never follow redirects, have a 20 second timeout that
covers both the request and response-body read, and stream at most 65536 actual
response bytes before JSON decoding. The byte cap does not trust
`Content-Length`.

The broker also has an instance-local 30 requests/minute limit. Concurrent
requests on one warm instance that use the same `request_id` and prompt share
one provider operation; reuse of that ID with another prompt returns a conflict.
The in-flight table and completed-response cache each use the configured
idempotency-cache capacity. New distinct work is rejected while the in-flight
table is full instead of evicting an active operation.

Provider work is governed by the broker timeout rather than an individual HTTP
client connection. A disconnected waiter therefore does not cancel provider
work that another matching waiter still needs. In-flight entries are removed
after success, failure, or timeout so later retries can proceed.

Both idempotency stores are instance-local. They reduce duplicate work for warm
instances but do not provide cross-instance exactly-once delivery.

The static client token is a temporary competition/low-volume gate. It is not
equivalent to user identity or App Attest and must not be described as either.
