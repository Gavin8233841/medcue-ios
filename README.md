# MedCue

MedCue is a native medication-management app for iPhone and Apple Watch. It helps people organize medication plans, record dose events, review adherence trends, monitor supply, and prepare concise information for follow-up visits.

MedCue supports medication safety and routine management. It does not diagnose conditions, prescribe medication, or replace a clinician or pharmacist.

## Highlights

- A focused Today timeline for recording taken, delayed, skipped, corrected, and reopened doses.
- Medication profiles with treatment periods, dose changes, multiple reminder times, package photos, and inventory estimates.
- Records, calendar review, adherence trends, risk review, and visit-summary export.
- Apple Watch, complications, notifications, and Live Activities backed by the iPhone as the primary source of truth.
- Optional HealthKit signals presented as contextual trends without diagnostic interpretation.
- Local OCR and barcode-assisted import with mandatory user review before persistence.
- Cloud and on-device medical-assistant modes with explicit consent, scoped context sharing, transport validation, and response safety boundaries.
- Simplified Chinese source localization backed by a project-wide String Catalog.
- VoiceOver labels and stable accessibility identifiers on selected navigation
  and editor controls.

## Architecture

The repository separates domain logic from Apple-platform integration:

- `swift-core/` contains pure Swift domain models, scheduling, adherence, trend, inventory, label, risk, and AI-safety logic.
- `ios-app/MedicationAdherenceApp/` contains the SwiftUI application, SwiftData persistence, app commands, system-service adapters, Watch app, Watch widget, and Live Activity extension.
- `Packages/LlamaFramework/` provides the local model runtime package boundary.
- `tools/` contains reproducible validation and release-safety checks.

Application writes use explicit command and transaction boundaries. SwiftData commits complete before user-visible success or post-commit side effects such as notifications, Watch snapshots, and Live Activity updates. Critical dose actions are designed to be idempotent across in-app and system-surface entry points; the current Live Activity URL entry point has a documented authorization and idempotency gap tracked in [GitHub Issue #2](https://github.com/Gavin8233841/medcue-ios/issues/2) and is not release-ready.

## Privacy And Safety

- Medication data is stored locally with versioned SwiftData schemas and migration coverage.
- Cloud AI remains opt-in and receives only user-authorized context scopes.
- Credentials are not stored in source control and release artifacts are checked for sensitive configuration.
- iOS remote endpoints are HTTPS validated, client-side redirects are rejected,
  and sessions use ephemeral storage.
- Local model files are integrity checked before use.
- AI output is finalized through medical-response boundaries before display or persistence.
- The assistant cannot create, stop, replace, or change medication or dosage.

## Requirements

- macOS with Xcode 26.5 or newer compatible with the project format
- iOS 17.0 or later
- watchOS target support for Watch features
- A personal or organization Apple Developer Team for physical-device signing

## Build

Open:

`ios-app/MedicationAdherenceApp/MedicationAdherenceApp.xcodeproj`

The source repository intentionally omits the local llama binary. For a clean
clone, build the rest of the product against the CI stub:

```zsh
MEDCUE_DISABLE_LOCAL_LLAMA=1 xcodebuild \
  -project ios-app/MedicationAdherenceApp/MedicationAdherenceApp.xcodeproj \
  -scheme MedicationAdherenceApp \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  -jobs 1 \
  build
```

To link the real on-device model runtime, first provide a local
`llama.xcframework` described in
[`ios-app/MedicationAdherenceApp/Frameworks/README.md`](ios-app/MedicationAdherenceApp/Frameworks/README.md),
then build without `MEDCUE_DISABLE_LOCAL_LLAMA`. The stub path verifies the rest
of the source and integration boundary; it does not verify the real llama binary
or on-device inference. Repository automation does not yet verify the binary's
source or digest, so those checks must be completed separately before treating
the framework as trusted.

For a physical device, select the same development team for the main app and its extensions, then run the shared `MedicationAdherenceApp` scheme from Xcode.

## Test And Validate

Run the portable domain suite:

```zsh
cd swift-core
swift test
```

Run the complete native validation gate from a clean source clone without the
local binary:

```zsh
MEDCUE_DISABLE_LOCAL_LLAMA=1 tools/verify-native.sh
```

The native gate covers domain tests, hosted persistence and application tests, primary-navigation and first-launch UI smoke tests, unsigned Release builds, Watch builds, project preflight checks, and sensitive-artifact assertions.

With a locally supplied XCFramework installed, omit
`MEDCUE_DISABLE_LOCAL_LLAMA` to link it during the gate. Real inference
additionally requires the ignored GGUF model and the explicit smoke procedure;
neither the CI stub nor a successful link build proves real-model behavior.

## Repository Structure

```text
.
├── .github/
├── cloudfunctions/
├── docs/
├── ios-app/
│   └── MedicationAdherenceApp/
├── Packages/
│   └── LlamaFramework/
├── swift-core/
├── tools/
├── AGENTS.md
├── CONTEXT.md
└── README.md
```

## Development Governance

Development uses an Issue -> branch -> Pull Request -> CI workflow. Start with
`AGENTS.md`, `CONTEXT.md`, `docs/PROJECT_STATUS.md`, and
`docs/DEVELOPMENT_WORKFLOW.md`. `docs/README.md` indexes current architecture,
test, operational, and historical material. Historical append-only logs are
retained for audit but are not the active backlog.

## Medical Disclaimer

MedCue is a medication organization and education tool. Its reminders, risk summaries, trends, imported text, and AI-generated content may be incomplete or incorrect. Users should verify medication decisions with qualified healthcare professionals and follow the prescription, label, and clinical guidance applicable to them.
