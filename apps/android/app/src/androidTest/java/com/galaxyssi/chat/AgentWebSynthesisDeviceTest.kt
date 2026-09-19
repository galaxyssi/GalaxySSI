package com.galaxyssi.chat

import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.commonmark.node.AbstractVisitor
import org.commonmark.node.Link
import org.commonmark.parser.Parser
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID

/** Opt-in real main-page submission. Never reuses or uploads an existing conversation. */
@RunWith(AndroidJUnit4::class)
class AgentWebSynthesisDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    @Test fun mainPageCompletesGroundedSynthesis() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("live_web") == "true")
        val query = requireNotNull(args.getString("live_web_query"))
        val context = instrumentation.targetContext
        val target = AppStoreAgentConnectorRegistry(context).availableTargets().firstOrNull {
            it.kind == AgentConnectorKind.MODEL && it.status == AgentConnectorStatus.AVAILABLE &&
                (it.title.contains("deepseek", true) || it.invocationProfile.normalizedModelId("").contains("deepseek", true))
        } ?: error("No configured DeepSeek provider; do not change credentials")
        val key = "synthesis-live-${UUID.randomUUID()}"
        val store = AgentTranscriptStore(context, key)
        val conversation = store.createConversation("Web synthesis ${BuildConfig.VERSION_NAME}", privateMode = true)
        store.append(AgentTranscriptRole.PROCESS, "Live synthesis verification", conversationId = conversation.id)
        AgentModelSelectionSettings.selectManual(context, conversation.id, target.id,
            target.invocationProfile.normalizedModelId(""), target.title, rememberAsDefault = false)
        val monitor = instrumentation.addMonitor(ConversationWindowActivity::class.java.name, null, false)
        try {
            context.startActivity(Intent(context, ConversationWindowActivity::class.java)
                .setData(Uri.parse("galaxyssi://conversation-window/$key"))
                .putExtra(AgentConversationWindows.WINDOW_KEY, key)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT or Intent.FLAG_ACTIVITY_NEW_TASK))
            val activity = instrumentation.waitForMonitorWithTimeout(monitor, 60_000) as? MainActivity
                ?: error("Test conversation window did not launch")
            await(60_000) {
                var ready = false
                instrumentation.runOnMainSync { ready = !activity.initialAgentHydrationPending &&
                    activity.conversationWindow.conversationId == conversation.id }
                ready
            }
            val started = SystemClock.elapsedRealtime()
            instrumentation.runOnMainSync {
                activity.agentGoalInput.setText(query)
                assertTrue(activity.agentSubmitButton.performClick())
            }
            val background = args.getString("background_research") == "true"
            if (background) {
                SystemClock.sleep(3_000)
                instrumentation.runOnMainSync { assertTrue(activity.moveTaskToBack(true)) }
            }
            await(180_000) {
                store.list(conversation.id).any { it.role == AgentTranscriptRole.ASSISTANT } &&
                    AgentTaskRuntime.supervisor(context).activeWorkspaces().none { it.conversationId == conversation.id }
            }
            val answer = store.list(conversation.id).filter { it.role == AgentTranscriptRole.ASSISTANT }
                .joinToString("\n") { it.text }
            val reports = File(context.getExternalFilesDir("reports"), "synthesis").apply { mkdirs() }
            val expected = args.getString("expected_answer_regex")?.takeIf(String::isNotBlank)
            val forbidden = args.getString("forbidden_answer_regex")?.takeIf(String::isNotBlank)
            val quality = ResearchQualityStandard.get(context).assess(answer, true)
            File(reports, "latest.json").writeText(JSONObject().put("query", query).put("answer", answer)
                .put("elapsed_ms", SystemClock.elapsedRealtime() - started).put("conversation_id", conversation.id)
                .put("background_research", background)
                .put("research_quality", quality)
                .put("content_oracle_configured", expected != null || forbidden != null)
                .put("window_key", key).put("version", BuildConfig.VERSION_NAME).toString(2))
            assertTrue("No final answer", answer.isNotBlank())
            assertFalse("Sources-only fallback", answer.contains(context.getString(R.string.cloud_web_fallback_sources)))
            assertFalse("Empty-evidence fallback", answer.contains(context.getString(R.string.cloud_web_fallback_empty)))
            var hasSource = false
            Parser.builder().build().parse(answer).accept(object : AbstractVisitor() {
                override fun visit(link: Link) {
                    if (link.destination.startsWith("https://") || link.destination.startsWith("http://")) hasSource = true
                    visitChildren(link)
                }
            })
            assertTrue("No source citation", hasSource)
            assertFalse("Unresolved internal citation", answer.contains("[[cite:"))
            assertNotEquals("Structural research quality risk: $quality", "needs_review", quality.getString("status"))
            expected?.let { assertTrue("Required content not found", Regex(it, RegexOption.IGNORE_CASE).containsMatchIn(answer)) }
            forbidden?.let { assertFalse("Unsupported inference found", Regex(it, RegexOption.IGNORE_CASE).containsMatchIn(answer)) }
            if (background) {
                context.startActivity(Intent(context, ConversationWindowActivity::class.java)
                    .setData(Uri.parse("galaxyssi://conversation-window/$key"))
                    .putExtra(AgentConversationWindows.WINDOW_KEY, key)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT or Intent.FLAG_ACTIVITY_NEW_TASK))
                SystemClock.sleep(1_000)
            }
            instrumentation.runOnMainSync {
                activity.agentTranscriptAutoFollow = false
                activity.agentOutputLayout.scrollToPositionWithOffset(0, 0)
            }
            val processed = activity.getString(R.string.agent_trace_processed, "", "").trim()
            await(10_000) {
                var finished = false
                instrumentation.runOnMainSync { finished = children(activity.agentOutputList).filterIsInstance<TextView>()
                    .any { it.isShown && it.text.toString().startsWith(processed) } }
                finished
            }
            instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
                File(reports, "latest.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                bitmap.recycle()
            }
        } finally { instrumentation.removeMonitor(monitor) }
    }

    private fun await(timeout: Long, condition: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + timeout
        while (!condition()) {
            check(SystemClock.elapsedRealtime() < deadline) { "Timed out waiting for synthesis/UI completion" }
            SystemClock.sleep(150)
        }
    }

    private fun children(view: View): List<View> = buildList {
        add(view)
        if (view is ViewGroup) for (index in 0 until view.childCount) addAll(children(view.getChildAt(index)))
    }
}
