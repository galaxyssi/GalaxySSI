# Author evidence read receipts

## Failure

An author could retrieve and confirm every page of its own operational evidence,
then publish an interim result. The saved citation retained the correct coverage
counts but unconditionally replaced `scoped_pages` with `same_dispatch_execution`.
An independent reviewer could therefore see who executed the operation but could
not distinguish that ownership shortcut from the author's separately completed
original read. A real handoff trial surfaced this ambiguity instead of silently
accepting the author's claim.

## Contract

When all original pages have actually been served and, for remote execution,
confirmed, the host keeps `scoped_pages` in the publication's frozen citation.
Execution ownership is used only while full page coverage is absent. Partial
counts and missing offsets remain explicit; ownership is not proof of a full read.

The reader identity, exact evidence digest, original content digest and total
coverage remain bound to the dispatch. Publishing does not accept model-authored
coverage fields. Another member must still read the original independently. No
later read rewrites an old artifact, creates a retroactive receipt or changes the
meaning of an existing immutable revision.

This is a host-recorded delivery fact, not proof of comprehension, correctness,
complete provider history or scientific validation. It avoids sending recursive
copies of prior recall responses just to establish a simple handoff fact.

## Verification

Focused tests cover full remote confirmation, partial reads, frozen pre-read
citations, recreation, dispatch isolation and forged peer coverage. The encrypted
device fixture imports a live Desktop observation, confirms the author's exact
read and publishes it to an assigned peer. Reading that artifact must expose the
author's receipt without crediting the peer with reading the original.

Android 1.4.90 (1175) built successfully with 1,353 focused unit tests across 111
suites passing. Three encrypted-store instrumentation tests passed on S26U after
replacement installation without clearing app data. Repository checks and the
Kotlin source-size policy passed. The APK SHA-256 is
`8680c7cef835872f9828e2cf6e797db3ab80d1f8f6038f016ba11fe2671bb332`.

No new real-model trial was run for this increment. The preceding live-handoff
trial remains a failed full-team acceptance result; this fix does not retroactively
change its verdict, establish complete provider history or prove capability
growth. Redundant coordination and full-team acceptance remain separate work.
