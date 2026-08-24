# Third-Party Notices

This source-only package does not redistribute third-party binaries, runtime
installations, fonts, media, or model files. The entries below document the
external boundaries that are referenced by the exact source tree.

## llama.cpp

MedCue can optionally link the llama.cpp iOS XCFramework. The repository does
not track that binary; `tools/install-llama-xcframework.sh` identifies the
upstream release tag and downloads it only when a maintainer explicitly
provides the artifact. The package manifest records this as an excluded,
optional runtime and does not present it as packaged or device-verified.

- Source: <https://github.com/ggml-org/llama.cpp>
- Release source used by the installer: `LLAMA_CPP_RELEASE_TAG` (default `b9596`)
- License: MIT, as published by the upstream project
- Attribution: retain the upstream project notice when the optional binary is
  separately redistributed; it is not part of this source-only package

## Node.js

The Broker declares a Node.js `>=18` runtime in its `package.json`. Node.js is a
deployment runtime and is not copied into this package. No third-party npm
dependencies are declared by the Broker package at the exact source revision.

## First-Party Source And Apple SDKs

MedCue source, SwiftPM modules, tests, icons, and documentation are first-party
repository content. Swift, SwiftPM, Xcode, and Apple SDKs are build-time
toolchains and are not redistributed in this source package; their device and
account obligations remain separate release evidence.
