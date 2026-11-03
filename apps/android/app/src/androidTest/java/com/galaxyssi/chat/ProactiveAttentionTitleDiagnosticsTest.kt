package com.galaxyssi.chat

import android.os.Bundle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ProactiveAttentionTitleDiagnosticsTest {
    @Test fun translateRequestedPublicHeadlineThroughConfiguredRoute() {
        val arguments = InstrumentationRegistry.getArguments()
        assumeTrue(arguments.getString("attention_live_titles") == "true")
        val prefix = arguments.getString("attention_title_prefix").orEmpty()
        assumeTrue(prefix.isNotBlank())
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = AppLanguage.wrap(instrumentation.targetContext)
        val repository = GlobalAgentRepository(context)
        val target = repository.proactiveMessages().first {
            it.id.startsWith("attention-feed:") && it.title.startsWith(prefix) && it.status == GlobalProactiveMessageStatus.DELIVERED
        }
        val preferences = ProactiveAttentionStore(context).preferences()
        val store = ProactiveAttentionTitleStore(context)
        store.prioritize(listOf(target.title), System.currentTimeMillis())
        ProactiveAttentionTitleScheduler.request(context)
        val started = android.os.SystemClock.elapsedRealtime()
        while (store.translation(target.title).isBlank() && android.os.SystemClock.elapsedRealtime() - started < 240_000) {
            android.os.SystemClock.sleep(1_000)
        }
        val translated = store.translation(target.title)
        instrumentation.sendStatus(0, Bundle().apply {
            putString("stream", "target_translation elapsed_ms=${android.os.SystemClock.elapsedRealtime() - started} translated=$translated\n")
        })
        org.junit.Assert.assertTrue("Requested public headline was not translated", translated.isNotBlank())
        org.junit.Assert.assertEquals(target.title, repository.proactiveMessages().first { it.id == target.id }.title)
        org.junit.Assert.assertEquals(preferences.allowCloudModel, ProactiveAttentionStore(context).preferences().allowCloudModel)
        org.junit.Assert.assertEquals(preferences.allowPairedModel, ProactiveAttentionStore(context).preferences().allowPairedModel)
    }

    @Test fun inspectPublicHeadlineTranslationState() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("attention_title_diagnostics") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        fun report(value: String) = instrumentation.sendStatus(0, Bundle().apply { putString("stream", "$value\n") })
        val preferences = ProactiveAttentionStore(context).preferences()
        val repository = GlobalAgentRepository(context)
        val titleStore = ProactiveAttentionTitleStore(context)
        val database = AgentEncryptedDatabase(context, "attention_titles_v1")
        val messages = repository.proactiveMessages().filter { it.id.startsWith("attention-feed:") }
        val english = messages.filter { ProactiveAttentionTitlePolicy.needsTranslation(it.title) }
        val translated = english.count { titleStore.translation(it.title).isNotBlank() }
        report("locale=${context.resources.configuration.locales[0]} public=${messages.size} english=${english.size} translated=$translated paired=${preferences.allowPairedModel} cloud=${preferences.allowCloudModel}")
        val target = messages.firstOrNull { it.title.startsWith("Eight states accuse OpenAI") }
        target?.let {
            val record = JSONObject(database.readString(ProactiveAttentionTitlePolicy.key(it.title), "{}"))
            report("visible_target needs=${ProactiveAttentionTitlePolicy.needsTranslation(it.title)} cached=${titleStore.translation(it.title).isNotBlank()} raw_cached=${record.optString("translated").isNotBlank()} next_delay_ms=${record.optLong("next_at") - System.currentTimeMillis()} retry_delay_ms=${record.optLong("retry_delay")}")
        }
        val request = AttentionTitleRequest.parse(AgentEncryptedDatabase(context, "attention_paired_titles_v1").readString("request", "{}"))
        report("paired_batch exists=${request != null} completed=${request?.completed} expires_in_ms=${request?.expires?.minus(System.currentTimeMillis())} titles=${request?.titles?.size} includes_target=${target?.title in request?.titles?.values.orEmpty()}")
        val budget = GlobalModelCallBudgetStore(context).snapshot(repository.settings())
        report("budget active=${budget.activeCalls} concurrent_limit=${budget.concurrencyLimit} tokens=${budget.totalTokensInWindow} token_limit=${budget.dailyTokenLimit}")
        listOf("attention-title-now-v1", "attention-title-timer-v1").forEach { name ->
            val work = WorkManager.getInstance(context).getWorkInfosForUniqueWork(name).get(10, TimeUnit.SECONDS)
            report("work=$name states=${work.map { "${it.state}:${it.runAttemptCount}" }}")
        }
    }
}
