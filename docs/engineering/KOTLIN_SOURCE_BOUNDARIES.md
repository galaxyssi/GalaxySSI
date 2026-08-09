# Kotlin Source Boundaries

Android source files should remain small enough to review, compile, and change safely.

## Policy

- New Kotlin source files must stay below 96 KiB.
- Prefer one responsibility per file and split feature code before it reaches the limit.
- Activity classes retain lifecycle, view ownership, and state. Feature behavior belongs in same-package extension modules.
- Runtime classes retain state and orchestration. Planning, execution, safety, persistence, and model types belong in focused modules.
- Same-package extension functions are used for the current decomposition so calls remain static and no forwarding object is added to hot paths.
- Existing oversized files are capped at their current size and cannot grow. They should be reduced in later focused refactors.

Run the guard with:

```bash
npm run check:android:source-size
```
