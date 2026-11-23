# Restore Atlas Illustration Integration

The original foundation PR #4428 merged head `e52cfa7e8`, not the subsequent
`da25f5d31` illustration-loader update. Pushing to its old branch did not deliver
that update to main. This formal main-based follow-up carries the missing changes
and the compatible typed public-illustration context API from `86366bee6`.

- Validate/load the optional #4328 system plate pack without replacing the graph.
- Preserve canonical visible-target routing, trusted OpenStax sources and old plate decoding.
- Show the selected illustration reference on Structure/Function.
- Share captions, schematic limitation and reference with the public confirmation.
- Keep Values and whole-body early returns free of illustration context.
- Supply both-language shared plate-context formatting without requiring another pack.

No Android/Desktop files or new feature numbering are included. This repairs the
missing delivery of already implemented atlas integration used by subsequent resource PRs.
Static structure/resource/grammar checks and regression source are included.
No Xcode build, XCTest execution, simulator or device acceptance is claimed.
