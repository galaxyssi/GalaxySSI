package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationGoalContractPagingTest {
    @Test fun boundGoalSnapshotCannotSilentlyChangePinnedMilestoneAccess() {
        val host = Host()
        val pinned = host.peer.copy(pinnedReads = setOf("workspace:" + "a".repeat(64) + ":1:" + "b".repeat(64)))
        host.allowed += pinned
        val store = host.store()
        val descriptor = ok(store.publish(pinned, "Check the published version", "[]"))
        ok(store.bind(pinned, descriptor.getString("snapshot_id")))
        ok(host.store().read(pinned, descriptor.getString("snapshot_id"), ""))
        rejected(host.store().read(host.peer, descriptor.getString("snapshot_id"), ""), "binding_corrupt")
    }

    private class Rows : CollaborationGoalContractRows {
        val data = linkedMapOf<String, String>()
        var rejectCommit = false
        override fun read(key: String) = data[key]
        override fun commit(values: Map<String, String>) {
            check(!rejectCommit)
            data.putAll(values)
        }
        override fun removePrefix(prefix: String) { data.keys.removeAll { it.startsWith(prefix) } }
    }

    private class Host {
        val rows = Rows()
        val author = CollaborationWorkspaceAccess("group", "run", "turn", 1, "node-a", "person-a")
        val peer = author.copy(nodeId = "node-b", personId = "person-b")
        val allowed = mutableSetOf(author, peer)
        val checks = mutableListOf<CollaborationWorkspaceAccess>()
        fun store(size: Int = CollaborationGoalContractStore.DEFAULT_PAGE_BYTES) =
            CollaborationGoalContractStore(rows, { checks += it; it in allowed }, size)
    }

    private fun criteria(requirement: String = "Preserve every original constraint"): String = JSONArray().put(
        JSONObject().put("id", "criterion-1").put("requirement", requirement)
            .put("verification", "documentary")).toString()

    private fun ok(value: JSONObject): JSONObject = value.also { assertEquals("ok", it.optString("status")) }
    private fun rejected(value: JSONObject, reason: String? = null) {
        assertEquals("rejected", value.optString("status"))
        if (reason != null) assertEquals(reason, value.getString("reason"))
        assertFalse(value.has("fragments"))
        assertFalse(value.has("snapshot_id"))
        assertFalse(value.has("criteria_sha256"))
    }

    private data class Retrieved(val cursor: String, val page: JSONObject)
    private fun pages(store: CollaborationGoalContractStore, access: CollaborationWorkspaceAccess,
                      descriptor: JSONObject): List<Retrieved> {
        ok(store.bind(access, descriptor.getString("snapshot_id")))
        val result = mutableListOf<Retrieved>()
        var cursor = ""
        do {
            val page = ok(store.read(access, descriptor.getString("snapshot_id"), cursor))
            assertEquals(result.size, page.getInt("page_index"))
            assertEquals(descriptor.getInt("page_count"), page.getInt("page_count"))
            assertEquals(descriptor.getString("snapshot_id"), page.getString("snapshot_sha256"))
            val encoded = page.toString().toByteArray(Charsets.UTF_8)
            assertTrue(encoded.size <= descriptor.getInt("max_page_bytes"))
            assertEquals(page.toString(), JSONObject(String(encoded, Charsets.UTF_8)).toString())
            result += Retrieved(cursor, page)
            if (page.isNull("next_cursor")) break
            cursor = page.getString("next_cursor")
            assertEquals(54, cursor.length)
            assertTrue(result.size < descriptor.getInt("page_count"))
        } while (true)
        assertEquals(descriptor.getInt("page_count"), result.size)
        return result
    }

    private fun reconstruct(pages: List<Retrieved>): Map<Pair<String, String>, String> {
        val values = linkedMapOf<Pair<String, String>, StringBuilder>()
        val parts = mutableMapOf<Pair<String, String>, Int>()
        val finished = hashSetOf<Pair<String, String>>()
        pages.forEach { entry ->
            val fragments = entry.page.getJSONArray("fragments")
            assertTrue(fragments.length() > 0)
            repeat(fragments.length()) { index ->
                val fragment = fragments.getJSONObject(index)
                val key = fragment.getString("stream") to if (fragment.has("context_index"))
                    fragment.getInt("context_index").toString() else fragment.getString("source_id")
                assertFalse(key in finished)
                val text = fragment.getString("text")
                assertTrue(Charsets.UTF_8.newEncoder().canEncode(text))
                assertTrue(text.isEmpty() || !text.first().isLowSurrogate() && !text.last().isHighSurrogate())
                val value = values.getOrPut(key) { StringBuilder() }
                assertEquals(parts[key] ?: 0, fragment.getInt("part"))
                assertEquals(value.length, fragment.getInt("start_utf16"))
                value.append(text)
                assertEquals(value.length, fragment.getInt("end_utf16"))
                parts[key] = (parts[key] ?: 0) + 1
                if (fragment.getBoolean("last")) finished += key
            }
        }
        assertEquals(values.keys, finished)
        return values.mapValues { it.value.toString() }
    }

    private fun assertContract(goal: String, criteria: String, descriptor: JSONObject, pages: List<Retrieved>) {
        val values = reconstruct(pages)
        assertEquals(goal, values["goal" to ""])
        assertEquals(criteria, values["criteria" to ""])
        assertEquals(AgentResultRecoveryClient.sha256(goal.toByteArray(Charsets.UTF_8)), descriptor.getString("goal_sha256"))
        assertEquals(CollaborationSemanticGoalCoverage.criteriaHash(JSONArray(criteria)), descriptor.getString("criteria_sha256"))
        assertEquals(AgentResultRecoveryClient.sha256(criteria.toByteArray(Charsets.UTF_8)), descriptor.getString("criteria_json_sha256"))
        val source = CollaborationSemanticGoalCoverage.source(goal).getJSONArray("segments")
        assertEquals(source.length(), descriptor.getInt("source_segment_count"))
        assertEquals(source.length() + 2, values.size)
        repeat(source.length()) { index ->
            val segment = source.getJSONObject(index)
            assertEquals(segment.getString("text"), values["source" to segment.getString("id")])
        }
    }

    @Test fun tenTwentyOneAndOneHundredThousandCharacterGoalsSurviveReopenLosslessly() {
        listOf(10_000, 21_000, 100_000).forEach { length ->
            val host = Host()
            val suffix = "\nPreserve the very last prohibition."
            val goal = "x".repeat(length - suffix.length) + suffix
            assertEquals(length, goal.length)
            val input = criteria()
            val descriptor = ok(host.store().publish(host.author, goal, input))
            assertTrue(descriptor.toString().toByteArray(Charsets.UTF_8).size < 1024)
            assertFalse(descriptor.toString().contains("prohibition"))
            val reopened = host.store(1024)
            assertContract(goal, input, descriptor, pages(reopened, host.author, descriptor))
        }
    }

    @Test fun manyClausesHaveNoSourceOrPageCountPolicyCap() {
        val host = Host()
        val goal = (1..12_000).joinToString("") { "Keep constraint $it;\n" }
        val store = host.store(2048)
        val descriptor = ok(store.publish(host.author, goal, "[]"))
        assertEquals(12_000, descriptor.getInt("source_segment_count"))
        assertTrue(descriptor.getInt("page_count") > 1000)
        assertContract(goal, "[]", descriptor, pages(store, host.peer, descriptor))
    }

    @Test fun encodedUtf8BudgetsCoverEscapesUnicodeAndIndividualOversizedStrings() {
        val text = "\u4e2d\u6587\uD83D\uDE80\"\\\n\t\r\b\u0000</script>\u2028\u0085"
        val goal = " ".repeat(9000) + text.repeat(700) + " last constraint " + " ".repeat(5000)
        val input = " \n" + criteria(text.repeat(900)) + "\t "
        listOf(1024, 2048, 8192, 65536).forEach { size ->
            val host = Host()
            val store = host.store(size)
            val descriptor = ok(store.publish(host.author, goal, input))
            val retrieved = pages(store, host.author, descriptor)
            assertContract(goal, input, descriptor, retrieved)
            if (size == 1024) {
                val fragments = retrieved.flatMap { item -> item.page.getJSONArray("fragments").let { array ->
                    (0 until array.length()).map(array::getJSONObject)
                } }
                assertTrue(fragments.any { it.getString("stream") == "criteria" && it.getInt("part") > 0 })
                assertTrue(fragments.any { it.getString("stream") == "source" && it.getInt("part") > 0 })
            }
        }
    }

    @Test fun validNestedCriteriaArePreservedIncludingWhitespaceAndExtraFields() {
        val host = Host()
        val input = " [ {\"id\":\"c\", \"requirement\":\"exact\", \"extras\":[{},[],true,false,null,-1.2e+3,\"\\u4e2d\"]} ] "
        val store = host.store()
        val descriptor = ok(store.publish(host.author, "Exact original goal", input))
        assertContract("Exact original goal", input, descriptor, pages(store, host.author, descriptor))
    }

    @Test fun malformedCriteriaNeverIssueAHashOrWriteASnapshot() {
        val malformed = listOf("", "null", "{}", "not-json", "[] trailing", "[{}]", "[1]", "[null]",
            "[{'id':'a','requirement':'b'}]", "[/*comment*/]", "[,]", "[1,]",
            "[{\"id\":\"a\",\"requirement\":\"b\",}]", "[{\"id\":\"a\",\"id\":\"b\",\"requirement\":\"c\"}]",
            "[{\"id\":\"a\",\"requirement\":\"\\uD800\"}]", "[{\"id\":\"a\",\"requirement\":\"b\",\"number\":01}]",
            "[{\"id\":\"a\",\"requirement\":\"b\",\"verification\":42}]",
            "[{\"id\":\"a\",\"requirement\":\"b\"},{\"id\":\"a\",\"requirement\":\"c\"}]")
        malformed.forEach { input ->
            val host = Host()
            rejected(host.store().publish(host.author, "Goal", input), "invalid_criteria")
            assertTrue(host.rows.data.isEmpty())
        }
        val host = Host()
        rejected(host.store().publish(host.author, "bad\uD800", "[]"), "invalid_goal")
        rejected(host.store().publish(host.author, "  ", "[]"), "invalid_goal")
    }

    @Test fun replayIsDeterministicAndNewCriteriaDoNotMutateOldSnapshots() {
        val host = Host()
        val store = host.store(2048)
        val goal = "Original goal. ".repeat(2000)
        val first = ok(store.publish(host.author, goal, "[]"))
        val firstPages = pages(store, host.author, first)
        val before = host.rows.data.toMap()
        assertEquals(first.toString(), ok(host.store(2048).publish(host.peer, goal, "[]")).toString())
        assertEquals(before, host.rows.data)
        val changed = ok(store.publish(host.author, goal, criteria()))
        assertNotEquals(first.getString("snapshot_id"), changed.getString("snapshot_id"))
        before.forEach { (key, value) -> assertEquals(value, host.rows.data[key]) }
        val reopened = host.store()
        firstPages.forEach { entry ->
            assertEquals(entry.page.toString(), ok(reopened.read(host.author, first.getString("snapshot_id"), entry.cursor)).toString())
        }
        rejected(store.read(host.author, changed.getString("snapshot_id"), firstPages[1].cursor), "snapshot_not_bound")
        rejected(store.bind(host.author, changed.getString("snapshot_id")), "access_already_bound")
        val next = host.author.copy(nodeId = "next-dispatch", round = 2)
        host.allowed += next
        ok(store.bind(next, changed.getString("snapshot_id")))
        assertEquals(0, ok(store.delivery(next, changed.getString("snapshot_id"))).getInt("delivered_page_count"))
        assertContract(goal, criteria(), changed, pages(store, next, changed))
    }

    @Test fun exactScopeAndMembershipAreRequiredAndPeerCursorsCannotBeBorrowed() {
        val host = Host()
        val store = host.store(1024)
        val descriptor = ok(store.publish(host.author, "Keep this exact goal. ".repeat(300), "[]"))
        val id = descriptor.getString("snapshot_id")
        ok(store.bind(host.author, id))
        val authorPage = ok(store.read(host.author))
        val token = authorPage.getString("next_cursor")
        listOf(host.author.copy(groupId = "foreign"), host.author.copy(runId = "foreign"),
            host.author.copy(turnId = "foreign")).forEach { other ->
            host.allowed += other
            rejected(store.bind(other, id))
            rejected(store.read(other, id, ""))
            rejected(store.read(other, id, token))
        }
        ok(store.bind(host.peer, id))
        ok(store.read(host.peer))
        rejected(store.read(host.peer, id, token), "invalid_cursor")
        rejected(store.recordDelivery(host.peer, id, "", authorPage), "invalid_delivery")
        val samePersonNewNode = host.author.copy(nodeId = "node-c")
        val sameNodeNewPerson = host.author.copy(personId = "person-c")
        listOf(samePersonNewNode, sameNodeNewPerson).forEach { other ->
            host.allowed += other
            ok(store.bind(other, id))
            ok(store.read(other))
            rejected(store.read(other, id, token), "invalid_cursor")
            assertEquals(0, ok(store.delivery(other, id)).getInt("delivered_page_count"))
        }
        val forged = host.author.copy(nodeId = "model-invented", dependencyNodes = setOf(host.author.nodeId), round = 999)
        rejected(store.read(forged), "access_denied")
        assertTrue(forged in host.checks)
        host.allowed.remove(host.author)
        rejected(store.read(host.author), "access_denied")
        rejected(store.recordDelivery(host.author, id, "", authorPage), "access_denied")
        rejected(store.publish(host.author, "Goal", "[]"), "access_denied")
    }

    @Test fun malformedAndTamperedCursorsFailClosed() {
        val host = Host()
        val store = host.store(1024)
        val id = ok(store.publish(host.author, "x".repeat(10_000), "[]")).getString("snapshot_id")
        ok(store.bind(host.author, id))
        val token = ok(store.read(host.author)).getString("next_cursor")
        val tampered = token.substring(0, 20) + (if (token[20] == 'A') "B" else "A") + token.substring(21)
        listOf(" ", "0", "../page:1", token + "=", "A".repeat(54), tampered).forEach {
            rejected(store.read(host.author, id, it), "invalid_cursor")
        }
    }

    @Test fun missingMixedAndTamperedPagesAndManifestsFailClosed() {
        val host = Host()
        val store = host.store(1024)
        val first = ok(store.publish(host.author, "a".repeat(10_000), "[]")).getString("snapshot_id")
        val second = ok(store.publish(host.author, "b".repeat(10_000), "[]")).getString("snapshot_id")
        ok(store.bind(host.author, first))
        val key = host.rows.data.keys.single { it.contains("snapshot:$first:") && it.endsWith("page:0") }
        val other = host.rows.data.keys.single { it.contains("snapshot:$second:") && it.endsWith("page:0") }
        val original = host.rows.data.getValue(key)
        host.rows.data[key] = host.rows.data.getValue(other)
        rejected(store.read(host.author), "snapshot_corrupt")
        host.rows.data[key] = original.replace("aaa", "bad")
        rejected(store.read(host.author), "snapshot_corrupt")
        host.rows.data.remove(key)
        rejected(store.read(host.author), "snapshot_corrupt")
        host.rows.data[key] = original
        val manifest = host.rows.data.keys.single { it.contains("snapshot:$first:") && it.endsWith("manifest") }
        val manifestRaw = host.rows.data.getValue(manifest)
        host.rows.data[manifest] = JSONObject(manifestRaw).put("goal_sha256", "0".repeat(64)).toString()
        rejected(store.read(host.author), "snapshot_corrupt")
        host.rows.data[manifest] = host.rows.data.entries.single { it.key.contains("snapshot:$second:") && it.key.endsWith("manifest") }.value
        rejected(store.read(host.author), "snapshot_corrupt")
        host.rows.data[manifest] = manifestRaw
        ok(store.read(host.author))
    }

    @Test fun partialDeliverySurvivesReopenAndReadAloneNeverClaimsDelivery() {
        val host = Host()
        val store = host.store(2048)
        val descriptor = ok(store.publish(host.author, "Original; ".repeat(300), "[]"))
        val id = descriptor.getString("snapshot_id")
        val retrieved = pages(store, host.author, descriptor)
        ok(store.bind(host.peer, id))
        assertEquals(0, ok(store.delivery(host.author, id)).getInt("delivered_page_count"))
        val first = retrieved.first()
        assertEquals("recorded", store.recordDelivery(host.author, id, first.cursor, first.page).getString("status"))
        assertEquals("recorded", store.recordDelivery(host.author, id, first.cursor, first.page).getString("status"))
        val reopened = host.store()
        val progress = ok(reopened.delivery(host.author, id))
        assertEquals(1, progress.getInt("delivered_page_count"))
        assertFalse(progress.getBoolean("all_pages_delivered"))
        assertEquals(retrieved[1].cursor, progress.getString("next_undelivered_cursor"))
        assertEquals(0, ok(reopened.delivery(host.peer, id)).getInt("delivered_page_count"))
        val altered = JSONObject(retrieved[1].page.toString()).put("page_sha256", "0".repeat(64))
        rejected(reopened.recordDelivery(host.author, id, retrieved[1].cursor, altered), "invalid_delivery")
        assertEquals("recorded", reopened.recordInlineDelivery(host.author, id, retrieved.drop(1).map { it.page }).getString("status"))
        val complete = ok(host.store().delivery(host.author, id))
        assertTrue(complete.getBoolean("all_pages_delivered"))
        assertTrue(complete.isNull("next_undelivered_cursor"))
        assertEquals("delivery_only_not_comprehension", complete.getString("trust"))
        rejected(reopened.recordInlineDelivery(host.peer, id, listOf(retrieved.last().page)), "invalid_delivery")
    }

    @Test fun deliveryCorruptionAndPartialFailedWritesCannotManufactureCompletion() {
        val host = Host()
        val store = host.store()
        host.rows.rejectCommit = true
        rejected(store.publish(host.author, "Goal", "[]"))
        assertTrue(host.rows.data.isEmpty())
        host.rows.rejectCommit = false
        val id = ok(store.publish(host.author, "Goal", "[]")).getString("snapshot_id")
        ok(store.bind(host.author, id))
        val page = ok(store.read(host.author))
        host.rows.rejectCommit = true
        rejected(store.recordDelivery(host.author, id, "", page))
        assertEquals(0, ok(store.delivery(host.author, id)).getInt("delivered_page_count"))
        host.rows.rejectCommit = false
        assertEquals("recorded", store.recordDelivery(host.author, id, "", page).getString("status"))
        val receipt = host.rows.data.keys.single { ":delivery:" in it }
        host.rows.data[receipt] = JSONObject(host.rows.data.getValue(receipt)).put("channel", "inline").toString()
        rejected(store.delivery(host.author, id), "delivery_corrupt")
    }

    @Test fun groupRemovalPurgesContractsAndDeliveryButLeavesOtherGroupsIntact() {
        val host = Host()
        val store = host.store()
        val other = host.author.copy(groupId = "other-group")
        host.allowed += other
        val id = ok(store.publish(host.author, "Goal", "[]")).getString("snapshot_id")
        val otherId = ok(store.publish(other, "Goal", "[]")).getString("snapshot_id")
        assertNotEquals(id, otherId)
        ok(store.bind(host.author, id))
        ok(store.bind(other, otherId))
        val page = ok(store.read(host.author))
        assertEquals("recorded", store.recordDelivery(host.author, id, "", page).getString("status"))
        store.remove(host.author.groupId)
        rejected(store.read(host.author), "access_not_bound")
        rejected(store.delivery(host.author, id), "access_not_bound")
        rejected(store.lookup(host.author), "access_not_bound")
        ok(host.store().read(other))
        assertEquals(1, host.rows.data.keys.map {
            it.substringBefore(":snapshot:").substringBefore(":cursor-key").substringBefore(":binding:")
        }.toSet().size)
    }

    @Test fun hostBindingPinsOneSnapshotPerExactDispatchAndSurvivesReopen() {
        val host = Host()
        val store = host.store(1024)
        val original = ok(store.publish(host.author, "Long original goal ".repeat(1000), "[]"))
        val changed = ok(store.publish(host.author, "Long original goal ".repeat(1000), criteria()))
        val first = original.getString("snapshot_id")
        val second = changed.getString("snapshot_id")
        rejected(store.lookup(host.author), "access_not_bound")
        rejected(store.read(host.author, first, ""), "access_not_bound")
        val before = host.rows.data.toMap()
        host.rows.rejectCommit = true
        rejected(store.bind(host.author, first))
        assertEquals(before, host.rows.data)
        host.rows.rejectCommit = false
        assertEquals(original.toString(), ok(store.bind(host.author, first)).toString())
        val pinned = host.rows.data.toMap()
        assertEquals(original.toString(), ok(store.bind(host.author, first)).toString())
        assertEquals(pinned, host.rows.data)
        val reopened = host.store()
        assertEquals(original.toString(), ok(reopened.lookup(host.author)).toString())
        rejected(reopened.bind(host.author, second), "access_already_bound")
        rejected(reopened.read(host.author, second, ""), "snapshot_not_bound")
        assertEquals(first, ok(reopened.read(host.author)).getString("snapshot_id"))
        rejected(reopened.read(host.peer), "access_not_bound")
        ok(reopened.bind(host.peer, second))
        val peerPage = ok(reopened.read(host.peer))
        rejected(reopened.read(host.author, peerPage.getString("next_cursor")), "invalid_cursor")
        val originalCursor = ok(reopened.read(host.author)).getString("next_cursor")
        val unchanged = host.rows.data.toMap()
        for (changedScope in listOf(host.author.copy(round = 2), host.author.copy(dependencyNodes = setOf("independent-peer")))) {
            host.allowed += changedScope
            rejected(reopened.bind(changedScope, second), "binding_corrupt")
            rejected(reopened.bind(changedScope, first), "binding_corrupt")
            rejected(reopened.lookup(changedScope), "binding_corrupt")
            rejected(reopened.read(changedScope, originalCursor), "binding_corrupt")
        }
        assertEquals(unchanged, host.rows.data)
        assertEquals(first, ok(reopened.lookup(host.author)).getString("snapshot_id"))
    }

    @Test fun copiedOrTamperedBindingsCannotGrantAnotherSnapshotOrMemberAccess() {
        val host = Host()
        val store = host.store()
        val first = ok(store.publish(host.author, "Original", "[]")).getString("snapshot_id")
        val second = ok(store.publish(host.author, "Original", criteria())).getString("snapshot_id")
        ok(store.bind(host.author, first))
        val keyA = host.rows.data.keys.single { ":binding:" in it }
        ok(store.bind(host.peer, second))
        val keyB = host.rows.data.keys.single { ":binding:" in it && it != keyA }
        val original = host.rows.data.getValue(keyA)
        host.rows.data[keyA] = host.rows.data.getValue(keyB)
        rejected(store.lookup(host.author), "binding_corrupt")
        rejected(store.read(host.author), "binding_corrupt")
        rejected(store.bind(host.author, second), "binding_corrupt")
        host.rows.data[keyA] = JSONObject(original).put("snapshot_id", second).toString()
        rejected(store.lookup(host.author), "binding_corrupt")
        host.rows.data[keyA] = original
        assertEquals(first, ok(store.lookup(host.author)).getString("snapshot_id"))
    }

    @Test fun optionalContextSectionsAreLosslessOrderedAndNeverCopiedIntoDescriptor() {
        val host = Host()
        val store = host.store(1024)
        val longName = "\uD83D\uDE80".repeat(1000)
        val contexts = linkedMapOf("roster" to "Roster member \"\u4e2d\u6587\"\n".repeat(7000),
            "previousAssessment" to "Previous assessment; ".repeat(2000), "empty" to "", longName to "Long-name section")
        repeat(40) { contexts["section-$it"] = "Exact optional context $it\n" }
        val descriptor = ok(store.publish(host.author, "Original goal", "[]", contexts))
        assertEquals(contexts.size, descriptor.getInt("context_section_count"))
        assertFalse(descriptor.getBoolean("context_keys_complete"))
        assertTrue(descriptor.getJSONArray("context_keys").length() <= 8)
        assertTrue(descriptor.getJSONArray("context_keys").toString().toByteArray(Charsets.UTF_8).size <= 256)
        assertTrue(descriptor.toString().toByteArray(Charsets.UTF_8).size < 1400)
        assertFalse(descriptor.toString().contains("Roster member"))
        assertFalse(descriptor.toString().contains("Previous assessment;"))
        val retrieved = pages(store, host.author, descriptor)
        val values = reconstruct(retrieved)
        assertEquals("Original goal", values["goal" to ""])
        assertEquals("[]", values["criteria" to ""])
        val fragments = retrieved.flatMap { entry -> entry.page.getJSONArray("fragments").let { array ->
            (0 until array.length()).map(array::getJSONObject)
        } }
        val firstContext = fragments.indexOfFirst { it.has("context_index") }
        assertTrue(firstContext > 0)
        assertTrue(fragments.drop(firstContext).all { it.has("context_index") })
        contexts.toSortedMap().entries.forEachIndexed { index, (name, text) ->
            val field = fragments.first { it.optString("stream") == "context" && it.getInt("context_index") == index }
            assertEquals("context", field.getString("kind"))
            val restoredName = if (field.isNull("id")) values["context_name" to index.toString()] else field.getString("id")
            assertEquals(name, restoredName)
            assertEquals(text, values["context" to index.toString()])
        }
        val reopened = host.store(1024)
        val reordered = contexts.entries.reversed().associate { it.key to it.value }
        assertEquals(descriptor.toString(), ok(reopened.publish(host.author, "Original goal", "[]", reordered)).toString())
        assertEquals(descriptor.toString(), ok(reopened.lookup(host.author)).toString())
        retrieved.forEach { entry ->
            assertEquals(entry.page.toString(), ok(reopened.read(host.author, entry.cursor)).toString())
        }
        val changed = ok(store.publish(host.author, "Original goal", "[]", contexts + ("roster" to "Changed roster")))
        assertNotEquals(descriptor.getString("snapshot_id"), changed.getString("snapshot_id"))
        rejected(store.bind(host.author, changed.getString("snapshot_id")), "access_already_bound")
        assertEquals(descriptor.toString(), ok(store.lookup(host.author)).toString())
    }

    @Test fun shortContextDirectoryIsCompleteAndInvalidUnicodeContextIsRejected() {
        val host = Host()
        val store = host.store()
        val descriptor = ok(store.publish(host.author, "Original", "[]", mapOf("roster" to "A, B", "previousAssessment" to "Untested")))
        assertTrue(descriptor.getBoolean("context_keys_complete"))
        assertEquals("[\"previousAssessment\",\"roster\"]", descriptor.getJSONArray("context_keys").toString())
        val before = host.rows.data.toMap()
        rejected(store.publish(host.author, "Original", "[]", mapOf("roster" to "broken\uD800")), "invalid_context")
        rejected(store.publish(host.author, "Original", "[]", mapOf("\uDC00" to "content")), "invalid_context")
        rejected(store.publish(host.author, "Original", "[]", mapOf("" to "content")), "invalid_context")
        assertEquals(before, host.rows.data)
    }
}
