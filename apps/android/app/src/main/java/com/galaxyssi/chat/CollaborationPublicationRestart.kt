package com.galaxyssi.chat

import kotlinx.coroutines.runBlocking

/** Finish a saved local publication, never redispatch a lost model/tool execution. */
internal object CollaborationPublicationRestart {
    fun recover(store: AgentTeamExecutionStore, run: String, workspace: CollaborationResearchWorkspace,
                archive: (AgentTeamMemberExecutionContext, String) -> String, allowed: () -> Boolean): Int {
        if (!allowed()) return 0
        val snapshot = store.snapshot(run)?.takeIf { it.state == AgentTeamExecutionState.INTERRUPTED } ?: return 0
        val checkpoint = store.interruptedCheckpoint(run) ?: return 0
        val running = snapshot.members.filter { it.status == AgentSubagentStatus.RUNNING }.associateBy { it.memberId }
        var sequence = checkpoint.lastSequence
        var recovered = 0
        checkpoint.definition.members.filter { it.memberId in running && it.agentId.startsWith("cloud:") }.forEach { member ->
            if (!allowed()) return recovered
            val stage = CollaborationResearchWorkflow.stage(member)?.takeIf { it != CollaborationResearchStage.DELIVER } ?: return@forEach
            val request = checkpoint.request.copy(runId = stableAgentTeamMemberRunId(run, member.memberId), parentRunId = run,
                context = checkpoint.request.context + member.context, deliveryMode = member.deliveryMode,
                idempotencyKey = "${checkpoint.request.idempotencyKey}:${member.memberId}")
            val execution = AgentTeamMemberExecutionContext(member, request,
                AgentSubagentContextHandoff("", emptyList(), 0, 0, false), 1,
                AgentSubagentProvenance(source = "agent-team", sourceId = checkpoint.definition.teamId, traceId = run,
                    metadata = mapOf("instance_id" to member.memberId, "agent_id" to member.agentId,
                        "recovery" to "saved-publication")))
            val access = CollaborationWorkspaceAccess.from(execution)
            if (workspace.publicationContract(access) == null) return@forEach
            val saved = workspace.publicationCheckpoint(access) ?: return@forEach
            val raw = saved.getString("raw")
            val receipt = workspace.submitPublication(access, raw, revalidate = true)
            if (receipt.optString("status") != "recorded" || !allowed()) return@forEach
            val archiveId = archive(execution, raw)
            check(archiveId.isNotBlank()) { "Recovered publication requires a preserved original" }
            val artifact = requireNotNull(CollaborationResearchArtifact.decode(raw))
            artifact.remove("remote_evidence_import")
            artifact.put("workspace_receipt", receipt)
            val output = CollaborationResearchArtifact.compactHandoff(
                CollaborationResearchArtifact.handoff(artifact.toString(), stage), archiveId)
            val now = System.currentTimeMillis()
            val result = AgentSubagentChildResult(supervisorId = run, childId = member.memberId, parentId = run, depth = 1,
                status = AgentSubagentStatus.SUCCEEDED, output = output, outputTruncated = false,
                provenance = execution.provenance, startedAtMillis = running.getValue(member.memberId).startedAtMillis,
                completedAtMillis = now)
            runBlocking { store.append(AgentSubagentEvent(++sequence, run, member.memberId,
                AgentSubagentEventKinds.CHILD_SUCCEEDED, childStatus = AgentSubagentStatus.SUCCEEDED,
                provenance = execution.provenance, result = result, timestampMillis = now)) }
            recovered++
        }
        return recovered
    }
}
