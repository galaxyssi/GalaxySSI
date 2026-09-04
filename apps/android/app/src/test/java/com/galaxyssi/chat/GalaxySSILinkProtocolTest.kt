package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Test
import java.util.UUID

class GalaxySSILinkProtocolTest {

    @Test
    fun agentRequestUsesClientMessageIdForDeliveryFailureCorrelation() {
        val payload = JSONObject()
            .put("type", "text")
            .put("client_message_id", 1308L)
            .put("source_message_id", 99L)

        assertEquals(1308L, GalaxySSILinkDeliveryStore.outboundClientSourceMessageId(payload))
        assertEquals(
            99L,
            GalaxySSILinkDeliveryStore.outboundClientSourceMessageId(
                JSONObject().put("source_message_id", "99")
            )
        )
        assertEquals(0L, GalaxySSILinkDeliveryStore.outboundClientSourceMessageId(JSONObject()))
    }

    @Test
    fun reliableOutboxCanFindAConnectorHandoffByClientSource() {
        val values = JSONArray()
            .put(outboxMessage("first", "topic").put("client_source_message_id", 1308L))
            .put(outboxMessage("second", "topic").put("client_source_message_id", 1400L))

        assertTrue(GalaxySSILinkDeliveryStore.containsClientSourceMessageId(values, 1308L))
        assertTrue(GalaxySSILinkDeliveryStore.containsClientSourceMessageId(values, 1400L))
        assertFalse(GalaxySSILinkDeliveryStore.containsClientSourceMessageId(values, 9999L))
        assertFalse(GalaxySSILinkDeliveryStore.containsClientSourceMessageId(values, 0L))
    }

    @Test
    fun envelopeBoundaryReplacesNonUuidMessageIds() {
        val envelope = GalaxySSILinkProtocol.makeEnvelope(
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
            GalaxySSITransportPrivacyPolicy.isLocalOnly(
                JSONObject().put("type", "text").put("conversation_id", "global-cognition:task")
            )
        )
        assertTrue(
            GalaxySSITransportPrivacyPolicy.isLocalOnly(
                JSONObject().put("type", "evolution_task_event")
            )
        )
        assertFalse(
            GalaxySSITransportPrivacyPolicy.isLocalOnly(
                JSONObject().put("type", "text").put("conversation_id", "user-session")
            )
        )
    }

    @Test
    fun mqttInboundWorkIsScopedByItsOpaqueMailbox() {
        val first = GalaxySSILinkProtocol.newLinkSecret()
        val second = GalaxySSILinkProtocol.newLinkSecret()
        assertEquals(first, mqttInboundRouteScope(first))
        assertEquals(second, mqttInboundRouteScope(second))
        assertNotEquals(mqttInboundRouteScope(first), mqttInboundRouteScope(second))
    }

    @Test
    fun routeIdsAreOpaque128BitBase64UrlValues() {
        val first = GalaxySSILinkProtocol.newRouteId()
        val second = GalaxySSILinkProtocol.newRouteId()
        assertEquals(22, first.length)
        assertTrue(GalaxySSILinkProtocol.validRouteId(first))
        assertNotEquals(first, second)
    }

    @Test
    fun relationshipTopicsAreOpaqueDirectionalAndRotating() {
        val routes = opaqueRoutes()
        val nextEpoch = GalaxySSILinkProtocol.relationshipTopic(
            routes.linkSecret,
            routes.localFingerprint,
            routes.remoteFingerprint,
            GalaxySSILinkProtocol.topicEpoch() + 1
        )
        assertTrue(GalaxySSILinkProtocol.validTopic(routes.up))
        assertTrue(GalaxySSILinkProtocol.validTopic(routes.down))
        assertFalse(routes.up.contains('/'))
        assertFalse(routes.up.contains("galaxyssi", ignoreCase = true))
        assertNotEquals(routes.up, routes.down)
        assertNotEquals(routes.up, nextEpoch)
        assertEquals(routes.up, routes.control)
        assertEquals(3, routes.receiveWindow.size)
    }

    @Test
    fun phonePeersDeriveTheSameSecretAndInverseMailboxes() {
        val pairingSecret = GalaxySSILinkProtocol.newLinkSecret()
        val firstFingerprint = "a".repeat(64)
        val secondFingerprint = "b".repeat(64)
        val firstSecret = GalaxySSILinkProtocol.deriveLinkSecret(
            pairingSecret,
            firstFingerprint,
            secondFingerprint
        )
        val secondSecret = GalaxySSILinkProtocol.deriveLinkSecret(
            pairingSecret,
            secondFingerprint,
            firstFingerprint
        )
        val first = GalaxySSILinkProtocol.Routes(
            GalaxySSILinkProtocol.newRouteId(),
            firstSecret,
            firstFingerprint,
            secondFingerprint
        )
        val second = GalaxySSILinkProtocol.Routes(
            GalaxySSILinkProtocol.newRouteId(),
            secondSecret,
            secondFingerprint,
            firstFingerprint
        )

        assertEquals(firstSecret, secondSecret)
        assertEquals(first.up, second.down)
        assertEquals(first.down, second.up)
        assertTrue(first.up in second.receiveWindow)
        assertTrue(second.up in first.receiveWindow)
        assertNotEquals(first.clientRouteId, second.clientRouteId)
    }

    @Test
    fun mailboxSubscriptionRefreshesJustAfterTheNextEpochBoundary() {
        val epochMillis = 6L * 60L * 60L * 1_000L
        assertEquals(epochMillis + 5_000L, GalaxySSILinkProtocol.topicRefreshDelayMillis(0L))
        assertEquals(5_001L, GalaxySSILinkProtocol.topicRefreshDelayMillis(epochMillis - 1L))
    }

    @Test
    fun opaqueDerivationMatchesTheDesktopProtocolVector() {
        val secret = "a2tra2tra2tra2tra2tra2tra2tra2tra2tra2tra2s"
        assertEquals(
            "2JlyIihMatyn0I3C3BRSMG1M_R0l3LYAzhWN831_AW4",
            GalaxySSILinkProtocol.deriveLinkSecret(secret, "a".repeat(64), "b".repeat(64))
        )
        assertEquals(
            "Jgbier2h03OqPfemWtnnlnaZNTPmBhNQeC8YxKOLyPw",
            GalaxySSILinkProtocol.relationshipTopic(secret, "a".repeat(64), "b".repeat(64), 42L)
        )
        assertEquals(
            "sxBAJb6fPy2-bajfKVuWag2jPwsJ43mnXbF5BVDDVw8",
            GalaxySSILinkProtocol.pairingTopic(secret)
        )
    }

    @Test
    fun opaqueWirePacketHidesContentPadsAndRejectsTampering() {
        val secret = GalaxySSILinkProtocol.newLinkSecret()
        val small = GalaxySSILinkProtocol.sealWirePacket("hello", secret)
        val larger = GalaxySSILinkProtocol.sealWirePacket("x".repeat(500), secret)
        assertEquals(small.length, larger.length)
        assertFalse(small.contains("hello"))
        assertEquals(
            "hello",
            GalaxySSILinkProtocol.openWirePacket(small.toByteArray(Charsets.US_ASCII), secret)
        )
        val tamperIndex = small.length / 2
        val tampered = small.replaceRange(
            tamperIndex,
            tamperIndex + 1,
            if (small[tamperIndex] == 'A') "B" else "A"
        )
        assertTrue(
            runCatching {
                GalaxySSILinkProtocol.openWirePacket(
                    tampered.toByteArray(Charsets.US_ASCII),
                    secret
                )
            }.isFailure
        )
    }

    @Test
    fun opaqueWirePacketUsesExpandedIntermediateBuckets() {
        val secret = GalaxySSILinkProtocol.newLinkSecret()
        val cases = listOf(
            2 * 1024 to 16 * 1024,
            20 * 1024 to 64 * 1024,
            60 * 1024 to 64 * 1024,
            100 * 1024 to 128 * 1024,
            180 * 1024 to 256 * 1024,
            220 * 1024 to 256 * 1024,
            400 * 1024 to 512 * 1024
        )

        cases.forEach { (payloadBytes, bucketBytes) ->
            val payload = "x".repeat(payloadBytes)
            val wire = GalaxySSILinkProtocol.sealWirePacket(payload, secret)
            val sealedBytes = 12 + bucketBytes + 16
            val expectedBase64UrlBytes = (sealedBytes * 8 + 5) / 6
            assertEquals(expectedBase64UrlBytes, wire.length)
            assertEquals(
                payload,
                GalaxySSILinkProtocol.openWirePacket(wire.toByteArray(Charsets.US_ASCII), secret)
            )
        }
    }

    @Test
    fun capabilityManifestIsRequestedOnlyUntilCurrentVersionIsCached() {
        val link = GalaxySSILinkProtocol.ServerLink(
            desktopId = "desktop-test",
            desktopName = "Test PC",
            desktopFingerprint = "a".repeat(64),
            signalName = "desktop-test",
            routes = opaqueRoutes(),
            paired = true
        )

        assertTrue(GalaxySSILinkProtocol.needsCapabilityManifest(link))
        assertTrue(
            !GalaxySSILinkProtocol.needsCapabilityManifest(
                link.copy(capabilityManifestVersion = GalaxySSILinkProtocol.CAPABILITY_MANIFEST_VERSION)
            )
        )
    }

    @Test
    fun rotatingRelationshipDropsOnlyMessagesForItsOldTopics() {
        val oldRoutes = opaqueRoutes()
        val otherRoutes = opaqueRoutes()
        val source = JSONArray()
            .put(outboxMessage("old-up", oldRoutes.up))
            .put(outboxMessage("old-control", oldRoutes.control))
            .put(outboxMessage("other-up", otherRoutes.up))

        val kept = GalaxySSILinkDeliveryStore.retainMessagesOutsideTopics(
            source,
            oldRoutes.receiveWindow + oldRoutes.up
        )

        assertEquals(1, kept.length())
        assertEquals("other-up", kept.getJSONObject(0).getString("message_id"))
        assertEquals(3, source.length())
    }

    @Test
    fun deliveryRetriesStopAfterTheBoundedBudget() {
        assertEquals(2_000L, GalaxySSILinkRetryPolicy.delayMillis(1))
        assertEquals(256_000L, GalaxySSILinkRetryPolicy.delayMillis(8))
        assertEquals(300_000L, GalaxySSILinkRetryPolicy.delayMillis(9))
        assertEquals(300_000L, GalaxySSILinkRetryPolicy.delayMillis(10_000))

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
        val pending = GalaxySSILinkDeliveryStore.pendingFromArray(
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
            GalaxySSILinkDeliveryStore.isDeliveryExhausted(
                publishing,
                maxAttempts = 6,
                nowMillis = now
            )
        )
        assertTrue(
            GalaxySSILinkDeliveryStore.isDeliveryExhausted(
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
            GalaxySSILinkDeliveryStore.isDeliveryExhausted(
                published,
                maxAttempts = 6,
                nowMillis = now + 63_999L
            )
        )
        assertTrue(
            GalaxySSILinkDeliveryStore.isDeliveryExhausted(
                published,
                maxAttempts = 6,
                nowMillis = now + 64_000L
            )
        )
    }

    @Test
    fun attachmentPacketsUseASeparateButBoundedRetryBudget() {
        val now = 1_000_000L
        val transferId = "a".repeat(64)
        val attachment = outboxMessage("attachment-chunk", "topic")
            .put("attempts", 8)
            .put("next_attempt_at", now)
            .put("attachment_transfer_id", transferId)
            .put(
                "broker_ack_timeout_millis",
                MqttBrokerAckTimeoutPolicy.ATTACHMENT_TIMEOUT_MILLIS
            )

        assertFalse(
            GalaxySSILinkDeliveryStore.isDeliveryExhausted(
                attachment,
                maxAttempts = 6,
                attachmentMaxAttempts = 9,
                nowMillis = now
            )
        )
        val pending = GalaxySSILinkDeliveryStore.pendingFromArray(
            JSONArray().put(attachment),
            now,
            maxAttempts = 6,
            attachmentMaxAttempts = 9
        ).single()
        assertEquals(transferId, pending.attachmentTransferId)
        assertEquals(
            MqttBrokerAckTimeoutPolicy.ATTACHMENT_TIMEOUT_MILLIS,
            pending.brokerAckTimeoutMillis
        )

        attachment.put("attempts", 9)
        assertTrue(
            GalaxySSILinkDeliveryStore.isDeliveryExhausted(
                attachment,
                maxAttempts = 6,
                attachmentMaxAttempts = 9,
                nowMillis = now
            )
        )
        assertTrue(
            GalaxySSILinkDeliveryStore.pendingFromArray(
                JSONArray().put(attachment),
                now,
                maxAttempts = 6,
                attachmentMaxAttempts = 9
            ).isEmpty()
        )
    }

    @Test
    fun attachmentTransferIdentityOnlyAppliesToManifestAndChunks() {
        val transferId = "b".repeat(64)
        assertEquals(
            transferId,
            GalaxySSILinkDeliveryStore.recoverableAttachmentTransferId(
                JSONObject()
                    .put("type", "input_attachment_chunk")
                    .put("transfer_id", transferId)
            )
        )
        assertEquals(
            "",
            GalaxySSILinkDeliveryStore.recoverableAttachmentTransferId(
                JSONObject()
                    .put("type", "input_attachment_receipt")
                    .put("transfer_id", transferId)
            )
        )
    }

    @Test
    fun pendingOutboxRoundRobinsIndependentRoutes() {
        val now = 1_000_000L
        val firstRoute = GalaxySSILinkProtocol.newLinkSecret()
        val secondRoute = GalaxySSILinkProtocol.newLinkSecret()
        val values = JSONArray()
            .put(outboxMessage("a-1", firstRoute).put("next_attempt_at", now))
            .put(outboxMessage("a-2", firstRoute).put("next_attempt_at", now))
            .put(outboxMessage("b-1", secondRoute).put("next_attempt_at", now))
            .put(outboxMessage("b-2", secondRoute).put("next_attempt_at", now))

        val pending = GalaxySSILinkDeliveryStore.pendingFromArray(values, now)

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

        val pending = GalaxySSILinkDeliveryStore.pendingFromArray(
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

        val pending = GalaxySSILinkDeliveryStore.pendingFromArray(values, now)
        val retryDelay = GalaxySSILinkDeliveryStore.nextRetryDelayFromArray(values, now)

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

        assertNull(GalaxySSILinkDeliveryStore.nextRetryDelayFromArray(values, now))
    }

    @Test
    fun outboxSchedulerUsesEarliestDueMessageInsteadOfFixedPolling() {
        val now = 1_000_000L
        val values = JSONArray()
            .put(outboxMessage("later", "topic").put("next_attempt_at", now + 30_000L))
            .put(outboxMessage("next", "topic").put("next_attempt_at", now + 750L))
            .put(outboxMessage("past-due", "topic").put("next_attempt_at", now - 1L))

        assertEquals(0L, GalaxySSILinkDeliveryStore.nextRetryDelayFromArray(values, now))
        values.remove(2)
        assertEquals(750L, GalaxySSILinkDeliveryStore.nextRetryDelayFromArray(values, now))
        assertNull(GalaxySSILinkDeliveryStore.nextRetryDelayFromArray(JSONArray(), now))
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

        val constrained = GalaxySSILinkDeliveryStore.pendingFromArray(
            values,
            now + 1_000L,
            allowValidatedNetworkMessages = false
        )
        val recovered = GalaxySSILinkDeliveryStore.pendingFromArray(
            values,
            now + 1_000L,
            allowValidatedNetworkMessages = true
        )

        assertEquals(listOf("text"), constrained.map { it.messageId })
        assertEquals(listOf("media", "text"), recovered.map { it.messageId })
        assertEquals(
            750L,
            GalaxySSILinkDeliveryStore.nextRetryDelayFromArray(
                values,
                now,
                allowValidatedNetworkMessages = false
            )
        )
        assertEquals(
            0L,
            GalaxySSILinkDeliveryStore.nextRetryDelayFromArray(
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

        assertEquals(transportId, GalaxySSILinkDeliveryAckPolicy.transportMessageId(payload))
        assertEquals("521", GalaxySSILinkDeliveryAckPolicy.clientSourceMessageId(payload))
    }

    @Test
    fun deliveryAckNeverTreatsLogicalMessageNumberAsTransportId() {
        val payload = JSONObject()
            .put("type", "delivery_ack")
            .put("source_message_id", "521")

        assertEquals("", GalaxySSILinkDeliveryAckPolicy.transportMessageId(payload))
        assertEquals("521", GalaxySSILinkDeliveryAckPolicy.clientSourceMessageId(payload))
    }

    @Test
    fun transportAckDoesNotAcceptAmbiguousLegacyFields() {
        val transportId = UUID.randomUUID().toString()
        val payload = JSONObject()
            .put("type", "delivery_ack")
            .put("source_message_id", transportId)
            .put("reply_to", transportId)

        assertEquals("", GalaxySSILinkDeliveryAckPolicy.transportMessageId(payload))
        assertEquals("", GalaxySSILinkDeliveryAckPolicy.clientSourceMessageId(payload))
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
            GalaxySSILinkCiphertextReplayPolicy.digest(first),
            GalaxySSILinkCiphertextReplayPolicy.digest(reordered)
        )
        assertNotEquals(
            GalaxySSILinkCiphertextReplayPolicy.digest(first),
            GalaxySSILinkCiphertextReplayPolicy.digest(changed)
        )
    }

    @Test
    fun pairingAccessProfilesFailClosedWhenExecutorScopesAreIncomplete() {
        val restricted = pairingAccess(
            GalaxySSILinkProtocol.ACCESS_RESTRICTED,
            GalaxySSILinkProtocol.SCOPE_AGENT_CHAT,
            GalaxySSILinkProtocol.SCOPE_EXPLICIT_ATTACHMENTS,
            GalaxySSILinkProtocol.SCOPE_TASK_WORKSPACE
        )
        val executor = pairingAccess(
            GalaxySSILinkProtocol.ACCESS_DESKTOP_EXECUTOR,
            GalaxySSILinkProtocol.SCOPE_AGENT_CHAT,
            GalaxySSILinkProtocol.SCOPE_EXPLICIT_ATTACHMENTS,
            GalaxySSILinkProtocol.SCOPE_TASK_WORKSPACE,
            GalaxySSILinkProtocol.SCOPE_DESKTOP_EXECUTOR,
            GalaxySSILinkProtocol.SCOPE_DESKTOP_CONTROL,
            GalaxySSILinkProtocol.SCOPE_DESKTOP_NATIVE_TOOLS,
            GalaxySSILinkProtocol.SCOPE_DESKTOP_EXTERNAL_FILES
        )
        val incompleteExecutor = pairingAccess(
            GalaxySSILinkProtocol.ACCESS_DESKTOP_EXECUTOR,
            GalaxySSILinkProtocol.SCOPE_AGENT_CHAT,
            GalaxySSILinkProtocol.SCOPE_EXPLICIT_ATTACHMENTS,
            GalaxySSILinkProtocol.SCOPE_TASK_WORKSPACE,
            GalaxySSILinkProtocol.SCOPE_DESKTOP_EXECUTOR,
            GalaxySSILinkProtocol.SCOPE_DESKTOP_CONTROL
        )
        val forgedRestricted = pairingAccess(
            GalaxySSILinkProtocol.ACCESS_RESTRICTED,
            GalaxySSILinkProtocol.SCOPE_AGENT_CHAT,
            GalaxySSILinkProtocol.SCOPE_EXPLICIT_ATTACHMENTS,
            GalaxySSILinkProtocol.SCOPE_TASK_WORKSPACE,
            GalaxySSILinkProtocol.SCOPE_DESKTOP_EXECUTOR
        )

        assertEquals(
            GalaxySSILinkProtocol.ACCESS_RESTRICTED,
            GalaxySSILinkProtocol.pairingAccess(restricted)?.profile
        )
        assertTrue(GalaxySSILinkProtocol.pairingAccess(executor)?.fullDesktopExecutor == true)
        assertNull(GalaxySSILinkProtocol.pairingAccess(incompleteExecutor))
        assertNull(GalaxySSILinkProtocol.pairingAccess(forgedRestricted))
    }

    @Test
    fun compactDesktopPairingQrExpandsToValidatedRestrictedPayload() {
        val now = System.currentTimeMillis()
        val compact = compactPairingQr(now, executor = false)

        val normalized = requireNotNull(GalaxySSILinkProtocol.normalizePairingQr(compact))

        assertTrue(GalaxySSILinkProtocol.validatePairingQr(normalized, now))
        assertEquals("ThinkPad T14", normalized.getString("desktop_name"))
        assertEquals("desktop_${"a".repeat(16)}", normalized.getString("desktop_id"))
        assertEquals(
            GalaxySSILinkProtocol.ACCESS_RESTRICTED,
            normalized.getJSONObject("pairing_access").getString("profile")
        )
        assertFalse(normalized.has("desktop_control_authorization"))
    }

    @Test
    fun compactDesktopPairingQrPreservesExecutorAuthorizationToken() {
        val now = System.currentTimeMillis()
        val compact = compactPairingQr(now, executor = true)

        val normalized = requireNotNull(GalaxySSILinkProtocol.normalizePairingQr(compact))

        assertTrue(GalaxySSILinkProtocol.validatePairingQr(normalized, now))
        assertTrue(
            GalaxySSILinkProtocol.pairingAccess(
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
            GalaxySSILinkProtocol.normalizePairingQr(compactPairingQr(now, executor = true))
        )
        val existing = GalaxySSILinkProtocol.ServerLink(
            desktopId = qr.getString("desktop_id"),
            desktopName = qr.getString("desktop_name"),
            desktopFingerprint = qr.getString("identity_key_sha256"),
            signalName = qr.getString("desktop_id"),
            routes = routesForPairingQr(qr),
            paired = false,
            accessProfile = GalaxySSILinkProtocol.ACCESS_DESKTOP_EXECUTOR,
            accessScopes = requireNotNull(
                GalaxySSILinkProtocol.pairingAccess(qr.getJSONObject("pairing_access"))
            ).scopes
        )

        assertFalse(GalaxySSILinkProtocol.shouldRotateClientRoute(existing, qr, TEST_LOCAL_FINGERPRINT))
        assertFalse(
            GalaxySSILinkProtocol.shouldRotateClientRoute(
                existing.copy(paired = true),
                qr,
                TEST_LOCAL_FINGERPRINT
            )
        )
    }

    @Test
    fun rescanningRotatesOnlyWhenDesktopIdentityRouteOrAccessChanges() {
        val now = System.currentTimeMillis()
        val restrictedQr = requireNotNull(
            GalaxySSILinkProtocol.normalizePairingQr(compactPairingQr(now, executor = false))
        )
        val existing = GalaxySSILinkProtocol.ServerLink(
            desktopId = restrictedQr.getString("desktop_id"),
            desktopName = restrictedQr.getString("desktop_name"),
            desktopFingerprint = restrictedQr.getString("identity_key_sha256"),
            signalName = restrictedQr.getString("desktop_id"),
            routes = routesForPairingQr(restrictedQr),
            paired = true,
            accessProfile = GalaxySSILinkProtocol.ACCESS_RESTRICTED,
            accessScopes = requireNotNull(
                GalaxySSILinkProtocol.pairingAccess(restrictedQr.getJSONObject("pairing_access"))
            ).scopes
        )
        val executorQr = requireNotNull(
            GalaxySSILinkProtocol.normalizePairingQr(
                compactPairingQr(now, executor = true).put(
                    "e",
                    restrictedQr.getString("pairing_secret")
                )
            )
        )
        val otherRouteQr = JSONObject(restrictedQr.toString())
            .put("pairing_secret", GalaxySSILinkProtocol.newLinkSecret())
            .also { it.put("pairing_topic", GalaxySSILinkProtocol.pairingTopic(it.getString("pairing_secret"))) }

        assertTrue(
            GalaxySSILinkProtocol.shouldRotateClientRoute(existing, executorQr, TEST_LOCAL_FINGERPRINT)
        )
        assertTrue(
            GalaxySSILinkProtocol.shouldRotateClientRoute(existing, otherRouteQr, TEST_LOCAL_FINGERPRINT)
        )
    }

    @Test
    fun unrelatedQrIsNotNormalizedAsDesktopPairing() {
        assertNull(GalaxySSILinkProtocol.normalizePairingQr(JSONObject().put("t", "website")))
    }

    private fun outboxMessage(id: String, topic: String): JSONObject = JSONObject()
        .put("message_id", id)
        .put("topic", topic)
        .put("wire_payload", "{}")

    private fun pairingAccess(profile: String, vararg scopes: String): JSONObject = JSONObject()
        .put("contract_version", GalaxySSILinkProtocol.ACCESS_CONTRACT)
        .put("version", 1)
        .put("profile", profile)
        .put("scopes", JSONArray(scopes.toList()))

    private fun compactPairingQr(nowMs: Long, executor: Boolean): JSONObject = JSONObject()
        .put("t", "o2")
        .put("n", "ThinkPad T14")
        .put("k", "identity-key")
        .put("h", "a".repeat(64))
        .put("c", nowMs / 1000L)
        .put("x", "pairing-token-${"x".repeat(24)}")
        .put("e", "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        .put("a", if (executor) 1 else 0)
        .apply {
            if (executor) put("o", "authorization-token")
        }

    private fun opaqueRoutes(): GalaxySSILinkProtocol.Routes = GalaxySSILinkProtocol.Routes(
        clientRouteId = GalaxySSILinkProtocol.newRouteId(),
        linkSecret = GalaxySSILinkProtocol.newLinkSecret(),
        localFingerprint = "a".repeat(64),
        remoteFingerprint = "b".repeat(64)
    )

    private fun routesForPairingQr(qr: JSONObject): GalaxySSILinkProtocol.Routes {
        val localFingerprint = TEST_LOCAL_FINGERPRINT
        val remoteFingerprint = qr.getString("identity_key_sha256")
        return GalaxySSILinkProtocol.Routes(
            clientRouteId = GalaxySSILinkProtocol.newRouteId(),
            linkSecret = GalaxySSILinkProtocol.deriveLinkSecret(
                qr.getString("pairing_secret"),
                localFingerprint,
                remoteFingerprint
            ),
            localFingerprint = localFingerprint,
            remoteFingerprint = remoteFingerprint
        )
    }

    companion object {
        private const val TEST_LOCAL_FINGERPRINT =
            "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    }
}
