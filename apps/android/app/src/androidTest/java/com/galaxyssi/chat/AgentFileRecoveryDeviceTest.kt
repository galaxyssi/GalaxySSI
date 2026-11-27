package com.galaxyssi.chat

import android.content.Intent
import android.net.Uri
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

class AgentFileRecoveryDeviceTest {
    private val runner get() = InstrumentationRegistry.getInstrumentation()
    private val ctx get() = runner.targetContext

    @Test fun unreadableThirdOfFiveSelectsOnlyItsOriginalBytesAndAcceptsOnlyItsOwnChild() {
        assumeTrue(ctx.packageName.endsWith(".pairingqa"))
        val store = AgentTranscriptStore(ctx, "file-retry-test")
        val chat = store.createConversation("Synthetic file receipts").id
        val turn = UUID.randomUUID().toString()
        val root = File(ctx.cacheDir, turn).apply { mkdirs() }
        val files = (1..5).map { n ->
            val file = File(root, "file-$n.txt").apply { writeText("contents-$n") }
            AgentInputAttachment("item-$n", Uri.fromFile(file), "same-name.txt", "text/plain", file.length())
        }
        var activity: MainActivity? = null
        try {
            val blocks = files.map(AgentInputAttachment::richBlock)
            AgentTurnReceipt.begin(ctx, chat, turn, AgentModelSelection())
            assertEquals(5, AgentAttachmentWorkspaceStager.stage(ctx, chat, turn, files).size)
            assertTrue(store.append(AgentTranscriptRole.USER, "Original request must not be repeated", conversationId = chat,
                turnId = turn, richOutputJson = AgentRichContentCodec.encode(blocks)))
            val input = store.entriesForTurn(turn).single { it.role == AgentTranscriptRole.USER }
            val third = AgentFileKey(chat, turn, files[2].id)
            files.forEachIndexed { i, f ->
                val k = third.copy(item = f.id)
                AgentTurnReceipt.fileChange(ctx, k) {
                    val id = (i+1).toString().repeat(64)
                    AgentFileReceipt.fold(it, k, id, "uploading", "fixture-peer")
                    AgentFileReceipt.fold(it, k, id, "stored")
                }
            }
            assertTrue(AgentFileReceipt.report(ctx, chat, turn, 3, false))
            assertFalse(AgentFileReceipt.report(ctx, chat, turn, 6, true))
            assertFalse(AgentFileReceipt.report(ctx, "other", turn, 3, true))
            assertTrue(AgentAttachmentWorkspaceStager.restore(ctx, chat, turn, listOf(blocks[2].copy(id = "absent")), true).isEmpty())
            val a = runner.startActivitySync(Intent(ctx, HealthAtlasDiscussionActivity::class.java)
                .putExtra("galaxyssi_agent_conversation_id", chat).putExtra("galaxyssi_open_agent", true)
                .putExtra(AgentConversationWindows.WINDOW_KEY, "test:$chat").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
            activity = a
            lateinit var selected: AgentInputAttachment
            lateinit var views: Map<String, TextView>
            val latch = CountDownLatch(1)
            runner.runOnMainSync {
                val row = LinearLayout(a).apply { orientation = LinearLayout.VERTICAL }
                views = files.associate { it.id to TextView(a).also(row::addView) }
                a.bindAgentFileCaptions(row, input, blocks, views) { k, f -> assertEquals(third, k); selected = f; latch.countDown() }
                a.findViewById<ViewGroup>(android.R.id.content).addView(row)
            }
            var clicked = false
            repeat(150) {
                if (!clicked) {
                    runner.runOnMainSync {
                        val v = views.getValue(third.item)
                        if (v.text.contains(a.getString(R.string.agent_file_unreadable))) {
                            assertTrue(v.text.contains(a.getString(R.string.agent_file_stored)))
                            assertFalse(v.text.contains(a.getString(R.string.agent_file_failed)))
                            assertEquals(1, views.values.count { it.text.contains(a.getString(R.string.agent_file_unreadable)) })
                            clicked = v.performClick()
                        }
                    }
                    if (!clicked) Thread.sleep(100)
                }
            }
            assertTrue("Third file has its own reading action", clicked)
            assertTrue("Single-file submission boundary reached", latch.await(15, TimeUnit.SECONDS))
            assertEquals("contents-3", File(requireNotNull(selected.uri.path)).readText())
            val child = UUID.randomUUID().toString()
            AgentTurnReceipt.begin(ctx, chat, child, AgentModelSelection())
            AgentTurnReceipt.bindFileRead(ctx, third, child)
            store.append(AgentTranscriptRole.USER, "Read individually", conversationId = chat, turnId = child,
                richOutputJson = AgentRichContentCodec.encode(listOf(selected.richBlock())))
            assertFalse(AgentFileReceipt.report(ctx, chat, turn, 3, true))
            assertTrue(AgentFileReceipt.report(ctx, chat, child, 1, true))
            assertEquals("recognized", AgentTurnReceipt.fileInfo(ctx, third)!!.getString("reading"))
            assertFalse(AgentTurnReceipt.fileInfo(ctx, third.copy(item = files[3].id))!!.has("reading"))
        } finally {
            activity?.let { runner.runOnMainSync { it.finish() } }
            store.deleteConversation(chat)
            root.deleteRecursively()
        }
    }

    @Test fun legacyExhaustionHoldsOnlyThatFileAndReleasesOriginalOnce() {
        assumeTrue(ctx.packageName.endsWith(".pairingqa"))
        val s = GalaxySSILinkDeliveryStore
        val token = UUID.randomUUID().toString()
        val ids = (1..5).map { AgentNativeJsonCodec.sha256("$token:$it") }
        val source = System.currentTimeMillis()
        val packet = "$token-chunk"
        try {
            assertTrue(s.enqueue(ctx, token, "fixture/$token", "{}", blockedByAttachmentTransferIds = ids, clientSourceMessageId = source))
            s.enableFileRecovery(ctx, source, ids.toSet())
            ids.filterIndexed { i, _ -> i != 2 }.forEach { assertEquals(0, s.releaseAttachmentDependency(ctx, it)) }
            assertTrue(s.enqueue(ctx, packet, "fixture/$token", "{}", clientSourceMessageId = source, attachmentTransferId = ids[2]))
            s.markAttempt(ctx, packet)
            val now = source + 60_000
            assertTrue(s.discardExhausted(ctx, 1, 1, now).any { it.messageId == packet && it.awaitingFileRetry })
            assertTrue(s.hasAttachmentDependency(ctx, source, ids[2]))
            assertFalse(s.resumeHeldFile(ctx, source+1, ids[2], now))
            assertFalse(s.resumeHeldFile(ctx, source, ids[0], now))
            assertTrue(s.resumeHeldFile(ctx, source, ids[2], now))
            assertFalse(s.resumeHeldFile(ctx, source, ids[2], now))
            assertEquals(1, s.releaseAttachmentDependency(ctx, ids[2]))
            assertEquals(0, s.releaseAttachmentDependency(ctx, ids[2]))
        } finally { s.discard(ctx, token); s.discard(ctx, packet) }
    }
}
