package com.galaxyssi.chat

import java.nio.ByteBuffer
import java.security.MessageDigest

/** Previous export-token algorithm, retained only as a real-ciphertext performance baseline. */
internal object KnowledgeSourceLegacyDigestFixture {
    fun run(f: KnowledgeBackupTestFixture, reference: AgentKnowledgeSourceReference): String = f.db.access { db ->
        val digest = MessageDigest.getInstance("SHA-256")
        val selection = KnowledgeSourceSelection(f.db, reference)
        db.rawQuery("SELECT item_key,header FROM knowledge_items WHERE ${selection.where} ORDER BY item_key",
            arrayOf(selection.value)).use { rows ->
            while (rows.moveToNext()) repeat(2) { column ->
                val bytes = rows.getString(column).toByteArray(Charsets.UTF_8)
                try { digest.update(ByteBuffer.allocate(4).putInt(bytes.size).array()); digest.update(bytes) }
                finally { bytes.fill(0) }
            }
        }
        digest.digest().joinToString("") { "%02x".format(it) }
    }
}
