package com.galaxyssi.watch

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Outline
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognizerIntent
import android.text.Editable
import android.text.InputFilter
import android.text.TextWatcher
import android.view.*
import android.widget.*
import android.window.OnBackInvokedDispatcher
import androidx.wear.widget.SwipeDismissFrameLayout
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Locale

class MainActivity : Activity() {
    private val repo get() = (application as WatchApplication).repository
    private var page = "home"
    private val history = ArrayDeque<String>()
    private var selectedTask = ""
    private var detailDesktop = ""
    private var webCredentialKey = ""
    private var webCredentialValue = ""
    private var followUpId = ""
    private var draft = ""
    private var pairingText = ""
    private var pairingOffer: JSONObject? = null
    private var apiStyle = "openai"
    private var apiProvider = ""
    private var apiEndpoint = ""
    private var apiModel = ""
    private var apiKey = ""
    private var apiOffer: ApiProfile? = null
    private var editor: EditText? = null
    private var busy = false
    private var resumed = false
    private var conversationView: WatchConversationView? = null
    private var sessionQuery = ""
    private var speech: WatchReplySpeech? = null
    private var screenAwake: WatchScreenAwake? = null
    private lateinit var content: LinearLayout
    private lateinit var scroll: ScrollView
    private val handler = Handler(Looper.getMainLooper())
    private val saveDraft = Runnable { repo.store.draft = draft }
    private val updated: () -> Unit = {
        if (page == "home") refreshConversation()
        else if (page !in setOf("session-search", "compose", "pair", "pair-review", "api-edit", "api-review")) render(true)

    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE == 0) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        page = savedInstanceState?.getString("page") ?: "home"
        if (page in setOf("task", "compose")) page = "home"
        selectedTask = savedInstanceState?.getString("task") ?: repo.store.activeTask
        followUpId = savedInstanceState?.getString("followup") ?: ""
        detailDesktop = savedInstanceState?.getString("desktop") ?: ""
        draft = savedInstanceState?.getString("draft") ?: repo.store.draft
        history.addAll(savedInstanceState?.getStringArrayList("history") ?: emptyList())
        // Pairing offers are intentionally not saved into instance state or logs.
        if (page.startsWith("pair")) page = "devices"
        if (page == "web-credential") webCredentialValue = ""
        if (page.startsWith("api-")) page = "settings"
        screenAwake = WatchScreenAwake(window)
        speech = WatchReplySpeech(this, onActivityChanged = { updateScreenAwake() }) { toast(R.string.speech_output_unavailable) }
        onBackInvokedDispatcher.registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT) { back() }
        readLaunchIntent(intent)
        render()
    }

    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); readLaunchIntent(intent); render() }
    private fun readLaunchIntent(intent: Intent) {
        intent.getStringExtra("task_id")?.takeIf { repo.store.task(it) != null }?.let { selectedTask = it; repo.store.activeTask = it; page = "home" }
        // adb provisioning writes a one-time offer to private app storage. It still
        // requires an on-watch identity review and confirmation before trust changes.
        val offer = File(filesDir, "pairing-offer.json")
        if (offer.isFile && offer.length() <= 32_000) {
            runCatching { pairingOffer = repo.inspectPairing(offer.readText()); page = "pair-review" }
                .onFailure { toast(R.string.pairing_invalid) }
            offer.delete()
        }
        val apiFile = File(filesDir, "api-profile.json")
        if (apiFile.isFile && apiFile.length() <= 16_000) {
            runCatching { apiOffer = ApiProfile.fromJson(JSONObject(apiFile.readText())); page = "api-review" }
                .onFailure { toast(R.string.api_invalid) }
            apiFile.delete()
        }
    }

    override fun onStart() { super.onStart(); repo.listen(updated); repo.foreground(true) }
    override fun onResume() {
        super.onResume(); resumed = true; updateConversationVisibility(); updated()
    }
    override fun onPause() {
        resumed = false; screenAwake?.update(false, false); speech?.stop(); repo.conversationVisibility.hide(this); super.onPause()
    }
    private fun updateScreenAwake() {
        val task = repo.store.task(selectedTask)
        screenAwake?.update(resumed && page == "home", busy || task?.state?.terminal == false || speech?.active == true)
    }
    private fun updateConversationVisibility() {
        if (!resumed) return
        val task = if (page == "home") repo.store.task(selectedTask) else null
        repo.conversationVisibility.show(this, task)
        if (task != null) {
            val turns = repo.store.tasks().filter { it.conversationKey() == task.conversationKey() }
            WatchNotifications.dismissConversation(this, turns, task)
            repo.store.markRead(turns)
        }
    }
    override fun onStop() {
        handler.removeCallbacks(saveDraft); repo.store.draft = draft
        repo.unlisten(updated); repo.foreground(false); speech?.stop()
        super.onStop()
    }
    override fun onDestroy() { handler.removeCallbacksAndMessages(null); speech?.shutdown(); super.onDestroy() }
    override fun onSaveInstanceState(out: Bundle) {
        out.putString("page", page); out.putString("task", selectedTask); out.putString("followup", followUpId)
        out.putString("desktop", detailDesktop); out.putString("draft", draft)
        out.putStringArrayList("history", ArrayList(history)); super.onSaveInstanceState(out)
    }

    private fun navigate(destination: String) { speech?.stop(); history.addLast(page); page = if (destination in setOf("task", "compose")) "home" else destination; render() }
    private fun back() {
        if (busy) return
        speech?.stop()
        if (page == "home" && history.isEmpty()) { finish(); return }
        if (page.startsWith("pair")) { pairingOffer = null; pairingText = "" }
        if (page == "web-credential") webCredentialValue = ""
        if (page.startsWith("api-")) { apiOffer = null; apiKey = "" }
        page = if (history.isEmpty()) "home" else history.removeLast()
        render()
    }
    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
    private fun background(color: Int) = GradientDrawable().apply { setColor(color); cornerRadius = dp(26).toFloat() }
    private val green = Color.rgb(20, 198, 106)

    private fun render(preserveScroll: Boolean = false) {
        updateScreenAwake()
        updateConversationVisibility()
        if (page == "api-edit" || page == "web-credential") window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        else if (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        if (page == "home") { showConversation(); return }
        conversationView = null
        val offset = if (preserveScroll && ::scroll.isInitialized) scroll.scrollY else 0
        editor = null
        val frame = SwipeDismissFrameLayout(this)
        frame.setBackgroundColor(Color.BLACK)
        frame.addCallback(object : SwipeDismissFrameLayout.Callback() {
            override fun onDismissed(layout: SwipeDismissFrameLayout) { back() }
        })
        if (resources.configuration.isScreenRound) {
            frame.outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) { outline.setOval(0, 0, view.width, view.height) }
            }
            frame.clipToOutline = true
        }
        scroll = ScrollView(this).apply {
            isFillViewport = true
            isVerticalScrollBarEnabled = true
            clipToPadding = false
            isFocusable = true
            setOnGenericMotionListener { _, event ->
                if (event.action == MotionEvent.ACTION_SCROLL) {
                    val factor = ViewConfiguration.get(this@MainActivity).scaledVerticalScrollFactor
                    scrollBy(0, (-event.getAxisValue(MotionEvent.AXIS_SCROLL) * factor).toInt()); true
                } else false
            }
        }
        content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            val horizontal = (resources.configuration.screenWidthDp * 0.14f).toInt().coerceAtLeast(20)
            setPadding(dp(horizontal), dp(26), dp(horizontal), dp(44))
        }
        scroll.addView(content, FrameLayout.LayoutParams(-1, -2))
        frame.addView(scroll, FrameLayout.LayoutParams(-1, -1))
        setContentView(frame)
        frame.post { frame.windowInsetsController?.hide(WindowInsets.Type.systemBars()) }
        label(SimpleDateFormat("HH:mm", Locale.getDefault()).format(java.util.Date()), 12, Color.LTGRAY)
        when (page) {
            "home" -> homeMenu()
            "devices" -> devices()
            "device" -> device()
            "agents" -> agents()
            "sessions" -> sessions()
            "contacts" -> contacts()
            "home-menu" -> homeMenu()
            "session-search" -> { title(R.string.search); input(sessionQuery, R.string.search, 100) { sessionQuery = it }; button(R.string.search) { page = "sessions"; render() } }
            "compose" -> homeMenu()
            "task" -> homeMenu()
            "stop" -> confirmStop()
            "pair" -> pairInput()
            "pair-review" -> pairReview()
            "forget" -> confirmForget()
            "settings" -> settings()
            "web-sources" -> webSources()
            "web-credential" -> webCredential()
            "api-providers" -> {
                title(R.string.api_provider)
                WATCH_MODEL_PRESETS.map { it.provider }.distinct().forEach { provider ->
                    button(provider) { apiProvider = provider; navigate("api-models") }
                }
            }
            "api-models" -> {
                title(R.string.api_model)
                WATCH_MODEL_PRESETS.filter { it.provider == apiProvider }.forEach { preset ->
                    button(preset.name) {
                        apiEndpoint = preset.endpoint; apiModel = preset.model; apiStyle = preset.style; apiKey = ""
                        navigate("api-edit")
                    }
                }
            }
            "api-edit" -> apiSettings()
            "api-review" -> apiReview()
            "api-remove" -> apiRemove()
            else -> homeMenu()
        }
        if (repo.errorResource != 0 && page !in setOf("compose", "pair", "pair-review")) label(getString(repo.errorResource), 12)
        if (page != "home") button(R.string.back) { back() }
        if (preserveScroll) scroll.post { scroll.scrollTo(0, offset) }
        if (editor == null) scroll.requestFocus()
    }

    private fun label(text: String, size: Int = 14, color: Int = Color.LTGRAY, heading: Boolean = false): TextView {
        val view = TextView(this).apply {
            this.text = text; textSize = size.toFloat(); setTextColor(color); gravity = Gravity.CENTER
            setPadding(0, dp(2), 0, dp(4))
            if (heading) setTypeface(typeface, Typeface.BOLD)
        }
        content.addView(view, LinearLayout.LayoutParams(-1, -2)); return view
    }
    private fun title(resource: Int) = label(getString(resource), 18, Color.WHITE, true)
    private fun button(resource: Int, primary: Boolean = false, action: () -> Unit) = button(getString(resource), primary, action)
    private fun button(text: String, primary: Boolean = false, action: () -> Unit): Button {
        val view = Button(this).apply {
            this.text = text; isAllCaps = false; textSize = 14f
            minHeight = dp(48); minimumHeight = dp(48)
            setPadding(dp(10), dp(9), dp(10), dp(9))
            setTextColor(if (primary) Color.BLACK else Color.WHITE)
            background = background(if (primary) green else Color.rgb(25, 33, 29))
            setOnClickListener { action() }
        }
        content.addView(view, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(6) })
        return view
    }
    private fun connectionLabel(): Int = when (repo.connection) {
        ConnectionState.CONNECTING -> R.string.connecting
        ConnectionState.BROKER_CONNECTED -> R.string.broker_connected
        ConnectionState.ERROR -> R.string.connection_error
        else -> R.string.disconnected
    }

    private fun newConversation() {
        selectedTask = ""; repo.store.activeTask = ""; followUpId = ""; draft = ""; repo.store.draft = ""
        page = "home"; history.clear(); render()
    }
    private fun homeMenu() {
        title(R.string.home_menu)
        button(R.string.new_conversation) { newConversation() }
        button(R.string.recent) { sessionQuery = ""; navigate("sessions") }
        button(R.string.contacts) { navigate("contacts") }
        button(R.string.api_provider) { openApiSettings() }
        button(R.string.devices) { navigate("devices") }
        button(R.string.stop_speech) { speech?.stop(); back() }
        button(R.string.settings) { navigate("settings") }
    }
    private fun showConversation() {
        val frame = SwipeDismissFrameLayout(this)
        frame.setBackgroundColor(Color.BLACK)
        if (resources.configuration.isScreenRound) {
            frame.outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) { outline.setOval(0, 0, view.width, view.height) }
            }
            frame.clipToOutline = true
        }
        frame.addCallback(object : SwipeDismissFrameLayout.Callback() {
            override fun onDismissed(layout: SwipeDismissFrameLayout) { back() }
        })
        conversationView = WatchConversationView(this, draft,
            onDraft = { draft = it; handler.removeCallbacks(saveDraft); handler.postDelayed(saveDraft, 350) },
            onSend = { sendFromHome() }, onVoice = { followUpId = selectedTask; startVoice() },
            onMenu = { navigate("home-menu") }, onSessions = { sessionQuery = ""; navigate("sessions") },
            onModel = { openApiSettings() },
            onStop = { selectedTask = it.id; navigate("stop") }, onRead = { speak(it) },
            onConnect = { navigate("devices") }, onStopReading = { speech?.stopIfActive() == true })
        frame.addView(conversationView, FrameLayout.LayoutParams(-1, -1))
        setContentView(frame)
        frame.post { frame.windowInsetsController?.hide(WindowInsets.Type.systemBars()) }
        editor = conversationView?.input
        refreshConversation(true)
    }
    private fun refreshConversation(reset: Boolean = false) {
        val previous = repo.store.task(selectedTask)
        val turns = repo.store.tasks().filter { previous != null && it.conversationKey() == previous.conversationKey() }.sortedBy { it.sourceId }
        val usingApi = previous?.desktopId == "api" || (previous == null && repo.store.apiPreferred)
        val api = repo.store.apiProfile
        val desktop = previous?.desktopId ?: repo.store.selectedDesktop
        val agent = previous?.agentId ?: repo.store.selectedAgent
        val ready = if (usingApi) api != null && (previous == null || previous.routeId == api.id)
            else repo.links().any { it.desktopId == desktop && it.paired } && agent.isNotBlank()
        val name = if (usingApi) api?.model.orEmpty() else agent
        conversationView?.update(turns, name.ifBlank { getString(R.string.connect_service) }, ready, reset)
        conversationView?.sending(busy)
        speech?.observe(turns.lastOrNull(), resumed && page == "home" && repo.store.autoSpeech)
        updateScreenAwake()
        updateConversationVisibility()
    }
    private fun sendFromHome() {
        if (busy || draft.isBlank()) return
        val previous = repo.store.task(selectedTask)
        if (previous == null && !repo.store.apiPreferred && (repo.store.selectedDesktop.isBlank() || repo.store.selectedAgent.isBlank())) {
            navigate("devices"); return
        }
        busy = true; conversationView?.sending(true); updateScreenAwake()
        val composer = conversationView?.input
        composer?.clearFocus()
        (getSystemService(INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager).hideSoftInputFromWindow(composer?.windowToken, 0)
        conversationView?.requestFocus()
        repo.send(draft, previous) { sent ->
            busy = false
            if (isDestroyed || isFinishing) return@send
            if (sent == null) { toast(if (repo.errorResource != 0) repo.errorResource else R.string.send_failed); refreshConversation(); return@send }
            selectedTask = sent.id; repo.store.activeTask = sent.id; followUpId = ""
            draft = ""; repo.store.draft = ""; page = "home"; history.clear()
            if (conversationView == null) render() else { conversationView?.setDraft(""); refreshConversation(true) }
            runCatching { startForegroundService(Intent(this, WatchConnectionService::class.java)) }
        }
    }
    private fun devices() {
        title(R.string.devices)
        if (repo.links().isEmpty()) label(getString(R.string.empty_devices))
        repo.links().forEach { link ->
            val status = if (!link.paired) R.string.pairing_pending else if (repo.online(link.desktopId)) R.string.online else R.string.offline
            button("${link.desktopName}\n${getString(status)}") { detailDesktop = link.desktopId; navigate("device") }
        }
        button(R.string.add_device, true) { navigate("pair") }
        button(R.string.api_title) { openApiSettings() }
        button(R.string.refresh) { repo.refresh() }
        label(getString(R.string.connection_note), 12)
    }
    private fun device() {
        val link = repo.links().firstOrNull { it.desktopId == detailDesktop }
        label(link?.desktopName ?: getString(R.string.devices), 18, Color.WHITE, true)
        if (link == null) return
        label(getString(if (!link.paired) R.string.pairing_pending else if (repo.online(link.desktopId)) R.string.online else R.string.offline))
        if (link.paired) button(R.string.choose_agent, true) { repo.store.apiPreferred = false; repo.store.selectedDesktop = link.desktopId; navigate("agents") }
        button(R.string.refresh) { repo.refresh() }
        button(R.string.forget) { navigate("forget") }
    }
    private fun agents() {
        title(R.string.choose_agent)
        val agents = repo.store.agents(repo.store.selectedDesktop)
        if (agents.isEmpty()) label(getString(R.string.no_agents))
        agents.forEach { agent ->
            button(if (agent.available) agent.name else getString(R.string.agent_unavailable, agent.name), agent.available) {
                repo.store.selectedAgent = agent.id; repo.store.apiPreferred = false; newConversation()
            }
        }
        button(R.string.refresh) { repo.refresh() }
    }
    private fun directoryRow(name: String, subtitle: String, count: Int = 0, action: () -> Unit) {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL; minimumHeight = dp(62)
            setPadding(dp(2), dp(7), dp(2), dp(7)); setOnClickListener { action() }
            addView(ImageView(this@MainActivity).apply { setImageResource(R.mipmap.ic_launcher) }, LinearLayout.LayoutParams(dp(28), dp(28)))
            addView(LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.VERTICAL; setPadding(dp(8), 0, dp(2), 0)
                addView(TextView(this@MainActivity).apply { text = name; textSize = 14f; setTextColor(Color.WHITE); maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END })
                addView(TextView(this@MainActivity).apply { text = subtitle; textSize = 11f; setTextColor(Color.LTGRAY); maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END })
            }, LinearLayout.LayoutParams(0, -2, 1f))
            if (count > 0) addView(TextView(this@MainActivity).apply { text = count.toString(); setTextColor(green); textSize = 12f })
        }
        content.addView(row, LinearLayout.LayoutParams(-1, -2))
        content.addView(View(this).apply { setBackgroundColor(Color.rgb(52, 56, 65)) }, LinearLayout.LayoutParams(-1, dp(1)))
    }
    private fun sessions() {
        title(R.string.recent)
        val actions = LinearLayout(this).apply { gravity = Gravity.CENTER }
        for ((label, action) in listOf<Pair<Int, () -> Unit>>(
            R.string.search to { navigate("session-search") }, R.string.contacts to { navigate("contacts") }, R.string.new_conversation to { newConversation() })) {
            actions.addView(Button(this).apply { text = getString(label); textSize = 10f; isAllCaps = false; minHeight = dp(48); setPadding(0, 0, 0, 0); setOnClickListener { action() } }, LinearLayout.LayoutParams(0, -2, 1f))
        }
        content.addView(actions, LinearLayout.LayoutParams(-1, -2))
        val groups = repo.store.tasks().groupBy { it.conversationKey() }.values.filter { turns ->
            sessionQuery.isBlank() || turns.any { it.prompt.contains(sessionQuery, true) || it.reply.contains(sessionQuery, true) }
        }
        if (groups.isEmpty()) label(getString(R.string.empty_sessions))
        groups.take(30).forEach { turns ->
            val current = turns.first()
            directoryRow(turns.last().prompt, current.reply.ifBlank { getString(current.state.label()) }, turns.count(repo.store::unread)) {
                selectedTask = current.id; repo.store.activeTask = current.id; followUpId = ""; navigate("home")
            }
        }
    }
    private fun contacts() {
        title(R.string.contacts)
        directoryRow(getString(R.string.app_name), getString(R.string.return_to_agent)) { page = "home"; render() }
        repo.links().forEach { link ->
            val assistants = repo.store.agents(link.desktopId)
            if (assistants.isEmpty()) directoryRow(link.desktopName, getString(R.string.no_agents)) { detailDesktop = link.desktopId; navigate("device") }
            assistants.forEach { assistant ->
                directoryRow(assistant.name, link.desktopName) {
                    repo.store.apiPreferred = false; repo.store.selectedDesktop = link.desktopId; repo.store.selectedAgent = assistant.id
                    newConversation()
                }
            }
        }
        label(getString(R.string.contacts_scope), 12)
        button(R.string.add_device) { navigate("pair") }
        button(R.string.api_title) { openApiSettings() }
    }
    private fun input(value: String, hint: Int, limit: Int, changed: (String) -> Unit) {
        editor = EditText(this).apply {
            setText(value); setHint(hint); textSize = 16f; setTextColor(Color.WHITE); setHintTextColor(Color.LTGRAY)
            minHeight = dp(56); maxLines = 5; gravity = Gravity.TOP
            filters = arrayOf(InputFilter.LengthFilter(limit))
            addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) { changed(s.toString()) }
                override fun afterTextChanged(s: Editable?) = Unit
            })
        }
        content.addView(editor, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(8) })
    }
    private fun confirmStop() {
        title(R.string.stop_task); label(getString(if (repo.store.task(selectedTask)?.desktopId == "api") R.string.api_stop_confirm else R.string.stop_confirm))
        button(R.string.confirm) { repo.store.task(selectedTask)?.let(repo::cancel); back() }
        button(R.string.cancel, true) { back() }
    }
    private fun pairInput() {
        title(R.string.add_device); label(getString(R.string.pairing_help))
        input(pairingText, R.string.pairing_input, 32_000) { pairingText = it }
        button(R.string.review_pairing, true) {
            runCatching { pairingOffer = repo.inspectPairing(pairingText); navigate("pair-review") }
                .onFailure { toast(R.string.pairing_invalid) }
        }
    }
    private fun pairReview() {
        title(R.string.review_pairing)
        val offer = pairingOffer ?: return
        label(getString(R.string.pairing_identity, offer.optString("desktop_name"), offer.optString("identity_key_sha256").chunked(8).joinToString(" ")), 13)
        button(R.string.confirm, true) {
            if (!busy) {
                busy = true
                repo.pair(offer) { success ->
                    busy = false
                    if (success) { pairingOffer = null; pairingText = ""; page = "devices" }
                    else toast(R.string.pairing_invalid)
                    render()
                }
            }
        }.isEnabled = !busy
        button(R.string.cancel) { back() }
    }
    private fun confirmForget() {
        title(R.string.forget); label(getString(R.string.forget_confirm))
        button(R.string.confirm) { repo.forget(detailDesktop); page = "devices"; render() }
        button(R.string.cancel, true) { back() }
    }
    private fun settings() {
        title(R.string.settings)
        toggle(R.string.web_search, repo.store.webSearch) { repo.store.webSearch = it }
        label(getString(R.string.web_search_description), 12)
        button(R.string.web_sources_title) { navigate("web-sources") }
        toggle(R.string.vibrate, repo.store.vibration) { repo.store.vibration = it }
        toggle(R.string.auto_speech, repo.store.autoSpeech) { repo.store.autoSpeech = it }
        button(R.string.notifications) { requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 42) }
        button(R.string.devices) { navigate("devices") }
        button(R.string.api_title) { openApiSettings() }
        label(getString(R.string.about), 12)
        label(getString(R.string.monitor_body), 12)
    }
    private fun webSources() {
        title(R.string.web_sources_title)
        val sources = com.galaxyssi.chat.AgentWebIntelligenceEngineCatalog.entries
        val credentials = com.galaxyssi.chat.AgentEncryptedWebIntelligenceCredentials(this)
        label(getString(R.string.web_tools_summary), 12)
        label(getString(R.string.web_source_count, sources.size), 12)
        listOf("brave_api_key" to "Brave API Key", "github_token" to "GitHub Token").forEach { (key, name) ->
            button(name) { webCredentialKey = key; webCredentialValue = ""; navigate("web-credential") }
        }
        sources.sortedBy { it.title }.forEach { source ->
            label(source.title + if (source.requiresKey.isNotBlank() && !credentials.configured(source.requiresKey))
                " · " + getString(R.string.web_key_needed) else "", 12)
        }
    }
    // Optional provider token entry, matching the standalone API-key setup (not account sign-in).
    @android.annotation.SuppressLint("WearPasswordInput")
    private fun webCredential() {
        title(R.string.web_credential_title)
        label(if (webCredentialKey == "brave_api_key") "Brave API Key" else "GitHub Token", 12)
        label(getString(R.string.web_credential_help), 12)
        input(webCredentialValue, R.string.api_key, 4096) { webCredentialValue = it }
        editor?.inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD
        button(R.string.confirm) {
            com.galaxyssi.chat.AgentEncryptedWebIntelligenceCredentials(this).setCredential(webCredentialKey, webCredentialValue)
            webCredentialValue = ""; back()
        }
    }
    private fun toggle(resource: Int, checked: Boolean, changed: (Boolean) -> Unit) {
        content.addView(Switch(this).apply {
            text = getString(resource); setTextColor(Color.WHITE); textSize = 14f
            minHeight = dp(48); isChecked = checked
            setOnCheckedChangeListener { _, value -> changed(value) }
        }, LinearLayout.LayoutParams(-1, -2))
    }
    private fun startVoice() {
        val previous = repo.store.task(selectedTask)
        val usingApi = previous?.desktopId == "api" || (previous == null && repo.store.apiPreferred)
        if (usingApi && repo.store.apiProfile == null) { openApiSettings(); return }
        if (!usingApi && ((previous?.desktopId ?: repo.store.selectedDesktop).isBlank() || (previous?.agentId ?: repo.store.selectedAgent).isBlank())) {
            navigate("devices"); return
        }
        if (page != "home") { page = "home"; render() }
        if (!WatchSpeechInput.launch(this) { startActivityForResult(it, 31) }) toast(R.string.speech_unavailable)
    }
    @Deprecated("Activity result callback for platform speech UI")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 31) {
            if (resultCode != RESULT_OK) { page = "home"; render(); return }
            val result = data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull().orEmpty()
            if (result.isBlank()) toast(R.string.speech_empty) else { draft = result.take(4000); repo.store.draft = draft }
            page = "home"; render()
        }
    }
    private fun speak(text: String) {
        speech?.read(text)
    }
    private fun openApiSettings() {
        val saved = repo.store.apiProfile
        apiStyle = saved?.style ?: "openai"
        apiEndpoint = saved?.endpoint.orEmpty(); apiModel = saved?.model.orEmpty(); apiKey = ""
        navigate(if (saved == null) "api-providers" else "api-edit")
    }
    // Optional standalone API credential entry. Private computer provisioning is
    // also available; retain password masking for users choosing watch entry.
    @android.annotation.SuppressLint("WearPasswordInput")
    private fun apiSettings() {
        title(R.string.api_title)
        button(R.string.api_provider) { navigate("api-providers") }
        label(getString(R.string.api_help), 12)
        label(getString(R.string.api_endpoint), 12)
        input(apiEndpoint, R.string.api_endpoint, 1024) { apiEndpoint = it }
        label(getString(R.string.api_model), 12)
        input(apiModel, R.string.api_model, 128) { apiModel = it }
        label(getString(R.string.api_key), 12)
        input(apiKey, if (repo.store.apiProfile != null) R.string.api_keep_key else R.string.api_key, 4096) { apiKey = it }
        editor?.apply {
            inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD
            isSaveEnabled = false
            importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
        }
        button(R.string.api_save, true) {
            runCatching {
                val old = repo.store.apiProfile
                val key = apiKey.trim().ifBlank { old?.takeIf { it.endpoint == apiEndpoint.trim() }?.key.orEmpty() }
                apiOffer = ApiProfile(apiEndpoint.trim(), apiModel.trim(), key, style = apiStyle)
                navigate("api-review")
            }.onFailure { toast(R.string.api_invalid) }
        }
        if (repo.store.apiProfile != null) {
            button(R.string.api_use) { repo.store.apiPreferred = true; newConversation() }
            button(R.string.api_remove) { navigate("api-remove") }
        }
    }
    private fun apiReview() {
        title(R.string.api_review)
        val offer = apiOffer ?: return
        label(getString(R.string.api_review_detail, offer.endpoint, offer.model), 13)
        button(R.string.confirm, true) {
            val old = repo.store.apiProfile
            val id = old?.takeIf { it.endpoint == offer.endpoint && it.model == offer.model }?.id ?: java.util.UUID.randomUUID().toString()
            repo.store.apiProfile = ApiProfile(offer.endpoint, offer.model, offer.key, id, offer.style)
            repo.store.apiPreferred = true; apiOffer = null; apiKey = ""; followUpId = ""
            newConversation()
        }
        button(R.string.cancel) { back() }
    }
    private fun apiRemove() {
        title(R.string.api_remove); label(getString(R.string.api_remove_confirm))
        button(R.string.confirm) {
            repo.store.apiProfile = null; repo.store.apiPreferred = false; apiKey = ""; apiOffer = null
            page = "settings"; history.clear(); render()
        }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 42 && grantResults.firstOrNull() != PackageManager.PERMISSION_GRANTED) toast(R.string.notification_denied)
    }
    private fun toast(resource: Int) = Toast.makeText(this, resource, Toast.LENGTH_LONG).show()
}
