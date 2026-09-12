# Native record sharding evidence

- Device: Samsung SM-T575, serial R52R90282TY only.
- Source base: `b0d5f6dff` (merged streaming projection PR #3022).
- Android: 1.1.99 / 985; native memory: 0.6.0; Desktop unchanged.
- Native SQLite: 37 passed, zero failed, one child-process helper ignored at
  top level; 43.80s. The suite actually spawns the helper for recovery tests.
- Initial App JNI/index/admission suite: 15 passed; 31.464s.
- Final App suite including ready-graph maintenance/reopen: 16 passed; 51.985s.
- JVM: 3,779 tests across 541 suites; zero failures/errors, five existing skips.
- Full debug build and instrumentation packaging succeeded in 13m20s.
- Repository guard passed; Android 16KiB audit passed for 74 ARM64 libraries.

`native-sqlite.txt`, `app-jni-regressions.txt` and `app-final-regressions.txt` are raw runner output from
isolated synthetic fixtures. They contain no production messages or memory
payloads. Evidence does not establish 100M capacity, a per-operation latency
guarantee, total memory peaks or whole-goal completion.
