# Security and privacy boundaries

MedCue handles medication and optional health context. The public repository is
organized so that source and reproducible checks are shareable while secrets,
private models, and user data remain local.

## Data boundaries

- Medication plans, dose history, inventory, and visit-summary inputs are local
  user-managed data.
- HealthKit and weather signals are optional context and are not interpreted as
  diagnosis or prescribing advice.
- OCR and barcode results require user review before persistence.
- Cloud AI is opt-in and receives only the context scopes authorized for that
  workflow.
- The assistant cannot create, stop, replace, or change medication or dosage.

## Public-repository rules

Do not commit or paste into Issues, pull requests, logs, screenshots, or test
fixtures:

- real medication, health, device, or account data;
- API keys, Bearer REDACTED_SECRET, client tokens, passwords, or private URLs;
- Apple certificates, private keys, provisioning profiles, or exported
  keychains;
- `AISecrets.plist`, `.env.local`, GGUF model files, local model frameworks,
  databases, or generated build products.

Use synthetic values and redacted paths in examples. The repository ignore rules
and native verification checks are defense in depth; they do not replace review
of the final diff and artifact.

## Change review

Changes that affect medication records, medical AI, consent, endpoint policy,
authorization, migrations, or system-surface dose actions require explicit
failure-path tests and fresh-context review before merge. A build passing is not
enough evidence for those changes.

## Reporting

Do not open a public Issue for an undisclosed credential or personal health
record. Preserve the evidence privately, rotate or revoke the affected
credential when appropriate, and coordinate disclosure with the repository
maintainer before publishing details.
