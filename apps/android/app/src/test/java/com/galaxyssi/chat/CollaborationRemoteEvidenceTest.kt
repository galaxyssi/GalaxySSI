package com.galaxyssi.chat

import java.util.Base64
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationRemoteEvidenceTest {
    private class Rows : CollaborationRemoteEvidenceRows, CollaborationWorkspaceRows {
        val data = sortedMapOf<String, String>()
        var failAdvance = false
        override fun read(key: String) = data[key]
        override fun mutate(values: Map<String, String>, remove: List<String>) {
            if (failAdvance && values.values.any { it.contains("\"cursor\":1") }) error("Simulated disk failure")
            remove.forEach(data::remove); data.putAll(values)
        }
        override fun commit(values: Map<String, String>) { data.putAll(values) }
        override fun keys(prefix: String, after: String, limit: Int) = data.keys.filter { it.startsWith(prefix) && it > after }.take(limit)
        override fun page(prefix: String, after: String, limit: Int) = keys(prefix, after, limit)
    }
    private fun fields() = JSONObject().apply {
        AgentResultRecoveryClient.FIELDS.forEach { put(it, it) }
    }.put("agent_id", "codex").put("source_message_id", "123").put("conversation_id", "group")
        .put("turn_id", "turn").put("execution_generation", 2)
    private fun access() = CollaborationWorkspaceAccess("group", "run", "turn", 1, "node", "author")
    private class Provider(val fields: JSONObject, count: Int = 1, size: Int = 20000, failed: Boolean = false,
        val inline: Boolean = false, var sealed: Boolean = true) {
        var queries = 0
        val pagesRead = mutableListOf<Pair<Int, Int>>()
        val bodies = (1..count).map { id ->
            JSONObject(fields.toString()).put("contract", CollaborationRemoteEvidenceProtocol.CONTRACT)
                .put("trust", CollaborationRemoteEvidenceProtocol.TRUST).put("coverage", "provider_payload_as_received")
                .put("observation", JSONObject().put("provider", "codex").put("thread_id", "provider-thread")
                    .put("turn_id", "provider-turn").put("item", JSONObject().put("id", "item-$id")
                        .put("type", "commandExecution").put("exitCode", if (failed) 1 else 0)
                        .put("aggregatedOutput", "Evidence \u8bc1\u636e ".repeat(size / 10)))).toString().toByteArray()
        }
        val entries = bodies.mapIndexed { index, body -> JSONObject().put("sequence", index + 1)
            .put("evidence_id", AgentNativeJsonCodec.sha256("item-$index")).put("sha256", AgentResultRecoveryClient.sha256(body))
            .put("total_bytes", body.size).put("page_count", (body.size + 16383) / 16384).put("item_type", "commandExecution")
            .put("outcome", if (failed) "failed" else "returned").put("trust", CollaborationRemoteEvidenceProtocol.TRUST)
            .put("coverage", "provider_payload_as_received").put("recorded_at", 123456L) }
        fun reply(request: JSONObject): JSONObject {
            queries++
            val result = JSONObject(fields.toString()).put("type", "agent_task_evidence")
                .put("contract", CollaborationRemoteEvidenceProtocol.CONTRACT).put("status", "ready")
                .put("mode", request.getString("mode")).put("request_id", request.optString("request_id"))
            if (request.getString("mode") == "index") {
                val cursor = request.getLong("after_sequence")
                val selected = entries.filter { it.getLong("sequence") > cursor }.take(20)
                val inlinePages = JSONArray()
                var remaining = request.optLong("inline_page_bytes")
                if (inline) selected.forEach { entry ->
                    if (entry.getInt("page_count") == 1 && entry.getLong("total_bytes") <= remaining) {
                        inlinePages.put(page(JSONObject(), entries.indexOf(entry), 0))
                        remaining -= entry.getLong("total_bytes")
                    }
                }
                return result.put("entries", JSONArray(selected)).put("next_sequence", selected.lastOrNull()?.getLong("sequence") ?: cursor)
                    .put("has_more", entries.size > cursor + selected.size).put("provider_history_complete", false)
                    .put("coverage", "observed_completed_items_only").put("archive_final", sealed).put("inline_pages", inlinePages)
            }
            val entryIndex = entries.indexOfFirst { it.getString("evidence_id") == request.getString("evidence_id") }
            val index = request.getInt("page_index")
            pagesRead.add(entryIndex to index)
            return page(result, entryIndex, index)
        }
        private fun page(result: JSONObject, entryIndex: Int, index: Int): JSONObject {
            val entry = entries[entryIndex]
            val body = bodies[entryIndex]
            val raw = body.copyOfRange(index * 16384, minOf(body.size, (index + 1) * 16384))
            entry.keys().forEach { result.put(it, entry.get(it)) }
            return result.put("status", "ready").put("page_index", index).put("page_sha256", AgentResultRecoveryClient.sha256(raw))
                .put("data_b64", Base64.getEncoder().encodeToString(raw))
        }
    }
    private class Fixture(fields: JSONObject, access: CollaborationWorkspaceAccess, terminal: Boolean = true) {
        val rows = Rows()
        val evidence = Rows()
        var authorized = true
        val store = CollaborationRemoteEvidenceStore(rows)
        val ledger = CollaborationEvidenceLedger(evidence) { authorized }
        val key: String
        init { ledger.bind(123, access); key = store.createIntent("desktop", fields, access, terminal).first }
        fun importer() = CollaborationRemoteEvidenceImporter(CollaborationRemoteEvidenceStore(rows), ledger)
    }
    private fun response(request: JSONObject) = JSONObject(request.toString()).put("type", "agent_task_evidence")
        .put("contract", CollaborationRemoteEvidenceProtocol.CONTRACT).put("status", "ready")

    @Test fun clientBindsEveryIdentityGenerationAndAuthenticatedDesktop(): Unit = runBlocking {
        val client = CollaborationRemoteEvidenceClient()
        lateinit var sent: JSONObject
        val job = async(start = CoroutineStart.UNDISPATCHED) {
            client.query("desktop", fields(), JSONObject().put("mode", "index")) { sent = it; true }
        }
        for (key in AgentResultRecoveryClient.FIELDS + listOf("execution_generation", "request_id", "mode", "contract", "type")) {
            assertFalse(key, client.receive(response(sent).put(key, if (key == "execution_generation") 3 else "wrong"), "desktop"))
        }
        assertFalse(client.receive(response(sent), "other-desktop"))
        assertTrue(client.receive(response(sent), "desktop"))
        assertNotNull(job.await()); assertEquals(0, client.pendingCount)
    }
    @Test fun pagesRequireExactReferenceAndIndex(): Unit = runBlocking {
        val client = CollaborationRemoteEvidenceClient()
        lateinit var sent: JSONObject
        val job = async(start = CoroutineStart.UNDISPATCHED) {
            client.query("desktop", fields(), JSONObject().put("mode", "page").put("evidence_id", "a".repeat(64))
                .put("sha256", "b".repeat(64)).put("page_index", 1)) { sent = it; true }
        }
        for (key in listOf("evidence_id", "sha256", "page_index"))
            assertFalse(client.receive(response(sent).put(key, if (key == "page_index") 0 else "c".repeat(64)), "desktop"))
        assertTrue(client.receive(response(sent), "desktop")); job.await()
    }
    @Test fun responseDiagnosticsDistinguishRejectionWithoutLeakingIdentityOrContent(): Unit = runBlocking {
        val client = CollaborationRemoteEvidenceClient()
        lateinit var sent: JSONObject
        val outcomes = mutableListOf<String>()
        val job = async(start = CoroutineStart.UNDISPATCHED) {
            client.query("desktop", fields(), JSONObject().put("mode", "index")) { sent = it; true }
        }
        assertFalse(client.receive(response(sent).put("request_id", "private-nonce"), "desktop", outcomes::add))
        assertFalse(client.receive(response(sent).put("conversation_id", "private-conversation"), "desktop", outcomes::add))
        assertFalse(client.receive(response(sent), "private-desktop", outcomes::add))
        assertTrue(client.receive(response(sent), "desktop", outcomes::add))
        assertNotNull(job.await())
        assertEquals(listOf("no_pending_request", "scope_mismatch", "desktop_mismatch", "accepted"), outcomes)
    }
    @Test fun timeoutCancellationAndPublishFailureRemoveWaiters(): Unit = runBlocking {
        val client = CollaborationRemoteEvidenceClient()
        val selection = JSONObject().put("mode", "index")
        assertNull(client.query("desktop", fields(), selection, 5) { true })
        assertNull(client.query("desktop", fields(), selection) { false })
        val job = async(start = CoroutineStart.UNDISPATCHED) { client.query("desktop", fields(), selection) { true } }
        job.cancel(); job.join(); assertEquals(0, client.pendingCount)
    }
    @Test fun strictScopeRejectsCoercionAndWrongProvider() {
        for (value in listOf("2", 2.0, 0, -1)) assertFalse(CollaborationRemoteEvidenceProtocol.validScope(fields().put("execution_generation", value)))
        assertFalse(CollaborationRemoteEvidenceProtocol.validScope(fields().put("source_message_id", 123)))
        assertFalse(CollaborationRemoteEvidenceProtocol.validScope(fields().put("agent_id", "deepseek")))
    }
    @Test fun originalsKeepExactBytesAndHostReceiptAfterReopen(): Unit = runBlocking {
        val f = Fixture(fields(), access()); val provider = Provider(fields())
        assertTrue(f.importer().run(f.key, { true }) { _, _, query -> provider.reply(query) })
        val ref = f.ledger.browse(access()).first.single()
        val saved = CollaborationEvidenceLedger(f.evidence).read(access(), ref.getString("evidence_id"), ref.getString("sha256"))!!
        val output = JSONObject(saved.getString("output_json"))
        assertEquals(String(provider.bodies.single(), Charsets.UTF_8), output.getString("original_json"))
        assertEquals("desktop_codex_tool", saved.getString("origin"))
        assertEquals("returned", saved.getString("status"))
        assertEquals(CollaborationRemoteEvidenceProtocol.TRUST, saved.getString("trust"))
        assertFalse(f.store.read(f.key)!!.getBoolean("provider_history_complete"))
        assertTrue(f.store.pending().isEmpty()); assertFalse(f.rows.data.keys.any { ":page:" in it })
    }
    @Test fun smallSealedEvidenceNeedsOnlyOneRoundTrip(): Unit = runBlocking {
        val f = Fixture(fields(), access()); val provider = Provider(fields(), count = 3, size = 100, inline = true, sealed = true)
        assertTrue(f.importer().run(f.key, { true }) { _, _, q -> provider.reply(q) })
        assertEquals(1, provider.queries); assertTrue(provider.pagesRead.isEmpty())
        assertEquals(3L, f.store.read(f.key)!!.getLong("imported"))
        assertEquals("imported", f.store.read(f.key)!!.getString("status"))
        assertFalse(f.store.read(f.key)!!.getBoolean("provider_history_complete"))
    }
    @Test fun runningSnapshotIsNotFinalAndDoesNotPollContinuously(): Unit = runBlocking {
        val f = Fixture(fields(), access(), terminal = false)
        val provider = Provider(fields(), size = 100, inline = true, sealed = false)
        assertTrue(f.importer().run(f.key, { true }) { _, _, q -> provider.reply(q) })
        assertEquals(1, provider.queries)
        assertEquals("snapshot_imported", f.store.read(f.key)!!.getString("status"))
        assertFalse(f.store.read(f.key)!!.getBoolean("archive_final"))
        assertTrue(f.store.pending().isEmpty())
        assertTrue(f.importer().run(f.key, { true }) { _, _, _ -> error("No unsolicited polling") })
    }
    @Test fun inlineCheckpointSurvivesCommitFailureWithoutNetworkReplay(): Unit = runBlocking {
        val f = Fixture(fields(), access()); val provider = Provider(fields(), size = 100, inline = true, sealed = true)
        f.rows.failAdvance = true
        assertTrue(runCatching { f.importer().run(f.key, { true }) { _, _, q -> provider.reply(q) } }.isFailure)
        f.rows.failAdvance = false
        assertTrue(f.importer().run(f.key, { true }) { _, _, _ -> error("Persisted inline page and boundary must survive reopen") })
        assertEquals(1, provider.queries); assertEquals(1, f.ledger.browse(access()).first.size)
    }
    @Test fun malformedInlineEvidenceCannotBypassPageOrScopeChecks(): Unit = runBlocking {
        for (fault in listOf("hash", "id", "index", "duplicate")) {
            val f = Fixture(fields(), access()); val provider = Provider(fields(), size = 100, inline = true, sealed = true)
            assertTrue(f.importer().run(f.key, { true }) { _, _, q -> provider.reply(q).apply {
                val pages = getJSONArray("inline_pages"); val page = pages.getJSONObject(0)
                when (fault) {
                    "hash" -> page.put("page_sha256", "0".repeat(64))
                    "id" -> page.put("evidence_id", "a".repeat(64))
                    "index" -> page.put("page_index", 1)
                    else -> pages.put(JSONObject(page.toString()))
                }
            } })
            assertEquals(fault, "integrity_rejected", f.store.read(f.key)!!.getString("status"))
            assertTrue(f.ledger.browse(access()).first.isEmpty())
        }
    }
    @Test fun inlineIndexPagingRetainsAllObservations(): Unit = runBlocking {
        val f = Fixture(fields(), access()); val provider = Provider(fields(), count = 121, size = 1, inline = true, sealed = true)
        assertTrue(f.importer().run(f.key, { true }) { _, _, q -> provider.reply(q) })
        assertEquals(7, provider.queries); assertEquals(121L, f.store.read(f.key)!!.getLong("imported"))
    }
    @Test fun inlineTotalBudgetAndOriginalScopeRemainMandatory(): Unit = runBlocking {
        val budget = Fixture(fields(), access()); val large = Provider(fields(), count = 2, size = 7000, sealed = true)
        assertTrue(large.bodies.sumOf { it.size } > 16_384)
        assertTrue(budget.importer().run(budget.key, { true }) { _, _, q -> large.reply(q).put("inline_pages",
            JSONArray(large.entries.map { entry -> large.reply(JSONObject().put("mode", "page")
                .put("evidence_id", entry.getString("evidence_id")).put("page_index", 0)) })) })
        assertEquals("integrity_rejected", budget.store.read(budget.key)!!.getString("status"))
        assertTrue(budget.ledger.browse(access()).first.isEmpty())
        val scope = Fixture(fields(), access())
        val other = Provider(fields().put("task_id", "other-task"), size = 100, inline = true, sealed = true)
        assertTrue(scope.importer().run(scope.key, { true }) { _, _, q -> other.reply(q) })
        assertEquals("integrity_rejected", scope.store.read(scope.key)!!.getString("status"))
        assertTrue(scope.ledger.browse(access()).first.isEmpty())
    }
    @Test fun partialTransferResumesAtMissingPageWithoutRepeatingProvider(): Unit = runBlocking {
        val f = Fixture(fields(), access()); val provider = Provider(fields(), size = 50000)
        assertFalse(f.importer().run(f.key, { true }) { _, _, query ->
            if (query.optInt("page_index", -1) == 1) null else provider.reply(query)
        })
        assertTrue(f.ledger.browse(access()).first.isEmpty())
        assertTrue(f.importer().run(f.key, { true }) { _, _, query -> provider.reply(query) })
        assertEquals(1, provider.pagesRead.count { it.second == 0 })
        assertEquals(1, f.ledger.browse(access()).first.size)
    }
    @Test fun ledgerCommitBeforeCursorCrashReplaysIdempotently(): Unit = runBlocking {
        val f = Fixture(fields(), access()); val provider = Provider(fields())
        f.rows.failAdvance = true
        assertTrue(runCatching { f.importer().run(f.key, { true }) { _, _, q -> provider.reply(q) } }.isFailure)
        assertEquals(1, f.ledger.browse(access()).first.size)
        val reads = provider.pagesRead.size
        f.rows.failAdvance = false
        assertTrue(f.importer().run(f.key, { true }) { _, _, q -> provider.reply(q) })
        assertEquals(reads, provider.pagesRead.size); assertEquals(1, f.ledger.browse(access()).first.size)
    }
    @Test fun pauseBeforeOrDuringTransferPreservesCheckpoint(): Unit = runBlocking {
        val f = Fixture(fields(), access()); val provider = Provider(fields())
        assertFalse(f.importer().run(f.key, { false }) { _, _, q -> provider.reply(q) })
        assertEquals(0, provider.queries)
        var allowed = true
        assertFalse(f.importer().run(f.key, { allowed }) { _, _, q -> provider.reply(q).also { allowed = false } })
        assertTrue(f.ledger.browse(access()).first.isEmpty())
        assertTrue(f.importer().run(f.key, { true }) { _, _, q -> provider.reply(q) })
    }
    @Test fun groupRevocationCannotPublishOrResurrectJobs(): Unit = runBlocking {
        val f = Fixture(fields(), access()); val provider = Provider(fields())
        assertFalse(f.importer().run(f.key, { true }) { _, _, q -> provider.reply(q).also {
            f.authorized = false; f.store.remove("group")
        } })
        assertTrue(f.rows.data.isEmpty()); assertTrue(f.ledger.browse(access()).first.isEmpty())
    }
    @Test fun failedToolsAreNotPromotedToSuccessfulEvidence(): Unit = runBlocking {
        val f = Fixture(fields(), access()); val provider = Provider(fields(), failed = true)
        assertTrue(f.importer().run(f.key, { true }) { _, _, q -> provider.reply(q) })
        assertEquals("failed", f.ledger.browse(access()).first.single().getString("status"))
    }
    @Test fun invalidPageHashIsQuarantinedWithoutReceipt(): Unit = runBlocking {
        val f = Fixture(fields(), access()); val provider = Provider(fields())
        assertTrue(f.importer().run(f.key, { true }) { _, _, q -> provider.reply(q).apply {
            if (q.getString("mode") == "page") put("page_sha256", "0".repeat(64))
        } })
        assertEquals("integrity_rejected", f.store.read(f.key)!!.getString("status"))
        assertTrue(f.ledger.browse(access()).first.isEmpty())
    }
    @Test fun wrongInnerScopeCannotBorrowAnotherTasksOriginal(): Unit = runBlocking {
        val f = Fixture(fields(), access()); val provider = Provider(fields().put("task_id", "other-task"))
        assertTrue(f.importer().run(f.key, { true }) { _, _, q -> provider.reply(q) })
        assertEquals("integrity_rejected", f.store.read(f.key)!!.getString("status"))
        assertTrue(f.ledger.browse(access()).first.isEmpty())
    }
    @Test fun descriptorOutcomeCannotLieAboutOriginal(): Unit = runBlocking {
        val f = Fixture(fields(), access()); val provider = Provider(fields(), failed = true)
        provider.entries.single().put("outcome", "returned")
        assertTrue(f.importer().run(f.key, { true }) { _, _, q -> provider.reply(q) })
        assertEquals("integrity_rejected", f.store.read(f.key)!!.getString("status"))
    }
    @Test fun indexIsPagedWithoutATotalObservationLimit(): Unit = runBlocking {
        val f = Fixture(fields(), access()); val provider = Provider(fields(), count = 121, size = 1)
        assertTrue(f.importer().run(f.key, { true }) { _, _, q -> provider.reply(q) })
        assertEquals(121L, f.store.read(f.key)!!.getLong("imported"))
        assertEquals(128, provider.queries) // 121 bodies and seven populated index pages with a sealed boundary.
    }
    @Test fun oversizedOriginalsStayExplicitlyIncompleteAndDoNotBlockOthers(): Unit = runBlocking {
        val f = Fixture(fields(), access()); val provider = Provider(fields(), count = 2)
        val bytes = CollaborationRemoteEvidenceProtocol.MAX_BODY_BYTES + 1
        provider.entries[0].put("total_bytes", bytes).put("page_count", (bytes + 16383) / 16384)
        assertTrue(f.importer().run(f.key, { true }) { _, _, q -> provider.reply(q) })
        assertEquals("partial_large_objects", f.store.read(f.key)!!.getString("status"))
        assertEquals(1L, f.store.read(f.key)!!.getLong("imported"))
        assertTrue(provider.pagesRead.none { it.first == 0 })
    }
    @Test fun unavailableArchiveFinishesWithoutInventingEvidenceOrRetryingOperation(): Unit = runBlocking {
        val f = Fixture(fields(), access())
        assertTrue(f.importer().run(f.key, { true }) { _, _, _ -> JSONObject().put("status", "unavailable") })
        assertEquals("unavailable", f.store.read(f.key)!!.getString("status")); assertTrue(f.ledger.browse(access()).first.isEmpty())
    }
    @Test fun repeatedFinalDoesNotReopenCompletedImport(): Unit = runBlocking {
        val f = Fixture(fields(), access()); val provider = Provider(fields())
        f.importer().run(f.key, { true }) { _, _, q -> provider.reply(q) }
        assertEquals(f.key, f.store.create("desktop", fields(), access()))
        assertFalse(f.store.createIntent("desktop", fields(), access()).second)
        assertTrue(f.store.pending().isEmpty())
        assertTrue(f.importer().run(f.key, { true }) { _, _, _ -> error("No repeat query") })
    }
    @Test fun nextLiveReadImportsOnlyTheTailAndFinalCaptureRearmsDurably(): Unit = runBlocking {
        val f = Fixture(fields(), access(), terminal = false)
        val first = Provider(fields(), size = 100, inline = true, sealed = false)
        assertTrue(f.importer().run(f.key, { true }) { _, _, q -> first.reply(q) })
        val reopened = CollaborationRemoteEvidenceStore(f.rows)
        assertTrue(reopened.createIntent("desktop", fields(), access(), terminal = false).second)
        assertEquals(1, reopened.pending().size)
        val second = Provider(fields(), count = 2, size = 100, inline = true, sealed = false)
        assertTrue(f.importer().run(f.key, { true }) { _, _, q ->
            assertEquals(1L, q.getLong("after_sequence")); second.reply(q)
        })
        assertEquals(2L, reopened.read(f.key)!!.getLong("imported"))
        assertTrue(reopened.createIntent("desktop", fields(), access()).second)
        val final = Provider(fields(), count = 3, size = 100, inline = true)
        assertTrue(f.importer().run(f.key, { true }) { _, _, q ->
            assertEquals(2L, q.getLong("after_sequence")); final.reply(q)
        })
        assertEquals(3, f.ledger.browse(access()).first.size)
        assertEquals("imported", reopened.read(f.key)!!.getString("status"))
        assertTrue(reopened.read(f.key)!!.getBoolean("archive_final"))
        assertFalse(reopened.createIntent("desktop", fields(), access(), terminal = false).second)
        assertTrue(reopened.pending().isEmpty())
    }
    @Test fun terminalNotificationDuringLiveTransferCannotBeLost(): Unit = runBlocking {
        val f = Fixture(fields(), access(), terminal = false)
        val provider = Provider(fields(), size = 30000, sealed = false)
        var notified = false
        assertFalse(f.importer().run(f.key, { true }) { _, _, q ->
            if (!notified && q.getString("mode") == "page") {
                f.store.createIntent("desktop", fields(), access()); notified = true
            }
            provider.reply(q)
        })
        val pending = f.store.read(f.key)!!
        assertTrue(pending.getBoolean("terminal_requested"))
        assertEquals("pending", pending.getString("status"))
        assertEquals(1, f.store.pending().size)
        provider.sealed = true
        assertTrue(f.importer().run(f.key, { true }) { _, _, q ->
            assertEquals("index", q.getString("mode")); assertEquals(1L, q.getLong("after_sequence")); provider.reply(q)
        })
        assertEquals(1, f.ledger.browse(access()).first.size)
        assertEquals("imported", f.store.read(f.key)!!.getString("status"))
    }
    @Test fun finalDemandWaitsForArchiveSealWithoutSpinningInsideOnePass(): Unit = runBlocking {
        val f = Fixture(fields(), access()); val provider = Provider(fields(), count = 0, sealed = false)
        assertFalse(f.importer().run(f.key, { true }) { _, _, q -> provider.reply(q) })
        assertEquals(1, provider.queries)
        assertEquals("pending", f.store.read(f.key)!!.getString("status"))
        assertTrue(f.ledger.browse(access()).first.isEmpty())
        provider.sealed = true
        assertTrue(f.importer().run(f.key, { true }) { _, _, q -> provider.reply(q) })
        assertEquals(2, provider.queries)
    }
    @Test fun parallelImportersShareOneCursorAndCannotReplayPages(): Unit = runBlocking {
        val f = Fixture(fields(), access()); val provider = Provider(fields(), size = 100, inline = true)
        val entered = CompletableDeferred<Unit>(); val release = CompletableDeferred<Unit>()
        val first = async(start = CoroutineStart.UNDISPATCHED) {
            f.importer().run(f.key, { true }) { _, _, q -> entered.complete(Unit); release.await(); provider.reply(q) }
        }
        entered.await()
        val other = async(start = CoroutineStart.UNDISPATCHED) {
            f.importer().run(f.key, { true }) { _, _, _ -> error("Duplicate transfer") }
        }
        release.complete(Unit)
        withTimeout(1_000) { assertTrue(first.await()); assertTrue(other.await()) }
        assertEquals(1, provider.queries); assertEquals(1, f.ledger.browse(access()).first.size)
    }
    @Test fun quarantineAndRevocationCannotBeReopenedByLiveOrFinalReads(): Unit = runBlocking {
        for (status in listOf("revoked", "stopped", "superseded", "integrity_rejected")) {
            val f = Fixture(fields(), access(), terminal = false)
            val stale = f.store.read(f.key)!!
            f.store.save(f.key, JSONObject(stale.toString()).put("status", status))
            f.store.createIntent("desktop", fields(), access(), terminal = false)
            f.store.createIntent("desktop", fields(), access())
            f.store.save(f.key, stale)
            f.store.completeSnapshot(f.key, stale)
            assertEquals(status, f.store.read(f.key)!!.getString("status"))
            assertTrue(f.store.pending().isEmpty())
        }
    }
    @Test fun generationsAndMembersHaveIndependentJobsAndAccess(): Unit = runBlocking {
        val f = Fixture(fields(), access()); val provider = Provider(fields())
        f.importer().run(f.key, { true }) { _, _, q -> provider.reply(q) }
        assertNotEquals(f.key, f.store.create("desktop", fields().put("execution_generation", 3), access()))
        val id = f.ledger.browse(access()).first.single().getString("evidence_id")
        assertNull(f.ledger.read(access().copy(nodeId = "independent", personId = "other"), id))
        assertNotNull(f.ledger.read(access().copy(nodeId = "reviewer", personId = "other", dependencyNodes = setOf("node")), id))
    }
    @Test fun evidenceQueriesDoNotEnterPersistentOutbox() {
        assertTrue(MqttQueryDeliveryPolicy.isTransient("agent_task_evidence_request"))
        assertTrue(MqttQueryDeliveryPolicy.hasRetryOwner("agent_task_evidence_request"))
    }
    @Test fun schedulerPositionPersistsAcrossReopenAndStateReadsExcludePagePayloads() {
        val f = Fixture(fields(), access())
        f.store.schedulerCursor("pending:last")
        assertEquals("pending:last", CollaborationRemoteEvidenceStore(f.rows).schedulerCursor())
        val provider = Provider(fields())
        val entry = provider.entries.single()
        f.store.savePage(f.key, entry, 0, provider.reply(JSONObject().put("mode", "page")
            .put("evidence_id", entry.getString("evidence_id")).put("page_index", 0)))
        assertEquals(1, f.store.states("group", 123).size)
        f.store.remove("group")
        assertTrue(f.store.pending().isEmpty()); assertEquals(setOf("scheduler:cursor"), f.rows.data.keys)
    }
    @Test fun invalidIndexDoesNotLoopOrAllocateUnboundedPages(): Unit = runBlocking {
        val f = Fixture(fields(), access()); val provider = Provider(fields())
        provider.entries.single().put("page_count", Int.MAX_VALUE)
        assertTrue(f.importer().run(f.key, { true }) { _, _, q -> provider.reply(q) })
        assertEquals("integrity_rejected", f.store.read(f.key)!!.getString("status"))
        assertTrue(provider.pagesRead.isEmpty())
    }
}
