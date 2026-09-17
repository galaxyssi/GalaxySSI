package com.galaxyssi.watch

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.view.*
import android.widget.*
import java.util.Locale

/** Own the recognition UI so confirmation does not depend on a vendor activity. */
class WatchVoiceCaptureActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private val draft = WatchVoiceDraft()
    private var recognizer: SpeechRecognizer? = null
    private var listening = false
    private var generation = 0
    private var resumed = false
    private var startPending = false
    private lateinit var status: TextView
    private lateinit var transcript: TextView
    private lateinit var send: Button
    private val timeout = Runnable { if (listening) fail(SpeechRecognizer.ERROR_SPEECH_TIMEOUT) }
    private val tick = object : Runnable {
        override fun run() {
            if (!resumed || !hasWindowFocus() || isFinishing) { interruptSend(); return }
            val now = SystemClock.elapsedRealtime()
            draft.takeDue(now)?.let { finishWithText(it); return }
            val deadline = draft.deadline ?: return
            status.text = getString(R.string.voice_send_countdown, ((deadline - now + 999) / 1000).toInt())
            handler.postDelayed(this, 100)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER
            setPadding(dp(28), dp(26), dp(28), dp(18)); setBackgroundColor(Color.BLACK)
        }
        root.addView(TextView(this).apply {
            text = getString(R.string.voice_entry_name); textSize = 16f
            setTextColor(Color.rgb(98, 207, 255)); gravity = Gravity.CENTER
        }, LinearLayout.LayoutParams(-1, -2))
        status = TextView(this).apply { textSize = 12f; setTextColor(Color.LTGRAY); gravity = Gravity.CENTER }
        root.addView(status, LinearLayout.LayoutParams(-1, -2))
        transcript = TextView(this).apply { textSize = 16f; setTextColor(Color.WHITE); gravity = Gravity.CENTER; setPadding(0, dp(8), 0, dp(8)) }
        root.addView(ScrollView(this).apply { addView(transcript) }, LinearLayout.LayoutParams(-1, 0, 1f))
        val actions = LinearLayout(this).apply { gravity = Gravity.CENTER }
        send = Button(this).apply {
            textSize = 12f; setPadding(0, 0, 0, 0); minWidth = 0; minimumWidth = 0
            setOnClickListener {
                if (listening) { recognizer?.stopListening(); status.setText(R.string.voice_processing) }
                else draft.take()?.let { finishWithText(it) }
            }
        }
        actions.addView(send, LinearLayout.LayoutParams(0, dp(40), 1f))
        actions.addView(Button(this).apply {
            text = getString(R.string.voice_retry); textSize = 12f; setPadding(0, 0, 0, 0); minWidth = 0; minimumWidth = 0
            setOnClickListener { begin() }
        }, LinearLayout.LayoutParams(0, dp(40), 1f))
        root.addView(actions)
        root.addView(TextView(this).apply {
            text = getString(R.string.voice_samsung_fallback); textSize = 12f; setTextColor(Color.LTGRAY)
            gravity = Gravity.CENTER; setPadding(0, dp(5), 0, dp(5))
            setOnClickListener {
                interruptSend(); releaseRecognizer()
                if (!WatchSpeechInput.launch(this@WatchVoiceCaptureActivity) { startActivityForResult(it, 32) }) {
                    status.setText(R.string.speech_unavailable)
                }
            }
        }, LinearLayout.LayoutParams(-1, -2))
        setContentView(root)
        onBackInvokedDispatcher.registerOnBackInvokedCallback(android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT) { finish() }
        val restored = savedInstanceState?.getString("voice_text").orEmpty()
        if (restored.isNotBlank()) { draft.recognized(restored, 0); draft.interrupt(); showDraft() }
        else { status.setText(R.string.voice_listening); startPending = savedInstanceState == null; updateSend() }
    }

    override fun onResume() { super.onResume(); resumed = true }
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus) interruptSend()
        else if (resumed && startPending) { startPending = false; begin() }
    }
    override fun onPause() {
        resumed = false; startPending = false; interruptSend(); releaseRecognizer()
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (draft.text.isBlank()) status.setText(R.string.voice_paused)
        updateSend(); super.onPause()
    }
    override fun onDestroy() { handler.removeCallbacksAndMessages(null); releaseRecognizer(); super.onDestroy() }
    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString("voice_text", draft.text); super.onSaveInstanceState(outState)
    }
    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_DOWN) interruptSend()
        return super.dispatchTouchEvent(event)
    }
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN) interruptSend()
        return super.dispatchKeyEvent(event)
    }
    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        interruptSend(); return super.dispatchGenericMotionEvent(event)
    }
    private fun interruptSend() {
        handler.removeCallbacks(tick)
        if (draft.deadline != null) { draft.interrupt(); status.setText(R.string.voice_send_paused) }
    }
    private fun begin() {
        interruptSend(); releaseRecognizer(); draft.clear(); transcript.text = ""; updateSend()
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 44); return
        }
        if (!SpeechRecognizer.isRecognitionAvailable(this)) { status.setText(R.string.speech_unavailable); return }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        status.setText(R.string.voice_listening)
        val token = generation
        val listener = object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) { if (listening && token == generation) status.setText(R.string.voice_listening) }
            override fun onBeginningOfSpeech() = Unit
            override fun onRmsChanged(rmsdB: Float) = Unit
            override fun onBufferReceived(buffer: ByteArray?) = Unit
            override fun onEndOfSpeech() { if (listening && token == generation) status.setText(R.string.voice_processing) }
            override fun onError(error: Int) { if (listening && token == generation) fail(error) }
            override fun onResults(results: Bundle?) {
                if (!listening || token != generation) return
                val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty()
                releaseRecognizer()
                acceptFinal(text)
            }
            override fun onPartialResults(partialResults: Bundle?) {
                if (listening && token == generation) transcript.text = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty()
            }
            override fun onEvent(eventType: Int, params: Bundle?) = Unit
        }
        runCatching {
            recognizer = SpeechRecognizer.createSpeechRecognizer(this).apply { setRecognitionListener(listener) }
            listening = true; updateSend()
            recognizer!!.startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault().toLanguageTag())
                .putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                .putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1))
            handler.postDelayed(timeout, 45000)
        }.onFailure { fail(SpeechRecognizer.ERROR_CLIENT) }
    }
    private fun acceptFinal(text: String) {
        draft.recognized(text, SystemClock.elapsedRealtime())
        if (draft.text.isBlank()) { status.setText(R.string.speech_empty); updateSend(); return }
        showDraft()
        if (resumed && hasWindowFocus()) handler.post(tick) else interruptSend()
    }
    private fun showDraft() { transcript.text = draft.text; status.setText(R.string.voice_send_paused); updateSend() }
    private fun updateSend() {
        send.setText(if (listening) R.string.voice_stop else R.string.send)
        send.isEnabled = listening || draft.text.isNotBlank()
    }
    private fun fail(error: Int) {
        releaseRecognizer(); draft.clear(); updateSend()
        status.setText(when (error) {
            SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT, SpeechRecognizer.ERROR_SERVER,
            SpeechRecognizer.ERROR_SERVER_DISCONNECTED -> R.string.voice_network_error
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> R.string.wake_permission_needed
            SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> R.string.speech_empty
            else -> R.string.speech_unavailable
        })
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
    private fun releaseRecognizer() {
        listening = false; generation++; handler.removeCallbacks(timeout)
        recognizer?.let { recognizer = null; it.cancel(); it.destroy() }
    }
    private fun finishWithText(text: String) {
        if (isFinishing) return
        handler.removeCallbacks(tick); releaseRecognizer()
        setResult(RESULT_OK, Intent().putStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS, arrayListOf(text)))
        finish()
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 44) {
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
                startPending = true
                if (resumed && hasWindowFocus()) { startPending = false; begin() }
            } else status.setText(R.string.wake_permission_needed)
        }
    }
    @Deprecated("Platform speech fallback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 32 && resultCode == RESULT_OK) {
            // The vendor already required confirmation. Keep the returned draft for explicit sending.
            acceptFinal(data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull().orEmpty())
            interruptSend()
        }
    }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
