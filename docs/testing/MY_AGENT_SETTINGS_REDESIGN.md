# My Agent Settings Redesign

## Scope

Android v1.2.22 (1027) reorganizes My Agent into nine home destinations:
Models and Agents, Devices, Voice, Memory and Knowledge, Proactive Assistant,
Skills and Tools, Security and Data, General, and Advanced.

The existing back button and feature navigation stack are retained. Settings
use flat list sections, small monochrome icons, compact labels, and collapsible
advanced controls. Ordinary chat rendering is outside this change.

## Resource Preservation

- No database migration, preference reset, model deletion, or reinstall reset.
- Existing ASR managers and row bindings still own QNN and Whisper download,
  retry, progress, selection, and installed-state behavior.
- Local model search, signed QNN import, installation, selection, and progress
  remain available. Preflight and accelerator diagnostics are folded.
- Linux and Python/uv installed packs remain in their existing locations.
  Installed versions are shown independently from downloadable catalog versions.
- A stopped runtime is not presented as a missing installation.
- Existing provider credentials, paired devices, and model selection are reused.
- Model settings list configured contacts rather than generic registry aliases.

## Verification

Run focused host tests:

```powershell
./gradlew.bat :app:testDebugUnitTest --tests '*ControlCenter*'
```

Run `MyAgentSettingsRedesignDeviceTest` on the explicitly selected device only.
The four read-only tests cover:

1. Collapsed-section state across refreshes.
2. Home and settings destination navigation, back buttons, and preference values.
3. ASR model section ordering and retained model controls.
4. Local model download/import/diagnostic controls and back navigation.

For release verification, cover-install with `adb install -r`, never uninstall
or clear data. Compare model-file hashes and resource configuration snapshots
before and after installation. The QNN manager may refresh its persisted
inspection timestamp on startup; distinguish this from changed configuration
or missing model files. Do not store credentials or private preference values
in the repository.

Manually verify S26U screenshots for the home page, Voice, QNN, Whisper, local
models, runtime packs, and the retained back button. Verify installed states
without initiating model downloads or modifying the user's selection.

## S26U Verification, 2026-09-22

- Debug build, test APK build, and 10 focused host tests passed.
- Four instrumentation tests passed on SM-S9480.
- Covered 18 settings destinations, plus ASR and local-model child navigation.
- Cover-installed v1.2.22 (1027); no uninstall or data clearing.
- Existing Whisper files and six runtime files retained identical SHA-256 hashes.
- Linux 1.3.9 and Python/uv 0.12.1 still report ready; Tiny remains selected.
- QNN and local-model download/import controls remain available. No new model
  download or inference benchmark was initiated as part of this UI test.
- Nine home entries are visible in the S26U screenshot. Generic registry aliases
  no longer duplicate configured Agents in the model settings list.
