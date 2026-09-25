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
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.view.Gravity
import android.view.View
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

/** Landscape, voice-first conversation surface for the VENUS 640×360 dp optical display. */
class MainActivity : ComponentActivity() {
    private val green = Color.rgb(27, 67, 91)
    private val dim = Color.rgb(68, 104, 126)
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val client = ChatClient()
    private lateinit var secure: SecureStore
    private lateinit var state: JSONObject
    private var page = "chat"
    private var draft = ""
    private var livePartial = ""
    private var status = "就绪"
    private var lastHeard = ""
    private var listening = false
    private var loadingModel = false
    private var resumed = false
    private var busy = false
    private var awake = false
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
    private var chineseModel: Model? = null
    private var englishModel: Model? = null
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        secure = SecureStore(this)
        try { state = secure.read() } catch (error: Exception) {
            setContentView(label(error.message ?: "无法打开加密数据", 18f))
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
        sessions().put(JSONObject().put("id", currentSession).put("title", "新对话").put("turns", JSONArray()))
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
    private fun button(text: String, primary: Boolean = false, action: () -> Unit) = Button(this).apply {
        this.text = text; textSize = 15f; isAllCaps = false
        setTextColor(Color.WHITE)
        background = shape(if (primary) green else Color.rgb(35, 42, 40))
        setOnClickListener { action() }
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
        statusLabel = null; settingsFeedback = null; wifiScanButton = null
        mainText = null; subText = null; replyText = null; replyScroll = null; waveBars.clear()
        val root = column().apply {
            background = GradientDrawable(GradientDrawable.Orientation.TL_BR,
                intArrayOf(Color.rgb(236, 249, 255), Color.rgb(193, 226, 244), Color.rgb(147, 204, 234)))
            setPadding(dp(24), dp(8), dp(24), dp(10))
        }
        when (page) {
            "settings" -> renderPhoneSetup(root)
            "sessions" -> renderSessions(root)
            "camera" -> renderCamera(root)
            else -> renderVoiceHome(root)
        }
        setContentView(root)
    }

    private fun header(root: LinearLayout, title: String, back: Boolean = false) {
        val top = row()
        if (back) {
            top.addView(button("‹ 返回") { navigate("chat") }, LinearLayout.LayoutParams(dp(88), dp(43)))
            addSpace(top)
        }
        top.addView(label(title, 22f, green).apply { setTypeface(null, Typeface.BOLD) }, LinearLayout.LayoutParams(0, dp(45), 1f))
        root.addView(top)
    }

    private fun renderVoiceHome(root: LinearLayout) {
        val top = row()
        top.addView(button("会话") { navigate("sessions") }, LinearLayout.LayoutParams(dp(76), dp(38)))
        top.addView(label("GalaxySSI", 17f, green).apply {
            gravity = Gravity.CENTER; setTypeface(null, Typeface.BOLD)
        }, LinearLayout.LayoutParams(0, dp(40), 1f))
        top.addView(button("拍照/录像") { openCamera() }, LinearLayout.LayoutParams(dp(110), dp(38)))
        top.addView(button("手机配置") { navigate("settings") }, LinearLayout.LayoutParams(dp(100), dp(38)))
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
        subText = label("说“Hello Hello”开始", 17f, dim).apply {
            gravity = Gravity.CENTER; maxLines = 2
        }.also { center.addView(it, LinearLayout.LayoutParams(-1, dp(48))) }
        replyScroll = ScrollView(this).apply {
            isFillViewport = true; overScrollMode = View.OVER_SCROLL_NEVER
        }.also { center.addView(it, LinearLayout.LayoutParams(-1, dp(120))) }
        replyText = label("", 19f, green).apply { gravity = Gravity.CENTER }.also { replyScroll?.addView(it) }

        val bottom = row().apply { gravity = Gravity.CENTER_VERTICAL }
        bottom.addView(button("新对话") { cancelAutoSend(); awake = false; newSession(); updateConversationView() }, LinearLayout.LayoutParams(dp(92), dp(42)))
        addSpace(bottom)
        bottom.addView(button("重播回复") { latestAnswer()?.let(::speak) }, LinearLayout.LayoutParams(dp(100), dp(42)))
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
                subtitle.text = "与手机数字一致时说 Hello Hello 确认配对"
                answer.text = ""
            }
            busy -> { title.text = "正在思考…"; subtitle.text = "问题已发送"; answer.text = "" }
            awake -> { title.text = combinedPrompt().ifBlank { "请说话" }; subtitle.text = if (combinedPrompt().isBlank()) "正在听取问题" else "识别结束后 1.5 秒发送"; answer.text = "" }
            replyVisible -> { title.text = "GalaxySSI"; subtitle.text = "回复"; answer.text = latestAnswer().orEmpty() }
            else -> {
                title.text = "Hello Hello"
                subtitle.text = when {
                    !listening -> if (loadingModel) "正在加载离线语音模型" else "正在启动麦克风"
                    profile() == null -> "请在手机 GalaxySSI 配置 AR 眼镜"
                    else -> "说“Hello Hello”开始"
                }
                answer.text = ""
            }
        }
    }

    private fun renderCamera(root: LinearLayout) {
        header(root, "相机 · 说 Hello Hello 拍照/开始录像/停止录像", true)
        val preview = PreviewView(this)
        root.addView(preview, LinearLayout.LayoutParams(-1, 0, 1f))
        val actions = row().apply { gravity = Gravity.CENTER }
        actions.addView(button("拍照", true) { camera?.takePhoto() }, LinearLayout.LayoutParams(dp(90), dp(44)))
        addSpace(actions)
        actions.addView(button("开始录像") { camera?.startVideo() }, LinearLayout.LayoutParams(dp(105), dp(44)))
        addSpace(actions)
        actions.addView(button("停止录像") { camera?.stopVideo() }, LinearLayout.LayoutParams(dp(105), dp(44)))
        addSpace(actions)
        wifiScanButton = button(if (pendingWifi == null) "扫描配网码" else "确认联网") {
            if (pendingWifi == null) camera?.scanWifi() else confirmWifi()
        }.also { actions.addView(it, LinearLayout.LayoutParams(dp(120), dp(44))) }
        addSpace(actions)
        actions.addView(button("返回") { navigate("chat") }, LinearLayout.LayoutParams(dp(80), dp(44)))
        root.addView(actions)
        statusLabel = label(status, 13f, dim).also { root.addView(it, LinearLayout.LayoutParams(-1, dp(28))) }
        camera?.close()
        camera = GlassesCamera(this, preview, { message ->
            setStatus(if (message.startsWith("相机已就绪") && pendingWifi != null)
                "Wi-Fi：${pendingWifi?.ssid} · 说 Hello Hello 确认联网" else message)
            if (message.startsWith("相机已就绪")) {
                when (pendingCameraAction) {
                    "photo" -> camera?.takePhoto()
                    "video" -> camera?.startVideo()
                    "scan" -> camera?.scanWifi()
                }
                pendingCameraAction = null
            }
        }, { raw ->
            pendingWifi = runCatching { WifiQrProvisioning.parse(raw) }.getOrNull()
            wifiScanButton?.text = "确认联网"
            setStatus("已扫描 Wi-Fi：${pendingWifi?.ssid} · 确认后请求连接")
        }).also { it.open() }
    }

    private fun renderPhoneSetup(root: LinearLayout) {
        header(root, "通过手机配置 AR 眼镜", true)
        val center = column().apply { gravity = Gravity.CENTER }
        root.addView(center, LinearLayout.LayoutParams(-1, 0, 1f))
        center.addView(label("手机 GalaxySSI → 我的 Agent → 设备 → 配置 AR 眼镜", 21f, green).apply { gravity = Gravity.CENTER },
            LinearLayout.LayoutParams(-1, dp(60)))
        val instructions = when (setupPhase) {
            "wifi_required" -> "请先让眼镜与手机连接同一个 Wi-Fi"
            "waiting" -> "等待手机连接 · $setupHost:$setupPort"
            "confirm" -> "请核对手机上的数字是否相同"
            "saved" -> "手机配置已安全保存，可以开始对话"
            "retry" -> "连接未完成，请在手机重新连接"
            "expired" -> "配置已超时，请返回后重新打开"
            "network_changed" -> "Wi-Fi 已改变，请重新打开配置页"
            "error" -> "配置连接失败，请重新打开配置页"
            else -> "正在启动手机配置…"
        }
        settingsFeedback = label(instructions, 17f, dim).apply { gravity = Gravity.CENTER }.also {
            center.addView(it, LinearLayout.LayoutParams(-1, dp(48)))
        }
        if (setupPhase == "confirm") {
            center.addView(label(setupCode.chunked(3).joinToString(" "), 45f, green).apply { gravity = Gravity.CENTER },
                LinearLayout.LayoutParams(-1, dp(70)))
            val actions = row().apply { gravity = Gravity.CENTER }
            actions.addView(button("数字一致，确认", true) { setupServer?.confirm(true); setupPhase = "transferring"; render() },
                LinearLayout.LayoutParams(dp(180), dp(48)))
            addSpace(actions)
            actions.addView(button("取消") { setupServer?.confirm(false); setupPhase = "retry"; render() },
                LinearLayout.LayoutParams(dp(110), dp(48)))
            center.addView(actions)
        } else if (setupPhase in setOf("wifi_required", "retry", "expired", "network_changed", "error")) {
            center.addView(button("重新连接手机", true) { stopPhoneSetup(); startPhoneSetup(); render() },
                LinearLayout.LayoutParams(dp(180), dp(46)).apply { gravity = Gravity.CENTER })
        }
        root.addView(label("设置、模型和密钥均在手机上填写；眼镜只接收加密配对后的配置。", 14f, dim).apply { gravity = Gravity.CENTER },
            LinearLayout.LayoutParams(-1, dp(36)))
    }

    private fun renderSessions(root: LinearLayout) {
        header(root, "最近对话", true)
        val scroll = ScrollView(this)
        val list = column()
        scroll.addView(list)
        root.addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
        val all = sessions()
        for (i in all.length() - 1 downTo maxOf(0, all.length() - 30)) {
            val item = all.getJSONObject(i)
            val id = item.getString("id")
            list.addView(button(item.optString("title", "新对话")) {
                currentSession = id; draft = ""; livePartial = ""; awake = false; replyVisible = false; persist(); navigate("chat")
            }, LinearLayout.LayoutParams(-1, dp(50)).apply { bottomMargin = dp(6) })
        }
        root.addView(button("＋ 新对话", true) { newSession(); navigate("chat") }, LinearLayout.LayoutParams(-1, dp(48)))
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
                                raw.getString("api_key"), raw.optString("api_style", "openai")).validated()
                            state.put("profile", JSONObject().put("endpoint", candidate.endpoint).put("model", candidate.model)
                                .put("key", candidate.key).put("style", candidate.style))
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
            persist(); setStatus("未配置 Agent · 请点右上角“手机配置”")
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
        busy = true; setStatus("正在等待回复…"); updateConversationView()
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
                    setStatus("回复已收到 · 点击回复可朗读")
                    speak(answer)
                } else { setStatus("请求失败：${result.exceptionOrNull()?.message ?: "未知错误"}"); updateConversationView() }
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
            setStatus("正在播报")
        } else {
            if (edgeTts == null) edgeTts = MicrosoftEdgeTts(applicationContext)
            setStatus("正在合成语音…")
            edgeTts?.speak(spoken, MicrosoftTtsVoiceCatalog.XIAOXIAO) { success, _ ->
                runOnUiThread {
                    setStatus(if (success) "播报完成" else "语音播报失败，请检查网络")
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
        if (chineseModel == null || englishModel == null) {
            loadingModel = true; setStatus("正在加载中英文离线语音模型…")
            worker.execute {
                val loaded = runCatching {
                    val cn = Model(unpackModel("vosk-model-small-cn-0.22").absolutePath)
                    val en = try { Model(unpackModel("vosk-model-small-en-us-0.15").absolutePath) }
                        catch (error: Exception) { cn.close(); throw error }
                    cn to en
                }
                runOnUiThread {
                    loadingModel = false
                    loaded.onSuccess { (cn, en) ->
                        chineseModel = cn; englishModel = en
                        if (resumed) startListening()
                    }
                        .onFailure { setStatus("语音模型加载失败：${it.message}") }
                }
            }
            return
        }
        try {
            recognizer = BilingualSpeech(this, chineseModel!!, englishModel!!,
                onLevel = { level -> if (listening) {
                    waveBars.forEachIndexed { i, bar -> bar.alpha = (0.3f + ((level + i * 13) % 70) / 100f).coerceAtMost(1f) }
                    if (page == "chat" && status != "正在听") setStatus(if (awake) "正在听问题" else "等待 Hello Hello")
                } },
                onPartial = { partial -> if (listening) {
                    lastHeard = partial
                    if (!awake && wakePhrase.containsMatchIn(partial)) {
                        awake = true; replyVisible = false; firstHelloAt = 0L; updateConversationView()
                    }
                    if (awake) {
                        val words = stripSpokenWake(wakePhrase.replaceFirst(partial, ""))
                        if (words.isNotBlank() && !singleHello.matches(words) && words != livePartial) {
                            livePartial = words
                            if (isDeviceCommand(words)) cancelAutoSend()
                            else { setStatus("正在识别 · 停顿 1.5 秒后发送"); scheduleAutoSend() }
                            updateConversationView()
                        }
                    }
                } },
                onFinal = { result -> if (listening) {
                    lastHeard = ""
                    val fallback = livePartial
                    val before = draft
                    livePartial = ""
                    recognized(result)
                    if (awake && draft == before && fallback.isNotBlank() &&
                        (singleHello.matches(result) || wakePhrase.containsMatchIn(result))) {
                        if (!executeDeviceCommand(fallback)) {
                            draft = addWords(draft, fallback)
                            setStatus("已识别 · 1.5 秒后发送")
                            updateConversationView(); scheduleAutoSend()
                        }
                    }
                } },
                onError = { reason ->
                    stopListening(); setStatus("语音识别失败：$reason")
                    if (resumed) main.postDelayed({ if (resumed) startListening() }, 1200)
                })
            listening = true
            recognizer?.start()
            setStatus(if (awake) "正在听问题" else "等待 Hello Hello")
            updateConversationView()
        } catch (error: Exception) {
            listening = false; recognizer?.stop(); recognizer = null
            setStatus("无法使用麦克风：${error.message}")
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
        check(File(target, "am/final.mdl").isFile) { "$name 模型不完整" }
        return target
    }

    private fun stopListening() {
        if (!listening && recognizer == null) return
        listening = false
        recognizer?.stop(); recognizer = null
        setStatus("语音输入已停止")
    }

    private val wakePhrase = Regex("(?i)\\bhello[\\s,，。.!?]*hello\\b")
    private val singleHello = Regex("(?i)^hello[\\s,，。.!?]*$")
    private val spokenChineseWake = Regex("^(哈喽|哈罗|你好|海螺)[\\s,，。]*(哈喽|哈罗|你好|海螺)")
    private fun stripSpokenWake(text: String) = spokenChineseWake.replaceFirst(text.trim(), "").trim()
    private fun normalizedCommand(text: String) = text.trim().replace(" ", "")
        .trim('。', '.', '!', '！', '?', '？', '，', ',').lowercase(Locale.ROOT)
    private fun isDeviceCommand(text: String) = normalizedCommand(text) in setOf(
        "发送", "提交", "确认发送", "取消", "清空", "朗读", "读出来", "停止朗读", "别读了", "新对话",
        "设置", "打开设置", "手机配置", "确认配对", "配对确认", "取消配对", "返回", "打开对话", "对话",
        "会话", "最近对话", "打开相机", "启动相机", "打开拍照", "拍照", "拍一张", "照相", "扫描配网", "扫描配网码", "连接wifi", "确认联网", "取消联网",
        "开始录像", "启动录像", "录像", "停止录像", "结束录像", "打开相册", "查看照片",
        "回到桌面", "返回桌面", "打开wifi设置", "打开无线设置", "打开蓝牙设置", "音量加", "调大音量",
        "音量减", "调小音量", "电量", "查看电量", "几点了", "现在几点", "帮助", "有什么命令",
        "takephoto", "startrecording", "stoprecording", "scanwifi", "confirmwifi", "cancelwifi", "back", "home"
    )
    private fun confirmWifi() {
        val wifi = pendingWifi
        if (wifi == null) { setStatus("请先扫描手机配网码"); return }
        pendingWifi = null
        wifiScanButton?.text = "扫描配网码"
        val accepted = runCatching { wifi.suggest(this) }.getOrDefault(false)
        setStatus(if (accepted) "已请求连接 ${wifi.ssid} · 请批准系统提示" else "Wi-Fi 请求未被系统接受")
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
        val command = normalizedCommand(text)
        if (!isDeviceCommand(command)) return false
        if (command in setOf("发送", "提交", "确认发送")) {
            if (draft.isBlank() && livePartial.isNotBlank()) draft = livePartial
            livePartial = ""
            sendDraft()
            return true
        }
        cancelAutoSend(); draft = ""; livePartial = ""; awake = false
        when (command) {
            "取消", "清空" -> setStatus("已清空 · 正在听")
            "朗读", "读出来" -> latestAnswer()?.let(::speak) ?: setStatus("没有可朗读的回复")
            "停止朗读", "别读了" -> { stopSpeaking(); setStatus("已停止播报") }
            "新对话" -> { newSession(); render() }
            "设置", "打开设置", "手机配置" -> navigate("settings")
            "确认配对", "配对确认" -> {
                if (setupPhase == "confirm") { setupServer?.confirm(true); setupPhase = "transferring"; setStatus("配对已确认") }
                else setStatus("当前没有待确认的配对")
            }
            "取消配对" -> { setupServer?.confirm(false); setStatus("已取消配对") }
            "返回", "打开对话", "对话", "back" -> navigate("chat")
            "会话", "最近对话" -> navigate("sessions")
            "打开相机", "启动相机", "打开拍照" -> openCamera()
            "扫描配网", "扫描配网码", "连接wifi", "scanwifi" -> {
                if (page != "camera") openCamera("scan") else camera?.scanWifi()
            }
            "确认联网", "confirmwifi" -> confirmWifi()
            "取消联网", "cancelwifi" -> { pendingWifi = null; wifiScanButton?.text = "扫描配网码"; setStatus("已取消联网") }
            "拍照", "拍一张", "照相", "takephoto" -> { if (page != "camera") openCamera("photo") else camera?.takePhoto() }
            "开始录像", "启动录像", "录像", "startrecording" -> { if (page != "camera") openCamera("video") else camera?.startVideo() }
            "停止录像", "结束录像", "stoprecording" -> camera?.stopVideo() ?: setStatus("当前没有录像")
            "打开相册", "查看照片" -> runCatching {
                startActivity(Intent(Intent.ACTION_VIEW, MediaStore.Images.Media.EXTERNAL_CONTENT_URI).apply { type = "image/*" })
            }.onFailure { setStatus("无法打开相册") }
            "回到桌面", "返回桌面", "home" -> startActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME))
            "打开wifi设置", "打开无线设置" -> startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
            "打开蓝牙设置" -> startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
            "音量加", "调大音量" -> { getSystemService(AudioManager::class.java).adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_RAISE, 0); setStatus("音量已调大") }
            "音量减", "调小音量" -> { getSystemService(AudioManager::class.java).adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_LOWER, 0); setStatus("音量已调小") }
            "电量", "查看电量" -> setStatus("电量 ${getSystemService(BatteryManager::class.java).getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)}%")
            "几点了", "现在几点" -> setStatus(java.text.SimpleDateFormat("HH:mm", Locale.CHINA).format(java.util.Date()))
            "帮助", "有什么命令" -> setStatus("可说：拍照、开始录像、停止录像、返回、音量、电量、设置")
        }
        updateConversationView()
        return true
    }
    private fun recognized(text: String) {
        if (!listening) return
        val hasWake = wakePhrase.containsMatchIn(text)
        if (!awake) {
            val now = SystemClock.elapsedRealtime()
            val twoSeparateHellos = singleHello.matches(text) && now - firstHelloAt in 1..3000
            if (!hasWake && !twoSeparateHellos) {
                if (singleHello.matches(text)) firstHelloAt = now
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
                setStatus("已识别 · 1.5 秒后发送")
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
            else { pendingCameraAction = null; setStatus("需要相机权限才能拍照录像") }
        }
        if (requestCode == 10) {
            if (results.firstOrNull() == PackageManager.PERMISSION_GRANTED) startListening()
            else setStatus("需要麦克风权限才能语音输入")
        }
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
        chineseModel?.close(); englishModel?.close(); worker.shutdownNow()
        super.onDestroy()
    }
}
