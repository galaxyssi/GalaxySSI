package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Retrieval aids for learned methods, never automatic adoption or additional authority. */
internal object CollaborationCapabilityRecall {
    val KINDS = setOf("procedure_skill", "failure_experience", "capability_lesson", "workflow_method",
        "tool_release", "capability_channel", CollaborationWorkflowSelection.KIND, CollaborationToolComparison.KIND)
    const val SCAN_PAGE = 100
    const val RESULT_PAGE = 12

    data class Query(val text: String, val terms: List<String>)

    fun query(value: String): Query {
        require(value.isNotBlank() && value.length <= 1000) { "Capability query requires 1-1000 characters" }
        val terms = AgentKnowledgeTextAnalyzer.tokens(value)
        require(terms.isNotEmpty()) { "Use descriptive capability keywords" }
        return Query(value, terms)
    }

    fun match(saved: JSONObject, query: Query, read: (JSONObject) -> JSONObject? = { null }): JSONObject? {
        val kind = saved.getString("kind")
        if (kind !in KINDS) return null
        val body = saved.getJSONObject("body").optJSONObject(kind) ?: return null
        val fields = linkedMapOf("title" to saved.getString("title"))
        listOf("name", "purpose", "domain", "keywords", "applies_when", "avoid_when", "limitations",
            "observed_issue", "interpretation", "avoid_repetition", "reconsider_when", "procedure",
            "bottleneck", "change_rationale", "risks").forEach { field ->
            when (val value = body.opt(field)) {
                is String -> fields[field] = value
                is JSONArray -> fields[field] = (0 until value.length()).mapNotNull { value.opt(it) as? String }.joinToString(" ")
            }
        }
        val sources = JSONArray()
        if (kind == CollaborationProceduralMemory.SKILL) {
            body.optJSONArray("inputs")?.let { inputs ->
                fields["inputs"] = (0 until inputs.length()).map { inputs.getJSONObject(it) }
                    .joinToString(" ") { "${it.getString("name")} ${it.getString("description")}" }
            }
            val host = saved.optJSONObject(CollaborationEvolutionContract.HOST)
            host?.optString("domain")?.takeIf(String::isNotBlank)?.let { fields["domain"] = it }
            // The skill cannot carry replacement steps. Search the exact reviewed lesson, within reader scope.
            host?.optJSONObject("lesson")?.let { ref ->
                val lesson = read(ref)?.takeIf { it.optString("kind") == CollaborationEvolutionContract.LESSON &&
                    CollaborationResearchCandidates.same(it, ref) &&
                    it.optJSONObject(CollaborationEvolutionContract.HOST)?.optString("state") == "eligible_for_scoped_reuse" }
                lesson?.getJSONObject("body")?.getJSONObject(CollaborationEvolutionContract.LESSON)?.let { value ->
                    val names = listOf("procedure", "applies_when", "avoid_when", "transfer_test")
                    names.forEach { field -> fields[field] = value.getString(field) }
                    sources.put(JSONObject().put("source", CollaborationResearchCandidates.reference(lesson))
                        .put("fields", JSONArray(names)).put("complete_read", false))
                }
            }
        }
        if (kind == CollaborationExecutableTool.RELEASE) {
            val host = saved.optJSONObject(CollaborationEvolutionContract.HOST)
            if (host?.optString("state") == "eligible_for_scoped_tool_execution") {
                host.optJSONObject(CollaborationExecutableTool.TOOL)?.let { ref ->
                    val tool = read(ref)?.takeIf { it.optString("kind") == CollaborationExecutableTool.TOOL &&
                        CollaborationResearchCandidates.same(it, ref) &&
                        host.optString("source_sha256").isNotBlank() &&
                        it.optJSONObject(CollaborationEvolutionContract.HOST)?.optString("source_sha256") == host.optString("source_sha256") }
                    tool?.getJSONObject("body")?.getJSONObject(CollaborationExecutableTool.TOOL)?.let { value ->
                        // Preserve the reviewer's narrower conditions; code and test answers are not search excerpts.
                        val names = listOf("name", "purpose", "environment", "dependencies", "applies_when", "avoid_when", "side_effects")
                        names.forEach { field -> fields["tool_$field"] = value.getString(field) }
                        sources.put(JSONObject().put("source", CollaborationResearchCandidates.reference(tool))
                            .put("field_prefix", "tool_").put("fields", JSONArray(names)).put("complete_read", false))
                    }
                }
            }
        }
        val normalized = fields.mapValues { AgentKnowledgeTextAnalyzer.normalize(it.value) }
        val matches = query.terms.filter { term -> normalized.values.any { term in it } }
        if (matches.isEmpty()) return null
        val score = matches.fold(0) { total, term -> total + normalized.entries.fold(0) { value, (field, text) ->
            value + if (term !in text) 0 else if (field in setOf("title", "name", "domain", "keywords", "tool_name")) 3 else 1
        } }
        val snippets = JSONObject()
        fields.entries.sortedByDescending { (field, _) -> matches.any { it in normalized.getValue(field) } }.forEach { (field, text) ->
            if (field in setOf("name", "domain", "applies_when", "avoid_when", "limitations", "observed_issue") ||
                matches.any { it in normalized.getValue(field) }) {
                if (snippets.length() < 5) snippets.put(field, text.take(180))
            }
        }
        return CollaborationResearchCandidates.reference(saved).put("title", saved.getString("title"))
            .put("kind", kind).put("recorded_at", saved.getLong("recorded_at"))
            .put("reported_state", saved.optJSONObject(CollaborationEvolutionContract.HOST)?.optString("state").orEmpty())
            .put("matched_terms", JSONArray(matches)).put("lexical_score", score).put("excerpts", snippets)
            .put("linked_sources", sources)
            .put("requires_scope_and_lineage_check", true).put("grants_permissions", false)
    }

    fun page(query: Query, records: List<JSONObject>, next: String?): JSONObject = JSONObject()
        .put("query", query.text).put("records", JSONArray(records.sortedWith(
            compareByDescending<JSONObject> { it.getInt("lexical_score") }.thenBy { it.getString("object_id") })))
        .put("next_cursor", next ?: JSONObject.NULL).put("scan_complete", next == null)
        .put("snapshot", false)
        .put("ranking", "lexical_within_page_not_global_or_semantic")
        .put("coverage", "visible_saved_capabilities_not_all_possible_methods")
        .put("trust", "retrieval_aids_not_validated_for_this_task")
        .put("guidance", "Follow next_cursor even after an empty page; null ends this query's live directory scan. " +
            "Concurrent publications do not restart pagination; rerun without cursor to discover additions or revisions behind it. " +
            "Search synonyms, other languages and alternative methods separately; no match is not proof no useful method exists. " +
            "Read exact workspace originals and their evidence, conditions and counterexamples before reuse. " +
            "Procedure matches can include their exact retained lesson; linked_sources identifies excerpt origins, not a full-read receipt. " +
            "Tool releases can include exact source metadata under tool_*; both source and review conditions apply, and code/tests require separate reads. " +
            "Follow usage_recall to inspect prior conditions, failures and delivery. Tool releases return original native observations with " +
            "read_original selectors for inputs, runtime reports and errors; follow empty pages and distinguish replays from executions. " +
            "Execution success is not a quality gain. " +
            "Check current lineage using the existing procedure/workflow/tool/channel admission; retrieval does not approve adoption.")

    fun context(workspace: CollaborationResearchWorkspace, execution: AgentTeamMemberExecutionContext): String {
        val objective = execution.member.objective
        val goal = execution.request.goal
        val query = listOf(objective.take(450), goal.take(450)).filter(String::isNotBlank).distinct().joinToString(" ")
        if (query.isBlank() || AgentKnowledgeTextAnalyzer.tokens(query).isEmpty()) return ""
        return workspace.searchCapabilities(CollaborationWorkspaceAccess.from(execution), query)
            .put("query_source", "assignment_and_goal_excerpt")
            .put("query_truncated", objective.length > 450 || goal.length > 450).toString()
    }
}
