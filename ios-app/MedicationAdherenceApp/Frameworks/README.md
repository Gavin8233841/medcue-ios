# Local Frameworks

The app and Xcode project use the unavailable local-inference stub by default,
whether or not this optional framework is present. Install it only for
local-model runtime validation, then set `MEDCUE_ENABLE_LOCAL_LLAMA=1` when
building; other MedCue features do not require it.

Place `llama.xcframework` in this directory after downloading or unpacking the official llama.cpp iOS XCFramework.

Preferred install commands from the repository root:

```bash
LLAMA_XCFRAMEWORK_ZIP=/path/to/llama-b9596-xcframework.zip tools/install-llama-xcframework.sh
```

or:

```bash
LLAMA_XCFRAMEWORK_DIR=/path/to/llama.xcframework tools/install-llama-xcframework.sh
```

Do not place partial downloads here. An explicit local-model build needs the
complete framework; an ordinary build does not inspect or link it.
