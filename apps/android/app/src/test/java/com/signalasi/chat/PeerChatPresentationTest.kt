package com.signalasi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
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
}
