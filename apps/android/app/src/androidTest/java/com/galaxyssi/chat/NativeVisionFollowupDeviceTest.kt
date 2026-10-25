package com.galaxyssi.chat

import android.net.Uri
import android.os.SystemClock
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.json.JSONObject
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class NativeVisionFollowupDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun provenanceSurvivesPhoneWorkspaceRecoveryAndPayloadPreparation() {
        val conversation = "vision-provenance-${UUID.randomUUID()}"
        val turn = UUID.randomUUID().toString()
        val bitmap = android.graphics.Bitmap.createBitmap(32, 32, android.graphics.Bitmap.Config.ARGB_8888)
        val source = File(context.cacheDir, "$turn.png")
        try {
            source.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
            val attachment = AgentInputAttachment("source-image", Uri.fromFile(source), "source.png", "image/png",
                source.length(), historicalSourceTurnId = "original-turn")
            AgentTurnAttachmentRegistry.put(turn, listOf(attachment))
            assertTrue(AgentTurnAttachmentRegistry.current(turn).isEmpty())
            AgentAttachmentWorkspaceStager.stage(context, conversation, turn, listOf(attachment))
            val restored = AgentAttachmentWorkspaceStager.restore(context, conversation, turn, listOf(attachment.richBlock()))
            assertEquals("original-turn", restored.single().historicalSourceTurnId)
            val payload = CloudImagePayloadFactory.prepare(context, restored).single()
            try {
                assertEquals("original-turn", payload.historicalSourceTurnId)
                assertTrue(AgentDirectVisionPolicy.instruction(restored).contains(AgentVisualTurnPolicy.HISTORICAL_CONTEXT))
                assertFalse(AgentDirectVisionPolicy.instruction(restored).contains("inspect the image twice"))
            } finally { payload.bytes.fill(0) }
        } finally {
            bitmap.recycle()
            source.delete()
            AgentTurnAttachmentRegistry.remove(turn)
            File(context.filesDir, "agent-native-workspaces/${AgentWorkspaceScope.id(conversation)}").deleteRecursively()
        }
    }

    @Test fun streamedAndLegacyCloudRequestsSeparateHistoryForAllStyles() {
        for (style in listOf("openai", "anthropic", "gemini")) {
            MockWebServer().use { server ->
                server.start()
                val contact = JSONObject().put("id", "vision-followup-fixture-$style")
                    .put("cloud_provider", "custom").put("cloud_api_style", style)
                    .put("cloud_model", "fixture-model").put("cloud_api_key", "fixture-only")
                    .put("cloud_endpoint", server.url("/v1/chat/completions").toString())
                val turns = listOf(ChatMessage(0L, "Narrative translate", true, Contact("fixture", "Fixture", "")))
                val images = listOf(CloudImagePayload("prior.jpg", "image/jpeg", byteArrayOf(1, 2, 3),
                    historicalSourceTurnId = "prior-turn"))
                val prepared = CloudModelClient.prepareConversationStream(context, contact, turns, "fixture", images,
                    "Keep the phone execution contract.")
                checkCloudBody(style, prepared.body)
                val response = when (style) {
                    "anthropic" -> """{"content":[{"type":"text","text":"Answer."}],"stop_reason":"end_turn"}"""
                    "gemini" -> """{"candidates":[{"content":{"parts":[{"text":"Answer."}]},"finishReason":"STOP"}]}"""
                    else -> """{"choices":[{"message":{"role":"assistant","content":"Answer."},"finish_reason":"stop"}]}"""
                }
                server.enqueue(MockResponse().setHeader("Content-Type", "application/json").setBody(response))
                assertEquals("Answer.", CloudModelClient.legacyConversationResponse(context, contact, turns, images,
                    null, "Keep the phone execution contract."))
                checkCloudBody(style, JSONObject(requireNotNull(server.takeRequest(1, TimeUnit.SECONDS)).body.readUtf8()))
            }
        }
    }

    private fun checkCloudBody(style: String, body: JSONObject) {
        val messages = body.getJSONArray(if (style == "gemini") "contents" else "messages")
        val current = messages.getJSONObject(messages.length() - 1).toString()
        assertTrue(current.contains("Narrative translate"))
        assertFalse(current.contains("AQID"))
        val history = messages.getJSONObject(messages.length() - 2).toString()
        assertTrue(history.contains("prior-turn"))
        assertTrue(history.contains("AQID"))
        assertFalse(body.toString().contains("inspect the image twice"))
        assertTrue(body.toString().contains("Keep the phone execution contract."))
    }

    @Test fun liveImageThenTextFollowupsKeepTheirOwnIntent() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("live_vision_followup") == "true")
        val source = File(requireNotNull(args.getString("vision_image_path"))).canonicalFile
        require(source.path.startsWith(context.filesDir.canonicalPath + File.separator) && source.isFile)
        val report = JSONObject().put("turns", JSONArray())
        val scenario = ActivityScenario.launch(MainActivity::class.java)
        var conversation = ""
        try {
            await("hydration", 60_000) {
                var ready = false
                scenario.onActivity { ready = !it.initialAgentHydrationPending }
                ready
            }
            scenario.onActivity {
                it.createAgentConversation()
                conversation = it.agentTranscriptStore.activeConversation().id
            }
            val prompts = listOf("这张图片里的算式答案是多少？", "Narrative单词翻译", "再看看刚才图片里写的是什么算式？")
            val store = AgentTranscriptStore(context)
            prompts.forEachIndexed { index, prompt ->
                var turn = ""
                val start = SystemClock.elapsedRealtime()
                scenario.onActivity {
                    it.agentInputAttachments.clear()
                    if (index == 0) it.agentInputAttachments += AgentInputAttachment(UUID.randomUUID().toString(),
                        Uri.fromFile(source), "vision-followup.jpg", "image/jpeg", source.length())
                    it.renderAgentInputAttachments()
                    it.agentGoalInput.setText(prompt)
                    it.submitAgentGoal(onTurnCreated = { id -> turn = id })
                }
                val item = JSONObject().put("prompt", prompt).put("turn_id", turn)
                report.getJSONArray("turns").put(item)
                await("final reply $index", 180_000) {
                    val entries = store.page(conversation, pageSize = 30).entries
                    val answer = entries.lastOrNull { it.turnId == turn && it.role == AgentTranscriptRole.ASSISTANT &&
                        it.dedupeKey == AgentFinalResponseIdentity.dedupeKey(turn) } ?: return@await false
                    item.put("answer", answer.text).put("elapsed_ms", SystemClock.elapsedRealtime() - start)
                    assertFalse("Orientation preamble: ${answer.text}",
                        Regex("(图片.{0,8}(正向|阅读)|[（(]0[°度]|顺时针|逆时针)").containsMatchIn(answer.text))
                    if (index == 1) assertTrue(answer.text.contains("叙事"))
                    if (index == 2) assertTrue(answer.text.contains("1"))
                    if (index > 0) {
                        val user = entries.first { it.role == AgentTranscriptRole.USER && it.turnId == turn }
                        assertTrue(AgentRichContentCodec.decode(user.richOutputJson).isEmpty())
                    }
                    true
                }
            }
            report.put("passed", true)
        } catch (error: Throwable) {
            report.put("passed", false).put("error", error.toString())
            throw error
        } finally {
            report.put("conversation_id", conversation)
            File(context.cacheDir, "native-vision-followup-report.json").writeText(report.toString(2))
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
