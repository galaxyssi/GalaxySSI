# Local Collaboration Tool Coverage

Android 1.4.87 / 1172. No Desktop or model-selection change.

## Scope

The on-device model loop previously filtered its registry down to web tools,
even when a collaboration assignment supplied an exact host source binding.
It could neither recall scoped peer originals nor publish an intermediate
workspace artifact. Bound local sessions now also disclose:

- `galaxyssi.phone.collaboration.recall`
- `galaxyssi.phone.collaboration.publish`

The publication adapter reuses the existing cloud/remote milestone schema,
validator, encrypted workspace, immutable IDs and scheduler notification. It
does not create another publication store or declare an assignment complete.
The ordinary local chat catalog is unchanged. Publication is not added to the
global phone catalog, avoiding duplicate publication adapters in cloud chats.

## Boundaries and Recovery

The source message, conversation and turn must resolve to the host's original
member assignment. Tool arguments cannot supply group, author or task authority.
Supplied source IDs with missing or mismatched ledger bindings fail before local inference starts. Fresh writes
are checked against pause/stop controls, membership and dispatch retirement.

Publication is a serialized mutation with an effect receipt. Replaying an
already committed native invocation returns its historical observation rather
than repeating the mutation. A new invocation with the same milestone ID and
identical payload recovers the same workspace version; changed payloads cannot
overwrite an accepted milestone. Failed submissions retain the validator's
reason and original result, not an invented generic JSON diagnostic.

A rejected final draft exposes only scoped recall on the next local run. The
publication executor also rejects an attempt to bypass that read-only repair
catalog. Existing dependency and independent-review visibility still apply.
An intermediate publication is not scientific verification, a verified web
citation, assignment completion, or proof that a peer consumed the work.

## Verification

Verified on 2026-10-07:

- 1,208 unit tests in 98 suites passed without failures, errors or skips.
- Android debug and instrumentation APK builds passed.
- Repository checks and six core-regression configuration tests passed.
- Twelve instrumentation tests passed on the authorized SM-S9480: seven new
  local-tool cases and five existing interim publication/scheduling cases.
- Android 1.4.87 / 1172 was installed without clearing application data.
- Installed APK SHA-256:
  `c59106ffd9ce9b2be46f29379d0a21ceb7e739fec364bad7d6d0ae473b9a884e`.

Tests use dedicated synthetic groups, production native registries and encrypted phone
storage. No real provider or local inference engine is invoked. Opening another
store instance is persistence coverage, not a process-death or reboot test.

The synthetic adapter checks that a publication receipt reaches the next model
request, the next call can read the exact original, and the final response can
reference the saved milestone without recreating it. It does not demonstrate
autonomous model selection of these actions or any increase in research quality.

## Reproduction

From `apps/android`, with the Android SDK configured:

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests '*Collaboration*Test' --tests '*LocalModelWebToolAdapterTest' -x :app:buildNativeMemory --console=plain
.\gradlew.bat :app:assembleDebug :app:assembleDebugAndroidTest -x :app:buildNativeMemory --console=plain
```

The exclusion reuses an existing native-memory artifact, not a new Rust build.
With both APKs installed on the authorized test phone:

```powershell
adb -s <authorized-device> shell am instrument -w -r -e class com.galaxyssi.chat.CollaborationLocalToolsDeviceTest,com.galaxyssi.chat.CollaborationMilestoneDeviceTest com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
```

Real on-device model inference, long interruption recovery and cross-provider
quality comparisons remain separate acceptance work. This increment does not
claim completion of those experiments or change the private paper's conclusions.
