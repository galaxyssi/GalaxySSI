package com.galaxyssi.chat

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.net.Uri
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import kotlinx.coroutines.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Opt-in S26U probe. Only unique test conversations and generated fixture images are sent. */
@RunWith(AndroidJUnit4::class)
class AgentDeliveryLiveDeviceTest {
    @Test fun textAndImageReachTheConfiguredDesktop(): Unit = runBlocking {
        assumeTrue(InstrumentationRegistry.getArguments().getString("live_delivery") == "true")
        assertEquals("SM-S9480", Build.MODEL)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        withContext(Dispatchers.IO) { GalaxySSIMqttClient.connect(context) }
        withTimeout(30_000L) { while (!GalaxySSIMqttClient.isRequestReplyReady()) delay(100) }
        val contacts = withContext(Dispatchers.IO) { AppStore.contacts(context) }
        val contact = (0 until contacts.length()).map { contacts.getJSONObject(it) }.first { value ->
            val id = value.optString("id")
            val desktop = value.optString("desktop_id")
            desktop.isNotBlank() && !AppStore.isDesktopDeviceContact(context, id) &&
                AppStore.agentIdForContact(context, id) == "codex" &&
                GalaxySSILinkProtocol.serverLink(context, desktop)?.paired == true
        }.getString("id")
        for (hasImage in listOf(false, true)) {
            val id = "delivery-probe-${UUID.randomUUID()}"
            val source = System.currentTimeMillis()
            val turn = "$id-turn"
            val task = "$id-task"
            val marker = if (hasImage) "图片投递验证完成" else "文字投递验证完成"
            val prompt = if (hasImage) "请读取附件中的算式，只回复算式和：$marker。不修改文件。"
                else "请只回复：$marker。不调用工具，不修改文件。"
            val store = AgentTranscriptStore(context)
            val conversation = withContext(Dispatchers.IO) {
                store.createConversation(marker, privateMode = true).also {
                    store.append(AgentTranscriptRole.USER, prompt, conversationId = it.id, turnId = turn, taskId = task)
                }
            }
            val fixture = if (hasImage) File(context.cacheDir, "$id.png").also { file ->
                val bitmap = Bitmap.createBitmap(640, 320, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bitmap)
                canvas.drawColor(Color.WHITE)
                canvas.drawText("2 + 2 = 4", 60f, 180f, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.BLACK; textSize = 72f
                })
                file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                bitmap.recycle()
                AgentTurnAttachmentRegistry.put(turn, listOf(AgentInputAttachment(id,
                    Uri.fromFile(file), "delivery-test.png", "image/png", file.length())))
            } else null
            val final = CompletableDeferred<AgentConnectorResponse>()
            val listener = object : GalaxySSIMqttClient.Listener {
                override fun onMessage(payload: String) {
                    val value = runCatching { JSONObject(payload) }.getOrNull() ?: return
                    if (value.optLong("source_message_id") != source || value.optString("contact_id") != contact ||
                        value.optString("conversation_id") != conversation.id || value.optString("turn_id") != turn ||
                        value.optString("task_id") != task || value.optString("type") != "text") return
                    val response = AgentRemoteOutcomeCodec.decode(value, AgentRemoteOutcomeCodec.content(context, value)) ?: return
                    AgentConnectorResponseStore.append(context, response)
                    GalaxySSIMqttClient.completeIncomingDelivery(context, payload)
                    final.complete(response)
                }
            }
            GalaxySSIMqttClient.addListener(listener)
            try {
                withContext(Dispatchers.IO) {
                    AgentPendingDeliveryStore.put(context, AgentPendingDelivery(source, conversation.id, turn, task, contact))
                    assertTrue(GalaxySSIMqttClient.publishUserMessage(prompt, contactId = contact,
                        clientMessageId = source, conversationId = conversation.id, turnId = turn, taskId = task))
                }
                val response = withTimeout(180_000L) { final.await() }
                assertTrue(response.success)
                assertEquals("completed", response.taskStatus)
                assertTrue(response.content.contains(marker))
                if (hasImage) assertTrue(response.content.contains("4"))
                assertFalse(AgentTerminalDeliveryStore.isTerminal(context, source))
                println("LIVE_DELIVERY image=$hasImage source=$source task=$task generation=${response.executionGeneration} success=true")
                fixture?.delete()
            } finally {
                GalaxySSIMqttClient.removeListener(listener)
            }
        }
    }
}
