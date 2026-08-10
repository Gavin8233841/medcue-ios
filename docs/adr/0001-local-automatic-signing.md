# ADR 0001: Use Xcode automatic signing for local device development

- Status: Accepted
- Date: 2026-08-10
- Scope: Local iPhone and Apple Watch development only

## Decision

Keep the Xcode project on automatic signing for the main app, Live Activity
extension, Watch app, Watch Widget, and test targets. Use the development Team
declared by the project and let Xcode manage development provisioning for the
registered physical device.

## Why

- It matches the current development goal: local physical-device validation,
  not product distribution.
- It avoids putting certificates, private keys, or provisioning profiles in a
  public repository.
- It keeps the same Team, Bundle ID, capability, and App Group relationship
  visible in the project for review.
- It allows Xcode to refresh development provisioning when device or capability
  state changes.

## Consequences

- A developer must sign into Xcode with an Apple Account that can use the
  configured Team and must trust/register the physical device.
- A local certificate and device/account state are required for signed runs;
  the public unsigned verification gate remains separate.
- Distribution certificates, App Store Connect, TestFlight, and CI signing are
  intentionally not configured by this decision.

## Revisit trigger

Revisit this ADR only when the product owner explicitly expands scope to
distribution, TestFlight, App Store, or a shared CI signing workflow. That
change requires a separate security review and an approved secret-management
plan.
