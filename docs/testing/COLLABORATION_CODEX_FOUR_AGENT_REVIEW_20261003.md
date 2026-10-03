# Codex Four-Agent Research Review: 2026-10-03

## Scope and Result

The user requested actual Codex execution with four agents on designing a novel
protein, predicting its fold, and experimentally verifying structure and function,
then using the execution lessons to improve GalaxySSI. The user subsequently
delegated the choice of function. The working scope selected was a GFP-binding
protein for benign cell-free in-vitro research, not therapeutic use or biological
regulation. Numerical acceptance thresholds remain provisional until the exact
target construct, non-target panel and analysis rules are frozen.

Four real Codex subagents ran in the current Codex task, with the parent acting as
coordinator. This was NOT a new run in the Android collaboration group or a phone
transport test. The original phone research was not restarted or modified.

| Agent | Independent contribution | Cross-review or handoff |
| --- | --- | --- |
| Hilbert | Goal contract and two candidate research routes | Received Volta's objections to binding, specificity and structure criteria |
| Bernoulli | Actual read-only local software/compute inventory | Parent resolved permission-denied hardware queries; received experimental evidence boundaries |
| Volta | Independent experimental evidence contract | Distinguished binder folding, binding affinity and complex pose; challenged proxy measurements |
| Dirac | Read-only App orchestration audit | Parent rejected an arbitrary three-attempt cutoff and requested a feedback-only alternative and patch review |

No candidate sequence, predicted structure, physical sample or experimental
measurement was produced. The scientific goal remains unfinished. These are real
model contributions and local capability checks, not a demonstrated multi-agent
quality advantage: no equal-budget single-agent control or complete token/cost
ledger was collected.

## Actual Capability Observations

- The inspected Python environment was 3.11.15 with PyTorch `2.12.1+cpu`;
  `torch.cuda.is_available()` returned false.
- Transformers `5.12.1` could import `EsmForProteinFolding`. Importability does not
  establish model weights, successful inference or binding-pose prediction.
- AlphaFold, ColabFold, OpenFold, fair-esm, JAX and OpenMM were not found in that
  interpreter. Checked default model caches did not contain folding weights;
  the entire host was not searched.
- Hardware CIM queries were initially denied. The parent repeated only those
  read-only queries with approved escalation: Intel Iris Xe Graphics,
  51,190,489,088 bytes of physical RAM and 16 logical processors.
- No package/model installation, large download, external sequence upload,
  compute purchase, account registration or experimental submission occurred.

The parent also acquired the public sfGFP target reference **2B3P, entity 1,
revision 2.0** from RCSB at `2026-10-03T15:45:24Z`. This is existing published
experimental data for the target, not an experimental result for a new binder.
The 309,580-byte mmCIF has SHA-256
`88db7abf8afdf94f165e671d72d0ccc73e8161d7f06cf89362ddb11aa6615b9f`;
the API canonical reference sequence has length 244 and SHA-256
`34c908a2ca4843e6c7c40a881ed0c5eb264134ae45ff71b4aaa26f554fee8801`.
The raw public files and local manifest are saved separately from this repository.
Only the coordinate record identity was checked; sequence-to-coordinate mapping
and physical sample identity remain unverified. This is a real input artifact,
not a prediction or completed protein design.

The useful recovery example was permission-denied -> report unknown -> obtain
authorized read-only observation. A denied probe was never converted into a claim
that the hardware does not exist.

## Scientific Review Findings

The provisional engineering goal was measured GFP affinity `Kd <= 1 micromolar`
and at least ten-fold affinity selectivity over a predeclared non-target panel.
These numbers are selected benchmarks, not literature guarantees or measurements.
Independent review required pinning the exact GFP sequence/construct and treating
uncertainty, undetectable binding and panel membership explicitly. Selectivity
must use the worst-case panel ratio, not an average.

The proposed core-coverage/RMSD criterion applies only to a predeclared comparison
against experimental structure. Agreement between two predictions is not physical
verification, and binder-fold agreement cannot establish the GFP-bound pose.
Fluorescence intensity alone also cannot establish affinity. Every future result
must retain target/candidate identity, sample or input hashes, raw evidence,
software/analysis versions, uncertainty and the exact criterion version.

Primary references consulted by the specialists:

- [RFdiffusion original research](https://www.nature.com/articles/s41586-023-06415-8)
- [BindCraft original research](https://www.nature.com/articles/s41586-025-09429-6)
- [De novo protein binding design](https://www.nature.com/articles/s41586-022-04654-9)
- [Quantitative binding measurement](https://elifesciences.org/articles/57264)
- [GFP/nanobody structure record 3K1K](https://www.rcsb.org/structure/3K1K)
- [Selected sfGFP target reference 2B3P](https://www.rcsb.org/structure/2B3P)
- [ESMFold implementation](https://github.com/facebookresearch/esm)
- [Transformers ESM documentation](https://huggingface.co/docs/transformers/model_doc/esm)
- [ColabFold external-service caveats](https://github.com/sokrypton/ColabFold)

## App Improvement Derived from This Run

An existing resource-discovery job can complete while the coordinator's blocked
assessment still omits the checked alternatives and their evidence. The host then
correctly declines to accept the blocker, but previously supplied no exact
resource-assessment diagnostic. It could request another coordinator assessment
without explaining the missing fields. This is a code-path finding, not a claim
that the current phone run exhibited this exact failure.

The scoped change adds `galaxyssi.resource-resolution-feedback.v1`:

- The exact blocker/alternative field path and validation requirement.
- The stable resolution-work ID and whether host-recorded work completed.
- Distinct `resolution_not_completed`, `assessment_needs_repair` and
  `blocking_record_complete` facts. The last means record shape only, not verified
  source truth, resource availability or scientific success.
- Guidance to recall the saved results, repair the assessment, assign concrete
  additional work with a new ID, seek assistance, or state a genuine blocker.
- Durable request context and goal-contract snapshot retrieval, including when
  the full feedback exceeds the inline prompt budget.

The change does not add retry-count termination, weaken acceptance, automatically
grant permissions, alter scheduling, replay completed work or change UI. It
provides more accurate observations; it does not guarantee the model will always
choose an effective recovery strategy. Cloud and remote assignments using the
shared research-prompt path receive the same feedback.

## Verification and Remaining Work

The existing equal-budget evaluation contract suite passed 26 tests before the
change. New JVM regressions cover exact missing fields, completed discovery
without repeated dispatch, unchanged criteria/disposition, genuine blocked
records, malformed alternatives and oversized feedback retrieval after snapshot
restoration. After the change, **631 JVM tests in 49 collaboration suites passed**
with zero failures, errors or skips; the 26 Node evaluation contracts also passed.
Independent Codex code review found no defect. Whitespace and Kotlin source-size
checks passed. These checks do not establish a scientific or model-quality score.

Command: `:app:testDebugUnitTest --tests '*Collaboration*Test'
-Pgalaxyssi.requireEmbeddedRuntime=false -x :app:buildNativeMemory`.
The native-memory rebuild was excluded for JVM testing because the Rust toolchain
was not configured in this environment; existing unchanged JNI artifacts were
present. No native code changed. An initial test assertion expected the inline
omission marker after restore; it was corrected to verify the actual pinned
directory and byte-for-byte paged retrieval through a recreated store.

Android source version is **1.4.35 (1120)**. Desktop is unchanged. The independent
follow-up branch is based on the still-open publication recovery PR #3359.

No new phone installation or real-provider retry experiment is claimed for this
patch. Genuine fold prediction requires suitable weights and compute; genuine
structure/function verification requires authorized experimental capability and
raw measurements. Neither requirement can be satisfied by repeating planning
documents, importing a model class, or converting simulations into observations.
