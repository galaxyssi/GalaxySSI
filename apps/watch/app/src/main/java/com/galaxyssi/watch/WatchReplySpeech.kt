package com.galaxyssi.watch

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import com.galaxyssi.chat.MicrosoftEdgeTts
import com.galaxyssi.chat.MicrosoftTtsVoiceCatalog

/** Foreground paragraph queue using the exact Android Xiaoxiao synthesizer and cancellation. */
internal class WatchReplySpeech(context: Context, private val onActivityChanged: () -> Unit = {}, private val onError: () -> Unit) {
    private data class Chunk(val key: String, val text: String)
    private val main = Handler(Looper.getMainLooper())
    private val engine = MicrosoftEdgeTts(context.applicationContext)
    private val policy = WatchSpeechPolicy()
    private val audio = context.getSystemService(AudioManager::class.java)
    private val focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
        .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANT)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
        .setOnAudioFocusChangeListener({ change -> if (change < 0) stop() }, main).build()
    private val queue = ArrayDeque<Chunk>()
    private var generation = 0L
    private var sequence = 0L
    private var playing = false
    private var awaitingMore = false
    private var focused = false
    private var closed = false
    val active: Boolean get() = playing || queue.isNotEmpty() || awaitingMore

    fun observe(task: WatchTask?, enabled: Boolean) {
        if (closed) return
        // Track raw committed reply offsets so partial Markdown rendering cannot rewrite the prefix.
        val text = task?.reply.orEmpty()
        val allowed = enabled && (task == null || !task.state.terminal || task.state == TaskState.COMPLETED)
        val update = policy.observe(task?.id.orEmpty(), text, task?.state?.terminal != false, allowed)
        if (update.reset || !allowed) cancelPlayback()
        awaitingMore = update.awaitingMore
        enqueue(update.chunks.flatMap { WatchSpeechPolicy.chunks(WatchRichReply.render(it).toString()) })
        onActivityChanged()
    }
    fun read(text: String) {
        if (closed) return
        stop()
        enqueue(WatchSpeechPolicy.chunks(text))
    }
    fun stopIfActive(): Boolean = active.also { if (it) stop() }
    fun stop() { policy.stop(); cancelPlayback() }
    fun shutdown() { stop(); closed = true; engine.shutdown(); main.removeCallbacksAndMessages(null) }

    private fun enqueue(chunks: List<String>) {
        chunks.forEach { queue.addLast(Chunk("watch-speech-$generation-${sequence++}", it)) }
        playNext()
    }
    private fun playNext() {
        if (closed || playing) return
        if (queue.isEmpty()) { releaseFocus(); onActivityChanged(); return }
        if (!focused) {
            focused = audio.requestAudioFocus(focus) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            if (!focused) { stop(); onError(); return }
        }
        val chunk = queue.removeFirst()
        val owner = generation
        playing = true
        onActivityChanged()
        engine.speak(chunk.text, MicrosoftTtsVoiceCatalog.XIAOXIAO, prefetchKey = chunk.key) { success, _ ->
            main.post {
                if (owner != generation || closed) return@post
                playing = false
                if (success) playNext() else { stop(); onError() }
            }
        }
        queue.firstOrNull()?.let { engine.prefetch("watch-$generation", it.key, it.text, MicrosoftTtsVoiceCatalog.XIAOXIAO) }
    }
    private fun cancelPlayback() {
        generation++; queue.clear(); playing = false; awaitingMore = false
        engine.stop(); releaseFocus(); onActivityChanged()
    }
    private fun releaseFocus() { if (focused) audio.abandonAudioFocusRequest(focus); focused = false }
}
