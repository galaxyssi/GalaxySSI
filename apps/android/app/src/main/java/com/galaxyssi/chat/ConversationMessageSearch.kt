package com.galaxyssi.chat

import android.content.Context
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

/** One transient, cancellable scan per open hub; no index, query history or snippets on disk. */
internal class ConversationMessageSearch(private val context: Context, private val changed: () -> Unit) {
    private val main = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val epoch = AtomicLong()
    private var delayed: Runnable? = null
    private var iterator: Iterator<LocalMessageHit>? = null // accessed only by the scanner thread
    var hits = emptyList<LocalMessageHit>()
        private set
    var active = false
        private set
    var busy = false
        private set
    var more = false
        private set
    var failed = false
        private set

    fun reset(query: String, archived: Boolean) {
        if (executor.isShutdown) return
        val id = epoch.incrementAndGet()
        delayed?.let(main::removeCallbacks)
        hits = emptyList(); busy = false; more = false; failed = false; active = query.isNotBlank()
        if (!active) { executor.execute { iterator = null }; return }
        busy = true
        delayed = Runnable {
            executor.execute {
                if (epoch.get() != id) return@execute
                iterator = LocalMessageSearch.scan(context, query, archived) { epoch.get() != id }.iterator()
                read(id)
            }
        }.also { main.postDelayed(it, 220) }
    }
    fun next() {
        if (executor.isShutdown || busy || !more || !active) return
        val id = epoch.get()
        busy = true; more = false; changed()
        executor.execute { read(id) }
    }
    private fun read(id: Long) {
        val scan = iterator ?: return
        val pending = mutableListOf<LocalMessageHit>()
        fun publish() {
            if (pending.isEmpty()) return
            val batch = pending.toList()
            pending.clear()
            main.post { if (epoch.get() == id) { hits = hits + batch; changed() } }
        }
        try {
            for (i in 0 until 24) {
                if (epoch.get() != id) return
                if (!scan.hasNext()) {
                    publish()
                    iterator = null
                    main.post { if (epoch.get() == id) { busy = false; more = false; changed() } }
                    return
                }
                pending += scan.next()
                if (i == 0 || pending.size >= 6) publish()
            }
            publish()
            main.post { if (epoch.get() == id) { busy = false; more = true; changed() } }
        } catch (_: Exception) {
            publish()
            main.post { if (epoch.get() == id) { busy = false; failed = true; changed() } }
        }
    }
    fun close() {
        epoch.incrementAndGet(); delayed?.let(main::removeCallbacks)
        main.removeCallbacksAndMessages(null); hits = emptyList()
        executor.shutdownNow()
    }
}
