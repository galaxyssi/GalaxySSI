package com.galaxyssi.chat

import java.io.ByteArrayInputStream
import org.junit.Assert.*
import org.junit.Test

class HealthTableCsvParserTest {
    private fun parse(value: String): Pair<List<String>, List<HealthTableRow>> {
        val rows = mutableListOf<HealthTableRow>()
        val headers = HealthTableParser.read(value.byteInputStream(), "csv", rows::add)
        return headers to rows
    }
    @Test fun quotedCommasAndEmbeddedNewlinesAreSingleCells() {
        val (headers, rows) = parse("time,note\r\n2026-09-01,\"first,second\nthird\"\r\n")
        assertEquals(listOf("time", "note"), headers); assertEquals(1, rows.size)
        assertEquals("first,second\nthird", rows.single().cells["note"])
    }
    @Test fun escapedQuotesAreNotNaivelySplit() {
        assertEquals("said \"hello\"", parse("note,value\n\"said \"\"hello\"\"\",5\n").second.single().cells["note"])
    }
    @Test fun semicolonAndTabDelimitersKeepDecimalCommas() {
        assertEquals("5,4", parse("time;glucose\n2026-09-01;5,4\n").second.single().cells["glucose"])
        assertEquals("5.4", parse("time\tglucose\n2026-09-01\t5.4\n").second.single().cells["glucose"])
    }
    @Test fun tooManyCellsAreRetainedAsAnInvalidRowNotShifted() {
        val result = parse("a,b\n1,2,3\n").second.single()
        assertEquals("columns", result.issue); assertEquals(mapOf("a" to "1", "b" to "2"), result.cells)
    }
    @Test fun absentCellsStayEmpty() { assertEquals("", parse("a,b\n1\n").second.single().cells["b"]) }
    @Test fun sourceWhitespaceAndHashPrefixedRowsAreNotSilentlyDiscarded() {
        val rows = parse("note,value\n  before breakfast  ,124\n#retained,125").second
        assertEquals("  before breakfast  ", rows[0].cells["note"]); assertEquals("#retained", rows[1].cells["note"])
    }
    @Test fun duplicateOrEmptyColumnNamesAreRejected() {
        for (text in listOf("a,a\n1,2", "a,\n1,2")) assertTrue(text, runCatching { parse(text) }.isFailure)
    }
    @Test fun invalidUtf8IsNotSilentlyReplaced() {
        assertTrue(runCatching { HealthTableParser.read(ByteArrayInputStream(byteArrayOf(0xc3.toByte(), 0x28)), "csv") {} }.isFailure)
    }
    @Test fun bomWorksEvenWhenTheStreamReturnsOnlyOneBytePerRead() {
        val bytes = byteArrayOf(0xef.toByte(), 0xbb.toByte(), 0xbf.toByte()) + "time,value\nnow,4".toByteArray()
        val stream = object : ByteArrayInputStream(bytes) {
            override fun read(b: ByteArray, off: Int, len: Int) = super.read(b, off, minOf(len, 1))
        }
        assertEquals(listOf("time", "value"), HealthTableParser.read(stream, "csv") {})
    }
    @Test fun utf16BomIsHandledWithoutChangingUnicodeColumnNames() {
        val text = "日期,高压\n2026,124"
        for ((charset, prefix) in listOf(Charsets.UTF_16LE to byteArrayOf(-1, -2), Charsets.UTF_16BE to byteArrayOf(-2, -1))) {
            assertEquals(listOf("日期", "高压"), HealthTableParser.read(ByteArrayInputStream(prefix + text.toByteArray(charset)), "csv") {})
        }
    }
    @Test fun parserDoesNotEvaluateFormulaCells() { assertEquals("=100+24", parse("value\n=100+24\n").second.single().cells["value"]) }
    @Test fun largeRowsAreRejectedBeforeBuildingAnUnboundedPendingChunk() {
        val header = (1..8).joinToString(",") { "c$it" }
        val row = (1..8).joinToString(",") { "x".repeat(9000) }
        assertEquals("table_row", (runCatching { parse("$header\n$row") }.exceptionOrNull() as HealthImportFailure).code)
    }
    @Test fun unsupportedTypeIsNotMisreportedAsCsv() {
        assertNull(HealthTableParser.format("table.xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"))
        assertEquals("csv", HealthTableParser.format("TABLE.CSV", "application/octet-stream"))
        assertEquals("json", HealthTableParser.format("data", "application/json"))
    }
}
