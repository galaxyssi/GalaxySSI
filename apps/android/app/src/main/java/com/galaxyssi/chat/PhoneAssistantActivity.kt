package com.galaxyssi.chat

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.app.role.RoleManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.telecom.Call
import android.telecom.CallAudioState
import android.telecom.TelecomManager
import android.telecom.VideoProfile
import android.text.InputType
import android.view.Gravity
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import com.galaxyssi.chat.ui.PhoneAssistantDisplay
import com.galaxyssi.chat.ui.PhoneAssistantPanel

/** Real call controls only. Translation UI is capability-gated, not populated from demo transcripts. */
class PhoneAssistantActivity : Activity() {
    internal lateinit var panel: PhoneAssistantPanel
        private set
    private var number: EditText? = null
    private var draftNumber = ""
    private var dialerDialog: AlertDialog? = null
    private var selected: Call? = null
    private val handler = Handler(Looper.getMainLooper())
    private val changed: () -> Unit = { runOnUiThread { render() } }
    private val timer = object : Runnable {
        override fun run() { updateStatus(); handler.postDelayed(this, 1_000) }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (android.os.Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        }
        window.statusBarColor = getColor(R.color.page_bg)
        window.navigationBarColor = getColor(R.color.page_bg)
        panel = PhoneAssistantPanel(this)
        panel.back.setOnClickListener { finish() }
        panel.footer.status.setOnClickListener {
            val call = selected
            when {
                call == null -> showDialer()
                call.state == Call.STATE_RINGING -> call.answer(VideoProfile.STATE_AUDIO_ONLY)
                else -> showCallControls(call)
            }
        }
        panel.footer.route.setOnClickListener { GalaxySSIInCallService.current.get()?.let(::chooseRoute) }
        panel.footer.hangup.setOnClickListener { selected?.let {
            if (it.state == Call.STATE_RINGING) it.reject(false, null) else it.disconnect()
        } }
        setContentView(panel)
        draftNumber = savedInstanceState?.getString("number") ?: intent.data?.takeIf { it.scheme == "tel" }?.schemeSpecificPart.orEmpty()
        if (intent.action == Intent.ACTION_DIAL) panel.post { showDialer() }
    }
    override fun onResume() { super.onResume(); GalaxySSIInCallService.listeners.add(changed); render(); handler.post(timer) }
    override fun onPause() { handler.removeCallbacks(timer); GalaxySSIInCallService.listeners.remove(changed); super.onPause() }
    override fun onSaveInstanceState(outState: Bundle) { outState.putString("number", number?.text?.toString() ?: draftNumber); super.onSaveInstanceState(outState) }
    override fun onDestroy() { dialerDialog?.dismiss(); super.onDestroy() }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.data?.takeIf { it.scheme == "tel" }?.let { draftNumber = it.schemeSpecificPart; number?.setText(draftNumber) }
        render()
        if (intent.action == Intent.ACTION_DIAL) showDialer()
    }

    private fun render() {
        val service = GalaxySSIInCallService.current.get()
        val calls = service?.calls.orEmpty().filter { it.state != Call.STATE_DISCONNECTED }
        selected = calls.firstOrNull { it.state == Call.STATE_RINGING } ?: selected?.takeIf { it in calls } ?: calls.firstOrNull()
        val call = selected
        val caller = call?.details?.callerDisplayName?.takeIf(String::isNotBlank)
            ?: call?.details?.handle?.schemeSpecificPart ?: getString(R.string.voice_control_phone_title)
        panel.title.setOnClickListener {
            if (calls.size > 1) AlertDialog.Builder(this).setItems(calls.map {
                it.details.handle?.schemeSpecificPart ?: getString(R.string.voice_control_unknown_caller)
            }.toTypedArray()) { _, i -> selected = calls[i]; render() }.show()
        }
        panel.render(PhoneAssistantDisplay(caller, callStatus(), hasCall = call != null,
            ringing = call?.state == Call.STATE_RINGING, route = getString(when (service?.callAudioState?.route) {
                CallAudioState.ROUTE_BLUETOOTH -> R.string.voice_control_bluetooth
                CallAudioState.ROUTE_WIRED_HEADSET -> R.string.voice_control_wired
                CallAudioState.ROUTE_SPEAKER -> R.string.voice_control_speaker
                CallAudioState.ROUTE_EARPIECE -> R.string.voice_control_earpiece
                else -> R.string.voice_control_no_audio_route
            })))
    }
    private fun updateStatus() { panel.updateStatus(callStatus()) }
    private fun callStatus(): String {
        val call = selected
        val resource = when (call?.state) {
            Call.STATE_RINGING -> R.string.voice_control_incoming
            Call.STATE_ACTIVE -> R.string.voice_control_call_active
            Call.STATE_HOLDING -> R.string.voice_control_call_held
            Call.STATE_DIALING, Call.STATE_CONNECTING -> R.string.voice_control_dialing
            else -> R.string.voice_control_call_idle
        }
        val seconds = call?.details?.connectTimeMillis?.takeIf { it > 0 }?.let { (System.currentTimeMillis() - it).coerceAtLeast(0) / 1_000 }
        return getString(resource) + if (seconds != null) " · %02d:%02d".format(seconds / 60, seconds % 60) else ""
    }

    private fun showCallControls(call: Call) {
        val service = GalaxySSIInCallService.current.get() ?: return
        val mute = if (service.callAudioState?.isMuted == true) R.string.voice_call_unmute else R.string.voice_call_mute
        AlertDialog.Builder(this).setItems(arrayOf(getString(mute), getString(R.string.voice_control_dtmf))) { _, index ->
            if (index == 0) service.setMuted(service.callAudioState?.isMuted != true) else keypad(call)
        }.show()
    }

    private fun showDialer() {
        if (dialerDialog?.isShowing == true) return
        val layout = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(20), dp(8), dp(20), dp(8)) }
        number = EditText(this).apply {
            inputType = InputType.TYPE_CLASS_PHONE
            hint = getString(R.string.voice_control_phone_number)
            setText(draftNumber)
        }
        layout.addView(number, LinearLayout.LayoutParams(-1, dp(56)))
        val role = if (android.os.Build.VERSION.SDK_INT >= 29) getSystemService(RoleManager::class.java) else null
        if (role?.isRoleAvailable(RoleManager.ROLE_DIALER) == true && !role.isRoleHeld(RoleManager.ROLE_DIALER)) {
            layout.addView(android.widget.Button(this).apply {
                setText(R.string.voice_control_default_dialer)
                setOnClickListener { requestDialerRole() }
            }, LinearLayout.LayoutParams(-1, -2))
        }
        dialerDialog = AlertDialog.Builder(this).setTitle(R.string.voice_control_dial).setView(layout)
            .setNegativeButton(android.R.string.cancel, null)
            .setPositiveButton(R.string.voice_control_dial, null).create().also { dialog ->
                dialog.setOnDismissListener { draftNumber = number?.text?.toString().orEmpty(); number = null; dialerDialog = null }
                dialog.show()
                dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener { dial() }
                dialog.window?.apply { setGravity(Gravity.BOTTOM); setLayout(-1, -2) }
            }
    }
    private fun chooseRoute(service: GalaxySSIInCallService) {
        val options = listOf(CallAudioState.ROUTE_EARPIECE to R.string.voice_control_earpiece,
            CallAudioState.ROUTE_SPEAKER to R.string.voice_control_speaker,
            CallAudioState.ROUTE_BLUETOOTH to R.string.voice_control_bluetooth,
            CallAudioState.ROUTE_WIRED_HEADSET to R.string.voice_control_wired)
            .filter { (service.callAudioState?.supportedRouteMask ?: 0) and it.first != 0 }
        AlertDialog.Builder(this).setItems(options.map { getString(it.second) }.toTypedArray()) { _, i -> service.setAudioRoute(options[i].first) }.show()
    }
    private fun keypad(call: Call) {
        val layout = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        listOf("123", "456", "789", "*0#").forEach { row ->
            val line = LinearLayout(this)
            row.forEach { digit -> line.addView(label(digit.toString(), 24f).apply {
                gravity = Gravity.CENTER
                setOnClickListener { call.playDtmfTone(digit); handler.postDelayed({ call.stopDtmfTone() }, 150) }
            }, LinearLayout.LayoutParams(0, dp(56), 1f)) }
            layout.addView(line)
        }
        AlertDialog.Builder(this).setView(layout).setOnDismissListener { call.stopDtmfTone() }.show()
    }
    private fun requestDialerRole() {
        if (android.os.Build.VERSION.SDK_INT >= 29) getSystemService(RoleManager::class.java)?.let {
            if (it.isRoleAvailable(RoleManager.ROLE_DIALER) && !it.isRoleHeld(RoleManager.ROLE_DIALER))
                startActivityForResult(it.createRequestRoleIntent(RoleManager.ROLE_DIALER), 40)
        }
    }
    private fun dial() {
        val text = number?.text?.toString().orEmpty().trim()
        if (text.isEmpty()) return
        if (checkSelfPermission(Manifest.permission.CALL_PHONE) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.CALL_PHONE), 41); return
        }
        runCatching { getSystemService(TelecomManager::class.java).placeCall(Uri.fromParts("tel", text, null), Bundle()) }
            .onSuccess { dialerDialog?.dismiss() }
            .onFailure { android.widget.Toast.makeText(this, R.string.voice_control_dial_failed,
                android.widget.Toast.LENGTH_LONG).show() }
    }
    private fun label(value: String, size: Float) = TextView(this).apply {
        text = value; textSize = size; gravity = Gravity.CENTER_VERTICAL; setTextColor(getColor(R.color.text_primary))
    }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
