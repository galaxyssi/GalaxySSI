package com.galaxyssi.chat.voice.benchmark

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.StandardCopyOption

class WhisperBenchmarkStore(private val file: File) {
    @Synchronized
    fun find(key: WhisperBenchmarkKey): WhisperBenchmarkRecord? = readAll()
        .firstOrNull { it.certification.key == key }

    @Synchronized
    fun latestForProfile(profileId: String): WhisperBenchmarkRecord? = readAll()
        .filter { it.certification.key.modelProfileId == profileId }
        .maxByOrNull { it.certification.createdAtEpochMs }

    @Synchronized
    fun save(record: WhisperBenchmarkRecord) {
        val records = readAll().filterNot {
            it.certification.key.stableId == record.certification.key.stableId
        }.toMutableList()
        records += record
        val bounded = records.sortedByDescending { it.certification.createdAtEpochMs }.take(MAX_RECORDS)
        writeAll(bounded)
    }

    @Synchronized
    fun removeForProfile(profileId: String) {
        writeAll(readAll().filterNot { it.certification.key.modelProfileId == profileId })
    }

    @Synchronized
    fun clear() {
        file.delete()
        File(file.parentFile, "${file.name}.partial").delete()
    }

    private fun readAll(): List<WhisperBenchmarkRecord> = runCatching {
        if (!file.isFile) return@runCatching emptyList()
        val root = JSONObject(file.readText(Charsets.UTF_8))
        if (root.optInt("schemaVersion", 0) != SCHEMA_VERSION) return@runCatching emptyList()
        val values = root.optJSONArray("records") ?: JSONArray()
        buildList {
            repeat(values.length().coerceAtMost(MAX_RECORDS)) { index ->
                runCatching { WhisperBenchmarkRecord.fromJson(values.getJSONObject(index)) }
                    .getOrNull()
                    ?.let(::add)
            }
        }
    }.getOrDefault(emptyList())

    private fun writeAll(records: List<WhisperBenchmarkRecord>) {
        file.parentFile?.mkdirs()
        val partial = File(file.parentFile, "${file.name}.partial")
        partial.delete()
        val bytes = JSONObject()
            .put("schemaVersion", SCHEMA_VERSION)
            .put("records", JSONArray().apply { records.forEach { put(it.toJson()) } })
            .toString()
            .toByteArray(Charsets.UTF_8)
        FileOutputStream(partial).use { output ->
            output.write(bytes)
            output.fd.sync()
        }
        try {
            Files.move(
                partial.toPath(),
                file.toPath(),
                StandardCopyOption.ATOMIC_MOVE,
                StandardCopyOption.REPLACE_EXISTING
            )
        } catch (_: AtomicMoveNotSupportedException) {
            Files.move(partial.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
    }

    private companion object {
        const val SCHEMA_VERSION = 1
        const val MAX_RECORDS = 64
    }
}
