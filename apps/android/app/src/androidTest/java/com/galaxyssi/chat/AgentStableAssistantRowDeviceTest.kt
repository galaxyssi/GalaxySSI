package com.galaxyssi.chat

import android.graphics.Bitmap
import android.os.SystemClock
import android.util.Base64
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.galaxyssi.chat.ui.ParagraphSelectingTextView
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayOutputStream

@RunWith(AndroidJUnit4::class)
class AgentStableAssistantRowDeviceTest {
    @Test fun streamAndFinalKeepTheSameParagraphViewAndRefreshSpeech() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val first = entry("First paragraph.")
                val adapter = AgentTranscriptRecyclerAdapter(activity)
                adapter.replaceAll(listOf(first))
                val holder = adapter.onCreateViewHolder(activity.agentOutputList, 0)
                activity.renderedAgentTranscriptSourceEntries = listOf(first)
                adapter.onBindViewHolder(holder, 0)
                val row = holder.container.getChildAt(0)
                val paragraph = descendants(row).filterIsInstance<ParagraphSelectingTextView>().first()
                val second = first.copy(text = "First paragraph.\n\nSecond paragraph.")
                activity.renderedAgentTranscriptSourceEntries = listOf(second)
                adapter.replaceAll(listOf(second))
                adapter.onBindViewHolder(holder, 0)
                assertSame(row, holder.container.getChildAt(0))
                assertSame(paragraph, descendants(row).filterIsInstance<ParagraphSelectingTextView>().first())
                assertTrue(paragraph.text.contains("Second paragraph."))
                val final = second.copy(id = "final-777")
                activity.renderedAgentTranscriptSourceEntries = listOf(final)
                adapter.replaceAll(listOf(final))
                adapter.onBindViewHolder(holder, 0)
                assertSame(row, holder.container.getChildAt(0))
                assertSame(paragraph, descendants(row).filterIsInstance<ParagraphSelectingTextView>().first())
                assertNotNull(descendants(row).firstOrNull { it.tag == "agent-reply-speech:stable-turn" })
                assertNotNull(AgentReplySpeechPresentationPolicy.target(final))
                adapter.onViewRecycled(holder)
            }
        }
    }

    @Test fun imageDrawableSurvivesRepeatedPreviewAndFinalBinds() {
        val bitmap = Bitmap.createBitmap(80, 80, Bitmap.Config.ARGB_8888).apply { eraseColor(0xff168f78.toInt()) }
        val encoded = ByteArrayOutputStream().use { bytes ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, bytes)
            Base64.encodeToString(bytes.toByteArray(), Base64.NO_WRAP)
        }
        bitmap.recycle()
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            lateinit var row: AgentStableAssistantRow
            lateinit var image: ImageView
            lateinit var initial: AgentTranscriptEntry
            scenario.onActivity { activity ->
                initial = entry("Image preview").copy(richOutputJson = richImage(encoded, "First"))
                row = AgentStableAssistantRow(activity, initial)
                activity.findViewById<ViewGroup>(android.R.id.content).addView(row)
                image = descendants(row).filterIsInstance<ImageView>().first { it.isClickable }
            }
            val deadline = SystemClock.elapsedRealtime() + 5_000
            var loaded = false
            while (!loaded && SystemClock.elapsedRealtime() < deadline) {
                scenario.onActivity { loaded = image.drawable != null }
                if (!loaded) SystemClock.sleep(50)
            }
            assertTrue("Fixture image did not decode", loaded)
            scenario.onActivity {
                val drawable = image.drawable
                repeat(12) { index ->
                    assertTrue(row.bind(initial.copy(richOutputJson = richImage(encoded, "Append $index", index + 1))))
                    assertSame(image, descendants(row).filterIsInstance<ImageView>().first { it.isClickable })
                    assertSame(drawable, image.drawable)
                }
                assertTrue(row.bind(initial.copy(id = "final-777", richOutputJson = richImage(encoded, "Done", 14))))
                assertSame(drawable, image.drawable)
                assertFalse(row.bind(initial.copy(conversationId = "another-conversation")))
                (row.parent as ViewGroup).removeView(row)
            }
        }
    }

    @Test fun correctedContentRetractsOldBlocksInsteadOfKeepingStaleEvidence() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val initial = entry("First paragraph.\n\n| Name | Value |\n| --- | --- |\n| Old | 1 |")
                val row = AgentStableAssistantRow(activity, initial)
                assertTrue(row.bind(initial.copy(id = "final-777", text = "Corrected answer.")))
                val text = descendants(row).filterIsInstance<TextView>().joinToString { it.text }
                assertTrue(text.contains("Corrected answer."))
                assertFalse(text.contains("Old"))
            }
        }
    }

    @Test fun nestedTableActionsRebindToTheAcceptedReply() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val initial = entry("Introduction.\n\n| Name | Value |\n| --- | --- |\n" +
                    (1..14).joinToString("\n") { "| Result $it | $it |" })
                val preview = AgentRichContentView(activity, { it.tag = "preview-action" }, {}, { _, _ -> })
                val root = preview.create(initial)
                val cells = descendants(root).filterIsInstance<ParagraphSelectingTextView>()
                assertTrue(cells.size > 2)
                val accepted = AgentRichContentView(activity, { it.tag = "accepted-action" }, {}, { _, _ -> })
                assertTrue(accepted.update(root, initial.copy(id = "final-777")))
                assertTrue(cells.all { it.tag == "accepted-action" })
                descendants(root).filterIsInstance<TextView>().first {
                    it.text.toString() == activity.getString(R.string.rich_output_more_rows, 2)
                }.performClick()
                assertTrue(descendants(root).filterIsInstance<ParagraphSelectingTextView>()
                    .all { it.tag == "accepted-action" })
            }
        }
    }

    private fun entry(text: String) = AgentTranscriptEntry("agent-stream-preview-777", AgentTranscriptRole.ASSISTANT,
        text, System.currentTimeMillis(), dedupeKey = "assistant-final:stable", conversationId = "stable-conversation",
        turnId = "stable-turn", taskId = "stable-task")

    private fun richImage(encoded: String, text: String, paragraphs: Int = 1) = AgentRichContentCodec.encode(
        listOf(AgentRichBlock("image", AgentRichBlockType.IMAGE, title = "Image", dataB64 = encoded, mimeType = "image/png")) +
            (1..paragraphs).map { AgentRichBlock("text-$it", AgentRichBlockType.TEXT, text = "$text $it") })

    private fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup) {
        (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) }
    } else emptyList()
}
