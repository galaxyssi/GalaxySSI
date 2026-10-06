package com.galaxyssi.glasses

import android.Manifest
import android.app.Activity
import android.media.AudioManager
import android.os.BatteryManager
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.view.Gravity
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.provider.Settings
import android.provider.MediaStore
import androidx.activity.ComponentActivity
import androidx.camera.view.PreviewView
import com.galaxyssi.chat.MicrosoftEdgeTts
import com.galaxyssi.chat.MicrosoftTtsVoiceCatalog
import org.json.JSONArray
import org.json.JSONObject
import org.vosk.Model
import java.io.File
import java.util.Locale
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.zip.ZipInputStream
import kotlin.math.abs

/** Landscape, voice-first conversation surface for the VENUS 640×360 dp optical display. */
class MainActivity : ComponentActivity() {
    private val green = Color.rgb(27, 67, 91)
    private val dim = Color.rgb(68, 104, 126)
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val speechWorker = Executors.newSingleThreadExecutor()
    private val client by lazy { ChatClient(applicationContext) }
    private lateinit var secure: SecureStore
    private lateinit var state: JSONObject
    private var page = "chat"
    private var draft = ""
    private var livePartial = ""
    private var status = ""
    private var lastHeard = ""
    private var listening = false
    private var loadingModel = false
    private var resumed = false
    private var busy = false
    @Volatile private var awake = false
    private var firstHelloAt = 0L
    private var replyVisible = false
    private var setupServer: GlassesPhoneSetupServer? = null
    private var camera: GlassesCamera? = null
    private var pendingCameraAction: String? = null
    private var pendingWifi: WifiQrProvisioning? = null
    private var setupPhase = ""
    private var setupHost = ""
    private var setupPort = 0
    private var setupCode = ""
    private var autoSend: Runnable? = null
    private val setupRetry = object : Runnable {
        override fun run() {
            if (!resumed || setupPhase != "wifi_required") return
            if (GlassesPhoneSetupServer.wifiAddress(this@MainActivity) != null) {
                stopPhoneSetup(); startPhoneSetup()
            } else main.postDelayed(this, 5000)
        }
    }
    private var requestGeneration = 0
    private var currentSession = ""
    private var englishModel: Model? = null
    private var speechGeneration = 0
    private var recognizer: BilingualSpeech? = null
    private var systemTts: TextToSpeech? = null
    private var systemTtsReady = false
    private var edgeTts: MicrosoftEdgeTts? = null
    private var mainText: TextView? = null
    private var subText: TextView? = null
    private var replyText: TextView? = null
    private var replyScroll: ScrollView? = null
    private var waveBars = mutableListOf<View>()
    private var statusLabel: TextView? = null
    private var settingsFeedback: TextView? = null
    private var wifiScanButton: Button? = null
    private val touchControls = mutableListOf<Button>()
    private var touchStarted = false
    private var touchStartedAt = 0L
    private var touchStartX = 0f
    private var touchStartY = 0f
    private var touchLastX = 0f
    private var touchLastY = 0f
    private var touchPointerCount = 0
    private var relativeLastX = Float.NaN
    private var relativeTravelX = 0f
    private var relativeLastAt = 0L
    private var relativeGestureHandled = false
    private val touchTapSlop by lazy { maxOf(dp(10), ViewConfiguration.get(this).scaledTouchSlop).toFloat() }
    private val touchSwipeThreshold by lazy { dp(24).toFloat() }
    private val relativeSwipeThreshold by lazy { dp(12).toFloat() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        status = getString(R.string.glasses_copy_ready)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
        window.setBackgroundDrawableResource(android.R.color.black)
        window.decorView.setBackgroundColor(Color.BLACK)
        secure = SecureStore(this)
        try { state = secure.read() } catch (error: Exception) {
            setContentView(label(error.message ?: getString(R.string.glasses_copy_cannot_open_encrypted_data), 18f))
            return
        }
        currentSession = state.optString("current")
        if (currentSession.isBlank() || findSession(currentSession) == null) newSession(save = false)
        draft = state.optString("draft")
        systemTts = TextToSpeech(this) { result ->
            systemTtsReady = result == TextToSpeech.SUCCESS
            if (systemTtsReady) {
                systemTts?.language = Locale.SIMPLIFIED_CHINESE
                systemTts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) = Unit
                    override fun onDone(utteranceId: String?) { runOnUiThread { if (resumed) startListening() } }
                    @Deprecated("Android TTS callback") override fun onError(utteranceId: String?) { runOnUiThread { if (resumed) startListening() } }
                })
            }
        }
        render()
        if (intent?.action == Intent.ACTION_VOICE_COMMAND) window.decorView.post { startListening() }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == Intent.ACTION_VOICE_COMMAND) startListening()
    }

    private fun sessions(): JSONArray = state.optJSONArray("sessions") ?: JSONArray().also { state.put("sessions", it) }
    private fun findSession(id: String): JSONObject? {
        val all = sessions()
        for (i in 0 until all.length()) if (all.optJSONObject(i)?.optString("id") == id) return all.getJSONObject(i)
        return null
    }
    private fun session(): JSONObject = findSession(currentSession) ?: error("No active session")
    private fun turns(): JSONArray = session().optJSONArray("turns") ?: JSONArray().also { session().put("turns", it) }
    private fun persist() {
        state.put("current", currentSession).put("draft", draft)
        secure.write(state)
    }
    private fun newSession(save: Boolean = true) {
        cancelAutoSend(); awake = false; replyVisible = false; livePartial = ""
        currentSession = UUID.randomUUID().toString()
        sessions().put(JSONObject().put("id", currentSession).put("title", getString(R.string.glasses_copy_new_chat)).put("turns", JSONArray()))
        draft = ""
        if (save) persist()
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    private fun shape(color: Int, radius: Int = 12) = GradientDrawable().apply {
        setColor(color); cornerRadius = dp(radius).toFloat()
    }
    private fun label(text: String, size: Float = 16f, color: Int = Color.WHITE) = TextView(this).apply {
        this.text = text; textSize = size; setTextColor(color); gravity = Gravity.CENTER_VERTICAL
    }
    private fun buttonBackground(primary: Boolean, focused: Boolean) = shape(when {
        focused -> Color.rgb(15, 111, 158)
        primary -> green
        else -> Color.rgb(35, 42, 40)
    }).apply { if (focused) setStroke(dp(3), Color.WHITE) }
    private fun button(text: String, primary: Boolean = false, action: () -> Unit) = Button(this).apply {
        this.text = text; textSize = 15f; isAllCaps = false
        setTextColor(Color.WHITE)
        isFocusable = true; isFocusableInTouchMode = true; defaultFocusHighlightEnabled = false
        background = buttonBackground(primary, false)
        setOnFocusChangeListener { _, focused -> background = buttonBackground(primary, focused) }
        setOnClickListener { action() }
        touchControls.add(this)
    }
    private fun row() = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
    private fun column() = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
    private fun addSpace(parent: LinearLayout, width: Int = 8) {
        parent.addView(View(this), LinearLayout.LayoutParams(dp(width), 1))
    }
    private fun navigate(destination: String) {
        cancelAutoSend(); awake = false; livePartial = ""
        if (page == "camera" && destination != "camera") { camera?.close(); camera = null }
        page = destination; render()
        if (destination == "settings" && resumed && setupServer == null) startPhoneSetup()
        if (resumed) startListening()
    }

    private fun render() {
        touchControls.clear()
        statusLabel = null; settingsFeedback = null; wifiScanButton = null
        mainText = null; subText = null; replyText = null; replyScroll = null; waveBars.clear()
        val root = column().apply {
            setBackgroundColor(Color.BLACK)
            setPadding(dp(24), dp(8), dp(24), dp(10))
        }
        when (page) {
            "settings" -> renderPhoneSetup(root)
            "sessions" -> renderSessions(root)
            "camera" -> renderCamera(root)
            else -> renderVoiceHome(root)
        }
        setContentView(root)
        root.post { touchControls.firstOrNull { it.isShown && it.isEnabled }?.requestFocus() }
    }

    private fun header(root: LinearLayout, title: String, back: Boolean = false) {
        val top = row()
        if (back) {
            top.addView(button(getString(R.string.glasses_copy_back)) { navigate("chat") }, LinearLayout.LayoutParams(dp(88), dp(43)))
            addSpace(top)
        }
        top.addView(label(title, 22f, green).apply { setTypeface(null, Typeface.BOLD) }, LinearLayout.LayoutParams(0, dp(45), 1f))
        root.addView(top)
    }

    private fun renderVoiceHome(root: LinearLayout) {
        val top = row()
        top.addView(button(getString(R.string.glasses_copy_chats)) { navigate("sessions") }, LinearLayout.LayoutParams(dp(76), dp(38)))
        top.addView(label("GalaxySSI", 17f, green).apply {
            gravity = Gravity.CENTER; setTypeface(null, Typeface.BOLD)
        }, LinearLayout.LayoutParams(0, dp(40), 1f))
        top.addView(button(getString(R.string.glasses_copy_camera)) { openCamera() }, LinearLayout.LayoutParams(dp(110), dp(38)))
        top.addView(button(getString(R.string.glasses_copy_phone_setup)) { navigate("settings") }, LinearLayout.LayoutParams(dp(100), dp(38)))
        root.addView(top)

        val center = column().apply { gravity = Gravity.CENTER; setPadding(dp(44), 0, dp(44), 0) }
        root.addView(center, LinearLayout.LayoutParams(-1, 0, 1f))
        val wave = row().apply { gravity = Gravity.CENTER }
        intArrayOf(12, 20, 31, 42, 29, 19, 12).forEach { height ->
            val bar = View(this).apply { background = shape(green, 4) }
            wave.addView(bar, LinearLayout.LayoutParams(dp(5), dp(height)).apply { marginStart = dp(4); marginEnd = dp(4) })
            waveBars.add(bar)
        }
        center.addView(wave, LinearLayout.LayoutParams(-1, dp(52)))
        mainText = label("Hello Hello", 36f, green).apply {
            gravity = Gravity.CENTER; setTypeface(null, Typeface.BOLD); maxLines = 2
        }.also { center.addView(it, LinearLayout.LayoutParams(-1, dp(65))) }
        subText = label(getString(R.string.glasses_copy_say_hello_hello_to_start), 17f, dim).apply {
            gravity = Gravity.CENTER; maxLines = 2
        }.also { center.addView(it, LinearLayout.LayoutParams(-1, dp(48))) }
        replyScroll = ScrollView(this).apply {
            isFillViewport = true; overScrollMode = View.OVER_SCROLL_NEVER
        }.also { center.addView(it, LinearLayout.LayoutParams(-1, dp(120))) }
        replyText = label("", 19f, green).apply { gravity = Gravity.CENTER }.also { replyScroll?.addView(it) }

        val bottom = row().apply { gravity = Gravity.CENTER_VERTICAL }
        bottom.addView(button(getString(R.string.glasses_copy_new_chat)) { cancelAutoSend(); awake = false; newSession(); updateConversationView() }, LinearLayout.LayoutParams(dp(92), dp(42)))
        addSpace(bottom)
        bottom.addView(button(getString(R.string.glasses_copy_replay)) { latestAnswer()?.let(::speak) }, LinearLayout.LayoutParams(dp(100), dp(42)))
        statusLabel = label(status, 12f, dim).apply {
            gravity = Gravity.RIGHT or Gravity.CENTER_VERTICAL; maxLines = 2
        }.also { bottom.addView(it, LinearLayout.LayoutParams(0, dp(42), 1f)) }
        root.addView(bottom)
        updateConversationView()
    }

    private fun updateConversationView() {
        val title = mainText ?: return
        val subtitle = subText ?: return
        val answer = replyText ?: return
        replyScroll?.visibility = if (replyVisible && !awake && !busy) View.VISIBLE else View.GONE
        when {
            setupPhase == "confirm" -> {
                title.text = setupCode.chunked(3).joinToString(" ")
                subtitle.text = getString(R.string.glasses_copy_if_the_digits_match_your_phone_say_hello)
                answer.text = ""
            }
            busy -> { title.text = getString(R.string.glasses_copy_thinking); subtitle.text = getString(R.string.glasses_copy_question_sent); answer.text = "" }
            awake -> { title.text = combinedPrompt().ifBlank { getString(R.string.glasses_copy_please_speak) }; subtitle.text = if (combinedPrompt().isBlank()) getString(R.string.glasses_copy_listening_to_your_question) else getString(R.string.glasses_copy_send_1_5_seconds_after_recognition); answer.text = "" }
            replyVisible -> { title.text = "GalaxySSI"; subtitle.text = getString(R.string.glasses_copy_reply); answer.text = latestAnswer().orEmpty() }
            else -> {
                title.text = "Hello Hello"
                subtitle.text = when {
                    !listening -> if (loadingModel) getString(R.string.glasses_copy_loading_offline_speech_model) else getString(R.string.glasses_copy_starting_microphone)
                    profile() == null -> getString(R.string.glasses_copy_configure_ar_glasses_in_galaxyssi_on_your_phone)
                    else -> getString(R.string.glasses_copy_say_hello_hello_to_start)
                }
                answer.text = ""
            }
        }
    }

    private fun renderCamera(root: LinearLayout) {
        header(root, getString(R.string.glasses_copy_camera_say_hello_hello_take_photo_start_video), true)
        val preview = PreviewView(this)
        root.addView(preview, LinearLayout.LayoutParams(-1, 0, 1f))
        val actions = row().apply { gravity = Gravity.CENTER }
        actions.addView(button(getString(R.string.glasses_copy_photo), true) { camera?.takePhoto() }, LinearLayout.LayoutParams(dp(90), dp(44)))
        addSpace(actions)
        actions.addView(button(getString(R.string.glasses_copy_record)) { camera?.startVideo() }, LinearLayout.LayoutParams(dp(105), dp(44)))
        addSpace(actions)
        actions.addView(button(getString(R.string.glasses_copy_stop_video)) { camera?.stopVideo() }, LinearLayout.LayoutParams(dp(105), dp(44)))
        addSpace(actions)
        wifiScanButton = button(if (pendingWifi == null) getString(R.string.glasses_copy_scan_wi_fi) else getString(R.string.glasses_copy_connect)) {
            if (pendingWifi == null) camera?.scanWifi() else confirmWifi()
        }.also { actions.addView(it, LinearLayout.LayoutParams(dp(120), dp(44))) }
        addSpace(actions)
        actions.addView(button(getString(R.string.glasses_copy_back_2)) { navigate("chat") }, LinearLayout.LayoutParams(dp(80), dp(44)))
        root.addView(actions)
        statusLabel = label(status, 13f, dim).also { root.addView(it, LinearLayout.LayoutParams(-1, dp(28))) }
        camera?.close()
        camera = GlassesCamera(this, preview, { message ->
            setStatus(if (message.startsWith(getString(R.string.glasses_copy_camera_ready)) && pendingWifi != null)
                getString(R.string.glasses_copy_wi_fi_say_hello_hello_to_connect, pendingWifi?.ssid) else message)
            if (message.startsWith(getString(R.string.glasses_copy_camera_ready))) {
                when (pendingCameraAction) {
                    "photo" -> camera?.takePhoto()
                    "video" -> camera?.startVideo()
                    "scan" -> camera?.scanWifi()
                }
                pendingCameraAction = null
            }
        }, { raw ->
            pendingWifi = runCatching { WifiQrProvisioning.parse(raw) }.getOrNull()
            wifiScanButton?.text = getString(R.string.glasses_copy_connect)
            setStatus(getString(R.string.glasses_copy_scanned_wi_fi_confirm_to_request_connection, pendingWifi?.ssid))
        }).also { it.open() }
    }

    private fun renderPhoneSetup(root: LinearLayout) {
        header(root, getString(R.string.glasses_copy_set_up_ar_glasses_from_your_phone), true)
        val center = column().apply { gravity = Gravity.CENTER }
        root.addView(center, LinearLayout.LayoutParams(-1, 0, 1f))
        center.addView(label(getString(R.string.glasses_copy_phone_galaxyssi_my_agent_devices_set_up_ar), 21f, green).apply { gravity = Gravity.CENTER },
            LinearLayout.LayoutParams(-1, dp(60)))
        state.optJSONObject("profile")?.let { saved ->
            center.addView(label(getString(R.string.glasses_copy_current_agent, saved.optString("agent_name").ifBlank { getString(R.string.glasses_copy_cloud_model) }, saved.optString("model")), 15f, dim)
                .apply { gravity = Gravity.CENTER }, LinearLayout.LayoutParams(-1, dp(38)))
        }
        val instructions = when (setupPhase) {
            "wifi_required" -> getString(R.string.glasses_copy_connect_glasses_and_phone_to_the_same_wi)
            "waiting" -> getString(R.string.glasses_copy_waiting_for_phone, setupHost, setupPort)
            "confirm" -> getString(R.string.glasses_copy_check_that_the_digits_match_your_phone)
            "saved" -> getString(R.string.glasses_copy_phone_configuration_saved_securely_ready_to_chat)
            "retry" -> getString(R.string.glasses_copy_connection_incomplete_reconnect_from_your_phone)
            "expired" -> getString(R.string.glasses_copy_setup_timed_out_go_back_and_reopen)
            "network_changed" -> getString(R.string.glasses_copy_wi_fi_changed_reopen_setup)
            "error" -> getString(R.string.glasses_copy_setup_connection_failed_reopen_setup)
            else -> getString(R.string.glasses_copy_starting_phone_setup)
        }
        settingsFeedback = label(instructions, 17f, dim).apply { gravity = Gravity.CENTER }.also {
            center.addView(it, LinearLayout.LayoutParams(-1, dp(48)))
        }
        if (setupPhase == "confirm") {
            center.addView(label(setupCode.chunked(3).joinToString(" "), 45f, green).apply { gravity = Gravity.CENTER },
                LinearLayout.LayoutParams(-1, dp(70)))
            val actions = row().apply { gravity = Gravity.CENTER }
            actions.addView(button(getString(R.string.glasses_copy_match_confirm), true) { setupServer?.confirm(true); setupPhase = "transferring"; render() },
                LinearLayout.LayoutParams(dp(180), dp(48)))
            addSpace(actions)
            actions.addView(button(getString(R.string.glasses_copy_cancel)) { setupServer?.confirm(false); setupPhase = "retry"; render() },
                LinearLayout.LayoutParams(dp(110), dp(48)))
            center.addView(actions)
        } else if (setupPhase in setOf("wifi_required", "retry", "expired", "network_changed", "error")) {
            center.addView(button(getString(R.string.glasses_copy_reconnect_phone), true) { stopPhoneSetup(); startPhoneSetup(); render() },
                LinearLayout.LayoutParams(dp(180), dp(46)).apply { gravity = Gravity.CENTER })
        }
        root.addView(label(getString(R.string.glasses_copy_enter_settings_model_and_key_on_your_phone), 14f, dim).apply { gravity = Gravity.CENTER },
            LinearLayout.LayoutParams(-1, dp(36)))
    }

    private fun renderSessions(root: LinearLayout) {
        header(root, getString(R.string.glasses_copy_recent_chats), true)
        val scroll = ScrollView(this)
        val list = column()
        scroll.addView(list)
        root.addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
        val all = sessions()
        for (i in all.length() - 1 downTo maxOf(0, all.length() - 30)) {
            val item = all.getJSONObject(i)
            val id = item.getString("id")
            list.addView(button(item.optString("title", getString(R.string.glasses_copy_new_chat))) {
                currentSession = id; draft = ""; livePartial = ""; awake = false; replyVisible = false; persist(); navigate("chat")
            }, LinearLayout.LayoutParams(-1, dp(50)).apply { bottomMargin = dp(6) })
        }
        root.addView(button(getString(R.string.glasses_copy_new_chat_2), true) { newSession(); navigate("chat") }, LinearLayout.LayoutParams(-1, dp(48)))
        val voiceStatus = label(status, 13f, dim)
        root.addView(voiceStatus, LinearLayout.LayoutParams(-1, dp(28)))
        statusLabel = voiceStatus
    }

    private fun setStatus(value: String) { status = value; statusLabel?.text = value; settingsFeedback?.text = value }
    private fun addWords(base: String, words: String): String {
        val clean = if (words.any { it.code in 0x4e00..0x9fff }) words.replace(" ", "") else words.trim()
        val separator = if (base.isNotBlank() && clean.firstOrNull()?.code?.let { it < 128 } == true &&
            base.lastOrNull()?.code?.let { it < 128 } == true) " " else ""
        return (base + separator + clean).take(4000)
    }
    private fun combinedPrompt(): String = addWords(draft, livePartial).trim()
    private fun cancelAutoSend() { autoSend?.let(main::removeCallbacks); autoSend = null }
    private fun scheduleAutoSend() {
        cancelAutoSend()
        if (!awake || combinedPrompt().isBlank()) return
        autoSend = Runnable {
            autoSend = null
            if (awake && combinedPrompt().isNotBlank() && !busy && resumed) sendDraft()
        }.also { main.postDelayed(it, 1500) }
    }
    private fun startPhoneSetup() {
        if (setupServer != null) return
        setupPhase = "starting"
        setupServer = GlassesPhoneSetupServer(this,
            onState = { next ->
                setupPhase = next.phase; setupHost = next.host; setupPort = next.port; setupCode = next.code
                if (next.phase in setOf("saved", "expired", "network_changed", "error")) setupServer = null
                if (page == "settings") render() else if (page == "chat") updateConversationView()
                if (next.phase == "wifi_required") main.postDelayed(setupRetry, 5000)
                if (next.phase == "network_changed") main.postDelayed({ if (resumed && setupServer == null) startPhoneSetup() }, 2000)
                if (next.phase == "saved") main.postDelayed({ if (resumed && setupServer == null) startPhoneSetup() }, 2000)
            },
            apply = { payload ->
                if (payload.optString("kind") != "cloud") JSONObject().put("status", "unsupported")
                else {
                    val latch = CountDownLatch(1)
                    var outcome = JSONObject().put("status", "invalid")
                    main.post {
                        try {
                            val raw = payload.getJSONObject("profile")
                            val candidate = Profile(raw.getString("endpoint"), raw.getString("model"),
                                raw.getString("api_key"), raw.optString("api_style", "openai")).validated { getString(it) }
                            state.put("profile", JSONObject().put("endpoint", candidate.endpoint).put("model", candidate.model)
                                .put("key", candidate.key).put("style", candidate.style)
                                .put("agent_name", payload.optString("agent_name").filterNot { Character.isISOControl(it) }.trim().take(80)))
                            persist()
                            outcome = JSONObject().put("status", "saved").put("kind", "cloud")
                        } catch (_: Exception) { outcome = JSONObject().put("status", "invalid") }
                        finally { latch.countDown() }
                    }
                    if (latch.await(15, TimeUnit.SECONDS)) outcome else JSONObject().put("status", "timeout")
                }
            })
        setupServer?.start()
    }
    private fun stopPhoneSetup() {
        main.removeCallbacks(setupRetry)
        setupServer?.close(); setupServer = null; setupPhase = ""; setupCode = ""
    }
    private fun profile(): Profile? = state.optJSONObject("profile")?.let {
        Profile(it.optString("endpoint"), it.optString("model"), it.optString("key"), it.optString("style"))
    }
    private fun sendDraft() {
        cancelAutoSend()
        val prompt = combinedPrompt()
        if (prompt.isBlank() || busy) return
        val profile = profile()
        if (profile == null) {
            draft = ""; livePartial = ""; awake = false; replyVisible = false
            persist(); setStatus(getString(R.string.glasses_copy_no_agent_configured_tap_phone_setup_at_the))
            updateConversationView()
            return
        }
        stopListening(); stopSpeaking()
        awake = false; replyVisible = false
        val conversation = session()
        val history = turns()
        history.put(JSONObject().put("role", "user").put("text", prompt))
        if (history.length() == 1) conversation.put("title", prompt.take(24))
        draft = ""; livePartial = ""; persist(); updateConversationView()
        busy = true; setStatus(getString(R.string.glasses_copy_waiting_for_reply)); updateConversationView()
        val generation = ++requestGeneration
        val requestSession = currentSession
        val snapshot = JSONArray(history.toString())
        worker.execute {
            val result = runCatching { client.answer(profile, snapshot) }
            runOnUiThread {
                if (generation != requestGeneration || isDestroyed) return@runOnUiThread
                busy = false
                if (result.isSuccess) {
                    val answer = result.getOrThrow()
                    findSession(requestSession)?.optJSONArray("turns")?.put(
                        JSONObject().put("role", "assistant").put("text", answer))
                    persist(); if (requestSession == currentSession) updateConversationView()
                    replyVisible = true; updateConversationView()
                    setStatus(getString(R.string.glasses_copy_reply_received_tap_to_read_aloud))
                    speak(answer)
                } else { setStatus(getString(R.string.glasses_copy_request_failed, result.exceptionOrNull()?.message ?: getString(R.string.glasses_copy_unknown_error))); updateConversationView() }
                if (result.isFailure && resumed) startListening()
            }
        }
    }

    private fun speak(text: String) {
        stopListening(); stopSpeaking()
        val spoken = text.replace(Regex("[`*_#>\\[\\]]"), " ").take(1200)
        if (spoken.isBlank()) { if (resumed) startListening(); return }
        if (systemTtsReady && (systemTts?.isLanguageAvailable(Locale.SIMPLIFIED_CHINESE) ?: -1) >= TextToSpeech.LANG_AVAILABLE) {
            systemTts?.speak(spoken, TextToSpeech.QUEUE_FLUSH, null, "galaxyssi-reply")
            setStatus(getString(R.string.glasses_copy_speaking))
        } else {
            if (edgeTts == null) edgeTts = MicrosoftEdgeTts(applicationContext)
            setStatus(getString(R.string.glasses_copy_synthesizing_speech))
            edgeTts?.speak(spoken, MicrosoftTtsVoiceCatalog.XIAOXIAO) { success, _ ->
                runOnUiThread {
                    setStatus(if (success) getString(R.string.glasses_copy_speech_complete) else getString(R.string.glasses_copy_speech_playback_failed_check_the_network))
                    if (resumed) startListening()
                }
            }
        }
    }
    private fun stopSpeaking() { systemTts?.stop(); edgeTts?.stop() }

    private fun startListening() {
        if (listening || loadingModel) return
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 10)
            return
        }
        stopSpeaking()
        if (englishModel == null) {
            loadingModel = true; setStatus(getString(R.string.glasses_copy_loading_whisper_tiny_and_wake_word_model))
            worker.execute {
                val loaded = runCatching {
                    WhisperTinyNative.load(WhisperTinyNative.prepareModel(this))
                    Model(unpackModel("vosk-model-small-en-us-0.15").absolutePath)
                }
                runOnUiThread {
                    loadingModel = false
                    loaded.onSuccess { en ->
                        englishModel = en
                        if (resumed) startListening()
                    }
                        .onFailure { setStatus(getString(R.string.glasses_copy_speech_model_failed_to_load, it.message)) }
                }
            }
            return
        }
        try {
            recognizer = BilingualSpeech(this, englishModel!!, isAwake = { awake },
                onLevel = { level -> if (listening) {
                    waveBars.forEachIndexed { i, bar -> bar.alpha = (0.3f + ((level + i * 13) % 70) / 100f).coerceAtMost(1f) }
                    if (page == "chat" && status in setOf(
                        getString(R.string.glasses_copy_listening), getString(R.string.glasses_copy_listening_to_question), getString(R.string.glasses_copy_waiting_for_hello_hello), getString(R.string.glasses_copy_say_hello_once_more), getString(R.string.glasses_copy_ready)
                    )) setStatus(when {
                        awake -> getString(R.string.glasses_copy_listening_to_question)
                        firstHelloAt != 0L && SystemClock.elapsedRealtime() - firstHelloAt < 7000 -> getString(R.string.glasses_copy_say_hello_once_more)
                        else -> getString(R.string.glasses_copy_waiting_for_hello_hello)
                    })
                } },
                onPartial = { partial -> if (listening) {
                    lastHeard = partial
                    if (!awake && wakePhrase.containsMatchIn(partial)) {
                        awake = true; lastHeard = ""; replyVisible = false; firstHelloAt = 0L; updateConversationView()
                    }
                } },
                onFinal = { result -> if (listening) {
                    lastHeard = ""
                    livePartial = ""
                    recognized(result)
                } },
                onUtterance = { pcm, done ->
                    val generation = speechGeneration
                    setStatus(getString(R.string.glasses_copy_recognizing))
                    speechWorker.execute {
                        val started = SystemClock.elapsedRealtime()
                        val result = runCatching { WhisperTinyNative.transcribe(pcm) }
                        Log.d("GalaxySpeech", "Whisper decode ms=${SystemClock.elapsedRealtime() - started} success=${result.isSuccess} chars=${result.getOrNull()?.length ?: 0}")
                        runOnUiThread {
                            done()
                            if (listening && generation == speechGeneration) {
                                result.onSuccess { text ->
                                    val cleaned = text.trim().trim('。', '.', '!', '！', '?', '？', '，', ',')
                                    if (cleaned.isNotBlank()) {
                                        lastHeard = ""
                                        recognized(cleaned)
                                    } else setStatus(getString(R.string.glasses_copy_no_speech_recognized_please_try_again))
                                }.onFailure {
                                    setStatus(if (it.message?.contains("timed out") == true)
                                        getString(R.string.glasses_copy_recognition_timed_out_please_try_again) else getString(R.string.glasses_copy_whisper_tiny_recognition_failed, it.message))
                                }
                            }
                        }
                    }
                },
                onError = { reason ->
                    stopListening(); setStatus(getString(R.string.glasses_copy_speech_recognition_failed, reason))
                    if (resumed) main.postDelayed({ if (resumed) startListening() }, 1200)
                })
            listening = true
            recognizer?.start()
            setStatus(if (awake) getString(R.string.glasses_copy_listening_to_question) else getString(R.string.glasses_copy_waiting_for_hello_hello))
            updateConversationView()
        } catch (error: Exception) {
            listening = false; recognizer?.stop(); recognizer = null
            setStatus(getString(R.string.glasses_copy_cannot_use_microphone, error.message))
        }
    }

    private fun unpackModel(name: String): File {
        val target = File(filesDir, name)
        if (File(target, "am/final.mdl").isFile) return target
        target.mkdirs()
        assets.open("$name.zip").use { raw ->
            ZipInputStream(raw).use { zip ->
                while (true) {
                    val entry = zip.nextEntry ?: break
                    val name = entry.name.substringAfter("/")
                    if (name.isNotBlank()) {
                        val output = File(target, name)
                        require(output.canonicalPath.startsWith(target.canonicalPath + File.separator))
                        if (entry.isDirectory) output.mkdirs()
                        else { output.parentFile?.mkdirs(); output.outputStream().use { zip.copyTo(it) } }
                    }
                    zip.closeEntry()
                }
            }
        }
        check(File(target, "am/final.mdl").isFile) { getString(R.string.glasses_copy_model_is_incomplete, name) }
        return target
    }

    private fun stopListening() {
        if (!listening && recognizer == null) return
        speechGeneration++
        listening = false
        recognizer?.stop(); recognizer = null
        setStatus(getString(R.string.glasses_copy_voice_input_stopped))
    }

    private val wakePhrase = Regex("(?i)\\bhello[\\s,，。.!?]*hello\\b")
    private val singleHello = Regex("(?i)^hello[\\s,，。.!?]*$")
    private fun stripSpokenWake(text: String) = VoiceCommandCatalog.stripSpokenWake(text)
    private fun confirmWifi() {
        val wifi = pendingWifi
        if (wifi == null) { setStatus(getString(R.string.glasses_copy_scan_the_phone_wi_fi_code_first)); return }
        pendingWifi = null
        wifiScanButton?.text = getString(R.string.glasses_copy_scan_wi_fi)
        val accepted = runCatching { wifi.suggest(this) }.getOrDefault(false)
        setStatus(if (accepted) getString(R.string.glasses_copy_requested_connection_to_approve_the_system_prompt, wifi.ssid) else getString(R.string.glasses_copy_system_did_not_accept_the_wi_fi_request))
    }
    private fun openCamera(action: String? = null) {
        pendingCameraAction = action ?: pendingCameraAction
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.CAMERA), 11)
            return
        }
        navigate("camera")
    }
    private fun executeDeviceCommand(text: String): Boolean {
        val command = VoiceCommandCatalog.resolve(text) ?: return false
        if (command == VoiceCommand.SEND) {
            if (draft.isBlank() && livePartial.isNotBlank()) draft = livePartial
            livePartial = ""
            sendDraft()
            return true
        }
        cancelAutoSend(); draft = ""; livePartial = ""; awake = false
        when (command) {
            VoiceCommand.CLEAR -> setStatus(getString(R.string.glasses_copy_cleared_listening))
            VoiceCommand.SPEAK_REPLY -> latestAnswer()?.let(::speak) ?: setStatus(getString(R.string.glasses_copy_no_reply_to_read_aloud))
            VoiceCommand.STOP_SPEAKING -> { stopSpeaking(); setStatus(getString(R.string.glasses_copy_speech_stopped)) }
            VoiceCommand.NEW_CHAT -> { newSession(); render() }
            VoiceCommand.OPEN_SETTINGS -> navigate("settings")
            VoiceCommand.STOP_CONFIGURATION -> {
                pendingWifi = null
                setupServer?.confirm(false)
                stopPhoneSetup()
                navigate("chat")
                setStatus(getString(R.string.glasses_copy_setup_stopped))
            }
            VoiceCommand.CONFIRM_PAIRING -> {
                if (setupPhase == "confirm") { setupServer?.confirm(true); setupPhase = "transferring"; setStatus(getString(R.string.glasses_copy_pairing_confirmed)) }
                else setStatus(getString(R.string.glasses_copy_no_pairing_awaiting_confirmation))
            }
            VoiceCommand.CANCEL_PAIRING -> { setupServer?.confirm(false); setStatus(getString(R.string.glasses_copy_pairing_canceled)) }
            VoiceCommand.OPEN_CHAT -> navigate("chat")
            VoiceCommand.OPEN_SESSIONS -> navigate("sessions")
            VoiceCommand.OPEN_CAMERA -> openCamera()
            VoiceCommand.SCAN_WIFI -> {
                if (page != "camera") openCamera("scan") else camera?.scanWifi()
            }
            VoiceCommand.CONFIRM_WIFI -> confirmWifi()
            VoiceCommand.CANCEL_WIFI -> { pendingWifi = null; wifiScanButton?.text = getString(R.string.glasses_copy_scan_wi_fi); setStatus(getString(R.string.glasses_copy_connection_canceled)) }
            VoiceCommand.TAKE_PHOTO -> { if (page != "camera") openCamera("photo") else camera?.takePhoto() }
            VoiceCommand.START_RECORDING -> { if (page != "camera") openCamera("video") else camera?.startVideo() }
            VoiceCommand.STOP_RECORDING -> camera?.stopVideo() ?: setStatus(getString(R.string.glasses_copy_no_recording_in_progress))
            VoiceCommand.OPEN_GALLERY -> runCatching {
                startActivity(Intent(Intent.ACTION_VIEW, MediaStore.Images.Media.EXTERNAL_CONTENT_URI).apply { type = "image/*" })
            }.onFailure { setStatus(getString(R.string.glasses_copy_cannot_open_gallery)) }
            VoiceCommand.HOME -> startActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME))
            VoiceCommand.OPEN_WIFI_SETTINGS -> startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
            VoiceCommand.OPEN_BLUETOOTH_SETTINGS -> startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
            VoiceCommand.VOLUME_UP -> { getSystemService(AudioManager::class.java).adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_RAISE, 0); setStatus(getString(R.string.glasses_copy_volume_increased)) }
            VoiceCommand.VOLUME_DOWN -> { getSystemService(AudioManager::class.java).adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_LOWER, 0); setStatus(getString(R.string.glasses_copy_volume_decreased)) }
            VoiceCommand.BATTERY -> setStatus(getString(R.string.glasses_copy_battery, getSystemService(BatteryManager::class.java).getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)))
            VoiceCommand.TIME -> setStatus(java.text.SimpleDateFormat("HH:mm", Locale.CHINA).format(java.util.Date()))
            VoiceCommand.HELP -> setStatus(getString(R.string.glasses_copy_say_take_photo_record_video_stop_video_scan))
            VoiceCommand.SEND -> Unit
        }
        updateConversationView()
        return true
    }
    private fun recognized(text: String) {
        if (!listening) return
        val hasWake = wakePhrase.containsMatchIn(text)
        if (!awake) {
            val now = SystemClock.elapsedRealtime()
            val twoSeparateHellos = singleHello.matches(text) && now - firstHelloAt in 1..7000
            if (!hasWake && !twoSeparateHellos) {
                if (singleHello.matches(text)) { firstHelloAt = now; setStatus(getString(R.string.glasses_copy_say_hello_once_more)) }
                return
            }
            firstHelloAt = 0L
            awake = true; replyVisible = false; draft = ""; updateConversationView()
            if (twoSeparateHellos) return
        }
        val clean = stripSpokenWake(wakePhrase.replaceFirst(text, ""))
            .trim(',', '，', '。', '.', '!', '?', ' ')
        if (clean.isBlank() || singleHello.matches(clean)) { updateConversationView(); return }
        if (clean.isBlank()) return
        if (!executeDeviceCommand(clean)) {
                if (page != "chat") { page = "chat"; render() }
                val words = if (clean.any { it.code in 0x4e00..0x9fff }) clean.replace(" ", "") else clean
                val separator = if (draft.isNotBlank() && words.firstOrNull()?.isLetter() == true &&
                    words.first().code < 128 && draft.lastOrNull()?.code?.let { it < 128 } == true) " " else ""
                draft = (draft + separator + words).take(4000)
                setStatus(getString(R.string.glasses_copy_recognized_sending_in_1_5_seconds))
                updateConversationView(); scheduleAutoSend()
        }
    }
    private fun latestAnswer(): String? {
        val all = turns()
        for (i in all.length() - 1 downTo 0) {
            val turn = all.optJSONObject(i) ?: continue
            if (turn.optString("role") == "assistant") return turn.optString("text")
        }
        return null
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, results: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, results)
        if (requestCode == 11) {
            if (results.firstOrNull() == PackageManager.PERMISSION_GRANTED) openCamera(pendingCameraAction)
            else { pendingCameraAction = null; setStatus(getString(R.string.glasses_copy_camera_permission_is_required_for_photos_and_videos)) }
        }
        if (requestCode == 10) {
            if (results.firstOrNull() == PackageManager.PERMISSION_GRANTED) startListening()
            else setStatus(getString(R.string.glasses_copy_microphone_permission_is_required_for_voice_input))
        }
    }

    private fun availableTouchControls() = touchControls.filter { it.isShown && it.isEnabled }

    private fun moveTouchFocus(next: Boolean) {
        val controls = availableTouchControls()
        if (controls.isEmpty()) return
        val current = controls.indexOfFirst { it.hasFocus() }
        val target = when {
            current < 0 -> controls.first()
            next -> controls[(current + 1) % controls.size]
            else -> controls[(current - 1 + controls.size) % controls.size]
        }
        target.requestFocus()
        target.requestRectangleOnScreen(android.graphics.Rect(0, 0, target.width, target.height), true)
    }

    private fun activateTouchFocus() {
        val controls = availableTouchControls()
        if (controls.isEmpty()) return
        val target = controls.firstOrNull { it.hasFocus() } ?: controls.first().also { it.requestFocus() }
        target.performClick()
    }

    private fun performTouchpadBack() {
        if (page != "chat") navigate("chat") else onBackPressedDispatcher.onBackPressed()
    }

    private fun performTouchpadAction(action: TouchpadAction): Boolean {
        when (action) {
            TouchpadAction.ACTIVATE -> activateTouchFocus()
            TouchpadAction.BACK -> performTouchpadBack()
            TouchpadAction.NEXT -> moveTouchFocus(true)
            TouchpadAction.PREVIOUS -> moveTouchFocus(false)
            TouchpadAction.NONE -> return false
        }
        return true
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                touchStarted = true
                touchStartedAt = event.eventTime
                touchStartX = event.x; touchStartY = event.y
                touchLastX = event.x; touchLastY = event.y
                touchPointerCount = event.pointerCount
                return true
            }
            MotionEvent.ACTION_POINTER_DOWN, MotionEvent.ACTION_MOVE, MotionEvent.ACTION_POINTER_UP -> {
                if (touchStarted) {
                    touchPointerCount = maxOf(touchPointerCount, event.pointerCount)
                    touchLastX = event.x; touchLastY = event.y
                    return true
                }
            }
            MotionEvent.ACTION_UP -> {
                if (touchStarted) {
                    touchLastX = event.x; touchLastY = event.y
                    val action = TouchpadGestureClassifier.classify(
                        touchPointerCount,
                        event.eventTime - touchStartedAt,
                        touchLastX - touchStartX,
                        touchLastY - touchStartY,
                        touchTapSlop,
                        touchSwipeThreshold
                    )
                    Log.d("GalaxyTouchpad", "pointers=$touchPointerCount duration=${event.eventTime - touchStartedAt} dx=${touchLastX - touchStartX} dy=${touchLastY - touchStartY} action=$action")
                    touchStarted = false
                    performTouchpadAction(action)
                    return true
                }
            }
            MotionEvent.ACTION_CANCEL -> {
                touchStarted = false
                return true
            }
        }
        return super.dispatchTouchEvent(event)
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        if (event.isFromSource(InputDevice.SOURCE_CLASS_POINTER)) {
            if (event.actionMasked == MotionEvent.ACTION_SCROLL) {
                val horizontal = event.getAxisValue(MotionEvent.AXIS_HSCROLL)
                if (abs(horizontal) >= 0.1f) {
                    moveTouchFocus(next = horizontal < 0f)
                    return true
                }
            }
            if (event.actionMasked == MotionEvent.ACTION_HOVER_MOVE || event.actionMasked == MotionEvent.ACTION_MOVE) {
                val now = event.eventTime
                if (now - relativeLastAt > 140) {
                    relativeTravelX = 0f
                    relativeGestureHandled = false
                }
                val relativeAxis = event.getAxisValue(MotionEvent.AXIS_RELATIVE_X)
                val delta = when {
                    abs(relativeAxis) > 0.01f -> relativeAxis
                    relativeLastX.isNaN() -> 0f
                    else -> event.x - relativeLastX
                }
                relativeTravelX += delta
                relativeLastX = event.x
                relativeLastAt = now
                if (!relativeGestureHandled && abs(relativeTravelX) >= relativeSwipeThreshold) {
                    moveTouchFocus(next = relativeTravelX < 0f)
                    Log.d("GalaxyTouchpad", "relative dx=$relativeTravelX")
                    relativeGestureHandled = true
                    return true
                }
            }
            if (event.actionMasked == MotionEvent.ACTION_BUTTON_RELEASE) {
                when (event.actionButton) {
                    MotionEvent.BUTTON_PRIMARY -> { activateTouchFocus(); return true }
                    MotionEvent.BUTTON_SECONDARY -> { performTouchpadBack(); return true }
                }
            }
        }
        return super.dispatchGenericMotionEvent(event)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        Log.d("GalaxyTouchpad", "key code=${event.keyCode} action=${event.action}")
        val handled = event.keyCode in setOf(
            KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER, KeyEvent.KEYCODE_DPAD_CENTER,
            KeyEvent.KEYCODE_BUTTON_SELECT, KeyEvent.KEYCODE_SPACE, KeyEvent.KEYCODE_F12,
            KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_DOWN,
            KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_DPAD_UP,
            KeyEvent.KEYCODE_ESCAPE, KeyEvent.KEYCODE_BACK
        )
        if (!handled) return super.dispatchKeyEvent(event)
        if (event.action == KeyEvent.ACTION_UP) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER, KeyEvent.KEYCODE_DPAD_CENTER,
                KeyEvent.KEYCODE_BUTTON_SELECT, KeyEvent.KEYCODE_SPACE, KeyEvent.KEYCODE_F12 -> activateTouchFocus()
                KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_DOWN -> moveTouchFocus(true)
                KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_DPAD_UP -> moveTouchFocus(false)
                KeyEvent.KEYCODE_ESCAPE, KeyEvent.KEYCODE_BACK -> performTouchpadBack()
            }
        }
        return true
    }

    override fun onBackPressed() {
        if (page != "chat") navigate("chat") else super.onBackPressed()
    }
    override fun onPause() {
        resumed = false
        cancelAutoSend(); awake = false; stopPhoneSetup()
        camera?.close(); camera = null
        stopListening()
        if (::state.isInitialized) persist()
        super.onPause()
    }
    override fun onResume() {
        super.onResume()
        resumed = true
        if (::state.isInitialized) startPhoneSetup()
        if (page == "camera" && camera == null) render()
        if (::state.isInitialized) window.decorView.post { if (resumed) startListening() }
    }
    override fun onStop() { super.onStop() }
    override fun onDestroy() {
        cancelAutoSend(); stopPhoneSetup()
        camera?.close(); camera = null
        stopSpeaking(); systemTts?.shutdown(); edgeTts?.shutdown()
        englishModel?.close(); worker.shutdownNow()
        speechWorker.execute { WhisperTinyNative.close() }; speechWorker.shutdown()
        super.onDestroy()
    }
}
