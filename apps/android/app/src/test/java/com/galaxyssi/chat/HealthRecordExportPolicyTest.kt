package com.galaxyssi.chat

import com.univocity.parsers.csv.CsvParser
import com.univocity.parsers.csv.CsvParserSettings
import java.io.ByteArrayOutputStream
import java.io.StringReader
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import org.apache.commons.compress.archivers.zip.ZipFile
import org.apache.commons.compress.utils.SeekableInMemoryByteChannel
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HealthRecordExportPolicyTest {
    private val now = Instant.parse("2026-11-04T12:00:00Z").toEpochMilli()
    private fun id() = UUID.randomUUID().toString()
    private fun record(metric: HealthMetric = HealthMetric.GLUCOSE, value: String = "5.4", unit: String = metric.units.first()) =
        HealthObservationPolicy.observation(HealthDraft(metric, metric.requiredFields.associateWith { value }, unit, now - 1000), now)
    private fun session(format: HealthRecordExportFormat, records: List<HealthObservation>, annotations: Boolean = true) =
        HealthRecordExportSession(id(), HealthRecordExportScope(format = format, annotations = annotations), now,
            state = HealthRecordExportState.GENERATING, count = records.size.toLong(), rows = records.sumOf { HealthRecordExportRows.count(it).toLong() }, confirmedAt = now, preparedAt = now - 100)
    private fun bytes(format: HealthRecordExportFormat, records: List<HealthObservation>, annotations: Boolean = true, sheetRows: Int = 1_048_576): ByteArray {
        val s = session(format, records, annotations)
        return ByteArrayOutputStream().use { output -> HealthRecordExportFormats.open(s, output, sheetRows).use { writer ->
            records.forEachIndexed { index, record -> writer.append(HealthRecordExportItem(index + 1L, s.scope.snapshot(record), if (record.draft.evidence == null) HealthExportSourceStatus.NONE else HealthExportSourceStatus.MISSING)) }
        }; output.toByteArray() }
    }
    private fun csv(records: List<HealthObservation>, annotations: Boolean = true) = CsvParser(CsvParserSettings().apply {
        isHeaderExtractionEnabled = true; nullValue = ""; emptyValue = ""; ignoreLeadingWhitespaces = false; ignoreTrailingWhitespaces = false
        isNormalizeLineEndingsWithinQuotes = false; format.setLineSeparator("\r\n")
    }).parseAllRecords(
        StringReader(bytes(HealthRecordExportFormat.CSV, records, annotations).toString(Charsets.UTF_8).removePrefix("\uFEFF")))
    private fun entries(bytes: ByteArray): Map<String, String> = ZipFile(SeekableInMemoryByteChannel(bytes)).use { zip -> buildMap {
        val entries = zip.entries
        while (entries.hasMoreElements()) { val entry = entries.nextElement(); put(entry.name, zip.getInputStream(entry).use { it.readBytes().toString(Charsets.UTF_8) }) }
    } }
    @Test fun scopeRejectsMissingMetricsInvalidDatesAndUntrustedOriginalIds() {
        assertTrue(runCatching { HealthRecordExportScope(metrics = emptySet()) }.isFailure)
        assertTrue(runCatching { HealthRecordExportScope(from = -1) }.isFailure)
        assertTrue(runCatching { HealthRecordExportScope(from = 5, until = 5) }.isFailure)
        assertTrue(runCatching { HealthRecordExportScope(originalId = "../../wrong") }.isFailure)
        assertTrue(runCatching { HealthRecordExportScope(zone = "imaginary/zone") }.isFailure)
    }
    @Test fun scopeCalendarDatesRespectBothDstTransitions() {
        val zone = ZoneId.of("America/New_York")
        val spring = HealthRecordExportScope.dates(LocalDate.of(2026, 3, 8), LocalDate.of(2026, 3, 8), zone)
        val fall = HealthRecordExportScope.dates(LocalDate.of(2026, 11, 1), LocalDate.of(2026, 11, 1), zone)
        assertEquals(23 * 3_600_000L, spring.second - spring.first); assertEquals(25 * 3_600_000L, fall.second - fall.first)
    }
    @Test fun epochDayInEasternTimezoneAndReversedDatesAreHandledExplicitly() {
        val range = HealthRecordExportScope.dates(LocalDate.of(1970, 1, 1), LocalDate.of(1970, 1, 1), ZoneId.of("Asia/Shanghai")); assertEquals(0L, range.first)
        assertTrue(runCatching { HealthRecordExportScope.dates(LocalDate.of(2026, 2, 2), LocalDate.of(2026, 2, 1), ZoneId.of("UTC")) }.isFailure)
    }
    @Test fun anotherProfileIsNotSilentlyExportedAsSelf() {
        val scope = HealthRecordExportScope(); val other = record().copy(profileId = "other-person")
        assertFalse(scope.matches(other)); assertTrue(runCatching { scope.snapshot(other) }.isFailure)
    }
    @Test fun timeMetricAndOriginalFiltersIntersect() {
        val original = id(); val r = record().copy(draft = record().draft.copy(evidence = HealthEvidence(original, id(), "value", "a".repeat(64), 1, "", confirmed = true)))
        val scope = HealthRecordExportScope(setOf(HealthMetric.GLUCOSE), r.draft.measuredAt, r.draft.measuredAt + 1, originalId = original)
        assertTrue(scope.matches(r)); assertFalse(scope.copy(originalId = id()).matches(r)); assertFalse(scope.copy(metrics = setOf(HealthMetric.WEIGHT)).matches(r))
    }
    @Test fun annotationsAreOptInAndSourceIdentityRemainsAvailable() {
        val original = id(); val r = record().copy(draft = record().draft.copy(note = "private note", reference = "reported range", evidence = HealthEvidence(original, id(), "value", "a".repeat(64), 1, "private name", confirmed = true)))
        val safe = HealthRecordExportScope().snapshot(r)
        assertEquals("", safe.draft.note); assertEquals("", safe.draft.reference); assertEquals("", safe.draft.evidence!!.rawText); assertEquals(original, safe.draft.evidence!!.originalId)
        assertEquals(r, HealthRecordExportScope(annotations = true).snapshot(r))
    }
    @Test fun scopeAndSessionMetadataRoundTripWithoutMeasurementPayloads() {
        val s = session(HealthRecordExportFormat.JSON, listOf(record())); val json = s.json()
        assertEquals(s, HealthRecordExportSession.from(json)); assertFalse(json.has("records")); assertFalse(json.has("values"))
        assertEquals(s.scope, HealthRecordExportScope.from(s.scope.json()))
    }
    @Test fun csvDangerousLeadingCharactersHaveReversibleMarkers() {
        for (value in listOf("=1+1", " +SUM(A1)", "-1", "@cmd", "\ttext", "\rtext", "\ntext", "'literal", "\uFEFF=1", "\u00A0@cmd", "\uFF1D1", "\uFF0B1", "\uFF0D1", "\uFF20cmd")) {
            val safe = HealthCsvCellSafety.encoded(value); assertTrue(safe.second); assertEquals('\t', safe.first.first()); assertEquals(value, safe.first.drop(1))
        }
    }
    @Test fun safeNumbersAndOrdinaryUnicodeDoNotAcquireEscapePrefixes() {
        for (value in listOf("", "5.4", "<0.1", "120-130", "\u9634\u6027", "ordinary text", "  text")) assertEquals(value to false, HealthCsvCellSafety.encoded(value))
    }
    @Test fun bloodPressureComponentRowsShareOneIdentityAndUseTheRightUnits() {
        val r = HealthObservationPolicy.observation(HealthDraft(HealthMetric.BLOOD_PRESSURE, mapOf("systolic" to "16.2", "diastolic" to "10.4", "pulse" to "67"), "kPa", now - 1000), now)
        val rows = csv(listOf(r)); assertEquals(3, rows.size); assertEquals(setOf(r.id), rows.map { it.getString("observation_id") }.toSet())
        assertEquals("bpm", rows.single { it.getString("component") == "pulse" }.getString("component_unit"))
        assertTrue(rows.filter { it.getString("component") != "pulse" }.all { it.getString("component_unit") == "kPa" })
    }
    @Test fun optionalMissingPulseDoesNotBecomeAZeroResult() {
        val r = HealthObservationPolicy.observation(HealthDraft(HealthMetric.BLOOD_PRESSURE, mapOf("systolic" to "120", "diastolic" to "80"), "mmHg", now - 1000), now)
        assertEquals(2, csv(listOf(r)).size)
    }
    @Test fun comparisonsRangesAndLabelsAreNotInventedExactNumbers() {
        val records = listOf(record(HealthMetric.CRP, "<0.1"), record(HealthMetric.CRP, "1-2"), record(HealthMetric.URINE_PROTEIN, "negative", ""))
        val rows = csv(records); assertEquals(listOf("COMPARISON", "RANGE", "QUALITATIVE"), rows.map { it.getString("result_kind") })
        assertTrue(rows.all { it.getString("exact_number").isEmpty() }); assertEquals("<", rows[0].getString("comparison")); assertEquals("2", rows[1].getString("upper_bound"))
    }
    @Test fun exactTwentyDigitCountsAreNotRoundedThroughDouble() {
        val value = "99999999999999999999"; val rows = csv(listOf(record(HealthMetric.STEPS, value)))
        assertEquals(value, rows.single().getString("exact_number")); assertEquals(value, rows.single().getString("reported_value"))
    }
    @Test fun reportedDecimalNotationIsKeptAlongsideCanonicalNumber() {
        val rows = csv(listOf(record(value = "05,40")))
        assertEquals("05,40", rows.single().getString("reported_value")); assertEquals("5.4", rows.single().getString("canonical_value"))
    }
    @Test fun csvQuotesCommasNewlinesAndDoubleQuotesWithoutTruncation() {
        val text = "\u8bf4\u660e, one\r\n\"quoted\""; val r = record().copy(draft = record().draft.copy(note = text))
        assertEquals(text, csv(listOf(r)).single().getString("note"))
    }
    @Test fun csvPreservesCrLfLfAndLoneCrInTheActualQuotedBytes() {
        val text = "first\r\nsecond\nthird\rfourth"; val r = record().let { it.copy(draft = it.draft.copy(note = text)) }
        val raw = bytes(HealthRecordExportFormat.CSV, listOf(r)).toString(Charsets.UTF_8)
        assertTrue(raw.contains("\"$text\"")); assertEquals(text, csv(listOf(r)).single().getString("note"))
    }
    @Test fun formulaLikeNotesAreLiteralAndTheirOriginalTextCanBeRecovered() {
        val r = record().copy(draft = record().draft.copy(note = "=SUM(A1)")); val row = csv(listOf(r)).single()
        assertEquals("\t=SUM(A1)", row.getString("note")); assertTrue("note" in row.getString("csv_tab_escaped_fields").split(';'))
    }
    @Test fun jsonRetainsNestedObservationSemanticsAndDeclaresNoOriginalBytes() {
        val records = listOf(record(HealthMetric.CRP, "<1"), record(HealthMetric.URINE_PROTEIN, "trace", ""))
        val json = JSONObject(bytes(HealthRecordExportFormat.JSON, records).toString(Charsets.UTF_8))
        assertEquals(2L, json.getLong("observation_count")); assertFalse(json.getBoolean("contains_original_files")); assertEquals(1, json.getInt("version"))
        val array = json.getJSONArray("records"); records.forEachIndexed { i, r -> assertEquals(r, HealthObservation.from(array.getJSONObject(i))) }
    }
    @Test fun privateAnnotationsAreAbsentFromEveryFormatByDefault() {
        val r = record().copy(draft = record().draft.copy(note = "secret-patient-note"))
        assertFalse(bytes(HealthRecordExportFormat.JSON, listOf(r), false).toString(Charsets.UTF_8).contains("secret-patient-note"))
        assertEquals("", csv(listOf(r), false).single().getString("note"))
        assertTrue(entries(bytes(HealthRecordExportFormat.XLSX, listOf(r), false)).values.none { it.contains("secret-patient-note") })
    }
    @Test fun xlsxWritesInlineTextWithoutFormulaTagsOrFloatingPointLoss() {
        val r = record(HealthMetric.STEPS, "99999999999999999999").let { it.copy(draft = it.draft.copy(note = "=1+1")) }
        val xml = entries(bytes(HealthRecordExportFormat.XLSX, listOf(r))).filterKeys { it.startsWith("xl/worksheets/") }.values.joinToString("\n")
        assertTrue(xml.contains("99999999999999999999")); assertTrue(xml.contains("=1+1")); assertTrue(xml.contains("inlineStr")); assertFalse(Regex("<f(?:\\s|>)").containsMatchIn(xml))
    }
    @Test fun xlsxSplitsAtItsWorksheetRowLimitRatherThanDroppingRecords() {
        val records = (0..7).map { record(HealthMetric.STEPS, (it + 1).toString()) }
        val files = entries(bytes(HealthRecordExportFormat.XLSX, records, sheetRows = 4))
        assertEquals(4, files.keys.count { it.startsWith("xl/worksheets/sheet") && it.endsWith(".xml") })
        records.forEach { r -> assertTrue(files.values.any { it.contains(r.id) }) }
    }
    @Test fun xlsxFlushesBeyondOneThirtyRecordPageWithoutLosingRows() {
        val records = (0..94).map { record(HealthMetric.STEPS, (it + 1).toString()) }
        val xml = entries(bytes(HealthRecordExportFormat.XLSX, records)).values.joinToString("\n")
        records.forEach { assertTrue(xml.contains(it.id)) }
    }
    @Test fun sourceWarningsRemainExplicitInDataRows() {
        val r = record(); val item = HealthRecordExportItem(1, r, HealthExportSourceStatus.HASH_MISMATCH)
        val row = HealthRecordExportRows.rows(item).single(); assertEquals("HASH_MISMATCH", row[HealthRecordExportRows.headers.indexOf("source_status_at_preview")])
    }
    @Test fun explicitZeroSurvivesAndSourceTimestampsAreUtc() {
        val row = csv(listOf(record(HealthMetric.STEPS, "0"))).single(); assertEquals("0", row.getString("exact_number"))
        assertEquals(Instant.ofEpochMilli(now - 1000).toString(), row.getString("measured_at_utc")); assertEquals((now - 1000).toString(), row.getString("measured_at_epoch_ms"))
    }
}
