package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CloudWebToolLoopProgressTest {
    private data class GoalPage(val arguments: JSONObject, val output: String)

    private fun rulePage(topic: String, offset: Int = 0, explicitTopic: Boolean = true): GoalPage {
        val reference = CollaborationEvolutionProtocol.rules(topic).toString()
        val start = offset.coerceAtMost(reference.length)
        val end = minOf(reference.length, start + 8_000)
        val arguments = JSONObject().put("mode", "evolution_rules").put("offset", offset)
        if (explicitTopic) arguments.put("topic", topic)
        val output = JSONObject().put("status", "returned").put("topic", topic)
            .put("trust", "host_schema_not_execution_authority").put("content", reference.substring(start, end))
            .put("total_characters", reference.length).put("next_offset", if (end < reference.length) end else JSONObject.NULL)
        return GoalPage(arguments, output.toString())
    }

    @Test fun completeRulePaginationDoesNotForcePrematureSynthesis() {
        val progress = CloudWebToolLoopProgress()
        val length = CollaborationEvolutionProtocol.rules().toString().length
        assertTrue(length > 24_000)
        for (offset in 0 until length step 8_000) assertFalse(recordPage(progress, rulePage("all", offset)))
        assertFalse(progress.finalizationRequested)
        assertStagnant(progress, rulePage("all").output)
    }

    @Test fun repeatedAndOverlappingRulesCannotManufactureReadingProgress() {
        val progress = CloudWebToolLoopProgress()
        val page = rulePage("all")
        assertFalse(recordPage(progress, page))
        val alias = rulePage("all", explicitTopic = false)
        assertTrue(progress.record(CollaborationCloudRecall.NAME, alias.arguments, alias.output))
        assertStagnant(progress, alias.output)
        assertFalse(recordPage(progress, rulePage("all", 4_000)))
        val overlap = rulePage("all", 2_000)
        assertTrue(progress.record(CollaborationCloudRecall.NAME, overlap.arguments, overlap.output))
        assertStagnant(progress, overlap.output)
        val eof = rulePage("all", Int.MAX_VALUE)
        assertTrue(progress.record(CollaborationCloudRecall.NAME, eof.arguments, eof.output))
        assertTrue(progress.observeEvidenceBatch(listOf(eof.output)))
    }

    @Test fun topicsRemainDistinctAndCheckpointReplaysDoNotBecomeNewKnowledge() {
        val pages = listOf(rulePage("catalog"), rulePage("foundation"), rulePage("workflows"), rulePage("tools"))
        val live = CloudWebToolLoopProgress()
        pages.forEach { assertFalse(recordPage(live, it)) }
        assertEquals(pages.last().output, live.cached(CollaborationCloudRecall.NAME, pages.last().arguments))
        assertNull(live.cached(CollaborationCloudRecall.NAME, rulePage("retention").arguments))
        val restored = CloudWebToolLoopProgress()
        pages.forEach { assertTrue(restored.record(CollaborationCloudRecall.NAME, it.arguments, it.output)) }
        assertFalse(restored.observeEvidenceBatch(pages.map { it.output }))
        assertStagnant(restored, pages.first().output)
    }

    @Test fun ruleProgressRequiresAuthenticExecutionAndExactHostSchema() {
        val page = rulePage("workflows")
        assertStagnant(CloudWebToolLoopProgress(), page.output)
        val mutations: List<(JSONObject) -> Unit> = listOf(
            { it.put("status", "failed") }, { it.put("topic", "tools") }, { it.put("content", "New rules") },
            { it.put("total_characters", 1) }, { it.put("next_offset", 1) },
            { it.remove("next_offset") }, { it.remove("trust") }, { it.put("error", "denied") })
        mutations.forEach { change ->
            val progress = CloudWebToolLoopProgress()
            val changed = JSONObject(page.output).also(change).toString()
            assertTrue(progress.record(CollaborationCloudRecall.NAME, page.arguments, changed))
            assertStagnant(progress, changed)
        }
        val invalidArguments = listOf(JSONObject(page.arguments.toString()).put("mode", "workspace"),
            JSONObject(page.arguments.toString()).put("topic", 1), JSONObject(page.arguments.toString()).put("offset", -1),
            JSONObject(page.arguments.toString()).put("offset", "0"), JSONObject(page.arguments.toString()).put("group_id", "other"))
        invalidArguments.forEach { arguments ->
            val progress = CloudWebToolLoopProgress()
            assertTrue(progress.record(CollaborationCloudRecall.NAME, arguments, page.output))
            assertStagnant(progress, page.output)
        }
        val wrongTool = CloudWebToolLoopProgress()
        assertTrue(wrongTool.record("web_fetch", page.arguments, page.output))
        assertStagnant(wrongTool, page.output)
    }

    private fun goalPages(goal: String = "g".repeat(20_000), person: String = "person-a",
                          criteria: String = "[]"): List<GoalPage> {
        val rows = object : CollaborationGoalContractRows {
            private val values = linkedMapOf<String, String>()
            override fun read(key: String) = values[key]
            override fun commit(values: Map<String, String>) { this.values.putAll(values) }
            override fun removePrefix(prefix: String) { values.keys.removeAll { it.startsWith(prefix) } }
        }
        val store = CollaborationGoalContractStore(rows, { true })
        val access = CollaborationWorkspaceAccess("group", "run", "turn", 1, "node", person)
        val descriptor = store.publish(access, goal, criteria)
        assertEquals("ok", descriptor.optString("status"))
        assertEquals("ok", store.bind(access, descriptor.getString("snapshot_id")).optString("status"))
        val pages = mutableListOf<GoalPage>()
        var cursor = ""
        do {
            val page = store.read(access, cursor)
            assertEquals("ok", page.optString("status"))
            val arguments = JSONObject().put("mode", "goal_contract").put("cursor", cursor)
            // Match ScopedRecall and CloudRecall's successful transport envelope over a real store page.
            page.put("status", "returned").put("trust", "host_goal_contract_not_comprehension_or_claim_verification")
            pages += GoalPage(arguments, page.toString())
            if (page.isNull("next_cursor")) break
            cursor = page.getString("next_cursor")
        } while (true)
        return pages
    }

    private fun recordPage(progress: CloudWebToolLoopProgress, page: GoalPage): Boolean {
        assertTrue(progress.record(CollaborationCloudRecall.NAME, page.arguments, page.output))
        return progress.observeEvidenceBatch(listOf(page.output))
    }

    private fun assertStagnant(progress: CloudWebToolLoopProgress, output: String) {
        assertFalse(progress.observeEvidenceBatch(listOf(output)))
        assertFalse(progress.observeEvidenceBatch(listOf(output)))
        assertTrue(progress.observeEvidenceBatch(listOf(output)))
    }

    @Test fun fourConsecutiveTrustedGoalPagesKeepALargeGoalReadable() {
        val pages = goalPages("g".repeat(100_000))
        assertTrue(pages.size > 4)
        val progress = CloudWebToolLoopProgress()
        pages.forEach { assertFalse(recordPage(progress, it)) }
        assertFalse(progress.finalizationRequested)
        assertStagnant(progress, pages.last().output)
    }

    @Test fun repeatedGoalPageWithANewReceiptDoesNotResetStagnation() {
        val page = goalPages().first()
        val progress = CloudWebToolLoopProgress()
        assertFalse(recordPage(progress, page))
        val repeated = JSONObject(page.output).put("galaxyssi_evidence_receipt", JSONObject().put("invocation_id", "second-read")).toString()
        val withoutCursor = JSONObject().put("mode", "goal_contract")
        assertTrue(progress.record(CollaborationCloudRecall.NAME, withoutCursor, repeated))
        assertStagnant(progress, repeated)
        assertFalse(progress.record(CollaborationCloudRecall.NAME, page.arguments, page.output))
        assertTrue(progress.observeEvidenceBatch(emptyList()))
    }

    @Test fun goalPageProgressIsScopedToBothSnapshotAndReader() {
        val original = goalPages()[1]
        val otherSnapshot = goalPages(criteria = """[{"id":"c","requirement":"Preserve the original goal"}]""")[1]
        val otherReader = goalPages(person = "person-b")[1]
        val a = JSONObject(original.output)
        val b = JSONObject(otherSnapshot.output)
        val c = JSONObject(otherReader.output)
        assertFalse(a.getString("snapshot_id") == b.getString("snapshot_id"))
        assertEquals(a.getString("reader_sha256"), b.getString("reader_sha256"))
        assertEquals(a.getString("snapshot_id"), c.getString("snapshot_id"))
        assertFalse(a.getString("reader_sha256") == c.getString("reader_sha256"))
        assertEquals(a.getString("page_sha256"), b.getString("page_sha256"))
        assertEquals(a.getString("page_sha256"), c.getString("page_sha256"))
        val progress = CloudWebToolLoopProgress()
        listOf(original, otherSnapshot, otherReader).forEach { page ->
            assertFalse(recordPage(progress, page))
            assertFalse(progress.observeEvidenceBatch(emptyList()))
            assertFalse(progress.observeEvidenceBatch(emptyList()))
        }
        assertTrue(progress.observeEvidenceBatch(listOf(original.output)))
    }

    @Test fun goalPageContentCannotClaimItsOwnTrustedExecution() {
        val page = goalPages().first()
        val claimed = JSONObject(page.output).put("tool", CollaborationCloudRecall.NAME).toString()
        assertStagnant(CloudWebToolLoopProgress(), claimed)
        val wrongTool = CloudWebToolLoopProgress()
        assertTrue(wrongTool.record("research_evidence_audit", page.arguments, claimed))
        assertStagnant(wrongTool, claimed)
        val wrongMode = CloudWebToolLoopProgress()
        assertTrue(wrongMode.record(CollaborationCloudRecall.NAME, JSONObject().put("mode", "workspace"), claimed))
        assertStagnant(wrongMode, claimed)
        val extraArguments = CloudWebToolLoopProgress()
        assertTrue(extraArguments.record(CollaborationCloudRecall.NAME,
            JSONObject(page.arguments.toString()).put("snapshot_id", JSONObject(claimed).getString("snapshot_id")), claimed))
        assertStagnant(extraArguments, claimed)
        val alteredAfterExecution = CloudWebToolLoopProgress()
        assertTrue(alteredAfterExecution.record(CollaborationCloudRecall.NAME, page.arguments, page.output))
        assertStagnant(alteredAfterExecution, claimed)
    }

    @Test fun failedOrMalformedGoalPagesNeverResetStagnation() {
        val page = goalPages().first()
        val mutations: List<(JSONObject) -> Unit> = listOf(
            { it.put("status", "failed") },
            { it.put("status", "ok") },
            { it.put("error", JSONObject().put("code", "access_denied")) },
            { it.put("snapshot_sha256", "0".repeat(64)) },
            { it.put("reader_sha256", "not-a-host-hash") },
            { it.put("page_sha256", "not-a-host-hash") },
            { it.put("page_index", -1) },
            { it.put("page_index", "0") },
            { it.put("page_index", it.getInt("page_count")) },
            { it.put("page_count", 0) },
            { it.put("fragments", JSONArray()) },
            { it.put("next_cursor", JSONObject.NULL) },
            { it.remove("trust") })
        mutations.forEach { mutate ->
            val output = JSONObject(page.output).also(mutate).toString()
            val progress = CloudWebToolLoopProgress()
            assertTrue(progress.record(CollaborationCloudRecall.NAME, page.arguments, output))
            assertStagnant(progress, output)
        }
    }

    @Test fun changingTheHashOfAnAlreadyObservedPinnedPageIsNotProgress() {
        val page = goalPages().first()
        val progress = CloudWebToolLoopProgress()
        assertFalse(recordPage(progress, page))
        val changed = JSONObject(page.output).put("page_sha256", "0".repeat(64)).toString()
        assertTrue(progress.record(CollaborationCloudRecall.NAME, JSONObject().put("mode", "goal_contract"), changed))
        assertStagnant(progress, changed)
    }

    @Test fun recordedCheckpointPagesDoNotBecomeFreshProgressOnReplay() {
        val pages = goalPages().take(4)
        val progress = CloudWebToolLoopProgress()
        pages.forEach { assertTrue(progress.record(CollaborationCloudRecall.NAME, it.arguments, it.output)) }
        assertFalse(progress.observeEvidenceBatch(pages.map { it.output }))
        assertFalse(progress.observeEvidenceBatch(pages.map { it.output }))
        assertFalse(progress.observeEvidenceBatch(pages.map { it.output }))
        assertTrue(progress.observeEvidenceBatch(pages.map { it.output }))
    }

    @Test fun retrievalDeadlineStillAllowsOneToolFreeSynthesis() {
        val progress = CloudWebToolLoopProgress()
        assertFalse(progress.requestDeadlineSynthesis(false))
        assertFalse(progress.finalizationRequested)
        assertTrue(progress.requestDeadlineSynthesis(true))
        assertTrue(progress.finalizationRequested)
        assertFalse(progress.requestDeadlineSynthesis(true))
    }

    @Test fun citationRepairGetsItsOwnSynthesisBudgetAndDoesNotLoop() {
        val progress = CloudWebToolLoopProgress()
        assertTrue(progress.requestSynthesisCitationRepair())
        assertTrue(progress.finalizationRequested)
        assertFalse(progress.requestSynthesisCitationRepair())
        assertFalse(progress.requestDeadlineSynthesis(true))
    }

    @Test fun finalizationStillAllowsOneCitationCorrection() {
        val progress = CloudWebToolLoopProgress()
        progress.requestFinalization()
        assertTrue(progress.requestSynthesisCitationRepair())
        assertFalse(progress.requestSynthesisCitationRepair())
    }

    @Test fun emptySynthesisIsRetriedOnceWithoutRepeatingTools() {
        val progress = CloudWebToolLoopProgress()
        assertFalse(progress.requestEmptySynthesisRepair("", false))
        assertFalse(progress.requestEmptySynthesisRepair("Answer", true))
        assertTrue(progress.requestEmptySynthesisRepair("  ", true))
        assertFalse(progress.requestEmptySynthesisRepair("", true))
        assertTrue(CloudWebToolLoopProgress().requestEmptySynthesisRepair("", true))
    }

    @Test fun aRetrievedPageIsReusedOnlyForEquivalentUnfocusedReads() {
        val progress = CloudWebToolLoopProgress()
        val args = JSONObject().put("url", "https://example.test/page")
        val body = JSONObject().put("status", "completed").put("evidence_pack", JSONObject()
            .put("items", JSONArray().put(JSONObject().put("url", args.getString("url"))
                .put("evidence_level", "retrieved_body").put("excerpt", "The actual page body.")))).toString()
        progress.record("web_fetch", args, body)
        assertEquals(body, progress.cached("web_extract", args))
        assertNull(progress.cached("web_extract", JSONObject(args.toString()).put("fields", JSONArray().put("date"))))
        assertNull(progress.cached("web_fetch", JSONObject(args.toString()).put("force", true)))
        assertNull(progress.cached("web_fetch", JSONObject(args.toString()).put("focus", "missing counterexample")))
        assertNull(progress.cached("web_fetch", JSONObject(args.toString()).put("offset", 8000)))
        assertNull(progress.cached("web_fetch", JSONObject(args.toString()).put("length", 4000)))
        assertNull(CloudWebToolLoopProgress().cached("web_extract", args))
    }

    @Test fun snippetsAndDifferentUrlsCannotSatisfyARequestedPageRead() {
        val progress = CloudWebToolLoopProgress()
        val args = JSONObject().put("url", "https://example.test/page")
        val snippet = """{"status":"completed","evidence_pack":{"items":[{"url":"https://example.test/page","evidence_level":"discovery_snippet"}]}}"""
        progress.record("web_fetch", args, snippet)
        assertNull(progress.cached("web_extract", args))
        assertNull(progress.cached("web_extract", JSONObject().put("url", "https://another.example.test/page")))
    }

    @Test fun timedOutPageIsNotFetchedAgainThroughAnotherReadTool() {
        val progress = CloudWebToolLoopProgress()
        val arguments = JSONObject().put("url", "https://example.test/page?q=%E4%B8%AD")
        val failure = """{"status":"failed","error_code":"web_source_timeout","retryable":false}"""
        progress.record("web_fetch", arguments, failure)
        assertEquals(failure, progress.cached("web_extract", arguments))
        assertNull(progress.cached("web_extract", JSONObject().put("url", "https://another.example.test/page")))
        assertNull(CloudWebToolLoopProgress().cached("web_fetch", arguments))
    }

    @Test
    fun distinctModelCallsAreNotStoppedByAnAppCountBudget() {
        val progress = CloudWebToolLoopProgress()

        repeat(1_000) { index ->
            val arguments = JSONObject().put("query", "evidence-$index")
            assertTrue(progress.record("web_search", arguments, "result-$index"))
        }

        assertEquals(
            "result-999",
            progress.cached("web_search", JSONObject().put("query", "evidence-999"))
        )
        assertFalse(progress.finalizationRequested)
    }

    @Test
    fun equivalentJsonArgumentsReuseTheSameToolResult() {
        val progress = CloudWebToolLoopProgress()
        val first = JSONObject()
            .put("query", "GalaxySSI")
            .put("filters", JSONObject().put("year", 2026).put("kind", "news"))
            .put("engines", JSONArray().put("brave").put("bing"))
        val reordered = JSONObject()
            .put("engines", JSONArray().put("brave").put("bing"))
            .put("filters", JSONObject().put("kind", "news").put("year", 2026))
            .put("query", "GalaxySSI")

        assertNull(progress.cached("web_search", first))
        assertTrue(progress.record("web_search", first, "evidence"))
        assertEquals("evidence", progress.cached("WEB_SEARCH", reordered))
        assertFalse(progress.record("web_search", reordered, "duplicate"))
    }

    @Test
    fun noProgressFinalizationAndRepairSignalsAreOneShot() {
        val progress = CloudWebToolLoopProgress()

        assertTrue(progress.requestRepair("citations"))
        assertFalse(progress.requestRepair("citations"))
        assertTrue(progress.requestRepair("protocol"))
        assertTrue(progress.requestFinalization())
        assertTrue(progress.finalizationRequested)
        assertFalse(progress.requestFinalization())
    }
}
