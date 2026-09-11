package com.galaxyssi.chat

import android.content.ComponentName
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.ServiceConnection
import android.os.*
import android.util.Log
import android.webkit.WebView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentWebRendererDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val component = ComponentName(context, AgentIsolatedWebRenderService::class.java)

    @Test fun rendererStartsRepeatedlyAlongsideMainProcessWebView() = withMainWebView {
        repeat(3) { index ->
            val connected = CountDownLatch(1)
            val responses = ArrayBlockingQueue<Bundle>(1)
            var remote: Messenger? = null
            val connection = object : ServiceConnection {
                override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
                    remote = Messenger(binder)
                    connected.countDown()
                }
                override fun onServiceDisconnected(name: ComponentName?) = Unit
            }
            val started = SystemClock.elapsedRealtime()
            assertTrue(context.bindService(Intent(context, AgentIsolatedWebRenderService::class.java),
                connection, Context.BIND_AUTO_CREATE))
            try {
                assertTrue("Renderer did not bind", connected.await(8, TimeUnit.SECONDS))
                val reply = Messenger(Handler(Looper.getMainLooper()) {
                    responses.offer(Bundle(it.data)); true
                })
                remote!!.send(Message.obtain(null, AgentWebRenderContract.MSG_RENDER).apply {
                    replyTo = reply
                    data = Bundle().apply {
                        putString(AgentWebRenderContract.KEY_REQUEST_ID, "isolation-$index")
                        putString(AgentWebRenderContract.KEY_URL, "http://localhost/blocked")
                    }
                })
                val result = responses.poll(5, TimeUnit.SECONDS)
                assertNotNull("Renderer did not reply", result)
                assertEquals("renderer_invalid_request", result!!.getString(AgentWebRenderContract.KEY_ERROR))
                assertTrue(File(context.applicationInfo.dataDir,
                    "app_webview_${AgentWebRendererProcessPolicy.DIRECTORY_SUFFIX}").isDirectory)
                Log.i("GalaxySSIWebViewTest", "isolated_bind_reply_ms=${SystemClock.elapsedRealtime() - started}")
            } finally { context.unbindService(connection) }
        }
    }

    @Test fun realPublicPageRendersAlongsideMainProcessWebView() = withMainWebView {
        val url = InstrumentationRegistry.getArguments().getString("web_renderer_test_url")
            ?: "https://example.com/"
        val started = SystemClock.elapsedRealtime()
        val result = AgentIsolatedWebViewRenderer(context, AgentWebRendererHealth()).render(
            url, 1_000_000, 30_000, AgentNativeToolCancellationToken.NONE) {}
        assertTrue(result.body.size > 50)
        assertTrue(result.contentType.contains("html"))
        assertTrue(result.body.toString(Charsets.UTF_8).contains("<", true))
        Log.i("GalaxySSIWebViewTest", "public_render_ms=${SystemClock.elapsedRealtime() - started} bytes=${result.body.size}")
    }

    @Test fun failedBindingsReturnQuicklyAndDoNotRebindDuringCooldown() {
        assumeTrue(Build.VERSION.SDK_INT >= 28)
        for (failure in listOf("null", "died", "disconnected", "rejected")) {
            val binds = AtomicInteger()
            val unbinds = AtomicInteger()
            val fake = object : ContextWrapper(context) {
                override fun getApplicationContext(): Context = this
                override fun bindService(intent: Intent, connection: ServiceConnection, flags: Int): Boolean {
                    binds.incrementAndGet()
                    if (failure == "rejected") return false
                    Handler(Looper.getMainLooper()).post {
                        when (failure) {
                            "null" -> connection.onNullBinding(component)
                            "died" -> connection.onBindingDied(component)
                            else -> connection.onServiceDisconnected(component)
                        }
                    }
                    return true
                }
                override fun unbindService(connection: ServiceConnection) { unbinds.incrementAndGet() }
            }
            val renderer = AgentIsolatedWebViewRenderer(fake, AgentWebRendererHealth())
            val started = SystemClock.elapsedRealtime()
            repeat(2) {
                assertThrows(AgentWebRendererUnavailableException::class.java) {
                    renderer.render("https://1.1.1.1/", 100_000, 15_000, AgentNativeToolCancellationToken.NONE) {}
                }
            }
            val elapsed = SystemClock.elapsedRealtime() - started
            assertTrue("$failure took ${elapsed}ms", elapsed < 2_000)
            assertEquals(1, binds.get())
            assertEquals(if (failure == "rejected") 0 else 1, unbinds.get())
            Log.i("GalaxySSIWebViewTest", "failed_binding=$failure elapsed_ms=$elapsed binds=${binds.get()}")
        }
    }

    @Test fun missingConnectionIsBoundedAndCancellationDoesNotPoisonRenderer() {
        assumeTrue(Build.VERSION.SDK_INT >= 28)
        val unbinds = AtomicInteger()
        val fake = object : ContextWrapper(context) {
            override fun getApplicationContext(): Context = this
            override fun bindService(intent: Intent, connection: ServiceConnection, flags: Int) = true
            override fun unbindService(connection: ServiceConnection) { unbinds.incrementAndGet() }
        }
        val health = AgentWebRendererHealth()
        val renderer = AgentIsolatedWebViewRenderer(fake, health)
        val cancellation = AgentNativeToolCancellationSource()
        Handler(Looper.getMainLooper()).postDelayed({ cancellation.cancel() }, 100)
        val cancelStarted = SystemClock.elapsedRealtime()
        assertThrows(AgentNativeToolCancelledException::class.java) {
            renderer.render("https://1.1.1.1/", 100_000, 15_000, cancellation.token) {}
        }
        assertTrue(SystemClock.elapsedRealtime() - cancelStarted < 2_000)
        health.checkAvailable()
        val started = SystemClock.elapsedRealtime()
        assertThrows(AgentWebRendererUnavailableException::class.java) {
            renderer.render("https://1.1.1.1/", 100_000, 15_000, AgentNativeToolCancellationToken.NONE) {}
        }
        val elapsed = SystemClock.elapsedRealtime() - started
        assertTrue("Unconnected renderer waited ${elapsed}ms", elapsed in 4_500..7_000)
        assertEquals(2, unbinds.get())
        Log.i("GalaxySSIWebViewTest", "missing_connection_ms=$elapsed")
    }

    private fun withMainWebView(block: () -> Unit) {
        assumeTrue(Build.VERSION.SDK_INT >= 28)
        var view: WebView? = null
        instrumentation.runOnMainSync {
            view = WebView(context).apply { loadData("<html><body>Main process</body></html>", "text/html", "UTF-8") }
        }
        try { block() } finally { instrumentation.runOnMainSync { view?.destroy() } }
    }
}
