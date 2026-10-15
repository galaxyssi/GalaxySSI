package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.widget.CheckBox
import android.widget.EditText
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import java.util.concurrent.Executors
import org.json.JSONObject

class ProactiveAttentionActivity : Activity() {
    private val worker = Executors.newSingleThreadExecutor()
    private lateinit var store: ProactiveAttentionStore
    private lateinit var runtime: GlobalSuperAgentRuntime
    private lateinit var body: LinearLayout
    private lateinit var scroll: ScrollView
    private lateinit var reader: ProactiveAttentionReader
    private lateinit var readerStateStore: ProactiveAttentionReaderStateStore
    private var readerState = AttentionReaderState()
    private lateinit var title: TextView
    private lateinit var trailing: ImageButton
    private var preferences = AttentionPreferences()
    private var items = emptyList<GlobalProactiveInboxItem>()
    private var messages = emptyMap<String, GlobalProactiveMessage>()
    private val evidence = android.util.LruCache<String, JSONObject>(64)
    private var tasks = emptyList<GlobalResearchTask>()
    private var feedLastPoll = 0L
    private var settingsPage = false
    private var revision = 0
    private var reloadRunning = false
    private var reloadQueued = false
    private var started = false
    private var collectionRequested = false
    private val pageHistory = mutableListOf<Boolean>()
    private val listener = GlobalProactiveDeliveryListener { runOnUiThread { if (started) reload() } }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        settingsPage = savedInstanceState?.getBoolean("settings") ?: intent.getBooleanExtra("settings", false)
        savedInstanceState?.getBooleanArray("pages")?.forEach(pageHistory::add)
        readerStateStore = ProactiveAttentionReaderStateStore(applicationContext)
        store = ProactiveAttentionStore(applicationContext)
        runtime = GlobalSuperAgentRuntime.get(applicationContext)
        window.statusBarColor = getColor(R.color.page_bg)
        window.navigationBarColor = getColor(R.color.page_bg)
        setContentView(layout())
    }

    override fun onStart() { super.onStart(); started = true; GlobalProactiveDeliveryBus.addListener(listener); reload() }
    override fun onStop() { started = false; GlobalProactiveDeliveryBus.removeListener(listener); super.onStop() }
    override fun onResume() { super.onResume(); reader.resume() }
    override fun onPause() { reader.pause(); super.onPause() }
    override fun onDestroy() { reader.destroy(); worker.shutdown(); super.onDestroy() }
    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean("settings", settingsPage)
        outState.putBooleanArray("pages", pageHistory.toBooleanArray())
        reader.persist()
        super.onSaveInstanceState(outState)
    }

    @Deprecated("Uses the existing Activity navigation contract")
    override fun onBackPressed() {
        if (pageHistory.isNotEmpty()) { settingsPage = pageHistory.removeAt(pageHistory.lastIndex); render() }
        else super.onBackPressed()
    }

    private fun navigate(settings: Boolean) {
        if (!settingsPage) reader.persist()
        pageHistory += settingsPage; settingsPage = settings; render(resetScroll = true)
    }

    private fun layout() = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setBackgroundColor(getColor(R.color.page_bg))
        val bar = horizontal()
        bar.setBackgroundColor(getColor(R.color.surface_bg))
        bar.addView(icon(R.drawable.ic_navigation_back, android.R.string.cancel) { onBackPressed() })
        title = text(getString(if (settingsPage) R.string.attention_title else R.string.attention_discoveries), 18f, true)
            .apply { gravity = Gravity.CENTER }
        bar.addView(title, LinearLayout.LayoutParams(0, dp(56), 1f))
        trailing = icon(R.drawable.ic_tab_settings, R.string.attention_title) {
            if (settingsPage) editTopic(null) else navigate(true)
        }
        bar.addView(trailing)
        addView(bar)
        body = LinearLayout(this@ProactiveAttentionActivity).apply { orientation = LinearLayout.VERTICAL }
        scroll = ScrollView(this@ProactiveAttentionActivity).apply { isFillViewport = true; addView(body) }
        scroll.visibility = if (settingsPage) View.VISIBLE else View.GONE
        addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
        reader = ProactiveAttentionReader(this@ProactiveAttentionActivity, worker, ::open, ::showSources, ::loadEvidence, ::reload)
        reader.view.visibility = if (settingsPage) View.GONE else View.VISIBLE
        addView(reader.view, LinearLayout.LayoutParams(-1, 0, 1f))
    }

    private fun reload() {
        if (reloadRunning) { reloadQueued = true; return }
        reloadRunning = true
        val request = ++revision
        worker.execute {
            val loaded = runCatching {
                val p = store.preferences()
                if (p.configured && p.enabled && !collectionRequested) {
                    collectionRequested = true
                    ProactiveAttentionFeedScheduler.request(applicationContext)
                    ProactiveAttentionTitleScheduler.request(applicationContext)
                }
                val repository = GlobalAgentRepository(applicationContext)
                val messageMap = repository.proactiveMessages().associateBy(GlobalProactiveMessage::id)
                val inbox = GlobalProactiveInboxPolicy.project(messageMap.values.toList(), repository.feedback())
                Triple(p, ProactiveAttentionTitleStore(applicationContext).decorate(inbox), messageMap)
            }
            val savedReaderState = readerStateStore.read()
            val research = runCatching { runtime.researchTasks().filter(ProactiveAttentionPolicy::isAttention) }.getOrDefault(emptyList())
            val lastPoll = runCatching {
                val feed = ProactiveAttentionFeedStore(applicationContext)
                store.preferences().topics.filter { it.enabled }.map { feed.topicState(it.id) }
                    .filter { it.optString("error").isBlank() }.maxOfOrNull { it.optLong("at") } ?: 0L
            }.getOrDefault(0L)
            runOnUiThread {
                reloadRunning = false
                if (isDestroyed || request != revision) return@runOnUiThread
                loaded.onSuccess { (p, inbox, metadata) ->
                    preferences = p; items = inbox; messages = metadata
                    readerState = savedReaderState
                    evidence.evictAll()
                    tasks = research
                    feedLastPoll = lastPoll
                    render()
                }.onFailure {
                    reader.view.visibility = View.GONE
                    scroll.visibility = View.VISIBLE
                    body.removeAllViews()
                    body.addView(row(getString(R.string.attention_error)) { reload() })
                }
                if (reloadQueued) { reloadQueued = false; reload() }
            }
        }
    }

    private fun mutate(reschedule: Boolean = true, transform: (AttentionPreferences) -> AttentionPreferences) {
        worker.execute {
            runCatching {
                val before = store.preferences()
                val next = store.update(transform)
                ProactiveAttentionPush.refresh()
                if (next.configured && next.enabled && (!before.configured || !before.enabled)) runtime.updateSettings { it.copy(
                    enabled = true, proactiveInsightsEnabled = true, autonomousResearchEnabled = true,
                    autoCreateConversationsEnabled = true
                ) }
                if (reschedule) {
                    ProactiveAttentionCoordinator(applicationContext).reconcile()
                    if (next.configured && next.enabled) {
                        ProactiveAttentionFeedScheduler.request(applicationContext)
                        ProactiveAttentionTitleScheduler.request(applicationContext)
                        AndroidCognitionScheduler.scheduleAt(applicationContext, System.currentTimeMillis())
                    } else AndroidCognitionScheduler.scheduleDynamic(applicationContext, runtime)
                }
            }.onFailure { runOnUiThread { toast(R.string.attention_error) } }
            runOnUiThread { if (!isDestroyed) reload() }
        }
    }

    private fun render(resetScroll: Boolean = false) {
        val previousScroll = if (resetScroll) 0 else scroll.scrollY
        title.setText(if (settingsPage) R.string.attention_title else R.string.attention_discoveries)
        trailing.setImageResource(if (settingsPage) android.R.drawable.ic_input_add else R.drawable.ic_tab_settings)
        trailing.contentDescription = getString(if (settingsPage) R.string.attention_add else R.string.attention_title)
        scroll.visibility = if (settingsPage) View.VISIBLE else View.GONE
        reader.view.visibility = if (settingsPage) View.GONE else View.VISIBLE
        body.removeAllViews()
        if (settingsPage) renderSettings() else reader.update(items, preferences.savedKeys, readerState)
        scroll.post { if (!isDestroyed) scroll.scrollTo(0, previousScroll) }
    }

    private fun renderSettings() {
        body.addView(row(getString(R.string.attention_view), getString(R.string.attention_unread_entry, items.count { it.isNew })) { navigate(false) })
        val enabled = Switch(this).apply {
            isChecked = preferences.configured && preferences.enabled
            contentDescription = getString(R.string.attention_collection)
            setOnCheckedChangeListener { _, checked ->
                mutate { it.copy(configured = true, enabled = checked) }
                if (checked && android.os.Build.VERSION.SDK_INT >= 33 &&
                    checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                    requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 45)
                }
            }
        }
        val header = row(getString(R.string.attention_collection), getString(R.string.attention_count, preferences.topics.count { it.enabled }))
        header.addView(enabled)
        body.addView(header)
        body.addView(segments(AttentionAlertMode.entries.map { getString(modeLabel(it)) }, preferences.alertMode.ordinal) { index ->
            mutate { it.copy(alertMode = AttentionAlertMode.entries[index]) }
        })
        var lastGroup: AttentionTopicGroup? = null
        preferences.topics.forEach { topic ->
            val group = ProactiveAttentionPolicy.group(topic.id)
            if (group != lastGroup) {
                body.addView(text(getString(groupLabel(group)), 14f, true).apply {
                    setPadding(dp(18), dp(22), dp(18), dp(10)); tag = "attention-group:${group.name}"
                })
                lastGroup = group
            }
            val line = horizontal().apply { setPadding(dp(12), 0, dp(10), 0); minimumHeight = dp(50) }
            val checkbox = CheckBox(this).apply {
                isChecked = topic.enabled; contentDescription = topic.title; tag = "attention-topic:${topic.id}"
                buttonTintList = android.content.res.ColorStateList.valueOf(getColor(R.color.galaxyssi_green))
                setOnCheckedChangeListener { _, checked -> mutate { state -> state.copy(topics = state.topics.map {
                    if (it.id == topic.id) it.copy(enabled = checked) else it
                }) } }
            }
            line.addView(checkbox, LinearLayout.LayoutParams(dp(44), dp(48)))
            line.addView(text(topic.title, 15f).apply { setOnClickListener { editTopic(topic) } }, LinearLayout.LayoutParams(0, -2, 1f))
            if (topic.id == "portfolio") line.addView(text(getString(R.string.attention_not_connected), 11f))
            line.addView(icon(R.drawable.ic_chevron_down, R.string.attention_edit) { editTopic(topic) }.apply { rotation = -90f })
            body.addView(line); divider()
        }
        body.addView(row("+ ${getString(R.string.attention_add)}") { editTopic(null) })
        body.addView(row(getString(R.string.attention_models), status()) { models() })
        body.addView(row(getString(R.string.attention_notifications)) {
            startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
        })
    }

    private fun open(item: GlobalProactiveInboxItem) {
        worker.execute {
            val repository = GlobalAgentRepository(applicationContext)
            val message = item.messageIds.firstNotNullOfOrNull(repository::proactiveMessage)
            var destination = message?.deliveredConversationId ?: item.destinationConversationId
            if (destination.isBlank() && message?.id?.startsWith("attention-feed:") == true) {
                val transcript = AgentTranscriptStore(applicationContext)
                val conversation = transcript.createAgentConversation(message.title)
                transcript.append(AgentTranscriptRole.ASSISTANT, message.content, "global-agent:" + message.id,
                    timestampMillis = message.createdAtMillis, conversationId = conversation.id)
                repository.bindProactiveConversation(message.id, conversation.id)
                destination = conversation.id
            }
            if (destination.isBlank()) return@execute
            runtime.markProactiveInboxViewed(item.messageIds)
            runOnUiThread {
                if (isDestroyed) return@runOnUiThread
                startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    .putExtra("galaxyssi_open_agent", true).putExtra("galaxyssi_agent_conversation_id", destination))
                finish()
            }
        }
    }

    private fun showSources(item: GlobalProactiveInboxItem) {
        loadEvidence(item) { showSourcesRecord(it) }
    }

    private fun loadEvidence(item: GlobalProactiveInboxItem, loaded: (JSONObject?) -> Unit) {
        evidence.get(item.key)?.let { loaded(it); return }
        val ids = item.messageIds.mapNotNull { messages[it]?.sourceEventId }
        worker.execute {
            val result = runCatching { ids.mapNotNull(store::evidence).lastOrNull() }.getOrNull()
            runOnUiThread {
                if (isDestroyed) return@runOnUiThread
                if (result != null) evidence.put(item.key, result)
                loaded(result)
            }
        }
    }

    private fun showSourcesRecord(record: JSONObject?) {
        val sources = record?.optJSONArray("sources")
        if (sources == null || sources.length() == 0) { toast(R.string.attention_source_unavailable); return }
        val rows = (0 until sources.length()).mapNotNull(sources::optJSONObject)
        if (rows.size == 1) { openSource(rows.single().optString("url")); return }
        AlertDialog.Builder(this).setTitle(R.string.attention_sources).setItems(rows.map { source ->
            source.optString("title") + "\n" + getString(R.string.attention_dates,
                source.optLong("published").takeIf { it > 0 }?.let(::date) ?: getString(R.string.attention_unknown_date), date(source.optLong("retrieved")))
        }.toTypedArray()) { _, index ->
            openSource(rows[index].optString("url"))
        }.setNegativeButton(android.R.string.cancel, null).show()
    }

    private fun openSource(url: String) {
        val uri = Uri.parse(url)
        if (uri.scheme in setOf("http", "https")) runCatching { startActivity(Intent(Intent.ACTION_VIEW, uri)) }
            .onFailure { toast(R.string.attention_error) }
    }

    private fun editTopic(topic: AttentionTopic?) {
        val form = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(20), dp(8), dp(20), 0) }
        val name = EditText(this).apply { hint = getString(R.string.attention_name); setText(topic?.title.orEmpty()); maxLines = 2 }
        val query = EditText(this).apply { hint = getString(R.string.attention_query); setText(topic?.query.orEmpty()); minLines = 3; maxLines = 6 }
        form.addView(name); form.addView(query)
        val dialog = AlertDialog.Builder(this).setTitle(if (topic == null) R.string.attention_add else R.string.attention_edit)
            .setView(form).setNegativeButton(android.R.string.cancel, null).setPositiveButton(android.R.string.ok, null).create()
        dialog.setOnShowListener { dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
            val label = name.text.toString().trim().take(120); val scope = query.text.toString().trim().take(2000)
            if (label.isBlank() || scope.isBlank()) { toast(R.string.attention_invalid); return@setOnClickListener }
            val updated = AttentionTopic(topic?.id ?: UUID.randomUUID().toString(), label, scope, topic?.enabled ?: true)
            mutate { state -> state.copy(topics = if (topic == null) state.topics + updated else state.topics.map { if (it.id == topic.id) updated else it }) }
            dialog.dismiss()
        } }
        dialog.show()
    }

    private fun models() {
        val flags = booleanArrayOf(preferences.allowPairedModel, preferences.allowCloudModel)
        AlertDialog.Builder(this).setTitle(R.string.attention_models)
            .setMultiChoiceItems(arrayOf(getString(R.string.attention_paired), getString(R.string.attention_cloud)), flags) { _, i, value -> flags[i] = value }
            .setNegativeButton(android.R.string.cancel, null).setPositiveButton(android.R.string.ok) { _, _ ->
                worker.execute {
                    store.update { it.copy(allowPairedModel = flags[0], allowCloudModel = flags[1]) }
                    val repository = GlobalAgentRepository(applicationContext)
                    repository.researchTasks().filter { ProactiveAttentionPolicy.isAttention(it) &&
                        it.status in setOf(GlobalResearchTaskStatus.WAITING_FOR_RESOURCE, GlobalResearchTaskStatus.FAILED)
                    }.forEach { task -> repository.updateResearchTask(task.id) {
                        it.copy(status = GlobalResearchTaskStatus.QUEUED, nextAttemptAtMillis = 0L, attemptCount = 0)
                    } }
                    if (preferences.configured && preferences.enabled) {
                        AndroidCognitionScheduler.scheduleAt(applicationContext, System.currentTimeMillis())
                    } else AndroidCognitionScheduler.scheduleDynamic(applicationContext, runtime)
                    runOnUiThread { if (!isDestroyed) reload() }
                }
            }.show()
    }

    private fun status(): String {
        if (!preferences.configured || !preferences.enabled) return getString(R.string.attention_paused)
        val settings = runtime.cachedSettings()
        if (settings.enabled && feedLastPoll > 0) return getString(R.string.attention_updated, date(feedLastPoll)) +
            "\n" + getString(R.string.attention_feed_active)
        if (!settings.enabled || !settings.autonomousResearchEnabled ||
            (!preferences.allowPairedModel && !preferences.allowCloudModel)) return getString(R.string.attention_waiting)
        val active = tasks.filter { it.status != GlobalResearchTaskStatus.PAUSED }
        val running = active.count { it.status == GlobalResearchTaskStatus.RUNNING }
        if (running > 0) return getString(R.string.attention_researching, running)
        val waiting = active.firstOrNull { it.status == GlobalResearchTaskStatus.WAITING_FOR_RESOURCE }
        if (waiting != null) {
            val reason = when (waiting.lastError) {
                "background_budget:TOKEN_LIMIT" -> R.string.attention_token_wait
                "background_budget:REPORTED_COST_LIMIT" -> R.string.attention_cost_wait
                "background_budget:CONCURRENCY_LIMIT" -> R.string.attention_capacity_wait
                "attention_source_read_unavailable" -> R.string.attention_source_wait
                else -> R.string.attention_waiting
            }
            return getString(reason)
        }
        if (active.any { it.status == GlobalResearchTaskStatus.FAILED }) return getString(R.string.attention_failed)
        if (active.maxByOrNull { it.updatedAtMillis }?.lastError == "attention_no_supported_news") {
            return getString(R.string.attention_no_supported_news)
        }
        val last = active.maxOfOrNull { it.lastCompletedAtMillis } ?: 0L
        return if (last > 0) getString(R.string.attention_updated, date(last)) else getString(R.string.attention_ready, preferences.topics.count { it.enabled })
    }

    private fun modeLabel(mode: AttentionAlertMode) = when (mode) {
        AttentionAlertMode.IMPORTANT -> R.string.attention_alert_important
        AttentionAlertMode.ALL -> R.string.attention_alert_all
        AttentionAlertMode.SILENT -> R.string.attention_alert_silent
    }
    private fun groupLabel(group: AttentionTopicGroup) = when (group) {
        AttentionTopicGroup.FINANCE -> R.string.attention_finance
        AttentionTopicGroup.TECHNOLOGY -> R.string.attention_technology
        AttentionTopicGroup.GALAXYSSI -> R.string.attention_galaxyssi
        AttentionTopicGroup.RESEARCH -> R.string.attention_research
        AttentionTopicGroup.CUSTOM -> R.string.attention_custom
    }
    private fun segments(labels: List<String>, selected: Int, click: (Int) -> Unit) = horizontal().apply {
        setPadding(dp(12), dp(8), dp(12), dp(8))
        labels.forEachIndexed { i, label -> addView(text(label, 12f, i == selected).apply {
            setTextColor(getColor(if (i == selected) R.color.galaxyssi_green else R.color.text_secondary))
            gravity = Gravity.CENTER; minimumHeight = dp(48); isSelected = i == selected
            background = GradientDrawable().apply { cornerRadius = dp(5).toFloat(); setColor(getColor(if (i == selected) R.color.agent_insight_bg else R.color.surface_bg)) }
            setOnClickListener { click(i) }
        }, LinearLayout.LayoutParams(0, -2, 1f)) }
    }
    private fun row(label: String, subtitle: String = "", click: (() -> Unit)? = null) = horizontal().apply {
        setPadding(dp(18), dp(8), dp(14), dp(8)); minimumHeight = dp(52)
        val labels = LinearLayout(this@ProactiveAttentionActivity).apply {
            orientation = LinearLayout.VERTICAL; addView(text(label, 15f))
            if (subtitle.isNotBlank()) addView(text(subtitle, 12f))
        }
        addView(labels, LinearLayout.LayoutParams(0, -2, 1f))
        if (click != null) {
            addView(icon(R.drawable.ic_chevron_down, R.string.common_view, click).apply { rotation = -90f })
            setOnClickListener { click() }
        }
    }
    private fun horizontal() = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
    private fun text(value: String, size: Float, bold: Boolean = false) = TextView(this).apply {
        text = value; textSize = size; setTextColor(getColor(if (size <= 12) R.color.text_secondary else R.color.text_primary))
        if (bold) setTypeface(typeface, Typeface.BOLD)
    }
    private fun icon(resource: Int, description: Int, click: () -> Unit) = ImageButton(this).apply {
        setImageResource(resource); contentDescription = getString(description); tooltipText = contentDescription
        imageTintList = android.content.res.ColorStateList.valueOf(getColor(R.color.text_primary))
        setBackgroundColor(android.graphics.Color.TRANSPARENT); setPadding(dp(12), dp(12), dp(12), dp(12))
        layoutParams = LinearLayout.LayoutParams(dp(48), dp(48)); setOnClickListener { click() }
    }
    private fun divider() { body.addView(View(this).apply { setBackgroundColor(getColor(R.color.separator)) }, LinearLayout.LayoutParams(-1, dp(1))) }
    private fun date(time: Long) = if (time <= 0L) getString(R.string.attention_unknown_date)
        else SimpleDateFormat("MM-dd HH:mm", Locale.getDefault()).format(Date(time))
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    private fun toast(resource: Int) = Toast.makeText(this, resource, Toast.LENGTH_SHORT).show()
}
