package com.galaxyssi.chat

import android.graphics.Bitmap
import android.database.sqlite.SQLiteDatabase
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.net.Uri
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.atomic.AtomicLong
import com.galaxyssi.chat.blob.BlobOutgoingJournal
import kotlinx.coroutines.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Opt-in device probe. Only unique test conversations and generated fixture images are sent. */
@RunWith(AndroidJUnit4::class)
class AgentDeliveryLiveDeviceTest {
    @Test fun generatedTextDiagnostics() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("live_delivery") == "true")
        assertEquals(args.getString("live_delivery_model"), Build.MODEL)
        val sources = args.getString("live_delivery_sources", "").split(',').mapNotNull(String::toLongOrNull)
        require(sources.isNotEmpty() && sources.size <= 20)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        LinkTransportReceiptJournal(context).use { journal ->
            journal.readableDatabase.rawQuery(
                "SELECT COUNT(*),MIN(next_at),SUM(CASE WHEN attempt='' THEN 1 ELSE 0 END) FROM receipts", null
            ).use { rows ->
                if (rows.moveToFirst()) println("LIVE_RECEIPTS total=${rows.getLong(0)} " +
                    "oldest_due_ms=${rows.getLong(1) - System.currentTimeMillis()} unclaimed=${rows.getLong(2)}")
            }
        }
        GalaxySSILinkOutboxDatabase(context).use { outbox ->
            for (source in sources) {
                val pending = AgentPendingDeliveryStore.find(context, source)
                if (pending == null) {
                    println("LIVE_TEXT source=$source pending=absent")
                    continue
                }
                require(pending.taskId.startsWith("delivery-probe-"))
                println("LIVE_TEXT source=$source task=${pending.taskId} terminal=" +
                    AgentTerminalDeliveryStore.isTerminal(context, source))
                outbox.readableDatabase.rawQuery(
                    "SELECT message_id,status,attempts,blocked_dependency_count,next_attempt_at " +
                        "FROM outbox_messages WHERE client_source_message_id=?", arrayOf(source.toString())
                ).use { rows ->
                    println("LIVE_TEXT source=$source outbox_rows=${rows.count}")
                    while (rows.moveToNext()) {
                        println("LIVE_TEXT source=$source message=${rows.getString(0)} status=${rows.getString(1)} " +
                            "attempts=${rows.getInt(2)} blocked=${rows.getInt(3)} " +
                            "due_ms=${rows.getLong(4) - System.currentTimeMillis()}")
                    }
                }
            }
        }
    }

    @Test fun generatedAttachmentDiagnostics() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("live_delivery") == "true")
        val model = InstrumentationRegistry.getArguments().getString("live_delivery_model")
        assertFalse("An explicit target model is required", model.isNullOrBlank())
        assertEquals(model, Build.MODEL)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        GalaxySSILinkOutboxDatabase(context).use { outbox ->
            AgentOutboundAttachmentTransferStore.pending(context).filter {
                it.scope.taskId.startsWith("delivery-probe-")
            }.forEach { transfer ->
                println("LIVE_TRANSFER task=${transfer.scope.taskId} id=${transfer.transferId.take(12)} " +
                    "bytes=${transfer.sizeBytes} dependency=" +
                    GalaxySSILinkDeliveryStore.hasAttachmentDependency(context, transfer.transferId))
                outbox.readableDatabase.rawQuery(
                    "SELECT status,attempts,blocked_dependency_count,attachment_transfer_id,next_attempt_at " +
                        "FROM outbox_messages WHERE attachment_transfer_id=? OR client_source_message_id=?",
                    arrayOf(transfer.transferId, transfer.scope.clientMessageId.toString())
                ).use { rows ->
                    while (rows.moveToNext()) {
                        println("LIVE_OUTBOX task=${transfer.scope.taskId} status=${rows.getString(0)} " +
                            "attempts=${rows.getInt(1)} blocked=${rows.getInt(2)} " +
                            "attachment=${rows.getString(3).isNotEmpty()} " +
                            "due_ms=${rows.getLong(4) - System.currentTimeMillis()}")
                    }
                }
            }
        }
        val file = File(context.noBackupFilesDir, "blob-outgoing-v1/jobs.sqlite3")
        if (!file.exists()) {
            println("LIVE_BLOB journal=absent")
            return
        }
        BlobOutgoingJournal(file).use { journal ->
            SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READONLY).use { database ->
                database.rawQuery("SELECT id,phase,state,attempts,error,ready FROM jobs", null).use { rows ->
                    while (rows.moveToNext()) {
                        val manifest = journal.body(rows.getString(0))?.optJSONObject("manifest") ?: continue
                        val task = manifest.optString("task_id")
                        if (!task.startsWith("delivery-probe-")) continue
                        println("LIVE_BLOB task=$task transfer=${rows.getString(0).take(12)} " +
                            "phase=${rows.getInt(1)} state=${rows.getInt(2)} attempts=${rows.getInt(3)} " +
                            "error=${rows.getString(4)} ready=${rows.getInt(5)}")
                    }
                }
            }
        }
    }

    @Test fun configuredRouteDiagnostics() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("live_delivery") == "true")
        val expectedModel = InstrumentationRegistry.getArguments().getString("live_delivery_model")
        assertFalse("An explicit target model is required", expectedModel.isNullOrBlank())
        assertEquals(expectedModel, Build.MODEL)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val contacts = AppStore.contacts(context)
        for (index in 0 until contacts.length()) {
            val contact = contacts.getJSONObject(index)
            val desktop = contact.optString("desktop_id")
            if (desktop.isBlank()) continue
            val link = GalaxySSILinkProtocol.serverLink(context, desktop) ?: continue
            fun digest(value: String) = java.security.MessageDigest.getInstance("SHA-256")
                .digest(value.toByteArray()).joinToString("") { "%02x".format(it) }.take(16)
            println("LIVE_ROUTE desktop=$desktop route=${link.routes.clientRouteId} paired=${link.paired} " +
                "agent=${AppStore.agentIdForContact(context, contact.optString("id"))} " +
                "up_sha256=${digest(link.routes.up)} down_sha256=${digest(link.routes.down)}")
        }
    }

    @Test fun textAndImageReachTheConfiguredDesktop(): Unit = runBlocking {
        assumeTrue(InstrumentationRegistry.getArguments().getString("live_delivery") == "true")
        val expectedModel = InstrumentationRegistry.getArguments().getString("live_delivery_model")
        assertFalse("An explicit target model is required", expectedModel.isNullOrBlank())
        assertEquals(expectedModel, Build.MODEL)
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
        val concurrency = InstrumentationRegistry.getArguments()
            .getString("live_delivery_concurrency", "1").toInt()
        require(concurrency in 1..10)
        val expectRecovery = InstrumentationRegistry.getArguments().getString("live_delivery_expect_recovery") == "true"
        val imageFirst = InstrumentationRegistry.getArguments().getString("live_delivery_image_first") == "true"
        val reuseConversation = InstrumentationRegistry.getArguments()
            .getString("live_delivery_reuse_conversation") == "true"
        val recoveredResponses = java.util.concurrent.atomic.AtomicInteger()
        val sources = AtomicLong(System.currentTimeMillis())
        coroutineScope {
          List(concurrency) { async {
           val store = AgentTranscriptStore(context)
           val sharedConversation = if (reuseConversation) withContext(Dispatchers.IO) {
               store.createConversation("delivery-probe-multi-turn-${UUID.randomUUID()}", privateMode = true)
           } else null
           for (hasImage in if (imageFirst) listOf(true, false) else listOf(false, true)) {
            val id = "delivery-probe-${UUID.randomUUID()}"
            val source = sources.incrementAndGet()
            val turn = "$id-turn"
            val task = "$id-task"
            val marker = (if (hasImage) "图片投递验证完成" else "文字投递验证完成") + " " + id.takeLast(8)
            val prompt = if (hasImage) "请读取附件中的算式，只回复算式和：$marker。不修改文件。"
                else "请只回复：$marker。不调用工具，不修改文件。"
            val conversation = withContext(Dispatchers.IO) {
                (sharedConversation ?: store.createConversation(marker, privateMode = true)).also {
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
                val startedAt = android.os.SystemClock.elapsedRealtime()
                println("LIVE_START model=${Build.MODEL} image=$hasImage source=$source task=$task " +
                    "conversation=${conversation.id} turn=$turn reuse_conversation=$reuseConversation")
                withContext(Dispatchers.IO) {
                    AgentPendingDeliveryStore.put(context, AgentPendingDelivery(source, conversation.id, turn, task, contact))
                    assertTrue(GalaxySSIMqttClient.publishUserMessage(prompt, contactId = contact,
                        clientMessageId = source, conversationId = conversation.id, turnId = turn, taskId = task))
                }
                val response = withTimeout(180_000L) { final.await() }
                assertTrue(response.success)
                assertEquals("completed", response.taskStatus)
                if (expectRecovery) {
                    assertTrue(response.executionGeneration in 1L..2L)
                    if (response.executionGeneration == 2L) recoveredResponses.incrementAndGet()
                } else assertEquals(1L, response.executionGeneration)
                assertTrue(response.content.contains(marker))
                if (hasImage) assertTrue("The complete equation from the image must be recognized",
                    Regex("2\\s*[+\uff0b]\\s*2\\s*[=\uff1d]\\s*4").containsMatchIn(response.content))
                assertFalse(AgentTerminalDeliveryStore.isTerminal(context, source))
                println("LIVE_DELIVERY image=$hasImage source=$source task=$task generation=${response.executionGeneration} " +
                    "elapsed_ms=${android.os.SystemClock.elapsedRealtime() - startedAt} success=true")
                fixture?.delete()
            } finally {
                GalaxySSIMqttClient.removeListener(listener)
            }
           }
          } }.awaitAll()
        }
        if (expectRecovery) assertTrue("No restarted execution was observed", recoveredResponses.get() > 0)
    }
}
