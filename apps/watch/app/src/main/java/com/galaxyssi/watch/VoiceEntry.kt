package com.galaxyssi.watch

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/** A distinct component ensures hardware shortcuts deliver a fresh voice request. */
class VoiceEntry : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startActivity(Intent(this, MainActivity::class.java)
            .setAction(Intent.ACTION_VOICE_COMMAND)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP))
        finish()
    }
}
