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
import android.speech.tts.TextToSpeech
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
    private var speechReady = false
    private var speech: TextToSpeech? = null
    private var lastSpokenTask = ""
    private lateinit var content: LinearLayout
    private lateinit var scroll: ScrollView
    private val handler = Handler(Looper.getMainLooper())
    private val saveDraft = Runnable { repo.store.draft = draft }
    private val updated: () -> Unit = {
        if (page !in setOf("compose", "pair", "pair-review", "api-edit", "api-review")) render(true)
        val task = repo.store.task(selectedTask)
        if (page == "task" && repo.store.autoSpeech && task?.state == TaskState.COMPLETED &&
            task.reply.isNotBlank() && task.id != lastSpokenTask) {
            lastSpokenTask = task.id; speak(task.reply)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE == 0) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        page = savedInstanceState?.getString("page") ?: "home"
        selectedTask = savedInstanceState?.getString("task") ?: ""
        followUpId = savedInstanceState?.getString("followup") ?: ""
        detailDesktop = savedInstanceState?.getString("desktop") ?: ""
        draft = savedInstanceState?.getString("draft") ?: repo.store.draft
        history.addAll(savedInstanceState?.getStringArrayList("history") ?: emptyList())
        // Pairing offers are intentionally not saved into instance state or logs.
        if (page.startsWith("pair")) page = "devices"
        if (page.startsWith("api-")) page = "settings"
        speech = TextToSpeech(this) { status ->
            speechReady = status == TextToSpeech.SUCCESS
            if (speechReady) speech?.language = Locale.getDefault()
        }
        onBackInvokedDispatcher.registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT) { back() }
        readLaunchIntent(intent)
        render()
    }

    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); readLaunchIntent(intent); render() }
    private fun readLaunchIntent(intent: Intent) {
        intent.getStringExtra("task_id")?.takeIf { repo.store.task(it) != null }?.let { selectedTask = it; page = "task" }
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
        resumed = false; repo.conversationVisibility.hide(this); super.onPause()
    }
    private fun updateConversationVisibility() {
        if (!resumed) return
        val task = if (page == "task") repo.store.task(selectedTask) else null
        repo.conversationVisibility.show(this, task)
        if (task != null) WatchNotifications.dismissConversation(this, repo.store.tasks(), task)
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

    private fun navigate(destination: String) { history.addLast(page); page = destination; render() }
    private fun back() {
        if (busy) return
        speech?.stop()
        if (page == "home") { finish(); return }
        if (page.startsWith("pair")) { pairingOffer = null; pairingText = "" }
        if (page.startsWith("api-")) { apiOffer = null; apiKey = "" }
        page = if (history.isEmpty()) "home" else history.removeLast()
        render()
    }
    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
    private fun background(color: Int) = GradientDrawable().apply { setColor(color); cornerRadius = dp(26).toFloat() }
    private val green = Color.rgb(20, 198, 106)

    private fun render(preserveScroll: Boolean = false) {
        updateConversationVisibility()
        val offset = if (preserveScroll && ::scroll.isInitialized) scroll.scrollY else 0
        editor = null
        if (page == "api-edit") window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        else if (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
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
            "home" -> home()
            "devices" -> devices()
            "device" -> device()
            "agents" -> agents()
            "sessions" -> sessions()
            "compose" -> compose()
            "task" -> task()
            "stop" -> confirmStop()
            "pair" -> pairInput()
            "pair-review" -> pairReview()
            "forget" -> confirmForget()
            "settings" -> settings()
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
            else -> { page = "home"; home() }
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

    private fun home() {
        title(R.string.app_name)
        val link = repo.links().firstOrNull { it.desktopId == repo.store.selectedDesktop }
        val api = repo.store.apiProfile?.takeIf { repo.store.apiPreferred }
        label(if (api != null) getString(R.string.api_ready, api.model) else link?.desktopName ?: getString(R.string.home_not_paired), 12)
        if (link != null && api == null) label(getString(if (repo.online(link.desktopId)) R.string.online else connectionLabel()), 12, green)
        if (link?.paired == true || api != null) {
            button(R.string.say_something, true) { followUpId = ""; startVoice() }
        } else {
            button(R.string.connect_service, true) { navigate("devices") }
        }
        button(R.string.recent) { navigate("sessions") }
        button(R.string.devices) { navigate("devices") }
        button(R.string.settings) { navigate("settings") }
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
                repo.store.selectedAgent = agent.id; followUpId = ""; navigate("compose")
            }
        }
        button(R.string.refresh) { repo.refresh() }
    }
    private fun sessions() {
        title(R.string.recent)
        val tasks = repo.store.tasks()
        if (tasks.isEmpty()) label(getString(R.string.empty_sessions))
        tasks.groupBy { it.conversationId }.values.take(30).forEach { turns ->
            val task = turns.first()
            button("${task.prompt.take(26)}\n${getString(task.state.label())}") { selectedTask = task.id; navigate("task") }
        }
        button(R.string.new_conversation) { followUpId = ""; navigate("compose") }
    }
    private fun compose() {
        title(R.string.review_message)
        val previous = repo.store.task(followUpId)
        val desktop = previous?.desktopId ?: repo.store.selectedDesktop
        val agent = previous?.agentId ?: repo.store.selectedAgent
        val link = repo.links().firstOrNull { it.desktopId == desktop }
        val usingApi = previous?.desktopId == "api" || (previous == null && repo.store.apiPreferred)
        val api = repo.store.apiProfile
        label(getString(R.string.recipient, if (usingApi) api?.let { "${java.net.URI(it.endpoint).host} · ${it.model}" }.orEmpty()
            else listOfNotNull(link?.desktopName, agent.takeIf { it.isNotBlank() }).joinToString(" · ")))
        if (usingApi && (api == null || (previous != null && previous.routeId != api.id))) {
            label(getString(R.string.api_invalid)); button(R.string.api_title) { openApiSettings() }; return
        }
        if (!usingApi && (link?.paired != true || agent.isBlank())) {
            button(R.string.devices, true) { navigate("devices") }; return
        }
        input(draft, R.string.message_hint, 4000) { draft = it; handler.removeCallbacks(saveDraft); handler.postDelayed(saveDraft, 350) }
        button(if (busy) R.string.sending else R.string.send, true) {
            if (!busy && draft.isNotBlank()) {
                busy = true; editor?.clearFocus()
                (getSystemService(INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager).hideSoftInputFromWindow(editor?.windowToken, 0)
                repo.send(draft, previous) { task ->
                    busy = false
                    if (isDestroyed || isFinishing) return@send
                    if (task == null) toast(R.string.send_failed) else {
                        draft = ""; repo.store.draft = ""; selectedTask = task.id; followUpId = ""
                        runCatching { startForegroundService(Intent(this, WatchConnectionService::class.java)) }
                        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 42)
                        }
                        page = "task"
                    }
                    render()
                }
            }
        }.isEnabled = !busy
        button(R.string.record_again) { startVoice() }
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
    private fun task() {
        val task = repo.store.task(selectedTask) ?: return
        label(getString(task.state.label()), 18, green, true)
        label(task.prompt, 14, Color.WHITE)
        if (task.progress.isNotBlank()) label(task.progress)
        if (task.reply.isNotBlank()) {
            label(task.reply, 15, Color.WHITE)
            button(R.string.read_aloud) { speak(task.reply) }
            button(R.string.stop_speech) { speech?.stop() }
        } else if (!task.state.terminal) label(getString(if (task.desktopId == "api") R.string.awaiting_api else R.string.awaiting_result))
        if (task.state == TaskState.WAITING_APPROVAL) label(getString(R.string.approval_help))
        if (task.state in setOf(TaskState.QUEUED, TaskState.SENT)) button(R.string.retry) { repo.retry(task) }
        if (!task.state.terminal && task.state != TaskState.STOP_REQUESTED) button(R.string.stop_task) { navigate("stop") }
        button(R.string.follow_up, true) { followUpId = task.id; startVoice() }
        button(R.string.text_input) { followUpId = task.id; navigate("compose") }
        repo.store.tasks().filter { it.conversationKey() == task.conversationKey() && it.id != task.id }.take(10).forEach { older ->
            button(older.prompt.take(30)) { selectedTask = older.id; render() }
            if (older.reply.isNotBlank()) label(older.reply, 15, Color.WHITE)
        }
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
        toggle(R.string.vibrate, repo.store.vibration) { repo.store.vibration = it }
        toggle(R.string.auto_speech, repo.store.autoSpeech) { repo.store.autoSpeech = it }
        button(R.string.notifications) { requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 42) }
        button(R.string.devices) { navigate("devices") }
        button(R.string.api_title) { openApiSettings() }
        label(getString(R.string.about), 12)
        label(getString(R.string.monitor_body), 12)
    }
    private fun toggle(resource: Int, checked: Boolean, changed: (Boolean) -> Unit) {
        content.addView(Switch(this).apply {
            text = getString(resource); setTextColor(Color.WHITE); textSize = 14f
            minHeight = dp(48); isChecked = checked
            setOnCheckedChangeListener { _, value -> changed(value) }
        }, LinearLayout.LayoutParams(-1, -2))
    }
    private fun startVoice() {
        val previous = repo.store.task(followUpId)
        val usingApi = previous?.desktopId == "api" || (previous == null && repo.store.apiPreferred)
        if (usingApi && repo.store.apiProfile == null) { openApiSettings(); return }
        if (!usingApi && ((previous?.desktopId ?: repo.store.selectedDesktop).isBlank() || (previous?.agentId ?: repo.store.selectedAgent).isBlank())) {
            navigate("devices"); return
        }
        if (page != "compose") navigate("compose")
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            .putExtra(RecognizerIntent.EXTRA_PROMPT, getString(R.string.speech_prompt))
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault().toLanguageTag())
        runCatching { startActivityForResult(intent, 31) }.onFailure { toast(R.string.speech_unavailable) }
    }
    @Deprecated("Activity result callback for platform speech UI")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 31 && resultCode == RESULT_OK) {
            val result = data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull().orEmpty()
            if (result.isBlank()) toast(R.string.speech_empty) else { draft = result.take(4000); repo.store.draft = draft }
            page = "compose"; render()
        }
    }
    private fun speak(text: String) {
        if (!speechReady || (speech?.isLanguageAvailable(Locale.getDefault()) ?: -1) < 0) { toast(R.string.speech_output_unavailable); return }
        speech?.speak(text.take(TextToSpeech.getMaxSpeechInputLength()), TextToSpeech.QUEUE_FLUSH, null, "watch-reply")
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
            button(R.string.api_use) { repo.store.apiPreferred = true; followUpId = ""; page = "home"; render() }
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
            page = "home"; history.clear(); render()
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
