package com.galaxyssi.watch

import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test

class WatchWebDiagnosticTest {
    @Test fun configuredModelAnswersWithSearchEvidence() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("web_api_diagnostic") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext
        val profile = WatchStore(context).apiProfile ?: error("No configured API")
        val operation = WatchApiOperation()
        val question = "What is the latest Wear OS release? Answer briefly with source citations."
        val evidence = WatchWebSearch().search(question, operation)
        val task = WatchTask.create("api", profile.id, profile.model, question)
        val api = WatchApi()
        val reply = api.execute(operation.attach(api.request(profile, task, emptyList(), evidence.json())))
        assertTrue(reply.isNotBlank())
        assertTrue("Expected source references in the answer", Regex("\\[[1-4]\\]").containsMatchIn(reply))
        // Do not log credentials, stored conversations, or model response bodies.
    }
    @Test fun publicSearchFromWatchWifi() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("web_diagnostic") == "true")
        val result = WatchWebSearch().search("Wear OS latest release", WatchApiOperation())
        assertTrue(result.hits.isNotEmpty())
        println("WATCH_WEB sources=${result.hits.size} retrieved=${result.retrievedAt}")
    }
}
