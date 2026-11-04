package com.galaxyssi.chat

import android.app.Service
import android.content.Intent
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.Process
import java.io.ByteArrayOutputStream
import kotlin.concurrent.thread

/** Deliberately stops only the isolated fixture process, never the main app or camera. */
internal class HealthCropProcessFixture : Service() {
    private val messages = Messenger(Handler(Looper.getMainLooper()) { message ->
        val args = message.data
        val reply = message.replyTo
        thread(name = "health-crop-death-fixture", isDaemon = true) {
            val failed = runCatching {
                val fixture = requireNotNull(args.getString("fixture")).also { require(HealthProfilePolicy.uuid(it)) }
                val names = HealthOverviewDatabases(fixture)
                val id = requireNotNull(args.getString("id"))
                val spec = HealthCropSpec(requireNotNull(args.getString("parent")), "fixture-crop.png", "image/png",
                    requireNotNull(args.getString("batch")), requireNotNull(args.getString("page")), fixture = fixture)
                val mode = requireNotNull(args.getString("phase"))
                require(mode in setOf("staging", "renamed", "committed"))
                val root = names.originalRoot(this)
                val ledger = HealthCropRecovery(root)
                val files = ledger.files(id)
                HealthOriginalStore(this, names.originals, root).use { store ->
                    val parent = requireNotNull(store.original(spec.parentId))
                    val bitmap = HealthPhotoInspector.decode(store, parent, 1_500_000L)
                    val cropped = Bitmap.createBitmap(bitmap, bitmap.width / 10, bitmap.height / 10, bitmap.width * 4 / 5, bitmap.height * 4 / 5)
                    val bytes = try { ByteArrayOutputStream().use {
                        check(cropped.compress(Bitmap.CompressFormat.PNG, 100, it))
                        it.toByteArray()
                    } } finally { cropped.recycle(); bitmap.recycle() }
                    try {
                        bytes.inputStream().use { input ->
                            store.saveCrop(id, input, spec) {
                                if (mode == "staging" && files.staging.length() > 0L ||
                                    mode == "renamed" && files.destination.isFile) stopProcess()
                            }
                        }
                        check(mode == "committed")
                        // Recreate the residue from a stop immediately after commit.
                        check(ledger.marker(id).createNewFile())
                        stopProcess()
                    } finally { bytes.fill(0) }
                }
            }.exceptionOrNull()
            runCatching { reply?.send(Message.obtain(null, 1).apply {
                data = android.os.Bundle().apply { putString("failure", failed?.javaClass?.simpleName ?: "Unexpected fixture completion") }
            }) }
        }
        true
    })
    override fun onBind(intent: Intent) = messages.binder

    private fun stopProcess(): Nothing {
        Process.killProcess(Process.myPid())
        error("Fixture process did not stop")
    }
}
