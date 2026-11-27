# Android #3038: bounded knowledge SQLite statement reuse

Android merge: `6e303ed067c0f2fb5ae4310ac229b8e32cb428d8`.
Incremental predecessor: iOS #4601 at
`bfcd499370441adfa07ff6361e422e4bb997b1ac`, including #4600 and #4596.
The PR targets main with shared ancestor commits. Its full-main scope includes
physical primary partitions, allocation recovery, leases, periodic maintenance
and checked synchronization, not only this statement-reuse increment.

## Prepared-source/read-view integration follow-up

This branch now also includes updated #4596 at `a5d92e61c`, which shares #4625
and its #4623/#4621/#4619/#4616 ancestry. The complete main diff includes those
prepared source, streamed observation/import, committed lexical/vector read
and timing prerequisites. They are not newly implemented #3038 features. The
base remains main; no prerequisite merge, approval or duplicate PR is required.

Route the newly added committed read-view and encrypted source-staging prepares,
returns and teardown through the same registry. Reapply the lifetime adapter to
every new catalog call site while preserving the newer read admission, lifecycle,
generation fence, physical batch and observation rules. This is not a reversion
to the older writer-locked queries to make statement reuse easier.

Private read views close with explicit `finalizingUnmanaged: true`: the registry
first invalidates/removes its loans, drains tracked active/idle/direct programs,
then finalizes any remaining raw cursors and closes SQLite before the view drops
its physical retention lease. Ordinary registry close defaults to false and does
not finalize an unrelated standalone pool's statements. This opt-in is valid
only for exclusively owned private handles, not a generic cursor-sharing API.
Source staging marks a throwing callback's statement failed before return, so
SQL/binding/authentication/caller failures cannot leave that program retained.

Five additional synthetic methods cover owned mixed-program teardown, generic
close preserving an unrelated standalone lease, reuse of the actual read-view
initialization query, staging identity/binding isolation and rescan after callback
failure. The statement suite now has nineteen authored methods, not executed.
Together with the primary/source prerequisites and allocation/durability suites,
163 methods remain authored only, not native passing results.

Retained-source guards pin updated #4596 for the new read/staging/catalog code,
and the original #4601 for unchanged partition/allocation/durability sources.
The catalog's declared checked durability configuration is retained explicitly.
Full project comparisons account for all inherited registrations; full-file SQL,
schema, transaction, crypto and generation checks remain, with only declared
cache lifetime hooks reversed for older guards. Native APIs are not substituted
by static assertions as acceptance evidence.

## Actual production wiring

Route every prepare/return/connection-close in AgentKnowledgeDatabase,
AgentKnowledgePrimaryPartitions, AgentKnowledgePrimaryAllocations and
AgentKnowledgePrimaryDurability, plus AgentKnowledgeCommittedReadView and
AgentKnowledgeSourceStaging through the connection-local registry.
Keep SQL text, parameter values, getters, stepping, transactions, schemas,
encryption, reader slots and file leases unchanged. Preserve sqlite3_exec,
including its multi-statement semantics. Two existing test owners now use the
same managed connection close so idle statements cannot outlive teardown.

Each connection keeps at most 32 idle statements and 65,536 UTF-16 SQL units.
An exact-SQL hit takes exclusive ownership; simultaneously active identical
queries receive different statements. On return, reset results and clear
bindings before retaining a statement. Keep one idle entry per SQL, evicting
oldest-returned entries to satisfy both budgets. Reject negative bounds; zero
capacity and oversized SQL remain executable without idle retention. Active
leases, total connections, native program memory and RSS are not bounded by
these idle-cache limits. The cache is connection-scoped, not shared across
encrypted namespaces or database handles.

Discard entries after a throwing lease callback, explicitly marked bind failure,
failed SQLite reset/clear or pool closure. Production string/blob bind helpers
mark their existing failure paths without changing their return/throw behavior.
The adapter retains native SQLite prepare error codes and the empty-SQL nil
statement convention. Explicit byte-span/tail requests use uncached native
prepare and tracked finalization. Standalone lease close is idempotent and a
closed pool rejects later access; active native statements are finalized on
lease return. Managed connection close drains its own outstanding raw borrows
and idle entries before closing SQLite. Raw pointers must not escape the
existing serialized connection-owner scopes; this is not a new concurrent raw
cursor API or permission to use a pointer after connection close.

## Deliberate iOS adaptation

Retain only ordinary SELECT/INSERT/UPDATE/DELETE/REPLACE programs. PRAGMA, DDL,
transaction control and unrecognized leading keywords remain uncached. Some
SQLite pragmas act during preparation; the durability policy therefore keeps
freshly prepared configuration/readback instead of retaining PRAGMA programs.
No SQL rewriting or general SQL parser is introduced.

SQLite documents that [reset](https://www.sqlite.org/c3ref/reset.html) does not
clear bindings and can report the previous execution failure; use
[clear_bindings](https://www.sqlite.org/c3ref/clear_bindings.html) separately and
check both results. [close_v2](https://www.sqlite.org/c3ref/close.html) alone may
defer database destruction while statements remain, so managed teardown drains
its tracked statements explicitly. These lifetime contracts are not proof of
performance improvement or hardware durability.

## Verification limits

Fourteen original synthetic Swift test methods authored and registered, not compiled or
executed: reset/NULL binding reuse, concurrent identical cursors, entry LRU,
SQL budget/oversize, UTF-16 counting, zero/invalid bounds, throwing callback,
execution failure, close/late lease return, stale lease isolation, fresh PRAGMA
and transaction programs, managed close with an outstanding raw borrow,
empty/invalid/byte-span SQL and marked binding failure, plus real primary-store
read calls observing the production registry's reuse counter. Together with
the original 56 inherited methods, that earlier review contained 70 authored
methods. The integrated totals and five new cases are described above; none is
claimed as native acceptance.

The scoped source guard pins the predecessor, reverses only declared mechanical
lifetime-routing and bind-failure hooks, and requires all surrounding production
and existing fixture bytes to match. The previous allocation, durability and
primary guards retain their assertions through a checked normalization hook.
Source verification covers those four guards, JavaScript syntax, iOS project
structure, changed-source literal-Han placement and diff whitespace. No native
compile/typecheck, SQLite/XCTest execution, real-device/process-death evidence,
CI monitoring, IPA, approval or merge. No full Android parity, speedup, bounded
total memory or all-repository check pass is claimed.
