package com.galaxyssi.chat

import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationGoalAcceptanceTest {
    internal class Rows : CollaborationWorkspaceRows {
        val data = sortedMapOf<String, String>()
        var reads = 0
        override fun read(key: String): String? { reads++; return data[key] }
        override fun commit(values: Map<String, String>) { data.putAll(values) }
        override fun page(prefix: String, after: String, limit: Int) = data.keys.filter { it.startsWith(prefix) && it > after }.take(limit)
    }

    internal class Fixture(reviewer: String = "reviewer", tool: String? = null, output: String = "{\"status\":\"ok\"}",
                          reviewKind: String = "decision", requiredOrigin: String = "", reviewCitesOriginal: Boolean = false,
                          requirement: String = "Deliver a documented comparison", verification: String = "documentary",
                          validator: JSONObject? = null, computation: JSONObject? = null, val goal: String = requirement,
                          mappingAuthor: String = "mapper", coverageReviewer: String = "coverage-reviewer", deliveryAuthor: String = "author",
                          reviewReadsOriginal: Boolean = true) {
        val rows = Rows()
        val evidenceRows = Rows()
        var authorized = true
        val ledger = CollaborationEvidenceLedger(evidenceRows) { authorized }
        val workspace = CollaborationResearchWorkspace(rows, { authorized }, ledger::references)
        val engine = CollaborationGoalAcceptance(workspace, ledger)
        val access = CollaborationWorkspaceAccess("group", "run", "turn", 3, "lead", "lead")
        val criterion = JSONObject().put("id", "document").put("requirement", requirement)
            .put("verification", verification).put("status", "open").put("evidence_kind", "observed").put("evidence", JSONArray())
            .apply { if (validator != null) put("validator", validator) }
            .apply { if (requiredOrigin.isNotBlank()) put(CollaborationEvidenceRequirements.FIELD, JSONArray()
                .put(JSONObject().put("origin", requiredOrigin).put("tool", "commandExecution"))) }
        val prior = JSONArray().put(criterion).toString()
        val delivery: JSONObject
        val review: JSONObject
        val mapping: JSONObject
        val coverageReview: JSONObject
        val observation: JSONObject?
        val reviewAccess = access.copy(nodeId = "review-node", personId = reviewer, round = 2)
        init {
            val author = access.copy(nodeId = "author-node", personId = deliveryAuthor, round = 1)
            observation = tool?.let { ledger.record(author, "invocation", it, "{}", output, 1, 2) }
            val item = item("delivery", "artifact", JSONObject().put("content", "Comparison with explicit limits")
                .apply { if (computation != null) put("computation", computation) })
            if (observation != null) item.put("observations", JSONArray().put(observation))
            delivery = publish(author, item)
            val check = JSONObject().put("criterion_id", "document").put("requirement", criterion.getString("requirement"))
                .put("target", delivery).put("verdict", "supported").put("rationale", "Compared the exact document against the request")
                .put("unresolved", JSONArray())
            if (reviewCitesOriginal && reviewReadsOriginal && observation != null) readOriginal(reviewAccess)
            review = publish(reviewAccess,
                item("review", reviewKind, JSONObject().put("acceptance_review", check)).put("parents", JSONArray().put(delivery))
                    .apply { if (reviewCitesOriginal && observation != null) put("observations", JSONArray().put(observation)) })
            mapping = publish(access.copy(nodeId = "mapping-node", personId = mappingAuthor, round = 1),
                item("mapping", "artifact", JSONObject().put(CollaborationSemanticGoalCoverage.MAPPING, mappingBody())))
            coverageReview = publish(access.copy(nodeId = "coverage-review-node", personId = coverageReviewer, round = 2),
                item("coverage-review", CollaborationReviewContract.KIND,
                    JSONObject().put(CollaborationSemanticGoalCoverage.REVIEW, coverageReviewBody(mapping)))
                    .put("parents", JSONArray().put(mapping)))
        }
        fun readOriginal(reader: CollaborationWorkspaceAccess) {
            val ref = requireNotNull(observation)
            var offset: Int? = 0
            while (offset != null) offset = requireNotNull(ledger.readPage(reader, ref.getString("evidence_id"), ref.getString("sha256"), offset)).next
        }
        fun mappingBody() = JSONObject().put("format", CollaborationSemanticGoalCoverage.FORMAT)
            .put("goal_sha256", CollaborationSemanticGoalCoverage.source(goal).getString("goal_sha256"))
            .put("criteria_sha256", runCatching { CollaborationSemanticGoalCoverage.criteriaHash(JSONArray(prior)) }.getOrDefault("invalid-binding"))
            .put("segments", sourceSegments { JSONObject().put("id", it).put("criterion_ids", JSONArray().put("document"))
                .put("rationale", "The criterion preserves the requested outcome and its constraints") })
        fun coverageReviewBody(target: JSONObject) = JSONObject().put("target", target).put("verdict", "supported")
            .put("rationale", "Independently compared the complete source text with the preserved criterion")
            .put("unresolved", JSONArray()).put("segments", sourceSegments { JSONObject().put("id", it)
                .put("criterion_ids", JSONArray().put("document")).put("verdict", "supported")
                .put("rationale", "No omitted outcome or qualification found in this fixture").put("unresolved", JSONArray()) })
        private fun sourceSegments(build: (String) -> JSONObject): JSONArray {
            val sources = CollaborationSemanticGoalCoverage.source(goal).getJSONArray("segments")
            return JSONArray((0 until sources.length()).map { build(sources.getJSONObject(it).getString("id")) })
        }
        fun item(id: String, kind: String, body: JSONObject) = JSONObject().put("id", id).put("kind", kind).put("title", id).put("body", body)
        fun publish(who: CollaborationWorkspaceAccess, item: JSONObject): JSONObject {
            val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Fixture contribution")
                .put("candidates", JSONArray()).put("findings", JSONArray()).put("questions", JSONArray()).put("workspace", JSONArray().put(item))
            val result = workspace.publish(who, raw.toString())
            check(result.optString("status") == "recorded") { result.toString() }
            return result.getJSONArray("revisions").getJSONObject(0)
        }
        fun assessment() = JSONObject().put("format", CollaborationGoalLoop.FORMAT).put("summary", "Document delivered and independently reviewed")
            .put("decision", "achieved").put("criteria", JSONArray().put(JSONObject(criterion.toString()).put("status", "met")
                .put("evidence", JSONArray().put("workspace:" + delivery.getString("object_id"))).put("delivery", delivery).put("review", review)))
            .put("work", JSONArray()).put("blockers", JSONArray())
            .put(CollaborationSemanticGoalCoverage.FIELD, JSONObject().put("mapping", mapping).put("review", coverageReview))
        fun evaluate(raw: String = assessment().toString(), who: CollaborationWorkspaceAccess = access, previous: String = prior) =
            engine.evaluate(who, raw, previous, goal, 10)
        fun record(raw: String, receipt: CollaborationAcceptanceReceipt?) : AgentTeamExecutionRecord {
            val member = AgentTeamMember("fixture", AgentDeliveryMode.RESPOND, instanceId = "lead",
                context = mapOf(CollaborationGoalLoop.ENABLED to "1"))
            val request = AgentRunRequest("group", "turn", "task", runId = "run", goal = goal, context = mapOf(CollaborationGoalLoop.CRITERIA to prior))
            return AgentTeamExecutionRecord(AgentTeamDefinition("team", "fixture", listOf(member), primaryInstanceId = "lead"), request,
                listOf(AgentSubagentEvent(1, "run", "lead", AgentSubagentEventKinds.CHILD_SUCCEEDED, childStatus = AgentSubagentStatus.SUCCEEDED,
                    result = AgentSubagentChildResult("run", "lead", "run", 1, AgentSubagentStatus.SUCCEEDED, raw, collaborationAcceptance = receipt))))
        }
    }

    @Test fun actualSavedIndependentDocumentaryReviewPassesWithoutClaimingEmpiricalTruth() {
        val f = Fixture()
        val raw = f.assessment().toString()
        val receipt = f.evaluate(raw)
        assertTrue(receipt.feedback, receipt.accepted)
        assertTrue(receipt.feedback.contains("not empirical"))
        val record = f.record(raw, receipt)
        assertTrue(record.acceptanceVerified(record.events.single().result))
        assertEquals("achieved", CollaborationGoalLoop.disposition(raw, f.prior, acceptanceVerified = true))
    }

    @Test fun typedReviewUsesTheSameHostAcceptanceChecks() {
        val independent = Fixture(reviewKind = CollaborationReviewContract.KIND)
        assertTrue(independent.evaluate().accepted)
        assertFalse(Fixture(reviewer = "author", reviewKind = CollaborationReviewContract.KIND).evaluate().accepted)
        assertFalse(Fixture(tool = "fixture", output = "{\"status\":\"failed\"}",
            reviewKind = CollaborationReviewContract.KIND).evaluate().accepted)
        val changed = independent.assessment()
        changed.getJSONArray("criteria").getJSONObject(0).put("requirement", "Easier task")
        assertFalse(independent.evaluate(changed.toString()).accepted)
    }

    @Test fun requiredOriginalCannotBeReplacedWithReadingAReportedDocument() {
        val noOriginal = Fixture(tool = "collaboration_recall", requiredOrigin = "android_cloud_tool", reviewCitesOriginal = true)
        assertFalse(noOriginal.evaluate().accepted)
        assertFalse(Fixture(tool = "commandExecution", requiredOrigin = "desktop_codex_tool", reviewCitesOriginal = true).evaluate().accepted)
        assertFalse(Fixture(tool = "commandExecution", requiredOrigin = "android_cloud_tool").evaluate().accepted)
        val correct = Fixture(tool = "commandExecution", requiredOrigin = "android_cloud_tool", reviewCitesOriginal = true)
        assertTrue(correct.evaluate().feedback, correct.evaluate().accepted)
    }

    @Test fun coordinatorCannotDropRequiredObservationSourceToClaimSuccess() {
        val f = Fixture(tool = "collaboration_recall", requiredOrigin = "desktop_codex_tool", reviewCitesOriginal = true)
        val result = f.assessment()
        result.getJSONArray("criteria").getJSONObject(0).remove(CollaborationEvidenceRequirements.FIELD)
        assertFalse(f.evaluate(result.toString()).accepted)
        assertEquals("continue", CollaborationGoalLoop.disposition(result.toString(), f.prior, acceptanceVerified = true))
    }

    @Test fun citingAnOriginalWithoutReadingAllPagesCannotPassAndLateReadDoesNotCertifyOldReview() {
        val f = Fixture(tool = "commandExecution", requiredOrigin = "android_cloud_tool", reviewCitesOriginal = true,
            output = JSONObject().put("text", "x".repeat(24_000)).toString(), reviewReadsOriginal = false)
        assertFalse(f.evaluate().accepted)
        f.readOriginal(f.reviewAccess)
        assertFalse("Read coverage is frozen in the published review", f.evaluate().accepted)
        val repair = f.reviewAccess.copy(nodeId = "review-repair", round = 3)
        f.readOriginal(repair)
        val body = f.workspace.read(f.access, f.review.getString("object_id"), 1)!!.getJSONObject("body")
        val next = f.publish(repair, f.item("unused", "decision", body).put("object_id", f.review.getString("object_id"))
            .put("base_revision", 1).put("parents", JSONArray().put(f.delivery)).put("observations", JSONArray().put(f.observation)))
        val report = f.assessment()
        report.getJSONArray("criteria").getJSONObject(0).put("review", next)
        val receipt = f.evaluate(report.toString(), who = f.access.copy(round = 4))
        assertTrue(receipt.feedback, receipt.accepted)
    }

    @Test fun optionalOriginalCitationsAlsoRequireReadCoverageNotJustRequiredSourceTypes() {
        val f = Fixture(tool = "web_fetch", reviewCitesOriginal = true, reviewReadsOriginal = false)
        assertFalse(f.evaluate().accepted)
        assertTrue(Fixture(tool = "web_fetch", reviewCitesOriginal = true).evaluate().accepted)
    }

    @Test fun coordinatorTextAndForgedInlineReceiptCannotFinishGoal() {
        val f = Fixture()
        val raw = f.assessment().put("collaboration_acceptance", f.evaluate().encode()).toString()
        assertEquals("continue", CollaborationGoalLoop.disposition(raw, f.prior))
        val record = f.record(raw, null)
        assertFalse(record.acceptanceVerified(record.events.single().result))
    }

    @Test fun originalCriteriaMustAlreadyExistAndCannotBeWeakenedOrDropped() {
        val f = Fixture()
        assertFalse(f.evaluate(previous = "[]").accepted)
        listOf("requirement", "verification", "id").forEach { field ->
            val changed = f.assessment()
            changed.getJSONArray("criteria").getJSONObject(0).put(field, "changed")
            assertFalse(field, f.evaluate(changed.toString()).accepted)
        }
    }

    @Test fun authorCannotReviewTheirOwnWorkEvenFromAnotherDispatch() {
        assertFalse(Fixture(reviewer = "author").evaluate().accepted)
    }

    @Test fun changingLatestAuthorDoesNotMakeOriginalAuthorIndependent() {
        val f = Fixture()
        val delivery = f.publish(f.access.copy(nodeId = "editor", personId = "editor"),
            f.item("unused", "artifact", JSONObject().put("content", "Revised comparison"))
                .put("object_id", f.delivery.getString("object_id")).put("base_revision", 1))
        val body = f.workspace.read(f.access, f.review.getString("object_id"), 1)!!.getJSONObject("body")
        body.getJSONObject("acceptance_review").put("target", delivery)
        val review = f.publish(f.access.copy(nodeId = "author-review", personId = "author", round = 4),
            f.item("second-review", "decision", body).put("parents", JSONArray().put(delivery)))
        val report = f.assessment()
        report.getJSONArray("criteria").getJSONObject(0).put("delivery", delivery).put("review", review)
        assertFalse(f.evaluate(report.toString(), who = f.access.copy(round = 5)).accepted)
    }

    @Test fun missingVersionAndForgedDigestCannotPass() {
        listOf("delivery", "review").forEach { field ->
            val f = Fixture()
            val json = f.assessment()
            json.getJSONArray("criteria").getJSONObject(0).getJSONObject(field).put("sha256", "0".repeat(64))
            assertFalse(field, f.evaluate(json.toString()).accepted)
            val missing = Fixture()
            val report = missing.assessment()
            report.getJSONArray("criteria").getJSONObject(0).getJSONObject(field).put("revision", 99)
            assertFalse(field, missing.evaluate(report.toString()).accepted)
        }
    }

    @Test fun savedRevisionTamperingIsDetected() {
        val f = Fixture()
        val key = f.rows.data.keys.single { it.contains("revision:${f.delivery.getString("object_id")}:1") }
        val saved = JSONObject(f.rows.data.getValue(key))
        saved.getJSONObject("body").put("content", "Altered after review")
        f.rows.data[key] = saved.toString()
        assertFalse(f.evaluate().accepted)
    }

    @Test fun reviewOfOlderVersionCannotAcceptRevisedDelivery() {
        val f = Fixture()
        val update = f.item("unused", "artifact", JSONObject().put("content", "New version"))
            .put("object_id", f.delivery.getString("object_id")).put("base_revision", 1)
        f.publish(f.access.copy(round = 3, nodeId = "revision", personId = "author"), update)
        assertFalse(f.evaluate().accepted)
    }

    @Test fun wrongTargetRequirementOrUnresolvedObjectionInvalidatesReview() {
        listOf("target", "criterion_id", "requirement", "verdict", "unresolved").forEach { field ->
            val f = Fixture()
            val saved = f.workspace.read(f.access, f.review.getString("object_id"), 1)!!
            val body = saved.getJSONObject("body")
            body.getJSONObject("acceptance_review").put(field, when (field) {
                "target" -> JSONObject(f.delivery.toString()).put("revision", 2)
                "unresolved" -> JSONArray().put("Check missing")
                else -> "different"
            })
            val next = f.publish(f.access.copy(nodeId = "review-update", personId = "reviewer"),
                f.item("unused", "decision", body).put("object_id", f.review.getString("object_id")).put("base_revision", 1)
                    .put("parents", JSONArray().put(f.delivery)))
            val json = f.assessment()
            json.getJSONArray("criteria").getJSONObject(0).put("review", next)
            assertFalse(field, f.evaluate(json.toString()).accepted)
        }
    }

    @Test fun crossGroupOtherRunAndRevokedAccessFailClosed() {
        val f = Fixture()
        assertFalse(f.evaluate(who = f.access.copy(groupId = "other")).accepted)
        assertFalse(f.evaluate(who = f.access.copy(runId = "other", turnId = "other")).accepted)
        f.authorized = false
        assertFalse(f.evaluate().accepted)
    }

    @Test fun durableObservationIsResolvedButFailureAndModelAssessmentDoNotCount() {
        assertTrue(Fixture(tool = "web_search").evaluate().accepted)
        assertFalse(Fixture(tool = "web_search", output = "{\"status\":\"failed\"}").evaluate().accepted)
        assertFalse(Fixture(tool = ResearchEvidenceAudit.TOOL).evaluate().accepted)
        val f = Fixture(tool = "web_search")
        f.evidenceRows.data.clear()
        assertFalse(f.evaluate().accepted)
    }

    @Test fun textReportsCannotCertifyComputationalOrPhysicalExecution() {
        listOf("computational", "physical").forEach { type ->
            val f = Fixture()
            val assessment = f.assessment()
            assessment.getJSONArray("criteria").getJSONObject(0).put("verification", type)
            val prior = JSONArray(f.prior).apply { getJSONObject(0).put("verification", type) }.toString()
            assertFalse(f.evaluate(assessment.toString(), previous = prior).accepted)
        }
    }

    @Test fun receiptCannotMoveAcrossGoalCriteriaTurnRunOrNodeAndSurvivesCodec() {
        val f = Fixture()
        val raw = f.assessment().toString()
        val receipt = f.evaluate(raw)
        assertEquals(receipt, CollaborationAcceptanceReceipt.decode(receipt.encode()))
        val record = f.record(raw, receipt)
        val result = record.events.single().result!!
        assertFalse(record.acceptanceVerified(result.copy(output = raw + " ")))
        assertFalse(record.acceptanceVerified(result.copy(outputTruncated = true)))
        assertFalse(record.copy(request = record.request.copy(goal = "Other")).acceptanceVerified(result))
        assertFalse(record.copy(request = record.request.copy(runId = "Other")).acceptanceVerified(result))
        assertFalse(record.copy(request = record.request.copy(messageId = "Other")).acceptanceVerified(result))
        assertFalse(record.copy(request = record.request.copy(context = emptyMap())).acceptanceVerified(result))
        assertFalse(record.acceptanceVerified(result.copy(childId = "Other")))
    }

    @Test fun runtimePersistsHostReceiptAndSnapshotsDoNotRereadEvidence() = runBlocking {
        val f = Fixture()
        val raw = f.assessment().toString()
        val fixtureRecord = f.record(raw, null)
        val store = InMemoryAgentTeamExecutionStore()
        AgentTeamExecutionRuntime(store).use { runtime ->
            val result = runtime.start(fixtureRecord.definition, fixtureRecord.request) {
                AgentSubagentOutput(raw, f.evaluate(raw))
            }.await()
            assertEquals("achieved", result.snapshot.goalDisposition)
            val reads = f.rows.reads
            repeat(50) { assertEquals("achieved", store.snapshot("run")?.goalDisposition) }
            assertEquals(reads, f.rows.reads)
            assertFalse(store.advanceGoal("run", "lead", Long.MAX_VALUE))
        }
    }

    @Test fun upgradingDoesNotRestartPreviouslyCompletedResearchOrCertifyIt() {
        val f = Fixture()
        val raw = f.assessment().toString()
        val historical = f.record(raw, null).let { it.copy(events = it.events + AgentSubagentEvent(2, "run",
            kind = AgentSubagentEventKinds.SUPERVISOR_SUCCEEDED, runStatus = AgentSubagentRunStatus.SUCCEEDED)) }
        assertEquals("unverified_history", CollaborationGoalLoop.disposition(raw, f.prior, allowUnverifiedHistory = true))
        assertNull(CollaborationGoalLoop.advance(historical, "lead", Long.MAX_VALUE, false))
        val active = historical.copy(request = historical.request.copy(context = historical.request.context + (CollaborationGoalLoop.HOST_ACCEPTANCE to "1")),
            definition = historical.definition.copy(members = CollaborationGoalLoop.initial(historical.definition.members, "Goal")))
        assertNotNull(CollaborationGoalLoop.advance(active, "lead", 1_000, false))
    }
}
