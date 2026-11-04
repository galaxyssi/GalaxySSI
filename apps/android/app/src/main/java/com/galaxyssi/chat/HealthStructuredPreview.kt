package com.galaxyssi.chat

import android.util.JsonReader
import android.util.JsonToken
import java.io.FilterInputStream
import java.io.InputStream
import org.json.JSONObject

internal data class HealthStructuredRow(val number: Long, val cells: List<String>)
internal data class HealthStructuredSample(
    val rows: List<HealthStructuredRow>, val more: Boolean, val columnsClipped: Boolean = false,
    val sheets: List<HealthXlsxSheet> = emptyList(), val selectedSheet: Int = -1, val jsonKeys: Boolean = false
)

internal object HealthStructuredPreview {
    const val ROWS = 20
    const val COLUMNS = 12
    private const val CELL_CHARS = 512
    private const val TEXT_BUDGET = 2 * 1024 * 1024
    private const val ELLIPSIS = "\u2026"

    fun cell(value: String) = if (value.length > CELL_CHARS) value.take(CELL_CHARS - 1) + ELLIPSIS else value

    fun read(store: HealthOriginalStore, original: HealthOriginal, sheet: Int? = null, cancelled: () -> Unit = {}): HealthStructuredSample {
        return when (HealthTableParser.format(original.name, original.mime)) {
            "xlsx" -> HealthXlsxReader.preview(store, original, sheet, cancelled)
            "csv" -> store.input(original).use { input -> csv(bounded(input, cancelled), cancelled) }
            "json" -> store.input(original).use { input -> json(bounded(input, cancelled), cancelled) }
            else -> throw HealthImportFailure("preview_unsupported")
        }
    }

    private fun bounded(input: InputStream, cancelled: () -> Unit): InputStream = object : FilterInputStream(input) {
        private var remaining = TEXT_BUDGET
        private fun availableBudget(): Int {
            cancelled()
            if (remaining <= 0) throw HealthImportFailure("structured_preview_limit")
            return remaining
        }
        override fun read(): Int {
            availableBudget()
            return super.read().also { if (it >= 0) remaining-- }
        }
        override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
            if (length == 0) return 0
            return super.read(buffer, offset, minOf(length, availableBudget())).also { if (it > 0) remaining -= it }
        }
    }

    private fun csv(input: InputStream, cancelled: () -> Unit): HealthStructuredSample = HealthTableParser.text(input) { reader ->
        val parser = HealthTableParser.csvParser()
        val rows = ArrayList<HealthStructuredRow>(ROWS)
        var clipped = false
        try {
            parser.beginParsing(reader)
            while (rows.size < ROWS) {
                cancelled()
                val values = parser.parseNext() ?: return@text HealthStructuredSample(rows, false, clipped)
                if (values.size > COLUMNS) clipped = true
                rows += HealthStructuredRow(rows.size + 1L, values.take(COLUMNS).map { cell(it.orEmpty()) })
            }
            cancelled()
            HealthStructuredSample(rows, parser.parseNext() != null, clipped)
        } catch (_: com.univocity.parsers.common.TextParsingException) {
            throw HealthImportFailure("table_csv")
        } finally { parser.stopParsing() }
    }

    private fun json(input: InputStream, cancelled: () -> Unit): HealthStructuredSample = HealthTableParser.text(input) { reader ->
        JsonReader(reader).use { json ->
            val rows = ArrayList<HealthStructuredRow>(ROWS)
            val keys = json.peek() == JsonToken.BEGIN_OBJECT
            val array = json.peek() == JsonToken.BEGIN_ARRAY
            if (!keys && !array) {
                if (json.peek() == JsonToken.END_DOCUMENT) return@use HealthStructuredSample(emptyList(), false)
                val result = HealthStructuredSample(listOf(HealthStructuredRow(1L, listOf(jsonCell(json, cancelled)))), false)
                if (json.peek() != JsonToken.END_DOCUMENT) throw HealthImportFailure("table_json")
                return@use result
            }
            if (keys) json.beginObject() else json.beginArray()
            while (rows.size < ROWS && json.hasNext()) {
                cancelled()
                val cells = if (keys) listOf(cell(json.nextName()), jsonCell(json, cancelled)) else listOf(jsonCell(json, cancelled))
                rows += HealthStructuredRow(rows.size + 1L, cells)
            }
            val more = json.hasNext()
            if (!more) {
                if (keys) json.endObject() else json.endArray()
                if (json.peek() != JsonToken.END_DOCUMENT) throw HealthImportFailure("table_json")
            }
            HealthStructuredSample(rows, more, jsonKeys = keys)
        }
    }

    private fun jsonCell(json: JsonReader, cancelled: () -> Unit, summarizeObject: Boolean = true): String {
        cancelled()
        return when (json.peek()) {
            JsonToken.STRING -> cell(JSONObject.quote(cell(json.nextString())))
            JsonToken.NUMBER -> cell(json.nextString())
            JsonToken.BOOLEAN -> json.nextBoolean().toString()
            JsonToken.NULL -> { json.nextNull(); "null" }
            JsonToken.BEGIN_OBJECT -> {
                if (!summarizeObject) { json.skipValue(); return "{$ELLIPSIS}" }
                val sample = ArrayList<String>(6)
                var clipped = false
                json.beginObject()
                while (json.hasNext()) {
                    cancelled()
                    val key = json.nextName()
                    if (sample.size < 6) sample += "${JSONObject.quote(cell(key))}: ${jsonCell(json, cancelled, false)}"
                    else { clipped = true; json.skipValue() }
                }
                json.endObject()
                cell(sample.joinToString(", ", "{", if (clipped) ", $ELLIPSIS}" else "}"))
            }
            JsonToken.BEGIN_ARRAY -> { json.skipValue(); "[$ELLIPSIS]" }
            else -> throw HealthImportFailure("table_json")
        }
    }
}
