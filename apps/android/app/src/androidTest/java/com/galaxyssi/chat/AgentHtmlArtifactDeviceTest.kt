package com.galaxyssi.chat

import android.app.Dialog
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import android.widget.ScrollView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentHtmlArtifactDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    @Test fun declaredCloudAnimationPersistsPrivatelyAndPlaysWithoutLinux() {
        val block = AgentRichBlock("cloud-html", AgentRichBlockType.HTML, title = "cloud-animation",
            text = ANIMATION, fallbackText = "Animation")
        val answer = "Animation\n```galaxyssi-rich\n${AgentRichContentCodec.encode(listOf(block))}\n```"
        val stored = AgentRichContentCodec.decode(AgentRichContentMaterializer.materialize(context, "", answer))
        val delivered = stored.single { it.type == AgentRichBlockType.FILE }
        val file = LocalAttachmentUris.resolve(context, android.net.Uri.parse(delivered.uri))!!
        try {
            assertEquals("text/html", delivered.mimeType)
            assertEquals("cloud-animation.html", delivered.title)
            assertEquals("app_private", delivered.metadata["storage"])
            assertTrue(file.canonicalPath.startsWith(context.filesDir.canonicalPath + File.separator))
            assertArrayEquals(ANIMATION.toByteArray(), file.readBytes())
            assertEquals(ANIMATION, AgentHtmlArtifactPreview.load(context, delivered))
            val again = AgentRichContentMaterializer.materialize(context, AgentRichContentCodec.encode(stored))
            assertEquals(delivered.uri, AgentRichContentCodec.decode(again).single { it.type == AgentRichBlockType.FILE }.uri)
            renderAndCheck(delivered, "inline-html-cloud-materialized")
        } finally { file.delete() }
    }

    @Test fun inspectRequestedGeneratedSource() {
        val args = InstrumentationRegistry.getArguments()
        val path = args.getString("inspect_html_source_path").orEmpty()
        assumeTrue(path.isNotBlank())
        val source = File(path)
        require(source.canonicalPath.startsWith(File(context.filesDir, "diagnostics").canonicalPath + File.separator))
        assertEquals(args.getString("inspect_html_source_sha256"), digest(source))
        val block = AgentRichBlock("preserved-cloud-html", AgentRichBlockType.HTML,
            title = "preserved-animation.html", text = source.readText())
        val stored = AgentRichContentMaterializer.materialize(context, AgentRichContentCodec.encode(listOf(block)))
        val file = LocalAttachmentUris.resolve(context, android.net.Uri.parse(AgentRichContentCodec.decode(stored).single().uri))!!
        val activity = instrumentation.startActivitySync(Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)) as MainActivity
        try {
            verifyLiveCanvas(activity, AgentTranscriptEntry("preserved-html-regression", AgentTranscriptRole.ASSISTANT,
                "Preserved model output", System.currentTimeMillis(), richOutputJson = stored))
        } finally { file.delete(); instrumentation.runOnMainSync { activity.finish() } }
    }

    @Test fun localHtmlAutomaticallyAnimatesAndReloadsAfterDetach() {
        val directory = File(context.filesDir, "agent-native-workspaces/html-preview-test-${UUID.randomUUID()}")
        directory.mkdirs()
        val file = File(directory, "animation.html").apply { writeText(ANIMATION) }
        try {
            val block = runtimeBlock(file)
            assertEquals(ANIMATION, AgentHtmlArtifactPreview.load(context, block))
            renderAndCheck(block, "inline-html-fixture")
            assertEquals(ANIMATION, file.readText())
        } finally { file.delete(); directory.delete() }
    }

    @Test fun deliveredPrivateAttachmentLoadsButInvalidHashAndExternalUriDoNot() {
        val file = File(context.filesDir, "agent-rich-output-v2/html-test-${UUID.randomUUID()}.html")
        AttachmentLocalStore.storeBytes(ANIMATION.toByteArray(), file)
        try {
            val block = AgentRichBlock("private-html", AgentRichBlockType.FILE, title = "animation.html",
                mimeType = "text/html", uri = LocalAttachmentUris.forFile(context, file, "animation.html", "text/html").toString(),
                metadata = mapOf("sha256" to digest(file)))
            assertEquals(ANIMATION, AgentHtmlArtifactPreview.load(context, block))
            assertThrows(IllegalArgumentException::class.java) {
                AgentHtmlArtifactPreview.load(context, block.copy(metadata = mapOf("sha256" to "0".repeat(64))))
            }
            assertThrows(IllegalArgumentException::class.java) {
                AgentHtmlArtifactPreview.load(context, block.copy(uri = "https://example.com/animation.html"))
            }
            assertThrows(IllegalArgumentException::class.java) {
                AgentHtmlArtifactPreview.load(context, block.copy(uri = "file:///data/data/com.galaxyssi.chat/shared_prefs/private.xml"))
            }
            renderAndCheck(block, "inline-html-private")
        } finally { file.delete() }
    }

    /** Explicit read-only verification of an existing delivered artifact, without resubmitting the task. */
    @Test fun inspectRequestedRuntimeArtifact() {
        val path = InstrumentationRegistry.getArguments().getString("inspect_html_path").orEmpty()
        assumeTrue(path.isNotBlank())
        val expected = InstrumentationRegistry.getArguments().getString("inspect_html_sha256").orEmpty()
        require(expected.matches(Regex("[a-f0-9]{64}")))
        val file = File(path)
        assertEquals(expected, digest(file))
        renderAndCheck(runtimeBlock(file), "inline-html-existing")
        assertEquals(expected, digest(file))
    }

    private fun renderAndCheck(block: AgentRichBlock, screenshotName: String) {
        val activity = instrumentation.startActivitySync(Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)) as MainActivity
        lateinit var dialog: Dialog
        lateinit var output: View
        instrumentation.runOnMainSync {
            activity.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            output = AgentRichContentView(activity, {}, {}, { _, _ -> }, enableResponseSections = false).create(
                AgentTranscriptEntry("html-test", AgentTranscriptRole.ASSISTANT, "", System.currentTimeMillis(),
                    richOutputJson = AgentRichContentCodec.encode(listOf(block))))
            dialog = Dialog(activity, android.R.style.Theme_Material_Light_NoActionBar).apply {
                setContentView(ScrollView(activity).apply { addView(output) })
                show()
                window?.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            }
        }
        try {
            var web = awaitWebView(output)
            val first = sample(web)
            SystemClock.sleep(900)
            val next = sample(web)
            assertTrue("Canvas must contain visible pixels", next.getInt("painted") > 10)
            assertTrue("Animation must advance without opening the attachment", next.getDouble("time") > first.getDouble("time"))
            assertNotEquals("Rendered canvas must change", first.getLong("pixels"), next.getLong("pixels"))
            instrumentation.runOnMainSync {
                assertFalse(web.settings.allowFileAccess)
                assertFalse(web.settings.allowContentAccess)
                assertTrue(web.settings.blockNetworkLoads)
            }
            evaluate(web, "document.getElementById('toggle').click()")
            SystemClock.sleep(120)
            val paused = sample(web).getDouble("time")
            SystemClock.sleep(300)
            assertEquals(paused, sample(web).getDouble("time"), 0.001)
            evaluate(web, "document.getElementById('restart').click()")
            SystemClock.sleep(100)
            assertTrue(sample(web).getDouble("time") < 1.0)
            val screenshot = instrumentation.uiAutomation.takeScreenshot()
            File(context.filesDir, "$screenshotName.png").outputStream().use {
                screenshot.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
            }
            screenshot.recycle()
            // Recycling or returning to the page must create a fresh functioning preview.
            instrumentation.runOnMainSync { dialog.hide() }
            SystemClock.sleep(150)
            instrumentation.runOnMainSync { dialog.show() }
            val replacement = awaitWebView(output)
            assertNotSame(web, replacement)
            web = replacement
            val resumed = sample(web).getDouble("time")
            SystemClock.sleep(300)
            assertTrue(sample(web).getDouble("time") > resumed)
        } finally {
            instrumentation.runOnMainSync { dialog.dismiss(); activity.finish() }
        }
    }

    private fun awaitWebView(root: View): WebView {
        val deadline = SystemClock.elapsedRealtime() + 15_000
        while (SystemClock.elapsedRealtime() < deadline) {
            var web: WebView? = null
            instrumentation.runOnMainSync { web = all(root).filterIsInstance<WebView>().firstOrNull() }
            if (web != null && runCatching { sample(web!!).getInt("painted") > 0 }.getOrDefault(false)) return web!!
            SystemClock.sleep(100)
        }
        error("HTML animation did not render")
    }

    private fun sample(web: WebView): JSONObject = JSONObject(evaluate(web, """
        (() => {const c=document.querySelector('canvas'),d=c.getContext('2d').getImageData(0,0,c.width,c.height).data;
        let painted=0,pixels=0;for(let i=0;i<d.length;i+=4){if(d[i+3])painted++;pixels=(pixels+(i+1)*(d[i]+d[i+1]*3+d[i+2]*7))%1000000007;}
        return {time:Number(document.body.dataset.animationTime),painted,pixels};})()
    """.trimIndent()))

    private fun evaluate(web: WebView, source: String): String {
        val done = CountDownLatch(1)
        var result = "null"
        instrumentation.runOnMainSync { web.evaluateJavascript(source) { result = it; done.countDown() } }
        assertTrue(done.await(5, TimeUnit.SECONDS))
        return result
    }

    private fun runtimeBlock(file: File): AgentRichBlock = AgentRichContentCodec.decode(
        AgentRuntimeArtifactUi.artifactOutput(mapOf("artifacts" to listOf(mapOf(
            "host_path" to file.path, "relative_path" to file.name,
            "sha256" to digest(file), "size_bytes" to file.length()
        ))), zh = true)).single()

    private fun digest(file: File) = MessageDigest.getInstance("SHA-256").digest(file.readBytes()).joinToString("") { "%02x".format(it) }
    private fun all(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { all(view.getChildAt(it)) } else emptyList()

    private companion object {
        val ANIMATION = """
            <!doctype html><html><body><h2>动画预览测试</h2><canvas width="200" height="100"></canvas>
            <button id="toggle">暂停</button><button id="restart">重播</button><script>
            let t=0,playing=true,last=0;const c=document.querySelector('canvas'),g=c.getContext('2d');
            function tick(n){if(last&&playing)t+=(n-last)/1000;last=n;g.clearRect(0,0,200,100);
            g.fillStyle='#00a890';g.fillRect(50+Math.sin(t)*40,25,40,40);document.body.dataset.animationTime=t;
            requestAnimationFrame(tick);}requestAnimationFrame(tick);
            document.getElementById('toggle').onclick=()=>playing=!playing;
            document.getElementById('restart').onclick=()=>{t=0;playing=true;};
            </script></body></html>
        """.trimIndent()
    }
}
