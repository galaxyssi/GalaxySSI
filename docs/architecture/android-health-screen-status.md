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
| h02 Page navigation | Native function page, grid entry, data/file hub, personal-profile, privacy and reminder entries, Activity returns, no bottom tabs | Final deep-return matrix |
| h03 Overview | Native freshness/coverage/missing states, revision-bound links, authorized weekly sleep summary, current sleep attention and recent OCR/table review shortcuts, persisted category/recency ordering; 290 JVM, 252 non-visual and 46 native UI tests pass on 0.1.7.30 | Final populated visual/source-navigation acceptance and future connected-source attention; no invented clinical severity |
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
| h14 Reminder detail | Daily recording and opt-in sleep change details; versioned first/latest evidence, 7/14-day coverage, gap-aware chart, revision-aware source links, complete/later/disable and cooldown; 286 JVM, 248 non-visual and 42 native UI tests pass on 0.1.7.29 | Final source-navigation, visual and physical delivery acceptance; other metric rules only with appropriate evidence |
| h15 Reminder center | Native pending/handled/all views, separate paged health-change and daily recording groups, independent system posting | Report-review and sync-error producers; real notification/reboot/time-zone matrix |
| h16 Weekly report | Native seven-day statistics and coverage, optional measured sleep baseline, revision-bound source links, scoped preview and explicit PDF save; 280 JVM, 242 non-visual and 39 UI tests pass on 0.1.7.28 | Final visual and source-navigation acceptance, real external provider/process-death matrix, and later h13/h14 links |
| h17 Devices/sources | Native overview/function entry, official Health Connect availability, local Bluetooth LE capability, indexed report and manual source summary, system/local fallback routes; 47 focused device tests and visible source-to-local navigation pass on 0.1.7.31 | Once platform and BLE adapters exist: scope grants, connected devices, last successful sync, compatibility verification, and distinct disconnect/stop/delete actions |
| h18 Health platforms | Native selected read scopes and Android authorization; explicit foreground preview and transactional encrypted Health Connect import with disconnect and copy-retention disclosure; 109 focused device tests on 0.1.7.32, including synthetic grant/revocation and actual missing-provider fallback | Real provider grant/deny/revoke and measurement-read acceptance on devices with Health Connect; source reconciliation and history erasure remain separate |
| h19 BLE | No simulated peripheral measurements | Real scan/pair/connect/read/disconnect states, ownership, device timestamps/source IDs/deduplication and opt-in trusted autosave |
| h20 Sync recovery | Import recovery is not health-platform synchronization | Real incremental platform/BLE sync, separate failure classes and tested recovery without duplicate writes |
| h21 Personal profile | Native optional basic fields and paged self-reported history/medication/allergies; encrypted drafts, per-field/entry conflicts, scoped delete preview and generation-safe clearing; explicit context/dependency-stamp APIs; 255 JVM, 218 non-visual and 28 UI tests pass on 0.1.7.25 with profile screenshots inspected | Connect dependency stamps to consent-scoped analysis/report consumers and stale-result UI when h13/h14/h16 are implemented; backup/restore and explicit family ownership remain open |
| h22 Privacy/data | Native privacy controls gate derived views and explicitly selected profile context; encrypted paged history covers those accesses, explicit saves and scoped profile deletion; 264 JVM, 229 non-visual and 32 native UI device tests pass on 0.1.7.26 | Per-request cloud consent and provider enforcement; original retention controls, broad erasure and key/backup policy acceptance |
| h23 Reminder settings | Native opt-in daily plan, sleep change threshold and merge choice, pause, quiet hours, permission status and lock-screen preference | Report-review preference; physical permission-revocation/reboot/time-zone delivery acceptance |
| h24 Body exploration | No personal body measurements or fictitious model installed | Educational visuals and interaction, explicit reference/personal distinction; independently validate animation/molecular/experiment work |
| h25 Data/file hub | Native separate measurement import/review, original-only import, record export, original library and export-history routes; native hub screenshot and UI checks pass on 0.1.7.24 | Complete backup hub, full navigation and populated scoped history acceptance; no automatic sending |
| h26 Import center | Photo/gallery/private originals, PDF OCR, CSV/JSON and current XLSX subset | PDF text-vs-scan path, dedicated verified backup restore and complete format/ownership/link matrix |
| h27 Original library | Native thumbnail/list modes, indexed imported-date/type filters, 30-row keyset pages, persisted cross-page selection and frozen original-only ZIP export; library UI/lifecycle and all 25 library store regressions pass again on 0.1.7.24 | Populated selection/export and SAF acceptance; large-library/large-export performance acceptance remains open |
| h28 Original detail | Hash/type/import time, image zoom/PDF pages, source links, primary observation association and linked-measurement export even with missing original bytes | Complete structured read-only information, secondary duplicate-source associations and populated navigation acceptance |
| h29 Export options | Native scoped measurement CSV/XLSX/JSON; original-only ZIP preserves exact bytes; private staging encrypted; configuration screenshot and native format/opt-in/lifecycle checks pass on 0.1.7.24 | PDF report, complete backup/version/link manifest, password-portable packages, combined content coupling and populated end-to-end acceptance |
| h30 Export confirmation | Original ZIP manifest and immutable 30-row measurement snapshot, metric/date/source scope, count/component distinction, warnings, estimates and explicit unencrypted-output consent | Final populated consent acceptance; report/backup preview and validated password-portable encryption remain open |
| h31 Export completion | Original ZIP and measurement exports separate private generation from explicit verified SAF save, retain retry artifacts and expose durable paged task history | Real SAF/provider/process-death/foreground matrix, explicit sharing and full backup completion/integrity acceptance remain open |
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
