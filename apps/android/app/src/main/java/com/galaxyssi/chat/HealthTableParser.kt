package com.galaxyssi.chat

import android.util.JsonReader
import android.util.JsonToken
import com.univocity.parsers.csv.CsvParser
import com.univocity.parsers.csv.CsvParserSettings
import java.io.InputStream
import java.io.InputStreamReader
import java.io.PushbackInputStream
import java.io.Reader
import java.nio.charset.CodingErrorAction

/** Streaming adapters retain source cells; they never execute spreadsheet formulas or infer measurements. */
internal object HealthTableParser {
    const val MAX_BYTES = 64L * 1024 * 1024
    private const val MAX_COLUMNS = 256
    private const val MAX_CELL = 16_384
    private const val MAX_ROW = 65_536
    fun format(name: String, mime: String): String? = when {
        name.endsWith(".xlsx", true) || mime == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" -> "xlsx"
        name.endsWith(".csv", true) || mime in listOf("text/csv", "application/csv") -> "csv"
        name.endsWith(".json", true) || mime == "application/json" -> "json"
        else -> null
    }
    internal fun <T> text(input: InputStream, block: (Reader) -> T): T {
        val source = PushbackInputStream(input, 3)
        val prefix = ByteArray(3); var count = 0
        while (count < prefix.size) { val n = source.read(prefix, count, prefix.size - count); if (n < 0) break; if (n > 0) count += n }
        val charset = when {
            count >= 2 && prefix[0] == 0xff.toByte() && prefix[1] == 0xfe.toByte() -> Charsets.UTF_16LE
            count >= 2 && prefix[0] == 0xfe.toByte() && prefix[1] == 0xff.toByte() -> Charsets.UTF_16BE
            else -> Charsets.UTF_8
        }
        val skip = if (charset != Charsets.UTF_8) 2 else if (count == 3 && prefix.contentEquals(byteArrayOf(0xef.toByte(), 0xbb.toByte(), 0xbf.toByte()))) 3 else 0
        if (count > skip) source.unread(prefix, skip, count - skip)
        prefix.fill(0)
        val decoder = charset.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
        return InputStreamReader(source, decoder).use(block)
    }

    internal fun csvParser() = CsvParser(CsvParserSettings().apply {
        setDelimiterDetectionEnabled(true, ',', ';', '\t'); isLineSeparatorDetectionEnabled = true
        maxColumns = MAX_COLUMNS; maxCharsPerColumn = MAX_CELL; setReadInputOnSeparateThread(false)
        setSkipEmptyLines(false); emptyValue = ""; nullValue = ""; isAutoClosingEnabled = false
        setIgnoreLeadingWhitespaces(false); setIgnoreTrailingWhitespaces(false); setCommentProcessingEnabled(false)
        errorContentLength = 0
        unescapedQuoteHandling = com.univocity.parsers.csv.UnescapedQuoteHandling.RAISE_ERROR
    })

    fun read(input: InputStream, format: String, emit: (HealthTableRow) -> Unit): List<String> =
        text(input) { reader ->
            when (format) {
                "csv" -> {
                    val parser = csvParser()
                    try {
                        parser.beginParsing(reader)
                        val headers = parser.parseNext()?.map(String::trim) ?: throw HealthImportFailure("table_empty")
                        if (headers.any { it.isBlank() || it.length > 200 } || headers.distinct().size != headers.size) throw HealthImportFailure("table_headers")
                        var index = 0L
                        while (true) {
                            val values = parser.parseNext() ?: break
                            if (values.sumOf { it?.length ?: 0 } > MAX_ROW) throw HealthImportFailure("table_row")
                            emit(HealthTableRow(++index, headers.mapIndexed { i, header -> header to values.getOrElse(i) { "" }.orEmpty() }.toMap(),
                                if (values.size > headers.size) "columns" else ""))
                        }
                        headers
                    } catch (_: com.univocity.parsers.common.TextParsingException) { throw HealthImportFailure("table_csv") }
                    finally { parser.stopParsing() }
                }
                "json" -> try { JsonReader(reader).use { json ->
                    if (json.peek() != JsonToken.BEGIN_ARRAY) throw HealthImportFailure("table_json")
                    val headers = linkedSetOf<String>(); var index = 0L
                    json.beginArray()
                    while (json.hasNext()) {
                        val cells = linkedMapOf<String, String>(); var issue = ""; var rowChars = 0
                        if (json.peek() != JsonToken.BEGIN_OBJECT) { json.skipValue(); issue = "object" }
                        else {
                            json.beginObject()
                            while (json.hasNext()) {
                                val key = json.nextName()
                                if (key.isBlank() || key.length > 200 || cells.containsKey(key)) throw HealthImportFailure("table_headers")
                                headers.add(key)
                                if (headers.size > MAX_COLUMNS) throw HealthImportFailure("table_columns")
                                val value = when (json.peek()) {
                                    JsonToken.STRING, JsonToken.NUMBER -> json.nextString()
                                    JsonToken.BOOLEAN -> json.nextBoolean().toString()
                                    JsonToken.NULL -> { json.nextNull(); "" }
                                    else -> { json.skipValue(); issue = "nested"; "" }
                                }
                                if (value.length > MAX_CELL) throw HealthImportFailure("table_cell")
                                rowChars += key.length + value.length
                                if (rowChars > MAX_ROW) throw HealthImportFailure("table_row")
                                cells[key] = value
                            }
                            json.endObject()
                        }
                        emit(HealthTableRow(++index, cells, issue))
                    }
                    json.endArray()
                    if (json.peek() != JsonToken.END_DOCUMENT) throw HealthImportFailure("table_json")
                    if (headers.isEmpty()) throw HealthImportFailure("table_empty")
                    headers.toList()
                } } catch (_: android.util.MalformedJsonException) { throw HealthImportFailure("table_json") }
                else -> throw HealthImportFailure("table_format")
            }
        }
}
