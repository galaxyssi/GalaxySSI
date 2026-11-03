package com.galaxyssi.chat

import android.net.Uri
import android.os.SystemClock
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Explicitly authorized real-provider acceptance through the actual composer and phone Agent Loop. */
@RunWith(AndroidJUnit4::class)
class NativeVisionPhoneLoopDeviceTest {
    @Test fun imageOnlyUsesNativeVisionAndCompletesInItsOwnConversation() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("live_vision_phone") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val source = File(requireNotNull(args.getString("vision_image_path"))).canonicalFile
        require(source.path.startsWith(context.filesDir.canonicalPath + File.separator) && source.isFile)
        val report = JSONObject().put("input_bytes", source.length())
        val destination = File(context.cacheDir, "native-vision-phone-report.json")
        val scenario = ActivityScenario.launch(MainActivity::class.java)
        val started = SystemClock.elapsedRealtime()
        var conversation = ""
        try {
            await("activity hydration", 60_000) {
                var ready = false
                scenario.onActivity { ready = !it.initialAgentHydrationPending }
                ready
            }
            scenario.onActivity {
                it.createAgentConversation()
                conversation = it.agentTranscriptStore.activeConversation().id
                it.agentInputAttachments.clear()
                it.agentInputAttachments += AgentInputAttachment(UUID.randomUUID().toString(),
                    Uri.fromFile(source), "vision-phone.jpg", "image/jpeg", source.length())
                it.renderAgentInputAttachments()
                it.agentGoalInput.setText("")
                it.submitAgentGoal()
            }
            report.put("conversation_id", conversation)
            val store = AgentTranscriptStore(context)
            await("actual final vision answer", 180_000) {
                val entries = store.page(conversation, pageSize = 30).entries
                val user = entries.lastOrNull { it.role == AgentTranscriptRole.USER } ?: return@await false
                val answer = entries.lastOrNull { it.role == AgentTranscriptRole.ASSISTANT && it.turnId == user.turnId &&
                    it.dedupeKey == AgentFinalResponseIdentity.dedupeKey(user.turnId) } ?: return@await false
                report.put("answer", answer.text).put("turn_id", user.turnId)
                assertEquals(conversation, store.conversationIdForTurn(user.turnId))
                assertTrue(answer.text.isNotBlank())
                args.getString("vision_expected_text")?.takeIf { it.isNotBlank() }?.let {
                    assertTrue("Unexpected visual answer: ${answer.text}", answer.text.contains(it))
                }
                true
            }
            report.put("passed", true)
        } catch (error: Throwable) {
            report.put("passed", false).put("error", error.toString())
            throw error
        } finally {
            report.put("elapsed_ms", SystemClock.elapsedRealtime() - started)
            destination.writeText(report.toString(2))
            scenario.close()
        }
    }

    private fun await(label: String, timeout: Long, condition: () -> Boolean) {
        val end = SystemClock.elapsedRealtime() + timeout
        while (SystemClock.elapsedRealtime() < end) {
            if (condition()) return
            Thread.sleep(250)
        }
        fail("Timed out waiting for $label")
    }
}
