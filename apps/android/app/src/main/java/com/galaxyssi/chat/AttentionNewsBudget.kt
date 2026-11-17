package com.galaxyssi.chat

import android.content.Context
import android.os.BatteryManager
import android.os.Process
import android.os.SystemClock

internal const val ATTENTION_MINUTE = 60_000L

internal data class AttentionNewsProfile(val recentlyRead: Boolean, val charging: Boolean) {
    val feedInterval = when {
        !recentlyRead -> 12 * 60 * ATTENTION_MINUTE
        charging -> 30 * ATTENTION_MINUTE
        else -> 60 * ATTENTION_MINUTE
    }
    val feedSpacing = when {
        charging -> 15_000L
        recentlyRead -> ATTENTION_MINUTE
        else -> 5 * ATTENTION_MINUTE
    }
    val articleLimit = if (charging) 10 else if (recentlyRead) 4 else 2
    val articleTime = if (charging) 60_000L else 30_000L
    val allowPush = charging && recentlyRead

    fun articleSpacing(published: Boolean): Long = when {
        !charging && !recentlyRead -> 12 * 60 * ATTENTION_MINUTE
        charging && published -> 2 * ATTENTION_MINUTE
        charging -> 10 * ATTENTION_MINUTE
        published -> 15 * ATTENTION_MINUTE
        else -> 45 * ATTENTION_MINUTE
    }

    companion object {
        fun topicDueAt(last: Long, next: Long, storedInterval: Long, cursor: Int, interval: Long): Long =
            if (cursor == 0 && last > 0L && storedInterval > 0 && next == last + storedInterval) last + interval else next

        fun of(now: Long, lastRead: Long, charging: Boolean) =
            AttentionNewsProfile(lastRead > 0L && now - lastRead in 0L until 24 * 60 * ATTENTION_MINUTE, charging)

        fun remaining(now: Long, last: Long, interval: Long): Long =
            if (last <= 0L || last > now) 0L else (interval - (now - last)).coerceAtLeast(0L)
    }
}

internal class AttentionNewsCpuWindow {
    private var startAt = -1L
    private var startCpu = 0L
    private var resumeAt = 0L

    @Synchronized
    fun delay(elapsed: Long, cpu: Long): Long {
        if (elapsed < resumeAt) return resumeAt - elapsed
        val duration = elapsed - startAt
        if (startAt < 0 || duration < 0 || duration > 60_000L || cpu < startCpu) {
            startAt = elapsed
            startCpu = cpu
        } else if (duration >= 10_000L) {
            if ((cpu - startCpu) * 10 >= duration) {
                resumeAt = elapsed + 5 * ATTENTION_MINUTE
                startAt = -1L
            } else {
                startAt = elapsed
                startCpu = cpu
            }
        }
        return (resumeAt - elapsed).coerceAtLeast(0L)
    }
}

internal object AttentionNewsBudget {
    private val cpu = AttentionNewsCpuWindow()
    private fun state(context: Context) = context.getSharedPreferences("attention_news_budget_v1", Context.MODE_PRIVATE)

    fun profile(context: Context, now: Long = System.currentTimeMillis()) = AttentionNewsProfile.of(
        now, state(context).getLong("last_read", 0L),
        context.getSystemService(BatteryManager::class.java)?.isCharging == true
    )

    @Synchronized
    fun noteRead(context: Context) {
        val now = System.currentTimeMillis()
        val prefs = state(context)
        val last = prefs.getLong("last_read", 0L)
        if (AttentionNewsProfile.remaining(now, last, ATTENTION_MINUTE) > 0L) return
        val wasActive = AttentionNewsProfile.of(now, last, false).recentlyRead
        prefs.edit().putLong("last_read", now).apply()
        if (!wasActive) {
            ProactiveAttentionFeedScheduler.request(context)
            AttentionArticleScheduler.request(context)
            ProactiveAttentionPush.refresh()
        }
    }

    fun cpuDelay() = cpu.delay(SystemClock.elapsedRealtime(), Process.getElapsedCpuTime()).also {
        if (it == 5 * ATTENTION_MINUTE) android.util.Log.i("GalaxySSIAttention", "news_budget_pause reason=process_cpu")
    }
    fun pressure(context: Context) = maxOf(cpuDelay(), BackgroundLearningLoadSampler.read(context).deferMillis)

    fun feedDelay(context: Context, now: Long, profile: AttentionNewsProfile): Long =
        AttentionNewsProfile.remaining(now, state(context).getLong("last_feed", 0L), profile.feedSpacing)

    fun feedFinished(context: Context, now: Long) {
        state(context).edit().putLong("last_feed", now).apply()
    }

    fun articleDelay(context: Context, now: Long, profile: AttentionNewsProfile): Long {
        val prefs = state(context)
        return AttentionNewsProfile.remaining(now, prefs.getLong("last_article", 0L),
            profile.articleSpacing(prefs.getBoolean("article_published", false)))
    }

    fun articleBoundary(context: Context, now: Long, published: Boolean = false) {
        state(context).edit().putLong("last_article", now).putBoolean("article_published", published).apply()
    }
}
