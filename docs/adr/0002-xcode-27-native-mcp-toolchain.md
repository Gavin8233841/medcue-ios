# ADR-0002: Adopt The Xcode 27 Native MCP Toolchain And Retire XcodeBuildMCP

- Status: Accepted
- Date: 2026-08-23
- Decision owner: MedCue product owner
- Related: [Issue #45](https://github.com/Gavin8233841/medcue-ios/issues/45),
  `docs/FINALS_PRODUCT_PLAN.md`

## Context

MedCue's iOS build, run, and simulator-interaction work previously relied on a
third-party Xcode MCP integration (XcodeBuildMCP, also surfaced as "Build iOS
Apps"). Historical recovery documents `docs/19-codex-plugin-restore-prompt.md`
and `docs/20-codex-full-skill-plugin-recovery.md` describe installing and
restoring that plugin; those documents are retained as historical evidence only
and no longer describe the current toolchain.

Xcode 27 ships a native MCP service covering build, run, and simulator
interaction, which removes the need for a third-party bridge. The local
toolchain was verified on 2026-08-23: `/Applications/Xcode.app` reports
`CFBundleShortVersionString` `27.0` and `ProductBuildVersion` `27A5237l`
(Xcode 27 Beta 5).

## Decision

1. The standard local toolchain is `/Applications/Xcode.app`, Xcode 27 Beta 5,
   Build `27A5237l`.
2. Agent build/run/simulator interactions use the Xcode 27 native MCP service.
3. The legacy third-party XcodeBuildMCP (and equivalent third-party Xcode MCP
   bridges) is retired: do not install, restore, or document it as current.
4. Historical documents mentioning the old plugin remain tracked as audit
   context and must not be cited as the current setup.

## Consequences

- One less third-party dependency in the trusted local build path; toolchain
  behavior follows Apple's shipped tooling.
- Onboarding and recovery instructions must point at the native MCP service;
  stale restore prompts for the old plugin are superseded by this ADR.
- CI evidence remains the merge gate; the local MCP choice does not change
  `tools/verify-native.sh` or the Native Verification workflow.

## Rejected Alternatives

- Keep XcodeBuildMCP alongside the native service: duplicate control of the
  same build path with divergent behavior and extra supply-chain surface.
- Pin an older Xcode for plugin compatibility: blocks platform SDK and
  simulator improvements required by current iOS targets.
