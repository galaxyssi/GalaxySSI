# Version Health Score

GalaxySSI evaluates each candidate version across six product dimensions:

- performance;
- reliability;
- security;
- UX;
- memory quality;
- automation success rate.

The score is evidence-driven. Each metric carries a normalized score, measurement time, source, and
sample size. Required evidence that is missing or older than the policy freshness window contributes
zero and blocks its dimension. Future-dated evidence and undeclared metrics are rejected.

## Deterministic Contract

Run the scorer tests and reference fixture:

```bash
npm run test:version-health
npm run score:version-health
```

The reference fixture proves scoring behavior only. It is explicitly marked as a fixture and must
not be presented as the health of a release.

## Release Evidence

Collect real reports from the candidate commit, convert them into the evidence contract, and run:

```bash
npm run score:version-health -- --evidence C:\path\to\version-evidence.json --strict-live
```

`--strict-live` rejects fixture evidence. The generated report is written to
`build/reports/version-health/report.json` and includes:

- the weighted overall score and grade;
- each dimension score and minimum;
- current, stale, and missing metric evidence;
- blocking failures;
- an SHA-256 digest of the complete evidence set.

To compare a candidate with a previous version:

```bash
npm run score:version-health -- --evidence C:\path\to\current.json --previous-evidence C:\path\to\previous.json --strict-live
```

The comparison reports overall and per-dimension deltas. Security and reliability are critical
dimensions, but every dimension must meet its own minimum before a version is healthy.
