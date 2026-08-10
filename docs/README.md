# MedCue documentation

This directory separates current product and engineering truth from dated
handoffs and investigation notes. When documents disagree, use source code,
tests, committed project settings, and exact verification evidence to describe
what the repository actually does.

## Start here

| Document | Owner and purpose |
| --- | --- |
| [PRD](PRD.md) | Product goal, users, scope, non-goals, and observable requirements |
| [Architecture](ARCHITECTURE.md) | Module boundaries, state ownership, data flow, and trust boundaries |
| [Test strategy](TEST_STRATEGY.md) | Risk-to-evidence mapping and required validation layers |
| [Development workflow](DEVELOPMENT_WORKFLOW.md) | Issue, branch, pull request, review, and completion rules |
| [Local iPhone signing](IOS_SIGNING.md) | Xcode automatic signing for local physical-device development |
| [Security and privacy](SECURITY_AND_PRIVACY.md) | Public-repository rules for medication data, credentials, and AI context |

## Operational references

- [iPhone and Live Activity device checklist](13-iphone-signing-and-live-activity-test.md)
- [Cloud AI Broker README](../cloudfunctions/medcue-ai-broker/README.md)
- [Watch support notes](watchos-support/README.md)
- [Architecture hardening audit](24-privacy-data-flow-audit-20260727.md)
- [Token Broker deployment prerequisites](25-token-broker-deployment-prerequisites-20260727.md)

The operational references describe concrete procedures or evidence. Recheck
their commands and status against the current source before treating them as a
release decision.

## Historical material

The numbered documents and dated handoffs are retained for context and audit.
They may describe an earlier UI, test result, environment, or product decision.
They are not an active backlog. New requirements belong in GitHub Issues; new
durable technical decisions belong in `docs/adr/`; verification evidence belongs
in the pull request for the exact revision.
