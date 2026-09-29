# Office layout and localized metadata regression

## Real failure and cause

The Active3 A006 warehouse XLSX baseline kept correct arithmetic but produced
clipped charts in versions 3 through 6. Read-only inspection of v06 found the
calculation sheet print area at `A1:D31`, while its two-cell chart anchor ended
in zero-based column 4 with a positive offset: beyond the D-column print edge.
The received PNG visibly truncates the chart's right side. Earlier versions 1
and 2 fit their explicit print areas. Currency inference is a separate defect.

## Desktop 1.3.27 change

`galaxyssi_office_preview` now returns `layout_check` alongside conversion and
page coverage. It inspects bounded package XML and existing static print ranges
without loading workbook values into a mutable spreadsheet or saving the source.
The Agent contract requires inspecting issues, repairing unintended clipping in
the original, and re-rendering before claiming a clean layout. Deliberate user
template cropping must be disclosed, not silently changed by the preview tool.

The check is deliberately limited to explicit rectangular XLSX print areas and
two-cell drawing anchors. It handles zero-based/exclusive edges, offsets,
disjoint print areas, quoted sheet names, hidden sheets and non-printing drawings.
Dynamic ranges, missing areas, other anchors and unsupported/oversized XML remain
unverified. A drawing must fit a single intended print area. Diagnostics never
certify typography, units, formulas, bar baselines or visual correctness.
`complete_preview` still means page coverage only; a successful conversion may
have `layout_check.status = issues_found`. Original bytes are preserved.

## Additional actual conversion failure fixed

An isolated real Microsoft Office conversion under Python UTF-8 mode failed
after PDF export because localized `pdfinfo` metadata included non-UTF-8 bytes.
The subprocess reader raised UnicodeDecodeError; missing stdout then caused a
TypeError during page-count matching. Page-count detection now reads bytes and
matches only the ASCII `Pages:` field. Unknown metadata/output remains unknown
coverage, not a guessed page count. Office worker diagnostic decoding also uses
replacement for undecodable bytes so its reader thread cannot crash. Process
ownership and cleanup rules are unchanged.

## Verification

- 125 isolated backend tests pass, including 12 layout regressions and two
  localized/missing metadata tests; 61 Desktop JavaScript tests pass.
- Read-only checks against all six actual received A006 workbooks detect the
  observed bounds defect in turns 2-5, with no bounds issue in turns 0-1.
- The same received v06 was copied to a separate temporary task workspace and
  rendered with the real Microsoft Office worker. After the encoding fix it
  returned 3 PDF pages and 3 PNG previews, with the expected clipping diagnostic.
- The unchanged native source SHA-256 is
  `2faf0063962db4b44661803d69bbf11f505c8eb92a3de179ad0c395aeaf57e80`.
  PNG pages 1 and 2 are byte-identical to the phone's received previews. Page 3
  was visually inspected and retains the correct total 556 and unconfirmed fields.
- No returned workbook or historical phone test report was edited. The live
  Desktop process remains on 1.3.23. This verifies real local conversion and
  diagnostics, not deployment, Agent self-repair, MQTT recovery, or the missing
  phone attachment. The full 100-case / 1100-turn campaign remains incomplete.
