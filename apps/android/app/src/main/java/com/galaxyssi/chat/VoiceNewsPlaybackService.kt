package com.galaxyssi.chat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import com.galaxyssi.chat.voice.modelstream.CommittedSpeechChunk
import com.galaxyssi.chat.voice.tts.*
import java.util.Locale
import java.util.concurrent.Executors
import org.json.JSONArray

/** Owns public-news speech independently of any Activity. Never records microphone audio. */
class VoiceNewsPlaybackService : Service() {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private lateinit var queue: VoiceNewsQueue
    private lateinit var edge: MicrosoftEdgeTts
    private lateinit var media: MediaSession
    private lateinit var scheduler: TtsChunkScheduler
    private lateinit var feeder: TtsChunkFeeder
    private var androidTts: TextToSpeech? = null
    private var androidReady = false
    private var pendingAndroid: (() -> Unit)? = null
    private var androidCallbacks: Pair<String, TtsChunkPlaybackCallbacks>? = null
    private var focus: AudioFocusRequest? = null
    private var wake: PowerManager.WakeLock? = null
    private var foreground = false
    private var closed = false
    private var paragraph = ""
    private var error = ""
    private var publishedMediaState = ""
    private val expiry = Runnable { if (!queue.playing) stopSelf() }
    private val noisy = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) { pause() }
    }
    private val audio get() = getSystemService(AudioManager::class.java)
    private val attributes get() = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()

    override fun onCreate() {
        super.onCreate()
        queue = VoiceNewsQueue(readCheckpoint(this))
        edge = MicrosoftEdgeTts(applicationContext)
        scheduler = TtsChunkScheduler(object : TtsChunkPlayer {
            override fun prefetch(chunk: CommittedSpeechChunk) {
                val config = VoiceAssistantSettings.get(this@VoiceNewsPlaybackService)
                if (config.ttsProvider == VoiceAssistantSettings.PROVIDER_MICROSOFT_EDGE) edge.prefetch(
                    chunk.requestId, progressiveTtsPrefetchKey(chunk), chunk.speechText,
                    LanguagePolicySettings.microsoftVoice(config.ttsLanguage, config.microsoftVoice))
            }
            override fun play(chunk: CommittedSpeechChunk, callbacks: TtsChunkPlaybackCallbacks): TtsChunkPlayback {
                val token = queue.revision
                val config = VoiceAssistantSettings.get(this@VoiceNewsPlaybackService)
                val guarded = TtsChunkPlaybackCallbacks(
                    { main.post { if (!closed && token == queue.revision) callbacks.onStarted() } },
                    { success, code -> main.post { if (!closed && token == queue.revision) callbacks.onCompleted(success, code) } })
                if (config.ttsProvider == VoiceAssistantSettings.PROVIDER_MICROSOFT_EDGE) {
                    edge.speak(chunk.speechText, LanguagePolicySettings.microsoftVoice(config.ttsLanguage, config.microsoftVoice),
                        prefetchKey = progressiveTtsPrefetchKey(chunk), onPlaybackStarted = guarded.onStarted,
                        recordCompletion = false, communicationPlayback = AppVoiceControlBridge.usesCommunicationAudio(),
                        mediaPlayback = !AppVoiceControlBridge.usesCommunicationAudio(), onDone = guarded.onCompleted)
                } else playAndroid(chunk, guarded)
                return TtsChunkPlayback { edge.stop(); pendingAndroid = null; androidCallbacks = null; androidTts?.stop() }
            }
            override fun releaseSession(sessionId: String) { edge.clearPrefetches(sessionId) }
        })
        feeder = TtsChunkFeeder(scheduler)
        media = MediaSession(this, "GalaxySSI news").apply {
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() { dispatch("resume") }
                override fun onPause() { dispatch("pause") }
                override fun onStop() { dispatch("stop") }
                override fun onSkipToNext() { dispatch("next") }
            }, main)
            setPlaybackToLocal(attributes)
            setSessionActivity(openPendingIntent())
            setMetadata(MediaMetadata.Builder().putString(MediaMetadata.METADATA_KEY_TITLE,
                getString(R.string.voice_news_title)).putString(MediaMetadata.METADATA_KEY_ARTIST, "GalaxySSI").build())
            isActive = true
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(NotificationChannel(
            CHANNEL, getString(R.string.voice_news_title), NotificationManager.IMPORTANCE_LOW).apply {
            setSound(null, null); setShowBadge(false)
        })
        running = java.lang.ref.WeakReference(this)
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(noisy, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY), RECEIVER_NOT_EXPORTED)
        else @Suppress("DEPRECATION") registerReceiver(noisy, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
    }

    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // No auto-play after process death or boot; a new explicit media action is required.
        if (intent == null) { stopSelf(); return START_NOT_STICKY }
        try {
            promote()
            dispatch(intent.action.orEmpty(), intent.getStringArrayListExtra("ids"))
        } catch (_: Exception) { fail("playback_start_failed") }
        return START_NOT_STICKY
    }

    private fun dispatch(action: String, ids: List<String>? = null) {
        if (closed) return
        try {
            when (action) {
                "replace" -> { pause(false); queue.replace(ids.orEmpty()); resume() }
                "resume" -> resume()
                "pause" -> pause()
                "next" -> { pause(false); if (queue.next()) resume() else settle() }
                "stop" -> { queue.stop(true); cancelSpeech(); settle(); stopSelf() }
                else -> { pause(); stopSelf() }
            }
        } catch (_: Exception) { fail("playback_start_failed") }
    }

    private fun resume() {
        if (queue.playing) return
        if (queue.articleId.isBlank()) { fail("news_queue_empty"); return }
        promote()
        if (audio.mode == AudioManager.MODE_IN_CALL ||
            audio.mode == AudioManager.MODE_IN_COMMUNICATION && !AppVoiceControlBridge.usesCommunicationAudio() || !acquireFocus()) {
            fail("audio_focus_unavailable"); return
        }
        main.removeCallbacks(expiry)
        val token = queue.resume()
        val id = queue.articleId
        val savedOffset = queue.checkpoint.offset
        paragraph = ""; error = ""
        publish(); saveCheckpoint()
        worker.execute {
            val body = runCatching { AttentionArticleStore(applicationContext).body(id)?.let {
                com.galaxyssi.chat.voice.modelstream.SpeechTextNormalizer.normalize(it)
            } }.getOrNull()
            val start = savedOffset.coerceIn(0, body?.length ?: 0)
            val command = if (!body.isNullOrBlank() && start < body.length) runCatching {
                AgentReplySpeechController("background-news").toggle(
                    AgentReplySpeechTarget("news:$id:$token", "news:$id", body.substring(start), true))
            }.getOrNull() else null
            main.post {
                if (closed || queue.revision != token) return@post
                if (body.isNullOrBlank()) { fail("article_unavailable"); return@post }
                if (start == body.length) {
                    queue.pause(); if (queue.next()) resume() else settle()
                    return@post
                }
                var searchFrom = start
                if (command == null) { fail("article_not_speakable"); return@post }
                val sessionId = command.beginSessionId
                if (sessionId.isBlank()) { fail("article_not_speakable"); return@post }
                scheduler.begin(sessionId, TtsChunkSchedulerCallbacks(
                    onPlaybackStarted = { chunk ->
                        if (queue.revision == token) {
                            val found = body.indexOf(chunk.speechText, searchFrom)
                            if (found >= 0) searchFrom = found + chunk.speechText.length
                            queue.progress(token, if (found >= 0) found else queue.checkpoint.offset)
                            paragraph = chunk.speechText.take(1200)
                            renewWake(); saveCheckpoint(); publish()
                        }
                    },
                    onCapacityAvailable = { feeder.onCapacityAvailable(sessionId) },
                    onFinished = { success, _ ->
                        if (queue.revision == token) {
                            feeder.clear(sessionId)
                            if (!success) fail("speech_failed")
                            else { queue.pause(); if (queue.next()) resume() else settle() }
                        }
                    }))
                feeder.begin(sessionId)
                feeder.offer(sessionId, command.chunks)
                feeder.finish(sessionId)
            }
        }
    }

    private fun pause(notify: Boolean = true) {
        queue.pause(); cancelSpeech(); if (notify) settle()
    }
    private fun cancelSpeech() {
        val id = scheduler.snapshot().sessionId
        scheduler.cancelActive(TtsCancelReason.USER_STOP); feeder.clear(id)
        pendingAndroid = null; androidCallbacks = null; androidTts?.stop(); edge.stop()
        releaseFocus(); wake?.let { if (it.isHeld) it.release() }; wake = null
        paragraph = ""
    }
    private fun fail(code: String) { queue.fail(); error = code; cancelSpeech(); settle() }
    private fun settle() {
        paragraph = ""; releaseFocus(); wake?.let { if (it.isHeld) it.release() }; wake = null
        saveCheckpoint(); publish()
        if (foreground) { stopForeground(STOP_FOREGROUND_DETACH); foreground = false }
        main.removeCallbacks(expiry); main.postDelayed(expiry, 60_000L)
    }
    private fun acquireFocus(): Boolean {
        if (focus != null) return true
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(attributes).setWillPauseWhenDucked(true)
            .setOnAudioFocusChangeListener({ change -> if (change < 0) pause() }, main).build()
        if (audio.requestAudioFocus(request) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) return false
        focus = request; renewWake(); return true
    }
    private fun releaseFocus() { focus?.let(audio::abandonAudioFocusRequest); focus = null }
    private fun renewWake() {
        val lock = wake ?: getSystemService(PowerManager::class.java).newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK, "GalaxySSI:news-speech").apply { setReferenceCounted(false); wake = this }
        lock.acquire(120_000L)
    }

    private fun playAndroid(chunk: CommittedSpeechChunk, callbacks: TtsChunkPlaybackCallbacks) {
        val id = progressiveTtsPrefetchKey(chunk)
        androidCallbacks = id to callbacks
        val speak: () -> Unit = {
            val config = VoiceAssistantSettings.get(this)
            androidTts?.language = Locale.forLanguageTag(config.ttsLanguage)
            androidTts?.setAudioAttributes(attributes)
            if (androidTts?.speak(chunk.speechText, TextToSpeech.QUEUE_FLUSH, null, id) == TextToSpeech.ERROR)
                callbacks.onCompleted(false, "tts_rejected")
            main.postDelayed({
                if (androidCallbacks?.first == id) {
                    androidCallbacks = null; androidTts?.stop(); callbacks.onCompleted(false, "tts_timeout")
                }
            }, ProgressiveTtsTimeoutPolicy.forText(chunk.speechText))
        }
        if (androidReady) { speak(); return }
        pendingAndroid = speak
        main.postDelayed({
            if (!androidReady && androidCallbacks?.first == id) {
                pendingAndroid = null; androidCallbacks = null; callbacks.onCompleted(false, "tts_init_timeout")
            }
        }, 15_000L)
        if (androidTts != null) return
        androidTts = TextToSpeech(applicationContext) { status -> main.post {
            if (closed) return@post
            androidReady = status == TextToSpeech.SUCCESS
            val pending = pendingAndroid; pendingAndroid = null
            if (androidReady) pending?.invoke() else {
                androidCallbacks?.second?.onCompleted(false, "tts_not_ready"); androidCallbacks = null
            }
        } }.apply {
            setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(id: String?) { main.post { androidCallbacks?.takeIf { it.first == id }?.second?.onStarted?.invoke() } }
                override fun onDone(id: String?) = finish(id, true)
                @Deprecated("Android callback") override fun onError(id: String?) = finish(id, false)
                private fun finish(id: String?, success: Boolean) { main.post {
                    val cb = androidCallbacks?.takeIf { it.first == id }?.second ?: return@post
                    androidCallbacks = null; cb.onCompleted(success, if (success) null else "tts_failed")
                } }
            })
        }
    }

    private fun publish() {
        VoiceNewsPlaybackBus.publish(VoiceNewsPlaybackState(queue.articleId, queue.state, paragraph, error))
        val mediaState = "${queue.articleId}:${queue.state}"
        if (publishedMediaState == mediaState) return
        publishedMediaState = mediaState
        val state = when (queue.state) {
            "loading" -> PlaybackState.STATE_BUFFERING
            "playing" -> PlaybackState.STATE_PLAYING
            "paused" -> PlaybackState.STATE_PAUSED
            "failed" -> PlaybackState.STATE_ERROR
            else -> PlaybackState.STATE_STOPPED
        }
        media.setPlaybackState(PlaybackState.Builder().setActions(PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
            PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_SKIP_TO_NEXT or PlaybackState.ACTION_STOP)
            .setState(state, PlaybackState.PLAYBACK_POSITION_UNKNOWN, if (queue.playing) 1f else 0f).build())
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION, notification())
    }
    private fun promote() {
        if (foreground) return
        if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        else startForeground(NOTIFICATION, notification())
        foreground = true
        publishedMediaState = ""
    }
    private fun notification(): Notification = Notification.Builder(this, CHANNEL)
        .setSmallIcon(R.drawable.ic_voice_headphones).setContentTitle(getString(R.string.voice_news_title))
        .setContentText(getString(when (queue.state) {
            "playing", "loading" -> R.string.voice_call_speaking
            "failed" -> R.string.agent_reply_speech_failed
            else -> R.string.voice_news_paused
        })).setContentIntent(openPendingIntent()).setOnlyAlertOnce(true).setVisibility(Notification.VISIBILITY_PUBLIC)
        .setOngoing(queue.playing).setDeleteIntent(actionPendingIntent("stop"))
        .addAction(Notification.Action.Builder(android.graphics.drawable.Icon.createWithResource(this,
            if (queue.playing) R.drawable.ic_rich_pause else R.drawable.ic_rich_play), getString(if (queue.playing) R.string.voice_news_pause else R.string.voice_news_play),
            actionPendingIntent(if (queue.playing) "pause" else "resume")).build())
        .addAction(Notification.Action.Builder(android.graphics.drawable.Icon.createWithResource(this, android.R.drawable.ic_media_next),
            getString(R.string.voice_news_next), actionPendingIntent("next")).build())
        .addAction(Notification.Action.Builder(android.graphics.drawable.Icon.createWithResource(this, R.drawable.ic_screen_prompt_voice_stop),
            getString(R.string.voice_news_stop), actionPendingIntent("stop")).build())
        .setStyle(Notification.MediaStyle().setMediaSession(media.sessionToken).setShowActionsInCompactView(0, 1, 2)).build()
    private fun openPendingIntent() = PendingIntent.getActivity(this, 0,
        Intent(this, ProactiveAttentionActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    private fun actionPendingIntent(action: String) = PendingIntent.getForegroundService(this, action.hashCode(),
        Intent(this, VoiceNewsPlaybackService::class.java).setAction(action), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    private fun saveCheckpoint() {
        val value = queue.checkpoint
        getSharedPreferences(PREFS, 0).edit().putString("ids", JSONArray(value.ids).toString())
            .putInt("index", value.index).putInt("offset", value.offset).apply()
    }
    override fun onDestroy() {
        if (running.get() === this) running.clear()
        closed = true; queue.pause(); cancelSpeech(); saveCheckpoint(); main.removeCallbacksAndMessages(null)
        runCatching { unregisterReceiver(noisy) }; media.release(); edge.shutdown(); androidTts?.shutdown(); worker.shutdownNow()
        stopForeground(STOP_FOREGROUND_REMOVE); getSystemService(NotificationManager::class.java).cancel(NOTIFICATION)
        VoiceNewsPlaybackBus.publish(VoiceNewsPlaybackState(queue.articleId, if (queue.articleId.isBlank()) "stopped" else "paused"))
        super.onDestroy()
    }
    companion object {
        private var running = java.lang.ref.WeakReference<VoiceNewsPlaybackService>(null)
        internal fun pauseForInput() {
            check(Looper.myLooper() == Looper.getMainLooper())
            running.get()?.let { if (it.queue.playing) it.pause() }
        }
        private const val CHANNEL = "voice_news_playback"
        private const val NOTIFICATION = 7813
        private const val PREFS = "voice_news_bookmark"
        internal fun command(context: Context, action: String, ids: List<String> = emptyList()) {
            context.startForegroundService(Intent(context, VoiceNewsPlaybackService::class.java).setAction(action)
                .putStringArrayListExtra("ids", ArrayList(ids)))
        }
        internal fun readCheckpoint(context: Context): VoiceNewsCheckpoint = runCatching {
            val prefs = context.getSharedPreferences(PREFS, 0)
            val array = JSONArray(prefs.getString("ids", "[]"))
            if (array.length() > 20) return@runCatching VoiceNewsCheckpoint()
            VoiceNewsCheckpoint((0 until array.length()).map { array.getString(it) }, prefs.getInt("index", 0), prefs.getInt("offset", 0))
        }.getOrDefault(VoiceNewsCheckpoint())
    }
}
