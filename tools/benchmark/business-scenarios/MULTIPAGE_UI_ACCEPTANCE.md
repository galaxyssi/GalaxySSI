# Multipage artifact UI acceptance

## Scope and invariants

The frozen campaign remains 100 cases and 1,100 planned turns. This change is
instrumentation only; it does not change production UI, timing thresholds,
model prompts or historical assessments. It depends on PR #3292's strict reply
identity checks. Only Active3 / SM-T575 was operated.

`business_artifact_ui_all=true`, together with `business_artifact_ui=true` and
`business_recapture=true`, checks every declared IMAGE block in the selected
completed turn. It does not silently filter out missing local files. Each image
must have a unique nonblank ID, a local file whose SHA-256 matches the delivery
manifest, a uniquely identifiable visible thumbnail, a fullscreen viewer and a
working save control. Saving must create a new MediaStore download with the same
hash; an existing download cannot satisfy the check.

The timestamped aggregate audit records expected and verified image counts,
per-image results, running/completed/failed status, and the failed image index.
Progress is persisted after every image. This tests declared previews, not proof
that a model declared every required page; source/native-file page counts and
content correctness need their separate audits. No model task is resent.

## Active3 results, 2026-09-30

App 1.3.26 (1069) was installed in place, preserving configuration. The test APK
was rebuilt and installed. Build succeeded in 1m 50s; eight reply-identity tests
passed in 0.178s and 32 host catalog/report tests passed in 0.242s.

Run: `active3-warehouse-pptx-20260929-v1325`, case A007.

| Turn | Separate audit | Declared / verified | Runner time | New downloads |
| --- | --- | ---: | ---: | --- |
| 1, quantity revision | capture-audit-1790722003583 | 4 / 4 | 18.222s | 1000003452-1000003455 |
| 2, mobile layout | capture-audit-1790722102428 | 4 / 4 | 19.872s | 1000003456-1000003459 |

For each page, the real thumbnail opened fullscreen and the save button produced
a new hash-matching download. Turn 1 had also passed an earlier four-page audit
(`capture-audit-1790721605299`, 18.414s) before incremental status recording was
added. That earlier result is not counted as another model turn.

Turn 2 originally lacked pages 2 and 3 after the 90-second artifact observation
window. They are present now. This establishes late availability and UI usability,
not timely delivery. The original failure is unchanged. Screenshots of the two
previously missing pages show the revised data (204 + 272 + 220 = 696, quantity
73, currency unspecified) and the improvement proposal. A prior-page save toast
temporarily overlaps the bottom of one capture; that capture alone is not a full
unobscured layout acceptance.

Run: `active3-warehouse-image-20260930-v1326`, case A008.

| Turn | Separate single-image audit | Runner time | New download |
| --- | --- | ---: | ---: |
| 2 | capture-audit-1790721255347 | 9.156s | 1000003445 |
| 3 | capture-audit-1790721309190 | 9.855s | 1000003446 |
| 4 | capture-audit-1790721349524 | 9.207s | 1000003447 |

All three opened fullscreen and saved with matching hashes. Their unsupported
currency content failures remain failures; file/UI correctness is independent
of content quality.

## Original evidence preserved

Raw report SHA-256 values remained unchanged after these read-only audits:

- A007: `1d49ab0c9fce6d5da22a4e63fb9335b7ca22cefb5f4a230b2bbaa14d90078f05`
- A008: `70839b41e821f3b5876f43462b280a29df8057e8d3d79a2020ce1811e6bd5548`

The historical process row was not captured in these recaptures, so they do not
prove timer state. Original live observations retain their own timing evidence.
Private raw JSON, screenshots and generated files remain outside Git. The wider
campaign, remaining follow-ups, live deployment of pending Desktop fixes, and
long-tail transport recovery are still incomplete.

## Reproduction

Run the installed instrumentation with these arguments, selecting one existing
synthetic completed turn (change `business_capture_turn` to 2 for the late audit):

```text
am instrument -w -r
  -e class com.galaxyssi.chat.BusinessScenarioLiveDeviceTest#recaptureCompletedTurns
  -e business_recapture true
  -e business_artifact_ui true
  -e business_artifact_ui_all true
  -e business_run active3-warehouse-pptx-20260929-v1325
  -e business_cases A007
  -e business_capture_turn 1
  -e business_device_model SM-T575
  com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
```

Use the authorized device serial explicitly. Read the aggregate and per-page
audit JSON, not only the instrumentation process exit code.
