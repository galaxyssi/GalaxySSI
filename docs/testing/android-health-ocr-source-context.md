# Android OCR source context review

The OCR review and item editor show labeled names and collection or
measurement times from the same recognized page. They do not infer
identity, read unrelated report dates as collection times, or copy the
new source context into confirmed records or the profile. The item editor reads the
authenticated source page using the selected evidence, not an intent
containing OCR text.

A single complete time may be applied explicitly. The action identifies
the source UTC offset or the device time zone used for a local timestamp.
Date-only values, conflicting values, multiple names, invalid times,
and ambiguous daylight-saving times require manual verification. A
future time is not offered for application. Unknown units remain unset.

Applying a time only changes the editor and clears the prior confirmation.
The user must verify their ownership, values, unit and measurement time.
Completing item review writes an encrypted draft and refreshes the
parent review page. No measurement is created until the selected items
receive separate batch consent.

Android 0.1.7.83 passed 25 focused JVM tests and 23 Tab Active3
instrumentation tests, with no skips. The new device cases use synthetic
source pages and isolated databases. They verify the two-step save,
source-offset handling, unknown-unit exclusion, and rejection of
conflicting times until a manual time is entered. They do not establish
OCR accuracy on real medical reports.
