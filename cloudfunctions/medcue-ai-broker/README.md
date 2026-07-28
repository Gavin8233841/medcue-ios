# MedCue AI Broker

CloudBase HTTP function for the MedCue cloud-AI boundary. It is intentionally
limited to the current Doubao Responses upstream and does not act as a general
proxy.

## Runtime contract

- CloudBase runtime: `Nodejs18.15`
- Entry: `scf_bootstrap`, listening on port `9000`
- Route: `POST /v1/respond`
- Required request headers: `Authorization: REDACTED_SECRET <client-token>` and
  `Content-Type: application/json`
- Required JSON fields: `request_id` (canonical UUID) and `prompt` (1 to
  12000 characters)
- Maximum request body: 32768 bytes

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
It has an instance-local 30 requests/minute limit and a 20 second provider
timeout. Its completed-response cache is also instance-local; it reduces
retries for warm instances but is not cross-instance exactly-once delivery.

The static client token is a temporary competition/low-volume gate. It is not
equivalent to user identity or App Attest and must not be described as either.
