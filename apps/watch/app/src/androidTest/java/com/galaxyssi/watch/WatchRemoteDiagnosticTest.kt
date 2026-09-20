package com.galaxyssi.watch

import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Opt-in end-to-end check using the user's already paired Desktop. Never changes credentials. */
class WatchRemoteDiagnosticTest {
    private fun stacks() {
        Thread.getAllStackTraces().forEach { (thread, frames) ->
            if (frames.any { it.className.contains("galaxyssi") })
                println("WATCH_STACK ${thread.name} ${thread.state}\n" + frames.take(18).joinToString("\n"))
        }
    }
    @Test fun helloRoundTrip() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("remote_diagnostic") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val app = instrumentation.targetContext.applicationContext as WatchApplication
        instrumentation.uiAutomation.executeShellCommand("input keyevent 224").close()
        val activity = instrumentation.startActivitySync(android.content.Intent(app, MainActivity::class.java)
            .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK))
        instrumentation.runOnMainSync {
            activity.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        val repo = app.repository
        require(!repo.store.apiPreferred && repo.store.selectedAgent == "codex")
        repo.foreground(true)
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(90)
        while (!repo.online(repo.store.selectedDesktop) && System.nanoTime() < deadline) Thread.sleep(250)
        println("WATCH_TRANSPORT ${repo.transportDiagnostics()}")
        if (!repo.online(repo.store.selectedDesktop)) stacks()
        assertTrue("Desktop route not ready: ${repo.transportDiagnostics()}", repo.online(repo.store.selectedDesktop))
        val queued = CountDownLatch(1)
        var sent: WatchTask? = null
        repo.send("Hello", null) { sent = it; queued.countDown() }
        assertTrue(queued.await(15, TimeUnit.SECONDS))
        val id = requireNotNull(sent).id
        instrumentation.runOnMainSync {
            activity.startActivity(android.content.Intent(app, MainActivity::class.java).putExtra("task_id", id)
                .addFlags(android.content.Intent.FLAG_ACTIVITY_CLEAR_TOP or android.content.Intent.FLAG_ACTIVITY_SINGLE_TOP))
        }
        val replyDeadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(120)
        var result = repo.store.task(id)!!
        while ((!result.state.terminal || (result.state == TaskState.COMPLETED && result.reply.isBlank())) && System.nanoTime() < replyDeadline) {
            Thread.sleep(250); result = repo.store.task(id)!!
        }
        println("WATCH_HELLO task=${result.id} state=${result.state} chars=${result.reply.length} detail=${result.progress.take(180)}")
        if (!result.state.terminal) stacks()
        assertEquals(TaskState.COMPLETED, result.state)
        assertTrue("Expected a nonempty answer", result.reply.isNotBlank())
    }
}
