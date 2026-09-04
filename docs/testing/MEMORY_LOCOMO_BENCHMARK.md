# Memory LoCoMo Benchmark

GalaxySSI uses a LoCoMo-style corpus to evaluate long-term personal memory across distant
sessions. The benchmark drives the production Android query planner and prompt compiler. It is
not a keyword-only reference replay.

The versioned corpus covers:

- cross-session preference and identity retrieval;
- current, historical, planned, completed, corrected, and conflicted state;
- similar-project isolation;
- device capability memory;
- local-only privacy exclusion;
- unknown-fact abstention;
- long-horizon goal continuity;
- reusable tool evidence;
- conversation-only scope.

Run:

```bash
npm run benchmark:memory-locomo
```

The Android test writes raw query evidence to
`build/reports/memory-locomo/raw-results.json`. The benchmark evaluator writes the scored report
to `build/reports/memory-locomo/report.json`.

The report includes overall assertion accuracy, retrieval recall, contamination avoidance,
temporal accuracy, privacy accuracy, abstention accuracy, and per-category scores. Privacy leaks,
cross-project contamination, and conversation-scope leaks are critical failures even when the
weighted score remains above the threshold.

The corpus is stored in `benchmarks/memory/locomo-corpus.json`. Add a new timeline when a product
memory contract changes. Do not weaken an existing expectation to accommodate a retrieval
regression.
