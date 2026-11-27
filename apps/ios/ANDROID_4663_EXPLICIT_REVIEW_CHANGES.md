# Explicit Review Changes (Android #4663)

Baseline: Android PR #4663, merge `fe0940f0c`.

Final editors may return exactly `verdict: request_changes` plus a specific
objection, without inventing an already-corrected answer. This uses the same
one-rewrite/one-recheck pair and pre-funded 12-call ceiling from Android #4659.
Mixed answer fields, missing/blank/wrong-type reasons and duplicate JSON fields
cannot grant approval. Recheck may treat request_changes as a terminal veto,
never as permission to start another rewrite.

Four historical literal example reasons are not actual objections. An initial
placeholder withhold/revise/request_changes yields a localized missing-reason
receipt and preserves contributor dissent, without asking the writer. At recheck,
an invalid or placeholder veto falls back to the original specific objection.
Real objections containing similar words are retained; matching is whole-string,
case-insensitive, with trailing ASCII periods ignored.

Workers, synthesis, audit, rewrite and recheck share the prediction-check prompt:
separate expected, contrary and uninterpretable observations under independent
conditions, do not classify invalid measurement/reporter failure as counterevidence,
identify plausible competing explanations and missing evidence, and invent no
data. These are model instructions, not deterministic scientific validation.
Planning authority, provider selection, text-only privacy boundaries and role,
parallel and call ceilings are unchanged.

Six additional synthetic XCTest methods are authored, not executed, covering the
exact new verdict, invalid fields, localized placeholder receipts, terminal veto,
specific-reason preservation and prompt propagation. Existing handback assertions
are updated to retain all original safety contracts. Focused JS/project checks
are source-only. No native compilation/tests, live models, device or scientific
acceptance, full check, CI monitoring or IPA generation is performed. No private
data or evidence is committed.
