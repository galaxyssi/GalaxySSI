package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import java.util.concurrent.ExecutorService
import org.json.JSONObject

internal class ProactiveAttentionReader(
    private val activity: Activity,
    private val worker: ExecutorService,
    private val ask: (GlobalProactiveInboxItem) -> Unit,
    private val sources: (GlobalProactiveInboxItem) -> Unit,
    private val evidence: (GlobalProactiveInboxItem, (JSONObject?) -> Unit) -> Unit,
    private val refresh: () -> Unit,
    storageContext: Context = activity
) {
    val timeline = ProactiveAttentionTimeline()
    private val main = Handler(Looper.getMainLooper())
    private val stateStore = ProactiveAttentionReaderStateStore(storageContext)
    private val attention = ProactiveAttentionStore(storageContext)
    private val repository = GlobalAgentRepository(storageContext)
    private val runtime = GlobalSuperAgentRuntime.get(activity)
    private val dwell = AttentionReadDwell()
    private var initialized = false
    private var active = false
    private var olderQueued = false
    private var saved = emptySet<String>()
    private val pendingSaves = mutableMapOf<String, Boolean>()
    private val pendingReads = mutableSetOf<String>()
    private val filters = listOf(AttentionFeedFilter.ALL, AttentionFeedFilter.UNREAD, AttentionFeedFilter.SAVED)
    private val tabs = mutableListOf<TextView>()
    private val tabLines = mutableListOf<View>()
    private val manager = LinearLayoutManager(activity)
    private val adapter = ProactiveAttentionFeedAdapter { ProactiveAttentionArticleView(activity,
        ::toggle, ::toggleSaved, ask, sources, evidence, ::menu) }
    val list = RecyclerView(activity).apply {
        layoutManager = manager; adapter = this@ProactiveAttentionReader.adapter; itemAnimator = null
        tag = "attention-reader-list"
    }
    private val notice = text(11f).apply {
        gravity = Gravity.END or Gravity.CENTER_VERTICAL; setPadding(dp(18), 0, dp(18), 0)
        setTextColor(activity.getColor(R.color.text_secondary)); tag = "attention-reader-updates"
        setOnClickListener { loadNewer(); refresh() }
    }
    private val empty = text(14f).apply {
        text = activity.getString(R.string.attention_loading); gravity = Gravity.CENTER
    }
    private val undo = LinearLayout(activity).apply {
        orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(16), 0, dp(8), 0); setBackgroundColor(activity.getColor(R.color.text_primary)); visibility = View.GONE
    }
    private val dismissUndo = Runnable { undo.visibility = View.GONE }
    val view = LinearLayout(activity).apply {
        orientation = LinearLayout.VERTICAL
        val bar = LinearLayout(activity).apply { orientation = LinearLayout.HORIZONTAL }
        filters.forEach { filter ->
            val tab = text(14f).apply {
                gravity = Gravity.CENTER; minimumHeight = dp(44); tag = "attention-filter:${filter.name}"
                maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END
                text = activity.getString(when (filter) {
                    AttentionFeedFilter.ALL -> R.string.attention_all
                    AttentionFeedFilter.UNREAD -> R.string.attention_unread
                    else -> R.string.attention_saved
                })
                setOnClickListener {
                    dwell.reset(); timeline.begin(filter); timeline.expanded.clear()
                    publish(); manager.scrollToPositionWithOffset(0, 0)
                    persistAt(timeline.visible.firstOrNull()?.key.orEmpty(), 0)
                }
            }
            val line = View(activity).apply {
                setBackgroundColor(activity.getColor(R.color.galaxyssi_green)); visibility = View.INVISIBLE
            }
            tabs += tab; tabLines += line
            bar.addView(LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL; addView(tab, LinearLayout.LayoutParams(-1, dp(44)))
                addView(line, LinearLayout.LayoutParams(dp(40), dp(2)).apply { gravity = Gravity.CENTER_HORIZONTAL })
            }, LinearLayout.LayoutParams(0, -2, 1f))
        }
        addView(bar); addView(notice, LinearLayout.LayoutParams(-1, dp(24)))
        addView(empty, LinearLayout.LayoutParams(-1, dp(80)))
        addView(list, LinearLayout.LayoutParams(-1, 0, 1f))
        addView(undo, LinearLayout.LayoutParams(-1, dp(48)))
    }

    private val settleReading = object : Runnable {
        override fun run() {
            if (activity.isDestroyed || !list.isAttachedToWindow || !view.isShown ||
                list.scrollState != RecyclerView.SCROLL_STATE_IDLE) return
            if (list.isComputingLayout || list.hasPendingAdapterUpdates()) {
                list.postOnAnimation(this)
                return
            }
            val first = manager.findFirstVisibleItemPosition()
            val last = manager.findLastVisibleItemPosition()
            val anchor = adapter.rows.getOrNull(first)?.item?.key ?: return
            val offset = manager.findViewByPosition(first)?.top ?: return
            val viewport = (first..last).mapNotNull { adapter.rows.getOrNull(it)?.item?.key }.toSet()
            if (timeline.collapseOutsideViewport(viewport)) {
                // Shrinking an article above the viewport must not move the current text.
                publish()
                manager.scrollToPositionWithOffset(first, offset)
            }
            persistAt(anchor, offset)
        }
    }

    init {
        list.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                if (dy >= 0 && !olderQueued && manager.findLastVisibleItemPosition() >= adapter.itemCount - 6) {
                    olderQueued = true
                    list.post {
                        olderQueued = false
                        if (!activity.isDestroyed && manager.findLastVisibleItemPosition() >= adapter.itemCount - 6 &&
                            timeline.loadOlder()) publish()
                    }
                }
                if (dy < 0 && manager.findFirstVisibleItemPosition() <= 1) list.post { loadNewer() }
            }
            override fun onScrollStateChanged(recyclerView: RecyclerView, state: Int) {
                dwell.reset()
                list.removeCallbacks(settleReading)
                if (state == RecyclerView.SCROLL_STATE_IDLE) list.postOnAnimation(settleReading)
            }
        })
        var downY = 0f
        var fromTop = false
        list.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> { downY = event.y; fromTop = !list.canScrollVertically(-1); dwell.reset() }
                MotionEvent.ACTION_UP -> if (fromTop && event.y - downY > dp(40)) { loadNewer(); refresh() }
            }
            false
        }
    }

    fun update(items: List<GlobalProactiveInboxItem>, savedKeys: Set<String>, restored: AttentionReaderState) {
        saved = savedKeys.toMutableSet().apply { pendingSaves.forEach { (key, value) -> if (value) add(key) else remove(key) } }
        timeline.update(items, saved)
        if (!initialized) {
            initialized = true
            timeline.begin(restored.filter.takeIf { it in filters } ?: AttentionFeedFilter.ALL, restored.keys)
            timeline.expanded.addAll(restored.expanded.intersect(timeline.visible.map { it.key }.toSet()))
            publish()
            val index = timeline.visible.indexOfFirst { it.key == restored.anchor }
            if (index >= 0) manager.scrollToPositionWithOffset(index, restored.offset)
        } else publish()
    }

    private fun publish() {
        timeline.setSaved(saved)
        adapter.submit(timeline.visible.map { AttentionReaderRow(it, it.key in timeline.expanded, it.key in saved) })
        tabs.forEachIndexed { index, tab ->
            tab.text = when (filters[index]) {
                AttentionFeedFilter.ALL -> activity.getString(R.string.attention_all)
                AttentionFeedFilter.UNREAD -> activity.getString(R.string.attention_reader_unread, timeline.unreadCount)
                else -> activity.getString(R.string.attention_saved)
            }
            tab.isSelected = timeline.filter == filters[index]
            tab.setTextColor(activity.getColor(if (tab.isSelected) R.color.galaxyssi_green else R.color.text_secondary))
            tabLines[index].visibility = if (tab.isSelected) View.VISIBLE else View.INVISIBLE
        }
        notice.text = if (timeline.newerCount > 0) activity.getString(R.string.attention_reader_new, timeline.newerCount) else ""
        notice.isClickable = timeline.newerCount > 0
        empty.text = activity.getString(R.string.attention_empty)
        empty.visibility = if (timeline.visible.isEmpty()) View.VISIBLE else View.GONE
    }

    private fun loadNewer() {
        val position = manager.findFirstVisibleItemPosition()
        val key = adapter.rows.getOrNull(position)?.item?.key
        val offset = manager.findViewByPosition(position)?.top ?: 0
        if (!timeline.loadNewer()) return
        publish()
        val restored = timeline.visible.indexOfFirst { it.key == key }
        if (restored >= 0) manager.scrollToPositionWithOffset(restored, offset)
        persistAt(key.orEmpty(), offset)
    }

    private fun toggle(key: String) {
        val position = manager.findFirstVisibleItemPosition()
        val anchor = adapter.rows.getOrNull(position)?.item?.key.orEmpty()
        val collapsing = key in timeline.expanded
        val offset = (manager.findViewByPosition(position)?.top ?: 0).let {
            if (collapsing && anchor == key) it.coerceAtLeast(0) else it
        }
        if (collapsing) timeline.expanded.remove(key) else timeline.expanded.add(key)
        dwell.reset(); publish()
        if (position >= 0) manager.scrollToPositionWithOffset(position, offset)
        persistAt(anchor, offset)
    }

    private fun toggleSaved(key: String) = setSaved(key, key !in saved)
    private fun setSaved(key: String, value: Boolean) {
        pendingSaves[key] = value
        saved = if (value) saved + key else saved - key
        publish()
        worker.execute {
            val result = runCatching { attention.update { it.copy(savedKeys = if (value) it.savedKeys + key else it.savedKeys - key) } }
            main.post {
                if (activity.isDestroyed) return@post
                if (pendingSaves[key] == value) {
                    pendingSaves.remove(key)
                    result.onFailure { saved = if (value) saved - key else saved + key; publish(); error() }
                        .onSuccess { showUndo(value) { setSaved(key, !value) } }
                }
            }
        }
    }

    private fun showUndo(value: Boolean, action: () -> Unit) {
        main.removeCallbacks(dismissUndo); undo.removeAllViews()
        undo.addView(text(13f).apply {
            text = activity.getString(if (value) R.string.attention_saved_done else R.string.attention_unsaved_done)
            setTextColor(activity.getColor(R.color.surface_bg))
        }, LinearLayout.LayoutParams(0, -2, 1f))
        undo.addView(text(13f).apply {
            text = activity.getString(R.string.attention_undo); gravity = Gravity.CENTER
            setTextColor(activity.getColor(R.color.galaxyssi_green))
            setOnClickListener { undo.visibility = View.GONE; action() }
        }, LinearLayout.LayoutParams(dp(64), dp(48)))
        undo.visibility = View.VISIBLE; main.postDelayed(dismissUndo, 4_000)
    }

    private fun menu(item: GlobalProactiveInboxItem) {
        AlertDialog.Builder(activity).setItems(arrayOf(activity.getString(R.string.attention_read),
            activity.getString(R.string.agent_global_feedback_not_relevant))) { _, which ->
            if (which == 0) markRead(setOf(item.key)) else worker.execute {
                val result = runCatching { runtime.recordProactiveFeedback(item.key, GlobalAgentFeedbackKind.NOT_RELEVANT) }
                main.post { if (!activity.isDestroyed) result.onSuccess { timeline.remove(item.key); publish(); refresh() }.onFailure { error() } }
            }
        }.show()
    }

    private val readTick = object : Runnable {
        override fun run() {
            if (!active) return
            val enabled = view.isShown && activity.hasWindowFocus() && list.scrollState == RecyclerView.SCROLL_STATE_IDLE
            val visible = mutableSetOf<String>()
            if (enabled) for (index in 0 until list.childCount) {
                val row = list.getChildAt(index) as? ProactiveAttentionArticleView ?: continue
                val item = row.currentItem ?: continue
                val rect = Rect()
                if (item.isNew && item.key !in pendingReads && row.readable.getGlobalVisibleRect(rect) &&
                    rect.height() >= row.readable.height * .85f) visible += item.key
            }
            val ready = dwell.sample(visible, SystemClock.elapsedRealtime(), enabled)
            if (ready.isNotEmpty()) markRead(ready)
            main.postDelayed(this, 250)
        }
    }

    private fun markRead(keys: Set<String>) {
        val selected = timeline.visible.filter { it.key in keys && it.key !in pendingReads && it.isNew }
        if (selected.isEmpty()) return
        val marking = selected.mapTo(hashSetOf()) { it.key }
        pendingReads += marking
        worker.execute {
            val result = runCatching { repository.markProactiveViewed(selected.flatMapTo(hashSetOf()) { it.messageIds }, System.currentTimeMillis()) }
            main.post {
                pendingReads.removeAll(marking)
                if (activity.isDestroyed) return@post
                result.onSuccess {
                    timeline.markRead(marking, System.currentTimeMillis()); publish(); GlobalProactiveDeliveryBus.signalReady()
                }.onFailure { dwell.reset(); error() }
            }
        }
    }

    fun resume() { if (!active) { active = true; dwell.reset(); main.post(readTick) } }
    fun pause() { active = false; dwell.reset(); main.removeCallbacks(readTick); list.removeCallbacks(settleReading); persist() }
    fun destroy() { active = false; main.removeCallbacksAndMessages(null); list.removeCallbacks(settleReading) }
    fun persist() {
        if (!initialized || activity.isDestroyed) return
        val position = manager.findFirstVisibleItemPosition()
        if (position < 0 && timeline.visible.isNotEmpty()) return
        persistAt(adapter.rows.getOrNull(position)?.item?.key.orEmpty(), manager.findViewByPosition(position)?.top ?: 0)
    }
    private fun persistAt(anchor: String, offset: Int) {
        if (!initialized || activity.isDestroyed) return
        val state = AttentionReaderState(timeline.filter, timeline.visible.map { it.key }, timeline.expanded.toSet(), anchor, offset)
        worker.execute { runCatching { stateStore.write(state) } }
    }
    private fun error() = Toast.makeText(activity, R.string.attention_error, Toast.LENGTH_SHORT).show()
    private fun text(size: Float) = TextView(activity).apply { textSize = size; setTextColor(activity.getColor(R.color.text_primary)) }
    private fun dp(value: Int) = (value * activity.resources.displayMetrics.density).toInt()
}
