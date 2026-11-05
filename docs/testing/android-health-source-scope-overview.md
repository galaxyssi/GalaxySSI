# Android health source scope overview

The device and data sources page distinguishes supported Health Connect
types, the user's app selection, and verified system read grants. Missing
permissions, unavailable providers, and unverified grants are not counted
as enabled scopes. Historical successes remain visible even if a source
is no longer selected or a subsequent attempt fails.

The overview reads saved checkpoints without fetching or importing
measurements. The per-type entry opens the same scope in Sync and
Coverage. A saved Bluetooth receipt is displayed separately from Health
Connect history and is not evidence of a live connection.

The source tests exercise the authorization-state matrix using supplied
states and use an isolated database for the native route and historical
timestamps. They do not stand in for a real Health Connect grant or a
commercial Bluetooth monitor.

Android 0.1.7.72 passed 42 focused instrumentation tests on Tab Active3
(SM-T575), with no failures or skips. The suite included source overview,
scope-specific sync navigation, Health Connect, Bluetooth storage,
sync-notification, and health overview regressions.
