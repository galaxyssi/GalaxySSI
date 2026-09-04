package com.galaxyssi.chat

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
import com.galaxyssi.chat.GalaxySSIMqttClient.Listener
import com.galaxyssi.chat.ui.AgentComposerUiPolicy
import com.galaxyssi.chat.ui.AppleHoldToTalkController
import com.galaxyssi.chat.ui.VoiceWaveformView
import com.galaxyssi.chat.voice.TranscriptHypothesis
import com.galaxyssi.chat.voice.VoiceFailure
import com.galaxyssi.chat.voice.VoiceFeatureFlags
import com.galaxyssi.chat.voice.VoiceInteractionCommand
import com.galaxyssi.chat.voice.VoiceInteractionCoordinator
import com.galaxyssi.chat.voice.VoiceInteractionCoordinatorRegistry
import com.galaxyssi.chat.voice.VoiceInteractionEvent
import com.galaxyssi.chat.voice.VoiceInteractionPhase
import com.galaxyssi.chat.voice.VoiceRouteDecision
import com.galaxyssi.chat.voice.VoiceRouteKind
import com.galaxyssi.chat.voice.VoiceSessionConfig
import com.galaxyssi.chat.voice.VoiceTtsRequest
import com.galaxyssi.chat.voice.VoiceTtsRequestRegistry
import com.galaxyssi.chat.voice.audio.AdaptiveEndpointConfig
import com.galaxyssi.chat.voice.audio.AndroidPcmRecorder
import com.galaxyssi.chat.voice.audio.DirectPcmFramePacket
import com.galaxyssi.chat.voice.audio.EndpointReason
import com.galaxyssi.chat.voice.audio.PcmCaptureConfig
import com.galaxyssi.chat.voice.audio.PcmSnapshot
import com.galaxyssi.chat.voice.audio.PcmStopReason
import com.galaxyssi.chat.voice.audio.PcmWaveFileAdapter
import com.galaxyssi.chat.voice.audio.VadDecision
import com.galaxyssi.chat.voice.audio.VoiceAudioHub
import com.galaxyssi.chat.voice.audio.VoiceAudioHubListener
import com.galaxyssi.chat.voice.asr.AsrNetworkType
import com.galaxyssi.chat.voice.asr.AsrProviderSelector
import com.galaxyssi.chat.voice.asr.AsrSessionConfig
import com.galaxyssi.chat.voice.asr.VoiceRecognitionPreference
import com.galaxyssi.chat.voice.asr.online.CachingRealtimeAsrCredentialSource
import com.galaxyssi.chat.voice.asr.online.HttpRealtimeAsrCredentialSource
import com.galaxyssi.chat.voice.asr.online.OnlineAsrCompletion
import com.galaxyssi.chat.voice.asr.online.OnlineRealtimeAsrTurn
import com.galaxyssi.chat.voice.asr.online.RealtimeAsrPreconnector
import com.galaxyssi.chat.voice.asr.online.RealtimeAsrProvider
import com.galaxyssi.chat.voice.asr.online.RealtimeAsrTurnAction
import com.galaxyssi.chat.voice.asr.remote.RemoteWhisperNodeClient
import com.galaxyssi.chat.voice.asr.remote.RemoteWhisperNodeRegistry
import com.galaxyssi.chat.voice.asr.remote.RemoteWhisperRoutingPolicy
import com.galaxyssi.chat.voice.asr.remote.GalaxySSILinkRemoteWhisperTransport
import com.galaxyssi.chat.voice.asr.local.AbortReason
import com.galaxyssi.chat.voice.asr.local.AsrConfig as HighAccuracyAsrConfig
import com.galaxyssi.chat.voice.asr.local.AsrEvent as HighAccuracyAsrEvent
import com.galaxyssi.chat.voice.asr.local.AsrPerformanceMode
import com.galaxyssi.chat.voice.asr.local.DefaultWhisperDecodeScheduler
import com.galaxyssi.chat.voice.asr.local.HighAccuracyAsrResult
import com.galaxyssi.chat.voice.asr.local.AsrTranscriptCompletenessPolicy
import com.galaxyssi.chat.voice.asr.local.HighAccuracyLocalAsrController
import com.galaxyssi.chat.voice.asr.local.HighAccuracyLocalAsrTurn
import com.galaxyssi.chat.voice.asr.local.LiveWhisperTranscriptionSession
import com.galaxyssi.chat.voice.asr.local.LiveWhisperTranscriptUpdate
import com.galaxyssi.chat.voice.asr.local.NativeWhisperCode
import com.galaxyssi.chat.voice.asr.local.LargeTurboQnnModelAction
import com.galaxyssi.chat.voice.asr.local.LargeTurboQnnModelManager
import com.galaxyssi.chat.voice.asr.local.LargeTurboQnnModelStatus
import com.galaxyssi.chat.voice.asr.local.QnnAsrEligibility
import com.galaxyssi.chat.voice.asr.local.QnnModelDownloadNetworkPolicy
import com.galaxyssi.chat.voice.asr.local.QnnWhisperPackageManager
import com.galaxyssi.chat.voice.asr.local.QnnWhisperPackageStatus
import com.galaxyssi.chat.voice.asr.local.WhisperDecodeScheduler
import com.galaxyssi.chat.voice.asr.local.largeTurboQnnModelAction
import com.galaxyssi.chat.voice.benchmark.WhisperBenchmarkManager
import com.galaxyssi.chat.voice.benchmark.WhisperBenchmarkDeferredException
import com.galaxyssi.chat.voice.benchmark.WhisperBenchmarkProgress
import com.galaxyssi.chat.voice.benchmark.WhisperBenchmarkRecord
import com.galaxyssi.chat.voice.benchmark.WhisperBenchmarkStage
import com.galaxyssi.chat.voice.benchmark.WhisperProviderChoice
import com.galaxyssi.chat.voice.benchmark.WhisperUserVoiceMode
import com.galaxyssi.chat.voice.correction.AndroidVoiceExecutionRecordStore
import com.galaxyssi.chat.voice.correction.CorrectionDecision
import com.galaxyssi.chat.voice.correction.DefaultVoiceCommandRiskClassifier
import com.galaxyssi.chat.voice.correction.TranscriptDiff
import com.galaxyssi.chat.voice.correction.VoiceCommandRisk
import com.galaxyssi.chat.voice.correction.VoiceCorrectionContextRecord
import com.galaxyssi.chat.voice.correction.VoiceCorrectionJournal
import com.galaxyssi.chat.voice.correction.VoiceExecutionLedger
import com.galaxyssi.chat.voice.correction.VoiceEntityType
import com.galaxyssi.chat.voice.correction.VoiceSecondPassCoordinator
import com.galaxyssi.chat.voice.correction.VoiceSecondPassRequest
import com.galaxyssi.chat.voice.correction.VoiceSecondPassResult
import com.galaxyssi.chat.voice.correction.VoiceSecondPassTriggerPolicy
import com.galaxyssi.chat.voice.audio.VoiceAudioSession
import com.galaxyssi.chat.voice.audio.VoiceAudioSessionConfig
import com.galaxyssi.chat.voice.agent.VoiceAgentEvent
import com.galaxyssi.chat.voice.agent.VoiceAgentRunBridge
import com.galaxyssi.chat.voice.agent.VoiceAgentRunListener
import com.galaxyssi.chat.voice.agent.VoiceAgentRunSnapshot
import com.galaxyssi.chat.voice.agent.VoiceAgentRunState
import com.galaxyssi.chat.voice.agent.VoiceAgentRunUpdate
import com.galaxyssi.chat.voice.metrics.VoiceLatencyTelemetry
import com.galaxyssi.chat.voice.metrics.VoiceLatencyTraceContext
import com.galaxyssi.chat.voice.metrics.VoiceTraceEvents
import com.galaxyssi.chat.voice.model.WhisperExecutionMode
import com.galaxyssi.chat.voice.model.WhisperCertificationLevel
import com.galaxyssi.chat.voice.model.WhisperMemoryAdmissionPolicy
import com.galaxyssi.chat.voice.model.WhisperModelFamily
import com.galaxyssi.chat.voice.model.WhisperModelFallbackPolicy
import com.galaxyssi.chat.voice.reliability.AndroidVoiceReliabilityController
import com.galaxyssi.chat.voice.reliability.VoicePipelineFeature
import com.galaxyssi.chat.voice.reliability.VoicePerformanceHealth
import com.galaxyssi.chat.voice.reliability.VoiceResourceMode
import com.galaxyssi.chat.voice.reliability.VoiceWorkloadProfile
import com.galaxyssi.chat.voice.modelstream.ModelStreamCancelReason
import com.galaxyssi.chat.voice.modelstream.CommittedSpeechChunk
import com.galaxyssi.chat.voice.modelstream.DefaultSentenceCommitter
import com.galaxyssi.chat.voice.modelstream.ModelStreamEvent
import com.galaxyssi.chat.voice.modelstream.ModelStreamUiMerger
import com.galaxyssi.chat.voice.modelstream.ModelStreamUiUpdate
import com.galaxyssi.chat.voice.modelstream.ModelUsage
import com.galaxyssi.chat.voice.modelstream.SentenceCommitter
import com.galaxyssi.chat.voice.tts.BargeInActions
import com.galaxyssi.chat.voice.tts.BargeInController
import com.galaxyssi.chat.voice.tts.BargeInTaskKind
import com.galaxyssi.chat.voice.tts.ProgressiveTtsUtteranceRegistry
import com.galaxyssi.chat.voice.tts.ProgressiveTtsUtteranceRequest
import com.galaxyssi.chat.voice.tts.TtsCancelReason
import com.galaxyssi.chat.voice.tts.TtsChunkPlayback
import com.galaxyssi.chat.voice.tts.TtsChunkPlaybackCallbacks
import com.galaxyssi.chat.voice.tts.TtsChunkPlayer
import com.galaxyssi.chat.voice.tts.TtsChunkScheduler
import com.galaxyssi.chat.voice.tts.TtsChunkSchedulerCallbacks
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

internal const val REQUEST_IMAGE = 2001
internal const val REQUEST_RECORD_AUDIO = 2002
internal const val REQUEST_IMPORT_BACKUP = 2003
internal const val REQUEST_EXPORT_BACKUP = 2004
internal const val REQUEST_PICK_AVATAR = 2005
internal const val REQUEST_IMPORT_KNOWLEDGE = 2006
internal const val REQUEST_AGENT_SCREEN_CAPTURE = 2007
internal const val REQUEST_AGENT_CAMERA = 2008
internal const val REQUEST_AGENT_CAMERA_PERMISSION = 2009
internal const val REQUEST_AGENT_NATIVE_PERMISSIONS = 2010
internal const val REQUEST_AGENT_NOTIFICATIONS = 2011
internal const val REQUEST_IMPORT_SKILL = 2012
internal const val REQUEST_EXPORT_SKILL = 2013
internal const val REQUEST_AGENT_ATTACHMENTS = 2014
internal const val REQUEST_AGENT_IMAGES = 2015
internal const val REQUEST_CONTROL_CENTER_PERMISSION = 2016
internal const val REQUEST_IMPORT_MCP_PACKAGE = 2017
internal const val REQUEST_IMPORT_RUNTIME_PACK = 2018
internal const val REQUEST_EXPORT_RUNTIME_ARTIFACT = 2019
internal const val REQUEST_IMPORT_LOCAL_QNN_PACKAGE = 2020
internal const val REQUEST_CHAT_CAMERA = 2021
internal const val REQUEST_CHAT_CAMERA_PERMISSION = 2022
internal const val REQUEST_OBSIDIAN_VAULT = 2023
internal const val INITIAL_VISIBLE_AGENT_TRANSCRIPT_ITEMS = 24
internal const val AGENT_PROCESS_COMPLETION_LOOKUP_RETRY_MS = 10_000L
internal const val AGENT_TRANSCRIPT_PAGE_ITEMS = 24
internal const val MAX_EXPANDED_AGENT_TRANSCRIPT_ENTRIES = 8
internal const val MAX_AGENT_RESPONSE_SECTION_STATES = 512
internal const val MAX_PENDING_AGENT_REPLY_INDICATORS = 256
internal const val CHAT_HISTORY_PAGE_ITEMS = 100
internal const val CHAT_HISTORY_WINDOW_ITEMS = 600
internal const val CHAT_HISTORY_PREFETCH_POSITION = 2
internal const val AGENT_PROCESS_TIMER_TICK_MS = 1_000L
internal const val CLOUD_STREAM_UI_INTERVAL_MS = 80L
internal const val AGENT_CONNECTOR_STREAM_UI_INTERVAL_MS = 250L
internal const val AGENT_TRANSCRIPT_PERF_LOG_THRESHOLD_MS = 16L
internal const val UNROUTABLE_CONNECTOR_GRACE_MILLIS = 5L * 60L * 1_000L
internal const val GLOBAL_AGENT_FOREGROUND_RETRY_MILLIS = 5_000L
internal const val AGENT_BRAND_LOGO_BASE_DP = 39
internal const val AGENT_BRAND_LOGO_MIN_DP = 32
internal const val AGENT_BRAND_LOGO_MAX_DP = 56
internal const val EXTRA_REOPEN_CONTROL_CENTER_CHILD = "galaxyssi_reopen_control_center_child"
internal const val CONTROL_CENTER_CHILD_TEXT_SIZE = "text_size"
internal const val CAPABILITY_KIND_NATIVE_TOOL = "native_tool"
internal const val CAPABILITY_KIND_MCP = "mcp"
internal const val CAPABILITY_KIND_AUTOMATION = "automation"
internal const val MAX_AGENT_ATTACHMENTS = 10
internal const val MAX_AGENT_ATTACHMENT_BYTES = 20L * 1024L * 1024L
internal const val MAX_CONNECTOR_PROGRESS_TEXT_CHARACTERS = 2_000
internal const val MAX_CONNECTOR_PROGRESS_DETAIL_CHARACTERS = 240
internal const val AGENT_REGISTRY_SYNC_INTERVAL_MILLIS = 5_000L
internal const val AGENT_STARTUP_MAINTENANCE_DELAY_MILLIS = 5_000L
internal const val AGENT_BUSY_MAINTENANCE_RETRY_MILLIS = 30_000L
internal const val VOICE_AGENT_RUN_CARD_COALESCE_MS = 200L
internal const val PEER_VOICE_TRANSCRIPTION_PURPOSE = "peer_voice_transcription"
internal const val MAX_RESTORED_VOICE_AGENT_RUNS = 64
internal const val MAX_VOICE_AGENT_RUN_STEP_CHARACTERS = 240
internal const val CONTROL_CENTER_HOME_CACHE_MILLIS = 30_000L
internal const val FAST_NAVIGATION_CONTENT_DELAY_MILLIS = 48L
internal const val NAVIGATION_CONTENT_PREWARM_DELAY_MILLIS = 1_200L
internal const val UI_PREFS = "galaxyssi_ui_preferences"
internal const val DEBUG_AGENT_PREFS = "galaxyssi_debug_agent"
internal const val PAGE_VOICE = "page_voice"
internal const val PAGE_AGENT = "page_agent"
internal const val PAGE_DISCOVER = "page_discover"
internal const val PAGE_SETTINGS = "page_settings"
internal const val TAB_DISCOVER = "\u53d1\u73b0"
internal const val TAB_SETTINGS = "\u8bbe\u7f6e"
internal val CONTACT_HERMES = Contact("hermes", "Hermes Agent", "")
internal val CONTACT_SYSTEM = Contact("system", "\u7cfb\u7edf\u901a\u77e5", "")
internal val CONTACT_ME = Contact("me", "\u6211", "")
internal val CONTACT_PC = Contact("pc_agent", "PC Agent", "")
internal val CONTACT_HOME = Contact("home_hub", "Home Hub", "")
internal val CONTACT_NEWS = Contact("news_agent", "\u65b0\u95fb Agent", "")
internal val CONTACT_AUTOMATION = Contact("automation_center", "\u81ea\u52a8\u5316\u4e2d\u5fc3", "")
internal val CONTACTS = listOf(CONTACT_HERMES, CONTACT_SYSTEM)
internal val CHAT_CONTACTS = listOf(CONTACT_HERMES)
internal val CLOUD_MODEL_PRESETS = listOf(
    CloudModelPreset("OpenAI", "GPT-5.5", "gpt-5.5", "https://api.openai.com/v1/chat/completions", "openai"),
    CloudModelPreset("OpenAI", "GPT-5.4 mini", "gpt-5.4-mini", "https://api.openai.com/v1/chat/completions", "openai"),
    CloudModelPreset("OpenAI", "GPT-5.4 nano", "gpt-5.4-nano", "https://api.openai.com/v1/chat/completions", "openai"),
    CloudModelPreset("OpenAI", "GPT-5", "gpt-5", "https://api.openai.com/v1/chat/completions", "openai"),
    CloudModelPreset("Anthropic", "Claude Opus 4.7", "claude-opus-4-7-latest", "https://api.anthropic.com/v1/messages", "anthropic"),
    CloudModelPreset("Anthropic", "Claude Sonnet 5", "claude-sonnet-5-latest", "https://api.anthropic.com/v1/messages", "anthropic"),
    CloudModelPreset("Anthropic", "Claude Haiku 4.5", "claude-haiku-4-5-latest", "https://api.anthropic.com/v1/messages", "anthropic"),
    CloudModelPreset("Google Gemini", "Gemini 3.5 Flash", "gemini-3.5-flash", "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent", "gemini"),
    CloudModelPreset("Google Gemini", "Gemini 3.1 Pro", "gemini-3.1-pro", "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-pro:generateContent", "gemini"),
    CloudModelPreset("Google Gemini", "Gemini 3.1 Flash Lite", "gemini-3.1-flash-lite", "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent", "gemini"),
    CloudModelPreset("DeepSeek", "deepseek-v4-pro", "deepseek-v4-pro", "https://api.deepseek.com/chat/completions", "openai"),
    CloudModelPreset("DeepSeek", "deepseek-v4-flash", "deepseek-v4-flash", "https://api.deepseek.com/chat/completions", "openai"),
    CloudModelPreset("DeepSeek", "deepseek-v4-flash-vision-exp", "deepseek-v4-flash-vision-exp", "https://api.deepseek.com/chat/completions", "openai"),
    CloudModelPreset("Qwen", "Qwen 3.7 Max", "qwen3.7-max", "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", "openai"),
    CloudModelPreset("Qwen", "Qwen 3.7 Plus", "qwen3.7-plus", "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", "openai"),
    CloudModelPreset("Qwen", "Qwen 3.6 Flash", "qwen3.6-flash", "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", "openai"),
    CloudModelPreset("OpenRouter", "OpenRouter Auto", "openrouter/auto", "https://openrouter.ai/api/v1/chat/completions", "openai"),
    CloudModelPreset("OpenRouter", "OpenAI GPT-5.5 via OpenRouter", "openai/gpt-5.5", "https://openrouter.ai/api/v1/chat/completions", "openai"),
    CloudModelPreset("Custom", "OpenAI Compatible", "model-id", "https://api.example.com/v1/chat/completions", "openai")
)
