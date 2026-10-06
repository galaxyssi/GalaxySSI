package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Test-only frozen candidate, never a retained skill, independent review, or permission grant. */
internal class CollaborationPilotArtifact private constructor(
    val source: Source, val payload: String
) {
    class Source private constructor(private val fields: Map<String, String>) {
        val pilotId get() = fields.getValue("pilot_id")
        val slotId get() = fields.getValue("slot_id")
        val artifactId = "candidate-" + hash(fields.entries.joinToString("") { (key, value) ->
            "${key.length}:$key${value.length}:$value"
        })
        fun json() = JSONObject(fields)
        operator fun get(key: String) = fields.getValue(key)
        fun matches(value: JSONObject) = value.keys().asSequence().toSet() == fields.keys &&
            fields.all { (key, expected) -> value.get(key) == expected }

        companion object {
            fun from(value: JSONObject): Source {
                val keys = listOf("pilot_id", "slot_id", "case_id", "arm", "protocol_sha256", "run_id",
                    "conversation_id", "turn_id", "task_id", "target_id", "model_id", "reasoning_effort", "goal_sha256")
                require(value.keys().asSequence().toSet() == keys.toSet())
                val fields = keys.associateWith { key ->
                    (value.get(key) as? String)?.also { require(it.isNotBlank()) } ?: error("Source field must be text: $key")
                }
                for (key in listOf("pilot_id", "slot_id", "case_id"))
                    require(fields.getValue(key).matches(Regex("[a-zA-Z0-9][a-zA-Z0-9_-]{0,47}")))
                require(fields.getValue("arm") in setOf("single", "team"))
                require(digestPattern.matches(fields.getValue("protocol_sha256")) && digestPattern.matches(fields.getValue("goal_sha256")))
                require(fields.getValue("task_id") == "task-${fields.getValue("run_id")}")
                return Source(fields)
            }

            fun of(plan: CollaborationRemotePilotPlan, slot: CollaborationRemotePilotPlan.Slot,
                   group: String, run: String, turn: String, protocolSha256: String): Source {
                require(slot in plan.slots && listOf(group, run, turn).all { it.isNotBlank() })
                require(digestPattern.matches(protocolSha256))
                return Source(linkedMapOf("pilot_id" to plan.id, "slot_id" to slot.id, "case_id" to slot.caseId,
                    "arm" to slot.arm, "protocol_sha256" to protocolSha256, "run_id" to run,
                    "conversation_id" to group, "turn_id" to turn, "task_id" to "task-$run",
                    "target_id" to plan.targetId, "model_id" to plan.selection.modelId,
                    "reasoning_effort" to plan.selection.reasoningEffort.wireValue, "goal_sha256" to hash(slot.prompt)))
            }
        }
    }

    data class Reference(val artifactId: String, val sha256: String) {
        init { require(artifactId.matches(Regex("candidate-[0-9a-f]{64}")) && digestPattern.matches(sha256)) }
        fun json() = JSONObject().put("artifact_id", artifactId).put("sha256", sha256)
        companion object {
            fun from(value: JSONObject): Reference {
                require(value.keys().asSequence().toSet() == setOf("artifact_id", "sha256"))
                return Reference(value.get("artifact_id") as String, value.get("sha256") as String)
            }
        }
    }

    val reference = Reference(source.artifactId, hash(payload))
    val finalOutput get() = JSONObject(payload).getString("final_output")
    fun envelope() = JSONObject().put("payload_json", payload).put("reference", reference.json()).toString()

    companion object {
        private val digestPattern = Regex("[0-9a-f]{64}")
        private val nodes = listOf("draft", "review", "final")
        private fun hash(value: String) = CollaborationRemotePilotDispatch.sha256(value.toByteArray(Charsets.UTF_8))

        fun capture(source: Source, snapshot: AgentTeamExecutionSnapshot, dispatches: JSONArray,
                    outputTruncated: Boolean): CollaborationPilotArtifact {
            require(!outputTruncated) { "Truncated output cannot become a frozen candidate" }
            require(snapshot.state == AgentTeamExecutionState.SUCCEEDED && !snapshot.paused)
            require(snapshot.supervisorRunId == source["run_id"] && snapshot.teamId == source["run_id"] &&
                snapshot.conversationId == source["conversation_id"] && snapshot.taskId == source["task_id"] &&
                snapshot.primaryAgentId == source["target_id"] && snapshot.primaryInstanceId == "final" &&
                hash(snapshot.goal) == source["goal_sha256"]) { "Candidate source does not match runtime snapshot" }
            require(snapshot.members.map { it.memberId } == nodes && snapshot.members.all {
                it.status == AgentSubagentStatus.SUCCEEDED && it.agentId == source["target_id"] &&
                    it.collaborationGroupId == source["conversation_id"] && it.output.isNotBlank()
            }) { "All assigned nodes must have completed successfully" }
            val body = JSONObject().put("format", "galaxyssi.remote-pilot-candidate.v1")
                .put("source", source.json()).put("trust", "unverified_candidate")
                .put("grants_permissions", false).put("final_output", snapshot.finalOutput)
                .put("final_output_sha256", hash(snapshot.finalOutput))
                .put("members", JSONArray(snapshot.members.map { JSONObject().put("node_id", it.memberId)
                    .put("person_id", it.personId).put("status", it.status.name).put("output", it.output) }))
                .put("dispatches", JSONArray(dispatches.toString()))
            validate(source, body)
            return CollaborationPilotArtifact(source, body.toString())
        }

        fun restore(raw: String, source: Source, expected: Reference): CollaborationPilotArtifact {
            require(expected.artifactId == source.artifactId) { "Candidate belongs to a different source" }
            val envelope = JSONObject(raw)
            require(envelope.keys().asSequence().toSet() == setOf("payload_json", "reference"))
            val ref = envelope.getJSONObject("reference")
            require(ref.keys().asSequence().toSet() == setOf("artifact_id", "sha256") &&
                ref.get("artifact_id") == expected.artifactId && ref.get("sha256") == expected.sha256)
            val payload = envelope.get("payload_json") as? String ?: error("Candidate payload must be exact text")
            require(hash(payload) == expected.sha256) { "Frozen candidate digest changed" }
            validate(source, JSONObject(payload))
            return CollaborationPilotArtifact(source, payload)
        }

        /** Exact completed test-report import, not a fresh runtime or provider attestation. */
        fun recoverReport(plan: CollaborationRemotePilotPlan, slot: CollaborationRemotePilotPlan.Slot,
                          protocolSha256: String, raw: String, expectedReportSha256: String): CollaborationPilotArtifact {
            require(digestPattern.matches(expectedReportSha256) && hash(raw) == expectedReportSha256)
            require(digestPattern.matches(protocolSha256) && slot in plan.slots)
            val report = JSONObject(raw)
            require(report.get("format") == "galaxyssi.remote-pilot-report.v1" && report.get("finished") == true &&
                report.get("pilot_id") == plan.id && report.get("protocol_sha256") == protocolSha256)
            require(report.get("selection_source") == "app_conversation_snapshot" &&
                (report.get("selection_conversation_id") as? String)?.isNotBlank() == true)
            val selection = report.getJSONObject("model_selection")
            require(selection.get("requested_model") == plan.selection.modelId &&
                selection.get("requested_reasoning_effort") == plan.selection.reasoningEffort.wireValue)
            val assigned = report.getJSONArray("slots")
            require(assigned.length() == plan.slots.size)
            plan.slots.forEachIndexed { index, expected ->
                val value = assigned.getJSONObject(index)
                require(value.get("id") == expected.id && value.get("case_id") == expected.caseId && value.get("arm") == expected.arm)
            }
            val outcome = assigned.getJSONObject(plan.slots.indexOf(slot))
            require(outcome.get("status") == "completed" && outcome.get("state") == "SUCCEEDED" &&
                outcome.get("result_truncated") == false && outcome.get("cleanup_confirmed") == true &&
                outcome.get("durable_control") == "STOP" && outcome.getJSONArray("pending_remote_owners").length() == 0)
            val run = "remote-pilot-${plan.id}-${slot.id}"
            require(outcome.get("run_id") == run && outcome.get("turn_id") == "turn-$run")
            val source = Source.of(plan, slot, outcome.getString("conversation_id"), run, "turn-$run", protocolSha256)
            val savedMembers = outcome.getJSONArray("members")
            require(savedMembers.length() == nodes.size)
            val members = JSONArray()
            nodes.forEachIndexed { index, node ->
                val member = savedMembers.getJSONObject(index)
                require(member.get("node") == node && member.get("error") == "")
                members.put(JSONObject().put("node_id", node).put("person_id", member.get("person_id"))
                    .put("status", member.get("status")).put("output", member.get("output")))
            }
            val output = outcome.get("final_output") as? String ?: error("Report output must be exact text")
            val body = JSONObject().put("format", "galaxyssi.remote-pilot-candidate.v2")
                .put("source", source.json()).put("trust", "unverified_candidate").put("grants_permissions", false)
                .put("final_output", output).put("final_output_sha256", hash(output)).put("members", members)
                .put("dispatches", JSONArray(outcome.getJSONArray("phone_dispatches").toString()))
                .put("report_recovery", JSONObject().put("origin", "completed_test_report")
                    .put("report_sha256", expectedReportSha256).put("provider_attested", false))
            validate(source, body)
            return CollaborationPilotArtifact(source, body.toString())
        }

        private fun validate(source: Source, body: JSONObject) {
            val recovered = body.get("format") == "galaxyssi.remote-pilot-candidate.v2"
            val fields = setOf("format", "source", "trust", "grants_permissions",
                "final_output", "final_output_sha256", "members", "dispatches")
            require(body.keys().asSequence().toSet() == fields + if (recovered) setOf("report_recovery") else emptySet())
            require((recovered || body.get("format") == "galaxyssi.remote-pilot-candidate.v1") &&
                body.get("trust") == "unverified_candidate" && body.get("grants_permissions") == false)
            if (recovered) {
                val provenance = body.getJSONObject("report_recovery")
                require(provenance.keys().asSequence().toSet() == setOf("origin", "report_sha256", "provider_attested") &&
                    provenance.get("origin") == "completed_test_report" && provenance.get("provider_attested") == false &&
                    digestPattern.matches(provenance.get("report_sha256") as? String ?: ""))
            }
            require(source.matches(body.getJSONObject("source"))) { "Frozen candidate source changed" }
            val output = body.get("final_output") as? String ?: error("Candidate output must be text")
            require(output.isNotBlank() && body.get("final_output_sha256") == hash(output))
            val members = body.getJSONArray("members")
            val dispatches = body.getJSONArray("dispatches")
            require(members.length() == nodes.size && dispatches.length() == nodes.size)
            val owners = mutableSetOf<String>()
            val messages = mutableSetOf<Long>()
            val keys = mutableSetOf<String>()
            nodes.forEachIndexed { index, node ->
                val person = if (node == "review" && source["arm"] == "team") "reviewer" else "analyst"
                val member = members.getJSONObject(index)
                require(member.get("node_id") == node && member.get("person_id") == person &&
                    member.get("status") == "SUCCEEDED" && (member.get("output") as? String)?.isNotBlank() == true)
                if (node == "final") require(member.get("output") == output) { "Final output differs from final node" }
                val entry = dispatches.getJSONObject(index)
                require(entry.get("node_id") == node && entry.get("person_id") == person &&
                    entry.get("transport_instance_id") == person && entry.get("parent_run_id") == source["run_id"] &&
                    entry.get("turn_id") == source["turn_id"] && entry.get("conversation_id") == source["conversation_id"] &&
                    entry.get("task_id") == source["task_id"] && entry.get("target_id") == source["target_id"] &&
                    entry.get("requested_model") == source["model_id"] &&
                    entry.get("requested_reasoning_effort") == source["reasoning_effort"] &&
                    entry.get("accounting_scope") == "phone_delegate_dispatch_not_provider_request") {
                    "Candidate dispatch attribution changed: $node"
                }
                val owner = entry.get("owner_run_id") as? String ?: error("Missing owner")
                val key = entry.get("idempotency_key") as? String ?: error("Missing dispatch key")
                require(owner.isNotBlank() && owners.add(owner) && key.isNotBlank() && keys.add(key))
                val message = CollaborationTrialPolicy.strictLong(entry.get("source_message_id"))
                require(messages.add(message) && message == AgentTeamDispatchIds.sourceMessageId("member:$key"))
                require(digestPattern.matches(entry.get("prepared_prompt_sha256") as? String ?: ""))
            }
        }
    }
}
