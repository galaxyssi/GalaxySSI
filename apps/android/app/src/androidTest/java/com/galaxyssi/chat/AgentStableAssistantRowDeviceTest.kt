package com.galaxyssi.chat

import android.graphics.Bitmap
import android.os.SystemClock
import android.util.Base64
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.HorizontalScrollView
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
    @Test fun executionMetadataIsNotAppendedDuringStreamingOrAfterCompletion() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val initial = entry("Answer remains visible.")
                val execution = executionFixture()
                val previousEntries = activity.renderedAgentTranscriptSourceEntries
                activity.renderedAgentTranscriptSourceEntries = listOf(initial)
                activity.rememberAgentExecutionPresentation(initial.taskId, execution)
                try {
                    val row = AgentStableAssistantRow(activity, initial)
                    assertNoExecutionFooter(row)
                    activity.rememberAgentExecutionPresentation(initial.taskId,
                        execution.copy(phase = AgentPhase.COMPLETED, cancellable = false))
                    val final = initial.copy(id = "final-777")
                    activity.renderedAgentTranscriptSourceEntries = listOf(final)
                    assertTrue(row.bind(final))
                    assertNoExecutionFooter(row)
                    assertNotNull(descendants(row).firstOrNull { it.tag == "agent-reply-speech:stable-turn" })
                    assertEquals(AgentPhase.COMPLETED,
                        activity.agentExecutionPresentations[initial.taskId]?.phase)
                } finally {
                    activity.agentExecutionPresentations.remove(initial.taskId)
                    activity.renderedAgentTranscriptSourceEntries = previousEntries
                }
            }
        }
    }

    @Test fun nonStableReplyDoesNotAppendExecutionMetadata() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val reply = entry("Answer remains visible.").copy(sourceConversationId = "history-source")
                assertFalse(AgentStableAssistantRow.supports(reply))
                activity.rememberAgentExecutionPresentation(reply.taskId, executionFixture())
                try {
                    assertNoExecutionFooter(activity.agentAssistantTranscriptRow(reply))
                    assertNotNull(activity.agentExecutionPresentations[reply.taskId])
                } finally {
                    activity.agentExecutionPresentations.remove(reply.taskId)
                }
            }
        }
    }

    @Test fun otherDesktopAndCloudAndLocalModelsAlsoOmitExecutionFooter() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val fixtures = listOf(
                    executionFixture().copy(executorLabel = "Claude Code"),
                    executionFixture().copy(executorLabel = "Hermes"),
                    executionFixture().copy(executorLabel = "DeepSeek",
                        locationKind = AgentExecutionLocationKind.PHONE,
                        runtimeKind = AgentExecutionRuntimeKind.PHONE_CLOUD_API),
                    executionFixture().copy(executorLabel = "Cloud model",
                        locationKind = AgentExecutionLocationKind.CLOUD,
                        runtimeKind = AgentExecutionRuntimeKind.PHONE_CLOUD_API),
                    executionFixture().copy(executorLabel = "Local model",
                        locationKind = AgentExecutionLocationKind.PHONE,
                        runtimeKind = AgentExecutionRuntimeKind.PHONE_LOCAL_MODEL))
                val reply = entry("Answer remains visible.")
                fixtures.forEach { execution ->
                    activity.rememberAgentExecutionPresentation(reply.taskId, execution)
                    try {
                        listOf(reply, reply.copy(sourceConversationId = "history-source")).forEach { variant ->
                            val row = activity.agentAssistantTranscriptRow(variant)
                            assertNoExecutionFooter(row)
                            val text = descendants(row).filterIsInstance<TextView>().joinToString { it.text }
                            assertFalse("Unexpected footer for ${execution.executorLabel}",
                                text.contains(execution.executorLabel))
                        }
                        assertNotNull(activity.agentExecutionPresentations[reply.taskId])
                    } finally {
                        activity.agentExecutionPresentations.remove(reply.taskId)
                    }
                }
            }
        }
    }

    private fun executionFixture() = AgentExecutionPresentation(
        executorId = "codex", executorLabel = "Codex",
        locationKind = AgentExecutionLocationKind.DESKTOP,
        locationLabelHint = "desktop_footer_test", runtimeKind = AgentExecutionRuntimeKind.DESKTOP_AGENT,
        currentStep = "Working", phase = AgentPhase.EXECUTING,
        cancellable = true, startedAtMillis = System.currentTimeMillis())

    private fun assertNoExecutionFooter(view: View) {
        val text = descendants(view).filterIsInstance<TextView>().joinToString { it.text }
        assertTrue(text.contains("Answer remains visible."))
        assertFalse(text.contains("Codex"))
        assertFalse(text.contains("desktop_footer_test"))
    }

    @Test fun tableUpdatesPreserveTheContainerUnchangedCellsAndExpansion() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                fun body(count: Int) = "Introduction.\n\n| Name | Value |\n| --- | --- |\n" +
                    (1..count).joinToString("\n") { "| Result $it | $it |" }
                val initial = entry(body(14))
                val row = AgentStableAssistantRow(activity, initial)
                val scroll = descendants(row).filterIsInstance<HorizontalScrollView>().single()
                val firstCell = descendants(scroll).filterIsInstance<TextView>().first { it.text.toString() == "Result 1" }
                descendants(row).filterIsInstance<TextView>().first {
                    it.text.toString() == activity.getString(R.string.rich_output_more_rows, 2)
                }.performClick()
                repeat(30) { index ->
                    assertTrue(row.bind(initial.copy(text = body(15 + index))))
                    assertSame(scroll, descendants(row).filterIsInstance<HorizontalScrollView>().single())
                    assertSame(firstCell, descendants(scroll).filterIsInstance<TextView>().first { it.text.toString() == "Result 1" })
                    assertTrue(descendants(scroll).filterIsInstance<TextView>().any { it.text.toString() == "Result ${15 + index}" })
                }
                assertTrue(row.bind(initial.copy(id = "final-777", text = body(44))))
                assertSame(scroll, descendants(row).filterIsInstance<HorizontalScrollView>().single())
            }
        }
    }

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
