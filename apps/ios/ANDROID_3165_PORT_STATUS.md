# Android #3165 Resource Settings

Android merge: `dab287aef9f951ded0b1ebf4cbb01c9da0ae52ee`.
Incremental predecessor: iOS #4532, `6af00b2194dcf14691b33ff3d5f79b1b77f350ce`.
This main-targeted branch is cumulative; its full-main diff includes unmerged predecessors and is not this independent increment.

## Resource Changes

- Model management/import/download stays first. Preflight, accelerators, actual iOS permissions and privacy/storage become separate standard disclosure groups, initially collapsed.
- ASR model selection and recheck remain ahead of device capabilities, runtime policy, online privacy and paired-Desktop settings. Keep existing feature gates, explicit consent alert, toggles, model selection, privacy boundaries and remote trust checks.
- Scene-local expansion state survives data refresh and view reconstruction without writing resource/provider preferences. Folding does not reinstall, delete, reset a setting, replace a download manager or grant permission.
- Preserve real native permission controls, rather than removing them to match Android's removed hardcoded permission rows.
- Software list/details separately show installed manifest version and available catalog version. A different catalog version is not presented as the version already installed. Unknown/missing metadata remains Unknown, never inferred from a catalog. A ready different-version pack is labeled Installed; exact matches retain Ready. Explicit install/reinstall/uninstall actions are unchanged.
- `installedVersion` is computed and does not alter the Codable storage format, manifests, signatures, validation, runtime requirements or activation policy.

## Coverage Limits

All 19 changed Android files are pinned and dispositioned. Existing native home/model navigation (including #3169) is retained. This increment does not establish completion of #3165's wider memory/proactive/general/execution subpage redesign or pixel parity. Those remaining areas need further comparison. Android QNN is not implemented or advertised on iOS; native acceleration controls stay intact.

Source guards compare retained native control bodies, consent, install/uninstall actions and backing managers to the exact predecessor. Regression fixture source covers installed version filtering and unchanged serialization, but is not executed. Windows has no Xcode: no Swift type checking, XCTest, layout/accessibility, scene restoration, actual model download retention or runtime activation/device acceptance was performed. No IPA, Android, Desktop, version bump or data migration.
