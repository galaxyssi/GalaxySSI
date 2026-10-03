package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Evidence-driven documentary review/repair/recheck. No candidate or revision-count limit, never certification. */
internal object CollaborationCandidateEvolution {
    const val REQUESTS = "candidate_cycles"
    const val STATE = "collaboration_research_candidate_cycles"
    const val FEEDBACK = "collaboration_research_candidate_feedback"
    const val TASK = "collaboration_research_candidate_task"
    private const val WORK_TASK = "candidate_task"
    private const val PREFIX = "candidate-cycle:"

    data class Plan(val work: List<JSONObject>, val state: String, val feedback: String = "", val error: Boolean = false)

    fun reserved(id: String) = id.startsWith(PREFIX)
    fun workId(cycle: JSONObject): String = "$PREFIX${cycle.getString("id")}:${cycle.getString("phase")}" +
        cycle.optString("work_key").takeIf(String::isNotBlank)?.let { ":$it" }.orEmpty()
    fun requested(assessment: JSONObject?) = (assessment?.optJSONArray(REQUESTS)?.length() ?: 0) > 0
    fun pending(state: String): Boolean = CollaborationCandidateVerificationState.pending(state)
    fun taskContext(work: JSONObject): Map<String, String> = work.optJSONObject(WORK_TASK)?.let { mapOf(TASK to it.toString()) }.orEmpty()
    fun completedNodes(state: String, finishedWork: Set<String>): Set<String> = runCatching {
        val cycles = CollaborationCandidateVerificationState.read(state)
        (0 until cycles.length()).map { cycles.getJSONObject(it) }.filter {
            it.getString("phase") != "done" && it.has("node_id") && workId(it) in finishedWork
        }.mapTo(hashSetOf()) { it.getString("node_id") }
    }.getOrDefault(emptySet())
    fun summary(state: String): String = runCatching {
        val saved = CollaborationCandidateVerificationState.checkpoint(state)
        val cycles = saved.cycles
        val recent = JSONArray((maxOf(0, cycles.length() - 8) until cycles.length()).map { index ->
            val cycle = cycles.getJSONObject(index)
            JSONObject().put("target", cycle.getJSONObject("target")).put("phase", cycle.getString("phase"))
                .put("result", cycle.optString("result"))
        })
        JSONObject().put("recent_cycles", recent).put("total_cycles", cycles.length())
            .put("pending_requests", saved.pendingRequests.length()).toString()
    }.getOrDefault("Candidate checkpoint is malformed; automatic work is unavailable")

    fun plan(workspace: CollaborationResearchWorkspace, access: CollaborationWorkspaceAccess, people: Set<String>,
             criteria: JSONArray, requests: JSONArray, previous: String, succeededNodes: Set<String>,
             dispatchId: (String) -> String): Plan = runCatching {
        val saved = CollaborationCandidateVerificationState.checkpoint(previous)
        val cycles = saved.cycles
        val indexes = hashMapOf<String, Int>()
        val deferred = mutableListOf<JSONObject>()
        val feedback = mutableListOf<String>()
        repeat(cycles.length()) {
            val cycle = cycles.getJSONObject(it)
            val objectId = cycle.getString("object_id")
            require(cycle.getString("id") == AgentNativeJsonCodec.sha256(JSONArray(listOf(access.runId, access.turnId, objectId)).toString())) {
                "Saved candidate cycle belongs to another goal scope"
            }
            indexes[objectId] = it
        }
        CollaborationCandidateVerificationState.requests(saved.pendingRequests, requests).forEach { request ->
          try {
            val requestedTarget = request.getJSONObject("target")
            val objectId = requestedTarget.getString("object_id")
            val existingIndex = indexes[objectId]
            val existing = existingIndex?.let { cycles.getJSONObject(it) }
            if (existing != null) {
                if (requestedTarget.optLong("revision") <= existing.getJSONObject("target").getLong("revision")) return@forEach
                if (existing.getString("phase") != "done") { deferred += request; return@forEach }
            }
            val target = exact(workspace, access, requestedTarget)
            require(current(workspace, access, target)) { "Candidate enrollment needs an exact current active revision" }
            val criterion = (0 until criteria.length()).map { criteria.getJSONObject(it) }
                .singleOrNull { it.getString("id") == request.getString("criterion_id") }
                ?: error("Candidate cycle must name an established original criterion")
            require(criterion.optString("verification") == "documentary" && CollaborationEvidenceRequirements.required(criterion).isNotEmpty()) {
                "Automatic candidate review requires documentary criteria with original host source requirements; physical/computational adapters are unavailable"
            }
            require(criterion.getString("requirement") in candidateCriteria(target)) { "Candidate must preserve the exact goal requirement" }
            val editor = request.getString("editor")
            val reviewer = request.getString("reviewer")
            require(editor in people && reviewer in people && editor != reviewer && reviewer !in contributors(target)) {
                "Select an authorized editor and a different independent non-contributor reviewer"
            }
            val id = AgentNativeJsonCodec.sha256(JSONArray(listOf(access.runId, access.turnId, objectId)).toString())
            val enrolled = JSONObject().put("id", id).put("object_id", objectId).put("target", reference(target))
                .put("criterion", JSONObject(criterion.toString())).put("editor", editor).put("reviewer", reviewer).put("phase", "validate")
            if (existing != null) {
                require(existing.getJSONObject("criterion").getString("id") == criterion.getString("id") &&
                    existing.getJSONObject("criterion").getString("requirement") == criterion.getString("requirement") &&
                    CollaborationEvidenceRequirements.required(criterion) == CollaborationEvidenceRequirements.required(existing.getJSONObject("criterion"))) {
                    "A reopened candidate must retain its original criterion/source contract"
                }
                enrolled.put("work_key", target.getString("sha256"))
                enrolled.put("prior_settlements", existing.optJSONArray("prior_settlements") ?: JSONArray())
                    .getJSONArray("prior_settlements").put(JSONObject().put("target", existing.getJSONObject("target")).put("result", existing.getString("result")))
                cycles.put(existingIndex!!, enrolled)
            } else {
                indexes[objectId] = cycles.length()
                cycles.put(enrolled)
            }
          } catch (failure: Exception) {
            deferred += request
            feedback += "Candidate enrollment deferred: ${failure.message}"
          }
        }
        val work = mutableListOf<JSONObject>()
        repeat(cycles.length()) { index ->
            val cycle = cycles.getJSONObject(index)
            if (cycle.getString("phase") == "done") return@repeat
            fun finish(reason: String) {
                cycle.put("phase", "done").put("result", reason).put("verification_state", "not_verified")
                feedback += "${cycle.getString("object_id")}: $reason"
            }
            try {
                require(cycle.getString("editor") in people && cycle.getString("reviewer") in people) {
                    "An assigned candidate member is unavailable; no automatic substitution or recruitment"
                }
                val original = cycle.getJSONObject("criterion")
                val criterion = (0 until criteria.length()).map { criteria.getJSONObject(it) }
                    .singleOrNull { it.getString("id") == original.getString("id") }
                require(criterion != null && criterion.getString("requirement") == original.getString("requirement") &&
                    criterion.optString("verification") == "documentary" &&
                    CollaborationEvidenceRequirements.required(criterion) == CollaborationEvidenceRequirements.required(original)) {
                    "Preserved criterion/source contract changed; replan explicitly"
                }
                val target = exact(workspace, access, cycle.getJSONObject("target"))
                if (!current(workspace, access, target)) {
                    // A completed repair is the sole allowed transition to a new target below.
                    if (cycle.getString("phase") != "repair" || !cycle.has("node_id")) {
                        finish("Target changed or retired; no stale validation or automatic restart")
                        return@repeat
                    }
                }
                if (cycle.has("node_id")) {
                    val node = cycle.getString("node_id")
                    val outputs = workspace.publicationRevisions(access, node)
                    if (node !in succeededNodes || outputs.size != 1) {
                        finish("No successful exact workspace publication; manual replanning required, no automatic retry")
                        return@repeat
                    }
                    val output = outputs.single()
                    val phase = cycle.getString("phase")
                    if (phase == "repair") {
                        require(output.getString("object_id") == target.getString("object_id") &&
                            output.getInt("revision") == target.getInt("revision") + 1 &&
                            output.getString("previous_sha256") == target.getString("sha256") &&
                            output.getString("person_id") == cycle.getString("editor") &&
                            output.optJSONObject("host_candidate")?.optString("operation") == "revise" &&
                            CollaborationResearchCandidates.same(output.getJSONObject("host_candidate").getJSONObject("basis"), cycle.getJSONObject("review")) &&
                            current(workspace, access, output)) { "Repair output does not match the exact assigned revision and review" }
                        cycle.put("target", reference(output)).put("phase", "recheck").remove("node_id")
                    } else {
                        val event = output.getJSONObject("host_candidate_event")
                        require(output.getString("person_id") == cycle.getString("reviewer") && event.getString("operation") == "review" &&
                            event.getString("criterion") == cycle.getJSONObject("criterion").getString("requirement") &&
                            CollaborationResearchCandidates.same(event.getJSONArray("targets").getJSONObject(0), target) &&
                            workspace.candidateReviewApplies(access, reference(output))) { "Review output is stale or mismatched" }
                        val report = output.getJSONObject("body").getJSONObject("candidate_event")
                        qualify(cycle.getJSONObject("criterion"), output)
                        if (report.getString("outcome") == "refuted") {
                            if (phase == "recheck") cycle.put("work_key", target.getString("sha256"))
                            cycle.put("review", reference(output)).put("phase", "repair").remove("node_id")
                        } else {
                            finish("${phase}: ${report.getString("outcome")} recorded, not host verified; no executable correction supplied by this assessment")
                            return@repeat
                        }
                    }
                }
                val phase = cycle.getString("phase")
                val member = cycle.getString(if (phase == "repair") "editor" else "reviewer")
                if (member !in people) {
                    finish("Assigned member is unavailable; no automatic substitute or recruitment")
                    return@repeat
                }
                val task = JSONObject().put("operation", if (phase == "repair") "revise" else "review")
                    .put("target", cycle.getJSONObject("target")).put("criterion", cycle.getJSONObject("criterion"))
                    .put("member", member).put("group_id", access.groupId).put("run_id", access.runId).put("turn_id", access.turnId)
                if (phase == "repair") task.put("basis", cycle.getJSONObject("review"))
                checkTask(workspace, access.copy(personId = member), task)
                val workId = workId(cycle)
                val node = dispatchId(workId)
                work += JSONObject().put("id", workId).put("member", member).put("stage", if (phase == "repair") "REVISE" else "VERIFY")
                    .put("assignment", assignment(task)).put(WORK_TASK, task)
                cycle.put("node_id", node)
            } catch (error: Exception) {
                finish("Candidate cycle stopped without certification: ${error.message}; manual replanning required")
            }
        }
        Plan(work, CollaborationCandidateVerificationState.encode(cycles, deferred), feedback.joinToString("\n"))
    }.getOrElse { Plan(emptyList(), previous, it.message ?: "Invalid candidate cycle", error = true) }

    fun checkTask(workspace: CollaborationResearchWorkspace, access: CollaborationWorkspaceAccess, task: JSONObject) {
        checkIdentity(access, task)
        val target = exact(workspace, access, task.getJSONObject("target"))
        require(current(workspace, access, target)) { "Candidate task target changed or is isolated; do not execute stale work" }
        val criterion = task.getJSONObject("criterion")
        require(criterion.optString("verification") == "documentary" && CollaborationEvidenceRequirements.required(criterion).isNotEmpty() &&
            criterion.getString("requirement") in candidateCriteria(target)) { "No qualified documentary source contract for this candidate task" }
        when (task.getString("operation")) {
            "review" -> require(access.personId !in contributors(target)) { "Candidate reviewer is a contributor" }
            "revise" -> {
                val review = exact(workspace, access, task.getJSONObject("basis"), candidate = false)
                require(workspace.candidateReviewApplies(access, reference(review)) &&
                    review.getJSONObject("host_candidate_event").getString("criterion") == criterion.getString("requirement") &&
                    CollaborationResearchCandidates.same(review.getJSONObject("host_candidate_event").getJSONArray("targets").getJSONObject(0), target) &&
                    review.getJSONObject("body").getJSONObject("candidate_event").getString("outcome") == "refuted") {
                    "Automatic repair requires an applicable exact independent refutation"
                }
                qualify(criterion, review)
                val refs = workspace.observationReferences(access, reference(review))
                CollaborationEvidenceRequirements.validate(criterion, (0 until refs.length()).map { refs.getJSONObject(it) })
            }
            else -> error("Unknown host candidate task")
        }
    }

    fun checkIdentity(access: CollaborationWorkspaceAccess, task: JSONObject) {
        require(task.getString("group_id") == access.groupId && task.getString("run_id") == access.runId &&
            task.getString("turn_id") == access.turnId && task.getString("member") == access.personId) { "Candidate task scope changed" }
    }

    fun checkPublication(task: JSONObject, revisions: List<JSONObject>) {
        require(revisions.size == 1) { "A bounded candidate task publishes exactly one assigned revision/event; preserve alternatives" }
        val saved = revisions.single()
        val target = task.getJSONObject("target")
        if (task.getString("operation") == "review") {
            val event = saved.optJSONObject("host_candidate_event")
            require(saved.getString("kind") == "candidate_event" && event?.optString("operation") == "review" &&
                CollaborationResearchCandidates.same(event.getJSONArray("targets").getJSONObject(0), target) &&
                event.getString("criterion") == task.getJSONObject("criterion").getString("requirement")) { "Publish only the exact assigned candidate review" }
            qualify(task.getJSONObject("criterion"), saved)
        } else {
            val candidate = saved.optJSONObject("host_candidate")
            require(saved.getString("kind") == "candidate" && candidate?.optString("operation") == "revise" &&
                saved.getString("object_id") == target.getString("object_id") && saved.getInt("revision") == target.getInt("revision") + 1 &&
                saved.getString("previous_sha256") == target.getString("sha256") &&
                CollaborationResearchCandidates.same(candidate.getJSONObject("basis"), task.getJSONObject("basis"))) { "Publish only the exact assigned repair with its review basis" }
        }
    }

    fun instructions() = "Optional candidate_cycles enrolls exact existing workspace candidates without a fixed candidate-count limit: " +
        "[{target:{object_id,revision,sha256},criterion_id:\"preserved goal criterion ID\",editor:\"person UUID\",reviewer:\"independent person UUID\"}]. " +
        "Use only documentary criteria with required_observations and the exact requirement in candidate.criteria. " +
        "Every applicable refutation may lead to a repair and a fresh independent review, with no fixed repair or review count. " +
        "Candidate reviewers must read every original evidence page before publishing; a listed ID or summary does not count. " +
        "Read coverage is frozen at publication, so later reads require a new review rather than validating an old one. " +
        "Host capacity controls execution concurrency; host admission budgets defer requests in durable pending state, never discard them or declare success. " +
        "Do not duplicate this work in work[], solicit extra votes, retire alternatives, or claim candidate reviews are verification. " +
        "Physical/computational criteria need qualified host validators; simulation never satisfies physical requirements. "

    fun artifactInstructions() = "Parallel alternatives use workspace kind=candidate, not only the top-level candidates notes. " +
        "body={content:\"full original\",candidate:{operation:\"propose|revise|combine|retire\",rationale:\"evidence-based reason\",criteria:[\"exact original goal requirement\"]}}. " +
        "Propose a distinct ID with no parents. Revise/retire use the existing object_id, exact base_revision and sole exact head parent; " +
        "combine creates a new ID from at least two distinct active current parents and retains all parent criteria. Retire preserves content and criteria; never delete alternatives. " +
        "All parents/resolves copy {object_id,revision,sha256}. Evolution needs actual observations. " +
        "For kind=candidate_event use body.candidate_event={operation:\"compare|challenge|review\",targets:[{object_id,revision,sha256}]," +
        "criterion:\"exact shared requirement\",check:\"specific discriminating check\",rationale:\"evidence assessment\",outcome:\"supported|refuted|not_tested\",unresolved:[]}. " +
        "Compare has at least two distinct targets and outcome differentiated|inconclusive. Challenge has one target, refuted|not_tested and correction. " +
        "Review has one exact current target, a non-contributor reviewer and actual returned host observations; supported cannot retain blockers. " +
        "Repair from a review also copies its exact reference into body.candidate.basis, NOT into resolves. " +
        "resolves accepts preserved counterexample/question objects (or a candidate challenge), not a candidate review; " +
        "use resolves=[] for review-based repair unless a separate qualifying counterexample/question is supplied. " +
        "A review is a member assessment, never a host verification certificate. "

    private fun assignment(task: JSONObject): String = "Exact-version candidate ${task.getString("operation")}. " +
        "Read the full exact target and original required host observations through scoped recall. " +
        "Publish exactly one candidate_event review, or one candidate revise with body.candidate.basis copied from this task. " +
        "Use resolves=[]; the review basis belongs only in body.candidate.basis. For revise, object_id and base_revision name the target, " +
        "and parents contains only the exact target reference, not the basis review. Cite original source_reference IDs in observations. " +
        "Do not change other candidates or execute unauthorized experiments; preserve alternatives. " +
        "A missing/unsupported check remains not_tested, never verified. Do not repeat completed side effects to manufacture receipts. " +
        "Host task: $task"

    private fun qualify(criterion: JSONObject, revision: JSONObject) {
        val refs = revision.getJSONArray("host_observations")
        CollaborationEvidenceRequirements.validate(criterion, (0 until refs.length()).map { refs.getJSONObject(it) })
    }
    private fun exact(workspace: CollaborationResearchWorkspace, access: CollaborationWorkspaceAccess, ref: JSONObject,
                      candidate: Boolean = true): JSONObject {
        val version = CollaborationRemoteEvidenceProtocol.integer(ref, "revision")
        require(version != null && version in 1..Int.MAX_VALUE.toLong()) { "Exact integer candidate revision required" }
        val saved = requireNotNull(workspace.read(access, ref.getString("object_id"), version.toInt())) { "Candidate reference missing or isolated" }
        require(CollaborationResearchCandidates.same(saved, ref) && saved.getString("run_id") == access.runId &&
            saved.getString("turn_id") == access.turnId && (!candidate || saved.getString("kind") == "candidate")) { "Candidate reference digest or goal scope mismatch" }
        return saved
    }
    private fun current(workspace: CollaborationResearchWorkspace, access: CollaborationWorkspaceAccess, target: JSONObject) =
        CollaborationResearchCandidates.active(target) && workspace.isCurrent(access, target.getString("object_id"), target.getInt("revision"))
    private fun candidateCriteria(target: JSONObject) = strings(target.getJSONObject("body").getJSONObject("candidate").getJSONArray("criteria"))
    private fun contributors(target: JSONObject) = strings(target.getJSONObject("host_candidate").getJSONArray("contributors"))
    private fun strings(values: JSONArray) = (0 until values.length()).map { values.getString(it) }
    private fun reference(value: JSONObject) = CollaborationResearchCandidates.reference(value)
}
