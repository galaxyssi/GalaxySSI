# Desktop Executable Resource Gate

## Finding And Change

The previous Windows packaging flow merely warned when `rcedit` was missing or
resource writing failed, then printed a successful package message. Earlier
v1.2.0 package evidence therefore correctly noted that Explorer could still
show Electron's version/product metadata.

Packaging now validates the source package version and resolves its resource
tool before building the sidecar, stopping a packaged process or deleting the
old output. The already-declared `rcedit` dev dependency is required, or an
explicit `RCEDIT_EXE` must point to its executable. A missing explicit override
does not silently select a different tool. Both bundled binary names and both
existing dependency installation layouts are recognized.

Resource writing must succeed. A separate Windows `FileVersionInfo` read then
checks every expected field before packaging can print success. The query is
read-only, receives the filename as environment data, and does not interpolate
it into PowerShell code or alter PowerShell execution policy. It runs hidden.
This is a version/resource gate, not a code-signing or complete installer gate.

## Verification

- Seven focused tests pass, including missing tools, explicit overrides, version
  bounds, literal paths, write/readback failures, metadata mismatch and preflight
  ordering ahead of stopping the installed app.
- The standard Desktop check command now includes these cases: 44 tests and the
  structure check passed. The final ordering assertion was independently rerun.
- `rcedit@5.0.1` was fetched outside the repository into
  `C:/Users/agent/MQTTDiagnostics/20260913-package-tools`. Its archive SHA-512
  matched the existing Desktop lockfile integrity exactly; no dependency or
  lockfile version was changed.
- A copied Electron executable was modified at
  `build/windows-resource-smoke-v1/owned's folder/GalaxySSI Desktop.exe`.
  The path deliberately includes spaces and an apostrophe. The real tool wrote
  resources/icon and the independent native readback passed:

| Field | Readback |
| --- | --- |
| FileVersion | 1.2.0.0 |
| ProductVersion | 1.2.0 |
| ProductName | GalaxySSI Desktop |
| FileDescription | GalaxySSI Desktop super agent and mobile gateway |
| CompanyName | GalaxySSI |
| OriginalFilename | GalaxySSI Desktop.exe |
| LegalCopyright | Copyright GalaxySSI contributors |

The source Electron binary still reports FileVersion 31.7.7 / ProductName
Electron. Only the isolated copy was modified. No executable was launched.
The first readback attempt used a new unsigned `.ps1` file and was rejected by
the host's script policy. That proposed file was removed; the final approach
uses the standard read-only command query without changing system policy.

## Remaining Release Work

This does not deploy or rebuild the full production Desktop package, start its
backend, or complete coordinated Android/Desktop acceptance. The existing
packaging command can stop its own deployed package, so it was deliberately not
run during this isolated resource check. The final package must still pass
the new resource gate along with runtime, pairing, task and artifact acceptance.
The full PR #3045 scope and device/performance/resource gates remain active.
