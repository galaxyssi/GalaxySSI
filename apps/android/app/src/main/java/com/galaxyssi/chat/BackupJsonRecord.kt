package com.galaxyssi.chat

import org.json.JSONObject

internal fun BackupRecordStream.Writer.json(section: String, key: String, value: JSONObject) {
    record(section, key) { output ->
        val bytes = value.toString().toByteArray(Charsets.UTF_8)
        try { output.write(bytes) } finally { bytes.fill(0) }
    }
}
