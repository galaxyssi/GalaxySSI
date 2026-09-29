# Artifact phase timing and annotation acceptance

## Measurement contract

Driver schema 4 preserves the historical `elapsed_ms` and latency target:
submission through final reply plus terminal task observation. It separately
records monotonic observations for artifact presence, container/hash/save audit,
and UI checks. These include instrumentation overhead, not isolated network
latency or a claim about when a person first saw the result.

- `artifact_presence_wait_ms`: polling after the reply, until every currently
  returned attachment is locally available. It does not prove the expected
  attachment set is complete.
- `artifact_audit_ms`: assessment duration minus that polling interval.
- `save_verification_ms`: a subset of audit time; never add it twice.
- `artifacts_verified_ms`: elapsed observation only when the expected delivery
  and every returned file's container, save operation and download hash pass.
  This does not prove semantic correctness.
- `observed_end_to_end_ms`: includes the later render, screenshot and timer
  checks, including unsuccessful attempts.
- Missing historical phases and failed readiness checks are null, not zero.
  Percentiles use actual samples; p95 is withheld below 30 samples.

The frozen workload remains 100 cases with 11 turns each (initial request plus
10 follow-ups), catalog SHA-256
`945c11225d2f7268e43403c09c7f0bc8158c579168b65e3c32a4b16ba9a113bc`.
Neither the catalog nor production App/Desktop behavior changes in this patch.

## Evidence preservation fix

Input fixtures and output screenshots previously both used `A032-0.png`-style
names. Capturing the reply could overwrite the original input evidence after
submission. Both fixture generators now use `A032-input-0.png`-style names.
A real-device regression writes screenshot stand-ins and verifies the input
bytes remain unchanged for normal data and annotation fixtures.

The initial A032 run below preceded this fix. Its visual checks must not be
reported as a pixel-exact comparison with a preserved phone input. Old evidence
is not silently reconstructed or marked passing.

## Active3 real run

Device SM-T575, Android and Desktop 1.3.22, configured Codex gpt-5.6-sol.
Run `active3-image-annotation-20260929-phases4`, case A032. Input is synthetic
printed arithmetic; this is not real handwriting recognition acceptance.

| Turn | Reply terminal ms | Extra attachment wait ms | Audit ms | Save subset ms | UI checks ms | Observed total ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 0: annotate | 89204 | 12684 | 113 | 82 | 2895 | 104951 |
| 1: minimal marks | 84494 | 12 | 86 | 70 | 2286 | 86929 |
| 2: dark red ink | 59015 | 23 | 127 | 100 | 10050 | 69278 |
| 3: handwriting style | 80587 | 9 | 115 | 97 | 2477 | 83223 |
| 4: unreadable answer | 100371 | 12 | 81 | 67 | 2490 | 102991 |
| 5: undo one mark | 70437 | 11 | 107 | 87 | 3720 | 74307 |
| 6: restore one mark | 70450 | 2577 | 75 | 62 | 2395 | 75521 |
| 7: text-only summary | 22661 | unmeasured | unmeasured | unmeasured | 2387 | 25077 |
| 8: verify original | 71620 | 15 | 116 | 89 | 2585 | 74370 |
| 9: improve legibility | 111829 | 11 | 83 | 69 | 1890 | 113834 |
| 10: final single image | 73754 | 11 | 75 | 58 | 2140 | 76013 |

These three turns delivered exactly one 1200 x 1600 JPEG each. Container,
version filename, download and hash checks passed. Visual inspection confirms
19 beside incorrect 18 and 24 beside incorrect 26; correct rows remain
unmarked and the obscured fifth answer is not fabricated. The second image
removes circles/arrows; the third changes the remaining marks to dark red.

Turn 2 received its result in the background but the immediate reply capture
did not find the target row. Preserve that failed observation. A separate
completed-turn audit then reopened the same conversation, captured the reply,
clicked its thumbnail, opened fullscreen and clicked Save. The new download's
SHA-256 matched `c144a6f428e1f6d2aeb0d9c8dc6cb3ac46b637405161c63b2285b3c7f5cf309b`.
That later audit does not replace the original timing or prove automatic
foreground restoration is reliable.

The remaining eight turns also completed. All ten image turns delivered one
1200 x 1600 JPEG with passing delivery/save checks; the summary turn delivered
text only. All eleven process timers were observed stopped. Reply terminal
latencies were 22.661-111.829 seconds, all within the unchanged 180-second target
for this case. Eleven samples do not establish p95.

Every returned image was visually inspected. Turn 3 uses readable handwriting-
style corrections. Turn 4 labels the obscured answer as unreadable/pending and
separately reports computed 23. Turn 5 removes only the third-row correction;
turn 6 restores it. Turn 7 correctly separates wrong, correct and unreadable
rows without attachments. Turns 8-10 retain the correct two corrections and
uncertainty note; turn 9 thickens the marks and final delivery contains only the
current image. This supports the visible content checks, not pixel-exact
preservation of the overwritten original input.

## Verification and remaining scope

- Android test APK compilation passed.
- Eight device regressions passed: phase chronology/null handling, format
  validation, fixture preservation, configured-target selection, and rendering
  all fixtures from the unchanged 100-case catalog on explicitly selected
  Active3. The renderer uses returned attachment paths and each fixture's
  expected dimensions instead of hardcoded old S26U-only filenames/heights.
- 18 Python catalog/report/phase tests passed, including unchanged historical
  latency and the full 100-case/1,100-turn denominator for partial reports.
- A032 completed all eleven turns, but its immediate turn-2 visibility and
  preserved-input comparison remain unproven. The full 100-case campaign is
  still incomplete.
- Original-image fidelity, semantic review, reliable foreground restoration,
  and stable latency p95 remain separate gates. No broad success percentage is
  inferred from these delivery checks.

Private transcripts, screenshots, generated artifacts and APKs stay outside Git.
