package com.galaxyssi.chat

import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import java.io.Closeable
import java.io.File
import java.util.UUID

internal class KnowledgeBackupTestFixture(val name: String = "test-knowledge-backup-${UUID.randomUUID()}.db") : Closeable {
    init { require(name.matches(Regex("test-knowledge-backup-[a-z0-9-]+\\.db"))) }
    val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val legacy = "legacy-$name"
    var db = AgentKnowledgeDatabase.shared(context, name, legacy)
    val mutations = mutableListOf<Pair<List<AgentKnowledgeItem>, List<AgentKnowledgeItem>>>()
    var observe = true
    var retain = false
    var store = openStore()
    val password = "fixture-only-passphrase".toCharArray()
    val file = File(context.cacheDir, "$name.hcbak")
    private fun openStore() = SQLiteAgentKnowledgeStore(context, name, legacy) { before, after ->
        if (observe) mutations.add(before to after)
    }
    fun item(index: Int, content: String = "\u77e5\u8bc6\u5907\u4efd\u6062\u590d-$index") = AgentKnowledgeItem(
        id = "backup-$index", kind = AgentKnowledgeKind.NOTE, title = "\u8d44\u6599-$index", content = content,
        source = "fixture-$index", summary = "\u6458\u8981-$index", updatedAtMillis = index.toLong() + 1)
    fun seed(count: Int) = db.transaction { sql -> (1..count).forEach { db.write(sql, item(it)) } }
    fun export(): Long = StreamingBackupArchive.write(file, password, store::exportRecords)
    fun restore() = KnowledgeBackupStaging(context).use { stage ->
        StreamingBackupArchive.read(file, password, stage::accept)
        stage.validateArchive(); store.restoreRecords(stage)
    }
    fun staged(items: Sequence<AgentKnowledgeItem>, action: (KnowledgeBackupStaging) -> Unit) = KnowledgeBackupStaging(context).use { stage ->
        stage.accept("knowledge", "begin", "{\"schema\":1}".byteInputStream())
        var n = 0L
        items.forEach { item ->
            stage.accept("knowledge-row", KnowledgeBackupRecords.key(item.id), AgentKnowledgeCodec.encodeItem(item).toString().byteInputStream())
            n++
        }
        stage.accept("knowledge", "end", JSONObject().put("rows", n).toString().byteInputStream())
        stage.validateArchive(); action(stage)
    }
    fun reopen() {
        store.close()
        db = AgentKnowledgeDatabase.shared(context, name, legacy)
        store = openStore()
    }
    override fun close() {
        store.close()
        if (!retain) { context.deleteDatabase(name); AgentEncryptedPreferences(context, legacy).clear(); file.delete() }
        password.fill('\u0000')
    }
}
