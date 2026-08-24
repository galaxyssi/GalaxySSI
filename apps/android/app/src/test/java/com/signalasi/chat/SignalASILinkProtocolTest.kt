package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Test
import java.util.UUID

class SignalASILinkProtocolTest {

    @Test
    fun agentRequestUsesClientMessageIdForDeliveryFailureCorrelation() {
        val payload = JSONObject()
            .put("type", "text")
            .put("client_message_id", 1308L)
            .put("source_message_id", 99L)

        assertEquals(1308L, SignalASILinkDeliveryStore.outboundClientSourceMessageId(payload))
        assertEquals(
            99L,
            SignalASILinkDeliveryStore.outboundClientSourceMessageId(
                JSONObject().put("source_message_id", "99")
            )
        )
        assertEquals(0L, SignalASILinkDeliveryStore.outboundClientSourceMessageId(JSONObject()))
    }

    @Test
    fun reliableOutboxCanFindAConnectorHandoffByClientSource() {
        val values = JSONArray()
            .put(outboxMessage("first", "topic").put("client_source_message_id", 1308L))
            .put(outboxMessage("second", "topic").put("client_source_message_id", 1400L))

        assertTrue(SignalASILinkDeliveryStore.containsClientSourceMessageId(values, 1308L))
        assertTrue(SignalASILinkDeliveryStore.containsClientSourceMessageId(values, 1400L))
        assertFalse(SignalASILinkDeliveryStore.containsClientSourceMessageId(values, 9999L))
        assertFalse(SignalASILinkDeliveryStore.containsClientSourceMessageId(values, 0L))
    }

    @Test
    fun envelopeBoundaryReplacesNonUuidMessageIds() {
        val envelope = SignalASILinkProtocol.makeEnvelope(
            JSONObject()
                .put("type", "peer_message")
                .put("message_id", "local-row-42")
                .put("content", "hello"),
            sourceId = "phone",
            targetId = "desktop"
        )

        assertTrue(runCatching { UUID.fromString(envelope.getString("message_id")) }.isSuccess)
        assertNotEquals("local-row-42", envelope.getString("message_id"))
    }

    @Test
    fun privateGlobalStateNeverEntersTheTransport() {
        assertTrue(
            SignalASITransportPrivacyPolicy.isLocalOnly(
                JSONObject().put("type", "text").put("conversation_id", "global-cognition:task")
            )
        )
        assertTrue(
            SignalASITransportPrivacyPolicy.isLocalOnly(
                JSONObject().put("type", "evolution_task_event")
            )
        )
        assertFalse(
            SignalASITransportPrivacyPolicy.isLocalOnly(
                JSONObject().put("type", "text").put("conversation_id", "user-session")
            )
        )
    }

    @Test
    fun mqttInboundWorkIsScopedPerSignalRelationship() {
        assertEquals(
            "server-a/client-a",
            mqttInboundRouteScope("signalasichat/v1/server-a/client-a/down")
        )
        assertEquals(
            "server-a/client-a",
            mqttInboundRouteScope("signalasichat/v1/server-a/client-a/control")
        )
        assertEquals(
            "server-b/client-b",
            mqttInboundRouteScope("signalasichat/v1/server-b/client-b/down")
        )
    }

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
    fun capabilityManifestIsRequestedOnlyUntilCurrentVersionIsCached() {
        val link = SignalASILinkProtocol.ServerLink(
            desktopId = "desktop-test",
            desktopName = "Test PC",
            desktopFingerprint = "a".repeat(64),
            signalName = "desktop-test",
            routes = SignalASILinkProtocol.Routes(
                SignalASILinkProtocol.newRouteId(),
                SignalASILinkProtocol.newRouteId()
            ),
            paired = true
        )

        assertTrue(SignalASILinkProtocol.needsCapabilityManifest(link))
        assertTrue(
            !SignalASILinkProtocol.needsCapabilityManifest(
                link.copy(capabilityManifestVersion = SignalASILinkProtocol.CAPABILITY_MANIFEST_VERSION)
            )
        )
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
    fun deliveryRetriesStopAfterTheBoundedBudget() {
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
        val pending = SignalASILinkDeliveryStore.pendingFromArray(
            values,
            now,
            maxAttempts = 6
        )
        assertEquals(emptyList<String>(), pending.map { it.messageId })
    }

    @Test
    fun finalDeliveryAttemptIsNotExhaustedWhileItsConfirmationWindowIsOpen() {
        val now = 1_000_000L
        val publishing = outboxMessage("final-attempt", "topic")
            .put("status", "publishing")
            .put("attempts", 6)
            .put("next_attempt_at", now + 2_000L)

        assertFalse(
            SignalASILinkDeliveryStore.isDeliveryExhausted(
                publishing,
                maxAttempts = 6,
                nowMillis = now
            )
        )
        assertTrue(
            SignalASILinkDeliveryStore.isDeliveryExhausted(
                publishing,
                maxAttempts = 6,
                nowMillis = now + 2_000L
            )
        )
    }

    @Test
    fun publishedFinalAttemptWaitsForEndToEndDeliveryAckBeforeExhaustion() {
        val now = 1_000_000L
        val published = outboxMessage("awaiting-delivery-ack", "topic")
            .put("status", "published")
            .put("attempts", 6)
            .put("next_attempt_at", now + 64_000L)

        assertFalse(
            SignalASILinkDeliveryStore.isDeliveryExhausted(
                published,
                maxAttempts = 6,
                nowMillis = now + 63_999L
            )
        )
        assertTrue(
            SignalASILinkDeliveryStore.isDeliveryExhausted(
                published,
                maxAttempts = 6,
                nowMillis = now + 64_000L
            )
        )
    }

    @Test
    fun pendingOutboxRoundRobinsIndependentRoutes() {
        val now = 1_000_000L
        val firstRoute = "signalasichat/v1/server-a/client-a/up"
        val secondRoute = "signalasichat/v1/server-b/client-b/up"
        val values = JSONArray()
            .put(outboxMessage("a-1", firstRoute).put("next_attempt_at", now))
            .put(outboxMessage("a-2", firstRoute).put("next_attempt_at", now))
            .put(outboxMessage("b-1", secondRoute).put("next_attempt_at", now))
            .put(outboxMessage("b-2", secondRoute).put("next_attempt_at", now))

        val pending = SignalASILinkDeliveryStore.pendingFromArray(values, now)

        assertEquals(listOf("a-1", "b-1", "a-2", "b-2"), pending.map { it.messageId })
    }

    @Test
    fun pendingOutboxCanHydrateAFileBackedEncryptedPayload() {
        val now = 1_000_000L
        val values = JSONArray().put(
            outboxMessage("file-backed", "topic")
                .apply { remove("wire_payload") }
                .put("wire_payload_file", "payload.wire")
                .put("next_attempt_at", now)
        )

        val pending = SignalASILinkDeliveryStore.pendingFromArray(
            values,
            now,
            wirePayload = { item ->
                if (item.optString("wire_payload_file") == "payload.wire") {
                    "encrypted-wire"
                } else {
                    ""
                }
            }
        )

        assertEquals("encrypted-wire", pending.single().wirePayload)
    }

    @Test
    fun outboxDoesNotPublishTaskWhileAttachmentTransferIsPending() {
        val now = 1_000_000L
        val values = JSONArray()
            .put(outboxMessage("manifest", "topic").put("next_attempt_at", now))
            .put(
                outboxMessage("task", "topic")
                    .put("next_attempt_at", now)
                    .put(
                        "blocked_by_attachment_transfers",
                        JSONArray().put("a".repeat(64))
                    )
            )

        val pending = SignalASILinkDeliveryStore.pendingFromArray(values, now)
        val retryDelay = SignalASILinkDeliveryStore.nextRetryDelayFromArray(values, now)

        assertEquals(listOf("manifest"), pending.map { it.messageId })
        assertEquals(0L, retryDelay)
    }

    @Test
    fun outboxDoesNotScheduleRetriesForOnlyAttachmentBlockedTasks() {
        val now = 1_000_000L
        val values = JSONArray().put(
            outboxMessage("task", "topic")
                .put("next_attempt_at", now)
                .put(
                    "blocked_by_attachment_transfers",
                    JSONArray().put("a".repeat(64))
                )
        )

        assertNull(SignalASILinkDeliveryStore.nextRetryDelayFromArray(values, now))
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
            SignalASILinkProtocol.SCOPE_DESKTOP_EXTERNAL_FILES
        )
        val incompleteExecutor = pairingAccess(
            SignalASILinkProtocol.ACCESS_DESKTOP_EXECUTOR,
            SignalASILinkProtocol.SCOPE_AGENT_CHAT,
            SignalASILinkProtocol.SCOPE_EXPLICIT_ATTACHMENTS,
            SignalASILinkProtocol.SCOPE_TASK_WORKSPACE,
            SignalASILinkProtocol.SCOPE_DESKTOP_EXECUTOR,
            SignalASILinkProtocol.SCOPE_DESKTOP_CONTROL
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
        assertNull(SignalASILinkProtocol.pairingAccess(incompleteExecutor))
        assertNull(SignalASILinkProtocol.pairingAccess(forgedRestricted))
    }

    @Test
    fun compactDesktopPairingQrExpandsToValidatedRestrictedPayload() {
        val now = System.currentTimeMillis()
        val compact = compactPairingQr(now, executor = false)

        val normalized = requireNotNull(SignalASILinkProtocol.normalizePairingQr(compact))

        assertTrue(SignalASILinkProtocol.validatePairingQr(normalized, now))
        assertEquals("ThinkPad T14", normalized.getString("desktop_name"))
        assertEquals("desktop_${"a".repeat(16)}", normalized.getString("desktop_id"))
        assertEquals(
            SignalASILinkProtocol.ACCESS_RESTRICTED,
            normalized.getJSONObject("pairing_access").getString("profile")
        )
        assertFalse(normalized.has("desktop_control_authorization"))
    }

    @Test
    fun compactDesktopPairingQrPreservesExecutorAuthorizationToken() {
        val now = System.currentTimeMillis()
        val compact = compactPairingQr(now, executor = true)

        val normalized = requireNotNull(SignalASILinkProtocol.normalizePairingQr(compact))

        assertTrue(SignalASILinkProtocol.validatePairingQr(normalized, now))
        assertTrue(
            SignalASILinkProtocol.pairingAccess(
                normalized.getJSONObject("pairing_access")
            )?.fullDesktopExecutor == true
        )
        assertEquals(
            "authorization-token",
            normalized.getJSONObject("desktop_control_authorization").getString("token")
        )
    }

    @Test
    fun rescanningTheSameDesktopOfferKeepsTheExistingClientRoute() {
        val now = System.currentTimeMillis()
        val qr = requireNotNull(
            SignalASILinkProtocol.normalizePairingQr(compactPairingQr(now, executor = true))
        )
        val existing = SignalASILinkProtocol.ServerLink(
            desktopId = qr.getString("desktop_id"),
            desktopName = qr.getString("desktop_name"),
            desktopFingerprint = qr.getString("identity_key_sha256"),
            signalName = qr.getString("desktop_id"),
            routes = SignalASILinkProtocol.Routes(
                qr.getString("server_route_id"),
                SignalASILinkProtocol.newRouteId()
            ),
            paired = false,
            accessProfile = SignalASILinkProtocol.ACCESS_DESKTOP_EXECUTOR,
            accessScopes = requireNotNull(
                SignalASILinkProtocol.pairingAccess(qr.getJSONObject("pairing_access"))
            ).scopes
        )

        assertFalse(SignalASILinkProtocol.shouldRotateClientRoute(existing, qr))
        assertFalse(SignalASILinkProtocol.shouldRotateClientRoute(existing.copy(paired = true), qr))
    }

    @Test
    fun rescanningRotatesOnlyWhenDesktopIdentityRouteOrAccessChanges() {
        val now = System.currentTimeMillis()
        val restrictedQr = requireNotNull(
            SignalASILinkProtocol.normalizePairingQr(compactPairingQr(now, executor = false))
        )
        val existing = SignalASILinkProtocol.ServerLink(
            desktopId = restrictedQr.getString("desktop_id"),
            desktopName = restrictedQr.getString("desktop_name"),
            desktopFingerprint = restrictedQr.getString("identity_key_sha256"),
            signalName = restrictedQr.getString("desktop_id"),
            routes = SignalASILinkProtocol.Routes(
                restrictedQr.getString("server_route_id"),
                SignalASILinkProtocol.newRouteId()
            ),
            paired = true,
            accessProfile = SignalASILinkProtocol.ACCESS_RESTRICTED,
            accessScopes = requireNotNull(
                SignalASILinkProtocol.pairingAccess(restrictedQr.getJSONObject("pairing_access"))
            ).scopes
        )
        val executorQr = requireNotNull(
            SignalASILinkProtocol.normalizePairingQr(
                compactPairingQr(now, executor = true)
                    .put("s", restrictedQr.getString("server_route_id"))
            )
        )
        val otherRouteQr = JSONObject(restrictedQr.toString())
            .put("server_route_id", SignalASILinkProtocol.newRouteId())

        assertTrue(SignalASILinkProtocol.shouldRotateClientRoute(existing, executorQr))
        assertTrue(SignalASILinkProtocol.shouldRotateClientRoute(existing, otherRouteQr))
    }

    @Test
    fun unrelatedQrIsNotNormalizedAsDesktopPairing() {
        assertNull(SignalASILinkProtocol.normalizePairingQr(JSONObject().put("t", "website")))
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

    private fun compactPairingQr(nowMs: Long, executor: Boolean): JSONObject = JSONObject()
        .put("t", "sv1")
        .put("n", "ThinkPad T14")
        .put("k", "identity-key")
        .put("h", "a".repeat(64))
        .put("c", nowMs / 1000L)
        .put("s", SignalASILinkProtocol.newRouteId())
        .put("x", "pairing-token-${"x".repeat(24)}")
        .put("e", "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        .put("a", if (executor) 1 else 0)
        .apply {
            if (executor) put("o", "authorization-token")
        }
}
