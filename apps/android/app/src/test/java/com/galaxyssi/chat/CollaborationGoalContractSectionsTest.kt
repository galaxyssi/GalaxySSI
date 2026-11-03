package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationGoalContractSectionsTest {
    private class Rows : CollaborationGoalContractRows {
        val data = linkedMapOf<String, String>()
        val reads = mutableListOf<String>()
        override fun read(key: String): String? { reads += key; return data[key] }
        override fun commit(values: Map<String, String>) { data.putAll(values) }
        override fun removePrefix(prefix: String) { data.keys.removeAll { it.startsWith(prefix) } }
    }

    private val author = CollaborationWorkspaceAccess("g", "r", "t", 1, "a", "a")
    private val peer = author.copy(nodeId = "b", personId = "b")
    private fun ok(value: JSONObject) = value.also { assertEquals(value.toString(), "ok", it.optString("status")) }
    private fun rejected(value: JSONObject, reason: String) { assertEquals(reason, value.optString("reason")); assertFalse(value.has("fragments")) }
    private fun store(rows: Rows, size: Int = 8192) = CollaborationGoalContractStore(rows, { it == author || it == peer }, size)

    @Test fun targetedPagesSkipLargeHistoryRemainExactAndDoNotClaimFullDelivery() {
        for (size in listOf(1024, 8192, 65536)) {
            val rows = Rows()
            val target = "Exact \u4e2d\u6587 \uD83D\uDE80 receipt\n".repeat(1600)
            val store = store(rows, size)
            val descriptor = ok(store.publish(author, "Original goal. ".repeat(9000), "[]", mapOf(
                "A history" to "old data ".repeat(10_000), "M current" to target, "Z later" to "later ".repeat(10_000))))
            val id = descriptor.getString("snapshot_id")
            ok(store.bind(author, id))
            rows.reads.clear()
            val pages = mutableListOf<Pair<String, JSONObject>>()
            var cursor = ""
            do {
                val page = ok(store(rows).readSection(author, "context:M current", cursor))
                assertTrue(page.getInt("page_index") > 0)
                assertTrue(page.toString().toByteArray(Charsets.UTF_8).size <= size)
                pages += cursor to page
                cursor = if (page.isNull("next_cursor")) "" else page.getString("next_cursor")
            } while (cursor.isNotEmpty())
            assertTrue(pages.size < descriptor.getInt("page_count") / 2)
            assertEquals(pages.size, rows.reads.count { it.contains(":page:") })
            val restored = buildString {
                pages.forEach { (_, page) ->
                    val fragments = page.getJSONArray("fragments")
                    repeat(fragments.length()) { i ->
                        val fragment = fragments.getJSONObject(i)
                        if (fragment.optString("stream") == "context" && fragment.optInt("context_index", -1) == 1) {
                            assertEquals(length, fragment.getInt("start_utf16"))
                            append(fragment.getString("text"))
                        }
                    }
                }
            }
            assertEquals(target, restored)
            assertEquals(0, ok(store.delivery(author, id)).getInt("delivered_page_count"))
            pages.forEach { (sentCursor, page) ->
                assertEquals("recorded", store.recordDelivery(author, id, sentCursor, page, "context:M current").optString("status"))
            }
            val delivered = ok(store(rows).delivery(author, id))
            assertEquals(pages.size, delivered.getInt("delivered_page_count"))
            assertFalse(delivered.getBoolean("all_pages_delivered"))
            assertTrue(pages.last().second.getInt("section_last_page") < descriptor.getInt("page_count") - 1)
        }
    }

    @Test fun sectionCursorsCannotCrossSectionReaderOrWholeSnapshot() {
        val rows = Rows()
        val store = store(rows, 1024)
        val id = ok(store.publish(author, "Long goal ".repeat(200), "[]", mapOf("Context" to "x".repeat(5000)))).getString("snapshot_id")
        ok(store.bind(author, id)); ok(store.bind(peer, id))
        val cursor = ok(store.readSection(author, "goal")).getString("next_cursor")
        ok(store.readSection(author, "goal", cursor))
        rejected(store.readSection(author, "context:Context", cursor), "invalid_cursor")
        rejected(store.readSection(peer, "goal", cursor), "invalid_cursor")
        rejected(store.read(author, cursor), "invalid_cursor")
        val wholeCursor = ok(store.read(author)).getString("next_cursor")
        rejected(store.readSection(author, "goal", wholeCursor), "invalid_cursor")
        rejected(store.readSection(author.copy(groupId = "other"), "goal"), "access_denied")
    }

    @Test fun fabricatedSectionEnvelopeCannotCreateDeliveryReceipt() {
        val rows = Rows()
        val store = store(rows)
        val id = ok(store.publish(author, "Goal", "[]", mapOf("Context" to "x".repeat(20_000)))).getString("snapshot_id")
        ok(store.bind(author, id))
        val page = ok(store.readSection(author, "context:Context"))
        rejected(store.recordDelivery(author, id, "", page), "invalid_delivery")
        page.put("section_last_page", page.getInt("section_first_page")).put("next_cursor", JSONObject.NULL)
        rejected(store.recordDelivery(author, id, "", page, "context:Context"), "invalid_delivery")
        assertEquals(0, ok(store.delivery(author, id)).getInt("delivered_page_count"))
    }

    @Test fun existingSnapshotsWithoutIndexStillSupportTargetedReadsWithoutMutation() {
        val rows = Rows()
        val store = store(rows)
        val newId = ok(store.publish(author, "Goal", "[]", mapOf("Current" to "preserved"))).getString("snapshot_id")
        val manifestKey = rows.data.keys.single { it.endsWith(":manifest") }
        val manifest = JSONObject(rows.data.getValue(manifestKey)).apply { remove("section_pages") }
        val raw = AgentNativeJsonCodec.stringify(manifest.toNativeObject())
        val oldId = AgentResultRecoveryClient.sha256(raw.toByteArray(Charsets.UTF_8))
        val snapshotRows = rows.data.filterKeys { it.contains(newId) }
        snapshotRows.forEach { (key, value) -> rows.data.remove(key); rows.data[key.replace(newId, oldId)] = if (key == manifestKey) raw else value }
        ok(store.bind(author, oldId))
        val before = rows.data.toMap()
        val page = ok(store(rows).readSection(author, "context:Current"))
        assertTrue(page.toString().contains("preserved"))
        assertEquals(before, rows.data)
    }

    @Test fun unknownOrInvalidSectionsNeverFallbackToUnrelatedMaterial() {
        val rows = Rows()
        val store = store(rows)
        val id = ok(store.publish(author, "Goal", "[]")).getString("snapshot_id")
        ok(store.bind(author, id))
        for (section in listOf("", "GOAL", "context:", "context:  ", "context:" + "x".repeat(513)))
            rejected(store.readSection(author, section), "invalid_section")
        rejected(store.readSection(author, "context:Missing"), "section_unavailable")
    }

    @Test fun fragmentedSectionNamesAreIndexedWithoutTruncation() {
        val rows = Rows()
        val store = store(rows, 1024)
        val name = "\u4e2d".repeat(160)
        val id = ok(store.publish(author, "Goal", "[]", mapOf(name to "EXACT_TARGET"))).getString("snapshot_id")
        ok(store.bind(author, id))
        var cursor = ""
        val result = StringBuilder()
        do {
            val page = ok(store.readSection(author, "context:$name", cursor))
            result.append(page)
            assertTrue(page.toString().toByteArray(Charsets.UTF_8).size <= 1024)
            cursor = if (page.isNull("next_cursor")) "" else page.getString("next_cursor")
        } while (cursor.isNotEmpty())
        assertTrue(result.contains("EXACT_TARGET"))
    }
}
