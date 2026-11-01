package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.Parcelable
import android.text.InputFilter
import android.text.TextWatcher
import android.text.Editable
import android.view.Gravity
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import java.util.concurrent.Executors

/** Separate navigation preserves the original reader/filter/anchor while search owns its paged results. */
class AttentionNewsSearchActivity : Activity() {
    private val queries = Executors.newSingleThreadExecutor()
    private val actions = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val articles by lazy { AttentionArticleStore(applicationContext) }
    private val repository by lazy { GlobalAgentRepository(applicationContext) }
    private val preferences by lazy { ProactiveAttentionStore(applicationContext) }
    private lateinit var input: EditText
    private lateinit var clear: ImageButton
    private lateinit var scopeButton: TextView
    private lateinit var sourceButton: TextView
    private lateinit var timeButton: TextView
    private lateinit var sortButton: TextView
    private lateinit var count: TextView
    private lateinit var status: TextView
    private lateinit var list: RecyclerView
    private lateinit var manager: LinearLayoutManager
    private lateinit var adapter: ProactiveAttentionFeedAdapter
    private var query = AttentionNewsQuery("")
    private var timeIndex = 0
    private var generation = 0
    private var signal: CancellationSignal? = null
    private var loading = false
    private var failed = false
    private var resumeLoading = false
    private var total = 0
    private var hits = emptyList<AttentionNewsHit>()
    private var searchState: AttentionNewsSearchState? = null
    private var expanded = ""
    private var sources = emptyList<String>()
    private var restoredLayout: Parcelable? = null
    private var restorePages = 1
    private val debounce = Runnable { restart() }
    private val timeLabels = intArrayOf(R.string.attention_search_time, R.string.attention_search_day,
        R.string.attention_search_week, R.string.attention_search_month)
    private val scopeLabels = intArrayOf(R.string.attention_search_all, R.string.attention_menu_unread, R.string.attention_menu_saved)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = getColor(R.color.page_bg)
        window.navigationBarColor = getColor(R.color.page_bg)
        if (savedInstanceState != null) {
            query = AttentionNewsQuery(savedInstanceState.getString("query").orEmpty(),
                AttentionNewsScope.entries.getOrElse(savedInstanceState.getInt("scope")) { AttentionNewsScope.ALL },
                savedInstanceState.getString("source").orEmpty(), savedInstanceState.getLong("since"),
                AttentionNewsSort.entries.getOrElse(savedInstanceState.getInt("sort")) { AttentionNewsSort.RELEVANCE },
                savedInstanceState.getLong("snapshot", System.currentTimeMillis()))
            timeIndex = savedInstanceState.getInt("time").coerceIn(0, 3)
            expanded = savedInstanceState.getString("expanded").orEmpty()
            restoredLayout = savedInstanceState.getParcelable("layout")
            restorePages = savedInstanceState.getInt("pages", 1).coerceAtLeast(1)
        }
        setContentView(layout())
        actions.execute {
            val loaded = runCatching { articles.searchSources() }.getOrDefault(emptyList())
            main.post { if (!isDestroyed) sources = loaded }
        }
        if (savedInstanceState == null) input.post {
            input.requestFocus()
            getSystemService(InputMethodManager::class.java).showSoftInput(input, InputMethodManager.SHOW_IMPLICIT)
        }
    }

    override fun onStart() {
        super.onStart()
        if (input.text.toString().trim() != query.text) restart()
        else if (query.text.isNotBlank() && hits.isEmpty()) restart(preserve = true)
        else if (resumeLoading) loadPage()
        resumeLoading = false
    }
    override fun onStop() {
        resumeLoading = loading
        main.removeCallbacks(debounce); signal?.cancel(); generation++; loading = false
        super.onStop()
    }
    override fun onDestroy() {
        main.removeCallbacksAndMessages(null); signal?.cancel(); queries.shutdownNow(); actions.shutdown()
        super.onDestroy()
    }
    override fun onSaveInstanceState(out: Bundle) {
        out.putString("query", input.text.toString()); out.putInt("scope", query.scope.ordinal)
        out.putString("source", query.source); out.putLong("since", query.since); out.putInt("sort", query.sort.ordinal)
        out.putLong("snapshot", query.snapshot); out.putInt("time", timeIndex); out.putString("expanded", expanded)
        out.putParcelable("layout", manager.onSaveInstanceState())
        out.putInt("pages", (hits.size + AttentionNewsSearchPolicy.PAGE_SIZE - 1) / AttentionNewsSearchPolicy.PAGE_SIZE)
        super.onSaveInstanceState(out)
    }

    private fun layout() = column().apply {
        setBackgroundColor(getColor(R.color.page_bg))
        addView(line().apply {
            addView(icon(R.drawable.ic_navigation_back, android.R.string.cancel) { finish() })
            val field = line().apply {
                background = getDrawable(R.drawable.search_background)
                addView(icon(R.drawable.ic_hub_search, R.string.attention_search_title) { submit() }.apply {
                    isFocusable = false
                })
                input = EditText(this@AttentionNewsSearchActivity).apply {
                    tag = "attention-search-input"; textSize = 16f
                    hint = getString(R.string.attention_search_hint); setSingleLine(true)
                    setTextColor(getColor(R.color.text_primary)); setHintTextColor(getColor(R.color.text_secondary))
                    setBackgroundColor(Color.TRANSPARENT); setPadding(0, 0, 0, 0)
                    filters = arrayOf(InputFilter.LengthFilter(AttentionNewsSearchPolicy.MAX_QUERY))
                    imeOptions = EditorInfo.IME_ACTION_SEARCH
                    inputType = android.text.InputType.TYPE_CLASS_TEXT
                    setText(query.text)
                    setOnEditorActionListener { _, action, _ ->
                        if (action == EditorInfo.IME_ACTION_SEARCH) { submit(); true } else false
                    }
                    addTextChangedListener(object : TextWatcher {
                        override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
                        override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                            invalidateQuery()
                            clear.visibility = if (s.isNullOrEmpty()) View.GONE else View.VISIBLE
                            main.postDelayed(debounce, 250)
                        }
                        override fun afterTextChanged(s: Editable?) = Unit
                    })
                }
                addView(input, LinearLayout.LayoutParams(0, dp(44), 1f))
                clear = icon(R.drawable.ic_agent_progress_close, R.string.attention_search_clear) { input.setText("") }.apply {
                    tag = "attention-search-clear"; visibility = if (query.text.isEmpty()) View.GONE else View.VISIBLE
                }
                addView(clear)
            }
            addView(field, LinearLayout.LayoutParams(0, dp(44), 1f))
            addView(label(getString(android.R.string.cancel), 15f).apply {
                gravity = Gravity.CENTER; setPadding(dp(10), 0, dp(10), 0)
                tag = "attention-search-cancel"; setOnClickListener { finish() }
            }, LinearLayout.LayoutParams(-2, dp(48)))
        }, LinearLayout.LayoutParams(-1, dp(56)))
        addView(line().apply {
            scopeButton = dropdown("attention-search-scope") { chooseScope() }
            sourceButton = dropdown("attention-search-source") { chooseSource() }
            timeButton = dropdown("attention-search-time") { chooseTime() }
            listOf(scopeButton, sourceButton, timeButton).forEach { addView(it, LinearLayout.LayoutParams(0, dp(48), 1f)) }
        })
        addView(separator())
        addView(line().apply {
            setPadding(dp(16), 0, dp(8), 0)
            count = label("", 12f).apply {
                tag = "attention-search-count"; setTextColor(getColor(R.color.text_secondary))
                setOnClickListener { if (failed) loadPage() }
            }
            addView(count, LinearLayout.LayoutParams(0, dp(44), 1f))
            sortButton = dropdown("attention-search-sort") { chooseSort() }
            addView(sortButton, LinearLayout.LayoutParams(-2, dp(44)))
        })
        status = label("", 14f).apply {
            gravity = Gravity.CENTER; minimumHeight = dp(64); tag = "attention-search-status"
            setOnClickListener { if (failed) { if (hits.isEmpty()) restart() else loadPage() } }
        }
        addView(status, LinearLayout.LayoutParams(-1, -2))
        manager = LinearLayoutManager(this@AttentionNewsSearchActivity)
        list = RecyclerView(this@AttentionNewsSearchActivity).apply {
            layoutManager = manager; itemAnimator = null; tag = "attention-search-results"
            addOnScrollListener(object : RecyclerView.OnScrollListener() {
                override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                    if (dy > 0 && !loading && !failed && hits.size < total &&
                        manager.findLastVisibleItemPosition() >= hits.size - 5) loadPage()
                }
                override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                    if (newState == RecyclerView.SCROLL_STATE_DRAGGING) hideKeyboard()
                }
            })
        }
        installAdapter()
        addView(list, LinearLayout.LayoutParams(-1, 0, 1f))
        renderControls()
    }

    private fun installAdapter() {
        val text = query.text
        adapter = ProactiveAttentionFeedAdapter {
            ProactiveAttentionArticleView(this, ::toggle, ::save, ::ask, ::source,
                { _, callback -> callback(null) }, ::headlineAction,
                loadArticle = { id, full, callback ->
                    actions.execute {
                        val value = runCatching { articles.presentation(id, full) }.getOrNull()
                        main.post { if (!isDestroyed) callback(value) }
                    }
                }, searchQuery = text)
        }
        list.adapter = adapter
    }
    private fun invalidateQuery() {
        main.removeCallbacks(debounce); signal?.cancel(); generation++; loading = false
    }
    private fun restart(preserve: Boolean = false) {
        invalidateQuery()
        query = query.copy(text = input.text.toString().trim(), snapshot = if (preserve) query.snapshot else System.currentTimeMillis())
        if (!preserve) { expanded = ""; restoredLayout = null; restorePages = 1 }
        hits = emptyList(); total = 0; searchState = null; failed = false
        count.text = ""
        installAdapter(); renderControls()
        if (query.text.isBlank()) { count.text = ""; status.visibility = View.GONE; return }
        loadPage()
    }
    private fun submit() { hideKeyboard(); restart() }
    private fun loadPage() {
        if (loading || query.text.isBlank() || isDestroyed) return
        loading = true; failed = false
        val request = ++generation
        val cancel = CancellationSignal().also { signal?.cancel(); signal = it }
        val spec = query
        val offset = hits.size
        val cached = searchState
        status.text = getString(R.string.attention_search_loading)
        status.visibility = if (hits.isEmpty()) View.VISIBLE else View.GONE
        queries.execute {
            val result = runCatching {
                val state = cached ?: repository.newsSearchState(preferences.preferences().savedKeys, cancel)
                articles.search(spec, state, offset, cancel) to state
            }
            main.post {
                if (isDestroyed || request != generation || cancel.isCanceled) return@post
                loading = false
                result.onSuccess { (page, state) ->
                    searchState = state; total = page.total
                    hits = (hits + page.hits).distinctBy { it.id }
                    publish()
                    count.text = getString(R.string.attention_search_count, total)
                    status.text = getString(R.string.attention_search_empty)
                    status.visibility = if (hits.isEmpty()) View.VISIBLE else View.GONE
                    val wanted = restorePages * AttentionNewsSearchPolicy.PAGE_SIZE
                    if (hits.size < wanted && page.hasMore) loadPage()
                    else { restoredLayout?.let(manager::onRestoreInstanceState); restoredLayout = null; restorePages = 1 }
                }.onFailure {
                    failed = true
                    status.text = getString(R.string.attention_search_error) + " · " + getString(R.string.attention_search_retry)
                    status.visibility = if (hits.isEmpty()) View.VISIBLE else View.GONE
                    if (hits.isNotEmpty()) count.text = status.text
                }
            }
        }
    }
    private fun publish() = adapter.submit(hits.map { AttentionReaderRow(it.item(), it.id == expanded, it.saved) })

    private fun toggle(key: String) {
        hideKeyboard()
        val id = hits.firstOrNull { AttentionNewsSearchState.itemKey(it.id) == key }?.id ?: return
        val anchor = manager.findFirstVisibleItemPosition()
        val top = manager.findViewByPosition(anchor)?.top ?: 0
        expanded = if (expanded == id) "" else id
        publish()
        if (anchor >= 0) manager.scrollToPositionWithOffset(anchor, top)
        if (expanded == id) markRead(id)
    }
    private fun markRead(id: String) {
        actions.execute {
            val at = System.currentTimeMillis()
            val result = runCatching { repository.markProactiveViewed(setOf("attention-feed:$id"), at) }
            main.post { if (!isDestroyed) result.onSuccess {
                hits = hits.map { if (it.id == id) it.copy(viewed = at) else it }; publish()
                GlobalProactiveDeliveryBus.signalReady()
            }.onFailure { error() } }
        }
    }
    private fun save(key: String) {
        val hit = hits.firstOrNull { AttentionNewsSearchState.itemKey(it.id) == key } ?: return
        val desired = !hit.saved
        actions.execute {
            val result = runCatching { preferences.update { it.copy(savedKeys =
                if (desired) it.savedKeys + key else it.savedKeys - key) } }
            main.post { if (!isDestroyed) result.onSuccess {
                hits = hits.map { if (it.id == hit.id) it.copy(saved = desired) else it }; publish()
                searchState = searchState?.copy(saved = it.savedKeys)
                GlobalProactiveDeliveryBus.signalReady()
            }.onFailure { error() } }
        }
    }
    private fun headlineAction(item: GlobalProactiveInboxItem, action: AttentionHeadlineAction) {
        when (action) {
            AttentionHeadlineAction.READ -> markRead(item.newsArticleKey)
            AttentionHeadlineAction.NOT_RELEVANT -> actions.execute {
                val result = runCatching { GlobalSuperAgentRuntime.get(applicationContext)
                    .recordProactiveFeedback(item.key, GlobalAgentFeedbackKind.NOT_RELEVANT) }
                main.post { if (!isDestroyed) result.onSuccess { restart() }.onFailure { error() } }
            }
            else -> Unit
        }
    }
    private fun source(item: GlobalProactiveInboxItem) {
        val url = hits.firstOrNull { it.id == item.newsArticleKey }?.url ?: return
        val uri = Uri.parse(url)
        if (uri.scheme in setOf("http", "https")) runCatching { startActivity(Intent(Intent.ACTION_VIEW, uri)) }.onFailure { error() }
    }
    private fun ask(item: GlobalProactiveInboxItem) {
        actions.execute {
            val result = runCatching {
                val id = item.newsArticleKey
                val message = requireNotNull(repository.proactiveMessage("attention-feed:$id"))
                message.deliveredConversationId.ifBlank {
                    val transcript = AgentTranscriptStore(applicationContext)
                    val conversation = transcript.createAgentConversation(message.title)
                    transcript.append(AgentTranscriptRole.ASSISTANT, articles.body(id) ?: message.content,
                        "global-agent:" + message.id, timestampMillis = message.createdAtMillis, conversationId = conversation.id)
                    repository.bindProactiveConversation(message.id, conversation.id)
                    conversation.id
                }
            }
            main.post { if (!isDestroyed) result.onSuccess { id ->
                startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    .putExtra("galaxyssi_open_agent", true).putExtra("galaxyssi_agent_conversation_id", id))
                finish()
            }.onFailure { error() } }
        }
    }

    private fun chooseScope() = choices(R.string.attention_search_all, scopeLabels.map(::getString), query.scope.ordinal) {
        query = query.copy(scope = AttentionNewsScope.entries[it]); restart()
    }
    private fun chooseSource() {
        val values = listOf("") + (sources + query.source).filter(String::isNotBlank).distinct().sorted()
        choices(R.string.attention_search_source_filter, values.map { it.ifBlank { getString(R.string.attention_search_sources) } },
            values.indexOf(query.source).coerceAtLeast(0)) { query = query.copy(source = values[it]); restart() }
    }
    private fun chooseTime() = choices(R.string.attention_search_time_filter, timeLabels.map(::getString), timeIndex) {
        timeIndex = it
        val days = intArrayOf(0, 1, 7, 30)[it]
        query = query.copy(since = if (days == 0) 0 else System.currentTimeMillis() - days * 86_400_000L); restart()
    }
    private fun chooseSort() = choices(R.string.attention_search_sort,
        listOf(getString(R.string.attention_search_relevance), getString(R.string.attention_search_newest)), query.sort.ordinal) {
        query = query.copy(sort = AttentionNewsSort.entries[it]); restart()
    }
    private fun choices(title: Int, values: List<String>, selected: Int, action: (Int) -> Unit) {
        hideKeyboard()
        AlertDialog.Builder(this).setTitle(title).setSingleChoiceItems(values.toTypedArray(), selected) { dialog, which ->
            dialog.dismiss(); action(which)
        }.setNegativeButton(android.R.string.cancel, null).show()
    }
    private fun renderControls() {
        scopeButton.text = getString(scopeLabels[query.scope.ordinal])
        sourceButton.text = query.source.ifBlank { getString(R.string.attention_search_sources) }
        timeButton.text = getString(timeLabels[timeIndex])
        sortButton.text = getString(if (query.sort == AttentionNewsSort.RELEVANCE) R.string.attention_search_relevance else R.string.attention_search_newest)
    }
    private fun dropdown(tagName: String, click: () -> Unit) = label("", 13f).apply {
        tag = tagName; gravity = Gravity.CENTER; maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END
        setPadding(dp(10), 0, dp(10), 0)
        val arrow = getDrawable(R.drawable.ic_chevron_down)?.mutate()?.apply {
            setTint(getColor(R.color.text_secondary)); setBounds(0, 0, dp(16), dp(16))
        }
        setCompoundDrawablesRelative(null, null, arrow, null); compoundDrawablePadding = dp(4)
        setOnClickListener { click() }
    }
    private fun icon(resource: Int, description: Int, click: () -> Unit) = ImageButton(this).apply {
        setImageResource(resource); contentDescription = getString(description); tooltipText = contentDescription
        imageTintList = ColorStateList.valueOf(getColor(R.color.text_primary))
        setBackgroundColor(Color.TRANSPARENT); setPadding(dp(13), dp(13), dp(13), dp(13))
        layoutParams = LinearLayout.LayoutParams(dp(44), dp(44)); setOnClickListener { click() }
    }
    private fun column() = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
    private fun line() = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
    private fun label(value: String, size: Float) = TextView(this).apply {
        text = value; textSize = size; gravity = Gravity.CENTER_VERTICAL; setTextColor(getColor(R.color.text_primary))
    }
    private fun separator() = View(this).apply {
        setBackgroundColor(getColor(R.color.separator)); layoutParams = LinearLayout.LayoutParams(-1, dp(1))
    }
    private fun hideKeyboard() { getSystemService(InputMethodManager::class.java).hideSoftInputFromWindow(input.windowToken, 0); input.clearFocus() }
    private fun error() = Toast.makeText(this, R.string.attention_error, Toast.LENGTH_SHORT).show()
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
