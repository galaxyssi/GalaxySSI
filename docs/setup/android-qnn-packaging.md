# Android QNN Packaging

GalaxySSI packages the Qualcomm QNN/HTP runtime inside the Android APK so local
Whisper QNN inference does not depend on a separately installed user library.
The runtime must come from the official Maven Central artifacts during the
Gradle build. Do not copy Qualcomm `.so` files or the QNN AAR into the public
source repository.

## Pinned artifacts

The supported combination is declared in `apps/android/app/build.gradle.kts`:

| Component | Maven coordinate | Version |
| --- | --- | --- |
| QNN runtime | `com.qualcomm.qti:qnn-runtime` | `2.47.0` |
| QNN LiteRT delegate | `com.qualcomm.qti:qnn-litert-delegate` | `2.47.0` |
| ONNX Runtime QNN | `com.qualcomm.qti:onnxruntime-android-qnn` | `2.3.0` |

This version pairing is intentional. ONNX Runtime QNN 2.3.0 requires QNN Core
API 2.36.0. QNN runtime 2.45.0 exposes Core API 2.34.0 and fails interface
discovery. QNN runtime 2.47.0 exposes Core API 2.36.0 and loads the HTP v81
backend used by the target S26 Ultra. Model contexts generated with QAIRT 2.45
remain accepted because the runtime is newer within the same major release.

## License boundary

The QNN AAR contains the Qualcomm AI Stack License. It permits object-code
distribution when the runtime is incorporated into an application, but it does
not permit standalone redistribution of the runtime. Therefore:

- The APK may contain the QNN libraries.
- The repository may contain Maven coordinates, build logic, tests, and notices.
- The public repository must not contain standalone QNN `.so` files or a copied
  `qnn-runtime` AAR.
- Release artifacts must preserve Qualcomm and third-party notices supplied by
  the official dependency.

## Required APK contents

`npm run check:android:qnn-package` verifies the dependency versions and all 24
required arm64 libraries, including the ONNX Runtime JNI layer, QNN provider,
QNN system/backend libraries, and HTP stub/skel pairs for v68, v69, v73, v75,
v79, and v81. `npm run check:android` invokes this gate automatically after the
APK is assembled.

The current debug APK snapshot has the following native footprint:

| Package scope | Files | Uncompressed | Compressed in APK |
| --- | ---: | ---: | ---: |
| QNN-specific runtime and provider | 22 | 196.94 MiB | 71.47 MiB |
| QNN plus base ONNX Runtime JNI | 24 | 221.68 MiB | about 81.24 MiB |
| S26 Ultra v81 minimum execution subset | 5 | 28.55 MiB | 9.17 MiB |

The complete multi-generation set is retained for device compatibility. Do not
remove apparently unused HTP generations merely to reduce one local build.

## Build and verification

From the repository root:

```text
npm run check:android
```

For an already assembled APK:

```text
npm run check:android:qnn-package
node tools/dev/check-android-qnn-package.js path/to/app.apk
```

The gate fails when a pinned dependency changes unexpectedly, a required native
library is absent from the APK, or a standalone QNN binary is copied into a
source vendor directory. This makes QNN packaging part of every new branch and
pull request rather than a manual release reminder.

The archived WhisperKit Android 0.3.3 dependency also contains eight legacy
open-source native libraries linked for 4 KB pages. GalaxySSI deterministically
normalizes those merged ELF files to 16 KB before APK signing. The strict
`check:android:16kb` gate has no compatibility whitelist: every packaged
AArch64 library must pass both ELF LOAD alignment and APK ZIP alignment.
