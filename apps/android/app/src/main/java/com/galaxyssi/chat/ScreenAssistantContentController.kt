package com.galaxyssi.chat

import android.app.AlertDialog
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.view.View
import android.widget.EditText
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.ScrollView
import android.widget.TextView
import org.json.JSONObject
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/** Source selection only; composition, routing, tools and transcript rendering remain in MainActivity. */
internal class ScreenAssistantContentController(
    private val activity: ScreenAssistantChatActivity,
    private val captureScreen: () -> Unit
) {
    private data class Pending(val conversation: String, val source: ScreenContentSource,
        val request: ScreenAssistantAnalysisRequest)
    private val preferences = activity.getSharedPreferences("screen_assistant_content_v1", Context.MODE_PRIVATE)
    private val pending = ConcurrentHashMap<String, Pending>()
    private val worker = Executors.newSingleThreadExecutor { Thread(it, "screen-content-capture") }
    private var conversation = ""
    private var source: ScreenContentSource? = null
    private var closed = false
    private val sourceRow = LinearLayout(activity).apply {
        id = R.id.screenContentSource
        gravity = android.view.Gravity.CENTER_VERTICAL
        background = surface()
        visibility = View.GONE
    }
    private val sourceLabel = label().apply {
        val icon = activity.getDrawable(R.drawable.ic_process_file)?.mutate()?.apply {
            setTint(activity.getColor(R.color.text_primary))
            setBounds(0, 0, activity.dp(18), activity.dp(18))
        }
        setCompoundDrawablesRelative(icon, null, null, null)
        compoundDrawablePadding = activity.dp(8)
    }
    private val coverage = LinearLayout(activity).apply {
        id = R.id.screenContentCoverage
        orientation = LinearLayout.VERTICAL
        visibility = View.GONE
    }
    private val coverageTitle = label().apply {
        setCompoundDrawablesRelativeWithIntrinsicBounds(R.drawable.ic_process_file, 0, R.drawable.ic_chevron_down, 0)
        compoundDrawablePadding = activity.dp(8)
        background = surface()
        isClickable = true
    }
    private val details = label()
    private val detailsScroll = ScrollView(activity).apply {
        visibility = View.GONE
        addView(details)
    }

    init {
        sourceRow.addView(sourceLabel, LinearLayout.LayoutParams(0, -2, 1f))
        sourceRow.addView(ImageButton(activity).apply {
            id = R.id.screenContentRemove
            setImageResource(R.drawable.ic_agent_progress_close)
            setBackgroundColor(Color.TRANSPARENT)
            contentDescription = activity.getString(R.string.screen_content_remove)
            setPadding(activity.dp(12), activity.dp(12), activity.dp(12), activity.dp(12))
            setOnClickListener { select(null) }
        }, LinearLayout.LayoutParams(activity.dp(44), activity.dp(44)))
        val composer = activity.findViewById<View>(R.id.agentComposerRow)
        val composerParent = composer.parent as LinearLayout
        composerParent.addView(sourceRow, composerParent.indexOfChild(composer), LinearLayout.LayoutParams(-1, -2))
        coverage.addView(coverageTitle, LinearLayout.LayoutParams(-1, -2))
        coverage.addView(detailsScroll, LinearLayout.LayoutParams(-1, activity.dp(100)))
        coverageTitle.setOnClickListener {
            val open = detailsScroll.visibility != View.VISIBLE
            detailsScroll.visibility = if (open) View.VISIBLE else View.GONE
            coverageTitle.isSelected = open
        }
        val viewport = activity.findViewById<View>(R.id.agentOutputViewport)
        val outputParent = viewport.parent as LinearLayout
        outputParent.addView(coverage, outputParent.indexOfChild(viewport), LinearLayout.LayoutParams(-1, -2))
    }

    fun showMenu(anchor: View) {
        PopupMenu(activity, anchor).apply {
            if (Build.VERSION.SDK_INT >= 29) setForceShowIcon(true)
            menu.add(0, 0, 0, R.string.screen_content_screen).setIcon(R.drawable.ic_agent_screen)
            menu.add(0, 1, 1, R.string.screen_content_page).setIcon(R.drawable.ic_process_network)
                .setCheckable(source?.kind == ScreenContentKind.PAGE).isChecked = source?.kind == ScreenContentKind.PAGE
            menu.add(0, 2, 2, R.string.screen_content_file).setIcon(R.drawable.ic_process_file)
            menu.add(0, 3, 3, R.string.screen_content_link).setIcon(R.drawable.ic_protocol_link)
                .setCheckable(source?.kind == ScreenContentKind.LINK).isChecked = source?.kind == ScreenContentKind.LINK
            repeat(menu.size()) { index ->
                menu.getItem(index).icon = menu.getItem(index).icon?.mutate()?.apply {
                    setTint(activity.getColor(R.color.text_primary))
                }
            }
            setOnMenuItemClickListener {
                when (it.itemId) {
                    0 -> { select(null); captureScreen() }
                    1 -> select(ScreenContentSource(ScreenContentKind.PAGE))
                    2 -> { select(null); activity.openAgentAttachmentPicker(imagesOnly = false) }
                    3 -> askLink()
                }
                true
            }
            show()
        }
    }

    fun showConversation(id: String) {
        conversation = id
        source = decode(preferences.getString("draft:$id", null))
        renderSource()
        renderCoverage(preferences.getString("coverage:$id", null))
    }

    internal fun select(value: ScreenContentSource?) {
        conversation = activity.agentTranscriptStore.activeConversation().id
        source = value
        preferences.edit().apply {
            if (value == null) {
                remove("draft:$conversation")
                remove("context:$conversation")
            } else putString("draft:$conversation", JSONObject().put("kind", value.kind.name)
                .put("value", value.value).toString())
        }.apply()
        renderSource()
    }

    fun onSubmitted(id: String, turn: String, request: ScreenAssistantAnalysisRequest, hasAttachments: Boolean) {
        val explicit = if (conversation == id) source else decode(preferences.getString("draft:$id", null))
        val selected = explicit ?: if (hasAttachments) null else decode(preferences.getString("context:$id", null))
        if (explicit != null || hasAttachments) {
            preferences.edit().remove("context:$id").remove("coverage:$id").apply()
            if (conversation == id) renderCoverage(null)
        }
        if (selected != null) {
            request.followUp = explicit == null
            pending[turn] = Pending(id, selected, request)
            preferences.edit().remove("draft:$id").apply()
            if (conversation == id) { source = null; renderSource() }
        }
    }

    fun hasSource(turn: String) = pending.containsKey(turn)

    fun prepare(id: String, turn: String, goal: String, attachments: List<AgentInputAttachment>,
        ready: (String, List<AgentInputAttachment>, () -> Boolean) -> Unit) {
        val item = pending[turn] ?: return ready(goal, attachments) { false }
        if (item.source.kind == ScreenContentKind.LINK) {
            saveContext(id, item.source)
            saveCoverage(id, activity.getString(R.string.screen_content_link_selected), item.source.value)
            pending.remove(turn)
            ready(ScreenAssistantContentPolicy.linkGoal(goal, item.source.value), attachments) { item.request.isCancelled }
            return
        }
        worker.execute {
            val session = ScreenAssistantPageCollection(item.request)
            val result = runCatching {
                item.request.awaitRunnable()
                if (item.source.value.isBlank()) {
                    val target = requireNotNull(GalaxySSIAccessibilityService.readTargetUi())
                    check(ScreenAssistantContentCapture.acquire(target.packageName, session))
                }
                try {
                    var lastProgress = ""
                    val capture = item.source.value.ifBlank {
                        ScreenAssistantPageCollector(activity.applicationContext).collect(session, renderHtml = false,
                            maxBytes = 16L * 1024 * 1024) { count, top ->
                            val progress = activity.getString(if (top) R.string.screen_content_locating else R.string.screen_content_collecting, count)
                            if (lastProgress != progress) {
                                lastProgress = progress
                                activity.agentTranscriptStore.upsert(AgentTranscriptRole.PROCESS, progress,
                                    "content-capture:$turn", conversationId = id, turnId = turn, taskId = turn)
                                activity.runOnUiThread { if (!closed) activity.refreshAgentTranscriptWindow(id) }
                            }
                        }
                    }
                    item.request.awaitRunnable()
                    check(!session.interrupted)
                    val store = ScreenAssistantPageStore(activity)
                    val meta = store.manifest(capture)
                    check(meta.optInt("pages") > 0)
                    check(meta.optString("reason") !in setOf("target_changed", "cancelled"))
                    item.request.pageCaptureId = capture
                    ScreenAssistantSettings.saveLastPageCapture(activity, capture)
                    val status = store.status(meta)
                    val text = File(store.directory(capture), "page.txt")
                    val pdf = File(store.directory(capture), "page.pdf").takeIf { it.isFile && it.length() > 0 }
                        ?: store.exportPdf(capture) { item.request.awaitRunnable() }
                    item.request.awaitRunnable()
                    val added = listOf(text to "text/plain", pdf to "application/pdf").map { (file, mime) ->
                        check(file.length() in 1..MAX_AGENT_ATTACHMENT_BYTES)
                        val name = activity.getString(R.string.screen_assistant_page_attachment) + "." + file.extension
                        AgentInputAttachment(UUID.randomUUID().toString(), LocalAttachmentUris.forFile(activity, file, name, mime),
                            name, mime, file.length())
                    }
                    check(attachments.size + added.size <= MAX_AGENT_ATTACHMENTS)
                    saveContext(id, ScreenContentSource(ScreenContentKind.PAGE, capture))
                    val title = activity.getString(when {
                        meta.optBoolean("complete") -> R.string.screen_content_complete
                        meta.optBoolean("visual_traversal_finished") -> R.string.screen_content_visual_collected
                        else -> R.string.screen_content_partial
                    }, meta.optInt("pages"))
                    saveCoverage(id, title, status + "\n" + activity.getString(R.string.screen_content_coverage_caveat))
                    activity.agentTranscriptStore.upsert(AgentTranscriptRole.PROCESS, status,
                        "content-capture:$turn", conversationId = id, turnId = turn, taskId = turn)
                    ScreenAssistantContentPolicy.pageGoal(goal, status) to (attachments + added)
                } finally { ScreenAssistantContentCapture.release(session) }
            }
            activity.runOnUiThread {
                pending.remove(turn)
                if (closed || activity.isDestroyed || item.request.isCancelled) {
                    finishPreparation(id, turn, activity.getString(R.string.screen_assistant_cancelled))
                    return@runOnUiThread
                }
                result.onSuccess { (preparedGoal, preparedAttachments) ->
                    AgentTurnAttachmentRegistry.put(turn, preparedAttachments)
                    ready(preparedGoal, preparedAttachments) { item.request.isCancelled }
                }.onFailure {
                    if (decode(preferences.getString("context:$id", null)) == item.source) {
                        preferences.edit().remove("context:$id").apply()
                    }
                    finishPreparation(id, turn, activity.getString(R.string.screen_content_failed))
                }
            }
        }
    }

    fun cancel(turn: String) { pending[turn]?.request?.cancel() }

    fun close() {
        closed = true
        pending.forEach { (turn, item) ->
            item.request.cancel()
            finishPreparation(item.conversation, turn, activity.getString(R.string.screen_assistant_cancelled))
        }
        worker.shutdown()
    }

    private fun finishPreparation(id: String, turn: String, message: String) {
        PhoneAssistantTaskControl.finish(turn)
        activity.pendingAgentReplyIndicators.remove(turn)
        activity.agentTaskPersistenceExecutor.execute {
            activity.agentTranscriptStore.upsert(AgentTranscriptRole.ASSISTANT, message,
                "assistant-final:$turn", conversationId = id, turnId = turn, taskId = turn)
            activity.runOnUiThread { if (!closed) activity.refreshAgentTranscriptWindow(id) }
        }
    }

    private fun askLink() {
        val input = EditText(activity).apply {
            inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_URI
            hint = "https://"
            maxLines = 3
            setText(source?.takeIf { it.kind == ScreenContentKind.LINK }?.value.orEmpty())
        }
        val dialog = AlertDialog.Builder(activity).setTitle(R.string.screen_content_link).setView(input)
            .setNegativeButton(android.R.string.cancel, null).setPositiveButton(android.R.string.ok, null).create()
        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val url = ScreenAssistantContentPolicy.link(input.text.toString())
                if (url == null) input.error = activity.getString(R.string.screen_content_invalid_link)
                else { select(ScreenContentSource(ScreenContentKind.LINK, url)); dialog.dismiss() }
            }
        }
        dialog.show()
    }

    private fun renderSource() {
        sourceRow.visibility = if (source == null) View.GONE else View.VISIBLE
        sourceLabel.text = when (source?.kind) {
            ScreenContentKind.PAGE -> activity.getString(R.string.screen_content_page_selected)
            ScreenContentKind.LINK -> source?.value
            null -> ""
        }
        sourceLabel.maxLines = 2
        sourceLabel.ellipsize = android.text.TextUtils.TruncateAt.END
    }

    private fun saveCoverage(id: String, title: String, detail: String) {
        val value = JSONObject().put("title", title).put("detail", detail).toString()
        preferences.edit().putString("coverage:$id", value).apply()
        activity.runOnUiThread { if (!closed && conversation == id) renderCoverage(value) }
    }

    private fun saveContext(id: String, source: ScreenContentSource) {
        preferences.edit().putString("context:$id", JSONObject().put("kind", source.kind.name)
            .put("value", source.value).toString()).apply()
    }

    private fun renderCoverage(value: String?) {
        val data = value?.let { runCatching { JSONObject(it) }.getOrNull() }
        coverage.visibility = if (data == null) View.GONE else View.VISIBLE
        coverageTitle.text = data?.optString("title").orEmpty()
        details.text = data?.optString("detail").orEmpty()
        detailsScroll.visibility = View.GONE
    }

    private fun decode(value: String?): ScreenContentSource? = value?.let { runCatching {
        val data = JSONObject(it)
        val kind = ScreenContentKind.valueOf(data.getString("kind"))
        val content = data.optString("value")
        if (kind == ScreenContentKind.LINK) require(ScreenAssistantContentPolicy.link(content) != null)
        else require(content.isBlank() || content.matches(Regex("[a-f0-9-]{36}")))
        ScreenContentSource(kind, content)
    }.getOrNull() }

    private fun label() = TextView(activity).apply {
        textSize = 13f
        setTextColor(activity.getColor(R.color.text_secondary))
        setPadding(activity.dp(10), activity.dp(10), activity.dp(10), activity.dp(10))
    }

    private fun surface() = GradientDrawable().apply {
        setColor(activity.getColor(R.color.page_bg))
        cornerRadius = activity.dp(8).toFloat()
    }
}
