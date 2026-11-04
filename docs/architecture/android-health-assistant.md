# Android Health Assistant

The assistant is available from Health Center and its function menu. The user
chooses a week ending on a completed calendar day, a subset of supported
metrics, and one of three questions: changes, coverage, or next records. A
changes request can include the preceding 14 days of sleep measurements for
comparison. The screen discloses this scope before calculation.

The existing weekly calculation reads confirmed self records in bounded pages.
It does not fill missing days with zeros or infer diagnoses from observations.
The result links representative records using exact revision IDs; these are
examples from the aggregate, not its entire cohort. Computed aggregates, source
references, and their versions are retained only in the foreground result. A record or policy
change invalidates it and dismisses any outstanding disclosure prompt.

Online analysis is off by default. It requires the health privacy policy and
a fresh confirmation for the selected Provider and minimized summary. The
request contains coverage, short temporary fact IDs, and only the aggregate
values needed by the selected question. It excludes record IDs, calendar
dates, personal profiles, raw values, originals, notes, and conversation
history. Health and general disclosure journals record authorization metadata,
not the request body. The dedicated HTTPS request has no tools, redirect
following, automatic retry, or Provider failover. The policy, record revision
and destination are checked again before writing the request body. Revoking
authorization cannot retract bytes already received by a Provider, but it
cancels the request and suppresses the obsolete result.

The Provider may prioritize known facts and select from the available local
next steps. Android verifies each ID and keeps the numeric result on-device;
unknown facts, unsupported actions, and unexpected output are rejected. No
model recommendation is executed automatically. The assistant is not
free-form medical chat and does not send health content into Agent history.
