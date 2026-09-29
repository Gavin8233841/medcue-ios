# Issue #28: local-model install-to-response acceptance

## Evidence boundary and starting revision

Start from `main@9b6ea26075f7d0abfe50729f9bf4c04a400dcae5` or record a newer exact commit before testing. The 2026-09-27 attempted journey used an iPhone 17 Pro, iOS 26.5 **Simulator** build from `ed67bf82cb582f482b87454ffa9012d239764b99`. The product owner authorized Simulator substitution for this Issue's functional journey. It remains Simulator evidence, not physical-device, signing, account, or release evidence.

Use only a dedicated clean test installation and fictional, non-medication-specific input. Keep the GGUF, XCFramework, app container, device identifier, raw prompt and response, secrets, and health data outside GitHub and shared evidence. Record the source commit, platform and OS version, pass/fail for each step, and a redacted error category. Do not attach raw app logs or a screenshot containing private content.

## Prerequisites

1. Supply the optional `llama.xcframework` in the ignored `ios-app/MedicationAdherenceApp/Frameworks/` location. The repository's `tools/install-llama-xcframework.sh` names the official llama.cpp `b9596` XCFramework release. Verify the source archive against the publisher's release-asset digest before trusting the binary; a successful link alone does not establish provenance or inference behavior.
2. Build with the real llama runtime by setting `MEDCUE_ENABLE_LOCAL_LLAMA=1`. Ordinary builds use the stub, and CI explicitly sets `MEDCUE_DISABLE_LOCAL_LLAMA=1`; neither tests the runtime. Allow at least the model manifest's recommended 700 MB of free space in the test environment.
3. Keep the model file out of the source tree. `LocalAIModelManifest.miniCPM4` pins the upstream HTTPS source, exact byte count and SHA-256 digest. If a mirror is evaluated, it must serve those **same bytes** over HTTPS and support a complete download; do not weaken the installer check or change the selected model.
4. Ensure the test device or Simulator has a network path for the initial download and a separately controllable offline state for the later response. Do not use real medication records or enable cloud AI for this test.

## Functional journey

| Step | Observable pass condition |
| --- | --- |
| Clean launch | Assistant shows the device model as not installed; cloud mode is not silently enabled. |
| In-app download | The user confirms download; progress and expected total are visible; the app reports ready only after installation passes the pinned size and digest checks. |
| Relaunch | Terminate and relaunch the app without reinstalling it; the model remains ready without another download. |
| Explicit local choice | Select the device model and verify that the assistant indicates local mode before sending. |
| Offline guarded response | Make network access unavailable, then send one fictional, medically safe question. Confirm a local provider response with the product's medical safety guard and no cloud request. Record only outcome and redacted category, not the text. |
| Failure and retry | On a fresh synthetic installation, interrupt connectivity during download or use another controlled failure. Confirm failure is visible and no partial file is presented as ready; restore connectivity and retry to a verified ready state. |

The integrity unit tests cover invalid size/digest and rollback behavior, but they do not replace this installed-app journey. A Simulator pass does not establish physical-device memory, performance, backgrounding, or network behavior.

## 2026-09-27 result and next decision

The Simulator showed the download confirmation, progress, and a 265.3 MB total. Progress remained below 1 MB and the app changed to **model unavailable / retry download**. A separate 1 MB range request to the pinned upstream address received HTTP 206 but only 69 KB in about 41 seconds before timing out. This supports a slow or unreliable delivery path on the test network; it does not prove a general Hugging Face outage or a defect in the app's integrity check. See the redacted [Issue #28 checkpoint](https://github.com/Gavin8233841/medcue-ios/issues/28#issuecomment-5853320437).

| Boundary | Result |
| --- | --- |
| In-app entry and progress | PASS on Simulator |
| Download completion, installed-file integrity, relaunch persistence | NOT VERIFIED: initial download failed |
| Explicit local selection, offline guarded response | NOT VERIFIED in this journey |
| Failure visibility | PASS on Simulator |
| Successful retry | NOT VERIFIED |
| Official runtime archive digest and physical-device behavior | NOT VERIFIED |

**Competition claim: not yet demonstrated through the install-to-first-response journey.** First select and verify a reliable model distribution endpoint and its cost/ownership, then repeat this matrix from a clean installation. Keep token-loop cancellation in #6, performance in #8, broader device behavior in #17, and general source-package provenance in #5.
