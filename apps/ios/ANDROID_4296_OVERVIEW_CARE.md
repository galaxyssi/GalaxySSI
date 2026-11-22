# Android #4296: care on the iOS health overview

Reference: https://github.com/galaxyssi/GalaxySSI/pull/4296
Android merge: `99f35f923cc288e019505295dbc4b1b1b1c88488`.

## Ported behavior

- Personal Health includes up to three current confirmed actions, or one upcoming action when today's bounded candidate page is empty and exhausted.
- Three ongoing concerns show their current stage or a changed-source marker. Reading the overview never reconciles concerns, accepts actions, calls a model, or writes the archive.
- Each concern contributes its latest visit by canonical revision. A cancelled latest visit does not fall back to an older appointment. The summary uses the recorded visit time zone and only a journal bound to that exact concern and visit.
- Action selection reopens the existing reminder/feedback/source-review UI by exact concern and action ID, without relying on a paginated first-page search. Visit selection opens its exact journal or encounter; concern selection reuses care detail.
- The eight-candidate agenda projection reuses current action, permission, profile, instruction and original-source checks. It is rebuilt in memory rather than trusting a potentially stale saved projection. An unexhausted page with no eligible action reports pending review rather than no actions.
- Selection rechecks the current preview and permission epoch. Source/privacy/account changes dismiss selection and refresh. Backgrounding and protected-data lock clear the overview; active minute, day and clock/time-zone updates refresh due labels.

## Platform boundary

iOS uses its existing separate local-summary and local-care consents. Both must be enabled to show sensitive previews; online model/profile-analysis permission is not requested or required. Revocation hides retained concerns and visits rather than exposing disabled historical data. Existing iOS action and encounter hosts remain responsible for mutation validation. Ordinary Agent chat is unchanged.

## Validation

Added XCTest source for read-only loading, missing concerns, online-permission independence, summary/care revocation, epoch renewal, changed inputs, exact visit/time zone, cancellation, clock ordering, action deadlines and exact missing-action rejection.

Windows can run the project/static and Swift grammar checks, not Xcode, XCTest, simulator screenshots, notification delivery or device interaction. No runtime/UI parity or device certification is claimed by this port.
