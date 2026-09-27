package com.galaxyssi.chat

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.widget.TextView

/** A normal visible Activity owns consent; no stored projection token is reused. */
class PhoneScreenRecordingActivity : Activity() {
    private var handedOff = false
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(TextView(this).apply {
            text = getString(R.string.screen_assistant_recording_consent)
            setPadding(24, 48, 24, 24)
        })
        if (!PhoneScreenRecording.isPending(intent.getStringExtra("recording_id").orEmpty())) { finish(); return }
        if (savedInstanceState == null) {
            startActivityForResult(getSystemService(MediaProjectionManager::class.java).createScreenCaptureIntent(), 71)
        }
    }
    @Deprecated("Android consent returns an Activity result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 71) return
        val id = intent.getStringExtra("recording_id").orEmpty()
        if (resultCode != RESULT_OK || data == null || !PhoneScreenRecording.isPending(id)) {
            PhoneScreenRecording.complete(id, error = "Screen recording consent was cancelled")
        } else {
            runCatching {
                val service = Intent(this, PhoneScreenRecordingService::class.java)
                    .setAction(PhoneScreenRecordingService.START).putExtra("recording_id", id)
                    .putExtra("duration_seconds", intent.getIntExtra("duration_seconds", 15))
                    .putExtra("result_code", resultCode).putExtra("projection_data", data)
                if (Build.VERSION.SDK_INT >= 26) startForegroundService(service) else startService(service)
                handedOff = true
            }.onFailure { PhoneScreenRecording.complete(id, error = "Recording could not start: ${it.message}") }
        }
        finish()
    }
    override fun onDestroy() {
        if (isFinishing && !handedOff) PhoneScreenRecording.complete(intent.getStringExtra("recording_id").orEmpty(),
            error = "Screen recording consent was cancelled")
        super.onDestroy()
    }
}
