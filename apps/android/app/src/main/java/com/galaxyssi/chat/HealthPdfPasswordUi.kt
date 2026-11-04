package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import kotlin.concurrent.thread

/** The secret is never passed to a Bundle, persisted task, clipboard, or background worker. */
internal class HealthPdfPasswordUi(private val activity: Activity) {
    private val main = Handler(Looper.getMainLooper())
    private var dialog: AlertDialog? = null
    private var running: CancellationSignal? = null

    fun <T> request(
        work: (CharArray, CancellationSignal, (Int, Int) -> Unit) -> T,
        discard: (T) -> Unit = {},
        complete: (Result<T>) -> Unit
    ) {
        if (running != null || dialog != null) return
        val ui = HealthCenterViews(activity)
        val input = EditText(activity).apply {
            tag = "health-pdf-password-input"
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
            imeOptions = EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING
            isSaveEnabled = false
            importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO
            setSingleLine(true)
            hint = activity.getString(R.string.health_pdf_password_title)
        }
        val prompt = AlertDialog.Builder(activity)
            .setTitle(R.string.health_pdf_password_title)
            .setView(ui.column().apply { setPadding(ui.dp(22), 0, ui.dp(22), 0); addView(input) })
            .setNegativeButton(R.string.common_cancel, null)
            .setPositiveButton(R.string.health_pdf_unlock) { _, _ ->
                val password = CharArray(input.text.length) { input.text[it] }
                input.text.clear()
                start(password, work, discard, complete)
            }.create()
        dialog = prompt
        prompt.setOnDismissListener {
            input.text.clear()
            if (dialog === prompt) dialog = null
        }
        prompt.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        prompt.show()
    }

    private fun <T> start(password: CharArray, work: (CharArray, CancellationSignal, (Int, Int) -> Unit) -> T,
                          discard: (T) -> Unit, complete: (Result<T>) -> Unit) {
        val signal = CancellationSignal()
        running = signal
        val progress = AlertDialog.Builder(activity)
            .setMessage(R.string.health_import_preparing)
            .setNegativeButton(R.string.common_cancel) { _, _ -> signal.cancel() }.create()
        progress.setOnCancelListener { signal.cancel() }
        progress.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        dialog = progress
        progress.show()
        thread(name = "health-protected-pdf") {
            val result = runCatching {
                work(password, signal) { page, count ->
                    main.post { if (!signal.isCanceled) progress.setMessage(activity.getString(R.string.health_import_recognizing, page, count)) }
                }
            }
            password.fill('\u0000')
            main.post {
                if (running === signal) running = null
                if (dialog === progress) dialog = null
                progress.dismiss()
                if (signal.isCanceled || activity.isDestroyed) result.onSuccess(discard)
                else complete(result)
            }
        }
    }

    fun cancel() {
        running?.cancel()
        dialog?.dismiss()
        dialog = null
    }
}
