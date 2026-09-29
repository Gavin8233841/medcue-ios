# Local Frameworks

The app and Xcode project build without this optional framework. When it is absent,
the local inference adapter reports unavailable. Install it only for local-model
runtime validation; other MedCue features do not require it.

Place `llama.xcframework` in this directory after downloading or unpacking the official llama.cpp iOS XCFramework.

Preferred install commands from the repository root:

```bash
LLAMA_XCFRAMEWORK_ZIP=/path/to/llama-b9596-xcframework.zip tools/install-llama-xcframework.sh
```

or:

```bash
LLAMA_XCFRAMEWORK_DIR=/path/to/llama.xcframework tools/install-llama-xcframework.sh
```

Do not place partial downloads here. The app only treats `Frameworks/llama.xcframework` as an installable runtime artifact after the full framework directory exists.
