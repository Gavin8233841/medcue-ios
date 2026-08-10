# Local iPhone signing

This document covers local Xcode development on a registered physical iPhone.
It does not configure App Store, TestFlight, distribution certificates, or
GitHub Actions signing.

## Repository signing configuration

The project currently uses Xcode automatic signing in both Debug and Release
settings. The source-checked values are:

| Target | Bundle identifier | Signing notes |
| --- | --- | --- |
| `MedicationAdherenceApp` | `com.gwyy.appcontest2026.medicationadherence` | Main iPhone app; HealthKit and Watch App Group entitlements |
| `MedicationReminderLiveActivityExtension` | `com.gwyy.appcontest2026.medicationadherence.MedicationReminderLiveActivityExtension` | Embedded iPhone extension |
| `MedicationAdherenceWatchApp` | `com.gwyy.appcontest2026.medicationadherence.watchkitapp` | Embedded Watch app |
| `MedicationAdherenceWatchWidget` | `com.gwyy.appcontest2026.medicationadherence.watchkitapp.MedicationAdherenceWatchWidget` | Watch complication/widget extension |
| `MedicationAdherenceAppTests` | `com.gwyy.appcontest2026.MedicationAdherenceAppTests` | iOS unit-test host target |
| `MedicationAdherenceAppUITests` | `com.gwyy.appcontest2026.MedicationAdherenceAppUITests` | iOS UI-test target |

The project declares development Team ID `M74Y4RX827` for these targets. If a
different Apple Developer Team must be used, update the project in Xcode and
review every target and App Group together; do not change one Bundle ID or
entitlement in isolation.

## One-time Xcode setup

1. In Xcode, open **Settings > Accounts** and add the Apple Account that has
   access to the development team.
2. Open `ios-app/MedicationAdherenceApp/MedicationAdherenceApp.xcodeproj`.
3. Select the project in the Project navigator and select each target listed
   above.
4. In **Signing & Capabilities**, keep **Automatically manage signing** on and
   select the same Team for the main app and all embedded targets.
5. Connect an unlocked physical iPhone, accept **Trust This Computer** if
   prompted, and select the shared `MedicationAdherenceApp` scheme.
6. Select the iPhone as the run destination and build/run from Xcode.
7. If the device asks for developer trust, finish the device trust step in
   **Settings > General > VPN & Device Management**, then run again.

Apple documents that automatic signing lets Xcode manage development
provisioning profiles, and that adding an Apple Account and assigning the
project to a team are prerequisites for device development:

- [Create a development provisioning profile](https://developer.apple.com/help/account/provisioning-profiles/create-a-development-provisioning-profile)
- [Adding capabilities to your app](https://developer.apple.com/documentation/xcode/adding-capabilities-to-your-app)
- [Certificates overview](https://developer.apple.com/help/account/create-certificates/certificates-overview)

## Safe verification

The following command lists local code-signing identities without reading or
printing private keys:

```zsh
security find-identity -v -p codesigning
```

For a source-only check, the unsigned native gate remains the reproducible
public-repository path:

```zsh
MEDCUE_DISABLE_LOCAL_LLAMA=1 tools/verify-native.sh
```

The unsigned gate does not prove physical-device signing. Physical acceptance
must be recorded separately with the exact Xcode version, device, OS, target,
and result.

## What must never be committed

- `.p12`, `.cer`, `.mobileprovision`, `.provisionprofile`, private keys, or
  exported signing identities;
- Apple Account passwords, authentication tokens, or API keys;
- `AISecrets.plist`, `.env.local`, GGUF files, local model frameworks, user
  databases, or health records.

If signing fails, inspect the Xcode signing report, Team assignment, target
Bundle IDs, capabilities, device registration, and device trust state. Do not
solve a local signing failure by committing a certificate or provisioning
profile to this public repository.
