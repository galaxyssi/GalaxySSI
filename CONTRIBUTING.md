# Contributing

Thank you for contributing to GalaxySSI.

Keep each pull request focused on a single change so it can be reviewed and verified efficiently.

The current repository release is v1.0.0. Keep platform package versions aligned for coordinated releases.

## Rules

- Use English for code, comments, documentation, commits, pull requests, and release notes.
- Put user-visible localized strings in the proper i18n resource files.
- Do not commit secrets, local device state, generated packages, logs, databases, or temporary screenshots.
- Keep protocol changes documented under `docs/protocol`.
- `npm run check` rejects tracked generated artifacts such as APKs, installers, smoke screenshots, UI dumps, local databases, logs, and pairing state.

## Pull request checks

Run the following commands from the repository root.

Before opening a pull request, run the checks relevant to your change and note any skipped checks and the reason in the pull request:

```bash
npm run check
npm run check:android
npm run smoke:android:ui
npm run smoke:android:friends
npm run smoke:android:background
npm run smoke:desktop
npm run smoke:desktop:e2e
npm run smoke:desktop:packaged
```

Smoke commands that touch the Desktop backend, MQTT broker, packaged app, or Android device must run sequentially because they share the same local backend port and test lock.

Use `docs/testing/README.md` as the release test matrix before publishing a build.

### Focused Node.js tests

When changing a standalone Node.js utility, run its colocated test directly with `node --test path/to/file.test.mjs` before broader checks.
