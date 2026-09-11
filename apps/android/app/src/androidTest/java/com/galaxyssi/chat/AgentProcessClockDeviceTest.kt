package com.galaxyssi.chat

import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentProcessClockDeviceTest {
    @Test fun attachedClockStopsWithoutRebindingAndDoesNotRestartForTheNextTurn() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            lateinit var row: View
            lateinit var process: AgentTranscriptEntry
            var completedText = ""
            scenario.onActivity { activity ->
                process = AgentTranscriptEntry("clock-test", AgentTranscriptRole.PROCESS, "Working",
                    System.currentTimeMillis() - 5000, conversationId = "clock-test", turnId = "clock-turn", taskId = "clock-task")
                activity.renderedAgentTranscriptSourceEntries = listOf(process)
                val executing = AgentExecutionPresentation(
                    executorId = "test", executorLabel = "Test", locationKind = AgentExecutionLocationKind.CLOUD,
                    locationLabelHint = "Test", currentStep = "Working", phase = AgentPhase.EXECUTING,
                    cancellable = true, startedAtMillis = process.timestampMillis)
                activity.rememberAgentExecutionPresentation(process.taskId, executing)
                row = activity.agentProcessTranscriptRow(process)
                activity.findViewById<ViewGroup>(android.R.id.content).addView(row)
                assertTrue(status(row).text.toString().contains(activity.getString(R.string.agent_trace_processing, "", "").trim()))
                activity.renderedAgentTranscriptSourceEntries = listOf(process, process.copy(id = "final-clock",
                    role = AgentTranscriptRole.ASSISTANT, text = "Done", timestampMillis = process.timestampMillis + 4000))
                activity.rememberAgentExecutionPresentation(process.taskId, executing.copy(
                    phase = AgentPhase.COMPLETED, cancellable = false, completedAtMillis = process.timestampMillis + 4000))
                completedText = activity.getString(R.string.agent_trace_processed, activity.agentProcessedDuration(4000), "").trimEnd()
            }
            Thread.sleep(1300)
            scenario.onActivity { activity ->
                assertEquals(completedText, status(row).text.toString())
                activity.renderedAgentTranscriptSourceEntries = listOf(process.copy(turnId = "next-turn"))
            }
            Thread.sleep(1300)
            scenario.onActivity { activity ->
                assertEquals(completedText, status(row).text.toString())
                (row.parent as ViewGroup).removeView(row)
                activity.agentExecutionPresentations.remove(process.taskId)
            }
        }
    }

    private fun status(view: View): TextView = all(view).filterIsInstance<TextView>().first()
    private fun all(view: View): List<View> = listOf(view) + if (view is ViewGroup) {
        (0 until view.childCount).flatMap { all(view.getChildAt(it)) }
    } else emptyList()
}
