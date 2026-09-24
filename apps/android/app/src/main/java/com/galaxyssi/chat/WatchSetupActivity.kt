package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.graphics.drawable.GradientDrawable
import android.graphics.Bitmap
import android.graphics.Color
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.text.Editable
import android.text.TextWatcher
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.*
import com.google.zxing.integration.android.IntentIntegrator
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors

/** Configuration drafts live only in this Activity, never in Bundles, logs or plaintext preferences. */
class WatchSetupActivity : Activity() {
    companion object { const val EXTRA_GLASSES = "configure_glasses" }
    private val glassesMode by lazy { intent.getBooleanExtra(EXTRA_GLASSES, false) }
    private fun device(zhWatch: String, zhGlasses: String, enWatch: String, enGlasses: String) =
        tr(if (glassesMode) zhGlasses else zhWatch, if (glassesMode) enGlasses else enWatch)
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var client: WatchSetupClient? = null
    private var generation = 0
    private var discovery: NsdManager.DiscoveryListener? = null
    private val devices = WatchDiscoveryCatalog<NsdServiceInfo>()
    private var page = "discover"
    private var connected = false
    private var scanning = false
    private var code = ""
    private var host = ""
    private var port = ""
    private var deviceName = "GalaxySSI Watch"
    private var provider = "DeepSeek"
    private var profile = JSONObject()
    private var tested = false
    private var busy = false
    private var pageRevision = 0
    private var desktopName = ""
    private var agents = JSONArray()
    private var selectedAgent = ""
    private var detail = ""
    private var wifiSsid = ""
    private var wifiPassword = ""
    private var wifiQrVisible = false
    private var wifiQrImage: ImageView? = null
    private lateinit var content: LinearLayout
    private lateinit var footer: LinearLayout
    private fun tr(zh: String, en: String) = if (resources.configuration.locales[0].language == "zh") zh else en
    private fun dp(n: Int) = (n * resources.displayMetrics.density).toInt()
    private fun color(id: Int) = getColor(id)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (glassesMode) deviceName = "GalaxySSI AR"
        if (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE == 0)
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        render(); discover()
    }
    override fun onStop() {
        super.onStop(); stopDiscovery()
        // The scanner is an app-owned foreground step, and does not receive credentials.
        if (!scanning && !isChangingConfigurations) {
            disconnect()
            if (page !in setOf("success", "discover", "manual")) { page = "offline"; render() }
        }
    }
    override fun onDestroy() { disconnect(); stopDiscovery(); main.removeCallbacksAndMessages(null); worker.shutdownNow(); super.onDestroy() }
    private fun disconnect() { generation++; client?.close(); client = null; connected = false; busy = false; devices.releaseSelection() }
    private fun go(value: String) {
        currentFocus?.windowToken?.let { getSystemService(android.view.inputmethod.InputMethodManager::class.java).hideSoftInputFromWindow(it, 0) }
        pageRevision++; page = value; render()
    }
    @Deprecated("Native back dispatch") override fun onBackPressed() {
        if (busy) {
            if (page == "edit") { busy = false; go("cloud") }
            else { disconnect(); go("offline") }
            return
        }
        when (page) {
            "discover", "success" -> finish()
            "confirm", "connecting", "offline", "manual" -> { disconnect(); go("discover"); discover() }
            "edit", "preview" -> go("cloud")
            "cloud", "remote" -> go("hub")
            "waiting", "agents" -> { disconnect(); go("offline") }
            else -> { disconnect(); go("discover"); discover() }
        }
    }
    private fun shape(fill: Int) = GradientDrawable().apply { setColor(fill); cornerRadius = dp(12).toFloat() }
    private fun text(value: String, secondary: Boolean = false, size: Float = 14f, parent: LinearLayout = content): TextView = TextView(this).apply {
        text = value; textSize = size; setTextColor(color(if (secondary) R.color.text_secondary else R.color.text_primary))
        setPadding(dp(4), dp(10), dp(4), dp(10)); parent.addView(this)
    }
    private fun card(title: String, subtitle: String = "", action: (() -> Unit)? = null) {
        val box = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(14), dp(5), dp(14), dp(5)); background = shape(color(R.color.surface_bg)) }
        content.addView(box, LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(10) })
        text(title + if (action != null) "   ›" else "", parent = box, size = 16f)
        if (subtitle.isNotBlank()) text(subtitle, true, 12f, box)
        action?.let { box.setOnClickListener { if (!busy) it() } }
    }
    private fun button(value: String, enabled: Boolean = true, primary: Boolean = true, action: () -> Unit) {
        footer.addView(Button(this).apply {
            text = value; textSize = 15f; isAllCaps = false; isEnabled = enabled && (!busy || (page == "confirm" && !primary))
            setTextColor(if (primary && isEnabled) android.graphics.Color.WHITE else color(R.color.text_secondary))
            background = shape(color(if (primary && isEnabled) R.color.accent_green else R.color.button_soft))
            setOnClickListener { action() }
        }, LinearLayout.LayoutParams(-1, dp(48)).apply { topMargin = dp(8) })
    }
    private fun input(label: String, value: String, password: Boolean = false, numeric: Boolean = false, changed: (String) -> Unit): EditText {
        text(label, true, 12f)
        return EditText(this).apply {
            setText(value); textSize = 15f; setSingleLine(true); isEnabled = !busy; setTextColor(color(R.color.text_primary))
            inputType = if (password) InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD else if (numeric) InputType.TYPE_CLASS_NUMBER else InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI
            isSaveEnabled = false; importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
            setPadding(dp(12), dp(8), dp(12), dp(8)); background = shape(color(R.color.surface_bg))
            content.addView(this, LinearLayout.LayoutParams(-1, dp(48)))
            addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) { changed(s.toString()) }
                override fun afterTextChanged(s: Editable?) = Unit
            })
        }
    }
    private fun render() {
        if (isDestroyed) return
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setBackgroundColor(color(R.color.page_bg)) }
        val toolbar = layoutInflater.inflate(R.layout.watch_setup_header, root, false)
        toolbar.findViewById<ImageButton>(R.id.watchSetupBack).setOnClickListener { onBackPressed() }
        toolbar.findViewById<TextView>(R.id.watchSetupTitle).text = when (page) {
            "manual" -> tr("手动连接", "Manual connection"); "confirm" -> tr("核对连接", "Verify connection")
            "wifi" -> tr("眼镜 Wi-Fi 配网", "Glasses Wi-Fi setup")
            "cloud" -> tr("云端 API Key", "Cloud API Key"); "edit" -> tr("编辑云端配置", "Edit cloud configuration")
            "preview" -> tr("确认同步", "Confirm transfer"); "remote" -> tr("添加远端电脑", "Add remote computer")
            "waiting", "agents" -> tr("远端 Agent", "Remote Agent"); "success" -> tr("同步完成", "Transfer complete")
            "offline" -> tr("连接已断开", "Disconnected"); else -> device("配置手表", "配置 AR 眼镜", "Configure watch", "Configure AR glasses")
        }
        root.addView(toolbar)
        content = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(14), dp(12), dp(14), dp(12)) }
        root.addView(ScrollView(this).apply { addView(content) }, LinearLayout.LayoutParams(-1, 0, 1f))
        footer = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(14), 0, dp(14), dp(18)) }; root.addView(footer)
        when (page) {
            "discover" -> {
                card(device("连接你的手表", "连接你的 AR 眼镜", "Connect your watch", "Connect your AR glasses"),
                    device("手机与手表连接同一个 Wi-Fi\n在手表打开 GalaxySSI 配置页", "手机与眼镜连接同一个 Wi-Fi\n在眼镜打开 GalaxySSI 即可自动发现，无需进入设置页", "Join the same Wi-Fi on both devices. Open GalaxySSI setup on the watch.", "Join the same Wi-Fi on both devices. Open GalaxySSI on the glasses; no settings page is needed."))
                text(device("发现的手表", "发现的眼镜", "Discovered watches", "Discovered glasses"), true)
                devices.values.forEach { info -> card(info.serviceName, tr("等待连接", "Not connected")) { resolve(info) } }
                if (devices.isEmpty()) text(tr("正在搜索…也可使用手动连接", "Searching… Manual connection is also available."), true)
                if (glassesMode) card(tr("眼镜还没有联网？生成配网码", "Glasses offline? Create Wi-Fi QR"),
                    tr("Wi-Fi 名称和密码只在手机输入；用眼镜语音扫描。", "Enter Wi-Fi details on the phone, then scan using glasses voice control.")) { go("wifi") }
                card(tr("手动连接", "Manual connection")) { go("manual") }
                button(tr("重新搜索", "Search again")) { discover() }
            }
            "wifi" -> {
                text(tr("在手机填写眼镜要连接的 Wi-Fi。眼镜说“Hello Hello 扫描配网”，看向此二维码，核对名称后说“Hello Hello 确认联网”。首次连接仍需批准眼镜上的系统提示。", "Enter the Wi-Fi network for the glasses. Say “Hello Hello scan Wi-Fi” on the glasses, look at this QR code, then confirm the network. Android may require one system approval on the glasses."), true)
                input(tr("Wi-Fi 名称（SSID）", "Wi-Fi name (SSID)"), wifiSsid) { wifiSsid = it; wifiQrVisible = false; wifiQrImage?.visibility = View.GONE }
                input(tr("Wi-Fi 密码（WPA2，8–63 位）", "Wi-Fi password (WPA2, 8–63 characters)"), wifiPassword, password = true) { wifiPassword = it; wifiQrVisible = false; wifiQrImage?.visibility = View.GONE }
                if (wifiQrVisible) {
                    val raw = JSONObject().put("type", "galaxyssi_wifi_v1").put("ssid", wifiSsid).put("passphrase", wifiPassword).toString()
                    val matrix = QRCodeWriter().encode(raw, BarcodeFormat.QR_CODE, 512, 512,
                        mapOf(EncodeHintType.CHARACTER_SET to "UTF-8"))
                    val bitmap = Bitmap.createBitmap(512, 512, Bitmap.Config.ARGB_8888)
                    for (y in 0 until 512) for (x in 0 until 512) bitmap.setPixel(x, y, if (matrix[x, y]) Color.BLACK else Color.WHITE)
                    wifiQrImage = ImageView(this).apply { setImageBitmap(bitmap); contentDescription = tr("眼镜 Wi-Fi 配网二维码", "Glasses Wi-Fi setup QR") }
                    content.addView(wifiQrImage, LinearLayout.LayoutParams(dp(280), dp(280)).apply { gravity = Gravity.CENTER_HORIZONTAL })
                }
                button(tr("显示配网码", "Show Wi-Fi QR")) {
                    if (wifiSsid.isBlank() || wifiSsid.toByteArray(Charsets.UTF_8).size > 32 || wifiPassword.length !in 8..63 || wifiPassword.any { it.code !in 32..126 })
                        Toast.makeText(this, tr("请检查 SSID 和 WPA2 密码", "Check the SSID and WPA2 password."), Toast.LENGTH_LONG).show()
                    else { wifiQrVisible = true; render() }
                }
            }
            "manual" -> {
                text(device("输入手表「连接帮助」中显示的地址", "输入眼镜配置页显示的地址", "Enter the address shown in Connection help on the watch.", "Enter the address shown on the glasses setup screen."), true)
                input(tr("IP 地址", "IP address"), host) { host = it.trim() }
                input(tr("端口", "Port"), port, numeric = true) { port = it.trim() }
                button(device("连接手表", "连接眼镜", "Connect watch", "Connect glasses")) { connect() }
            }
            "connecting" -> text(tr("正在建立加密连接…", "Establishing encrypted connection…"))
            "confirm" -> {
                text(device("请核对手表上的数字", "请核对眼镜上的数字", "Compare the code on the watch", "Compare the code on the glasses"), size = 20f)
                text(code.chunked(3).joinToString(" "), size = 40f).gravity = Gravity.CENTER
                text(device("两端数字一致后，也请在手表上点击确认", "两端数字一致后，也请在眼镜上点击确认", "If the codes match, also confirm on the watch.", "If the codes match, also confirm on the glasses."), true)
                button(tr("一致，继续", "Codes match, continue")) { busy = true; render(); client?.confirm() }
                button(tr("取消连接", "Cancel"), primary = false) { disconnect(); go("discover"); discover() }
            }
            "hub" -> {
                card(deviceName, tr("● 已连接", "● Connected")); text(tr("对话方式", "Conversation mode"), true)
                card(tr("云端 API Key", "Cloud API Key"), device("手表直接连接模型服务", "眼镜直接连接模型服务", "Connect the watch directly to a model provider", "Connect the glasses directly to a model provider")) { go("cloud") }
                if (!glassesMode) card(tr("远端 Agent", "Remote Agent"), tr("由远端电脑处理任务", "Run tasks on your computer")) { go("remote") }
                if (glassesMode) text(tr("电脑配对码扫描暂未接入眼镜；当前可同步手机已有云端模型。", "Desktop pairing QR is not yet available on the glasses; existing phone cloud models can be transferred."), true)
                text(if (glassesMode) tr("云端模型可在手机选取、测试并同步；眼镜上只需核对一次配对数字。", "Choose, test and transfer a cloud model on the phone; only compare the pairing code on the glasses.") else tr("配置任意一种方式即可开始", "Configure either option to start."), true)
            }
            "cloud" -> {
                text(tr("使用手机已有配置", "Use a phone configuration"), true)
                val contacts = AppStore.contacts(this)
                for (i in 0 until contacts.length()) {
                    val raw = contacts.getJSONObject(i)
                    if (raw.optString("delivery_mode") != "cloud_api") continue
                    val models = AppStore.cloudModels(this, raw.getString("id"))
                    for (j in 0 until models.length()) {
                        val model = models.getJSONObject(j)
                        if (model.optString("api_key").isBlank()) continue
                        card(raw.optString("cloud_provider") + " · " + model.optString("model_id"), tr("密钥已隐藏", "Key hidden")) {
                            provider = raw.optString("cloud_provider")
                            profile = JSONObject().put("endpoint", model.optString("endpoint")).put("model", model.optString("model_id"))
                                .put("api_key", model.optString("api_key")).put("api_style", model.optString("api_style", "openai"))
                            tested = false; go("edit")
                        }
                    }
                }
                card(tr("新增配置", "New configuration")) { chooseProvider() }
                text(tr("仅复制所选配置，不修改手机设置", "Copies the selected configuration without changing phone settings."), true)
                if (profile.length() > 0) card(tr("继续编辑草稿", "Resume draft")) { go("edit") }
            }
            "edit" -> {
                card(tr("服务商：", "Provider: ") + provider) { chooseProvider() }
                input(tr("接口地址（完整请求地址）", "Endpoint (full request URL)"), profile.optString("endpoint")) { profile.put("endpoint", it.trim()); tested = false }
                input("API Key", profile.optString("api_key"), password = true) { profile.put("api_key", it.trim()); tested = false }
                card(tr("选择模型", "Select model"), profile.optString("model")) { chooseModel() }
                input(tr("模型 ID（可手动填写）", "Model ID (editable)"), profile.optString("model")) { profile.put("model", it.trim()); tested = false }
                card(tr("深度思考", "Deep thinking"), device("关闭 · 手表默认使用简洁回答", "关闭 · 眼镜默认使用简洁回答", "Off · Concise watch responses", "Off · Concise glasses responses"))
                button(tr("测试连接", "Test connection"), primary = false) { testCloud() }
                button(tr("保存并继续", "Save and continue")) { runCatching { WatchSetupCloud.validate(profile) }.onSuccess { go("preview") }.onFailure { invalid() } }
            }
            "preview" -> {
                card(if (tested) tr("手机端连接测试通过", "Phone connection test passed") else tr("尚未测试连接", "Connection not tested"), device("还未同步到手表", "还未同步到眼镜", "Not yet transferred to the watch", "Not yet transferred to the glasses"))
                card(device("目标手表", "目标眼镜", "Watch", "Glasses"), deviceName); card(provider, profile.optString("model")); card("API Key", tr("已隐藏", "Hidden"))
                button(device("同步到手表", "同步到眼镜", "Transfer to watch", "Transfer to glasses")) { exchange(JSONObject().put("type", "configure").put("kind", "cloud").put("profile", profile)) { result -> require(result.optString("status") == "saved"); detail = provider + " · " + profile.optString("model"); disconnect(); go("success") } }
            }
            "remote" -> {
                card(tr("扫描电脑配对码", "Scan computer pairing code"), tr("使用新的配对码，为手表建立独立连接", "Use a fresh pairing code for the watch's own connection.")) {
                    scanning = true; IntentIntegrator(this).setDesiredBarcodeFormats(IntentIntegrator.QR_CODE).setPrompt(tr("对准电脑配对码", "Scan the computer pairing code")).setBeepEnabled(false).initiateScan()
                }
                card(tr("手动输入配对信息", "Enter pairing information")) {
                    val field = EditText(this).apply { isSaveEnabled = false; inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE }
                    AlertDialog.Builder(this).setTitle(tr("粘贴电脑配对信息", "Paste computer pairing information")).setView(field).setPositiveButton(tr("继续", "Continue")) { _, _ -> pair(field.text.toString()) }.setNegativeButton(tr("取消", "Cancel"), null).show()
                }
            }
            "waiting" -> { card(desktopName, tr("等待电脑授权", "Waiting for computer approval")); text(tr("请在电脑端确认手表的配对请求。授权后将显示可选 Agent。", "Approve the watch pairing request on your computer. Agents appear after approval."), true) }
            "agents" -> {
                card(desktopName, tr("电脑已授权", "Computer authorized"))
                for (i in 0 until agents.length()) { val agent = agents.getJSONObject(i); card((if (selectedAgent == agent.getString("id")) "● " else "○ ") + agent.optString("name")) { selectedAgent = agent.getString("id"); render() } }
                button(tr("在手表使用此 Agent", "Use this Agent on watch"), enabled = selectedAgent.isNotBlank()) {
                    exchange(JSONObject().put("type", "configure").put("kind", "select_agent").put("agent_id", selectedAgent)) { result -> require(result.optString("status") == "saved"); detail = desktopName + " · " + result.optString("agent_name"); disconnect(); go("success") }
                }
            }
            "success" -> { card(device("✓ 手表已确认接收", "✓ 眼镜已确认接收", "✓ Watch confirmed receipt", "✓ Glasses confirmed receipt"), detail); text(device("现在可以在手表开始对话", "现在可以在眼镜说 Hello Hello 开始对话", "You can now chat on the watch.", "Say Hello Hello on the glasses to start chatting."), true); button(tr("完成", "Done")) { finish() } }
            "offline" -> {
                card(device("尚未收到手表确认", "尚未收到眼镜确认", "No watch acknowledgment", "No glasses acknowledgment"), tr("本次配置草稿仍保留在当前页面", "Your draft remains available in this screen."))
                text(device("请保持同一 Wi-Fi，并在手表重新打开配置页。重新连接后需再次核对数字。", "请保持同一 Wi-Fi，并在眼镜重新打开手机配置页。重新连接后需再次核对数字。", "Use the same Wi-Fi and reopen watch setup. Compare the new code when reconnecting.", "Use the same Wi-Fi and reopen glasses setup. Compare the new code when reconnecting."), true)
                button(tr("重新连接", "Reconnect")) { go("discover"); discover() }
            }
        }
        setContentView(root)
    }
    private fun invalid() { Toast.makeText(this, tr("请检查完整 HTTPS 地址、模型和密钥", "Check the full HTTPS endpoint, model and key."), Toast.LENGTH_LONG).show() }
    private fun chooseProvider() {
        val names = CLOUD_MODEL_PRESETS.map { it.provider }.distinct()
        AlertDialog.Builder(this).setTitle(tr("选择服务商", "Select provider")).setItems(names.toTypedArray()) { _, n ->
            provider = names[n]; val preset = CLOUD_MODEL_PRESETS.first { it.provider == provider }
            profile = JSONObject().put("endpoint", preset.endpoint).put("model", preset.modelId).put("api_style", preset.apiStyle).put("api_key", "")
            tested = false; go("edit")
        }.show()
    }
    private fun chooseModel() {
        val options = CLOUD_MODEL_PRESETS.filter { it.provider == provider }
        AlertDialog.Builder(this).setTitle(tr("选择模型", "Select model")).setItems(options.map { it.name }.toTypedArray()) { _, n ->
            val option = options[n]; profile.put("model", option.modelId).put("endpoint", option.endpoint).put("api_style", option.apiStyle); tested = false; render()
        }.show()
    }
    private fun testCloud() {
        val copy = JSONObject(profile.toString())
        if (runCatching { WatchSetupCloud.validate(copy) }.isFailure) { invalid(); return }
        busy = true; render(); val owner = generation; val revision = pageRevision
        worker.execute {
            val ok = runCatching { WatchSetupCloud.test(copy) }.getOrDefault(false)
            main.post { if (owner == generation && revision == pageRevision && !isDestroyed) { busy = false; tested = ok; if (ok) go("preview") else { render(); Toast.makeText(this, tr("连接测试失败，请检查密钥、模型或网络", "Test failed. Check credentials, model or network."), Toast.LENGTH_LONG).show() } } }
        }
    }
    private fun connect() {
        val cm = getSystemService(ConnectivityManager::class.java)
        val network = cm.allNetworks.firstOrNull { cm.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true }
        val number = port.toIntOrNull()
        if (network == null || number == null || number !in 1..65535) { devices.releaseSelection(); busy = false; render(); Toast.makeText(this, tr("请连接 Wi-Fi 并检查 IP 和端口", "Connect to Wi-Fi and check the IP and port."), Toast.LENGTH_LONG).show(); return }
        stopDiscovery(); disconnect(); val owner = generation
        val connection = WatchSetupClient(); client = connection; go("connecting")
        worker.execute {
            runCatching { connection.connect(network, host, number) { value -> main.post { if (owner == generation) { code = value; go("confirm") } } } }
                .onSuccess { main.post { if (owner == generation) { connected = true; busy = false; go("hub") } } }
                .onFailure { main.post { if (owner == generation) { disconnect(); go("offline") } } }
        }
    }
    private fun exchange(payload: JSONObject, done: (JSONObject) -> Unit) {
        val connection = client
        if (!connected || connection == null) { go("offline"); return }
        val snapshot = JSONObject(payload.toString())
        busy = true; render(); val owner = generation
        worker.execute { val result = runCatching { connection.exchange(snapshot) }; main.post {
            if (owner == generation && !isDestroyed) { busy = false; result.onSuccess { runCatching { done(it) }.onFailure { disconnect(); go("offline") } }.onFailure { disconnect(); go("offline") } }
        } }
    }
    private fun pair(raw: String) {
        val qr = runCatching { require(raw.length <= 32000); val source = JSONObject(raw); (GalaxySSILinkProtocol.normalizePairingQr(source) ?: source).also { require(GalaxySSILinkProtocol.validatePairingQr(it)) } }.getOrNull()
        if (qr == null) { Toast.makeText(this, tr("配对信息无效或已过期，请在电脑重新生成", "Pairing code is invalid or expired. Generate a new one."), Toast.LENGTH_LONG).show(); return }
        desktopName = qr.optString("desktop_name").ifBlank { tr("我的电脑", "My computer") }
        exchange(JSONObject().put("type", "configure").put("kind", "desktop").put("pairing_offer", qr)) { result ->
            require(result.optString("status") == "pairing_started"); go("waiting"); pollDesktop(generation, 0)
        }
    }
    private fun pollDesktop(owner: Int, attempt: Int) {
        main.postDelayed({
            if (owner == generation && page == "waiting") {
                if (attempt >= 90) { disconnect(); go("offline") }
                else exchange(JSONObject().put("type", "configure").put("kind", "desktop_status")) { result ->
                    if (result.optString("status") == "agents_ready") { agents = result.getJSONArray("agents"); selectedAgent = ""; go("agents") }
                    else pollDesktop(owner, attempt + 1)
                }
            }
        }, 2000)
    }
    @Deprecated("Scanner activity result") override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        val result = IntentIntegrator.parseActivityResult(requestCode, resultCode, data) ?: return
        scanning = false; result.contents?.let { pair(it) }
    }
    private fun stopDiscovery() { discovery?.let { runCatching { getSystemService(NsdManager::class.java).stopServiceDiscovery(it) } }; discovery = null }
    private fun discover() {
        stopDiscovery(); devices.clear(); render()
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(type: String) = Unit
            override fun onDiscoveryStopped(type: String) = Unit
            override fun onStartDiscoveryFailed(type: String, error: Int) = Unit
            override fun onStopDiscoveryFailed(type: String, error: Int) = Unit
            override fun onServiceFound(info: NsdServiceInfo) { main.post { if (discovery === this && page == "discover") { devices.put(serviceKey(info), info); render() } } }
            override fun onServiceLost(info: NsdServiceInfo) { main.post { if (discovery === this) {
                if (devices.remove(serviceKey(info))) busy = false
                if (page == "discover") render()
            } } }
        }
        discovery = listener
        runCatching { getSystemService(NsdManager::class.java).discoverServices(if (glassesMode) "_galaxyssi-glasses._tcp." else "_galaxyssi-watch._tcp.", NsdManager.PROTOCOL_DNS_SD, listener) }
    }
    private fun resolve(info: NsdServiceInfo) {
        val owner = generation
        val key = serviceKey(info)
        if (!devices.select(key)) return
        val selection = devices.selectionRevision
        busy = true; render()
        val listener = object : NsdManager.ResolveListener {
            override fun onResolveFailed(service: NsdServiceInfo, error: Int) { main.post { if (owner == generation && devices.selected == key && devices.selectionRevision == selection) {
                devices.releaseSelection(); busy = false; go("manual")
            } } }
            override fun onServiceResolved(service: NsdServiceInfo) { main.post { if (owner == generation && page == "discover" && devices.selected == key && devices.selectionRevision == selection) {
                busy = false
                host = if (android.os.Build.VERSION.SDK_INT >= 34) service.hostAddresses.firstOrNull { it is java.net.Inet4Address }?.hostAddress.orEmpty()
                    else service.host?.hostAddress.orEmpty()
                port = service.port.toString(); deviceName = service.serviceName; connect()
            } } }
        }
        runCatching { getSystemService(NsdManager::class.java).resolveService(info, listener) }
            .onFailure { listener.onResolveFailed(info, NsdManager.FAILURE_INTERNAL_ERROR) }
    }
    private fun serviceKey(info: NsdServiceInfo) = WatchDiscoveryCatalog.Key(
        info.serviceName, info.serviceType.trimEnd('.'),
        if (android.os.Build.VERSION.SDK_INT >= 33) info.network?.networkHandle?.toString().orEmpty() else ""
    )
}
