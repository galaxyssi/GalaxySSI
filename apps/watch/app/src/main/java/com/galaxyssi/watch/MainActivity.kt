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
import com.galaxyssi.chat.DoorAccessConfigurationStore
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.UUID

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
    private var pendingLocationPrompt: String? = null
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
    private var conversationReady = false
    private var conversationUsesApi = false
    private var resumed = false
    private var conversationView: WatchConversationView? = null
    private var conversationFrame: SwipeDismissFrameLayout? = null
    private var renderedConversation: WatchConversationKey? = null
    private var lastReadProjection = emptyList<Pair<String, String>>()
    private data class SessionsKey(val tasks: List<WatchTask>, val query: String, val readRevision: Long, val error: Int, val contactsRevision: Long)
    private var sessionsKey: SessionsKey? = null
    private var sessionsFrame: SwipeDismissFrameLayout? = null
    private var sessionsScroll: ScrollView? = null
    private var sessionsContent: LinearLayout? = null
    private var sessionQuery = ""
    private var modelPageProjection: List<Any?>? = null
    private var speech: WatchReplySpeech? = null
    private var wake: WatchForegroundWake? = null
    private var wakePreference = false
    private var voicePending = false
    private var voiceEntryPending = false
    private var voiceEntryScheduled = false
    private val openVoiceEntry = Runnable {
        voiceEntryScheduled = false
        if (voiceEntryCanStart()) {
            voiceEntryPending = false // Consume before launch so cancel/resume cannot reopen the microphone.
            followUpId = selectedTask
            startVoice()
        }
    }
    private var wasSpeaking = false
    private var wakeCooldownUntil = 0L
    private val refreshWakeLater = Runnable { refreshWake() }
    private var lastWakeGate = ""
    private var settingsPageRefreshOnResume = false
    private var screenAwake: WatchScreenAwake? = null
    private lateinit var content: LinearLayout
    private lateinit var scroll: ScrollView
    private val handler = Handler(Looper.getMainLooper())
    private val refreshModelStatus = object : Runnable {
        override fun run() {
            if (!resumed) return
            if (page in setOf("switch-model", "model-config", "model-options", "model-effort", "agents")) render(true)
            handler.postDelayed(this, 30_000)
        }
    }
    private val saveDraft = Runnable { repo.saveDraft(draft) }
    private val updated: () -> Unit = {
        if (page == "home") refreshConversation()
        else if (page !in setOf("home-menu", "task", "session-search", "compose", "pair", "pair-review", "api-edit", "api-review",
                "settings", "settings-connection", "settings-voice", "settings-wake", "settings-web", "settings-feedback",
                "about", "location-settings", "web-sources", "web-credential", "api-providers", "api-models")) render(true)

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
        pendingLocationPrompt = savedInstanceState?.getString("pending-location")
        history.addAll(savedInstanceState?.getStringArrayList("history") ?: emptyList())
        // Pairing offers are intentionally not saved into instance state or logs.
        if (page.startsWith("pair")) page = "devices"
        if (page == "web-credential") webCredentialValue = ""
        if (page.startsWith("api-")) page = "settings"
        wakePreference = repo.store.foregroundWake
        wake = WatchForegroundWake(this, onState = {}, onWake = {
            if (wakeAllowed()) {
                wakeCooldownUntil = android.os.SystemClock.elapsedRealtime() + 2500
                getSystemService(android.os.VibratorManager::class.java).defaultVibrator.vibrate(
                    android.os.VibrationEffect.createOneShot(45, android.os.VibrationEffect.DEFAULT_AMPLITUDE))
                followUpId = selectedTask
                startVoice()
            }
        })
        screenAwake = WatchScreenAwake(window)
        speech = WatchReplySpeech(this, onActivityChanged = { updateScreenAwake() },
            onSpeaking = { id, start, end -> if (resumed && page == "home") conversationView?.showSpeaking(id, start, end) },
            onSpeechStopped = { conversationView?.stopSpeaking() }) { toast(R.string.speech_output_unavailable) }
        onBackInvokedDispatcher.registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT) { back() }
        voicePending = savedInstanceState?.getBoolean("voice_pending") ?: false
        voiceEntryPending = savedInstanceState?.getBoolean("voice_entry_pending") ?: false
        readLaunchIntent(intent, savedInstanceState == null)
        render()
    }

    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); readLaunchIntent(intent); render() }
    private fun readLaunchIntent(intent: Intent, acceptVoice: Boolean = true) {
        if (acceptVoice) {
            handler.removeCallbacks(openVoiceEntry)
            voiceEntryScheduled = false
            voiceEntryPending = false
        }
        if (acceptVoice && WatchVoiceEntryPolicy.requestsVoice(intent.action,
                intent.component?.className == "$packageName.VoiceEntry",
                intent.hasExtra("task_id"))) {
            voiceEntryPending = true
            // Consume this launch request; subsequent task recreation is an ordinary open.
            intent.action = Intent.ACTION_MAIN
            intent.component = android.content.ComponentName(this, MainActivity::class.java)
            page = "home"
            setTurnScreenOn(true)
        }
        intent.getStringExtra("task_id")?.takeIf { it.isNotBlank() }?.let { selectedTask = it; repo.saveActiveTask(it); page = "home" }
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

    override fun onStart() {
        super.onStart(); repo.listen(updated); repo.foreground(true)
        if (repo.store.backgroundEnabled) runCatching { startForegroundService(Intent(this, WatchConnectionService::class.java)) }
    }
    override fun onResume() {
        super.onResume(); resumed = true
        wakePreference = repo.store.foregroundWake
        if (wakePreference && repo.store.backgroundWake) WatchBackgroundWakeService.start(this)
        if (page.startsWith("settings") && settingsPageRefreshOnResume) render(true)
        settingsPageRefreshOnResume = false
        updateConversationVisibility(); updated(); refreshWake()
        handler.removeCallbacks(refreshModelStatus); handler.postDelayed(refreshModelStatus, 30_000)
    }
    override fun onPause() {
        handler.removeCallbacks(refreshModelStatus)
        if (page.startsWith("settings")) settingsPageRefreshOnResume = true
        resumed = false; handler.removeCallbacks(openVoiceEntry); voiceEntryScheduled = false; wake?.setEnabled(false); screenAwake?.update(false, false); speech?.stop(); repo.conversationVisibility.hide(this); refreshWake(); super.onPause()
    }
    private fun updateScreenAwake() {
        val task = repo.store.cachedTask(selectedTask)
        screenAwake?.update(resumed && page == "home", busy || task?.state?.terminal == false || speech?.active == true)
        refreshWake()
    }
    private fun updateConversationVisibility() {
        if (!resumed) return
        val task = if (page == "home") repo.store.cachedTask(selectedTask) else null
        repo.conversationVisibility.show(this, task)
        if (task != null) {
            val turns = repo.store.cachedTasks().filter { it.conversationKey() == task.conversationKey() }
            val projection = turns.map { it.id to "${it.state}:${it.reply.hashCode()}:${it.reply.length}" }
            if (projection != lastReadProjection) {
                lastReadProjection = projection
                repo.markConversationRead(turns, task)
            }
        }
    }
    override fun onStop() {
        handler.removeCallbacks(saveDraft); repo.saveDraft(draft)
        repo.unlisten(updated); repo.foreground(false); speech?.stop()
        super.onStop()
    }
    override fun onDestroy() { handler.removeCallbacksAndMessages(null); speech?.shutdown(); wake?.shutdown(); super.onDestroy() }
    override fun onSaveInstanceState(out: Bundle) {
        out.putBoolean("voice_pending", voicePending)
        out.putBoolean("voice_entry_pending", voiceEntryPending)
        out.putString("page", page); out.putString("task", selectedTask); out.putString("followup", followUpId)
        out.putString("desktop", detailDesktop); out.putString("draft", draft)
        out.putString("pending-location", pendingLocationPrompt)
        out.putStringArrayList("history", ArrayList(history)); super.onSaveInstanceState(out)
    }

    private fun navigate(destination: String) {
        if (destination == "contacts") { speech?.stop(); startActivity(Intent(this, WatchContactsActivity::class.java)); return }
        speech?.stop(); history.addLast(page); page = if (destination in setOf("task", "compose")) "home" else destination; render() }
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
        if (page !in setOf("switch-model", "model-config", "model-options", "model-effort", "agents")) modelPageProjection = null
        else {
            val links = repo.links().filter { it.paired }
            val profile = repo.store.apiProfile
            val projection = listOf(page, links.map { it.desktopId to it.desktopName },
                links.flatMap { repo.store.agents(it.desktopId) },
                profile?.let { listOf(it.id, it.model, it.endpoint) },
                repo.modelTargets().map { listOf(it.id, it.name, it.source, it.available, it.profile) }, repo.store.selection(currentModelScope()),
                selectedTask, repo.store.selectedDesktop, repo.store.selectedAgent,
                repo.store.apiPreferred, busy, repo.errorResource)
            if (preserveScroll && modelPageProjection == projection) return
            modelPageProjection = projection
        }
        updateScreenAwake()
        updateConversationVisibility()
        if (page == "api-edit" || page == "web-credential") window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        else if (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        if (page == "home") {
            if (repo.store.apiProfiles().isEmpty() && repo.links().none { it.paired }) {
                voiceEntryPending = false
                startActivity(Intent(this, WatchPhoneSetupActivity::class.java))
                finish(); return
            }
            showConversation(); return
        }
        val listKey = if (page == "sessions") SessionsKey(repo.store.cachedTasks(), sessionQuery, repo.store.cachedReadRevision, repo.errorResource, repo.contacts.revision) else null
        if (listKey != null && listKey == sessionsKey && sessionsFrame != null) {
            val frame = requireNotNull(sessionsFrame)
            scroll = requireNotNull(sessionsScroll)
            content = requireNotNull(sessionsContent)
            editor = null
            if (frame.parent == null) setContentView(frame)
            frame.post { frame.windowInsetsController?.hide(WindowInsets.Type.systemBars()) }
            return
        }
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
            // Match the home transcript width and the home's top/bottom insets.
            val horizontal = (resources.configuration.screenWidthDp * 0.055f).toInt().coerceAtLeast(10)
            setPadding(dp(horizontal), dp(10), dp(horizontal), dp(18))
        }
        scroll.addView(content, FrameLayout.LayoutParams(-1, -2))
        frame.addView(scroll, FrameLayout.LayoutParams(-1, -1))
        setContentView(frame)
        frame.post { frame.windowInsetsController?.hide(WindowInsets.Type.systemBars()) }
        when (page) {
            "home" -> homeMenu()
            "devices" -> devices()
            "device" -> device()
            "agents" -> agents()
            "switch-model" -> modelSelection()
            "model-config", "model-options", "model-effort" -> modelConfiguration()
            "sessions" -> sessions()
            "contacts" -> contacts()
            "paste" -> pasteMenu()
            "home-menu" -> homeMenu()
            "session-search" -> { title(R.string.search); input(sessionQuery, R.string.search, 100) { sessionQuery = it }; button(R.string.search) { page = "sessions"; render() } }
            "compose" -> homeMenu()
            "task" -> homeMenu()
            "stop" -> confirmStop()
            "pair" -> pairInput()
            "pair-review" -> pairReview()
            "forget" -> confirmForget()
            "settings" -> settings()
            "settings-connection" -> settingsConnection()
            "settings-voice" -> settingsVoice()
            "settings-wake" -> settingsWake()
            "settings-web" -> settingsWeb()
            "settings-feedback" -> settingsFeedback()
            "location-settings" -> locationSettings()
            "about" -> {
                title(R.string.about)
                label(getString(R.string.app_name), 18, Color.WHITE)
                val info = packageManager.getPackageInfo(packageName, android.content.pm.PackageManager.PackageInfoFlags.of(0))
                label(getString(R.string.app_version, info.versionName ?: info.longVersionCode.toString()), 16)
            }
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
        if (repo.errorResource != 0 && page !in setOf("compose", "pair", "pair-review", "paste")) label(getString(repo.errorResource), 12)
        if (page !in setOf("home", "paste") && !page.startsWith("settings")) button(R.string.back) { back() }
        if (preserveScroll) scroll.post { scroll.scrollTo(0, offset) }
        if (editor == null) scroll.requestFocus()
        if (listKey != null) {
            sessionsKey = listKey; sessionsFrame = frame; sessionsScroll = scroll; sessionsContent = content
        }
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
        repo.store.draftConversationId = java.util.UUID.randomUUID().toString()
        selectedTask = ""; repo.saveActiveTask(""); followUpId = ""; draft = ""; repo.saveDraft("")
        page = "home"; history.clear(); render()
    }
    private fun homeMenu() {
        button(R.string.new_conversation) { newConversation() }
        button(R.string.recent) { sessionQuery = ""; navigate("sessions") }
        button(R.string.contacts) { navigate("contacts") }
        button(R.string.paste_message) { navigate("paste") }
        button(R.string.switch_model) { navigate("switch-model"); repo.refresh() }
        button(R.string.configure_models) {
            startActivity(Intent(this, WatchPhoneSetupActivity::class.java)
                .putExtra(WatchPhoneSetupActivity.EXTRA_CONFIGURE_MODELS, true))
        }
        button(R.string.devices) { navigate("devices") }
        button(R.string.settings) { navigate("settings") }
        button(R.string.about) { navigate("about") }
    }
    private fun pasteMenu() {
        val clipboard = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
        val clip = clipboard.primaryClip
        val current = if (clip == null) emptyList() else (0 until clip.itemCount).mapNotNull {
            clip.getItemAt(it).text?.toString()?.takeIf(String::isNotBlank)
        }.distinct()
        fun entry(value: String) {
            button(value) {
                if (busy) return@button
                val input = conversationView?.input
                val start = input?.selectionStart?.takeIf { it >= 0 } ?: draft.length
                val end = input?.selectionEnd?.takeIf { it >= 0 } ?: start
                val from = minOf(start, end).coerceIn(0, draft.length)
                val to = maxOf(start, end).coerceIn(from, draft.length)
                val insert = value.take((4000 - draft.length + to - from).coerceAtLeast(0))
                draft = draft.replaceRange(from, to, insert)
                handler.removeCallbacks(saveDraft); repo.saveDraft(draft)
                page = "home"; history.clear(); render()
                conversationView?.input?.setSelection(from + insert.length)
            }.apply {
                maxLines = 4; ellipsize = android.text.TextUtils.TruncateAt.END
                gravity = Gravity.START or Gravity.CENTER_VERTICAL
                setPadding(dp(8), dp(9), dp(8), dp(9))
            }
        }
        current.forEach(::entry)
        val recent = WatchClipboardHistory.snapshot().filterNot { it in current }
        recent.forEach(::entry)
        if (current.isEmpty() && recent.isEmpty()) label(getString(R.string.clipboard_empty))
    }

    private fun showConversation() {
        conversationFrame?.let { existing ->
            if (existing.parent == null) setContentView(existing)
            existing.post { existing.windowInsetsController?.hide(WindowInsets.Type.systemBars()) }
            conversationView?.setDraft(draft)
            editor = conversationView?.input
            refreshConversation()
            return
        }
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
            onDraft = { draft = it; handler.removeCallbacks(saveDraft); handler.postDelayed(saveDraft, 350); refreshWake() },
            onSend = { sendFromHome() }, onVoice = { followUpId = selectedTask; startVoice() },
            onMenu = { navigate("home-menu") }, onSessions = { sessionQuery = ""; navigate("sessions") },
            onModel = { navigate("switch-model"); repo.refresh() },
            onStop = { selectedTask = it.id; navigate("stop") }, onRead = { speak(it) },
            onConnect = { navigate("devices") }, onStopReading = { speech?.stopIfActive() == true },
            onReadFrom = { id, text, start ->
                speech?.read(text, id, start)
                conversationView?.resumeSpeechFollow()
            })
        conversationView?.input?.setOnFocusChangeListener { _, _ -> refreshWake() }
        frame.addView(conversationView, FrameLayout.LayoutParams(-1, -1))
        conversationFrame = frame
        setContentView(frame)
        frame.post { frame.windowInsetsController?.hide(WindowInsets.Type.systemBars()) }
        editor = conversationView?.input
        refreshConversation(true)
    }
    private fun refreshConversation(reset: Boolean = false) {
        val previous = repo.store.cachedTask(selectedTask)
        val turns = repo.store.cachedTasks().filter { previous != null && it.conversationKey() == previous.conversationKey() }.sortedBy { it.sourceId }
        val chosen = repo.selectedModel(previous)
        val usingApi = chosen?.first?.api != null
        val ready = chosen != null
        conversationReady = ready
        conversationUsesApi = usingApi
        val name = chosen?.let { (target, selection) -> target.profile.models.firstOrNull { it.id == selection.model }?.displayName
            ?: selection.model.ifBlank { target.name } }.orEmpty()
        val key = previous?.conversationKey()
        conversationView?.update(turns, name.ifBlank { getString(R.string.connect_service) }, ready, reset || key != renderedConversation)
        renderedConversation = key
        conversationView?.sending(busy)
        speech?.observe(turns.lastOrNull(), resumed && page == "home" && repo.store.autoSpeech)
        updateScreenAwake()
        updateConversationVisibility()
        scheduleVoiceEntry()
    }
    private fun sendFromHome(prompt: String = draft) {
        if (busy || prompt.isBlank()) return
        if (DoorAccessConfigurationStore(this).load()?.parse(prompt) != null) {
            draft = ""
            repo.saveDraft("")
            conversationView?.setDraft("")
            startActivity(Intent(this, com.galaxyssi.chat.DoorAccessActivity::class.java)
                .putExtra(com.galaxyssi.chat.DoorAccessActivity.EXTRA_REQUEST, prompt)
                .putExtra(com.galaxyssi.chat.DoorAccessActivity.EXTRA_COMMAND_ID, UUID.randomUUID().toString()))
            return
        }
        val locationRequest = WatchLocationIntent.matches(prompt)
        if (locationRequest && !WatchLocation.permitted(this)) {
            draft = prompt; repo.saveDraft(prompt); conversationView?.setDraft(prompt)
            pendingLocationPrompt = prompt
            requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), 44)
            return
        }
        val previous = repo.store.cachedTask(selectedTask)
        if (!locationRequest && repo.selectedModel(previous) == null) { navigate("switch-model"); return }
        busy = true; conversationView?.sending(true); updateScreenAwake()
        val composer = conversationView?.input
        composer?.clearFocus()
        (getSystemService(INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager).hideSoftInputFromWindow(composer?.windowToken, 0)
        conversationView?.requestFocus()
        repo.send(prompt, previous) { sent ->
            busy = false
            if (isDestroyed || isFinishing) return@send
            if (sent == null) {
                draft = prompt; repo.saveDraft(prompt); conversationView?.setDraft(prompt)
                toast(if (repo.errorResource != 0) repo.errorResource else R.string.send_failed); refreshConversation(); return@send
            }
            selectedTask = sent.id; repo.saveActiveTask(sent.id); followUpId = ""
            draft = ""; repo.saveDraft(""); page = "home"; history.clear()
            showConversation()
            refreshConversation(true)
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
    private fun modelTitle(resource: Int) {
        val header = LinearLayout(this).apply { gravity = Gravity.CENTER; setPadding(dp(24), 0, dp(24), dp(4)) }
        header.addView(TextView(this).apply {
            text = "‹"; textSize = 27f; setTextColor(Color.WHITE); gravity = Gravity.CENTER
            contentDescription = getString(R.string.back); setOnClickListener { back() }
        }, LinearLayout.LayoutParams(dp(40), dp(44)))
        header.addView(TextView(this).apply {
            text = getString(resource); textSize = 16f; setTextColor(Color.WHITE); setTypeface(typeface, Typeface.BOLD)
            gravity = Gravity.CENTER_VERTICAL
        }, LinearLayout.LayoutParams(0, dp(44), 1f))
        content.addView(header, LinearLayout.LayoutParams(-1, -2))
    }
    private fun modelRow(name: String, subtitle: String, selected: Boolean = false, enabled: Boolean = true, action: () -> Unit) {
        val row = LinearLayout(this).apply {
            gravity = Gravity.CENTER_VERTICAL; minimumHeight = dp(48)
            setPadding(dp(12), dp(8), dp(12), dp(8))
            background = background(if (selected) Color.rgb(31, 45, 30) else Color.rgb(23, 28, 25))
            isEnabled = enabled; alpha = if (enabled) 1f else .55f
            contentDescription = "$name, $subtitle" + if (selected) ", ${getString(R.string.model_current)}" else ""
            setOnClickListener { action() }
        }
        row.addView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(TextView(this@MainActivity).apply { text = name; textSize = 14f; setTextColor(Color.WHITE); setTypeface(typeface, Typeface.BOLD) })
            if (subtitle.isNotBlank()) addView(TextView(this@MainActivity).apply { text = subtitle; textSize = 11f; setTextColor(Color.LTGRAY) })
        }, LinearLayout.LayoutParams(0, -2, 1f))
        row.addView(TextView(this).apply {
            text = if (selected) "✓" else "›"; textSize = 20f; setTextColor(if (selected) green else Color.GRAY)
            gravity = Gravity.CENTER
        }, LinearLayout.LayoutParams(dp(24), -2))
        content.addView(row, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(6) })
    }
    private fun currentModelScope() = repo.modelScope(repo.store.cachedTask(selectedTask))
    private fun returnToConversation() { page = "home"; history.clear(); render() }
    private fun modelSelection() {
        modelTitle(R.string.switch_model)
        val scope = currentModelScope()
        val targets = repo.modelTargets()
        val chosen = repo.selectedModel(repo.store.cachedTask(selectedTask), targets)
        val automatic = repo.store.selection(scope)?.automatic == true
        modelRow(getString(R.string.model_auto), getString(R.string.model_auto_help), automatic) {
            repo.store.select(scope, WatchModelSelection(automatic = true)); render(true)
        }
        listOf(false, true).forEach { cloud ->
            val group = targets.filter { (it.api != null) == cloud }
            if (group.isNotEmpty()) label(getString(if (cloud) R.string.model_cloud_section else R.string.model_remote_section), 12)
            group.forEach { target ->
                val selected = !automatic && chosen?.first?.id == target.id
                modelRow(target.name, target.source, selected, target.available) {
                    val fresh = repo.modelTargets().firstOrNull { it.id == target.id && it.available }
                    if (fresh == null) { render(true); repo.refresh() }
                    else {
                        repo.store.select(scope, fresh.normalize(repo.store.targetSelection(scope, fresh.id)))
                        navigate("model-config")
                    }
                }
            }
        }
        if (targets.isEmpty()) label(getString(R.string.model_empty), 12)
        label(getString(R.string.model_switch_hint), 11)
        button(R.string.model_return, true) { returnToConversation() }
        button(R.string.refresh) { repo.refresh() }
    }
    private fun modelConfiguration() {
        val scope = currentModelScope()
        val chosen = repo.selectedModel(repo.store.cachedTask(selectedTask))
        modelTitle(if (page == "model-options") R.string.model_options else if (page == "model-effort") R.string.model_effort else R.string.switch_model)
        if (chosen == null) { label(getString(R.string.model_empty)); return }
        val (target, selection) = chosen
        label(target.name, 13, green)
        val profile = target.profile
        when (page) {
            "model-options" -> profile.models.forEach { model ->
                modelRow(model.displayName, model.description, model.id == selection.model, target.available) {
                    val fresh = repo.modelTargets().firstOrNull { it.id == target.id && it.available }
                    if (fresh?.profile?.models?.any { it.id == model.id } == true) {
                        repo.store.select(scope, fresh.normalize(selection.copy(model = model.id)))
                        back()
                    } else { render(true); repo.refresh() }
                }
            }
            "model-effort" -> profile.reasoningEfforts.forEach { effort ->
                modelRow(modelEffortName(effort.wireValue), "", effort.wireValue == selection.effort, target.available) {
                    val fresh = repo.modelTargets().firstOrNull { it.id == target.id && it.available }
                    if (fresh != null && effort in fresh.profile.reasoningEfforts) {
                        repo.store.select(scope, fresh.normalize(selection.copy(effort = effort.wireValue)))
                        back()
                    } else { render(true); repo.refresh() }
                }
            }
            else -> {
                if (profile.models.isNotEmpty()) modelRow(getString(R.string.model_options),
                    profile.models.firstOrNull { it.id == selection.model }?.displayName ?: selection.model) { navigate("model-options") }
                else label(getString(R.string.model_desktop_default), 12)
                if (profile.reasoningEfforts.isNotEmpty()) modelRow(getString(R.string.model_effort), modelEffortName(selection.effort)) { navigate("model-effort") }
                label(getString(R.string.model_switch_hint), 11)
                button(R.string.model_return, true) { returnToConversation() }
            }
        }
    }
    private fun modelEffortName(value: String) = getString(when (value) {
        "low" -> R.string.model_effort_low
        "medium" -> R.string.model_effort_medium
        "high" -> R.string.model_effort_high
        "xhigh" -> R.string.model_effort_xhigh
        else -> R.string.model_auto
    })
    private fun agents() {
        title(R.string.choose_agent)
        val agents = repo.store.agents(repo.store.selectedDesktop)
        if (agents.isEmpty()) label(getString(R.string.no_agents))
        agents.forEach { agent ->
            button("${agent.name}\n${getString(agent.statusLabel)}", agent.available) {
                if (repo.store.agents(agent.desktopId).none { it.id == agent.id && it.available }) {
                    render(true); repo.refresh(); return@button
                }
                repo.store.selectedAgent = agent.id; repo.store.apiPreferred = false; newConversation()
            }.isEnabled = agent.available
        }
        button(R.string.refresh) { repo.refresh() }
    }
    private fun directoryRow(name: String, subtitle: String, count: Int = 0, fingerprint: String = "",
        status: WatchConversationStatus? = null, action: () -> Unit) {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL; minimumHeight = dp(62)
            setPadding(dp(2), dp(7), dp(2), dp(7)); setOnClickListener { action() }
            addView(if (status != null) WatchConversationStatusIcon(this@MainActivity, status) else ImageView(this@MainActivity).apply {
                if (fingerprint.isBlank()) setImageResource(R.mipmap.ic_launcher)
                else setImageDrawable(com.galaxyssi.chat.GalaxySSIIdenticonDrawable(fingerprint))
            }, LinearLayout.LayoutParams(dp(28), dp(28)))
            addView(LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.VERTICAL; setPadding(dp(8), 0, dp(2), 0)
                addView(TextView(this@MainActivity).apply {
                    text = name.take(80).replace('\n', ' ').replace('\r', ' '); textSize = 14f; setTextColor(Color.WHITE)
                    maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END
                    if (status == WatchConversationStatus.COMPLETE_UNREAD) setTypeface(typeface, Typeface.BOLD)
                })
                addView(TextView(this@MainActivity).apply { text = subtitle.take(120).replace('\n', ' ').replace('\r', ' '); textSize = 11f; setTextColor(Color.LTGRAY); maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END })
            }, LinearLayout.LayoutParams(0, -2, 1f))
            if (status == null && count > 0) addView(TextView(this@MainActivity).apply { text = count.toString(); setTextColor(green); textSize = 12f })
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
        val groups = repo.store.cachedTasks().groupBy { it.conversationKey() }.values.filter { turns ->
            sessionQuery.isBlank() || turns.any { it.prompt.contains(sessionQuery, true) || it.reply.contains(sessionQuery, true) }
        }
        val entries = mutableListOf<Pair<Long, () -> Unit>>()
        groups.forEach { turns ->
            val current = WatchConversationStatus.latest(turns)
            val status = WatchConversationStatus.resolve(current, turns.any { it.state == TaskState.COMPLETED && repo.store.cachedUnread(it) })
            val subtitle = when (status) {
                WatchConversationStatus.COMPLETE_UNREAD, WatchConversationStatus.READ -> current.reply
                WatchConversationStatus.RUNNING -> current.progress.ifBlank { getString(status.label()) }
                else -> getString(status.label())
            }
            entries += current.sourceId to {
            directoryRow(turns.minBy { it.sourceId }.prompt, subtitle, status = status) {
                selectedTask = current.id; repo.saveActiveTask(current.id); followUpId = ""; navigate("home")
            }
            }
        }
        repo.contacts.people().filter { it.status == "approved" }.forEach { person ->
            val messages = repo.contacts.messages(person.id)
            val last = messages.lastOrNull() ?: return@forEach
            if (sessionQuery.isNotBlank() && !person.name.contains(sessionQuery, true) && messages.none { it.text.contains(sessionQuery, true) }) return@forEach
            entries += last.time to {
                directoryRow(person.name, if (last.audioId.isNotEmpty()) getString(R.string.peer_voice_message) else last.text, person.unread, person.fingerprint.ifBlank { person.id }) {
                    startActivity(Intent(this, WatchContactsActivity::class.java).putExtra("peer", person.id))
                }
            }
        }
        if (entries.isEmpty()) label(getString(R.string.empty_sessions))
        entries.sortedByDescending { it.first }.take(30).forEach { it.second() }
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
        title(R.string.stop_task); label(getString(if (repo.store.cachedTask(selectedTask)?.desktopId == "api") R.string.api_stop_confirm else R.string.stop_confirm))
        button(R.string.confirm) { repo.store.cachedTask(selectedTask)?.let(repo::cancel); back() }
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
        settingsHeader(R.string.settings)
        settingsRow(R.string.settings_connection, R.string.settings_connection_summary) { navigate("settings-connection") }
        settingsRow(R.string.settings_voice, R.string.settings_voice_summary) { navigate("settings-voice") }
        settingsRow(R.string.settings_wake, R.string.settings_wake_summary) { navigate("settings-wake") }
        settingsRow(R.string.settings_web, R.string.settings_web_summary) { navigate("settings-web") }
        settingsRow(R.string.settings_door_skill, R.string.settings_door_skill_summary) {
            startActivity(Intent(this, com.galaxyssi.chat.DoorAccessActivity::class.java))
        }
        settingsRow(R.string.settings_feedback, R.string.settings_feedback_summary) { navigate("settings-feedback") }
    }
    private fun settingsConnection() {
        settingsHeader(R.string.settings_connection)
        settingsRow(R.string.phone_setup_settings, R.string.settings_phone_summary) {
            startActivity(Intent(this, WatchPhoneSetupActivity::class.java))
        }
        settingsRow(R.string.devices, R.string.settings_devices_summary) { navigate("devices") }
        settingsRow(R.string.api_title, R.string.settings_api_summary) { openApiSettings() }
        settingsNote(R.string.settings_connection_note)
    }
    private fun settingsVoice() {
        settingsHeader(R.string.settings_voice)
        settingsToggle(R.string.settings_auto_speech, R.string.settings_auto_speech_summary, repo.store.autoSpeech) {
            repo.store.autoSpeech = it
        }
        settingsToggle(R.string.settings_samsung_confirm, R.string.settings_samsung_summary, repo.store.samsungAutoConfirm) {
            repo.store.samsungAutoConfirm = it
            if (!it) WatchSamsungConfirmService.cancelSession()
        }
        settingsRow(R.string.settings_voice_service,
            if (WatchSamsungConfirmService.enabled(this)) R.string.samsung_confirm_enabled else R.string.samsung_confirm_settings) {
            runCatching { startActivity(Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)) }
                .onFailure { toast(R.string.samsung_confirm_settings) }
        }
        settingsRow(R.string.voice_entry_try, R.string.settings_voice_try_summary) {
            voiceEntryPending = true; page = "home"; render()
        }
        settingsNote(R.string.settings_voice_note)
    }
    private fun settingsWake() {
        settingsHeader(R.string.settings_wake)
        settingsToggle(R.string.settings_hello_wake, R.string.settings_foreground_summary, wakePreference) { enable ->
            if (enable && checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 43)
            } else setWakePreference(enable)
        }
        settingsToggle(R.string.background_wake, R.string.settings_background_wake_summary, repo.store.backgroundWake) { enable ->
            if (enable && (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED ||
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)) {
                requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO, Manifest.permission.POST_NOTIFICATIONS), 49)
            } else setBackgroundWake(enable)
        }
        settingsToggle(R.string.background_enabled, R.string.settings_background_run_summary, repo.store.backgroundEnabled) {
            repo.store.backgroundEnabled = it
            if (it) startForegroundService(Intent(this, WatchConnectionService::class.java))
            else stopService(Intent(this, WatchConnectionService::class.java))
        }
        settingsNote(R.string.settings_wake_note)
    }
    private fun settingsWeb() {
        settingsHeader(R.string.settings_web)
        settingsToggle(R.string.settings_web_search, R.string.settings_search_summary, repo.store.webSearch) {
            repo.store.webSearch = it
        }
        settingsRow(R.string.web_sources_title, R.string.settings_sources_summary) { navigate("web-sources") }
        settingsRow(R.string.location_settings, R.string.settings_location_summary) { navigate("location-settings") }
        settingsNote(R.string.settings_web_note)
    }
    private fun settingsFeedback() {
        settingsHeader(R.string.settings_feedback)
        settingsRow(R.string.settings_task_notifications,
            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)
                R.string.settings_notifications_enabled else R.string.settings_notifications_summary) {
            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
                runCatching {
                    startActivity(Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, packageName))
                }.onFailure {
                    startActivity(Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        android.net.Uri.parse("package:$packageName")))
                }
            } else requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 42)
        }
        settingsToggle(R.string.vibrate, R.string.settings_vibrate_summary, repo.store.vibration) {
            repo.store.vibration = it
        }
        settingsNote(R.string.settings_feedback_note)
    }
    private fun locationSettings() {
        title(R.string.location_settings)
        label(getString(R.string.location_privacy), 12)
        val prefs = getSharedPreferences("watch-location", MODE_PRIVATE)
        var tile = prefs.getString("tile_base", "https://tile.openstreetmap.org").orEmpty()
        var address = prefs.getString("address_endpoint", "https://photon.komoot.io/reverse").orEmpty()
        label(getString(R.string.location_tile_source), 12)
        input(tile, R.string.location_tile_source, 500) { tile = it }
        label(getString(R.string.location_address_source), 12)
        input(address, R.string.location_address_source, 500) { address = it }
        button(R.string.confirm) {
            fun valid(value: String): Boolean = runCatching {
                val uri = java.net.URI(value)
                uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.userInfo == null && uri.query == null && uri.fragment == null
            }.getOrDefault(false)
            if (!valid(tile.trim()) || (address.isNotBlank() && !valid(address.trim()))) { toast(R.string.location_source_invalid); return@button }
            prefs.edit().putString("tile_base", tile.trim().trimEnd('/')).putString("address_endpoint", address.trim()).apply()
            back()
        }
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
    private fun settingsHeader(resource: Int) {
        val bar = FrameLayout(this).apply { minimumHeight = dp(42) }
        bar.addView(TextView(this).apply {
            text = getString(resource); textSize = 16f; setTextColor(Color.WHITE)
            setTypeface(typeface, Typeface.BOLD); gravity = Gravity.CENTER
            setPadding(dp(42), 0, dp(42), 0)
            maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END
        }, FrameLayout.LayoutParams(-1, dp(42), Gravity.TOP))
        bar.addView(TextView(this).apply {
            text = "‹"; textSize = 28f; setTextColor(Color.WHITE); gravity = Gravity.CENTER
            contentDescription = getString(R.string.back)
            setOnClickListener { back() }
        }, FrameLayout.LayoutParams(dp(42), dp(42), Gravity.START or Gravity.TOP).apply { leftMargin = 10 })
        content.addView(bar, LinearLayout.LayoutParams(-1, dp(44)).apply { bottomMargin = dp(2) })
    }
    private fun settingsRow(title: Int, subtitle: Int, action: () -> Unit) {
        val row = LinearLayout(this).apply {
            gravity = Gravity.CENTER_VERTICAL; minimumHeight = dp(40)
            background = background(Color.rgb(35, 40, 38))
            setPadding(dp(12), dp(3), dp(12), dp(3))
            contentDescription = "${getString(title)}，${getString(subtitle)}"
            setOnClickListener { action() }
        }
        row.addView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER_VERTICAL
            addView(TextView(this@MainActivity).apply {
                text = getString(title); textSize = 12f; setTextColor(Color.WHITE)
                setTypeface(typeface, Typeface.BOLD); maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
            })
            addView(TextView(this@MainActivity).apply {
                text = getString(subtitle); textSize = 9f; setTextColor(Color.LTGRAY)
                maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END
            })
        }, LinearLayout.LayoutParams(0, -2, 1f))
        row.addView(TextView(this).apply {
            text = "›"; textSize = 22f; setTextColor(Color.LTGRAY); gravity = Gravity.CENTER
        }, LinearLayout.LayoutParams(dp(20), -1))
        content.addView(row, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(4) })
    }
    private fun settingsToggle(title: Int, subtitle: Int, checked: Boolean, changed: (Boolean) -> Unit) {
        val row = LinearLayout(this).apply {
            gravity = Gravity.CENTER_VERTICAL; minimumHeight = dp(40)
            background = background(Color.rgb(35, 40, 38))
            setPadding(dp(12), dp(3), dp(10), dp(3))
        }
        row.addView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER_VERTICAL
            addView(TextView(this@MainActivity).apply {
                text = getString(title); textSize = 12f; setTextColor(Color.WHITE)
                setTypeface(typeface, Typeface.BOLD); maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
            })
            addView(TextView(this@MainActivity).apply {
                text = getString(subtitle); textSize = 9f; setTextColor(Color.LTGRAY)
                maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END
            })
        }, LinearLayout.LayoutParams(0, -2, 1f))
        val control = Switch(this).apply {
            text = ""; isChecked = checked
            contentDescription = getString(title)
            thumbTintList = android.content.res.ColorStateList.valueOf(if (checked) Color.rgb(9, 43, 33) else Color.LTGRAY)
            trackTintList = android.content.res.ColorStateList.valueOf(if (checked) Color.rgb(125, 228, 198) else Color.rgb(85, 92, 89))
            setOnCheckedChangeListener { _, value ->
                thumbTintList = android.content.res.ColorStateList.valueOf(if (value) Color.rgb(9, 43, 33) else Color.LTGRAY)
                trackTintList = android.content.res.ColorStateList.valueOf(if (value) Color.rgb(125, 228, 198) else Color.rgb(85, 92, 89))
                changed(value)
            }
        }
        row.addView(control, LinearLayout.LayoutParams(dp(52), dp(34)))
        row.setOnClickListener { control.isChecked = !control.isChecked }
        content.addView(row, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(4) })
    }
    private fun settingsNote(resource: Int) {
        content.addView(TextView(this).apply {
            text = getString(resource); textSize = 11f; setTextColor(Color.LTGRAY)
            gravity = Gravity.CENTER; setPadding(dp(10), dp(9), dp(10), dp(9))
        }, LinearLayout.LayoutParams(-1, -2))
    }
    private fun startVoice() {
        if (voicePending) return
        if (!conversationReady) {
            if (conversationUsesApi) openApiSettings() else navigate("devices")
            return
        }
        voicePending = true
        wake?.setEnabled(false)
        speech?.stop()
        if (page != "home") { page = "home"; render() }
        val launch = {
            if (resumed && page == "home" && !isDestroyed) {
                if (!WatchSpeechInput.launch(this) { startActivityForResult(it, 31) }) {
                    voicePending = false
                    toast(R.string.speech_unavailable)
                    scheduleWakeResume()
                }
            } else voicePending = false
        }
        val handoff = { WatchBackgroundWakeService.stopThen(launch) }
        wake?.stopThen(handoff) ?: handoff()
    }
    @Deprecated("Activity result callback for platform speech UI")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 31) {
            WatchSamsungConfirmService.cancelSession()
            voicePending = false
            scheduleWakeResume()
            if (resultCode != RESULT_OK) { page = "home"; render(); return }
            val result = data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull().orEmpty()
            page = "home"
            if (result.isBlank()) { toast(R.string.speech_empty); render(); return }
            if (busy) {
                draft = result.take(4000); repo.saveDraft(draft)
                render(); conversationView?.setDraft(draft)
                return
            }
            render()
            sendFromHome(result.take(4000))
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
        if (requestCode == 44) {
            val prompt = pendingLocationPrompt; pendingLocationPrompt = null
            if (WatchLocation.permitted(this) && prompt != null) sendFromHome(prompt)
            else toast(R.string.location_permission)
        }
        if (requestCode == 49) {
            setBackgroundWake(checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED &&
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)
        }
        if (requestCode == 43) {
            setWakePreference(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            if (!wakePreference) toast(R.string.wake_permission_needed)
        }
        if (requestCode == 42) {
            if (grantResults.firstOrNull() != PackageManager.PERMISSION_GRANTED) toast(R.string.notification_denied)
            if (page == "settings-feedback") render(true)
        }
    }
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) scheduleVoiceEntry()
    }
    private fun voiceEntryCanStart(): Boolean = voiceEntryPending && resumed && page == "home" &&
        hasWindowFocus() && !voicePending &&
        !getSystemService(android.app.KeyguardManager::class.java).isDeviceLocked

    private fun scheduleVoiceEntry() {
        if (!voiceEntryCanStart() || voiceEntryScheduled) return
        voiceEntryScheduled = true
        handler.post(openVoiceEntry)
    }
    private fun setWakePreference(value: Boolean) {
        wakePreference = value
        repo.store.foregroundWake = value
        wake?.retry()
        if (!value) { repo.store.backgroundWake = false; WatchBackgroundWakeService.stop(this) }
        refreshWake()
        if (page == "settings-wake") render(true)
    }
    private fun setBackgroundWake(value: Boolean) {
        repo.store.backgroundWake = value
        if (value) {
            wakePreference = true
            repo.store.foregroundWake = true
            wake?.stopThen {
                if (resumed && repo.store.backgroundWake && !WatchBackgroundWakeService.start(this)) {
                    repo.store.backgroundWake = false
                    toast(R.string.wake_failed)
                    if (page == "settings-wake") render(true)
                }
                refreshWake()
            }
        } else {
            WatchBackgroundWakeService.stopThen {
                WatchBackgroundWakeService.stop(this)
                refreshWake()
            }
            if (page == "settings-wake") render(true)
            return
        }
        refreshWake()
        if (page == "settings-wake") render(true)
    }
    private fun wakeAllowed(): Boolean = wakePreference && resumed && conversationReady &&
        !voicePending && !voiceEntryPending && speech?.audible != true && draft.isBlank() && conversationView?.input?.hasFocus() != true &&
        checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED &&
        android.os.SystemClock.elapsedRealtime() >= wakeCooldownUntil

    private fun refreshWake() {
        wakePreference = repo.store.foregroundWake
        val speaking = speech?.audible == true
        if (wasSpeaking && !speaking) scheduleWakeResume()
        wasSpeaking = speaking
        val background = repo.store.backgroundWake && wakePreference
        val gate = "on=$wakePreference visible=$resumed ready=$conversationReady pending=$voicePending entry=$voiceEntryPending " +
            "speaking=$speaking draft=${draft.isNotBlank()} focus=${conversationView?.input?.hasFocus() == true} " +
            "cooldown=${android.os.SystemClock.elapsedRealtime() < wakeCooldownUntil} bg=$background"
        if (gate != lastWakeGate) { android.util.Log.i("WatchWakeGate", gate); lastWakeGate = gate }
        wake?.setEnabled(!background && wakeAllowed())
        // A paused MainActivity may still receive speech/repository callbacks after another watch page resumes.
        if (!(application as WatchApplication).anotherActivityIsForeground(this)) {
            WatchBackgroundWakeService.update(background && wakeAllowed(), voicePending || voiceEntryPending || speaking,
                if (resumed) ({
                    if (wakeAllowed()) {
                        wakeCooldownUntil = android.os.SystemClock.elapsedRealtime() + 2500
                        followUpId = selectedTask
                        startVoice()
                    }
                }) else null)
        }
    }
    private fun scheduleWakeResume() {
        wakeCooldownUntil = android.os.SystemClock.elapsedRealtime() + 2500
        handler.removeCallbacks(refreshWakeLater)
        handler.postDelayed(refreshWakeLater, 2600)
    }
    private fun toast(resource: Int) = Toast.makeText(this, resource, Toast.LENGTH_LONG).show()
}
