package com.galaxyssi.chat

import android.content.Intent
import android.graphics.Bitmap
import android.provider.Settings
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Explicit opt-in harness: real HTTPS download, visible UI and production restart recovery. */
@RunWith(AndroidJUnit4::class)
class KnowledgeModelProductionDeviceTest {
    @Test fun exerciseSelectedPhase() {
        val phase = InstrumentationRegistry.getArguments().getString("knowledgeModelPhase").orEmpty()
        assumeTrue("Select download, prepare, verify or show explicitly", phase.isNotEmpty())
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val controller = KnowledgeSemanticRuntime.production(context)
        controller.awaitReady()
        val marker = File(context.filesDir, "knowledge-model-production-test.json")
        val activity = instrumentation.startActivitySync(Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        await("startup overlay finishes") {
            var ready = false
            instrumentation.runOnMainSync { ready = activity.findViewById<View>(R.id.startupConnectingView).visibility == View.GONE }
            ready
        }
        instrumentation.runOnMainSync {
            if (phase == "show") {
                activity.showAgentKnowledgePage()
                clickLabel(activity, activity.getString(R.string.knowledge_model_title))
            } else activity.showKnowledgeModelPage()
        }
        instrumentation.waitForIdleSync()
        when (phase) {
            "download" -> {
                check(!controller.state.installed) { "The real download case requires an uninstalled model; do not delete a user's model" }
                val started = SystemClock.elapsedRealtime()
                instrumentation.runOnMainSync {
                    clickLabel(activity, activity.getString(R.string.knowledge_model_download))
                }
                await("real HTTPS model download", 300_000) {
                    check(controller.state.phase != "error" || controller.downloadPending) { controller.state.error }
                    controller.state.installed && controller.state.enabled
                }
                controller.artifact.verifyInstalled()
                println("KNOWLEDGE_MODEL_DOWNLOAD verified_bytes=${controller.modelFile.length()} elapsed_ms=${SystemClock.elapsedRealtime() - started}")
            }
            "prepare" -> {
                check(!marker.exists()) { "Finish the previous named recovery fixture first" }
                controller.artifact.verifyInstalled()
                val previousEnabled = controller.state.enabled
                controller.setEnabled(false).get(40, TimeUnit.SECONDS)
                await("previous index stops") { controller.runningWork.get() == 0 }
                val prefix = "semantic-recovery-${UUID.randomUUID()}"
                val ids = (0 until 64).map { "$prefix-$it" }
                val source = "test://$prefix"
                val saved = JSONObject().put("ids", JSONArray(ids)).put("source", source)
                    .put("boot", Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT))
                    .put("previous_enabled", previousEnabled)
                marker.writeText(saved.toString())
                val store = SQLiteAgentKnowledgeStore(context)
                ids.forEachIndexed { index, id -> store.upsert(AgentKnowledgeItem(id, AgentKnowledgeKind.NOTE,
                    "$prefix $index", "\u624b\u673a\u4e22\u5931\u540e\u53ef\u4ee5\u901a\u8fc7\u5b9a\u4f4d\u529f\u80fd\u67e5\u627e\u8bbe\u5907\u3002".repeat(80), source = source)) }
                controller.setEnabled(true).get(40, TimeUnit.SECONDS)
                val ledger = controller.database().vectors(KnowledgeEmbeddingModel.spec)
                val keys = ids.map { controller.database().key("id", it) }
                var checkpoint: JSONObject? = null
                await("first durable vector") {
                    checkpoint = controller.database().access { db -> db.rawQuery(
                        "SELECT item_key,ordinal,hex(ciphertext) FROM knowledge_vectors WHERE model_key=? AND item_key IN (${keys.joinToString(",") { "?" }}) LIMIT 1",
                        (listOf(ledger.modelKey) + keys).toTypedArray()).use {
                        if (!it.moveToFirst()) null else JSONObject().put("key", it.getString(0))
                            .put("ordinal", it.getInt(1)).put("ciphertext", it.getString(2))
                    } }
                    checkpoint != null
                }
                marker.writeText(saved.put("checkpoint", checkpoint).toString())
                println("KNOWLEDGE_MODEL_RECOVERY_PREPARED boot=${saved.getInt("boot")} documents=64")
            }
            "verify" -> {
                val saved = JSONObject(marker.readText())
                val boot = Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT)
                check(boot > saved.getInt("boot")) { "A real device reboot is required" }
                assertTrue(controller.state.enabled)
                val ids = saved.getJSONArray("ids").let { array -> List(array.length()) { array.getString(it) } }
                val ledger = controller.database().vectors(KnowledgeEmbeddingModel.spec)
                val keys = ids.map { controller.database().key("id", it) }
                val started = SystemClock.elapsedRealtime()
                await("production startup drains durable queue", 900_000) {
                    controller.database().access { db -> db.rawQuery(
                        "SELECT count(*) FROM knowledge_vector_docs WHERE model_key=? AND complete=1 AND item_key IN (${keys.joinToString(",") { "?" }})",
                        (listOf(ledger.modelKey) + keys).toTypedArray()).use { check(it.moveToFirst()); it.getInt(0) == ids.size } }
                }
                assertTrue(ids.all { id -> ledger.page(id, 0)?.use { it.total > 0 } == true })
                val checkpoint = saved.getJSONObject("checkpoint")
                val unchanged = controller.database().access { db -> db.rawQuery(
                    "SELECT count(*) FROM knowledge_vectors WHERE model_key=? AND item_key=? AND ordinal=? AND hex(ciphertext)=?",
                    arrayOf(ledger.modelKey, checkpoint.getString("key"), checkpoint.getInt("ordinal").toString(), checkpoint.getString("ciphertext"))).use {
                    check(it.moveToFirst()); it.getLong(0)
                } }
                assertEquals(1L, unchanged)
                println("KNOWLEDGE_MODEL_RECOVERY_VERIFIED boot=$boot documents=${ids.size} elapsed_ms=${SystemClock.elapsedRealtime() - started} unchanged_checkpoint=1")
                // Delete only records created by this explicit test, not user knowledge.
                controller.database().transaction { db -> ids.forEach { id ->
                    db.delete("knowledge_items", "item_key=?", arrayOf(controller.database().key("id", id)))
                } }
                controller.invalidateSession()
                controller.setEnabled(saved.getBoolean("previous_enabled")).get(40, TimeUnit.SECONDS)
                check(marker.delete())
            }
            "show" -> Unit
            else -> error("Unknown test phase")
        }
        instrumentation.waitForIdleSync()
        val drawn = java.util.concurrent.CountDownLatch(1)
        instrumentation.runOnMainSync {
            assertFalse(allViews(activity.featureContent).filterIsInstance<TextView>().any { it.text.toString() == "?" })
            activity.featureContent.postOnAnimation { activity.featureContent.postOnAnimation { drawn.countDown() } }
        }
        check(drawn.await(10, TimeUnit.SECONDS)) { "Model page did not draw" }
        val screenshot = File(context.getExternalFilesDir(null), "embedding-test/knowledge-model-$phase.png")
        screenshot.parentFile!!.mkdirs()
        instrumentation.uiAutomation.takeScreenshot().let { bitmap ->
            screenshot.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            bitmap.recycle()
        }
    }
    private fun clickLabel(activity: MainActivity, label: String) {
        var target: View = allViews(activity.featureContent).filterIsInstance<TextView>().first { it.text.toString() == label }
        while (!target.isClickable) target = target.parent as View
        assertTrue(target.performClick())
    }
    private fun allViews(view: View): Sequence<View> = sequence {
        yield(view)
        if (view is ViewGroup) for (i in 0 until view.childCount) yieldAll(allViews(view.getChildAt(i)))
    }
    private fun await(label: String, timeout: Long = 180_000, predicate: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + timeout
        while (!predicate()) { check(SystemClock.elapsedRealtime() < deadline) { "Timed out: $label" }; SystemClock.sleep(100) }
    }
}
