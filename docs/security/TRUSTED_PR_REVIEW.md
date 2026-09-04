# Trusted automated pull request reviews

GalaxySSI treats an automated pull request approval as a privileged action. Human reviews continue
to use the repository's normal review policy. Automated approvals are accepted only when all of
the following are true:

- GitHub identifies the reviewer as a `Bot`, not a user account used by a script.
- The exact bot login is listed in `.github/trusted-pr-review-policy.json`.
- The review commit matches the current pull request head.
- Every required check exists.
- Every observed check and legacy commit status is complete and successful. Neutral and skipped
  checks are accepted only because the policy lists them explicitly.

An untrusted, stale, or premature bot approval is dismissed through the GitHub review API and the
workflow fails. The bot can submit a new review after the current head has green CI.

The workflow checks out the repository default branch rather than pull request code. A pull request
therefore cannot change the evaluator or allowlist used to judge its own review. Changes to the
trusted bot list require a separate, human-reviewed repository change.

The policy does not merge pull requests and does not grant a bot permission to bypass repository
rules. Automatic merge remains disabled.

Run the policy regression suite with:

```bash
npm run test:trusted-pr-review
```
