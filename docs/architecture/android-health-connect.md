# Android Health Connect Import

GalaxySSI's source page distinguishes SDK availability, granted read types,
and the latest confirmed foreground import. Authorization is not proof that
the provider contains data. The native authorization page requests only
missing, user-selected scopes through AndroidX's Health Connect contract.

- Sleep, steps, measured and resting heart rate, blood pressure, and weight
  are independently selectable. There are no write, background, or history
  permissions. Steps use the platform's aggregate for each completed local
  calendar day, not raw totals from multiple apps. Sleep uses the source
  session's duration, not a diagnosis or a reconstruction of sleep stages.
- Preview reads the intersection of selected and system-granted types, from
  a bounded time range. The app checks grants again after reads and before
  a confirmed save. An empty preview, missing permission, unavailable
  provider, and excessive or failed reads are distinct.
- Preview does not write. Confirmation saves into the encrypted local
  observation store in one transaction, with an authenticated source label
  and keyed per-record deduplication. Stable IDs from distinct origins do
  not collide. Re-import does not overwrite existing observations, undo
  user edits, or resurrect removed copies. The source page's import time
  is a foreground confirmation timestamp, not a synchronization cursor.
- Disconnect revokes Health Connect grants and clears the app selection
  without removing local copies. Existing catalog removal hides the
  measurement but retains its encrypted revision history. Full erasure
  and platform source reconciliation remain separate.
- The exported system rationale displays static data-use disclosures only.
  The legacy AndroidX provider callback uses the SDK's caller UID and
  provider package checks. No measurements or provider IDs are logged or
  automatically transferred to another device or model.

See the [Android authorization contract](https://developer.android.com/health-and-fitness/health-connect/get-started)
and [aggregation behavior](https://developer.android.com/health-and-fitness/health-connect/aggregate-data).
Google Play distribution needs the matching health-data declaration and privacy
disclosure; this change does not modify publishing configuration.

## Verification

Galaxy Tab Active3 (SM-T575, Android 13) was cover-installed with version
0.1.7.32 (1445). Native navigation to the missing-provider state and its
manual-entry fallback was inspected. The existing database opened at schema
5 without clearing data. All 109 focused device regressions passed without
skips, including isolated version 1 through 4 migrations, selection filtering,
revocation before save, duplicate and removed copies, and rollback.

The tablet did not have the Health Connect provider installed. System
authorization and actual provider records still require acceptance on a
device with the provider; injected records do not establish that result.
