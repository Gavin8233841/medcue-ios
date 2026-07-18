# Local Frameworks

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
