# MedCue test strategy

The test strategy maps product risk to observable evidence. A successful build
alone is not evidence that medication ordering, privacy, device behavior, or
system-surface actions are correct.

## Verification layers

| Layer | Command or procedure | Evidence |
| --- | --- | --- |
| Domain rules | `cd swift-core && swift test` | Scheduling, adherence, dose history, trends, labels, risk, and AI-safety behavior |
| Broker | `cd cloudfunctions/medcue-ai-broker && node --test` | Request validation, allowlist, timeout, cache, and failure behavior |
| iOS hosted tests | `tools/verify-native.sh` | SwiftData, command, persistence, and application integration behavior |
| UI smoke | Native verification gate plus the current UI test target | Launch, primary navigation, and first-use behavior on the configured simulator |
| Native build | `tools/verify-native.sh` | Unsigned iOS Release and Watch builds without private signing assets |
| Artifact safety | Native verification and repository scans | No credentials, user databases, local model files, or sensitive generated products |
| Physical device | [Local signing and device checklist](IOS_SIGNING.md) and [device scenarios](13-iphone-signing-and-live-activity-test.md) | Real certificate, entitlements, install, permissions, notifications, Watch, and Live Activity behavior |

## Required behavior coverage

Tests for a feature should cover the successful path plus invalid input,
failure, cancellation, ordering, duplicate delivery, and rollback behavior when
those states are possible. For persisted medication actions, verify both:

- the durable commit and the resulting record;
- the absence of success UI or post-commit side effects when the commit fails.

For system-surface actions, verify that the logical dose identity is stable and
that repeated delivery is idempotent. For AI and import workflows, verify
consent boundaries, scope selection, transport failures, malformed responses,
and safe display behavior without real health data or credentials.

## Evidence rules

- Record the exact revision, command, environment, and result in the pull
  request.
- Use synthetic medication and health examples in fixtures, screenshots, and
  issue reports.
- Treat simulator output as simulator evidence; do not call it physical-device
  acceptance.
- Keep pending account, capability, or device checks explicit. Do not infer
  them from source configuration alone.
