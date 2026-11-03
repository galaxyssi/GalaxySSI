package com.galaxyssi.chat

import org.json.JSONObject
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.IDEA
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.LESSON
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.PLAN
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.text

/** Group-scoped selection. Workspace CAS preserves history; existing executors keep pinned work. */
internal object CollaborationCapabilityChannel {
    const val KIND = "capability_channel"
    const val FIELD = "capability_channel"
    val IMPLEMENTATIONS = setOf(CollaborationProceduralMemory.SKILL, CollaborationWorkflowMethod.KIND, CollaborationExecutableTool.RELEASE)

    fun validate(value: JSONObject, head: JSONObject?, revision: JSONObject,
                 exact: (JSONObject, Set<String>) -> JSONObject, historical: (JSONObject, Set<String>) -> JSONObject): JSONObject {
        text(value, "reason")
        val operation = text(value, "operation")
        require(operation in setOf("initialize", "promote", "rollback") && (head == null) == (operation == "initialize")) { "Initialize once; later revisions promote or rollback with base_revision" }
        if (operation == "rollback") {
            val target = historical(value.getJSONObject("target_revision"), setOf(KIND))
            require(target.getString("object_id") == revision.getString("object_id") && target.getInt("revision") < revision.getInt("revision")) {
                "Rollback must name a previously approved revision of this same channel"
            }
            val host = JSONObject(target.getJSONObject(HOST).toString())
            val implementation = exact(host.getJSONObject("implementation"), IMPLEMENTATIONS)
            CollaborationInnovationValidation.checkRecord(implementation, exact)
            CollaborationInnovationValidation.checkRecord(exact(host.getJSONObject("lesson"), setOf(LESSON)), exact)
            val testedSuite = host.optJSONObject("restored_suite") ?: host.getJSONObject("suite")
            host.put("operation", operation).put("restored_from", CollaborationResearchCandidates.reference(target))
                .put("previous_selection", CollaborationResearchCandidates.reference(requireNotNull(head)))
                .put("restored_suite", testedSuite)
                .put("suite", head.getJSONObject(HOST).getJSONObject("suite"))
                .put("newer_capabilities_require_revalidation", !CollaborationResearchCandidates.same(
                    testedSuite, head.getJSONObject(HOST).getJSONObject("suite")))
            return host
        }
        val lesson = exact(value.getJSONObject("lesson"), setOf(LESSON))
        require(lesson.getJSONObject(HOST).getString("state") == "eligible_for_scoped_reuse") { "Selection needs an independently retained lesson" }
        CollaborationInnovationValidation.checkRecord(lesson, exact)
        val implementation = exact(value.getJSONObject("implementation"), IMPLEMENTATIONS)
        val idea = exact(lesson.getJSONObject(HOST).getJSONObject("innovation"), setOf(IDEA))
        if (implementation.getString("kind") == CollaborationWorkflowMethod.KIND) require(
            exact(lesson.getJSONObject(HOST).getJSONObject("plan"), setOf(PLAN)).getJSONObject(HOST).has(CollaborationWorkflowMethod.COMPARISON)) {
            "Selected workflow needs a controlled, exact-version workflow comparison"
        }
        when (implementation.getString("kind")) {
            CollaborationProceduralMemory.SKILL -> require(CollaborationResearchCandidates.same(implementation.getJSONObject(HOST).getJSONObject("lesson"), lesson)) { "Procedure must come from this retained lesson" }
            else -> require(CollaborationResearchCandidates.same(idea.getJSONObject(HOST).getJSONObject(implementation.getString("kind")), implementation)) { "The reviewed innovation must bind this exact executable implementation" }
        }
        CollaborationInnovationValidation.checkRecord(implementation, exact)
        val suite = exact(value.getJSONObject("suite"), setOf(CollaborationCapabilityRetention.SUITE))
        require(CollaborationResearchCandidates.same(suite.getJSONObject(HOST).getJSONObject("lesson"), lesson)) { "Freeze all newly demonstrated capabilities before selecting this version" }
        if (head != null) {
            val old = head.getJSONObject(HOST)
            val plan = exact(lesson.getJSONObject(HOST).getJSONObject("plan"), setOf(PLAN))
            val spec = plan.getJSONObject("body").getJSONObject(PLAN)
            require(implementation.getString("kind") == old.getString("implementation_kind") && lesson.getJSONObject(HOST).getString("domain") == old.getString("domain")) { "A channel cannot change implementation kind or domain" }
            require(CollaborationResearchCandidates.same(spec.getJSONObject("baseline"), old.getJSONObject("innovation")) &&
                CollaborationResearchCandidates.same(spec.getJSONObject(CollaborationCapabilityRetention.FIELD), old.getJSONObject("suite")) &&
                CollaborationResearchCandidates.same(suite.getJSONObject(HOST).getJSONObject("previous_suite"), old.getJSONObject("suite"))) {
                "Promotion must beat the active version, pass its complete capability bank and extend that bank"
            }
        }
        return JSONObject().put("state", "selected_scoped_version").put("operation", operation)
            .put("implementation", CollaborationResearchCandidates.reference(implementation)).put("implementation_kind", implementation.getString("kind"))
            .put("lesson", CollaborationResearchCandidates.reference(lesson)).put("innovation", CollaborationResearchCandidates.reference(idea))
            .put("suite", CollaborationResearchCandidates.reference(suite)).put("domain", lesson.getJSONObject(HOST).getString("domain"))
            .put("grants_permissions", false).apply { head?.let { put("previous_selection", CollaborationResearchCandidates.reference(it)) } }
    }

    fun binding(use: JSONObject, implementation: JSONObject, workspace: CollaborationResearchWorkspace,
                access: CollaborationWorkspaceAccess, replay: Boolean): JSONObject? {
        if (!use.has(FIELD)) return null
        val ref = use.getJSONObject(FIELD)
        require(ref.opt("revision") is Int && ref.getInt("revision") > 0) { "Use an exact capability channel revision" }
        val saved = requireNotNull(workspace.read(access, ref.getString("object_id"), ref.getInt("revision"))) { "Capability channel unavailable or isolated" }
        require(saved.getString("kind") == KIND && CollaborationResearchCandidates.same(saved, ref) &&
            (replay || workspace.isCurrent(access, ref.getString("object_id"), ref.getInt("revision")))) { "Capability selection changed; inspect the active revision for new work" }
        require(CollaborationResearchCandidates.same(saved.getJSONObject(HOST).getJSONObject("implementation"), implementation)) { "Dispatch does not match the selected capability implementation" }
        if (!replay) requireCurrentLineage(saved, workspace, access)
        return CollaborationResearchCandidates.reference(saved)
            .put("protected_suite", saved.getJSONObject(HOST).getJSONObject("suite"))
            .put("newer_capabilities_require_revalidation", saved.getJSONObject(HOST).optBoolean("newer_capabilities_require_revalidation"))
    }

    fun requireCurrentLineage(record: JSONObject, workspace: CollaborationResearchWorkspace, access: CollaborationWorkspaceAccess) {
        CollaborationInnovationValidation.checkRecord(record) { ref, kinds ->
            require(ref.opt("revision") is Int && ref.getInt("revision") > 0) { "Use exact lineage revisions" }
            val saved = requireNotNull(workspace.read(access, ref.getString("object_id"), ref.getInt("revision"))) { "Capability lineage is unavailable or isolated" }
            require(saved.getString("kind") in kinds && CollaborationResearchCandidates.same(saved, ref) &&
                workspace.isCurrent(access, ref.getString("object_id"), ref.getInt("revision"))) { "Capability evidence changed; revalidate before new execution" }
            saved
        }
    }

    fun toolIdea(value: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject? {
        val ref = value.optJSONObject(CollaborationExecutableTool.RELEASE) ?: return null
        val release = exact(ref, setOf(CollaborationExecutableTool.RELEASE))
        require(release.getJSONObject(HOST).getString("state") == "eligible_for_scoped_tool_execution") { "Innovation tool has not passed independent release review" }
        return CollaborationResearchCandidates.reference(release)
    }
}
