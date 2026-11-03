package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationCandidateLiveGraphTest {
    private class Rows : CollaborationWorkspaceRows {
        val values = sortedMapOf<String, String>()
        override fun read(key: String) = values[key]
        override fun commit(values: Map<String, String>) { this.values.putAll(values) }
        override fun page(prefix: String, after: String, limit: Int) = values.keys.filter { it.startsWith(prefix) && it > after }.take(limit)
    }
    private class Fixture {
        val rows = Rows()
        val ledger = CollaborationEvidenceLedger(Rows())
        var authorized = true
        val workspace = CollaborationResearchWorkspace(rows, { authorized }, ledger::references,
            evidenceReadCoverage = ledger::requireReadCoverage)
        val access = CollaborationWorkspaceAccess("group", "run", "turn", 5, "lead-dispatch", "lead")
        val people = setOf("lead", "author", "editor", "reviewer")
        val criterion = JSONObject().put("id", "accuracy").put("requirement", "Documented accuracy")
            .put("verification", "documentary").put("required_observations", JSONArray().put(JSONObject()
                .put("origin", "android_cloud_tool").put("tool", "original_check")))
        val source = ledger.record(access.copy(nodeId = "source", personId = "author", round = 0), "call", "original_check", "{}", "{\"value\":17}", 1, 2)
        val target = seed("a")
        fun candidate(id: String) = JSONObject().put("id", id).put("kind", "candidate").put("title", id)
            .put("body", JSONObject().put("content", "Original $id").put("candidate", JSONObject()
                .put("operation", "propose").put("rationale", "Check this alternative")
                .put("criteria", JSONArray().put("Documented accuracy"))))
        fun seed(id: String, round: Long = 0) = publish(access.copy(nodeId = "seed-$id", personId = "author", round = round), candidate(id))
        fun request(ref: JSONObject = target, vararg producers: String) = JSONObject().put("target", ref)
            .put("criterion_id", "accuracy").put("editor", "editor").put("reviewer", "reviewer")
            .apply { if (producers.isNotEmpty()) put(CollaborationCandidateLiveGraph.PRODUCERS, JSONArray(producers.toList())) }
        fun node(work: String, dispatch: String = work, status: CollaborationCandidateLiveGraph.Status = CollaborationCandidateLiveGraph.Status.RUNNING,
            person: String = "author") = CollaborationCandidateLiveGraph.Node(work, dispatch, person, status, "opaque-host-node:$work")
        fun snapshot(vararg nodes: CollaborationCandidateLiveGraph.Node<String>) = CollaborationCandidateLiveGraph.Snapshot(
            "group", "run", "turn", 10, nodes.toList(), nodes.mapTo(linkedSetOf()) { it.workId },
            mapOf("archived" to "original artifact bytes"), CollaborationCandidateLiveGraph.Control.RUN, Int.MAX_VALUE)
        fun plan(snapshot: CollaborationCandidateLiveGraph.Snapshot<String>, previous: String = "[]",
            requests: JSONArray = JSONArray().put(request()), grants: Set<String> = snapshot.nodes.filter { it.workId in snapshot.visibleWorkIds }.mapTo(hashSetOf()) { it.dispatchId }) =
            CollaborationCandidateLiveGraph.plan(workspace, access.copy(dependencyNodes = grants), people, JSONArray().put(criterion),
                requests, previous, snapshot) { "dispatch:$it" }
        fun installed(plan: CollaborationCandidateLiveGraph.Plan<String>) = plan.retained.copy(generation = plan.retained.generation + 1,
            nodes = plan.retained.nodes + plan.additions.map { node(it.work.getString("id"), it.dispatchId,
                CollaborationCandidateLiveGraph.Status.QUEUED, it.work.getString("member")) },
            visibleWorkIds = plan.retained.visibleWorkIds + plan.additions.map { it.work.getString("id") })
        fun complete(snapshot: CollaborationCandidateLiveGraph.Snapshot<String>, addition: CollaborationCandidateLiveGraph.Addition,
            status: CollaborationCandidateLiveGraph.Status = CollaborationCandidateLiveGraph.Status.SUCCEEDED) = snapshot.copy(
            generation = snapshot.generation + 1,
            nodes = snapshot.nodes.map { if (it.dispatchId == addition.dispatchId) it.copy(status = status) else it },
            completedOutputs = snapshot.completedOutputs + (addition.dispatchId to "retained opaque completion"))
        fun execute(addition: CollaborationCandidateLiveGraph.Addition, outcome: String = "refuted") {
            enroll(addition)
            val task = JSONObject(CollaborationCandidateEvolution.taskContext(addition.work).getValue(CollaborationCandidateEvolution.TASK))
            val target = task.getJSONObject("target")
            val item = if (task.getString("operation") == "review") JSONObject().put("id", AgentNativeJsonCodec.sha256(addition.dispatchId))
                .put("kind", "candidate_event").put("title", "Independent exact review").put("observations", JSONArray().put(source))
                .put("body", JSONObject().put("candidate_event", JSONObject().put("operation", "review").put("targets", JSONArray().put(target))
                    .put("criterion", "Documented accuracy").put("check", "Compare original source").put("rationale", "Documentary finding")
                    .put("outcome", outcome).put("unresolved", JSONArray().apply { if (outcome != "supported") put("Repair needed") })))
            else candidate("ignored").put("object_id", target.getString("object_id")).put("base_revision", target.getInt("revision"))
                .put("parents", JSONArray().put(target)).put("observations", JSONArray().put(source)).apply {
                    getJSONObject("body").put("content", "Repaired original")
                    getJSONObject("body").getJSONObject("candidate").put("operation", "revise").put("basis", task.getJSONObject("basis"))
                }
            publish(access.copy(nodeId = addition.dispatchId, personId = task.getString("member"), dependencyNodes = addition.dependencyDispatchIds), item, task)
        }
        fun enroll(addition: CollaborationCandidateLiveGraph.Addition) {
            val task = JSONObject(CollaborationCandidateEvolution.taskContext(addition.work).getValue(CollaborationCandidateEvolution.TASK))
            workspace.enrollPublication(access.copy(nodeId = addition.dispatchId, personId = task.getString("member"),
                dependencyNodes = addition.dependencyDispatchIds), if (task.getString("operation") == "review")
                    CollaborationResearchStage.VERIFY else CollaborationResearchStage.REVISE, task)
        }
        private fun publish(who: CollaborationWorkspaceAccess, item: JSONObject, task: JSONObject? = null): JSONObject {
            if (item.optString("kind") == "candidate_event" &&
                item.getJSONObject("body").getJSONObject("candidate_event").optString("operation") == "review")
                assertNull(ledger.readPage(who, source.getString("evidence_id"), source.getString("sha256"))!!.next)
            val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Original research output")
                .put("candidates", JSONArray()).put("findings", JSONArray()).put("workspace", JSONArray().put(item)).toString()
            val receipt = workspace.publish(who, raw, candidateTask = task)
            assertEquals(receipt.toString(), "recorded", receipt.getString("status"))
            return receipt.getJSONArray("revisions").getJSONObject(0)
        }
    }

    @Test fun runnableCandidateStartsWhileUnrelatedNodeIsStillRunningAndRetainsSnapshot() {
        val f = Fixture(); val snapshot = f.snapshot(f.node("slow"))
        val before = f.rows.values.toMap()
        val plan = f.plan(snapshot)
        assertFalse(plan.feedback, plan.error)
        assertSame(snapshot, plan.retained)
        assertEquals(before, f.rows.values)
        assertEquals(1, plan.additions.size)
        assertTrue(plan.additions.single().dependencyDispatchIds.isEmpty())
        assertEquals(snapshot.completedOutputs, plan.retained.completedOutputs)
    }

    @Test fun queuedRunningUnknownAndMissingNodesNeverFailOrRedispatch() {
        val f = Fixture(); val first = f.plan(f.snapshot(f.node("slow")))
        val installed = f.installed(first)
        listOf(CollaborationCandidateLiveGraph.Status.QUEUED, CollaborationCandidateLiveGraph.Status.RUNNING,
            CollaborationCandidateLiveGraph.Status.UNKNOWN).forEach { status ->
            val snapshot = installed.copy(nodes = installed.nodes.map { it.copy(status = status) })
            val next = f.plan(snapshot, first.state)
            assertFalse(next.error)
            assertEquals(first.state, next.state)
            assertTrue(next.additions.isEmpty())
            assertSame(snapshot, next.retained)
        }
        val missing = f.plan(first.retained, first.state, JSONArray())
        assertFalse(missing.error)
        assertEquals(first.state, missing.state)
        assertTrue(missing.additions.isEmpty())
        assertTrue(missing.feedback.contains("unavailable"))
    }

    @Test fun publishedButStillRunningReviewIsNotConsumedUntilItsHostTerminalEvent() {
        val f = Fixture(); val first = f.plan(f.snapshot()); f.execute(first.additions.single())
        val before = f.rows.values.toMap()
        val held = f.plan(f.installed(first), first.state, JSONArray())
        assertEquals(first.state, held.state)
        assertTrue(held.additions.isEmpty())
        assertEquals(before, f.rows.values)
    }

    @Test fun reviewRepairAndRecheckAdvanceIndividuallyWhileAnotherNodeKeepsRunning() {
        val f = Fixture(); var plan = f.plan(f.snapshot(f.node("slow")))
        val issued = linkedSetOf<String>()
        listOf("review", "revise", "review").forEachIndexed { index, operation ->
            val addition = plan.additions.single()
            assertTrue(issued.add(addition.dispatchId))
            val task = JSONObject(CollaborationCandidateEvolution.taskContext(addition.work).getValue(CollaborationCandidateEvolution.TASK))
            assertEquals(operation, task.getString("operation"))
            f.execute(addition, if (index == 2) "supported" else "refuted")
            val completed = f.complete(f.installed(plan), addition)
            val next = f.plan(completed, plan.state, JSONArray())
            assertFalse(next.feedback, next.error)
            assertSame(completed, next.retained)
            assertEquals(CollaborationCandidateLiveGraph.Status.RUNNING, next.retained.nodes.first().status)
            assertEquals(completed.completedOutputs, next.retained.completedOutputs)
            if (index < 2) {
                assertTrue(addition.dispatchId in next.additions.single().dependencyDispatchIds)
                assertEquals("success", next.additions.single().work.getString("dependency_policy"))
                assertTrue("slow" !in next.additions.single().dependencyDispatchIds)
            }
            plan = next
        }
        assertTrue(plan.additions.isEmpty())
        assertFalse(CollaborationCandidateEvolution.pending(plan.state))
        assertEquals(4, plan.retained.nodes.size)
        assertEquals(4, plan.retained.completedOutputs.size)
        assertTrue(f.plan(plan.retained, plan.state).additions.isEmpty())
    }

    @Test fun actualFailedCancelledAndSkippedDispatchesSettleWithoutRetry() {
        listOf(CollaborationCandidateLiveGraph.Status.FAILED, CollaborationCandidateLiveGraph.Status.CANCELLED,
            CollaborationCandidateLiveGraph.Status.SKIPPED).forEach { status ->
            val f = Fixture(); val first = f.plan(f.snapshot())
            val snapshot = f.complete(f.installed(first), first.additions.single(), status)
            val next = f.plan(snapshot, first.state, JSONArray())
            assertFalse(next.error)
            assertFalse(CollaborationCandidateEvolution.pending(next.state))
            assertTrue(next.additions.isEmpty())
            assertSame(snapshot, next.retained)
        }
    }

    @Test fun explicitReviewReplacementIsAppendOnlyAndDoesNotWaitForUnrelatedWork() {
        val f = Fixture(); val first = f.plan(f.snapshot(f.node("slow")))
        val old = first.additions.single()
        f.enroll(old)
        val completed = f.complete(f.installed(first), old)
        val retry = f.request().put("reviewer", "lead").put("retry_review", JSONObject()
            .put("node_id", old.dispatchId).put("reason", "Publish the missing original-source review"))
        val next = f.plan(completed, first.state, JSONArray().put(retry))
        assertFalse(next.feedback, next.error)
        assertSame(completed, next.retained)
        assertEquals(CollaborationCandidateLiveGraph.Status.RUNNING, next.retained.nodes.first().status)
        val replacement = next.additions.single()
        assertNotEquals(old.dispatchId, replacement.dispatchId)
        assertEquals("lead", replacement.work.getString("member"))
        assertTrue(replacement.dependencyDispatchIds.isEmpty())
        assertEquals(completed.completedOutputs, next.retained.completedOutputs)
        val replay = f.plan(f.installed(next), next.state, JSONArray().put(retry))
        assertFalse(replay.feedback, replay.error)
        assertEquals(next.state, replay.state)
        assertTrue(replay.additions.isEmpty())
        f.execute(replacement, "supported")
        val settled = f.plan(f.complete(f.installed(next), replacement), next.state, JSONArray())
        assertFalse(CollaborationCandidateEvolution.pending(settled.state))
        assertTrue(settled.feedback.contains("not host verified"))
    }

    @Test fun reviewReplacementRespectsPauseStopAdmissionAndUnknownRemoteStates() {
        val f = Fixture(); val first = f.plan(f.snapshot())
        val old = first.additions.single()
        val retry = f.request().put("reviewer", "lead").put("retry_review", JSONObject()
            .put("node_id", old.dispatchId).put("reason", "Repair the publication contract"))
        val installed = f.installed(first)
        listOf(CollaborationCandidateLiveGraph.Status.UNKNOWN, CollaborationCandidateLiveGraph.Status.RUNNING,
            CollaborationCandidateLiveGraph.Status.QUEUED).forEach { status ->
            val held = f.plan(installed.copy(nodes = installed.nodes.map { it.copy(status = status) }), first.state, JSONArray().put(retry))
            assertTrue(held.additions.isEmpty())
            assertEquals(1, held.deferredRequests.size)
            assertEquals("validate", CollaborationCandidateVerificationState.read(held.state).getJSONObject(0).getString("phase"))
        }
        val completed = f.complete(installed, old)
        listOf(CollaborationCandidateLiveGraph.Control.PAUSE, CollaborationCandidateLiveGraph.Control.STOP).forEach { control ->
            val held = f.plan(completed.copy(control = control), first.state, JSONArray().put(retry))
            assertTrue(held.additions.isEmpty())
            assertEquals(1, held.deferredRequests.size)
        }
        val deferred = f.plan(completed.copy(maxNewDispatches = 0), first.state, JSONArray().put(retry))
        assertTrue(deferred.additions.isEmpty())
        assertEquals(1, deferred.deferredRequests.size)
        assertTrue(CollaborationCandidateVerificationState.read(deferred.state).getJSONObject(0).getBoolean("retryable_review"))
        val admitted = f.plan(completed, deferred.state, JSONArray())
        assertEquals(1, admitted.additions.size)
        assertTrue(admitted.deferredRequests.isEmpty())
    }

    @Test fun failedCancelledAndSkippedReviewsCannotUseSameVersionReplacement() {
        listOf(CollaborationCandidateLiveGraph.Status.FAILED, CollaborationCandidateLiveGraph.Status.CANCELLED,
            CollaborationCandidateLiveGraph.Status.SKIPPED).forEach { status ->
            val f = Fixture(); val first = f.plan(f.snapshot())
            val old = first.additions.single()
            val retry = f.request().put("retry_review", JSONObject().put("node_id", old.dispatchId).put("reason", "Try another member"))
            val held = f.plan(f.complete(f.installed(first), old, status), first.state, JSONArray().put(retry))
            assertTrue(held.additions.isEmpty())
            assertFalse(CollaborationCandidateVerificationState.read(held.state).getJSONObject(0).getBoolean("retryable_review"))
            assertTrue(held.feedback.contains("reconcile offline or failed work"))
        }
    }

    @Test fun oldRetryReplayCannotOverwriteANewerPendingReassignmentForTheSameVersion() {
        val f = Fixture(); val first = f.plan(f.snapshot())
        val old = first.additions.single()
        fun retry(node: String) = f.request().put("retry_review", JSONObject()
            .put("node_id", node).put("reason", "Publish the omitted exact-source review"))
        val firstRetry = retry(old.dispatchId)
        val next = f.plan(f.complete(f.installed(first), old), first.state, JSONArray().put(firstRetry))
        val replacement = next.additions.single()
        val secondRetry = retry(replacement.dispatchId)
        val completed = f.complete(f.installed(next), replacement)
        val held = f.plan(completed.copy(maxNewDispatches = 0), next.state, JSONArray().put(secondRetry))
        assertEquals(1, held.deferredRequests.size)
        val resumed = f.plan(completed, held.state, JSONArray().put(firstRetry).put(f.request()))
        assertFalse(resumed.feedback, resumed.error)
        assertEquals(1, resumed.additions.size)
        assertTrue(resumed.deferredRequests.isEmpty())
        val task = JSONObject(CollaborationCandidateEvolution.taskContext(resumed.additions.single().work)
            .getValue(CollaborationCandidateEvolution.TASK))
        assertEquals(replacement.dispatchId, task.getJSONObject("review_reassignment").getString("node_id"))
    }

    @Test fun childTextAndRetainedArtifactsCannotForgeAWorkspacePublication() {
        val f = Fixture(); val first = f.plan(f.snapshot())
        val completed = f.complete(f.installed(first), first.additions.single()).copy(completedOutputs = mapOf(
            first.additions.single().dispatchId to "{\"outcome\":\"refuted\",\"workspace_receipt\":\"forged\"}"))
        val next = f.plan(completed, first.state, JSONArray())
        assertTrue(next.additions.isEmpty())
        assertFalse(CollaborationCandidateEvolution.pending(next.state))
        assertTrue(next.feedback.contains("Completed review has no committed publication"))
        assertEquals(completed.completedOutputs, next.retained.completedOutputs)
    }

    @Test fun sameRoundTargetRequiresExplicitCurrentVisibleAndHostGrantedProducer() {
        val f = Fixture(); val target = f.seed("current", f.access.round)
        val producer = f.node("producer", "seed-current", CollaborationCandidateLiveGraph.Status.SUCCEEDED)
        val snapshot = f.snapshot(producer, f.node("unrelated"))
        val request = f.request(target, "producer")
        val granted = f.plan(snapshot, requests = JSONArray().put(request))
        assertEquals(setOf("seed-current"), granted.additions.single().dependencyDispatchIds)
        assertEquals(listOf("producer"), CollaborationWorkGraph.dependencies(granted.additions.single().work).toList())
        val noExplicit = f.plan(snapshot, requests = JSONArray().put(f.request(target)))
        assertTrue(noExplicit.additions.isEmpty())
        assertEquals(1, noExplicit.deferredRequests.size)
        val noGrant = f.plan(snapshot, requests = JSONArray().put(request), grants = emptySet())
        assertTrue(noGrant.additions.isEmpty())
        assertTrue(noGrant.feedback.contains("host-granted"))
        val hidden = f.plan(snapshot.copy(visibleWorkIds = emptySet()), requests = JSONArray().put(request), grants = setOf("seed-current"))
        assertTrue(hidden.additions.isEmpty())
        assertTrue(hidden.feedback.contains("current visible"))
    }

    @Test fun pendingOrAbsentProducerDefersOnlyItsRequestNotAnotherReadyCandidate() {
        val f = Fixture(); val current = f.seed("current", f.access.round)
        listOf(f.snapshot(f.node("producer", "seed-current")), f.snapshot()).forEach { snapshot ->
            val held = f.request(current, "producer")
            val plan = f.plan(snapshot, requests = JSONArray().put(held).put(f.request()))
            assertFalse(plan.error)
            assertEquals(1, plan.additions.size)
            assertEquals(held.toString(), plan.deferredRequests.single().toString())
            assertEquals(f.target.getString("object_id"), CollaborationCandidateVerificationState.read(plan.state).getJSONObject(0).getString("object_id"))
        }
    }

    @Test fun archivedOutputAndInventedWorkCannotBecomeProducerDependencies() {
        val f = Fixture()
        listOf("archived", "future-work").forEach { id ->
            val plan = f.plan(f.snapshot(), requests = JSONArray().put(f.request(f.target, id)))
            assertTrue(plan.additions.isEmpty())
            assertEquals(0, CollaborationCandidateVerificationState.read(plan.state).length())
            assertEquals(1, plan.deferredRequests.size)
        }
        val producer = f.node("unrelated", "other", CollaborationCandidateLiveGraph.Status.SUCCEEDED)
        val unrelated = f.plan(f.snapshot(producer), requests = JSONArray().put(f.request(f.target, "unrelated")))
        assertTrue(unrelated.additions.isEmpty())
        assertTrue(unrelated.feedback.contains("exact candidate producer"))
    }

    @Test fun invisibleCompletedCandidateDoesNotHoldAnotherVisibleCompletedCandidate() {
        val f = Fixture(); val other = f.seed("b")
        val first = f.plan(f.snapshot(), requests = JSONArray().put(f.request()).put(f.request(other)))
        first.additions.forEach { f.execute(it) }
        var completed = f.installed(first)
        first.additions.forEach { completed = f.complete(completed, it) }
        val second = first.additions[1]
        val partial = completed.copy(visibleWorkIds = setOf(second.work.getString("id")))
        val next = f.plan(partial, first.state, JSONArray())
        assertFalse(next.error)
        assertEquals(1, next.additions.size)
        assertEquals("validate", JSONArray(next.state).getJSONObject(0).getString("phase"))
        assertEquals("repair", JSONArray(next.state).getJSONObject(1).getString("phase"))
        assertSame(partial, next.retained)
    }

    @Test fun durablePauseAndStopHoldAllCandidateWorkWithoutLosingRequests() {
        val f = Fixture(); val first = f.plan(f.snapshot())
        listOf(CollaborationCandidateLiveGraph.Control.PAUSE, CollaborationCandidateLiveGraph.Control.STOP).forEach { control ->
            val snapshot = f.installed(first).copy(control = control)
            val next = f.plan(snapshot, first.state)
            assertEquals(first.state, next.state)
            assertTrue(next.additions.isEmpty())
            assertEquals(0, next.deferredRequests.size)
            assertSame(snapshot, next.retained)
        }
    }

    @Test fun independenceAndRevokedWorkspaceAccessRemainRequired() {
        val f = Fixture()
        listOf("author", "editor", "outsider").forEach { person ->
            val next = f.plan(f.snapshot(), requests = JSONArray().put(f.request().put("reviewer", person)))
            assertTrue(next.additions.isEmpty())
            assertEquals(0, CollaborationCandidateVerificationState.read(next.state).length())
            assertEquals(1, next.deferredRequests.size)
        }
        f.authorized = false
        val revoked = f.plan(f.snapshot())
        assertTrue(revoked.additions.isEmpty())
        assertEquals(1, revoked.deferredRequests.size)
    }

    @Test fun mismatchedScopeDuplicateIdentitiesAndAppendCollisionsPreserveOriginalPlan() {
        val f = Fixture(); val initial = f.plan(f.snapshot())
        val addition = initial.additions.single()
        val collision = f.node(addition.work.getString("id"), "existing", person = "reviewer")
        listOf(f.snapshot().copy(runId = "foreign"), f.snapshot(f.node("duplicate"), f.node("duplicate")),
            f.snapshot(collision)).forEach { snapshot ->
            val next = f.plan(snapshot)
            assertTrue(next.feedback, next.error)
            assertTrue(next.additions.isEmpty())
            assertEquals("[]", next.state)
            assertSame(snapshot, next.retained)
        }
    }

    @Test fun checkpointAndHostMemberMismatchCannotBorrowASuccessfulNode() {
        val f = Fixture(); val first = f.plan(f.snapshot())
        val installed = f.installed(first)
        val borrowed = installed.copy(nodes = installed.nodes.map { it.copy(personId = "author") })
        val next = f.plan(borrowed, first.state, JSONArray())
        assertTrue(next.error)
        assertEquals(first.state, next.state)
        assertTrue(next.additions.isEmpty())
    }

    @Test fun hostAdmissionBudgetDefersAndResumesWithoutLimitingActiveCandidateCount() {
        val f = Fixture(); val first = f.plan(f.snapshot())
        val b = f.seed("b"); val c = f.seed("c")
        val pending = f.request(c)
        val next = f.plan(f.installed(first).copy(maxNewDispatches = 1), first.state, JSONArray().put(f.request(b)).put(pending))
        assertFalse(next.error)
        assertEquals(1, next.additions.size)
        assertEquals(2, CollaborationCandidateVerificationState.read(next.state).length())
        assertEquals(pending.toString(), next.deferredRequests.single().toString())
        assertEquals(JSONArray(first.state).getJSONObject(0).toString(), CollaborationCandidateVerificationState.read(next.state).getJSONObject(0).toString())
        val resumed = f.plan(f.installed(next), next.state, JSONArray())
        assertEquals(1, resumed.additions.size)
        assertEquals(3, CollaborationCandidateVerificationState.read(resumed.state).length())
        assertTrue(resumed.deferredRequests.isEmpty())
    }

    @Test fun producerProjectionCannotSubstituteTheOriginalAuthor() {
        val f = Fixture(); val current = f.seed("current", f.access.round)
        val producer = f.node("producer", "seed-current", CollaborationCandidateLiveGraph.Status.SUCCEEDED, "reviewer")
        val next = f.plan(f.snapshot(producer), requests = JSONArray().put(f.request(current, "producer")))
        assertFalse(next.error)
        assertTrue(next.additions.isEmpty())
        assertEquals(1, next.deferredRequests.size)
        assertTrue(next.feedback.contains("producer author"))
    }

    @Test fun revocationAfterPublishedReviewDoesNotAuthorizeRepair() {
        val f = Fixture(); val first = f.plan(f.snapshot()); f.execute(first.additions.single())
        val completed = f.complete(f.installed(first), first.additions.single())
        f.authorized = false
        val next = f.plan(completed, first.state, JSONArray())
        assertFalse(next.error)
        assertTrue(next.additions.isEmpty())
        assertSame(completed, next.retained)
    }

    @Test fun corruptCandidateCheckpointPreservesOriginalStateAndArtifactsWithoutAppend() {
        val f = Fixture(); val snapshot = f.snapshot(f.node("existing"))
        val corrupt = "[{\"phase\":\"done\"}]"
        val next = f.plan(snapshot, corrupt)
        assertTrue(next.error)
        assertEquals(corrupt, next.state)
        assertSame(snapshot, next.retained)
        assertTrue(next.additions.isEmpty())
    }

    @Test fun thousandRequestsPersistAndDrainAcrossHostBudgetsWithoutBatchRejection() {
        val f = Fixture()
        val requests = JSONArray()
        repeat(1000) { requests.put(f.request(f.seed("bulk-$it"))) }
        var plan = f.plan(f.snapshot().copy(maxNewDispatches = 0), requests = requests)
        assertFalse(plan.feedback, plan.error)
        assertEquals(1000, CollaborationCandidateVerificationState.checkpoint(plan.state).pendingRequests.length())
        assertTrue(plan.additions.isEmpty())
        assertTrue(CollaborationCandidateEvolution.pending(plan.state))
        val issued = hashSetOf<String>()
        listOf(37, 0, 103, Int.MAX_VALUE).forEach { budget ->
            val snapshot = f.installed(plan).copy(maxNewDispatches = budget)
            plan = f.plan(snapshot, plan.state, JSONArray())
            assertFalse(plan.feedback, plan.error)
            assertTrue(plan.additions.size <= budget)
            plan.additions.forEach { assertTrue(issued.add(it.dispatchId)) }
            val saved = CollaborationCandidateVerificationState.checkpoint(plan.state)
            assertEquals(1000, saved.cycles.length() + saved.pendingRequests.length())
            assertSame(snapshot, plan.retained)
        }
        assertEquals(1000, issued.size)
        assertEquals(1000, CollaborationCandidateVerificationState.read(plan.state).length())
        assertTrue(plan.deferredRequests.isEmpty())
        val repeated = f.plan(f.installed(plan), plan.state, JSONArray())
        assertTrue(repeated.additions.isEmpty())
        assertEquals(plan.state, repeated.state)
    }

    @Test fun completedRefutationWaitsForHostBudgetThenResumesWithoutRepeatingItsPublication() {
        val f = Fixture(); val first = f.plan(f.snapshot()); val review = first.additions.single()
        f.execute(review)
        val completed = f.complete(f.installed(first), review).copy(maxNewDispatches = 0)
        val originals = f.rows.values.toMap()
        val held = f.plan(completed, first.state, JSONArray())
        assertTrue(held.additions.isEmpty())
        assertEquals(first.state, held.state)
        assertTrue(CollaborationCandidateEvolution.pending(held.state))
        val resumed = f.plan(completed.copy(maxNewDispatches = 1), held.state, JSONArray())
        assertEquals(1, resumed.additions.size)
        assertEquals("repair", CollaborationCandidateVerificationState.read(resumed.state).getJSONObject(0).getString("phase"))
        assertEquals(originals, f.rows.values)
        assertEquals(completed.completedOutputs, resumed.retained.completedOutputs)
    }

    @Test fun oneFailedRouteDoesNotPreventThreeOtherCandidatesFromImproving() {
        val f = Fixture()
        val requests = JSONArray().put(f.request())
        repeat(3) { requests.put(f.request(f.seed("parallel-$it"))) }
        val first = f.plan(f.snapshot(), requests = requests)
        assertEquals(4, first.additions.size)
        var completed = f.installed(first)
        first.additions.forEachIndexed { index, addition ->
            if (index > 0) f.execute(addition)
            completed = f.complete(completed, addition, if (index == 0) CollaborationCandidateLiveGraph.Status.FAILED
                else CollaborationCandidateLiveGraph.Status.SUCCEEDED)
        }
        val next = f.plan(completed.copy(maxNewDispatches = 3), first.state, JSONArray())
        assertFalse(next.error)
        assertEquals(3, next.additions.size)
        val cycles = CollaborationCandidateVerificationState.read(next.state)
        assertEquals("done", cycles.getJSONObject(0).getString("phase"))
        assertEquals("not_verified", cycles.getJSONObject(0).getString("verification_state"))
        (1..3).forEach { assertEquals("repair", cycles.getJSONObject(it).getString("phase")) }
        assertTrue(CollaborationCandidateEvolution.pending(next.state))
    }

    @Test fun repeatedRefutationsNeverBecomeSuccessAndOldRepairReplayHasNoSideEffects() {
        val f = Fixture(); var plan = f.plan(f.snapshot().copy(maxNewDispatches = 1))
        val issued = hashSetOf<String>()
        var firstRepair: CollaborationCandidateLiveGraph.Addition? = null
        repeat(9) { index ->
            val addition = plan.additions.single()
            assertTrue(issued.add(addition.dispatchId))
            if (index == 1) firstRepair = addition
            f.execute(addition, "refuted")
            val completed = f.complete(f.installed(plan), addition)
            plan = f.plan(completed, plan.state, JSONArray())
            assertFalse(plan.error)
            assertEquals(1, plan.additions.size)
            assertTrue(CollaborationCandidateEvolution.pending(plan.state))
            val cycle = CollaborationCandidateVerificationState.read(plan.state).getJSONObject(0)
            assertNotEquals("done", cycle.getString("phase"))
            assertFalse(cycle.has("result"))
        }
        assertTrue(plan.additions.single().dispatchId !in issued)
        val repair = requireNotNull(firstRepair)
        val task = JSONObject(CollaborationCandidateEvolution.taskContext(repair.work).getValue(CollaborationCandidateEvolution.TASK))
        val originals = f.rows.values.toMap()
        assertNotNull(f.workspace.replayCandidateTask(f.access.copy(nodeId = repair.dispatchId,
            personId = task.getString("member"), dependencyNodes = repair.dependencyDispatchIds), task))
        assertEquals(originals, f.rows.values)
    }

    @Test fun pauseAndStopPersistUnadmittedRequestsAndRunCanResumeWithoutResendingThem() {
        listOf(CollaborationCandidateLiveGraph.Control.PAUSE, CollaborationCandidateLiveGraph.Control.STOP).forEach { control ->
            val f = Fixture()
            val held = f.plan(f.snapshot().copy(control = control, maxNewDispatches = 3))
            assertTrue(held.additions.isEmpty())
            assertEquals(1, CollaborationCandidateVerificationState.checkpoint(held.state).pendingRequests.length())
            val resumed = f.plan(held.retained.copy(control = CollaborationCandidateLiveGraph.Control.RUN), held.state, JSONArray())
            assertEquals(1, resumed.additions.size)
            assertTrue(resumed.deferredRequests.isEmpty())
        }
    }
}
