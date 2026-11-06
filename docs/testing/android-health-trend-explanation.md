# Android Health filtered trend explanation

The trend page opens Health Assistant with the exact metric, date range, time
zone, source, unit, aggregation, and record version of the chart. The assistant
shows that scope before reading measurements and does not widen it to a weekly
report or add profile details. If the chart is stale, the user must return to
the trend and open the current chart.

The local explanation uses the same numeric buckets as the chart. It shows the
first and last plotted values, their difference when at least two points
exist, coverage, and exclusions. A single point is not presented as a zero
change. Evidence links open the same version-pinned contributor cohorts and
original record revisions as the trend audit.

Online use remains optional and requires the same destination and exact-payload
confirmation as other Health Assistant requests. Only relative bucket indices,
summary values, counts, metric, unit and aggregation are included for the
trend. No record identifiers, dates, source identifiers, notes, original bytes
or profile fields are included. A follow-up also includes its confirmed
question and the preceding structured answer, when present. Record and privacy
changes invalidate pending work, and the encrypted audit records the source
class, local period, destination and outcome without retaining the question.

Regression coverage includes the actual chart-to-assistant route, a filtered
minimum and its exact original revision, stale consent cancellation, a
synthetic model exchange checked against the consent payload, and the existing
weekly assistant. The fixture never sends data to a real provider.
