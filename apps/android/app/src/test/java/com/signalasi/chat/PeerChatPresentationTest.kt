package com.signalasi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PeerChatPresentationTest {
    @Test
    fun attachmentOnlyPeerMessageDoesNotExposeProtocolEnvelope() {
        val envelope = JSONObject()
            .put("type", "peer_message")
            .put("content", "")
            .put("attachments", JSONArray().put(JSONObject().put("name", "photo.png")))

        assertEquals("", PeerChatPresentation.incomingContent(envelope.toString(), envelope))
    }

    @Test
    fun peerMessageWithoutContentDoesNotExposeProtocolEnvelope() {
        val envelope = JSONObject()
            .put("type", "peer_message")
            .put("attachments", JSONArray().put(JSONObject().put("name", "photo.png")))

        assertEquals("", PeerChatPresentation.incomingContent(envelope.toString(), envelope))
    }

    @Test
    fun historicalPeerEnvelopeIsReducedToItsActualMessage() {
        val envelope = JSONObject()
            .put("type", "peer_message")
            .put("content", "Photo from Desktop")
            .put("client_route_id", "private-route")

        assertEquals("Photo from Desktop", PeerChatPresentation.storedContent(envelope.toString()))
    }

    @Test
    fun userAuthoredJsonTextIsPreserved() {
        val content = "{\"answer\":42}"

        assertEquals(content, PeerChatPresentation.storedContent(content))
    }

    @Test
    fun attachmentProgressIsNeverPresentedAsChatContent() {
        val progress = JSONObject()
            .put("type", PeerAttachmentTransferProgress.TYPE)
            .put("transfer_id", "a".repeat(64))
            .put("progress", 50)

        assertTrue(PeerChatPresentation.isInternalTransportEvent(progress))
        assertEquals("", PeerChatPresentation.incomingContent(progress.toString(), progress))
        assertEquals("", PeerChatPresentation.storedContent(progress.toString()))
    }

    @Test
    fun attachmentProtocolPacketsAreNeverPresentedAsChatContent() {
        listOf(
            "input_attachment_manifest",
            "input_attachment_chunk",
            "input_attachment_receipt",
            AgentAttachmentRecoveryRequest.REQUEST_TYPE,
            AgentAttachmentRecoveryRequest.RESULT_TYPE
        ).forEach { type ->
            val packet = JSONObject().put("type", type).put("data_b64", "private")
            assertTrue(PeerChatPresentation.isInternalTransportEvent(packet))
            assertEquals("", PeerChatPresentation.incomingContent(packet.toString(), packet))
            assertEquals("", PeerChatPresentation.storedContent(packet.toString()))
        }
    }

    @Test
    fun peerMessageContentRemainsVisible() {
        val message = JSONObject()
            .put("type", "peer_message")
            .put("content", "hello")

        assertFalse(PeerChatPresentation.isInternalTransportEvent(message))
        assertEquals("hello", PeerChatPresentation.incomingContent(message.toString(), message))
        assertEquals("hello", PeerChatPresentation.storedContent(message.toString()))
    }
}
