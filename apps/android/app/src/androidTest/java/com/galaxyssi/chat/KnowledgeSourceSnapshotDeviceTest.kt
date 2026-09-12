package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeSourceSnapshotDeviceTest {
    @Test fun bodyHeaderAndPreviewShareOnePermissionSnapshot() = KnowledgeBackupTestFixture().use { f ->
        var reads = 0
        // A changing caller-owned list makes multiple reads deterministic instead of relying on a race.
        val allowed = object : AbstractList<String>() {
            override val size = 1
            override fun get(index: Int): String {
                require(index == 0)
                return if (reads++ == 0) "fixture-before" else "fixture-after"
            }
        }
        val item = f.item(1).copy(agentAccess = AgentKnowledgeAgentAccess.SELECTED_AGENTS, allowedAgentIds = allowed)
        f.db.transaction { f.db.write(it, item) }
        assertEquals(1, reads)
        val body = f.db.access { f.db.read(it, f.db.key("id", item.id)) }
        assertEquals(listOf("fixture-before"), requireNotNull(body).allowedAgentIds)
        assertEquals(listOf("fixture-before"), f.store.sourcePage().groups.single().allowedAgentIds)
        KnowledgeSourcePreviewFixtureSchema.versionEight(f)
        assertEquals(listOf("fixture-before"), f.store.sourcePage().groups.single().allowedAgentIds)
        assertEquals(1, reads)
        assertFalse(f.db.hasActivePreviewKey)
    }
}
