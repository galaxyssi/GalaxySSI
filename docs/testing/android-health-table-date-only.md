# Android Health date-only table review

CSV, JSON and XLSX table mapping can use a date-only value in the explicitly
selected date format. A valid date without a selected time is counted as
missing. Invalid calendar dates remain format errors. The time picker never
automatically selects midnight. Offset-bearing values retain their source
offset; other local values use the mapping's time zone. Ambiguous or
nonexistent DST times remain invalid unless the source supplies an offset.

The preview marks only the rows that use the selected time. Their saved source
evidence includes the unchanged source date, resolved timestamp, and the
explicitly chosen time. Complete timestamps are not overwritten. No records
are saved before the separate ownership and source confirmation.

`HealthTableDateOnlyPolicyTest` covers accepted date formats, explicit
midnight, offsets, invalid dates, and DST boundaries.
`HealthTableDateOnlyDeviceTest` uses isolated encrypted records and actual
WorkManager operations to exercise the native picker, row detail, screen
recreation, validation counts, source consent, idempotent save, and a
confirmed undo that keeps unrelated records. It also stages a JSON file and
checks that typed comparison/range results and their reported references
survive save. `-e tableDateScreenshot true` captures the synthetic preview.
