# Android Health Design Acceptance Ledger

The complete objective is the 32-screen GalaxySSI Health Android V2 design in
`design-spec.html`, `index.html` and `screen-specifications.json` supplied by the
user. These are specifications, not patient data. All rows below remain part of
the objective. An implementation or narrow store test is not visible-page
acceptance, and no global completion claim follows from the first imports.

## Per-Screen Evidence And Gaps

| Screen | Existing implementation/evidence | Required work or acceptance still missing |
| --- | --- | --- |
| h01 Common entry | Native Health Center route and prior entry/manual device checks | Final navigation/layout regression with the complete feature set |
| h02 Page navigation | Native function page, grid entry, Activity returns, no bottom tabs | Profile/privacy/file-hub links and final deep-return matrix |
| h03 Overview | Real confirmed-record counts/latest observations; no fabricated score | Freshness/missing/unverified separation, versioned attention cards and preference/severity ordering |
| h04 First use | Actual empty state and local photo/manual/file entry | Backup restore entry and complete first-use acceptance |
| h05 Record Center | Native capture/file queue, encrypted drafts, edit/delete and recovery foundations | Changes must invalidate affected analyses once analysis exists; full multi-format UI matrix |
| h06 Capture | Native Camera2, ordered multi-page drafts, EXIF orientation, quality hints, retake/crop/manual fallback | Authorized hardware focus/light/rotation/photo matrix, automatic paper boundaries, unlocked UI acceptance |
| h07 Recognition review | Local image/PDF OCR, source text/boxes/hash, explicit ownership/unit/time confirmation and partial saves | Source-region overlay, broader field semantics, complete correction UI acceptance |
| h08 Manual measurements | 27 metric definitions, BP components, exact/bounded/range/qualitative results, report reference text, conditions, units, timestamps, revisions, duplicates and soft deletion | Full late-entry/edit/undo UI matrix; connect later analysis invalidation |
| h09 File queue | Encrypted originals, durable jobs, typed failures, retry/cancel, separate table/OCR routes | Final multi-format/process-death UI matrix and encrypted-PDF workflow; unsupported XLSX ISO-typed cells remain explicit errors |
| h10 Table mapping | CSV/JSON mapping, counts, 30-row preview, transactional save/undo; XLSX worksheet/header/serial-date/cache increment | Unlocked mapping/rotation/background tests; XLSX ISO-typed date interoperability; broad qualitative metric support |
| h11 Catalog | Native 27-metric daily/laboratory catalog, bilingual names/aliases/unit search, categories and 30-row records; typed results; metric rows now open native trends; final styled screenshot and three native catalog UI tests pass on 0.1.7.22 | Row-to-trend/back and all-record navigation acceptance; broader/custom definitions, explicit custom qualitative value types and search-state return handling remain open |
| h12 Trends | Native gap-aware exact-value chart, calendar/source/unit/aggregation filters, valid-day coverage, 30-row cohorts, revision-bound point targets and transactional freshness tokens; 195 focused JVM, 142 non-visual and 14 visible device regressions pass; empty trend screenshot inspected | Complete populated point/audit/cohort/return acceptance; physical-device cohorts depend on h17-h20; high-write-rate/large-history performance acceptance and rollups remain open, not a universal latency claim |
| h13 Health AI | No automatic exposure of health records to a Provider | Explicit data-range consent, computed facts/citations, unavailable/stale analysis, necessary-field-only requests |
| h14 Reminder detail | No synthetic medical alert data installed | Versioned rule/snapshot/baseline coverage, complete/later/disable, deduplication and cooldown |
| h15 Reminder center | No health alert functionality claimed | Graded center, independent in-app/system delivery/handling, lock-screen privacy and sync-error separation |
| h16 Weekly report | No generated medical report claimed | Versioned date range/statistics, configurable preview/PDF, no automatic sharing |
| h17 Devices/sources | Manual/file/OCR provenance exists | Actual capability/permission/last-sync source list and distinct disconnect/stop/delete actions |
| h18 Health platforms | No simulated platform connection | User-selected scopes, actual adapter availability, revocation/background/copy-retention handling |
| h19 BLE | No simulated peripheral measurements | Real scan/pair/connect/read/disconnect states, ownership, device timestamps/source IDs/deduplication and opt-in trusted autosave |
| h20 Sync recovery | Import recovery is not health-platform synchronization | Real incremental platform/BLE sync, separate failure classes and tested recovery without duplicate writes |
| h21 Personal profile | Observation profile ID defaults to self | Editable/deletable self-reported context, separate provenance and stale-analysis invalidation |
| h22 Privacy/data | Keystore-backed row encryption and per-original streaming keys; background view cleanup; no generic Agent-memory copy | Health-specific scope/purpose controls, export/delete range preview, permanent erasure and key/backup policy acceptance |
| h23 Reminder settings | General App notification capabilities are not health-specific plans | Plans, quiet/pause/group/complete/later/disable, permission loss/reboot/timezone/revision handling |
| h24 Body exploration | No personal body measurements or fictitious model installed | Educational visuals and interaction, explicit reference/personal distinction; independently validate animation/molecular/experiment work |
| h25 Data/file hub | Distinct observations/originals linked by IDs and import batches | Complete import/export/backup hub and scoped task histories with no automatic sending |
| h26 Import center | Photo/gallery/private originals, PDF OCR, CSV/JSON and current XLSX subset | PDF text-vs-scan path, dedicated verified backup restore and complete format/ownership/link matrix |
| h27 Original library | Native thumbnail/list modes, indexed imported-date/type filters, 30-row keyset pages, persisted cross-page selection and frozen original-only ZIP export; final 207 focused JVM and 167 non-visual device tests pass on installed 0.1.7.23 | Native visible/populated library/selection/export and SAF acceptance pending unlock; missing-original measurement export depends on h29; large-library/large-export performance acceptance remains open |
| h28 Original detail | Hash/type/import time, image zoom/PDF pages, source links and primary observation association | Complete structured read-only information, secondary duplicate-source associations and export-configuration links |
| h29 Export options | Single originals and original-only ZIP stream exact bytes with an explicit manifest; private staging encrypted | CSV/XLSX/JSON record export, PDF report, complete backup/version/link manifest, password-portable packages and format/content coupling |
| h30 Export confirmation | Original-only ZIP freezes a paged file/count/source-size/missing manifest and requires explicit unencrypted-output consent | Final populated confirmation acceptance; scoped measurement/report/backup preview and validated password-portable encryption remain open |
| h31 Export completion | Original-only ZIP separates private generation and explicit SAF save, retains retry artifacts, detects corruption and missing/changed sources | Real SAF/provider/process-death/foreground matrix, complete task history and explicit sharing; full backup completion/integrity acceptance remains open |
| h32 Restore | No general JSON import is treated as a backup restore | Format/version/password/hash/profile/link checks, duplicate/conflict/missing/legacy preview, transactional merge and rollback without default overwrites |

## Accepted Evidence Boundaries

- PR #3685: native manual-record foundation; PR #3686: encrypted originals/local
  recognition; PR #3687: native photo drafts; PR #3688: CSV/JSON mapping and batch
  transactions. Open pull requests and pending checks are not merged-release proof.
- Isolated JVM/device store tests prove the assertions they execute, not every
  screen, production record or platform/peripheral/provider capability.
- After the user unlocked Tab Active3, eight existing native entry/manual/import/
  photo-draft UI tests passed on 0.1.7.20 and its empty draft screenshot was
  inspected. This does not prove the new catalog or XLSX mapping UI. No keyguard
  bypass was performed; hardware capture still needs separate authorization.
- Failing prototype/build/device attempts are retained in ignored build logs.
  Later passing focused tests must not be described as full repository CI success.
- Every independent functional increment needs its own English PR and a version
  increment, after fetching current main. Keep this ledger open until final
  requirement-by-requirement evidence closes every remaining gap.
