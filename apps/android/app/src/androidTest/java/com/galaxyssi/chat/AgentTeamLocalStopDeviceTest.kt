package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Exact public fixture ownership only; no installed model or user task is executed/stopped. */
@RunWith(AndroidJUnit4::class)
class AgentTeamLocalStopDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun offlineTeamStopSettlesOnlyItsLocalMemberAndPersistsInternalReceipt() {
        val run = "public-team-local-stop-${UUID.randomUUID()}"
        val member = "fixture-member"
        val owner = stableAgentTeamMemberRunId(run, member)
        val key = "$run-key"
        val source = AgentTeamDispatchIds.sourceMessageId("member:$key")
        val identity = AgentLocalDispatchIdentity(source, "local-llm", "$run-conversation", "$run-turn", "$run-task", "team-$owner")
        val request = AgentRunRequest(conversationId = identity.conversationId, messageId = identity.turnId,
            taskId = identity.taskId, runId = owner, parentRunId = run, goal = "Public cancellation fixture",
            idempotencyKey = key, deliveryMode = AgentDeliveryMode.OBSERVE, context = mapOf("managed_team" to true))
        val action = AgentManagedDispatchIntent.bind(AgentAction(id = identity.actionId,
            kind = AgentActionKind.CALL_CONNECTOR, target = "local-llm", risk = AgentRisk.LOW,
            status = AgentActionStatus.RUNNING, description = "Public cancellation fixture",
            parameters = mapOf(MANAGED_AGENT_TEAM_ACTION_PARAMETER to "true", "agent_instance_id" to member,
                "idempotency_key" to key)), request, "fixture-local-model")
        val team = AgentTeamExecutionSnapshot(run, run, identity.conversationId, identity.taskId, member,
            "Public local cancellation fixture", AgentTeamVisibilityMode.BACKGROUND, AgentTeamExecutionState.INTERRUPTED,
            listOf(AgentTeamMemberSnapshot(member, "Fixture", AgentDeliveryMode.OBSERVE, AgentSubagentStatus.RUNNING)))
        val ledger = EncryptedAgentManagedResponseLedger(context)
        val lease = AgentLocalDispatchRegistry.register(identity)
        val sibling = AgentLocalDispatchRegistry.register(identity.copy(sourceMessageId = source + 1, actionId = "other-member"))
        val started = CountDownLatch(1)
        val settled = CountDownLatch(1)
        val executor = Executors.newSingleThreadExecutor()
        try {
            AgentManagedDispatchIntent.persist(context, action, source, identity.contactId, identity.conversationId,
                identity.turnId, identity.taskId)
            assertNotNull(ledger.findOwner(owner))
            val future = executor.submit {
                lease.execute({ token ->
                    val cancelled = CountDownLatch(1)
                    val subscription = token.invokeOnCancellation { cancelled.countDown() }
                    try { started.countDown(); assertTrue(cancelled.await(10, TimeUnit.SECONDS)); "late result" }
                    finally { subscription.dispose(); settled.countDown() }
                }, { fail("STOP-winning local dispatch cannot publish a result") }, {
                    assertEquals(0L, settled.count)
                    AgentLocalCancellationDelivery.settled(context, identity, dedicatedHistory = false, managedTeam = true)
                })
            }
            assertTrue(started.await(10, TimeUnit.SECONDS))
            AgentTeamRemoteStopRecovery({ false }, { error("Offline local stop cannot use MQTT") })
                .reconcile(listOf(team), ledger) { it == run }
            future.get(10, TimeUnit.SECONDS)
            assertFalse(sibling.token.isCancellationRequested)
            assertFalse(PhoneExecutionAuthority.isCancelled(identity.taskId))
            val reopened = EncryptedAgentManagedResponseLedger(context)
            val saved = requireNotNull(reopened.findOwner(owner))
            assertEquals(AgentManagedResponseState.COMPLETED, saved.state)
            val receipt = requireNotNull(saved.response)
            assertFalse(receipt.success)
            assertEquals("cancelled", receipt.taskStatus)
            assertFalse(AgentConnectorResponseStore.contains(context, receipt))
            assertTrue(reopened.pendingForSupervisor(run).isEmpty())
            AgentConnectorResponseBus.publish(context, receipt.copy(success = true, taskStatus = "completed", content = "Late success"))
            assertEquals("cancelled", reopened.findOwner(owner)?.response?.taskStatus)
            assertFalse(AgentConnectorResponseStore.contains(context, receipt))
        } finally { lease.cancel(); lease.close(); sibling.close(); executor.shutdownNow(); ledger.removeOwner(owner) }
    }

    @Test fun stoppedDedicatedHistoryNoLongerSaysRequestingAndDoesNotCreateAnIncomingReply() {
        val id = "public-local-history-stop-${UUID.randomUUID()}"
        val source = ChatHistoryStore.appendOutgoing(context, id, "公开测试：本地停止状态。",
            deliveryStatus = context.getString(R.string.delivery_status_requesting))
        try {
            val identity = AgentLocalDispatchIdentity(source, id, "$id-conversation", "$id-turn", "$id-task", "$id-action")
            AgentLocalCancellationDelivery.settled(context, identity, dedicatedHistory = true, managedTeam = false)
            val history = ChatHistoryStore.readContact(context, id)
            assertEquals(1, history.length())
            val message = history.getJSONObject(0)
            assertTrue(message.getBoolean("isMine"))
            assertEquals(context.getString(R.string.cloud_stream_cancelled_status), message.getString("deliveryStatus"))
            assertEquals("cancelled", message.getJSONArray("deliveryTrace").getJSONObject(
                message.getJSONArray("deliveryTrace").length() - 1).getString("stage"))
            assertFalse(AgentConnectorResponseStore.contains(context, AgentConnectorResponse(source, id, "Public fixture")))
        } finally { ChatHistoryStore.deleteMessage(context, source) }
    }
}
