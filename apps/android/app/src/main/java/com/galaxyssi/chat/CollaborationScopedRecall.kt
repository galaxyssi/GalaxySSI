package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

/** The host supplies access; model arguments can select records, never a group or member identity. */
internal object CollaborationScopedRecall {
    fun read(context: Context, input: Map<String, Any?>, access: CollaborationWorkspaceAccess,
             recordCoverage: Boolean = true): AgentNativeToolExecutionResult {
        val group = CollaborationGroupStore(context).load(access.groupId)
        if (group == null || access.personId.isNotBlank() && group.members.none { it.id == access.personId })
            return AgentNativeToolExecutionResult.failure("group_unavailable", "Group access was removed.")
        if (input.containsKey("topic") && input["mode"] != "evolution_rules")
            return AgentNativeToolExecutionResult.failure("invalid_arguments", "Topic is only supported for evolution rules.")
        if (input.containsKey("case_filter") && input["mode"] != CollaborationNumericFeedback.MODE)
            return AgentNativeToolExecutionResult.failure("invalid_arguments", "Case filter is only supported for numeric feedback.")
        if (input.containsKey("section") && input["mode"] != "goal_contract")
            return AgentNativeToolExecutionResult.failure("invalid_arguments", "Section is only supported for goal/context recall.")
        if (input.containsKey("work_id") && input["mode"] != CollaborationCoordinatorUpdates.MODE)
            return AgentNativeToolExecutionResult.failure("invalid_arguments", "Work ID is only supported for coordinator updates.")
        return when (input["mode"]) {
            CollaborationCoordinatorUpdates.MODE -> {
                val work = input.containsKey("work_id")
                val fields = if (work) setOf("mode", "work_id") else setOf("mode", "cursor")
                if (input.keys.any { it !in fields } || input.containsKey("cursor") && input["cursor"] !is String ||
                    work && input["work_id"] !is String)
                    return AgentNativeToolExecutionResult.failure("invalid_arguments", "Team updates take cursor for publications OR work_id for the complete work contract.")
                try { AgentNativeToolExecutionResult.success((if (work) CollaborationCoordinatorUpdates.work(context, access, input["work_id"] as String)
                    else CollaborationCoordinatorUpdates.read(context, access, input["cursor"] as? String ?: "")).toNativeObject()) }
                catch (invalid: IllegalArgumentException) {
                    AgentNativeToolExecutionResult.failure("updates_unavailable", invalid.message.orEmpty())
                }
            }
            CollaborationNumericFeedback.MODE -> {
                val revision = input["revision"]
                if (input["object_id"] !is String || input["sha256"] !is String || revision !is Number ||
                    revision.toDouble() != revision.toInt().toDouble() || revision.toInt() < 1)
                    return AgentNativeToolExecutionResult.failure("invalid_arguments", "Numeric feedback requires an exact trial reference.")
                val saved = CollaborationResearchWorkspace(context).read(access, input["object_id"] as String, revision.toInt())
                    ?: return AgentNativeToolExecutionResult.failure("object_unavailable", "Numeric trial is missing or isolated.")
                try { AgentNativeToolExecutionResult.success(CollaborationNumericFeedback.page(saved, input).toNativeObject()) }
                catch (invalid: IllegalArgumentException) {
                    AgentNativeToolExecutionResult.failure("invalid_arguments", invalid.message.orEmpty())
                }
            }
            "method_history" -> {
                val workspace = CollaborationResearchWorkspace(context)
                if (input.containsKey("record_id")) {
                    if (input.keys.any { it !in setOf("mode", "record_id", "offset") } || input["record_id"] !is String)
                        return AgentNativeToolExecutionResult.failure("invalid_arguments", "Method history record accepts record_id and offset only.")
                    val saved = workspace.methodHistoryRecord(access, input.getValue("record_id") as String)
                        ?: return AgentNativeToolExecutionResult.failure("record_unavailable", "Method history is missing or isolated.")
                    page(saved, input, "host_execution_observation_not_method_effectiveness",
                        mapOf("record_id" to saved.getString("record_id"), "record_sha256" to saved.getString("sha256")))
                } else {
                    if (input.keys.any { it !in setOf("mode", "object_id", "revision", "sha256", "cursor") } ||
                        input["object_id"] !is String || input["sha256"] !is String || input["revision"] !is Number ||
                        (input["revision"] as Number).toDouble() != (input["revision"] as Number).toInt().toDouble() ||
                        (input["revision"] as Number).toInt() < 1 || input.containsKey("cursor") && input["cursor"] !is String)
                        return AgentNativeToolExecutionResult.failure("invalid_arguments", "Method history requires exact object_id, revision, sha256 and optional cursor.")
                    val ref = JSONObject().put("object_id", input["object_id"]).put("revision", (input["revision"] as Number).toInt())
                        .put("sha256", input["sha256"])
                    AgentNativeToolExecutionResult.success(workspace.methodHistory(access, ref, input["cursor"] as? String ?: "").toNativeObject())
                }
            }
            "capabilities" -> {
                if (input.keys.any { it !in setOf("mode", "query", "cursor") } || input["query"] !is String ||
                    input.containsKey("cursor") && input["cursor"] !is String)
                    return AgentNativeToolExecutionResult.failure("invalid_arguments", "Capability search accepts query and cursor only.")
                val result = try { CollaborationResearchWorkspace(context).searchCapabilities(access,
                    input.getValue("query") as String, input["cursor"] as? String ?: "") }
                catch (invalid: IllegalArgumentException) {
                    return AgentNativeToolExecutionResult.failure("invalid_arguments", invalid.message.orEmpty())
                }
                AgentNativeToolExecutionResult.success(result.toNativeObject())
            }
            "problems" -> {
                if (input.keys.any { it !in setOf("mode", "cursor") })
                    return AgentNativeToolExecutionResult.failure("invalid_arguments", "Problem directory accepts only cursor.")
                val result = try { CollaborationEvidenceLedger(context).problems(access, input["cursor"] as? String ?: "") }
                    catch (invalid: IllegalArgumentException) {
                        return AgentNativeToolExecutionResult.failure("invalid_arguments", invalid.message.orEmpty())
                    }
                AgentNativeToolExecutionResult.success(mapOf("observations" to result.first.map { it.toString() },
                    "next_cursor" to result.second, "coverage" to "indexed_tool_failures_not_all_possible_gaps",
                    "trust" to "observed_symptoms_not_diagnosed_causes"))
            }
            "evolution_rules" -> {
                if (input.keys.any { it !in setOf("mode", "offset", "topic") } ||
                    input.containsKey("topic") && input["topic"] !is String)
                    return AgentNativeToolExecutionResult.failure("invalid_arguments", "Evolution rules accept offset and topic only.")
                val topic = input["topic"] as? String ?: "all"
                val rules = try { CollaborationEvolutionProtocol.rules(topic) } catch (invalid: IllegalArgumentException) {
                    return AgentNativeToolExecutionResult.failure("invalid_arguments", invalid.message.orEmpty())
                }
                page(rules, input, "host_schema_not_execution_authority", mapOf("topic" to topic))
            }
            "evolution" -> {
                if (input.keys.any { it !in setOf("mode", "cursor") })
                    return AgentNativeToolExecutionResult.failure("invalid_arguments", "Evolution directory accepts only cursor.")
                val result = CollaborationResearchWorkspace(context).browseEvolution(access, input["cursor"] as? String ?: "")
                AgentNativeToolExecutionResult.success(mapOf("revisions" to result.revisions.map { it.toString() },
                    "next_cursor" to result.next, "trust" to "scoped_learning_not_scientific_certification"))
            }
            "archive" -> {
                if (input.keys.any { it !in setOf("mode", "record_id", "offset") })
                    return AgentNativeToolExecutionResult.failure("invalid_arguments", "Archive recall accepts record_id and offset only.")
                val record = CollaborationResearchArchive(context, access.groupId).read(input["record_id"] as? String ?: "")
                    ?: return AgentNativeToolExecutionResult.failure("record_unavailable", "Original is unavailable.")
                val saved = JSONObject(record.content)
                if (!CollaborationResearchArchive.visibleToAssignment(saved, access))
                    return AgentNativeToolExecutionResult.failure("record_isolated", "Original is not an assigned dependency.")
                page(saved, input, "member_reported_not_verified", mapOf("record_id" to record.id))
            }
            "goal_contract" -> {
                if (input.keys.any { it !in setOf("mode", "cursor", "section") } ||
                    input.containsKey("cursor") && input["cursor"] !is String ||
                    input.containsKey("section") && (input["section"] !is String ||
                        !CollaborationGoalContractSections.valid(input["section"] as String)))
                    return AgentNativeToolExecutionResult.failure("invalid_arguments", "Goal contract recall accepts mode, cursor and optional section (goal, criteria, source or context:<exact name>).")
                val store = CollaborationGoalContractStore(context)
                val cursor = input["cursor"] as? String ?: ""
                val result = (input["section"] as? String)?.let { store.readSection(access, it, cursor) } ?: store.read(access, cursor)
                if (result.optString("status") != "ok")
                    AgentNativeToolExecutionResult.failure("goal_contract_unavailable", result.optString("reason", "Contract is unavailable."))
                else AgentNativeToolExecutionResult.success(result.toNativeObject() +
                    ("trust" to "host_goal_contract_not_comprehension_or_claim_verification"))
            }
            "evidence" -> {
                val access = CollaborationCoordinatorUpdates.readAccess(context, access)
                val ledger = CollaborationEvidenceLedger(context)
                val id = input["evidence_id"] as? String ?: ""
                if (id.isNotBlank()) {
                    val offset = input["offset"] ?: 0
                    if (offset !is Number || offset.toDouble() != offset.toInt().toDouble() || offset.toInt() < 0)
                        return AgentNativeToolExecutionResult.failure("invalid_arguments", "Evidence offset must be a nonnegative integer.")
                    val page = try { ledger.readPage(access, id, input["sha256"] as? String ?: "", offset.toInt(), recordCoverage) }
                        catch (invalid: IllegalArgumentException) {
                            return AgentNativeToolExecutionResult.failure("invalid_arguments", invalid.message.orEmpty())
                        }
                        ?: return AgentNativeToolExecutionResult.failure("evidence_unavailable", "Evidence is missing, changed or isolated from this assignment.")
                    val source = listOf("evidence_id", "sha256", "origin", "tool", "status", "observation_kind")
                        .associateWith { page.source.get(it) }
                    AgentNativeToolExecutionResult.success(mapOf("content" to page.content, "total_characters" to page.total,
                        "next_offset" to page.next, "trust" to "execution_observed_not_claim_verified",
                        CollaborationEvidenceReadCoverage.FIELD to page.coverage.toNativeObject(),
                        "source_reference" to source,
                        "citation_guidance" to "To cite the original observation in workspace.observations, copy source_reference.evidence_id and sha256. " +
                            "galaxyssi_evidence_receipt describes this recall operation, not the original source. " +
                            "Follow next_offset until null before publishing a review. Missing pages cannot support formal acceptance; " +
                            "use host_read_coverage.first_missing_offset to resume gaps. Page coverage is not comprehension or verification."))
                } else {
                    val (refs, next) = ledger.browse(access, input["cursor"] as? String ?: "")
                    AgentNativeToolExecutionResult.success(mapOf("observations" to refs.map { it.toString() },
                        "next_cursor" to next, "trust" to "execution_observed_not_claim_verified"))
                }
            }
            "workspace" -> {
                val access = CollaborationCoordinatorUpdates.readAccess(context, access)
                val workspace = CollaborationResearchWorkspace(context)
                val id = input["object_id"] as? String ?: ""
                if (id.isNotBlank()) {
                    val saved = workspace.read(access, id, (input["revision"] as? Number)?.toInt() ?: 0)
                        ?: return AgentNativeToolExecutionResult.failure("object_unavailable", "Object revision is missing or isolated from this assignment.")
                    page(saved, input, "member_reported_not_verified")
                } else {
                    val result = workspace.browse(access, input["cursor"] as? String ?: "")
                    AgentNativeToolExecutionResult.success(mapOf("revisions" to result.revisions.map { it.toString() },
                        "next_cursor" to result.next, "trust" to "member_reported_not_verified"))
                }
            }
            else -> AgentNativeToolExecutionResult.failure("invalid_mode", "Use goal_contract, evidence, workspace, archive, evolution, capabilities, method_history, evolution_rules, numeric_cases, team_updates or problems for scoped recall.")
        }
    }

    private fun page(saved: JSONObject, input: Map<String, Any?>, trust: String,
                     metadata: Map<String, Any?> = emptyMap()): AgentNativeToolExecutionResult {
        val content = saved.toString()
        val offset = (input["offset"] as? Number)?.toInt()?.coerceIn(0, content.length) ?: 0
        val end = minOf(content.length, offset + 8_000)
        return AgentNativeToolExecutionResult.success(mapOf("content" to content.substring(offset, end),
            "total_characters" to content.length, "next_offset" to end.takeIf { it < content.length }, "trust" to trust) + metadata)
    }
}
