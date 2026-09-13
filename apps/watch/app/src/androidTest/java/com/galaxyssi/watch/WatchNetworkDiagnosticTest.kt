package com.galaxyssi.watch

import androidx.test.platform.app.InstrumentationRegistry
import okhttp3.OkHttpClient
import okhttp3.Request
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.util.concurrent.TimeUnit

/** Explicit, read-only network diagnostic; skipped by ordinary test runs. */
class WatchNetworkDiagnosticTest {
    @Test fun inspectConfiguredEndpoint() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("network_diagnostic") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext
        val store = WatchStore(context)
        store.tasks().take(3).forEach { println("TASK state=${it.state} route=${it.desktopId} detail=${it.progress}") }
        val profile = store.apiProfile ?: error("No configured API")
        require(profile.endpoint == "https://api.deepseek.com/chat/completions")
        val client = OkHttpClient.Builder().connectTimeout(15, TimeUnit.SECONDS).callTimeout(25, TimeUnit.SECONDS)
            .retryOnConnectionFailure(false).followRedirects(false).build()
        val start = System.nanoTime()
        try {
            client.newCall(Request.Builder().url("https://api.deepseek.com/models")
                .header("Authorization", "Bearer ${profile.key}").build()).execute().use {
                println("DEEPSEEK models HTTP=${it.code} elapsedMs=${(System.nanoTime() - start) / 1000000}")
            }
        } catch (e: Exception) {
            println("DEEPSEEK failure=${e.javaClass.simpleName} elapsedMs=${(System.nanoTime() - start) / 1000000}")
            throw AssertionError("Endpoint connection failed: ${e.javaClass.simpleName}")
        }
    }
}
