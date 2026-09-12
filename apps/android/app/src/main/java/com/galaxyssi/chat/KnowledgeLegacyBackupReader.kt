package com.galaxyssi.chat

import android.util.JsonReader
import android.util.JsonToken
import org.json.JSONArray
import org.json.JSONObject
import java.io.InputStream
import java.io.InputStreamReader
import java.math.BigDecimal
import java.nio.charset.CodingErrorAction

/** Reads the old array envelope one source at a time, without rebuilding its corpus array. */
internal object KnowledgeLegacyBackupReader {
    fun read(input: InputStream, visit: (JSONObject) -> Unit) = reader(input).use { json ->
        json.beginObject()
        check(json.hasNext() && json.nextName() == "value") { "Invalid knowledge field envelope" }
        json.beginArray()
        while (json.hasNext()) visit(value(json, 0) as? JSONObject ?: error("Invalid knowledge item"))
        json.endArray()
        check(!json.hasNext()) { "Invalid knowledge field envelope" }
        json.endObject()
        check(json.peek() == JsonToken.END_DOCUMENT)
    }
    fun record(input: InputStream): JSONObject = reader(input).use { json ->
        val result = value(json, 0) as? JSONObject ?: error("Invalid knowledge record")
        check(json.peek() == JsonToken.END_DOCUMENT)
        result
    }
    private fun reader(input: InputStream) = JsonReader(InputStreamReader(input, Charsets.UTF_8.newDecoder()
        .onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)))
    private fun value(json: JsonReader, depth: Int): Any {
        require(depth <= 32) { "Knowledge backup JSON nesting is invalid" }
        return when (json.peek()) {
            JsonToken.BEGIN_OBJECT -> JSONObject().also { result ->
                json.beginObject()
                while (json.hasNext()) {
                    val key = json.nextName()
                    require(!result.has(key)) { "Duplicate knowledge JSON field" }
                    result.put(key, value(json, depth + 1))
                }
                json.endObject()
            }
            JsonToken.BEGIN_ARRAY -> JSONArray().also { result ->
                json.beginArray()
                while (json.hasNext()) result.put(value(json, depth + 1))
                json.endArray()
            }
            JsonToken.STRING -> json.nextString()
            JsonToken.NUMBER -> BigDecimal(json.nextString())
            JsonToken.BOOLEAN -> json.nextBoolean()
            JsonToken.NULL -> { json.nextNull(); JSONObject.NULL }
            else -> error("Invalid knowledge JSON token")
        }
    }
}
