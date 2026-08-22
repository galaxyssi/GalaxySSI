package com.signalasi.chat

import android.app.Activity
import android.app.AlertDialog
import android.app.DownloadManager
import android.app.Dialog
import android.app.NotificationManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ImageDecoder
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.drawable.AnimatedImageDrawable
import android.graphics.drawable.GradientDrawable
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaRecorder
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.OpenableColumns
import android.provider.MediaStore
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.text.Editable
import android.text.InputType
import android.text.SpannableString
import android.text.Spanned
import android.text.TextPaint
import android.text.TextUtils
import android.text.TextWatcher
import android.text.style.CharacterStyle
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.text.style.UpdateAppearance
import android.util.Base64
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.InputMethodManager
import android.widget.*
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.zxing.BarcodeFormat
import com.google.zxing.integration.android.IntentIntegrator
import com.google.zxing.qrcode.QRCodeWriter
import com.rementia.openwakeword.lib.WakeWordEngine
import com.rementia.openwakeword.lib.model.DetectionMode
import com.rementia.openwakeword.lib.model.WakeWordModel
import com.signalasi.chat.SignalASIMqttClient.Listener
import com.signalasi.chat.ui.AgentComposerUiPolicy
import com.signalasi.chat.ui.AppleHoldToTalkController
import com.signalasi.chat.ui.VoiceWaveformView
import com.signalasi.chat.voice.TranscriptHypothesis
import com.signalasi.chat.voice.VoiceFailure
import com.signalasi.chat.voice.VoiceFeatureFlags
import com.signalasi.chat.voice.VoiceInteractionCommand
import com.signalasi.chat.voice.VoiceInteractionCoordinator
import com.signalasi.chat.voice.VoiceInteractionCoordinatorRegistry
import com.signalasi.chat.voice.VoiceInteractionEvent
import com.signalasi.chat.voice.VoiceInteractionPhase
import com.signalasi.chat.voice.VoiceRouteDecision
import com.signalasi.chat.voice.VoiceRouteKind
import com.signalasi.chat.voice.VoiceSessionConfig
import com.signalasi.chat.voice.VoiceTtsRequest
import com.signalasi.chat.voice.VoiceTtsRequestRegistry
import com.signalasi.chat.voice.audio.AdaptiveEndpointConfig
import com.signalasi.chat.voice.audio.AndroidPcmRecorder
import com.signalasi.chat.voice.audio.DirectPcmFramePacket
import com.signalasi.chat.voice.audio.EndpointReason
import com.signalasi.chat.voice.audio.PcmCaptureConfig
import com.signalasi.chat.voice.audio.PcmSnapshot
import com.signalasi.chat.voice.audio.PcmStopReason
import com.signalasi.chat.voice.audio.PcmWaveFileAdapter
import com.signalasi.chat.voice.audio.VadDecision
import com.signalasi.chat.voice.audio.VoiceAudioHub
import com.signalasi.chat.voice.audio.VoiceAudioHubListener
import com.signalasi.chat.voice.asr.AsrNetworkType
import com.signalasi.chat.voice.asr.AsrProviderSelector
import com.signalasi.chat.voice.asr.AsrSessionConfig
import com.signalasi.chat.voice.asr.VoiceRecognitionPreference
import com.signalasi.chat.voice.asr.online.CachingRealtimeAsrCredentialSource
import com.signalasi.chat.voice.asr.online.HttpRealtimeAsrCredentialSource
import com.signalasi.chat.voice.asr.online.OnlineAsrCompletion
import com.signalasi.chat.voice.asr.online.OnlineRealtimeAsrTurn
import com.signalasi.chat.voice.asr.online.RealtimeAsrPreconnector
import com.signalasi.chat.voice.asr.online.RealtimeAsrProvider
import com.signalasi.chat.voice.asr.online.RealtimeAsrTurnAction
import com.signalasi.chat.voice.asr.remote.RemoteWhisperNodeClient
import com.signalasi.chat.voice.asr.remote.RemoteWhisperNodeRegistry
import com.signalasi.chat.voice.asr.remote.RemoteWhisperRoutingPolicy
import com.signalasi.chat.voice.asr.remote.SignalASILinkRemoteWhisperTransport
import com.signalasi.chat.voice.asr.local.AbortReason
import com.signalasi.chat.voice.asr.local.AsrConfig as HighAccuracyAsrConfig
import com.signalasi.chat.voice.asr.local.AsrEvent as HighAccuracyAsrEvent
import com.signalasi.chat.voice.asr.local.AsrPerformanceMode
import com.signalasi.chat.voice.asr.local.DefaultWhisperDecodeScheduler
import com.signalasi.chat.voice.asr.local.HighAccuracyAsrResult
import com.signalasi.chat.voice.asr.local.AsrTranscriptCompletenessPolicy
import com.signalasi.chat.voice.asr.local.HighAccuracyLocalAsrController
import com.signalasi.chat.voice.asr.local.HighAccuracyLocalAsrTurn
import com.signalasi.chat.voice.asr.local.LiveWhisperTranscriptionSession
import com.signalasi.chat.voice.asr.local.LiveWhisperTranscriptUpdate
import com.signalasi.chat.voice.asr.local.NativeWhisperCode
import com.signalasi.chat.voice.asr.local.LargeTurboQnnModelAction
import com.signalasi.chat.voice.asr.local.LargeTurboQnnModelManager
import com.signalasi.chat.voice.asr.local.LargeTurboQnnModelStatus
import com.signalasi.chat.voice.asr.local.QnnAsrEligibility
import com.signalasi.chat.voice.asr.local.QnnModelDownloadNetworkPolicy
import com.signalasi.chat.voice.asr.local.QnnWhisperPackageManager
import com.signalasi.chat.voice.asr.local.QnnWhisperPackageStatus
import com.signalasi.chat.voice.asr.local.WhisperDecodeScheduler
import com.signalasi.chat.voice.asr.local.largeTurboQnnModelAction
import com.signalasi.chat.voice.benchmark.WhisperBenchmarkManager
import com.signalasi.chat.voice.benchmark.WhisperBenchmarkDeferredException
import com.signalasi.chat.voice.benchmark.WhisperBenchmarkProgress
import com.signalasi.chat.voice.benchmark.WhisperBenchmarkRecord
import com.signalasi.chat.voice.benchmark.WhisperBenchmarkStage
import com.signalasi.chat.voice.benchmark.WhisperProviderChoice
import com.signalasi.chat.voice.benchmark.WhisperUserVoiceMode
import com.signalasi.chat.voice.correction.AndroidVoiceExecutionRecordStore
import com.signalasi.chat.voice.correction.CorrectionDecision
import com.signalasi.chat.voice.correction.DefaultVoiceCommandRiskClassifier
import com.signalasi.chat.voice.correction.TranscriptDiff
import com.signalasi.chat.voice.correction.VoiceCommandRisk
import com.signalasi.chat.voice.correction.VoiceCorrectionContextRecord
import com.signalasi.chat.voice.correction.VoiceCorrectionJournal
import com.signalasi.chat.voice.correction.VoiceExecutionLedger
import com.signalasi.chat.voice.correction.VoiceEntityType
import com.signalasi.chat.voice.correction.VoiceSecondPassCoordinator
import com.signalasi.chat.voice.correction.VoiceSecondPassRequest
import com.signalasi.chat.voice.correction.VoiceSecondPassResult
import com.signalasi.chat.voice.correction.VoiceSecondPassTriggerPolicy
import com.signalasi.chat.voice.audio.VoiceAudioSession
import com.signalasi.chat.voice.audio.VoiceAudioSessionConfig
import com.signalasi.chat.voice.agent.VoiceAgentEvent
import com.signalasi.chat.voice.agent.VoiceAgentRunBridge
import com.signalasi.chat.voice.agent.VoiceAgentRunListener
import com.signalasi.chat.voice.agent.VoiceAgentRunSnapshot
import com.signalasi.chat.voice.agent.VoiceAgentRunState
import com.signalasi.chat.voice.agent.VoiceAgentRunUpdate
import com.signalasi.chat.voice.metrics.VoiceLatencyTelemetry
import com.signalasi.chat.voice.metrics.VoiceLatencyTraceContext
import com.signalasi.chat.voice.metrics.VoiceTraceEvents
import com.signalasi.chat.voice.model.WhisperExecutionMode
import com.signalasi.chat.voice.model.WhisperCertificationLevel
import com.signalasi.chat.voice.model.WhisperMemoryAdmissionPolicy
import com.signalasi.chat.voice.model.WhisperModelFamily
import com.signalasi.chat.voice.model.WhisperModelFallbackPolicy
import com.signalasi.chat.voice.reliability.AndroidVoiceReliabilityController
import com.signalasi.chat.voice.reliability.VoicePipelineFeature
import com.signalasi.chat.voice.reliability.VoicePerformanceHealth
import com.signalasi.chat.voice.reliability.VoiceResourceMode
import com.signalasi.chat.voice.reliability.VoiceWorkloadProfile
import com.signalasi.chat.voice.modelstream.ModelStreamCancelReason
import com.signalasi.chat.voice.modelstream.CommittedSpeechChunk
import com.signalasi.chat.voice.modelstream.DefaultSentenceCommitter
import com.signalasi.chat.voice.modelstream.ModelStreamEvent
import com.signalasi.chat.voice.modelstream.ModelStreamUiMerger
import com.signalasi.chat.voice.modelstream.ModelStreamUiUpdate
import com.signalasi.chat.voice.modelstream.ModelUsage
import com.signalasi.chat.voice.modelstream.SentenceCommitter
import com.signalasi.chat.voice.tts.BargeInActions
import com.signalasi.chat.voice.tts.BargeInController
import com.signalasi.chat.voice.tts.BargeInTaskKind
import com.signalasi.chat.voice.tts.ProgressiveTtsUtteranceRegistry
import com.signalasi.chat.voice.tts.ProgressiveTtsUtteranceRequest
import com.signalasi.chat.voice.tts.TtsCancelReason
import com.signalasi.chat.voice.tts.TtsChunkPlayback
import com.signalasi.chat.voice.tts.TtsChunkPlaybackCallbacks
import com.signalasi.chat.voice.tts.TtsChunkPlayer
import com.signalasi.chat.voice.tts.TtsChunkScheduler
import com.signalasi.chat.voice.tts.TtsChunkSchedulerCallbacks
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.Executors
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import okhttp3.OkHttpClient
import kotlin.concurrent.thread
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.math.sin

internal fun MainActivity.agentProcessNarrationRow(entry: AgentTranscriptEntry): View = TextView(this).apply {
    text = localizedAgentProcessText(entry.text)
    setTextColor(getColorCompat(R.color.text_primary))
    textSize = 16f
    includeFontPadding = false
    setLineSpacing(dp(4).toFloat(), 1f)
    setPadding(0, dp(8), 0, dp(8))
    attachAgentTranscriptActions(this, entry)
}

internal fun MainActivity.agentUserTranscriptRow(entry: AgentTranscriptEntry): View = LinearLayout(this).apply {
    orientation = LinearLayout.VERTICAL
    gravity = Gravity.END
    layoutParams = LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.WRAP_CONTENT
    ).apply { topMargin = dp(14) }
    val blocks = AgentRichContentCodec.decode(entry.richOutputJson)
        .filter { it.type == AgentRichBlockType.IMAGE || it.type == AgentRichBlockType.FILE }
    blocks.forEach { block ->
        val imageAttachment = block.type == AgentRichBlockType.IMAGE
        addView(
            agentUserAttachmentBlock(block),
            LinearLayout.LayoutParams(
                if (imageAttachment) {
                    dp(AGENT_IMAGE_THUMBNAIL_WIDTH_DP)
                } else {
                    ViewGroup.LayoutParams.WRAP_CONTENT
                },
                if (imageAttachment) {
                    dp(AGENT_IMAGE_THUMBNAIL_HEIGHT_DP)
                } else {
                    ViewGroup.LayoutParams.WRAP_CONTENT
                }
            ).apply { bottomMargin = dp(6) }
        )
    }
    val attachmentOnlyLabel = blocks.isNotEmpty() && (
        entry.text == "[${blocks.firstOrNull()?.title.orEmpty()}]" ||
            entry.text == getString(R.string.agent_attachment_count, blocks.size)
        )
    if (AgentVoiceTranscriptPolicy.isPending(entry)) {
        addView(
            AgentVoiceTranscriptionPendingView(this@agentUserTranscriptRow),
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
    } else if (!attachmentOnlyLabel) {
        addView(TextView(this@agentUserTranscriptRow).apply {
            text = entry.text
            setTextColor(getColorCompat(R.color.text_primary))
            textSize = 16f
            setLineSpacing(dp(3).toFloat(), 1f)
            setTextIsSelectable(true)
            maxWidth = (resources.displayMetrics.widthPixels * 0.78f).toInt()
            setPadding(dp(15), dp(10), dp(15), dp(10))
            setBackgroundResource(R.drawable.bubble_agent_user_background)
            attachAgentTranscriptActions(this, entry)
        }, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ))
    }
}

internal fun MainActivity.agentUserAttachmentBlock(block: AgentRichBlock): View {
    val uri = Uri.parse(block.uri)
    if (block.type == AgentRichBlockType.IMAGE) {
        return ImageView(this).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            contentDescription = block.title
            background = GradientDrawable().apply {
                cornerRadius = dp(AGENT_IMAGE_THUMBNAIL_RADIUS_DP).toFloat()
                setColor(Color.parseColor("#F4F6F8"))
            }
            clipToOutline = true
            setOnClickListener { showAgentImagePreview(uri, block.title) }
            loadAgentImageThumbnail(
                this,
                uri,
                dp(AGENT_IMAGE_THUMBNAIL_WIDTH_DP * 2),
                dp(AGENT_IMAGE_THUMBNAIL_HEIGHT_DP * 2),
                adaptToTranscript = true
            )
            layoutParams = LinearLayout.LayoutParams(
                dp(AGENT_IMAGE_THUMBNAIL_WIDTH_DP),
                dp(AGENT_IMAGE_THUMBNAIL_HEIGHT_DP)
            )
        }
    }
    return LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(12), dp(10), dp(12), dp(10))
        background = GradientDrawable().apply {
            cornerRadius = dp(8).toFloat()
            setColor(Color.parseColor("#F4F6F8"))
            setStroke(dp(1), Color.parseColor("#DDE2E7"))
        }
        addView(ImageView(this@agentUserAttachmentBlock).apply {
            setImageResource(R.drawable.ic_agent_attach)
            imageTintList = android.content.res.ColorStateList.valueOf(Color.parseColor("#53606D"))
        }, LinearLayout.LayoutParams(dp(30), dp(30)).apply { marginEnd = dp(9) })
        addView(LinearLayout(this@agentUserAttachmentBlock).apply {
            orientation = LinearLayout.VERTICAL
            addView(TextView(this@agentUserAttachmentBlock).apply {
                text = block.title
                textSize = 14f
                setTextColor(getColorCompat(R.color.text_primary))
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.MIDDLE
            })
            if (block.text.isNotBlank()) addView(TextView(this@agentUserAttachmentBlock).apply {
                text = block.text
                textSize = 11f
                setTextColor(getColorCompat(R.color.text_secondary))
            })
        }, LinearLayout.LayoutParams(dp(190), ViewGroup.LayoutParams.WRAP_CONTENT))
        setOnClickListener {
            runCatching {
                startActivity(Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, block.mimeType.ifBlank { "application/octet-stream" })
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                })
            }
        }
    }
}

internal fun MainActivity.loadAgentImageThumbnail(
    image: ImageView,
    uri: Uri,
    width: Int,
    height: Int,
    adaptToTranscript: Boolean = false
) {
    val requestKey = uri.toString()
    image.tag = requestKey
    thread(name = "signalasi-image-thumbnail") {
        val bitmap = AgentImagePipeline.loadPreview(applicationContext, uri, width, height)
        runOnUiThread {
            if (!isDestroyed && image.tag == requestKey && bitmap != null) {
                image.setImageBitmap(bitmap)
                if (adaptToTranscript) {
                    val size = agentImageThumbnailSize(bitmap.width, bitmap.height)
                    image.layoutParams = image.layoutParams.apply {
                        this.width = dp(size.widthDp)
                        this.height = dp(size.heightDp)
                    }
                }
            } else {
                bitmap?.recycle()
            }
        }
    }
}

internal fun MainActivity.showAgentImagePreview(uri: Uri, title: String) {
    val dialog = Dialog(this, android.R.style.Theme_Black_NoTitleBar_Fullscreen)
    val root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
    val viewport = SignalASIPinchZoomViewport(this)
    val image = ImageView(this).apply {
        scaleType = ImageView.ScaleType.FIT_CENTER
        contentDescription = title
    }
    viewport.attach(image)
    root.addView(viewport, FrameLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.MATCH_PARENT
    ))
    if (title.isNotBlank()) {
        root.addView(TextView(this).apply {
            text = title
            textSize = 13f
            setTextColor(Color.WHITE)
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.MIDDLE
            setPadding(dp(16), dp(8), dp(16), dp(8))
            background = GradientDrawable().apply {
                cornerRadius = dp(8).toFloat()
                setColor(Color.argb(150, 0, 0, 0))
            }
        }, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
        ).apply {
            leftMargin = dp(24)
            rightMargin = dp(24)
            bottomMargin = dp(24)
        })
    }
    root.addView(ImageButton(this).apply {
        setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
        imageTintList = android.content.res.ColorStateList.valueOf(Color.WHITE)
        contentDescription = getString(R.string.agent_image_preview_close)
        setPadding(dp(10), dp(10), dp(10), dp(10))
        background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.argb(165, 30, 30, 30))
        }
        setOnClickListener { dialog.dismiss() }
    }, FrameLayout.LayoutParams(dp(48), dp(48), Gravity.TOP or Gravity.END).apply {
        topMargin = dp(20)
        rightMargin = dp(16)
    })
    dialog.setContentView(root)
    var previewBitmap: Bitmap? = null
    dialog.setOnDismissListener {
        image.setImageDrawable(null)
        previewBitmap?.recycle()
        previewBitmap = null
    }
    dialog.show()
    val metrics = resources.displayMetrics
    thread(name = "signalasi-image-preview") {
        val bitmap = AgentImagePipeline.loadPreview(
            applicationContext,
            uri,
            metrics.widthPixels * 2,
            metrics.heightPixels * 2
        )
        runOnUiThread {
            if (dialog.isShowing && bitmap != null) {
                previewBitmap = bitmap
                image.setImageBitmap(bitmap)
            } else {
                bitmap?.recycle()
            }
        }
    }
}

internal fun MainActivity.attachAgentTranscriptActions(textView: TextView, entry: AgentTranscriptEntry) {
    textView.setOnLongClickListener {
        val feedbackEntry = entry.role == AgentTranscriptRole.ASSISTANT &&
            (entry.dedupeKey.startsWith("global-agent:") ||
                entry.dedupeKey.startsWith("global-agent-digest:"))
        val helpfulLabel = getString(R.string.agent_global_feedback_helpful)
        val notRelevantLabel = getString(R.string.agent_global_feedback_not_relevant)
        val tooFrequentLabel = getString(R.string.agent_global_feedback_too_frequent)
        val copyLabel = getString(R.string.common_copy)
        val selectAllLabel = getString(R.string.common_select_all)
        val deleteLabel = getString(R.string.common_delete)
        val labels = buildList {
            if (feedbackEntry) {
                add(helpfulLabel)
                add(notRelevantLabel)
                add(tooFrequentLabel)
            }
            add(copyLabel)
            add(selectAllLabel)
            add(deleteLabel)
        }.toTypedArray()
        android.app.AlertDialog.Builder(this)
            .setItems(labels) { _, which ->
                when (labels[which]) {
                    helpfulLabel -> recordGlobalInsightFeedback(entry, GlobalAgentFeedbackKind.HELPFUL)
                    notRelevantLabel -> recordGlobalInsightFeedback(entry, GlobalAgentFeedbackKind.NOT_RELEVANT)
                    tooFrequentLabel -> recordGlobalInsightFeedback(entry, GlobalAgentFeedbackKind.TOO_FREQUENT)
                    copyLabel -> {
                        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        clipboard.setPrimaryClip(ClipData.newPlainText(getString(R.string.app_name), entry.text))
                        Toast.makeText(this, getString(R.string.toast_copied), Toast.LENGTH_SHORT).show()
                    }
                    selectAllLabel -> {
                        textView.requestFocus()
                        (textView.text as? android.text.Spannable)?.let(android.text.Selection::selectAll)
                        Toast.makeText(this, getString(R.string.agent_message_all_selected), Toast.LENGTH_SHORT).show()
                    }
                    deleteLabel -> {
                        if (agentTranscriptStore.deleteEntry(entry.id)) {
                            agentTranscriptWindow.remove(entry.id)
                            clearAgentTranscriptRows()
                            refreshAgentTranscriptWindow()
                        }
                    }
                }
            }
            .show()
        true
    }
}

internal fun MainActivity.recordGlobalInsightFeedback(entry: AgentTranscriptEntry, kind: GlobalAgentFeedbackKind) {
    recordGlobalInsightFeedback(entry.dedupeKey, kind)
}

internal fun MainActivity.recordGlobalInsightFeedback(dedupeKey: String, kind: GlobalAgentFeedbackKind): Boolean {
    val runtime = if (isGlobalSuperAgentRuntimeInitialized()) {
        globalSuperAgentRuntime
    } else GlobalSuperAgentRuntime.get(this)
    val count = runtime.recordProactiveFeedback(dedupeKey, kind)
    refreshGlobalInsightIndicator()
    Toast.makeText(
        this,
        getString(
            if (count > 0) R.string.agent_global_feedback_saved
            else R.string.agent_global_feedback_unavailable
        ),
        Toast.LENGTH_SHORT
    ).show()
    return count > 0
}

internal fun MainActivity.handleAgentRichAction(entry: AgentTranscriptEntry, action: AgentRichAction) {
    when (action.verb) {
        "copy" -> {
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            clipboard.setPrimaryClip(ClipData.newPlainText(action.label, action.value))
            Toast.makeText(this, getString(R.string.toast_copied), Toast.LENGTH_SHORT).show()
        }
        "open_uri" -> {
            val uri = runCatching { Uri.parse(action.value) }.getOrNull()
            if (uri?.scheme?.lowercase() in setOf("https", "content", "file", "android.resource")) {
                runCatching { startActivity(Intent(Intent.ACTION_VIEW, uri)) }
                    .onFailure { Toast.makeText(this, action.value, Toast.LENGTH_SHORT).show() }
            }
        }
        "set_input" -> setAgentRichInput(action.value, submit = false)
        "submit_prompt" -> setAgentRichInput(action.value, submit = true)
        "open_conversation" -> openAgentConversation(action.value)
        "decide_task_permission" -> runAgentRichTaskDecision(entry, action)
        "decide_remote_task_permission" -> runRemoteAgentTaskDecision(entry, action)
        "recover_agent_task" -> runAgentFailureRecovery(entry, action)
        "preview_runtime_artifact" -> previewRuntimeArtifact(action.value)
        "open_runtime_artifact" -> openRuntimeArtifact(action.value)
        "save_runtime_artifact" -> saveRuntimeArtifact(action.value)
        else -> Toast.makeText(this, action.label, Toast.LENGTH_SHORT).show()
    }
}

internal fun MainActivity.openRuntimeArtifact(rawPayload: String) {
    val payload = AgentRuntimeArtifactActionPayload.decode(rawPayload)
    if (payload == null) {
        Toast.makeText(this, R.string.agent_runtime_artifact_unavailable, Toast.LENGTH_SHORT).show()
        return
    }
    if (
        payload.mimeType == "application/vnd.android.package-archive" &&
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
        !packageManager.canRequestPackageInstalls()
    ) {
        startActivity(Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:$packageName")
        ))
        return
    }
    AgentRuntimeArtifactUi.contentUri(this, payload).fold(
        onSuccess = { uri ->
            runCatching {
                startActivity(Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, payload.mimeType)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                })
            }.onFailure {
                Toast.makeText(this, R.string.agent_runtime_artifact_unavailable, Toast.LENGTH_LONG).show()
            }
        },
        onFailure = {
            Toast.makeText(this, R.string.agent_runtime_artifact_unavailable, Toast.LENGTH_LONG).show()
        }
    )
}

internal fun MainActivity.runAgentFailureRecovery(
    entry: AgentTranscriptEntry,
    action: AgentRichAction
) {
    val payload = AgentFailureRecoveryPayload.decode(action.value)
    if (
        payload == null ||
        payload.taskId.isBlank() ||
        payload.taskId != entry.taskId ||
        payload.conversationId != entry.conversationId
    ) {
        Toast.makeText(
            this,
            R.string.agent_recovery_unavailable,
            Toast.LENGTH_SHORT
        ).show()
        return
    }
    val dispatchKey = "${payload.taskId}:${payload.action.wireValue}"
    if (!agentRecoveryActionsInFlight.add(dispatchKey)) {
        Toast.makeText(
            this,
            R.string.agent_recovery_already_started,
            Toast.LENGTH_SHORT
        ).show()
        return
    }
    while (agentRecoveryActionsInFlight.size > 200) {
        agentRecoveryActionsInFlight.firstOrNull()?.let(agentRecoveryActionsInFlight::remove)
    }
    if (agentTranscriptStore.activeConversation().id != payload.conversationId) {
        openAgentConversation(payload.conversationId)
    }
    val chinese = LanguagePolicySettings.resolvedResponseLanguage(this)
        .startsWith("zh", ignoreCase = true)
    val instruction = AgentFailureRecoveryPolicy.instruction(payload, chinese)
    val turnId = UUID.randomUUID().toString()
    val displayText = when (payload.action) {
        AgentFailureRecoveryAction.RETRY -> getString(R.string.agent_recovery_retry)
        AgentFailureRecoveryAction.SWITCH_AGENT -> getString(R.string.agent_recovery_switch_agent)
        AgentFailureRecoveryAction.DEGRADE -> getString(R.string.agent_recovery_degrade)
        AgentFailureRecoveryAction.DIAGNOSTICS -> getString(R.string.agent_recovery_diagnostics)
    }
    val forcedAction = agentFailureRecoveryConnectorAction(payload, instruction, turnId)
    agentTurnGoals[turnId] = instruction
    agentSubmissionExecutor.execute {
        agentTranscriptStore.append(
            role = AgentTranscriptRole.USER,
            text = displayText,
            conversationId = payload.conversationId,
            turnId = turnId,
            taskId = turnId
        )
        runOnUiThread {
            if (isFinishing || isDestroyed) return@runOnUiThread
            deleteAgentTranscriptByDedupeKey(
                payload.conversationId,
                agentFailureRecoveryDedupeKey(payload.taskId)
            )
            refreshAgentConversationHeader()
            refreshAgentTranscriptWindow(payload.conversationId)
            continueAgentGoalSubmission(
                goal = instruction,
                conversationId = payload.conversationId,
                turnId = turnId,
                forcedAction = forcedAction,
                originalGoal = instruction,
                executionModeOverride = AgentFailureRecoveryPolicy.executionMode(
                    payload.action
                )
            )
        }
    }
}

internal fun MainActivity.agentFailureRecoveryConnectorAction(
    payload: AgentFailureRecoveryPayload,
    prompt: String,
    turnId: String
): AgentAction? {
    val targets = AppStoreAgentConnectorRegistry(this).availableTargets()
        .filter { it.status == AgentConnectorStatus.AVAILABLE }
    fun canonical(value: String): String = value
        .substringAfterLast(':')
        .lowercase(Locale.ROOT)
        .replace("-", "")
    val current = canonical(payload.agentId)
    val target = when (payload.action) {
        AgentFailureRecoveryAction.SWITCH_AGENT -> targets.firstOrNull {
            canonical(it.id) != current
        }
        AgentFailureRecoveryAction.RETRY,
        AgentFailureRecoveryAction.DEGRADE,
        AgentFailureRecoveryAction.DIAGNOSTICS -> targets.firstOrNull {
            canonical(it.id) == current
        }
    } ?: return null
    return AgentAction(
        id = "recovery-${payload.action.wireValue}-$turnId",
        kind = AgentActionKind.CALL_CONNECTOR,
        target = target.title,
        risk = AgentRisk.LOW,
        status = AgentActionStatus.PENDING_CONFIRMATION,
        description = "Continue a failed task with ${target.title}",
        parameters = mapOf(
            "connector_id" to target.id,
            "prompt" to prompt,
            "recovery_of_task_id" to payload.taskId,
            "recovery_action" to payload.action.wireValue
        ),
        requiresConfirmation = false
    )
}

internal fun MainActivity.previewRuntimeArtifact(rawPayload: String) {
    val payload = AgentRuntimeArtifactActionPayload.decode(rawPayload)
    if (payload == null) {
        Toast.makeText(this, R.string.agent_runtime_artifact_unavailable, Toast.LENGTH_SHORT).show()
        return
    }
    thread(name = "signalasi-artifact-preview") {
        val resolved = AgentRuntimeArtifactUi.resolve(this, payload)
        val preview = resolved.mapCatching { file -> AgentRuntimeArtifactUi.preview(file).getOrThrow() }
        runOnUiThread {
            preview.fold(
                onSuccess = { source -> showRuntimeArtifactPreview(payload, source) },
                onFailure = {
                    Toast.makeText(this, R.string.agent_runtime_artifact_unavailable, Toast.LENGTH_LONG).show()
                }
            )
        }
    }
}

internal fun MainActivity.showRuntimeArtifactPreview(payload: AgentRuntimeArtifactActionPayload, source: String) {
    val content = TextView(this).apply {
        text = source
        textSize = 13.5f
        typeface = android.graphics.Typeface.MONOSPACE
        setTextColor(getColorCompat(R.color.text_primary))
        setTextIsSelectable(true)
        setPadding(dp(16), dp(12), dp(16), dp(18))
    }
    val viewport = ScrollView(this).apply {
        isFillViewport = true
        addView(HorizontalScrollView(this@showRuntimeArtifactPreview).apply {
            isHorizontalScrollBarEnabled = true
            addView(content, ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ))
        })
    }
    val dialog = AlertDialog.Builder(this)
        .setTitle(payload.displayName)
        .setView(viewport)
        .setNegativeButton(R.string.common_close, null)
        .setNeutralButton(R.string.common_copy) { _, _ ->
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            clipboard.setPrimaryClip(ClipData.newPlainText(payload.displayName, source))
            Toast.makeText(this, R.string.toast_copied, Toast.LENGTH_SHORT).show()
        }
        .setPositiveButton(R.string.common_save) { _, _ -> saveRuntimeArtifact(payload.encode()) }
        .create()
    dialog.setOnShowListener {
        dialog.window?.setLayout((resources.displayMetrics.widthPixels * 0.94f).toInt(), (resources.displayMetrics.heightPixels * 0.82f).toInt())
    }
    dialog.show()
}

internal fun MainActivity.saveRuntimeArtifact(rawPayload: String) {
    val payload = AgentRuntimeArtifactActionPayload.decode(rawPayload)
    if (payload == null) {
        Toast.makeText(this, R.string.agent_runtime_artifact_unavailable, Toast.LENGTH_SHORT).show()
        return
    }
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
        pendingRuntimeArtifactExport = payload
        startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = payload.mimeType
            putExtra(Intent.EXTRA_TITLE, payload.displayName)
        }, REQUEST_EXPORT_RUNTIME_ARTIFACT)
        return
    }
    thread(name = "signalasi-artifact-save") {
        val result = AgentRuntimeArtifactUi.resolve(this, payload).mapCatching { source ->
            AgentRuntimeArtifactExporter(this).saveToDownloads(source, payload).getOrThrow()
        }
        runOnUiThread {
            result.fold(
                onSuccess = { path ->
                    Toast.makeText(this, getString(R.string.agent_runtime_artifact_saved, path), Toast.LENGTH_LONG).show()
                },
                onFailure = {
                    Toast.makeText(this, R.string.agent_runtime_artifact_save_failed, Toast.LENGTH_LONG).show()
                }
            )
        }
    }
}

internal fun MainActivity.exportRuntimeArtifactToUri(payload: AgentRuntimeArtifactActionPayload, destination: Uri) {
    thread(name = "signalasi-artifact-export") {
        val result = AgentRuntimeArtifactUi.resolve(this, payload).mapCatching { source ->
            AgentRuntimeArtifactExporter(this).copyToUri(source, destination).getOrThrow()
        }
        runOnUiThread {
            Toast.makeText(
                this,
                if (result.isSuccess) R.string.agent_runtime_artifact_saved_picker else R.string.agent_runtime_artifact_save_failed,
                Toast.LENGTH_LONG
            ).show()
        }
    }
}

internal fun MainActivity.handleAgentRichForm(
    entry: AgentTranscriptEntry,
    block: AgentRichBlock,
    values: Map<String, String>
) {
    val response = JSONObject().apply {
        put("form_id", block.id)
        put("task_id", entry.taskId)
        put("values", JSONObject(values))
    }
    setAgentRichInput("${block.title.ifBlank { "Form response" }}: $response", submit = true)
}

internal fun MainActivity.setAgentRichInput(value: String, submit: Boolean) {
    if (value.isBlank()) return
    agentGoalInput.setText(value)
    agentGoalInput.setSelection(agentGoalInput.text?.length ?: 0)
    if (submit) submitAgentGoal() else {
        agentGoalInput.requestFocus()
        getSystemService(InputMethodManager::class.java)
            .showSoftInput(agentGoalInput, InputMethodManager.SHOW_IMPLICIT)
    }
}

internal fun MainActivity.runAgentRichTaskDecision(
    entry: AgentTranscriptEntry,
    action: AgentRichAction
) {
    val choice = AgentPermissionChoice.fromWireValue(action.value)
    if (choice == null) {
        Toast.makeText(this, R.string.agent_remote_approval_invalid, Toast.LENGTH_LONG).show()
        return
    }
    val runtimes = buildList {
        addAll(activeAgentTasks.values)
        addAll(provisionalAgentTasks)
        add(mobileNativeAgent)
    }.distinct()
    val runtime = runtimes.firstOrNull { it.snapshot().sessionId == entry.taskId }
    if (runtime == null) {
        Toast.makeText(this, getString(R.string.agent_task_detail_unavailable), Toast.LENGTH_SHORT).show()
        return
    }
    if (agentTranscriptStore.deleteEntry(entry.id)) {
        agentTranscriptWindow.remove(entry.id)
    }
    clearAgentTranscriptRows()
    refreshAgentTranscriptWindow(entry.conversationId)
    thread(name = "signalasi-rich-decision") {
        bindAgentExecutionLoop(runtime, entry.turnId)
        var state = runtime.approveNextAction(
            highRiskConfirmed = true,
            permissionChoice = choice
        )
        if (entry.turnId.isNotBlank()) {
            state = finalizeAgentExecutionLoop(runtime, entry.turnId, state)
            persistAgentWorkspaceSnapshot(entry.turnId, state, runtime)
        }
        runOnUiThread { renderAgentState(state, entry.conversationId, entry.turnId) }
    }
}

internal fun MainActivity.runRemoteAgentTaskDecision(
    entry: AgentTranscriptEntry,
    action: AgentRichAction
) {
    val encodedDecision = AgentRemoteApprovalDecision.decode(action.value)
    val decision = encodedDecision?.takeIf {
        it.taskId == entry.taskId &&
            entry.dedupeKey == "remote-approval:${it.taskId}:${it.approvalId}"
    }
    if (decision == null) {
        Toast.makeText(this, R.string.agent_remote_approval_invalid, Toast.LENGTH_LONG).show()
        return
    }
    val operationKey = "${decision.taskId}:${decision.approvalId}:${decision.actionHash}"
    if (!remoteAgentApprovalsInFlight.add(operationKey)) {
        Toast.makeText(this, R.string.agent_remote_approval_pending, Toast.LENGTH_SHORT).show()
        return
    }
    val published = SignalASIMqttClient.publishAgentTaskApproval(
        decision = decision,
        topicOverride = AppStore.outgoingTopicForContact(this, decision.contactId)
    )
    if (!published) {
        remoteAgentApprovalsInFlight.remove(operationKey)
        Toast.makeText(this, R.string.agent_remote_approval_send_failed, Toast.LENGTH_LONG).show()
        return
    }
    Toast.makeText(this, R.string.agent_remote_approval_sent, Toast.LENGTH_SHORT).show()
}

internal fun MainActivity.agentExecutionLine(state: AgentUiState, entry: AgentAuditEntry): String? {
    val route = state.plan?.route?.targetTitle
        .orEmpty()
        .ifBlank { state.plan?.selectedAgentOrModel.orEmpty() }
        .ifBlank { getString(R.string.agent_output_on_device) }
    val phoneNativePlan = state.plan?.actions?.any { it.kind == AgentActionKind.CALL_NATIVE_TOOL } == true
    return when (entry.event) {
        AgentAuditEvent.REASONING_SUMMARY -> when {
            auditDetailValue(entry.detail, "summary_key") == "phone_development_repair" ->
                getString(R.string.agent_trace_phone_development_repair)
            else -> auditDetailValue(entry.detail, "summary")
                .ifBlank { getString(R.string.agent_trace_reasoning_summary, route) }
        }
        AgentAuditEvent.TOOL_STARTED -> getString(
            if (auditDetailValue(entry.detail, "planning_only") == "true") {
                R.string.agent_trace_model_planning
            } else if (auditDetailValue(entry.detail, "command").isNotBlank()) {
                R.string.agent_trace_phone_linux_command
            } else {
                R.string.agent_trace_tool_started
            },
            auditDetailValue(entry.detail, "command").ifBlank {
                agentTraceTargetLabel(auditDetailValue(entry.detail, "target").ifBlank { route })
            }
        )
        AgentAuditEvent.TOOL_COMPLETED -> {
            val actionId = auditDetailValue(entry.detail, "action")
            val actionKind = auditDetailValue(entry.detail, "kind")
                .takeIf(String::isNotBlank)
                ?.let { value -> runCatching { AgentActionKind.valueOf(value) }.getOrNull() }
                ?: state.plan?.actions?.firstOrNull { it.id == actionId }?.kind
            val awaitingResponse = when (auditDetailValue(entry.detail, "awaiting_response")) {
                "true" -> true
                "false" -> false
                else -> null
            }
            val target = agentTraceTargetLabel(
                auditDetailValue(entry.detail, "target").ifBlank { route }
            )
            val duration = auditDetailValue(entry.detail, "duration_ms").toLongOrNull() ?: 0L
            val succeeded = auditDetailValue(entry.detail, "success") == "true"
            if (!AgentTranscriptPresentationPolicy.shouldRenderToolCompletion(
                    actionKind = actionKind,
                    succeeded = succeeded,
                    awaitingResponse = awaitingResponse
                )
            ) {
                return null
            }
            getString(
                if (succeeded) R.string.agent_trace_tool_completed else R.string.agent_trace_tool_failed,
                target,
                agentTraceDuration(duration)
            )
        }
        AgentAuditEvent.PLAN_REPLANNED,
        AgentAuditEvent.PLAN_EDITED -> getString(R.string.agent_trace_plan_updated)
        AgentAuditEvent.TOOL_OUTPUT_HANDOFF -> getString(R.string.agent_trace_tool_result_ready)
        AgentAuditEvent.ACTION_RECOVERY_STARTED ->
            if (phoneNativePlan) null else getString(R.string.agent_trace_recovery_started)
        AgentAuditEvent.ACTION_RECOVERY_COMPLETED ->
            if (phoneNativePlan) null else getString(R.string.agent_trace_recovery_completed)
        AgentAuditEvent.ACTION_RECOVERY_MANUAL_REQUIRED ->
            if (phoneNativePlan) null else getString(R.string.agent_trace_recovery_manual)
        AgentAuditEvent.CONNECTOR_RESPONSE_RECEIVED -> null
        AgentAuditEvent.ACTION_EXECUTED -> when {
            entry.detail.contains("FAILED", ignoreCase = true) && phoneNativePlan -> null
            entry.detail.contains("FAILED", ignoreCase = true) -> getString(R.string.agent_trace_request_failed, route)
            else -> null
        }
        AgentAuditEvent.ACTION_BLOCKED -> if (
            entry.detail.startsWith("secondary_confirmation_required:")
        ) {
            null
        } else {
            getString(R.string.agent_trace_action_blocked)
        }
        AgentAuditEvent.TASK_PAUSED -> getString(R.string.agent_trace_task_paused)
        AgentAuditEvent.TASK_RESUMED -> getString(R.string.agent_trace_task_resumed)
        AgentAuditEvent.TASK_INTERRUPTED -> getString(R.string.agent_trace_task_interrupted)
        else -> null
    }
}

internal fun MainActivity.agentExecutionLoopTimelineText(label: AgentExecutionLoopTimelineLabel): String =
    getString(when (label) {
        AgentExecutionLoopTimelineLabel.PLAN -> R.string.agent_loop_timeline_plan
        AgentExecutionLoopTimelineLabel.ACT -> R.string.agent_loop_timeline_act
        AgentExecutionLoopTimelineLabel.OBSERVE -> R.string.agent_loop_timeline_observe
        AgentExecutionLoopTimelineLabel.REPLAN -> R.string.agent_loop_timeline_replan
        AgentExecutionLoopTimelineLabel.VERIFY -> R.string.agent_loop_timeline_verify
        AgentExecutionLoopTimelineLabel.FINALIZE -> R.string.agent_loop_timeline_finalize
        AgentExecutionLoopTimelineLabel.LEARN -> R.string.agent_loop_timeline_learn
        AgentExecutionLoopTimelineLabel.WAITING_CONFIRMATION ->
            R.string.agent_loop_timeline_waiting_confirmation
        AgentExecutionLoopTimelineLabel.WAITING_RESPONSE ->
            R.string.agent_loop_timeline_waiting_response
        AgentExecutionLoopTimelineLabel.PAUSED -> R.string.agent_loop_timeline_paused
        AgentExecutionLoopTimelineLabel.BLOCKED -> R.string.agent_loop_timeline_blocked
        AgentExecutionLoopTimelineLabel.FAILED -> R.string.agent_loop_timeline_failed
        AgentExecutionLoopTimelineLabel.CANCELLED -> R.string.agent_loop_timeline_cancelled
    })

internal fun MainActivity.auditDetailValue(detail: String, key: String): String = detail
    .split(';')
    .asSequence()
    .map(String::trim)
    .firstOrNull { it.startsWith("$key=") }
    ?.substringAfter('=')
    .orEmpty()

internal fun MainActivity.agentTraceDuration(durationMillis: Long): String =
    AgentTranscriptPresentationPolicy.formatElapsedSeconds(durationMillis)

internal fun MainActivity.agentProcessCompletionTimestamp(
    entry: AgentTranscriptEntry,
    entries: List<AgentTranscriptEntry> = agentTranscriptStore.list(entry.conversationId)
): Long? {
    agentExecutionPresentations[entry.taskId]
        ?.takeIf { presentation ->
            !presentation.cancellable &&
                !AgentExecutionPresentationPolicy.isCancellable(presentation.phase)
        }
        ?.completedAtMillis
        ?.takeIf { it > 0L }
        ?.let { return it.coerceAtLeast(entry.timestampMillis) }
    val assistantTimestamp = entries.asSequence()
        .filter { candidate ->
            candidate.role == AgentTranscriptRole.ASSISTANT &&
                !isAgentApprovalEntry(candidate) &&
                when {
                    entry.turnId.isNotBlank() -> candidate.turnId == entry.turnId
                    entry.taskId.isNotBlank() -> candidate.taskId == entry.taskId
                    else -> candidate.timestampMillis >= entry.timestampMillis
                }
        }
        .maxOfOrNull(AgentTranscriptEntry::timestampMillis)
    if (assistantTimestamp != null) return assistantTimestamp

    val workspaceId = entry.turnId.trim()
    if (workspaceId.isBlank()) return null
    val cached = agentProcessCompletionLookups[workspaceId]
    cached?.completedAtMillis?.let { return it.coerceAtLeast(entry.timestampMillis) }
    val cacheFresh = cached != null &&
        SystemClock.elapsedRealtime() - cached.checkedAtElapsedRealtime <
        AGENT_PROCESS_COMPLETION_LOOKUP_RETRY_MS
    if (!cacheFresh) scheduleAgentProcessCompletionLookup(entry, workspaceId)
    return null
}

private fun MainActivity.scheduleAgentProcessCompletionLookup(
    entry: AgentTranscriptEntry,
    workspaceId: String
) {
    if (!agentProcessCompletionLookupInFlight.add(workspaceId)) return
    agentTranscriptContentExecutor.execute {
        val completedAtMillis = runCatching {
            EncryptedAgentWorkspaceStore(this).find(workspaceId)
                ?.takeIf { AgentTranscriptPresentationPolicy.processClockStopsFor(it.status) }
                ?.updatedAtMillis
                ?.takeIf { it > 0L }
        }.getOrNull()
        agentProcessCompletionLookups[workspaceId] = AgentProcessCompletionLookup(
            completedAtMillis = completedAtMillis,
            checkedAtElapsedRealtime = SystemClock.elapsedRealtime()
        )
        agentProcessCompletionLookupInFlight.remove(workspaceId)
        runOnUiThread {
            if (isFinishing || isDestroyed || !isAgentTranscriptAdapterInitialized()) {
                return@runOnUiThread
            }
            agentTranscriptAdapter.indexOfEntry(entry.id)
                .takeIf { it >= 0 }
                ?.let(agentTranscriptAdapter::notifyItemChanged)
        }
    }
}

internal fun MainActivity.agentTraceTargetLabel(target: String): String {
    val normalized = target.lowercase(Locale.US)
    return when {
        normalized == "codex" || normalized == "codex agent" ->
            connectorAgentDisplayName("codex", "Codex")
        "on-device linux" in normalized || "phone linux" in normalized ->
            getString(R.string.agent_trace_phone_linux)
        "runtime package manager" in normalized ->
            getString(R.string.agent_trace_runtime_package_manager)
        else -> target
    }
}

internal fun MainActivity.connectorAgentDisplayName(agentId: String, fallbackName: String): String {
    val contacts = AppStore.contacts(this)
    for (index in 0 until contacts.length()) {
        val contact = contacts.optJSONObject(index) ?: continue
        if (!contact.optString("agent_id").equals(agentId, ignoreCase = true)) continue
        val desktopName = contact.optString("desktop_name").trim()
        if (desktopName.isNotBlank()) return "$fallbackName \u00b7 $desktopName"
        return contact.optString("name").trim().ifBlank { fallbackName }
    }
    return fallbackName
}

internal fun MainActivity.localizedAgentProcessText(value: String): String {
    val replacements = listOf(
        "Execute in the on-device Linux sandbox",
        "Run and verify in the phone's on-device Linux runtime",
        "Run and verify in the phone\u2019s on-device Linux runtime"
    )
    return replacements.fold(value) { rendered, internalTitle ->
        rendered.replace(
            oldValue = internalTitle,
            newValue = getString(R.string.agent_trace_phone_linux_verify),
            ignoreCase = true
        )
    }
}

internal fun MainActivity.localizedAgentAssistantText(value: String): String = when (
    AgentTranscriptPresentationPolicy.controlMessageKind(value)
) {
    AgentTranscriptPresentationPolicy.ControlMessageKind.CANCELLED ->
        getString(R.string.agent_loop_timeline_cancelled)
    null -> value
}

internal fun MainActivity.renderAgentToolbox(state: AgentUiState) {
    agentToolboxList.removeAllViews()
    val tools = state.runtimeContext.systemTools.take(6)
    if (tools.isEmpty()) {
        agentToolboxList.addView(agentToolboxEmptyRow())
        return
    }
    tools.forEachIndexed { index, tool ->
        agentToolboxList.addView(agentToolboxRow(tool, index))
    }
}

internal fun MainActivity.renderAgentRecentTasks(state: AgentUiState) {
    agentRecentTaskList.removeAllViews()
    if (state.recentTasks.isEmpty()) {
        agentRecentTaskList.addView(agentRecentEmptyRow())
        return
    }
    state.recentTasks.forEachIndexed { index, task ->
        agentRecentTaskList.addView(agentRecentTaskRow(task, index))
    }
}
