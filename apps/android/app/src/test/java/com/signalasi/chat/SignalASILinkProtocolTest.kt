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
    fun mqttInboundWorkIsScopedByItsOpaqueMailbox() {
        val first = SignalASILinkProtocol.newLinkSecret()
        val second = SignalASILinkProtocol.newLinkSecret()
        assertEquals(first, mqttInboundRouteScope(first))
        assertEquals(second, mqttInboundRouteScope(second))
        assertNotEquals(mqttInboundRouteScope(first), mqttInboundRouteScope(second))
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
    fun relationshipTopicsAreOpaqueDirectionalAndRotating() {
        val routes = opaqueRoutes()
        val nextEpoch = SignalASILinkProtocol.relationshipTopic(
            routes.linkSecret,
            routes.localFingerprint,
            routes.remoteFingerprint,
            SignalASILinkProtocol.topicEpoch() + 1
        )
        assertTrue(SignalASILinkProtocol.validTopic(routes.up))
        assertTrue(SignalASILinkProtocol.validTopic(routes.down))
        assertFalse(routes.up.contains('/'))
        assertFalse(routes.up.contains("signalasi", ignoreCase = true))
        assertNotEquals(routes.up, routes.down)
        assertNotEquals(routes.up, nextEpoch)
        assertEquals(routes.up, routes.control)
        assertEquals(3, routes.receiveWindow.size)
    }

    @Test
    fun phonePeersDeriveTheSameSecretAndInverseMailboxes() {
        val pairingSecret = SignalASILinkProtocol.newLinkSecret()
        val firstFingerprint = "a".repeat(64)
        val secondFingerprint = "b".repeat(64)
        val firstSecret = SignalASILinkProtocol.deriveLinkSecret(
            pairingSecret,
            firstFingerprint,
            secondFingerprint
        )
        val secondSecret = SignalASILinkProtocol.deriveLinkSecret(
            pairingSecret,
            secondFingerprint,
            firstFingerprint
        )
        val first = SignalASILinkProtocol.Routes(
            SignalASILinkProtocol.newRouteId(),
            firstSecret,
            firstFingerprint,
            secondFingerprint
        )
        val second = SignalASILinkProtocol.Routes(
            SignalASILinkProtocol.newRouteId(),
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
        assertEquals(epochMillis + 5_000L, SignalASILinkProtocol.topicRefreshDelayMillis(0L))
        assertEquals(5_001L, SignalASILinkProtocol.topicRefreshDelayMillis(epochMillis - 1L))
    }

    @Test
    fun opaqueDerivationMatchesTheDesktopProtocolVector() {
        val secret = "a2tra2tra2tra2tra2tra2tra2tra2tra2tra2tra2s"
        assertEquals(
            "YJk0tvzG0ys3W5qOssXFIfTvTgiQ1bqcMUVMoBDv0dM",
            SignalASILinkProtocol.deriveLinkSecret(secret, "a".repeat(64), "b".repeat(64))
        )
        assertEquals(
            "-tqN7UsUs_L2UmiYlrUMgIwOOlR_fgcKTpOfPJWag-Y",
            SignalASILinkProtocol.relationshipTopic(secret, "a".repeat(64), "b".repeat(64), 42L)
        )
        assertEquals(
            "yNdJOwdEyFxLKGEu-BEA6O3kebQpimncPUA80pj0J-I",
            SignalASILinkProtocol.pairingTopic(secret)
        )
    }

    @Test
    fun opaqueWirePacketHidesContentPadsAndRejectsTampering() {
        val secret = SignalASILinkProtocol.newLinkSecret()
        val small = SignalASILinkProtocol.sealWirePacket("hello", secret)
        val larger = SignalASILinkProtocol.sealWirePacket("x".repeat(500), secret)
        assertEquals(small.length, larger.length)
        assertFalse(small.contains("hello"))
        assertEquals(
            "hello",
            SignalASILinkProtocol.openWirePacket(small.toByteArray(Charsets.US_ASCII), secret)
        )
        val tamperIndex = small.length / 2
        val tampered = small.replaceRange(
            tamperIndex,
            tamperIndex + 1,
            if (small[tamperIndex] == 'A') "B" else "A"
        )
        assertTrue(
            runCatching {
                SignalASILinkProtocol.openWirePacket(
                    tampered.toByteArray(Charsets.US_ASCII),
                    secret
                )
            }.isFailure
        )
    }

    @Test
    fun opaqueWirePacketUsesExpandedIntermediateBuckets() {
        val secret = SignalASILinkProtocol.newLinkSecret()
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
            val wire = SignalASILinkProtocol.sealWirePacket(payload, secret)
            val sealedBytes = 12 + bucketBytes + 16
            val expectedBase64UrlBytes = (sealedBytes * 8 + 5) / 6
            assertEquals(expectedBase64UrlBytes, wire.length)
            assertEquals(
                payload,
                SignalASILinkProtocol.openWirePacket(wire.toByteArray(Charsets.US_ASCII), secret)
            )
        }
    }

    @Test
    fun capabilityManifestIsRequestedOnlyUntilCurrentVersionIsCached() {
        val link = SignalASILinkProtocol.ServerLink(
            desktopId = "desktop-test",
            desktopName = "Test PC",
            desktopFingerprint = "a".repeat(64),
            signalName = "desktop-test",
            routes = opaqueRoutes(),
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
        val oldRoutes = opaqueRoutes()
        val otherRoutes = opaqueRoutes()
        val source = JSONArray()
            .put(outboxMessage("old-up", oldRoutes.up))
            .put(outboxMessage("old-control", oldRoutes.control))
            .put(outboxMessage("other-up", otherRoutes.up))

        val kept = SignalASILinkDeliveryStore.retainMessagesOutsideTopics(
            source,
            oldRoutes.receiveWindow + oldRoutes.up
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
            SignalASILinkDeliveryStore.isDeliveryExhausted(
                attachment,
                maxAttempts = 6,
                attachmentMaxAttempts = 9,
                nowMillis = now
            )
        )
        val pending = SignalASILinkDeliveryStore.pendingFromArray(
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
            SignalASILinkDeliveryStore.isDeliveryExhausted(
                attachment,
                maxAttempts = 6,
                attachmentMaxAttempts = 9,
                nowMillis = now
            )
        )
        assertTrue(
            SignalASILinkDeliveryStore.pendingFromArray(
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
            SignalASILinkDeliveryStore.recoverableAttachmentTransferId(
                JSONObject()
                    .put("type", "input_attachment_chunk")
                    .put("transfer_id", transferId)
            )
        )
        assertEquals(
            "",
            SignalASILinkDeliveryStore.recoverableAttachmentTransferId(
                JSONObject()
                    .put("type", "input_attachment_receipt")
                    .put("transfer_id", transferId)
            )
        )
    }

    @Test
    fun pendingOutboxRoundRobinsIndependentRoutes() {
        val now = 1_000_000L
        val firstRoute = SignalASILinkProtocol.newLinkSecret()
        val secondRoute = SignalASILinkProtocol.newLinkSecret()
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
    fun transportAckDoesNotAcceptAmbiguousLegacyFields() {
        val transportId = UUID.randomUUID().toString()
        val payload = JSONObject()
            .put("type", "delivery_ack")
            .put("source_message_id", transportId)
            .put("reply_to", transportId)

        assertEquals("", SignalASILinkDeliveryAckPolicy.transportMessageId(payload))
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
            routes = routesForPairingQr(qr),
            paired = false,
            accessProfile = SignalASILinkProtocol.ACCESS_DESKTOP_EXECUTOR,
            accessScopes = requireNotNull(
                SignalASILinkProtocol.pairingAccess(qr.getJSONObject("pairing_access"))
            ).scopes
        )

        assertFalse(SignalASILinkProtocol.shouldRotateClientRoute(existing, qr, TEST_LOCAL_FINGERPRINT))
        assertFalse(
            SignalASILinkProtocol.shouldRotateClientRoute(
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
            SignalASILinkProtocol.normalizePairingQr(compactPairingQr(now, executor = false))
        )
        val existing = SignalASILinkProtocol.ServerLink(
            desktopId = restrictedQr.getString("desktop_id"),
            desktopName = restrictedQr.getString("desktop_name"),
            desktopFingerprint = restrictedQr.getString("identity_key_sha256"),
            signalName = restrictedQr.getString("desktop_id"),
            routes = routesForPairingQr(restrictedQr),
            paired = true,
            accessProfile = SignalASILinkProtocol.ACCESS_RESTRICTED,
            accessScopes = requireNotNull(
                SignalASILinkProtocol.pairingAccess(restrictedQr.getJSONObject("pairing_access"))
            ).scopes
        )
        val executorQr = requireNotNull(
            SignalASILinkProtocol.normalizePairingQr(
                compactPairingQr(now, executor = true).put(
                    "e",
                    restrictedQr.getString("pairing_secret")
                )
            )
        )
        val otherRouteQr = JSONObject(restrictedQr.toString())
            .put("pairing_secret", SignalASILinkProtocol.newLinkSecret())
            .also { it.put("pairing_topic", SignalASILinkProtocol.pairingTopic(it.getString("pairing_secret"))) }

        assertTrue(
            SignalASILinkProtocol.shouldRotateClientRoute(existing, executorQr, TEST_LOCAL_FINGERPRINT)
        )
        assertTrue(
            SignalASILinkProtocol.shouldRotateClientRoute(existing, otherRouteQr, TEST_LOCAL_FINGERPRINT)
        )
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

    private fun opaqueRoutes(): SignalASILinkProtocol.Routes = SignalASILinkProtocol.Routes(
        clientRouteId = SignalASILinkProtocol.newRouteId(),
        linkSecret = SignalASILinkProtocol.newLinkSecret(),
        localFingerprint = "a".repeat(64),
        remoteFingerprint = "b".repeat(64)
    )

    private fun routesForPairingQr(qr: JSONObject): SignalASILinkProtocol.Routes {
        val localFingerprint = TEST_LOCAL_FINGERPRINT
        val remoteFingerprint = qr.getString("identity_key_sha256")
        return SignalASILinkProtocol.Routes(
            clientRouteId = SignalASILinkProtocol.newRouteId(),
            linkSecret = SignalASILinkProtocol.deriveLinkSecret(
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
