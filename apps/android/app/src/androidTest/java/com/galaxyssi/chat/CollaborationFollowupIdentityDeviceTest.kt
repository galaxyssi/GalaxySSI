package com.galaxyssi.chat

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CollaborationFollowupIdentityDeviceTest {
    @Test fun productionWorkerDispatchesOrdinaryFollowupsWithEvidenceBindingAndPreservesTheModel() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val transcripts = AgentTranscriptStore(context)
        val previous = transcripts.activeConversation().id
        val conversation = transcripts.createConversation(privateMode = true)
        val groups = CollaborationGroupStore(context)
        try {
            val member = CollaborationMember(name = "Turing", agentId = "identity-fixture", providerLabel = "Fixture",
                modelId = "selected-model")
            val group = groups.update(conversation.id) { it.copy(members = listOf(member), coordinatorId = member.id) }
            val respondent = CollaborationFollowupPolicy.respondents(group, "请概括已有结果", group.requested(emptyList())).single()
            val registration = AgentRegistration(agentId = member.agentId, installationId = "fixture", deviceId = "fixture",
                providerId = "fixture", displayName = "Identity fixture", kind = AgentConnectorKind.AGENT,
                location = AgentResourceLocation.TRUSTED_DESKTOP, status = AgentEndpointStatus.ONLINE,
                capabilities = setOf(AgentCapability.RESEARCH), protocol = AgentProtocolRange("1.0", "1.0", "1.0"),
                connectionKind = AgentConnectionKind.GALAXYSSI_LINK, trust = AgentResourceTrust.VERIFIED_PAIRED,
                adapterType = "codex-app-server-or-cli")
            val actions = mutableListOf<AgentAction>()
            val provider = ActionExecutorAgentProvider(registrationSource = { listOf(registration) },
                delegate = object : AgentActionExecutor {
                    override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
                        actions += action
                        return AgentActionResult(action.id, true, "这是独立追问的测试回答。")
                    }
                })
            val worker = ActionExecutorAgentTeamMemberWorker(provider,
                AgentAdapterDirectory().apply { register(provider) },
                { ScreenContext("identity-fixture", pageTitle = "Fixture") }, progressContext = context)
            val request = AgentRunRequest(conversation.id, "turn-${conversation.id}", "task-${conversation.id}",
                runId = "child-${conversation.id}", parentRunId = "parent-${conversation.id}", goal = "请概括已有结果",
                idempotencyKey = "dispatch-${conversation.id}")
            val execution = AgentTeamMemberExecutionContext(
                AgentTeamMember(member.agentId, AgentDeliveryMode.RESPOND, instanceId = respondent.instanceId,
                    context = mapOf("collaboration_group_id" to conversation.id, "collaboration_name" to member.name,
                        "collaboration_model_id" to respondent.modelId)),
                request, AgentSubagentContextHandoff("", emptyList(), 0, 60_000, false), 0, AgentSubagentProvenance())
            val result = worker.execute(execution)
            assertEquals("这是独立追问的测试回答。", result.content)
            assertEquals(1, actions.size)
            assertEquals("selected-model", actions.single().parameters["manual_model_id"])
            assertEquals(conversation.id, actions.single().parameters["_galaxyssi_conversation_id"])
            val access = CollaborationWorkspaceAccess.from(execution)
            val source = AgentTeamDispatchIds.sourceMessageId("member:${request.idempotencyKey}")
            assertEquals(member.id, access.personId)
            assertEquals(access, CollaborationEvidenceLedger(context).binding(source, conversation.id, request.messageId))
            assertTrue(CollaborationResearchArchive(context, conversation.id).browse().total >= 2)
        } finally {
            groups.remove(conversation.id)
            transcripts.deleteConversation(conversation.id)
            transcripts.switchConversation(previous)
        }
    }
}
