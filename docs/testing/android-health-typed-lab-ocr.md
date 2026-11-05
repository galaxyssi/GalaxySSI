# Android typed lab OCR

Complete labeled report rows can produce comparison, range, or
recognized qualitative suggestions using the existing result model.
The same parser covers supported laboratory metric names, units and
selected unambiguous aliases. A source row and its regions remain the
evidence, including row numbers, high/low flags and original notation.
The parser does not interpret those flags or infer a diagnosis.

An explicitly separated and labeled reference field is distinct from the
result. Ambiguous trailing values are not extracted, and missing or
competing units remain unset. Urine protein accepts recognized labels
or grades, not arbitrary text or quantitative concentrations. Unknown
units, unresolved times and unconfirmed ownership cannot be bypassed by
the result type. Reviewed items still require separate batch consent.

Confirmed comparison, range and qualitative results retain their display
and source text. Only exact numbers are eligible for numeric aggregation.
The regression fixtures use synthetic OCR lines and do not establish
recognition accuracy for real laboratory layouts.

Android 0.1.7.84 passed 74 focused JVM tests and 37 Tab Active3
instrumentation tests with no skips. The native flow confirms a selected
batch, keeps its unresolved-unit row as a draft, verifies the saved
catalog text, and tests that the numeric trend selects only the exact
glucose value from three different result types.
