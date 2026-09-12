# SM-T575 source revision evidence

- Date: 2026-09-12.
- App: Android 1.1.96, versionCode 982. Installed with `adb install -r`; no user data reset or model changes.
- PR release reservation: 1.1.97 (983), changed after testing to avoid concurrent PR #3019. These evidence files describe the real 1.1.96 test APK and are not relabeled as a 1.1.97 device run.
- Upstream base: `253069c46` (includes #3017); subsequent source-language-only Desktop correction is separate from this Android feature.
- App APK SHA-256: `db079e5ca84ebb0a2121f82c9a30f5299a5262f83d05ca7349a70e4e02296784`.
- Test APK SHA-256: `5b11dd413c60a11639946519cd005bf656ebcc3540b0cf6f29f2d7ba19eef312`.
- Fixture: `test-knowledge-backup-source-revision-7d7ae32a605d0a6bf9487023.db`.
- Scope: 10,001 real encrypted synthetic members in one source, not 10,001 distinct sources.
- Canonical header/chunk SHA-256 before and after both runs: `c847fabe9875782c74e5b9fd9043320feedba59e3c921ada5f01b66ef3bac7af`.

## Files

| File | Samples | SHA-256 |
| --- | ---: | --- |
| `summary.json` | Summary | `460efb8583ad3c95ea1578128d5a1266563cb1672bb5dff932a2e9fdfb3d06d1` |
| `legacy-digest-ms.csv` | 20 | `6c44a899e415b6c6170901398f580f6768ff9a0d0ee0b8a622f7be9ced551dd2` |
| `revision-and-write-ms.csv` | 200 lookup/write pairs | `df77ee8425ad506ce5a8f985e30f2811cfc0694c0fc4926e525ce5839e462d69` |

The legacy algorithm is the previous full encrypted-header SHA-256 scan. It uses the same source and ciphertext as the new indexed checks. Writes target a separate synthetic source and are removed before final fingerprint validation. The migration simulation drops only the new fixture revision tables/triggers; canonical encrypted data is not regenerated. The first full run including seeding passed in 407.078 seconds; the retained-corpus final run passed in 136.402 seconds.

## Reproduction

Run `KnowledgeSourceRevisionScaleDeviceTest` with `sourceRevisionScaleFixture` set to an isolated name matching `test-knowledge-backup-source-revision-[24 hexadecimal characters].db`. An empty fixture is seeded with 10,001 records in committed batches of 64. A complete retained fixture is reused. The test requires all identities and content in descending fixture order, bounded key pages, original ciphertext invariance, and lookup/write P95 below 200 ms. It exports these small evidence files under the App's external-files test directory.

`KnowledgeSourceRevisionRecoveryDeviceTest` is opt-in using `sourceRevisionRecoveryFixture` with its own strict fixture-name prefix. Run `prepareUncommittedRevisionAndTerminate`, expect intentional process termination, then run `verifyNextProcessRestoresCommittedRevisionAndSnapshot` in a new process. A crash result alone is not a passed recovery test. Cleanup runs only after successful verification.

## Limits

These are storage-level tests on synthetic private fixtures. They do not establish 100-million-record capacity, concurrent saturation latency, a 200-ms full-source export, UI responsiveness, physical-device-reboot recovery, all-provider tracing, or full long-running DAG adoption. A 64-key page does not bound one exceptionally large item's plaintext size or the WAL retained by a long snapshot. The Markdown adapter still materializes a complete List and document String.
