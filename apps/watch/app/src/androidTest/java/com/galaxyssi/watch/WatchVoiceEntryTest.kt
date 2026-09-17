package com.galaxyssi.watch

import android.app.Activity
import android.app.Instrumentation
import android.content.ComponentName
import android.content.Intent
import android.content.IntentFilter
import android.speech.RecognizerIntent
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

class WatchVoiceEntryTest {
    @Test fun configureSystemAssistantEntry() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("enable_voice_entry") == "true")
        val repo = (InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as WatchApplication).repository
        repo.store.voiceOnOpen = false
        repo.store.foregroundWake = false
        assertFalse(repo.store.voiceOnOpen)
        assertFalse(repo.store.foregroundWake)
    }

    @Test fun voiceAliasAndOptInLaunchOnceWithoutCancelLoop() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("voice_entry_diagnostic") == "true")
        val inst = InstrumentationRegistry.getInstrumentation()
        val repo = (inst.targetContext.applicationContext as WatchApplication).repository
        assumeTrue(repo.store.apiProfile != null)
        repo.store.tasks()
        val oldOpen = repo.store.voiceOnOpen
        val oldWake = repo.store.foregroundWake
        repo.store.voiceOnOpen = false
        repo.store.foregroundWake = false
        val monitor = inst.addMonitor(IntentFilter(RecognizerIntent.ACTION_RECOGNIZE_SPEECH),
            Instrumentation.ActivityResult(Activity.RESULT_CANCELED, null), true)
        val alias = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
            .setComponent(ComponentName(inst.targetContext, "com.galaxyssi.watch.VoiceEntry"))
        var activity: MainActivity? = null
        fun awaitHits(expected: Int) {
            val deadline = android.os.SystemClock.elapsedRealtime() + 12000
            while (monitor.hits < expected && android.os.SystemClock.elapsedRealtime() < deadline) Thread.sleep(50)
            assertEquals(expected, monitor.hits)
            Thread.sleep(1800)
            assertEquals("Cancel/resume must not reopen speech input", expected, monitor.hits)
        }
        try {
            // startActivitySync tracks concrete activity names; launcher aliases can time out
            // even when their target is visible. Deliver alias intents to the concrete target.
            activity = inst.startActivitySync(Intent(inst.targetContext, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
            fun deliver(intent: Intent) { inst.runOnMainSync {
                MainActivity::class.java.getDeclaredMethod("onNewIntent", Intent::class.java).apply { isAccessible = true }.invoke(activity, intent)
            } }
            deliver(alias)
            awaitHits(1)
            deliver(alias)
            awaitHits(2)
            val ordinary = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER).setClass(inst.targetContext, MainActivity::class.java)
            deliver(ordinary)
            Thread.sleep(1000)
            assertEquals(2, monitor.hits)
            repo.store.voiceOnOpen = true
            deliver(ordinary)
            awaitHits(3)
            val hardwareShortcut = Intent(Intent.ACTION_MAIN).setClass(inst.targetContext, MainActivity::class.java)
            deliver(hardwareShortcut)
            awaitHits(4)
            repo.store.voiceOnOpen = false
            deliver(hardwareShortcut)
            Thread.sleep(1000)
            assertEquals("Hardware shortcut must respect opt-in", 4, monitor.hits)
            repo.store.voiceOnOpen = true
            repo.store.cachedTasks().firstOrNull()?.let { task ->
                deliver(Intent(hardwareShortcut).putExtra("task_id", task.id))
                Thread.sleep(1000)
                assertEquals("Notification task links must not start speech", 4, monitor.hits)
            }
        } finally {
            inst.removeMonitor(monitor)
            repo.store.voiceOnOpen = oldOpen
            repo.store.foregroundWake = oldWake
            inst.runOnMainSync { activity?.finish() }
        }
    }
}
