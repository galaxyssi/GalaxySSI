# S26U WebView renderer recovery

## Scope

- Device: S26U / SM-S9480 only.
- Android build: 1.1.70 (956).
- WebView provider: com.google.android.webview 150.0.7871.181.
- Updated with `adb install -r`; app data and the WebView provider were not cleared or downgraded.
- No Desktop, UI layout, theme, or provider-credential changes.

## Reproduced failures

The original direct-cloud image-search request established a cloud connection in
389 ms but did not produce its first text delta until 230,093 ms. Completion was
logged at 230,102 ms. The intervening log contains repeated web search/research/fetch
operations, renderer crashes and timeouts. This is not a measurement of DeepSeek
inference speed in isolation.

1. The main process and `:web_renderer` used the same WebView data directory.
   Chromium repeatedly rejected the second process at service initialization.
   Android displayed a suggestion to uninstall WebView updates, but the reproduced
   error was an application process-isolation defect.
2. Once process isolation was fixed, the real-page test failed with
   `renderer_non_public_destination`. The service performed hostname resolution
   on its main thread. Moving that validation to a worker made the same real-page
   test pass without relaxing the public-address policy.

The initial device run was **3/4**, not a pass. Its real-page failure drove the
second fix and was retested.

## Changes

- Select `agent_web_renderer` as the private process's WebView directory suffix
  in `Application.attachBaseContext`, before WebView or providers initialize.
  Keep the main process directory unchanged. Android versions below API 28 retain
  static fetching rather than starting an unsupported isolated renderer.
- Report initialization failures through the service protocol instead of throwing
  from service startup.
- Handle null/dead bindings and binder death. Bound missing-connection waiting to
  five seconds, unbind in cleanup, and apply a 30-second process-health cooldown.
- Resolve the service's initial hostname on a dedicated worker, within the render
  timeout. Cancel preflight work and reject late requests after service shutdown.
- Preserve static evidence and its diagnostic when optional rendering is
  unavailable. Preserve task cancellation and overall deadline semantics.
- Return actionable model-facing guidance for an unavailable renderer and unknown
  search engine IDs. Do not silently replace an explicitly required source.

The initialization ordering follows the Android
[WebView data-directory API](https://developer.android.com/reference/android/webkit/WebView#setDataDirectorySuffix(java.lang.String)).
Dead/null binding handling follows the
[ServiceConnection contract](https://developer.android.com/reference/android/content/ServiceConnection).

## Final validation

- Final stable-source Gradle build: successful.
- Targeted unit tests: **24 passed**, zero failures/errors.
- S26U instrumentation: **4 passed**, zero failures, 7.317 seconds total.
- `npm run check` and `git diff --check`: passed.
- No new GalaxySSI fatal exception appeared in the inspected 14:00+ crash log.

Device cases in `AgentWebRendererDeviceTest`:

| Case | Observed result |
| --- | --- |
| Main-process WebView plus real isolated public-page rendering | 2,080 ms; 544-byte HTML result |
| Repeated service binding while main-process WebView is alive | 5 ms, 1 ms, 1 ms (warm rebinds) |
| Null/dead/disconnected/rejected binding plus immediate retry | 0-2 ms; one bind per scenario; retry suppressed |
| Missing callback and cancellation recovery | Missing connection ends at 5,000 ms; cancellation propagates and does not poison health |

The final APK's compiled service was also checked for both the preflight executor
and shutdown guard before installation. Unit and device suites cover static
fallback, cooldown expiry, public URL restrictions, cancellation, and source-error
guidance. They do not test every website or every Android/WebView version.

## Remaining verification

The phone auto-locked before the original question could be repeated visibly in
the App. User unlock is required for the remaining live DeepSeek UI test. Do not
compare the original 230-second full agent turn to the 2.08-second standalone
page-render test as if they were the same benchmark.

Search-store lock contention was observed during the original turn and has not
been redesigned in this fix. No claim is made that all direct-cloud response
latency is resolved. No PR has been submitted for this branch yet.
