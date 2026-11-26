# Android #3165 Resource Settings

Android merge: `dab287aef9f951ded0b1ebf4cbb01c9da0ae52ee`.
Incremental predecessor: iOS #4532, `6af00b2194dcf14691b33ff3d5f79b1b77f350ce`.
This main-targeted branch is cumulative; its full-main diff includes unmerged predecessors and is not this independent increment.

The settings-subpage follow-up uses an independent branch from fetched main
`ee17e7cac043350e3f65c10ba025ecf55cde10c7`; it does not include the unmerged
Android #4543 Health work. The cumulative-branch warning above describes the
historical predecessor, not this follow-up's current PR diff.

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

## Settings Subpage Follow-up

Compared the actual pinned Android `MainActivityMyAgentPages`, memory, general,
global-cognition and Agent-settings source, not only the changed-file inventory.
The previously dense iOS subpages now prioritize common controls and keep advanced
views behind scene-local, initially collapsed disclosure groups:

- Memory opens with real memory, knowledge, review inbox and Obsidian destinations,
  followed by the existing capture toggle. Categories, all six lifecycle states,
  graph, evolution history and audit remain reachable under More. Hero/metric
  overview is no longer placed ahead of management actions.
- Proactive opens with the existing master and proactive-insights preferences,
  goals/research/insights, public attention, current work and continuity. Advanced
  cognition is a distinct route; original observation, world-model and intelligence
  detail destinations remain under More. Runtime refresh and process-now actions
  remain their existing implementations.
- Advanced cognition keeps its first four control switches visible; remaining
  controls, resource budgets and conversation boundaries are initially folded.
  Disabling prerequisites does not reset child settings. Tools/replanning require
  autonomous preparation; discovery requires model understanding. These are UI
  availability conditions, not new grants or execution authority.
- The existing Obsidian configuration, folder importer, incremental sync, review
  candidates and disconnect handlers now also have a direct Memory destination,
  without cloning their storage or approval logic into a second implementation.
- General keeps language, iOS appearance, text size, notifications and About ahead
  of a folded developer/reset group. Notifications opens its own native status and
  system-settings page. Returning to the foreground refreshes actual OS status;
  it does not fabricate an app-managed notification toggle or request permission
  just by expanding a section.
- Execution policy keeps permission mode and task control visible, with existing
  confirmation rules and privacy details initially collapsed. Native guards,
  settings mutations, permission requests and existing navigation remain.

Ten Chinese navigation labels follow Android's pinned Simplified Chinese resource
values. English labels use the established localization fallbacks. Only expansion
state uses new SceneStorage keys; no model/resource install, runtime migration,
preference reset, Android/Desktop/version change or IPA build is involved.

This is source integration, not proof of native build, rendered/pixel parity,
accessibility, navigation/scene restoration or device resource-retention acceptance.
It does not declare every Android #3165 changed-file behavior or the broader
Android-to-iOS backlog complete.

Follow-up source checks: `check-settings-subpages-scope.cjs`, `npm run check:ios`,
grammar parsing of the five changed Swift files, and whitespace checks. The new
scope checker compares backing stores/resource managers and the retained native
handler bodies against the fetched main above, and confirms all 12 advanced
switches remain. No native tests were run. The historical
`check-resource-settings-scope.cjs` fails against its older `6af00b219` baseline on
pre-existing `GalaxySSIStore.swift` changes already present in this main; that
script was not rewritten or its checks suppressed to label this change green.
