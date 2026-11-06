package com.galaxyssi.chat

import android.app.Service
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.Process
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

internal class HealthProtectedPdfProcessFixture : Service() {
    private val kill = CountDownLatch(1)
    private val handler = Messenger(Handler(Looper.getMainLooper()) { message ->
        when (message.what) {
            1 -> {
                val fixture = message.data.getString("fixture").orEmpty()
                val job = message.data.getString("job").orEmpty()
                val reply = requireNotNull(message.replyTo)
                thread(name = "health-protected-pdf-death-fixture", isDaemon = true) {
                    val result = runCatching {
                        require(HealthProfilePolicy.uuid(fixture) && HealthProfilePolicy.uuid(job))
                        val names = HealthOverviewDatabases(fixture)
                        HealthOriginalStore(this, names.originals, names.originalRoot(this)).use { store ->
                            check(store.job(job)?.sourceUri == "content://fixture/report")
                            HealthProtectedPdfImport.run(this, store, job, "fixture-password".toCharArray(), { false }) { page, count ->
                                if (page == 2) {
                                    check(count == 2 && store.job(job)?.nextPage == 1)
                                    reply.send(Message.obtain(null, 1))
                                    check(kill.await(40, TimeUnit.SECONDS))
                                    Process.killProcess(Process.myPid())
                                    error("Fixture process did not stop")
                                }
                            }
                        }
                    }
                    runCatching { reply.send(Message.obtain(null, 3).apply {
                        data = Bundle().apply { putString("failure", result.exceptionOrNull()?.javaClass?.simpleName ?: "Unexpected completion") }
                    }) }
                }
            }
            2 -> kill.countDown()
        }
        true
    })

    override fun onBind(intent: Intent) = handler.binder
}
