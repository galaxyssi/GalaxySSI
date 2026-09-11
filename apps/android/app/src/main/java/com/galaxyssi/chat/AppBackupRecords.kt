package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject
import java.io.File

/** Full archive authentication and section validation precede any live restore callback. */
internal class AppBackupRecords(private val context: Context) {
    fun export(file: File, password: CharArray, contacts: Boolean, messages: Boolean,
        appFields: ((String, Any) -> Unit) -> Unit,
        agentFields: ((String, Any) -> Unit) -> Unit = { visit -> AgentBackupData.visitNonMemoryFields(context, messages, visit) }
    ): Long = StreamingBackupArchive.write(file, password) { writer ->
        writer.json("app", "begin", JSONObject().put("schema", 1).put("contacts", contacts).put("messages", messages))
        val emitted = mutableSetOf<Pair<String, String>>()
        fun field(section: String, key: String, value: Any) {
            AppBackupFields.validate(section, key, value)
            check(emitted.add(section to key)) { "Duplicate backup field" }
            writer.json(section, key, JSONObject().put("value", value))
        }
        appFields { key, value -> field("app-field", key, value) }
        agentFields { key, value -> field("agent-field", key, value) }
        check(emitted == AppBackupFields.expected(contacts, messages)) { "Backup fields are incomplete" }
        EncryptedAgentMemoryDeletionIndex(context).exportRecords(writer)
        writer.json("app", "end", JSONObject().put("fields", emitted.size))
    }

    fun restore(file: File, password: CharArray, includeMessages: Boolean,
        applyAppField: (String, Any) -> Unit,
        applyAgentField: (String, Any) -> Unit = { key, value -> AgentBackupData.restoreNonMemoryFields(context, JSONObject().put(key, value)) },
        finish: () -> Unit = { AgentBackupData.finishRestore(context); AgentWorkflowScheduler.restoreAll(context) }
    ) {
        MemoryBackupStaging(context).use { memory -> BackupFieldStaging(context).use { fields ->
            var expected: Set<Pair<String, String>>? = null
            var ended = false
            StreamingBackupArchive.read(file, password) { section, key, input ->
                check(!ended) { "Unexpected data after app backup end" }
                when (section) {
                    "app" -> {
                        val json = readBackupJson(input)
                        when (key) {
                            "begin" -> {
                                check(expected == null && json.getInt("schema") == 1)
                                check(json.get("contacts") is Boolean && json.get("messages") is Boolean)
                                expected = AppBackupFields.expected(json.getBoolean("contacts"), json.getBoolean("messages"))
                            }
                            "end" -> {
                                check(expected != null && fields.identities() == expected && json.getLong("fields") == expected!!.size.toLong()) {
                                    "App backup fields are incomplete"
                                }
                                ended = true
                            }
                            else -> error("Unknown app backup boundary")
                        }
                    }
                    "app-field", "agent-field" -> {
                        check(expected?.contains(section to key) == true) { "Unexpected app backup field" }
                        fields.accept(section, key, input)
                    }
                    "memory", "memory-row", "memory-deletion" -> {
                        check(expected != null) { "Missing app backup beginning" }
                        memory.accept(section, key, input)
                    }
                    else -> error("Unknown app backup section")
                }
            }
            check(ended) { "Missing app backup end" }
            memory.validateArchive()
            EncryptedAgentMemoryDeletionIndex(context).restoreRecords(memory)
            fields.visit { section, key, value ->
                if (section == "agent-field") applyAgentField(key, value)
                else if (key != "messages" || includeMessages) applyAppField(key, value)
            }
            finish()
        } }
    }
}
