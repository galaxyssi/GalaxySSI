# Reference 4697: Chinese Export Intent

Reference: Desktop-only PR #4697 at
256c8c76b17c43988bfa7e4e6967d52421f31e94, stacked on #4696. Android is
unchanged in that PR. This independent iOS port starts from main
c6bad3465c673dfb2dcecb23b095185c129c7447 and does not import that stack.

The iOS execution profile had the same substring error: the export suffix of
the Simplified/Traditional Chinese verb for derive could require a new file.
Skip only that occurrence in positive term scanning and in the PDF creation
expression. Continue scanning so a separate, unnegated export in the same
request still requires its file. Support direct Simplified and Traditional
export forms. Preserve quoted-field filtering, English word boundaries,
negation, plan-only mode and independent build/install/artifact requirements.

Production changes are confined to AgentExecutionPolicy.swift. No task executor,
artifact verifier, filesystem path policy, file-delivery proof, permission,
transport, model route, Android/Desktop source or version number is changed.
Do not treat a structured answer as proof of a requested file. This change
corrects request classification, not artifact generation or verification.

Eight Swift fixture methods cover inference from existing PDF/Excel/CSV sources,
direct exports, mixed and repeated occurrences, negated exports, quoted fields,
English boundaries, plan-only and independent output requirements. They are
authored, not compiled or executed. A separate JS source contract checks the
exact policy delta and synthetic extracted grammar cases; its JS regex engine
and modeled term scan are not Swift/ICU or app execution evidence.

No Swift/native build, XCTest, simulator/device/model/socket test, full repository
check, CI inspection, IPA, private evidence upload, remote approval or merge is
performed. Native classification and end-to-end delivery acceptance remain
unverified.
