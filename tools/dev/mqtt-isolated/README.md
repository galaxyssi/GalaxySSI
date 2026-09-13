# Isolated Android MQTT Storage Verification

This debug-only build compiles the real app Kotlin and its dependencies, but uses
`com.galaxyssi.chat.mqttverification` and a minimal manifest with a plain Android
`Application`. It has no launcher or product services and does not run production
Application startup. Tests and real Workers may initialize state inside this
separate package; they have no access to production App private data. The app's
CMake outputs and embedded model/runtime assets are not
needed by the SQLite/Keystore/Signal tests and are omitted. Libsignal's dependency
and native library are retained. This is not a shipping APK or full product test.

The manifest permits Internet access only for explicit network test cases; no
service or connection starts with the package. `MqttPublicPoolDeviceTest` is
skipped unless `-e publicMqttSmoke true` is passed to AndroidJUnitRunner. It sends
at most one small synthetic packet per public broker, using a fresh exact test
topic, no wildcard subscription, no user identity, and no chat or pairing data.
Select the designated phone explicitly and report each path independently.
This small loopback test is not App/Desktop delivery or a throughput benchmark.

Run from `apps/android` with the usual JDK and Android SDK configured:

```powershell
./gradlew.bat -I ../../tools/dev/mqtt-isolated/isolated.init.gradle `
  :app:assembleDebug :app:assembleDebugAndroidTest -x :app:buildNativeMemory `
  '-Pgalaxyssi.requireEmbeddedRuntime=false' --max-workers=2 --console=plain
```

Before installation, use `aapt dump badging` to verify the target application ID
is `com.galaxyssi.chat.mqttverification`, and the test ID ends in `.test`. Never
install an APK whose package identity differs from those values during this test.
Always provide the explicitly designated phone's serial to ADB.

```powershell
adb -s SERIAL install -r app/build/outputs/apk/debug/app-debug.apk
adb -s SERIAL install -r app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb -s SERIAL shell am instrument -w -r `
  -e class com.galaxyssi.chat.MqttAtomicInboxDeviceTest,com.galaxyssi.chat.MqttRouteStateDeviceTest `
  com.galaxyssi.chat.mqttverification.test/com.galaxyssi.chat.MqttIsolatedTestRunner
```

The isolated runner initializes WorkManager with its test scheduler and preserved
executors before the test suite starts. It retains the real Worker factory and
only accepts the verification package, never production storage. This enables
window/history tests which publish cognition events; it is not a test of Android
JobScheduler, Doze, foreground services or process survival.

The MQTT storage tests only create `test_link_atomic_*` and `mqtt_route_test_*` databases
inside the separate test package. They do not reset any real app identity or scan
contacts. After recording results, uninstall only the two verification packages
created by this procedure. Never uninstall `com.galaxyssi.chat` as test cleanup.

Do not ship or benchmark normal app startup using this manifest. The next normal
build must omit this init script, restoring the normal application ID, manifest,
native build, and runtime assets. The normal app still requires full coordinated
Android/Desktop transport integration and its own end-to-end verification.
