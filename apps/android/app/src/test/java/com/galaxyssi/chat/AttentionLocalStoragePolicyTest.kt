package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AttentionLocalStoragePolicyTest {
    @Test fun publicDiscoveryStoresAndReaderStateAreLocal() {
        listOf("attention_feed_v1", "attention_push_v1", "attention_titles_v1",
            "attention_paired_titles_v1", "attention_news_evidence_v1").forEach {
            assertTrue(AttentionLocalStoragePolicy.allows(it, "example", "data"))
        }
        listOf("proactive_attention_v1", "proactive_attention_evidence_row:source", "attention_reader_position_v1")
            .forEach { assertTrue(AttentionLocalStoragePolicy.allows(GlobalAgentRepository.DATABASE_NAME, it, "{}")) }
    }

    @Test fun onlyPublicNewsRowsInTheSharedStoreAreUnencrypted() {
        val db = GlobalAgentRepository.DATABASE_NAME
        assertTrue(AttentionLocalStoragePolicy.allows(db, "proactive_message_row:news",
            """{"source_event_id":"research:attention-research:ai:article"}"""))
        assertFalse(AttentionLocalStoragePolicy.allows(db, "proactive_message_row:personal",
            """{"source_event_id":"research:private-conversation"}"""))
        assertFalse(AttentionLocalStoragePolicy.allows(db, "world", "{}"))
        assertFalse(AttentionLocalStoragePolicy.allows(db, "research_tasks", "[]"))
        assertFalse(AttentionLocalStoragePolicy.allows(db, "proactive_message_row:broken", "not json"))
    }

    @Test fun unrelatedDatabasesNeverOptOut() {
        listOf("contacts", "agent_transcript", "agent_memory", "attention_feed_v1_copy").forEach {
            assertFalse(AttentionLocalStoragePolicy.allows(it, "proactive_attention_v1", "{}"))
        }
    }
}
