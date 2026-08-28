package com.signalasi.chat

import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Test

class MessageAdapterVoiceBubbleTest {
    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()
    private val contact = Contact("peer-test", "Peer", "")
    private val attachment = PeerChatAttachment(
        name = "voice-test.opus",
        mimeType = "audio/ogg",
        sizeBytes = 4_096L,
        durationMillis = 3_000L
    )

    @Test
    fun incomingAndOutgoingVoiceBubblesUseTheSameVerticalPaddingAndHeight() {
        val outgoing = bindVoiceBubble(isMine = true)
        val incoming = bindVoiceBubble(isMine = false)

        assertEquals(outgoing.paddingTop, incoming.paddingTop)
        assertEquals(outgoing.paddingBottom, incoming.paddingBottom)

        val unspecified = View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        outgoing.measure(unspecified, unspecified)
        incoming.measure(unspecified, unspecified)
        assertEquals(outgoing.measuredHeight, incoming.measuredHeight)
    }

    private fun bindVoiceBubble(isMine: Boolean): TextView {
        val message = ChatMessage(
            id = if (isMine) 1L else 2L,
            content = "",
            isMine = isMine,
            contact = if (isMine) CONTACT_ME else contact,
            attachments = listOf(attachment)
        )
        val adapter = MessageAdapter(listOf(message))
        val holder = adapter.onCreateViewHolder(FrameLayout(context), 0)
        adapter.onBindViewHolder(holder, 0)
        return holder.attachments.getChildAt(0) as TextView
    }
}
