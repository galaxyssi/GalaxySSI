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
        if (busy || !more || !active) return
        val id = epoch.get()
        busy = true; more = false; changed()
        executor.execute { read(id) }
    }
    private fun read(id: Long) {
        val scan = iterator ?: return
        try {
            for (i in 0 until 24) {
                if (epoch.get() != id) return
                if (!scan.hasNext()) {
                    iterator = null
                    main.post { if (epoch.get() == id) { busy = false; more = false; changed() } }
                    return
                }
                val hit = scan.next()
                main.post { if (epoch.get() == id) { hits = hits + hit; changed() } }
            }
            main.post { if (epoch.get() == id) { busy = false; more = true; changed() } }
        } catch (_: Exception) {
            main.post { if (epoch.get() == id) { busy = false; failed = true; changed() } }
        }
    }
    fun close() {
        epoch.incrementAndGet(); delayed?.let(main::removeCallbacks)
        main.removeCallbacksAndMessages(null); hits = emptyList()
        executor.shutdownNow()
    }
}
