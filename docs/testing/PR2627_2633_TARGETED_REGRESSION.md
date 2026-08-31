# PR 2627-2633 Targeted Android Regression

This regression suite validates the Android web-intelligence, evidence, privacy, pairing, and
model-tool changes introduced by PR #2627 through PR #2633. It contains exactly 1,000 traceable
independently addressable risk scenarios. The catalog is a risk matrix, not one assertion repeated
with different labels:

- 1,000 unique risk IDs, conversation IDs, Chinese test descriptions, steps, and expected results.
- 50 production behavior families, each backed by a real production-code oracle.
- 20 non-equivalent state, input, failure, timeout, cancellation, redirect, boundary, privacy,
  restart, and concurrency conditions in every behavior family.
- 7 pull requests, at least 20 behavior categories, and at least 15 executable oracle families.
- A unique case ID, title, risk statement, precondition, action, expected result, and result record
  for every case.

## Coverage

| Pull request | Cases | Main risks |
| --- | ---: | --- |
| #2627 | 160 | Parallel page reads, host fairness, deadlines, cancellation, deduplication, partial failure |
| #2628 | 100 | Pairing identity, replay deduplication, route isolation, durable system notices |
| #2629 | 160 | URL extraction, follow-up context, cache expiry, singleflight, redirect aliases |
| #2630 | 140 | Evidence integrity, correlation, conflicts, canonical URLs, bounded model context |
| #2631 | 140 | WeChat headers and parsing, generic articles, dynamic fallback, renderer isolation |
| #2632 | 160 | Cognition scheduling, bounded cycles, secret blocking, metadata and transcript redaction |
| #2633 | 140 | Semantic tool selection, DSML parsing, citation verification, bounded repair |

The 20 profiles include cold and warm state, duplicate and reordered input, isolated and partial
failure, early and late timeout, cancellation before and during work, offline behavior, same-host
and cross-host redirects, Unicode and percent-encoded content, missing optional fields, maximum
bounds, untrusted instructions, process restart, and concurrent callers.

## Catalog Check

Generate the 50 small suite assets and validate all 1,000 scenario identities, Chinese test
specifications, traceability, and coverage:

```powershell
node tools/benchmark/generate-pr2627-2633-regression.mjs
npm run test:android:web-regression-corpus
```

Generated assets live under
`apps/android/app/src/androidTest/assets/pr2627-pr2633-targeted-regression`. Each suite is a
separate JSON file so individual risks remain reviewable and files stay below the repository's
preferred source-size range.

## SM-G9880 Device Run

```powershell
npm run test:android:web-regression:sm-g9880 -- --serial R5CN319CESA
```

The runner refuses every device whose reported model is not exactly `SM-G9880`. It builds and
installs the App with `adb install -r`, installs the instrumentation APK, executes all 1,000
oracles, copies the detailed report to
`build/reports/pr2627-pr2633/sm-g9880.json`, and removes only the test package. It does not use
Gradle's connected-device cleanup and therefore does not uninstall the target App or clear its
data.

Every run also creates or updates exactly 1,000 visible App conversations. Each conversation has
two encrypted messages: the Chinese risk specification and the measured execution result. The
test records use deterministic IDs, so rerunning the suite updates them instead of creating
duplicates. Existing user conversations are preserved. Test conversations are private and have
tracking disabled, so they cannot enter global learning or external routing.

Use `--skip-build` only when both APKs were built from the current checkout. A successful run must
report exactly 1,000 cases, 1,000 passed, 0 failed, and 1,000 persisted visible conversations.
Each report record includes its risk ID, conversation ID, Chinese title, pull request, production
oracle, condition profile, duration, persistence result, and failure evidence.
