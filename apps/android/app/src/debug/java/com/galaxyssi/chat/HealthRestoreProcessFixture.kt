package com.galaxyssi.chat

import android.app.Service
import android.content.Intent
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.Process
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

/** Runs only synthetic restores in a dedicated debug process. */
internal class HealthRestoreProcessFixture : Service() {
    private val continueCommit = CountDownLatch(1)
    private val handler = Messenger(Handler(Looper.getMainLooper()) { message ->
        if (message.what == 2) {
            continueCommit.countDown()
        } else {
            val data = message.data
            val reply = requireNotNull(message.replyTo)
            thread(name = "health-restore-death-fixture", isDaemon = true) {
                val failure = runCatching {
                    val id = requireNotNull(data.getString("fixture")).also { require(HealthProfilePolicy.uuid(it)) }
                    val phase = requireNotNull(data.getString("phase"))
                    val file = File(cacheDir, "health-restore-process-$id.ghbackup")
                    val password = "restore test secret".toCharArray()
                    val signal = CancellationSignal()
                    val plan = try {
                        HealthRestoreRepository(this, HealthOverviewDatabases(id)) { "Fixture Owner" }
                            .prepare(file::inputStream, password, signal)
                    } finally { password.fill('\u0000') }
                    plan.use {
                        reply.send(Message.obtain(null, 1).apply { this.data = Bundle().apply { putString("batch", plan.id) } })
                        check(continueCommit.await(45, TimeUnit.SECONDS))
                        if (phase == "preview") stopProcess()
                        val point = HealthRestoreCommitPoint.valueOf(phase)
                        plan.commit(signal) { if (it == point) stopProcess() }
                        error("Restore process did not stop at checkpoint")
                    }
                }.exceptionOrNull()
                runCatching { reply.send(Message.obtain(null, 3).apply {
                    this.data = Bundle().apply { putString("error", failure?.javaClass?.simpleName ?: "Unexpected completion") }
                }) }
            }
        }
        true
    })

    override fun onBind(intent: Intent) = handler.binder

    private fun stopProcess(): Nothing {
        Process.killProcess(Process.myPid())
        error("Fixture process did not stop")
    }
}
