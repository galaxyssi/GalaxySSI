# Android research citation recovery

## Reproduced failure

On S26U (SM-S9480), the v1.2.4 development APK returned a sources-only fallback
for the user's relationship question. A separate fresh test conversation
reproduced it in 69,249 ms. The model produced a final draft, but the citation
gate found three foreign URLs; after one repair there was still one foreign URL.
The app discarded the draft despite having 43 locally integrity-checked evidence
items. These items are not necessarily independent sources or semantically proven
support. The original 53-second task's detailed log had already rotated away.

## Changes

- Android streaming and its complete-JSON fallback request stable citation IDs.
  The app resolves `[[cite:ID]]` only against verified local evidence. No domain,
  source-title or fuzzy URL substitutions are allowed.
- Preview and final text share the resolver. Code examples, existing links and
  image Markdown are not rewritten. Unknown/tampered IDs cannot pass validation.
- The existing inline renderer now accepts angle-delimited HTTPS Markdown links,
  including parentheses/query strings, without exposing their raw URL as text.
- Keep the existing first correction, then allow one bounded partial-synthesis
  repair. It must preserve supported conclusions, remove unsupported claims and
  explain remaining uncertainty. It must not simply delete problematic links.
- All generated answers still pass citation and research-quality checks. A final
  failure remains a sources-only fallback; this is not permission to fabricate
  a summary or a guarantee that every provider obeys the contract.
- Log mismatch category and reference hashes, never private URL query strings.
- Android version: 1.2.6 (1011). No UI layout or color changes.

The tested development build includes the research changes from #3070 and
transport changes from #3071. Both merged before submission, so this PR is based
on main after those merges and contains only the citation-recovery follow-up.
The device results below describe that integrated development build. Unrelated
watch changes subsequently merged into main were not part of the Android test
build. This follow-up does not change the Desktop native-agent citation
implementation.

## Verification

The first focused JVM run passed 29 tests. The v1.2.6 APK built and was installed
over the existing S26U installation. The same question produced a complete answer
in 80,299 ms, with `status=verified`, zero invalid citations, and no correction
round. Its real-provider instrumented test passed. This is one sample, not a
latency improvement claim: additional source retrieval took longer than in the
earlier failed run.

Screenshot inspection caught raw angle-link syntax in the rich inline renderer
despite the correctly validated answer. The renderer and its regression tests
were then fixed. The final focused JVM run passed 33 tests (zero failures/errors),
the APK rebuilt successfully, and the final v1.2.6 build was installed on S26U.
An additional original-question run returned a summary in 73,286 ms; its saved
post-assertion screenshot shows normal clickable citation labels instead of raw
URLs. The terminal session for that run was interrupted before its final output
was collected; the on-device report and post-assertion screenshot were recovered.

A separate fresh main-page weather query completed in 8,769 ms. The real-provider
instrumented test passed, the citation gate reported `verified` with zero invalid
citations, and screenshot review confirmed summary text plus a rendered source
link. Existing pairing and chat data were preserved. No UI layout/colors changed.

Local evidence (outside the repository):
- `galaxyssi-citation-final-20260919.json` and `.png` in the user's Temp directory.
- `galaxyssi-citation-weather-20260919.json` and `.png` in the same directory.

The tests distinguish a delivered summary from factual correctness: deterministic
URL/ID matching is not an independent semantic judge. The first successful draft
still made overconfident relationship statements before later uncertainty; this
is a remaining semantic-quality issue, not a passing factual-accuracy evaluation.
