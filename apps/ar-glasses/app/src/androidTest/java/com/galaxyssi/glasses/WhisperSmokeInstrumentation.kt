package com.galaxyssi.glasses

import android.app.Instrumentation
import android.os.Bundle
import android.os.SystemClock
import java.io.File

/** Device benchmark: copy 16 kHz mono PCM16LE to the app files directory first. */
class WhisperSmokeInstrumentation : Instrumentation() {
    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        start()
    }

    override fun onStart() {
        val results = Bundle()
        try {
            val context = targetContext
            val bytes = File(context.filesDir, "whisper-bench.pcm").readBytes()
            val pcm = ShortArray(bytes.size / 2) { index ->
                val offset = index * 2
                ((bytes[offset + 1].toInt() shl 8) or (bytes[offset].toInt() and 0xff)).toShort()
            }
            WhisperTinyNative.load(WhisperTinyNative.prepareModel(context))
            val started = SystemClock.elapsedRealtime()
            results.putString("transcript", WhisperTinyNative.transcribe(pcm))
            results.putLong("decodeMs", SystemClock.elapsedRealtime() - started)
            results.putInt("samples", pcm.size)
        } catch (error: Throwable) {
            results.putString("error", error.stackTraceToString())
        } finally {
            WhisperTinyNative.close()
        }
        finish(0, results)
    }
}
