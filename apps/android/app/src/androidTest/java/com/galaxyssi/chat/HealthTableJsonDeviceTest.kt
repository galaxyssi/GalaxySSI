package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class HealthTableJsonDeviceTest {
    private fun parse(text: String): Pair<List<String>, List<HealthTableRow>> {
        val rows = arrayListOf<HealthTableRow>()
        return HealthTableParser.read(text.byteInputStream(), "json", rows::add) to rows
    }
    @Test fun numbersNullAndUnicodeStayInTheirOriginalColumns() {
        val (headers, rows) = parse("""[{"日期":"2026-09-01T08:00:00Z","高压":124.50,"低压":null},{"日期":"2026-09-02T08:00:00Z","单位":"mmHg"}]""")
        assertEquals(listOf("日期", "高压", "低压", "单位"), headers)
        assertEquals("124.50", rows[0].cells["高压"]); assertEquals("", rows[0].cells["低压"])
        assertFalse(rows[1].cells.containsKey("高压")); assertEquals(2L, rows[1].number)
    }
    @Test fun nestedArraysAndObjectsAreFlaggedNotConvertedIntoMedicalValues() {
        val rows = parse("""[{"value":{"nested":124}},{"value":[124,82]}]""").second
        assertTrue(rows.all { it.issue == "nested" }); assertTrue(rows.all { it.cells["value"] == "" })
    }
    @Test fun nonObjectRowsAreKeptAsInvalidRatherThanRenumberingTheFollowingRows() {
        val rows = parse("""[null,1,{"value":124}]""").second
        assertEquals(listOf(1L, 2L, 3L), rows.map { it.number }); assertEquals("object", rows.first().issue)
    }
    @Test fun duplicatePropertiesAreRejectedInsteadOfOverwritingSourceValues() {
        assertTrue(runCatching { parse("""[{"value":120,"value":140}]""") }.isFailure)
    }
    @Test fun backupsTrailingContentAndMalformedJsonAreRejected() {
        for (text in listOf("""{"records":[]}""", "[]", "[{", """[{"value":1}] {}""")) assertTrue(text, runCatching { parse(text) }.isFailure)
    }
    @Test fun oversizedCellsAndColumnSetsAreRejectedExplicitly() {
        assertEquals("table_cell", (runCatching { parse("""[{"note":"${"x".repeat(16_385)}"}]""") }.exceptionOrNull() as HealthImportFailure).code)
        val text = "[{" + (1..257).joinToString(",") { "\"c$it\":1" } + "}]"
        assertEquals("table_columns", (runCatching { parse(text) }.exceptionOrNull() as HealthImportFailure).code)
    }
    @Test fun escapedQuotesAndLinebreaksAreDecodedButNeverExecuted() {
        val value = parse("""[{"note":"a\n\"b\"","value":"=1+1"}]""").second.single()
        assertEquals("a\n\"b\"", value.cells["note"]); assertEquals("=1+1", value.cells["value"])
    }
}
