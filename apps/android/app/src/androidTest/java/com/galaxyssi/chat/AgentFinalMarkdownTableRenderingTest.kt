package com.galaxyssi.chat

import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.widget.HorizontalScrollView
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentFinalMarkdownTableRenderingTest {
    @Test fun streamingFinalAndReloadRenderTheSameTable() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val activity = instrumentation.startActivitySync(
            Intent(instrumentation.targetContext, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        ) as MainActivity
        val text = "Monthly fruit plan\n\n| Month | Fruit |\n| --- | --- |\n| January | Orange |\n| February | Pear |\n\nEnd of plan"
        val raw = AgentRichContentCodec.encode(listOf(
            AgentRichBlock("final-text", AgentRichBlockType.TEXT, text = text)
        ))
        val states = listOf("", raw, AgentRichContentCodec.normalize(raw))
        val snapshots = mutableListOf<List<String>>()
        try {
            states.forEachIndexed { index, rich ->
                lateinit var root: View
                instrumentation.runOnMainSync {
                    root = AgentRichContentView(activity, {}, {}, { _, _ -> }).create(
                        AgentTranscriptEntry(
                            id = if (index == 0) "agent-stream-table" else "final-table",
                            role = AgentTranscriptRole.ASSISTANT, text = text,
                            timestampMillis = 1L, richOutputJson = rich
                        )
                    )
                    activity.setContentView(root)
                }
                instrumentation.waitForIdleSync()
                instrumentation.runOnMainSync {
                    val views = descendants(root)
                    val table = views.filterIsInstance<HorizontalScrollView>().single()
                    assertTrue("Table must have visible dimensions", table.width > 0 && table.height > 0)
                    snapshots += views.filterIsInstance<TextView>().map { it.text.toString() }
                    assertTrue(snapshots.last().containsAll(listOf("Month", "Fruit", "January", "Orange")))
                    assertTrue(snapshots.last().none { it.contains("| --- |") })
                }
            }
            assertEquals(snapshots[0], snapshots[1])
            assertEquals(snapshots[1], snapshots[2])
        } finally {
            instrumentation.runOnMainSync { activity.finish() }
        }
    }

    private fun descendants(view: View): List<View> = buildList {
        add(view)
        if (view is ViewGroup) for (index in 0 until view.childCount) {
            addAll(descendants(view.getChildAt(index)))
        }
    }
}
