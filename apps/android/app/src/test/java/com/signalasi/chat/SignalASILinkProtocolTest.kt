package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Test
import java.util.UUID

class SignalASILinkProtocolTest {
    @Test
    fun routeIdsAreOpaque128BitBase64UrlValues() {
        val first = SignalASILinkProtocol.newRouteId()
        val second = SignalASILinkProtocol.newRouteId()
        assertEquals(22, first.length)
        assertTrue(SignalASILinkProtocol.validRouteId(first))
        assertNotEquals(first, second)
    }

    @Test
    fun relationshipTopicsAreDerivedFromBothRoutes() {
        val server = SignalASILinkProtocol.newRouteId()
        val client = SignalASILinkProtocol.newRouteId()
        val routes = SignalASILinkProtocol.Routes(server, client)
        assertEquals("signalasichat/v1/$server/pair", routes.pairing)
        assertEquals("signalasichat/v1/$server/$client/up", routes.up)
        assertEquals("signalasichat/v1/$server/$client/down", routes.down)
        assertEquals("signalasichat/v1/$server/$client/control", routes.control)
    }

    @Test
    fun rotatingRelationshipDropsOnlyMessagesForItsOldTopics() {
        val oldRoutes = SignalASILinkProtocol.Routes(
            SignalASILinkProtocol.newRouteId(),
            SignalASILinkProtocol.newRouteId()
        )
        val otherRoutes = SignalASILinkProtocol.Routes(
            SignalASILinkProtocol.newRouteId(),
            SignalASILinkProtocol.newRouteId()
        )
        val source = JSONArray()
            .put(outboxMessage("old-up", oldRoutes.up))
            .put(outboxMessage("old-control", oldRoutes.control))
            .put(outboxMessage("other-up", otherRoutes.up))

        val kept = SignalASILinkDeliveryStore.retainMessagesOutsideTopics(
            source,
            setOf(oldRoutes.up, oldRoutes.down, oldRoutes.control, oldRoutes.pairing)
        )

        assertEquals(1, kept.length())
        assertEquals("other-up", kept.getJSONObject(0).getString("message_id"))
        assertEquals(3, source.length())
    }

    @Test
    fun deliveryRetriesRemainEligibleAfterManyAttempts() {
        assertEquals(2_000L, SignalASILinkRetryPolicy.delayMillis(1))
        assertEquals(256_000L, SignalASILinkRetryPolicy.delayMillis(8))
        assertEquals(300_000L, SignalASILinkRetryPolicy.delayMillis(9))
        assertEquals(300_000L, SignalASILinkRetryPolicy.delayMillis(10_000))

        val now = 1_000_000L
        val values = JSONArray()
            .put(
                outboxMessage("many-attempts", "topic")
                    .put("attempts", 10_000)
                    .put("next_attempt_at", now)
                    .put("created_at", 1L)
            )
            .put(
                outboxMessage("not-due", "topic")
                    .put("attempts", 1)
                    .put("next_attempt_at", now + 1L)
                    .put("created_at", 2L)
            )
        val pending = SignalASILinkDeliveryStore.pendingFromArray(values, now)
        assertEquals(1, pending.size)
        assertEquals("many-attempts", pending.single().messageId)
    }

    @Test
    fun outboxSchedulerUsesEarliestDueMessageInsteadOfFixedPolling() {
        val now = 1_000_000L
        val values = JSONArray()
            .put(outboxMessage("later", "topic").put("next_attempt_at", now + 30_000L))
            .put(outboxMessage("next", "topic").put("next_attempt_at", now + 750L))
            .put(outboxMessage("past-due", "topic").put("next_attempt_at", now - 1L))

        assertEquals(0L, SignalASILinkDeliveryStore.nextRetryDelayFromArray(values, now))
        values.remove(2)
        assertEquals(750L, SignalASILinkDeliveryStore.nextRetryDelayFromArray(values, now))
        assertNull(SignalASILinkDeliveryStore.nextRetryDelayFromArray(JSONArray(), now))
    }

    @Test
    fun deferredMediaWaitsForValidatedNetworkWithoutBlockingText() {
        val now = 1_000_000L
        val values = JSONArray()
            .put(
                outboxMessage("media", "topic")
                    .put("next_attempt_at", now)
                    .put("requires_validated_network", true)
            )
            .put(
                outboxMessage("text", "topic")
                    .put("next_attempt_at", now + 750L)
                    .put("requires_validated_network", false)
            )

        val constrained = SignalASILinkDeliveryStore.pendingFromArray(
            values,
            now + 1_000L,
            allowValidatedNetworkMessages = false
        )
        val recovered = SignalASILinkDeliveryStore.pendingFromArray(
            values,
            now + 1_000L,
            allowValidatedNetworkMessages = true
        )

        assertEquals(listOf("text"), constrained.map { it.messageId })
        assertEquals(listOf("media", "text"), recovered.map { it.messageId })
        assertEquals(
            750L,
            SignalASILinkDeliveryStore.nextRetryDelayFromArray(
                values,
                now,
                allowValidatedNetworkMessages = false
            )
        )
        assertEquals(
            0L,
            SignalASILinkDeliveryStore.nextRetryDelayFromArray(
                values,
                now,
                allowValidatedNetworkMessages = true
            )
        )
    }

    @Test
    fun deliveryAckSeparatesTransportAndClientMessageIds() {
        val transportId = UUID.randomUUID().toString()
        val payload = JSONObject()
            .put("type", "delivery_ack")
            .put("transport_message_id", transportId)
            .put("source_message_id", "521")
            .put("client_source_message_id", "521")

        assertEquals(transportId, SignalASILinkDeliveryAckPolicy.transportMessageId(payload))
        assertEquals("521", SignalASILinkDeliveryAckPolicy.clientSourceMessageId(payload))
    }

    @Test
    fun deliveryAckNeverTreatsLogicalMessageNumberAsTransportId() {
        val payload = JSONObject()
            .put("type", "delivery_ack")
            .put("source_message_id", "521")

        assertEquals("", SignalASILinkDeliveryAckPolicy.transportMessageId(payload))
        assertEquals("521", SignalASILinkDeliveryAckPolicy.clientSourceMessageId(payload))
    }

    @Test
    fun legacyTransportAckWithUuidSourceStillClearsOutbox() {
        val transportId = UUID.randomUUID().toString()
        val payload = JSONObject()
            .put("type", "delivery_ack")
            .put("source_message_id", transportId)

        assertEquals(transportId, SignalASILinkDeliveryAckPolicy.transportMessageId(payload))
        assertEquals("", SignalASILinkDeliveryAckPolicy.clientSourceMessageId(payload))
    }

    @Test
    fun ciphertextReplayDigestIsStableAndSensitiveToCiphertext() {
        val first = JSONObject()
            .put("scheme", "signal")
            .put("from", "desktop")
            .put("to", "phone")
            .put("message_type", 2)
            .put("body", "ciphertext-a")
        val reordered = JSONObject()
            .put("body", "ciphertext-a")
            .put("message_type", 2)
            .put("to", "phone")
            .put("from", "desktop")
            .put("scheme", "signal")
        val changed = JSONObject(first.toString()).put("body", "ciphertext-b")

        assertEquals(
            SignalASILinkCiphertextReplayPolicy.digest(first),
            SignalASILinkCiphertextReplayPolicy.digest(reordered)
        )
        assertNotEquals(
            SignalASILinkCiphertextReplayPolicy.digest(first),
            SignalASILinkCiphertextReplayPolicy.digest(changed)
        )
    }

    @Test
    fun pairingAccessProfilesFailClosedWhenExecutorScopesAreIncomplete() {
        val restricted = pairingAccess(
            SignalASILinkProtocol.ACCESS_RESTRICTED,
            SignalASILinkProtocol.SCOPE_AGENT_CHAT,
            SignalASILinkProtocol.SCOPE_EXPLICIT_ATTACHMENTS,
            SignalASILinkProtocol.SCOPE_TASK_WORKSPACE
        )
        val executor = pairingAccess(
            SignalASILinkProtocol.ACCESS_DESKTOP_EXECUTOR,
            SignalASILinkProtocol.SCOPE_AGENT_CHAT,
            SignalASILinkProtocol.SCOPE_EXPLICIT_ATTACHMENTS,
            SignalASILinkProtocol.SCOPE_TASK_WORKSPACE,
            SignalASILinkProtocol.SCOPE_DESKTOP_EXECUTOR,
            SignalASILinkProtocol.SCOPE_DESKTOP_CONTROL,
            SignalASILinkProtocol.SCOPE_DESKTOP_NATIVE_TOOLS,
            SignalASILinkProtocol.SCOPE_DESKTOP_EXTERNAL_FILES,
            SignalASILinkProtocol.SCOPE_DESKTOP_APPROVAL_BYPASS
        )
        val forgedRestricted = pairingAccess(
            SignalASILinkProtocol.ACCESS_RESTRICTED,
            SignalASILinkProtocol.SCOPE_AGENT_CHAT,
            SignalASILinkProtocol.SCOPE_EXPLICIT_ATTACHMENTS,
            SignalASILinkProtocol.SCOPE_TASK_WORKSPACE,
            SignalASILinkProtocol.SCOPE_DESKTOP_EXECUTOR
        )

        assertEquals(
            SignalASILinkProtocol.ACCESS_RESTRICTED,
            SignalASILinkProtocol.pairingAccess(restricted)?.profile
        )
        assertTrue(SignalASILinkProtocol.pairingAccess(executor)?.fullDesktopExecutor == true)
        assertNull(SignalASILinkProtocol.pairingAccess(forgedRestricted))
    }

    private fun outboxMessage(id: String, topic: String): JSONObject = JSONObject()
        .put("message_id", id)
        .put("topic", topic)
        .put("wire_payload", "{}")

    private fun pairingAccess(profile: String, vararg scopes: String): JSONObject = JSONObject()
        .put("contract_version", SignalASILinkProtocol.ACCESS_CONTRACT)
        .put("version", 1)
        .put("profile", profile)
        .put("scopes", JSONArray(scopes.toList()))
}
