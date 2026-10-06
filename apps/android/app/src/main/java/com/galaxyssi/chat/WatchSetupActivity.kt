package com.galaxyssi.chat

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.drawable.GradientDrawable
import android.graphics.Bitmap
import android.graphics.Color
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
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
    private fun device(watch: Int, glasses: Int) = getString(if (glassesMode) glasses else watch)
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var client: WatchSetupClient? = null
    private var generation = 0
    private var discovery: NsdManager.DiscoveryListener? = null
    private val devices = WatchDiscoveryCatalog<NsdServiceInfo>()
    private var page = "discover"
    private var connected = false
    private var scanning = false
    private var pickingSkill = false
    private var skillBytes: ByteArray? = null
    private var skillVersion = ""
    private var skillTransferComplete = false
    private var code = ""
    private var host = ""
    private var port = ""
    private var deviceName = "GalaxySSI Watch"
    private var provider = "DeepSeek"
    private var selectedCloudAgent = ""
    private var profile = JSONObject()
    private var tested = false
    private var busy = false
    private var pageRevision = 0
    private var desktopName = ""
    private var agents = JSONArray()
    private var selectedAgent = ""
    private var detail = ""
    private var resumePreviewAfterConnect = false
    private var wifiSsid = ""
    private var wifiPassword = ""
    private var wifiQrVisible = false
    private var wifiQrImage: ImageView? = null
    private var wifiSsidInput: EditText? = null
    private var wifiScanFeedback: TextView? = null
    private var wifiNetworkList: LinearLayout? = null
    private var wifiNetworks = emptyList<String>()
    private var wifiScanReceiver: BroadcastReceiver? = null
    private var wifiScanStatus = ""
    private var wifiScanPermissionAsked = false
    private lateinit var content: LinearLayout
    private lateinit var footer: LinearLayout
    private fun dp(n: Int) = (n * resources.displayMetrics.density).toInt()
    private fun color(id: Int) = getColor(id)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (glassesMode) deviceName = "GalaxySSI AR"
        if (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE == 0)
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        render(); discover()
    }
    override fun onResume() {
        super.onResume()
        if (page == "wifi" && checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED && wifiScanReceiver == null)
            beginWifiScan()
    }
    override fun onStop() {
        super.onStop(); stopDiscovery(); stopWifiScan()
        // The scanner is an app-owned foreground step, and does not receive credentials.
        if (!scanning && !pickingSkill && !isChangingConfigurations) {
            disconnect()
            if (page !in setOf("success", "discover", "manual", "wifi")) { page = "offline"; render() }
        }
    }
    override fun onDestroy() { disconnect(); stopDiscovery(); stopWifiScan(); main.removeCallbacksAndMessages(null); worker.shutdownNow(); super.onDestroy() }
    private fun disconnect() { generation++; client?.close(); client = null; connected = false; busy = false; devices.releaseSelection() }
    private fun go(value: String) {
        currentFocus?.windowToken?.let { getSystemService(android.view.inputmethod.InputMethodManager::class.java).hideSoftInputFromWindow(it, 0) }
        if (page == "discover" && value != "discover") stopDiscovery()
        if (page == "wifi" && value != "wifi") stopWifiScan()
        pageRevision++; page = value; render()
        if (value == "wifi") beginWifiScan()
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
            "cloud", "remote", "skills" -> go("hub")
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
            "manual" -> getString(R.string.watch_setup_copy_manual_connection); "confirm" -> getString(R.string.watch_setup_copy_verify_connection)
            "wifi" -> getString(R.string.watch_setup_copy_glasses_wi_fi_setup)
            "skills" -> getString(R.string.watch_setup_copy_import_watch_skill)
            "cloud" -> getString(R.string.watch_setup_copy_cloud_api_key); "edit" -> getString(R.string.watch_setup_copy_edit_cloud_configuration)
            "preview" -> getString(R.string.watch_setup_copy_confirm_transfer); "remote" -> getString(R.string.watch_setup_copy_add_remote_computer)
            "waiting", "agents" -> getString(R.string.watch_setup_copy_remote_agent); "success" -> getString(R.string.watch_setup_copy_transfer_complete)
            "offline" -> getString(R.string.watch_setup_copy_disconnected); else -> device(R.string.watch_setup_copy_configure_watch, R.string.watch_setup_copy_configure_ar_glasses)
        }
        root.addView(toolbar)
        content = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(14), dp(12), dp(14), dp(12)) }
        root.addView(ScrollView(this).apply { addView(content) }, LinearLayout.LayoutParams(-1, 0, 1f))
        footer = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(14), 0, dp(14), dp(18)) }; root.addView(footer)
        when (page) {
            "discover" -> {
                if (glassesMode) card(getString(R.string.watch_setup_copy_configure_agent_and_cloud_model),
                    getString(R.string.watch_setup_copy_choose_or_add_a_cloud_agent_on_the_phone)) { go("hub") }
                card(device(R.string.watch_setup_copy_connect_your_watch, R.string.watch_setup_copy_connect_your_ar_glasses),
                    device(R.string.watch_setup_copy_join_the_same_wi_fi_on_both_devices_open, R.string.watch_setup_copy_join_the_same_wi_fi_on_both_devices_open_2))
                text(device(R.string.watch_setup_copy_discovered_watches, R.string.watch_setup_copy_discovered_glasses), true)
                devices.values.forEach { info -> card(info.serviceName, getString(R.string.watch_setup_copy_not_connected)) { resolve(info) } }
                if (devices.isEmpty()) text(getString(R.string.watch_setup_copy_searching_manual_connection_is_also_available), true)
                if (glassesMode) card(getString(R.string.watch_setup_copy_glasses_offline_create_wi_fi_qr),
                    getString(R.string.watch_setup_copy_enter_wi_fi_details_on_the_phone_then_scan)) { go("wifi") }
                card(getString(R.string.watch_setup_copy_manual_connection)) { go("manual") }
                button(getString(R.string.watch_setup_copy_search_again)) { discover() }
            }
            "wifi" -> {
                text(getString(R.string.watch_setup_copy_enter_the_wi_fi_network_for_the_glasses_say), true)
                wifiScanFeedback = text(wifiScanStatus.ifBlank { getString(R.string.watch_setup_copy_looking_for_nearby_wi_fi) }, true)
                text(getString(R.string.watch_setup_copy_only_wpa2_compatible_networks_are_listed_hidden_wpa2_networks), true, 12f)
                wifiNetworkList = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }.also { content.addView(it) }
                renderWifiNetworks()
                wifiSsidInput = input(getString(R.string.watch_setup_copy_wi_fi_name_ssid), wifiSsid) { wifiSsid = it; wifiQrVisible = false; wifiQrImage?.visibility = View.GONE }
                input(getString(R.string.watch_setup_copy_wi_fi_password_wpa2_8_63_characters), wifiPassword, password = true) { wifiPassword = it; wifiQrVisible = false; wifiQrImage?.visibility = View.GONE }
                if (wifiQrVisible) {
                    val raw = JSONObject().put("type", "galaxyssi_wifi_v1").put("ssid", wifiSsid).put("passphrase", wifiPassword).toString()
                    val matrix = QRCodeWriter().encode(raw, BarcodeFormat.QR_CODE, 512, 512,
                        mapOf(EncodeHintType.CHARACTER_SET to "UTF-8"))
                    val bitmap = Bitmap.createBitmap(512, 512, Bitmap.Config.ARGB_8888)
                    for (y in 0 until 512) for (x in 0 until 512) bitmap.setPixel(x, y, if (matrix[x, y]) Color.BLACK else Color.WHITE)
                    wifiQrImage = ImageView(this).apply { setImageBitmap(bitmap); contentDescription = getString(R.string.watch_setup_copy_glasses_wi_fi_setup_qr) }
                    content.addView(wifiQrImage, LinearLayout.LayoutParams(dp(280), dp(280)).apply { gravity = Gravity.CENTER_HORIZONTAL })
                }
                button(getString(R.string.watch_setup_copy_show_wi_fi_qr)) {
                    if (wifiSsid.isBlank() || wifiSsid.toByteArray(Charsets.UTF_8).size > 32 || wifiPassword.length !in 8..63 || wifiPassword.any { it.code !in 32..126 })
                        Toast.makeText(this, getString(R.string.watch_setup_copy_check_the_ssid_and_wpa2_password), Toast.LENGTH_LONG).show()
                    else { wifiQrVisible = true; render() }
                }
                button(getString(R.string.watch_setup_copy_refresh_nearby_wi_fi), primary = false) { beginWifiScan(retryPermission = true) }
                if (glassesMode) button(getString(R.string.watch_setup_copy_continue_to_agent_and_cloud_model), primary = false) { go("hub") }
                if (!getSystemService(LocationManager::class.java).isLocationEnabled)
                    button(getString(R.string.watch_setup_copy_open_phone_location_settings), primary = false) {
                        startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
                    }
            }
            "manual" -> {
                text(device(R.string.watch_setup_copy_enter_the_address_shown_in_connection_help_on_the, R.string.watch_setup_copy_enter_the_address_shown_on_the_glasses_setup_screen), true)
                input(getString(R.string.watch_setup_copy_ip_address), host) { host = it.trim() }
                input(getString(R.string.watch_setup_copy_port), port, numeric = true) { port = it.trim() }
                button(device(R.string.watch_setup_copy_connect_watch, R.string.watch_setup_copy_connect_glasses)) { connect() }
            }
            "connecting" -> text(getString(R.string.watch_setup_copy_establishing_encrypted_connection))
            "confirm" -> {
                text(device(R.string.watch_setup_copy_compare_the_code_on_the_watch, R.string.watch_setup_copy_compare_the_code_on_the_glasses), size = 20f)
                text(code.chunked(3).joinToString(" "), size = 40f).gravity = Gravity.CENTER
                text(device(R.string.watch_setup_copy_if_the_codes_match_also_confirm_on_the_watch, R.string.watch_setup_copy_if_the_codes_match_also_confirm_on_the_glasses), true)
                button(getString(R.string.watch_setup_copy_codes_match_continue)) { busy = true; render(); client?.confirm() }
                button(getString(R.string.watch_setup_copy_cancel), primary = false) { disconnect(); go("discover"); discover() }
            }
            "hub" -> {
                card(deviceName, if (connected) getString(R.string.watch_setup_copy_connected) else getString(R.string.watch_setup_copy_glasses_not_connected))
                text(getString(R.string.watch_setup_copy_conversation_mode), true)
                card(device(R.string.watch_setup_copy_cloud_api_key, R.string.watch_setup_copy_cloud_agent_and_model), device(R.string.watch_setup_copy_connect_the_watch_directly_to_a_model_provider, R.string.watch_setup_copy_choose_a_phone_agent_or_add_a_model_the)) { go("cloud") }
                if (!glassesMode) card(getString(R.string.watch_setup_copy_remote_agent), getString(R.string.watch_setup_copy_run_tasks_on_your_computer)) { go("remote") }
                if (!glassesMode) card(getString(R.string.watch_setup_copy_import_skill), getString(R.string.watch_setup_copy_choose_a_gskill_package_then_confirm_installation_on_the)) { go("skills") }
                if (glassesMode && !connected) card(getString(R.string.watch_setup_copy_connect_glasses_to_transfer),
                    getString(R.string.watch_setup_copy_use_the_same_wi_fi_and_compare_the_six)) { go("discover"); discover() }
                if (glassesMode) text(getString(R.string.watch_setup_copy_choose_and_test_cloud_settings_on_the_phone_the), true)
                else text(getString(R.string.watch_setup_copy_configure_either_option_to_start), true)
            }
            "skills" -> {
                card(deviceName, if (connected) getString(R.string.watch_setup_copy_connected) else getString(R.string.watch_setup_copy_disconnected))
                text(getString(R.string.watch_setup_copy_open_skill_management_import_skill_on_the_watch_both), true)
                if (skillBytes == null) text(getString(R.string.watch_setup_copy_no_skill_package_selected), true)
                else card(getString(R.string.watch_setup_copy_door_access_skill), "v$skillVersion")
                card(getString(R.string.watch_setup_copy_choose_gskill_file)) { chooseSkillFile() }
                text(getString(R.string.watch_setup_copy_door_access_packages_are_currently_supported_this_sends_the), true)
                button(if (busy) getString(R.string.watch_setup_copy_transferring_confirm_on_the_watch) else getString(R.string.watch_setup_copy_send_to_watch),
                    enabled = connected && skillBytes != null && !busy) { sendSkill() }
            }
            "cloud" -> {
                text(device(R.string.watch_setup_copy_use_a_phone_configuration, R.string.watch_setup_copy_choose_a_cloud_agent_on_the_phone), true)
                val contacts = AppStore.contacts(this)
                for (i in 0 until contacts.length()) {
                    val raw = contacts.getJSONObject(i)
                    if (raw.optString("delivery_mode") != "cloud_api") continue
                    val models = AppStore.cloudModels(this, raw.getString("id"))
                    for (j in 0 until models.length()) {
                        val model = models.getJSONObject(j)
                        if (model.optString("api_key").isBlank()) continue
                        card(raw.optString("name").ifBlank { raw.optString("cloud_provider") } + " · " + model.optString("model_id"), getString(R.string.watch_setup_copy_key_hidden)) {
                            provider = raw.optString("cloud_provider")
                            selectedCloudAgent = raw.optString("name").ifBlank { provider }
                            profile = JSONObject().put("endpoint", model.optString("endpoint")).put("model", model.optString("model_id"))
                                .put("api_key", model.optString("api_key")).put("api_style", model.optString("api_style", "openai"))
                            tested = false; go("edit")
                        }
                    }
                }
                card(getString(R.string.watch_setup_copy_new_configuration)) { chooseProvider() }
                text(getString(R.string.watch_setup_copy_copies_the_selected_configuration_without_changing_phone_settings), true)
                if (profile.length() > 0) card(getString(R.string.watch_setup_copy_resume_draft)) { go("edit") }
            }
            "edit" -> {
                card(getString(R.string.watch_setup_copy_provider) + provider) { chooseProvider() }
                input(getString(R.string.watch_setup_copy_endpoint_full_request_url), profile.optString("endpoint")) { profile.put("endpoint", it.trim()); tested = false }
                input("API Key", profile.optString("api_key"), password = true) { profile.put("api_key", it.trim()); tested = false }
                card(getString(R.string.watch_setup_copy_select_model), profile.optString("model")) { chooseModel() }
                input(getString(R.string.watch_setup_copy_model_id_editable), profile.optString("model")) { profile.put("model", it.trim()); tested = false }
                card(getString(R.string.watch_setup_copy_deep_thinking), device(R.string.watch_setup_copy_off_concise_watch_responses, R.string.watch_setup_copy_off_concise_glasses_responses))
                button(getString(R.string.watch_setup_copy_test_connection), primary = false) { testCloud() }
                button(getString(R.string.watch_setup_copy_save_and_continue)) { runCatching { WatchSetupCloud.validate(profile) }.onSuccess { go("preview") }.onFailure { invalid() } }
            }
            "preview" -> {
                card(if (tested) getString(R.string.watch_setup_copy_phone_connection_test_passed) else getString(R.string.watch_setup_copy_connection_not_tested), device(R.string.watch_setup_copy_not_yet_transferred_to_the_watch, R.string.watch_setup_copy_not_yet_transferred_to_the_glasses))
                card(device(R.string.watch_setup_copy_watch, R.string.watch_setup_copy_glasses), deviceName)
                card(selectedCloudAgent.ifBlank { provider }, profile.optString("model")); card("API Key", getString(R.string.watch_setup_copy_hidden))
                if (!connected && glassesMode) button(getString(R.string.watch_setup_copy_connect_glasses_and_transfer)) {
                    resumePreviewAfterConnect = true; go("discover"); discover()
                } else button(device(R.string.watch_setup_copy_transfer_to_watch, R.string.watch_setup_copy_transfer_to_glasses)) { exchange(JSONObject().put("type", "configure").put("kind", "cloud").put("profile", profile)
                    .put("agent_name", selectedCloudAgent.ifBlank { provider })) { result -> require(result.optString("status") == "saved"); detail = selectedCloudAgent.ifBlank { provider } + " · " + profile.optString("model"); disconnect(); go("success") } }
            }
            "remote" -> {
                card(getString(R.string.watch_setup_copy_scan_computer_pairing_code), getString(R.string.watch_setup_copy_use_a_fresh_pairing_code_for_the_watch_s)) {
                    scanning = true; IntentIntegrator(this).setDesiredBarcodeFormats(IntentIntegrator.QR_CODE).setPrompt(getString(R.string.watch_setup_copy_scan_the_computer_pairing_code)).setBeepEnabled(false).initiateScan()
                }
                card(getString(R.string.watch_setup_copy_enter_pairing_information)) {
                    val field = EditText(this).apply { isSaveEnabled = false; inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE }
                    AlertDialog.Builder(this).setTitle(getString(R.string.watch_setup_copy_paste_computer_pairing_information)).setView(field).setPositiveButton(getString(R.string.watch_setup_copy_continue)) { _, _ -> pair(field.text.toString()) }.setNegativeButton(getString(R.string.watch_setup_copy_cancel_2), null).show()
                }
            }
            "waiting" -> { card(desktopName, getString(R.string.watch_setup_copy_waiting_for_computer_approval)); text(getString(R.string.watch_setup_copy_approve_the_watch_pairing_request_on_your_computer_agents), true) }
            "agents" -> {
                card(desktopName, getString(R.string.watch_setup_copy_computer_authorized))
                for (i in 0 until agents.length()) { val agent = agents.getJSONObject(i); card((if (selectedAgent == agent.getString("id")) "● " else "○ ") + agent.optString("name")) { selectedAgent = agent.getString("id"); render() } }
                button(getString(R.string.watch_setup_copy_use_this_agent_on_watch), enabled = selectedAgent.isNotBlank()) {
                    exchange(JSONObject().put("type", "configure").put("kind", "select_agent").put("agent_id", selectedAgent)) { result -> require(result.optString("status") == "saved"); detail = desktopName + " · " + result.optString("agent_name"); disconnect(); go("success") }
                }
            }
            "success" -> { card(device(R.string.watch_setup_copy_watch_confirmed_receipt, R.string.watch_setup_copy_glasses_confirmed_receipt), detail); text(if (skillTransferComplete) getString(R.string.watch_setup_copy_installed_on_the_watch_manage_enable_or_uninstall_it) else device(R.string.watch_setup_copy_you_can_now_chat_on_the_watch, R.string.watch_setup_copy_say_hello_hello_on_the_glasses_to_start_chatting), true); button(getString(R.string.watch_setup_copy_done)) { finish() } }
            "offline" -> {
                card(device(R.string.watch_setup_copy_no_watch_acknowledgment, R.string.watch_setup_copy_no_glasses_acknowledgment), getString(R.string.watch_setup_copy_your_draft_remains_available_in_this_screen))
                text(device(R.string.watch_setup_copy_use_the_same_wi_fi_and_reopen_watch_setup, R.string.watch_setup_copy_use_the_same_wi_fi_and_reopen_glasses_setup), true)
                button(getString(R.string.watch_setup_copy_reconnect)) { go("discover"); discover() }
            }
        }
        setContentView(root)
    }
    private fun invalid() { Toast.makeText(this, getString(R.string.watch_setup_copy_check_the_full_https_endpoint_model_and_key), Toast.LENGTH_LONG).show() }
    private fun chooseSkillFile() {
        if (busy || pickingSkill) return
        pickingSkill = true
        try {
            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE); type = "*/*"
            }, 94)
        } catch (_: android.content.ActivityNotFoundException) {
            pickingSkill = false
            Toast.makeText(this, getString(R.string.watch_setup_copy_no_file_picker_is_available_on_the_phone), Toast.LENGTH_LONG).show()
        }
    }
    private fun readSkillFile(uri: android.net.Uri) {
        busy = true; go("skills"); val owner = generation
        worker.execute {
            val result = runCatching {
                val bytes = contentResolver.openInputStream(uri)?.use { input ->
                    val output = java.io.ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        require(output.size() + count <= DoorAccessSkillPackage.MAX_PACKAGE_BYTES)
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray()
                } ?: error("Cannot read Skill")
                bytes to DoorAccessSkillPackage.inspect(bytes).version
            }
            main.post {
                if (owner != generation || isDestroyed) return@post
                busy = false
                result.onSuccess { (bytes, version) -> skillBytes = bytes; skillVersion = version }
                    .onFailure { Toast.makeText(this, getString(R.string.watch_setup_copy_invalid_or_unsupported_skill_existing_configuration_was_not_changed), Toast.LENGTH_LONG).show() }
                render()
            }
        }
    }
    private fun sendSkill() {
        val bytes = skillBytes ?: return
        val connection = client
        if (!connected || connection == null) { go("offline"); return }
        busy = true; render(); val owner = generation
        worker.execute {
            val result = runCatching { WatchSkillTransfer.send(bytes) { payload ->
                connection.exchange(payload, if (payload.getString("kind") == "skill_finish") 90000 else 30000)
            } }
            main.post {
                if (owner != generation || isDestroyed) return@post
                busy = false
                result.onSuccess { response ->
                    if (response.optString("status") == "saved") {
                        detail = getString(R.string.watch_setup_copy_door_access_skill) + " · v$skillVersion"
                        skillTransferComplete = true; skillBytes = null; disconnect(); go("success")
                    } else {
                        render()
                        Toast.makeText(this, getString(R.string.watch_setup_copy_not_installed_confirm_on_the_watch_and_try_again), Toast.LENGTH_LONG).show()
                    }
                }.onFailure { disconnect(); go("offline") }
            }
        }
    }
    private fun chooseProvider() {
        val names = CLOUD_MODEL_PRESETS.map { it.provider }.distinct()
        AlertDialog.Builder(this).setTitle(getString(R.string.watch_setup_copy_select_provider)).setItems(names.toTypedArray()) { _, n ->
            provider = names[n]; val preset = CLOUD_MODEL_PRESETS.first { it.provider == provider }
            selectedCloudAgent = provider
            profile = JSONObject().put("endpoint", preset.endpoint).put("model", preset.modelId).put("api_style", preset.apiStyle).put("api_key", "")
            tested = false; go("edit")
        }.show()
    }
    private fun chooseModel() {
        val options = CLOUD_MODEL_PRESETS.filter { it.provider == provider }
        AlertDialog.Builder(this).setTitle(getString(R.string.watch_setup_copy_select_model)).setItems(options.map { it.name }.toTypedArray()) { _, n ->
            val option = options[n]; profile.put("model", option.modelId).put("endpoint", option.endpoint).put("api_style", option.apiStyle); tested = false; render()
        }.show()
    }
    private fun testCloud() {
        val copy = JSONObject(profile.toString())
        if (runCatching { WatchSetupCloud.validate(copy) }.isFailure) { invalid(); return }
        busy = true; render(); val owner = generation; val revision = pageRevision
        worker.execute {
            val ok = runCatching { WatchSetupCloud.test(copy) }.getOrDefault(false)
            main.post { if (owner == generation && revision == pageRevision && !isDestroyed) { busy = false; tested = ok; if (ok) go("preview") else { render(); Toast.makeText(this, getString(R.string.watch_setup_copy_test_failed_check_credentials_model_or_network), Toast.LENGTH_LONG).show() } } }
        }
    }
    private fun connect() {
        val cm = getSystemService(ConnectivityManager::class.java)
        val network = cm.allNetworks.firstOrNull { cm.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true }
        val number = port.toIntOrNull()
        if (network == null || number == null || number !in 1..65535) { devices.releaseSelection(); busy = false; render(); Toast.makeText(this, getString(R.string.watch_setup_copy_connect_to_wi_fi_and_check_the_ip_and), Toast.LENGTH_LONG).show(); return }
        stopDiscovery(); disconnect(); val owner = generation
        val connection = WatchSetupClient(); client = connection; go("connecting")
        worker.execute {
            runCatching { connection.connect(network, host, number) { value -> main.post { if (owner == generation) { code = value; go("confirm") } } } }
                .onSuccess { main.post { if (owner == generation) {
                    connected = true; busy = false
                    val next = if (resumePreviewAfterConnect) "preview" else "hub"
                    resumePreviewAfterConnect = false; go(next)
                } } }
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
        if (qr == null) { Toast.makeText(this, getString(R.string.watch_setup_copy_pairing_code_is_invalid_or_expired_generate_a_new), Toast.LENGTH_LONG).show(); return }
        desktopName = qr.optString("desktop_name").ifBlank { getString(R.string.watch_setup_copy_my_computer) }
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
        if (requestCode == 94) {
            pickingSkill = false
            if (resultCode == RESULT_OK) data?.data?.let { readSkillFile(it) }
            return
        }
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

    private fun stopWifiScan() {
        wifiScanReceiver?.let { runCatching { unregisterReceiver(it) } }
        wifiScanReceiver = null
    }

    private fun wifiFeedback(value: String) {
        wifiScanStatus = value
        if (page == "wifi") wifiScanFeedback?.text = value
    }

    private fun beginWifiScan(retryPermission: Boolean = false) {
        if (page != "wifi" || isDestroyed) return
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            wifiFeedback(getString(R.string.watch_setup_copy_nearby_wi_fi_scanning_needs_precise_location_permission_you))
            if (!wifiScanPermissionAsked || retryPermission) {
                wifiScanPermissionAsked = true
                requestPermissions(arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION), 93)
            }
            return
        }
        val wifi = getSystemService(WifiManager::class.java)
        if (!getSystemService(LocationManager::class.java).isLocationEnabled) {
            wifiFeedback(getString(R.string.watch_setup_copy_phone_location_is_off_turn_it_on_to_scan))
            return
        }
        if (!wifi.isWifiEnabled) {
            wifiFeedback(getString(R.string.watch_setup_copy_phone_wi_fi_is_off_enter_the_network_name))
            return
        }
        if (wifiScanReceiver == null) {
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    if (page != "wifi") return
                    loadWifiNetworks(wifi,
                        intent.getBooleanExtra(WifiManager.EXTRA_RESULTS_UPDATED, false))
                }
            }
            val filter = IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION)
            if (android.os.Build.VERSION.SDK_INT >= 33) registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            else registerReceiver(receiver, filter)
            wifiScanReceiver = receiver
        }
        loadWifiNetworks(wifi, false)
        val started = runCatching { wifi.startScan() }.getOrDefault(false)
        wifiFeedback(if (started) getString(R.string.watch_setup_copy_scanning_nearby_wi_fi)
            else getString(R.string.watch_setup_copy_the_system_limited_a_new_scan_showing_recent_results))
    }

    @Suppress("DEPRECATION")
    private fun loadWifiNetworks(wifi: WifiManager, updated: Boolean) {
        val results = runCatching { wifi.scanResults }.onFailure {
            wifiFeedback(getString(R.string.watch_setup_copy_cannot_read_nearby_wi_fi_check_precise_location_permission))
        }.getOrNull() ?: return
        wifiNetworks = results.asSequence().filter { it.SSID.isNotBlank() && it.capabilities.contains("PSK") }
            .groupBy { it.SSID }
            .entries.sortedByDescending { entry -> entry.value.maxOf { it.level } }
            .map { it.key }.take(20)
        if (updated) wifiFeedback(getString(R.string.watch_setup_copy_select_nearby_wi_fi_or_enter_a_name_manually))
        renderWifiNetworks()
    }

    private fun renderWifiNetworks() {
        val list = wifiNetworkList ?: return
        list.removeAllViews()
        if (wifiNetworks.isEmpty()) {
            list.addView(TextView(this).apply {
                text = getString(R.string.watch_setup_copy_no_networks_listed_enter_a_name_manually)
                setTextColor(color(R.color.text_secondary)); textSize = 13f; setPadding(dp(6), dp(8), dp(6), dp(8))
            })
            return
        }
        wifiNetworks.forEach { name ->
            list.addView(Button(this).apply {
                text = name; isAllCaps = false; textSize = 15f
                setTextColor(color(R.color.text_primary))
                background = shape(color(R.color.surface_bg))
                setOnClickListener {
                    wifiSsid = name
                    wifiSsidInput?.setText(name)
                    wifiSsidInput?.setSelection(name.length)
                    wifiFeedback(getString(R.string.watch_setup_copy_selected, name))
                }
            }, LinearLayout.LayoutParams(-1, dp(45)).apply { bottomMargin = dp(5) })
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 93 && page == "wifi") {
            if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED)
                beginWifiScan()
            else wifiFeedback(getString(R.string.watch_setup_copy_precise_location_was_not_granted_enter_the_wi_fi))
        }
    }
}
