# Collaboration browser ownership

## Problem and contract

Interactive browser scopes previously hashed session, conversation, workspace
and caller. Collaboration members can share those four parent identities. The
host-owned `collaborationSourceMessageId` now adds an independent scope dimension
when present. It is not accepted as a model tool argument. This separates browser
daemons, cookies, operation receipt identities, handoff keys and host capabilities.
This is a preventive isolation fix, not evidence of an observed credential leak.

Playwright's [browser context documentation](https://playwright.dev/docs/browser-contexts)
describes isolated cookie, local storage and session storage. The application
must also route each member to its own scope; creating isolated contexts does not
help if two members are given the same context handle and owner namespace.

## Durable handoff

The encrypted user-control record persists the exact 64-bit collaboration source.
Ownership requires both that source and the derived browser scope to match.
Same-generation updates cannot change the source. The event-wait resolver carries
the original source when reconstructing the native invocation context, including
when committing the returned-control observation. A foreign or missing owner
produces an unverified observation, never a successful login or consumed event.

Ordinary single-agent scopes are byte-for-byte unchanged. Old records without a
source remain ordinary; they are not silently assigned to a collaboration member.
An older collaboration browser in a parent-shared namespace must not be adopted
by guessing which member owned its authentication state.

Ordinary planner and local-dispatch recovery explicitly reject a member record.
The initial isolation increment did not enable managed local-member catalogs.
The subsequent [managed continuation integration](managed-browser-continuation.md)
uses the managed dispatch ledger, exact member assignment, stop/pause state and
durable continuation journal, rather than substituting the parent's ordinary Run
owner. Existing started loops are not silently migrated to the expanded catalog.

## Verification boundaries

JVM tests cover ordinary hash compatibility, two-member scope/receipt separation,
all 64-bit source values, host-only input identity, immutable handoff ownership,
legacy records, exact event resolution and observation commit fencing. Existing
planner/local-dispatch tests also reject a member posing as their ordinary owner.

Android framework fixtures exercise actual Keystore-derived capabilities,
encrypted record reload, independent control transitions, rejected retagging and
production user-control request persistence with an injected host transport.
They submit no model goal, open no website and do not demonstrate autonomous
dependency installation, website login or real-provider task acceptance.
