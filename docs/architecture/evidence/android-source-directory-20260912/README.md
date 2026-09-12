# Android source directory evidence

Device: SM-T575 only. Android: 1.1.94 (980). Sources are isolated synthetic
Chinese fixtures encrypted by the application's actual storage implementation.
No user database, source text or model configuration is exported.

## Scope

- `summary.json`: initial schema-7 opening, background migration, all 201 pages
  of the retained 10,001-source corpus, and reopen at page 100.
- `pages-ms.csv`: each actual authenticated source page (maximum 50 groups).
- `profile-ms.csv`: five separate passes on 50 retained sources for SQL seek,
  header AEAD, identity HMAC, authenticated summaries and the complete page.
  Stages are independently measured, not additive parent/child spans.
- `device-tests.csv`: the 128 completed shared instrumentation cases, extracted
  from the runner status protocol. All passed; none were skipped.

The scale test passed, preserving the header/chunk ciphertext fingerprint
`95b4ea281213622780074760c1fa15afccce5ded8c1594ea55c76b7c7718eb1e`.
This fingerprint is not an APK hash or a plaintext corpus digest.

The initial scale test used application SHA-256
`586b806f0e293cc9286744911166fb1a0c8915fe2003570ae6901b91356d5fce`.
The subsequent resource-only locale-directory correction produced application
SHA-256 `edb3fbe3ec8a50cff64b7d8c27c82b82ebdf136fa299943d9ef0a4bdabf410c8`.
Production Kotlin and SQL are identical between these APKs. The corrected APK
was installed before the component profile and process-death verification.

The profile/shared-regression test APK SHA-256 is
`cbe859de02a27337162b58177f0a07f8cb48d02e3b0a3b22deec5f1b77b9165c`.
The full build passed. JVM results were 3,751 tests, zero failures/errors and
five existing skips across 537 suites. All 74 native libraries passed 16 KB
alignment checks. Repository checks passed. All 128 shared device regressions
passed in 850.389 s, without failures or skips.

Additional isolated tests passed for the retained corpus (147.964 s), component
profiling (11.075 s), and verification after intentional process death (2.177 s).
The process-termination setup intentionally does not report a normal test pass;
a separate invocation proves the next PID resumes the committed checkpoint.
Recovery cleanup passed in 0.110 s and did not remove the retained scale corpus.

Sample SHA-256 values:

- `pages-ms.csv`: `4dcb7662188d8ce293427dd566773394bb3420adc1d8e4525fc18eca28fe58f0`
- `profile-ms.csv`: `1490c552c68c69dc3df5b5f661da80b696ff94e0f9f8b83c227a857a9b0cdcf3`
- `summary.json`: `ba8bf6ca6091029ab5bcf3ec92c11f28fac8a2e9ec9f0891c9f0123a75f217bf`

## What this does not prove

- P95 below 200 ms for authenticated pages: observed P95 was 916.665 ms.
- 100M retained source capacity, physical reboot recovery or UI frame latency.
- Vector recall or model latency at 10,001 sources: no model was configured by
  the scale test.
- A bounded overall Java/native heap peak: this test verifies bounded pages,
  not a continuous process-memory trace.
