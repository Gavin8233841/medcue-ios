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
- Simplified Chinese source localization with an English String Catalog foundation.
- VoiceOver labels and stable accessibility identifiers for critical workflows.

## Architecture

The repository separates domain logic from Apple-platform integration:

- `swift-core/` contains pure Swift domain models, scheduling, adherence, trend, inventory, label, risk, and AI-safety logic.
- `ios-app/MedicationAdherenceApp/` contains the SwiftUI application, SwiftData persistence, app commands, system-service adapters, Watch app, Watch widget, and Live Activity extension.
- `Packages/LlamaFramework/` provides the local model runtime package boundary.
- `tools/` contains reproducible validation and release-safety checks.

Application writes use explicit command and transaction boundaries. SwiftData commits complete before user-visible success or post-commit side effects such as notifications, Watch snapshots, and Live Activity updates. Critical dose actions are idempotent across in-app and system-surface entry points.

## Privacy And Safety

- Medication data is stored locally with versioned SwiftData schemas and migration coverage.
- Cloud AI remains opt-in and receives only user-authorized context scopes.
- Credentials are not stored in source control and release artifacts are checked for sensitive configuration.
- Remote endpoints are HTTPS validated, redirects are restricted, and sessions use ephemeral storage.
- Local model files are integrity checked before use.
- AI output is finalized through medical-response boundaries before display or persistence.
- The assistant cannot create, stop, replace, or change medication or dosage.

## Requirements

- macOS with Xcode 26.5 or newer compatible with the project format
- iOS 17.0 or later
- watchOS target support for Watch features
- A personal or organization Apple Developer Team for physical-device signing

## Documentation

Start with the current product and engineering documents:

- [Product requirements](docs/PRD.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Test strategy](docs/TEST_STRATEGY.md)
- [Development workflow](docs/DEVELOPMENT_WORKFLOW.md)
- [Local iPhone signing](docs/IOS_SIGNING.md)
- [Security and privacy](docs/SECURITY_AND_PRIVACY.md)
- [Documentation map](docs/README.md)

Historical handoffs and dated investigation notes remain under `docs/` for
traceability. They are indexed and clearly marked in the [documentation map](docs/README.md)
so that they are not mistaken for current product or engineering truth.

## Build

Open:

`ios-app/MedicationAdherenceApp/MedicationAdherenceApp.xcodeproj`

Or build the unsigned Simulator configuration:

```zsh
xcodebuild \
  -project ios-app/MedicationAdherenceApp/MedicationAdherenceApp.xcodeproj \
  -scheme MedicationAdherenceApp \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  -jobs 1 \
  build
```

For a physical device, select the same development team for the main app and its extensions, then run the shared `MedicationAdherenceApp` scheme from Xcode.

## Test And Validate

Run the portable domain suite:

```zsh
cd swift-core
swift test
```

Run the complete native validation gate from the repository root:

```zsh
tools/verify-native.sh
```

The native gate covers domain tests, hosted persistence and application tests, unsigned Release builds, Watch builds, project preflight checks, and sensitive-artifact assertions.

## Repository Structure

```text
.
├── ios-app/
│   └── MedicationAdherenceApp/
├── Packages/
│   └── LlamaFramework/
├── docs/
│   ├── PRD.md
│   ├── ARCHITECTURE.md
│   ├── TEST_STRATEGY.md
│   ├── DEVELOPMENT_WORKFLOW.md
│   └── IOS_SIGNING.md
├── swift-core/
├── tools/
├── CONTRIBUTING.md
└── README.md
```

## Medical Disclaimer

MedCue is a medication organization and education tool. Its reminders, risk summaries, trends, imported text, and AI-generated content may be incomplete or incorrect. Users should verify medication decisions with qualified healthcare professionals and follow the prescription, label, and clinical guidance applicable to them.
