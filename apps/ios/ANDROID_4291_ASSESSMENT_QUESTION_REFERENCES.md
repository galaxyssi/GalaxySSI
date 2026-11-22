# Android #4291: assessments linked to retained questions

Reference: galaxyssi/GalaxySSI#4291, merge
`412bb2db8a96af7cb68d65d93f33f0b4a643fff6`.

## Contract and validation

- Every new assessment submission includes `questions`, an array of at most 30
  unique UUID/positive-integer revision references. `CLARIFY` requires at least
  one; other decisions may use an empty array. Legacy encrypted inputs decode
  with no references and are not rewritten or retroactively rejected.
- Question pages and proposal receipts expose exact identifiers. The review
  recorder looks up each current row directly in the concern's encrypted ledger,
  not just the first page. It checks sharing consent, profile/measurement scope,
  exact revision, current source basis and current known facts. Only OPEN and
  explicitly CONFLICT rows are eligible; answered, deferred, declined, stale,
  invented or outside-scope rows fail without inventing an answer.
- Invalid references use the existing correctable bounded cloud tool feedback.
  Scope/permission changes still fail closed. Assessment receipts return the exact
  stored references and `questions_created=false`. The recorder never substitutes
  or inserts a missing reference.

## Paired read-only adaptation

The existing iOS paired Health channel returns a supervised final envelope, not
Android's interactive native-tool session. To keep this flow usable with exact
references, a newly proposed question in that envelope declares a unique UUID
along with key/question/purpose. Initial revision is one. The phone validates the
proposal and namespace, persists it, then independently validates the assessment
against the actual retained row. Existing questions must be cited using the IDs
and revisions from the authorized question page, with no replacement proposal.

Declared IDs are creation identifiers, not permission tokens. Cloud question
proposals still receive host-generated IDs. The paired path rejects duplicate
IDs/keys, collisions with any retained concern namespace, changed content under
an existing ID, reuse of another turn's question, or a known fact disguised as a
new question. A reference with no accepted retained row is rejected even when
another valid proposal was saved. Successful proposal storage does not guarantee
assessment acceptance; an invalid final assessment leaves the saved questions
unanswered and commits no final reply/assessment.

This is a platform-specific ordered batch adaptation. It does not implement
interactive paired tool-error correction or on-demand paired history paging;
those earlier protocol parity gaps remain outstanding. No Desktop execution or
filesystem permission is added.

## UI

The existing assessment shows a localized question-count action. Its scoped sheet
loads only the referenced IDs and rereads current answer states/revisions, so a
historical assessment can open the user's now-answered question. Missing or changed
scope fails instead of falling back to the full question list. Existing answer,
defer, decline and reopen controls are reused. The parent assessment and selected
question surface clear/dismiss on background, profile change or protected-data
loss. The Agent main-page layout is unchanged.

## Verification limits

Added isolated XCTest sources cover strict shape/duplicates/revisions, retained
OPEN/CONFLICT input, stale/resolved/known-fact/scope rejection, current answer
display, references beyond page one, legacy decode, paired creation order,
namespace/ID hijack rejection and actual cloud error/proposal/corrected-review
continuation. Existing synthetic fixtures and paired-envelope tests were updated
for the new contract, not silently backfilled by production code.

Windows checks are project structure, changed Swift grammar, localization
placement and diff/merge checks. XCTest, Swift type-checking, simulator/device UI,
real-provider semantics and IPA acceptance were not executed. These sources are
not a claim that Android's real paired acceptance ran on iOS.
