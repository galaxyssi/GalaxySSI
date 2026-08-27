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

internal fun MainActivity.showExportBackupDialog() {
    showFeaturePage(getString(R.string.backup_export_title))
    featureContent.addView(featureHeroCard(
        getString(R.string.backup_encrypted_title),
        getString(R.string.backup_encrypted_subtitle),
        R.drawable.ic_import,
        "#14C66A",
        getString(R.string.common_export)
    ))
    addSectionTitle(getString(R.string.backup_password_section))
    val passwordInput = EditText(this).apply {
        setSingleLine(true)
        hint = getString(R.string.backup_password_hint)
        setBackgroundResource(R.drawable.message_input_background)
        setPadding(dp(14), dp(10), dp(14), dp(10))
        textSize = 16f
    }
    featureContent.addView(passwordInput, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(48)).apply {
        bottomMargin = dp(10)
    })
    val includeMessagesCb = CheckBox(this).apply {
        text = getString(R.string.backup_include_messages)
        setTextColor(getColorCompat(R.color.text_primary))
        textSize = 15f
        buttonTintList = android.content.res.ColorStateList.valueOf(getColorCompat(R.color.signalasi_green))
        isChecked = true
    }
    featureContent.addView(includeMessagesCb, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(48)).apply {
        bottomMargin = dp(18)
    })
    featureContent.addView(
        featureRow(
            getString(R.string.backup_include_agent_data),
            getString(R.string.backup_include_agent_data_subtitle),
            R.drawable.ic_agent_node,
            getString(R.string.backup_included)
        ),
        LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
            bottomMargin = dp(18)
        }
    )
    featureContent.addView(TextView(this).apply {
        text = getString(R.string.common_export)
        gravity = Gravity.CENTER
        setTextColor(Color.WHITE)
        textSize = 17f
        background = getDrawable(R.drawable.send_button_background)
        setOnClickListener {
            val pw = passwordInput.text?.toString().orEmpty()
            if (pw.isBlank()) {
                Toast.makeText(this@showExportBackupDialog, getString(R.string.backup_password_required), Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            pendingExportPassword = pw
            pendingExportIncludeMessages = includeMessagesCb.isChecked
            startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/octet-stream"
                putExtra(Intent.EXTRA_TITLE, getString(R.string.backup_export_file_name))
            }, REQUEST_EXPORT_BACKUP)
        }
    }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(46)))
}

internal fun MainActivity.exportBackupToUri(uri: Uri) {
    val password = pendingExportPassword ?: return
    pendingExportPassword = null
    runCatching {
        val file = AppStore.exportBackup(this, password, includeMessages = pendingExportIncludeMessages, includeContacts = true)
        contentResolver.openOutputStream(uri)?.use { out ->
            file.inputStream().use { input -> input.copyTo(out) }
        }
        runOnUiThread { Toast.makeText(this, getString(R.string.backup_export_success), Toast.LENGTH_SHORT).show() }
    }.onFailure {
        runOnUiThread { Toast.makeText(this, getString(R.string.backup_export_failed, it.message ?: ""), Toast.LENGTH_LONG).show() }
    }
}

internal fun MainActivity.openBackupImportPicker() {
    startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
        addCategory(Intent.CATEGORY_OPENABLE)
        type = "*/*"
    }, REQUEST_IMPORT_BACKUP)
}

internal fun MainActivity.importBackupFromUri(uri: Uri) {
    pendingImportUri = uri
    showPasswordFeaturePage(getString(R.string.backup_import_title), getString(R.string.backup_import_subtitle), getString(R.string.common_import)) { password ->
        importBackupWithPassword(uri, password)
    }
}

internal fun MainActivity.showBackupImportPasswordPreview() {
    showPasswordFeaturePage(getString(R.string.backup_import_title), getString(R.string.backup_import_subtitle), getString(R.string.common_import)) {}
}

internal fun MainActivity.renderControlCenterResetPage() {
    showControlCenterFeature(
        getString(R.string.destroy_data_title),
        ControlCenterPageSpec(
            banner = ControlCenterBannerSpec(
                title = getString(R.string.destroy_data_hero_title),
                subtitle = getString(R.string.destroy_data_hero_subtitle),
                iconRes = R.drawable.ic_delete,
                tone = ControlCenterTone.RED
            ),
            sections = listOf(
                ControlCenterSectionSpec(
                    getString(R.string.destroy_data_scope),
                    listOf(
                        ControlCenterRowSpec(
                            "",
                            getString(R.string.destroy_data_regenerate_identity),
                            getString(R.string.destroy_data_regenerate_identity_subtitle),
                            R.drawable.ic_security_shield,
                            getString(R.string.cc_reset_removed_status),
                            ControlCenterTone.RED,
                            showChevron = false
                        ),
                        ControlCenterRowSpec(
                            "",
                            getString(R.string.destroy_data_contacts),
                            getString(R.string.destroy_data_contacts_subtitle),
                            R.drawable.ic_group,
                            getString(R.string.cc_reset_removed_status),
                            ControlCenterTone.RED,
                            showChevron = false
                        ),
                        ControlCenterRowSpec(
                            "",
                            getString(R.string.destroy_data_messages),
                            getString(R.string.destroy_data_messages_subtitle),
                            R.drawable.ic_delete,
                            getString(R.string.cc_reset_removed_status),
                            ControlCenterTone.RED,
                            showChevron = false
                        ),
                        ControlCenterRowSpec(
                            "",
                            getString(R.string.cc_reset_agent_data_title),
                            getString(R.string.cc_reset_agent_data_subtitle),
                            R.drawable.ic_agent_node,
                            getString(R.string.cc_reset_removed_status),
                            ControlCenterTone.RED,
                            showChevron = false
                        ),
                        ControlCenterRowSpec(
                            "",
                            getString(R.string.cc_reset_settings_assets_title),
                            getString(R.string.cc_reset_settings_assets_subtitle),
                            R.drawable.ic_settings_diagnostics,
                            getString(R.string.cc_reset_removed_status),
                            ControlCenterTone.RED,
                            showChevron = false
                        )
                    )
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_reset_confirmation_section),
                    listOf(
                        ControlCenterRowSpec(
                            "reset.begin",
                            getString(R.string.cc_reset_begin_title),
                            getString(R.string.cc_reset_begin_subtitle),
                            R.drawable.ic_reset_data,
                            getString(R.string.cc_reset_irreversible),
                            ControlCenterTone.RED
                        )
                    )
                )
            ),
            footer = getString(R.string.cc_reset_footer)
        )
    )
}

internal fun MainActivity.confirmDestroyAllData() {
    renderControlCenterResetPage()
}

internal fun MainActivity.showResetConfirmationDialog() {
    val input = EditText(this).apply {
        setSingleLine(true)
        hint = getString(R.string.cc_reset_input_hint)
        setPadding(dp(12), dp(8), dp(12), dp(8))
    }
    val dialog = android.app.AlertDialog.Builder(this)
        .setTitle(getString(R.string.cc_reset_dialog_title))
        .setMessage(getString(R.string.cc_reset_dialog_message))
        .setView(input)
        .setNegativeButton(getString(R.string.common_cancel), null)
        .setPositiveButton(getString(R.string.destroy_data_title), null)
        .create()
    dialog.setOnShowListener {
        dialog.getButton(android.app.AlertDialog.BUTTON_POSITIVE).apply {
            setTextColor(Color.parseColor("#C7372F"))
            setOnClickListener {
                if (input.text?.toString()?.trim() != "RESET") {
                    input.error = getString(R.string.cc_reset_input_error)
                    return@setOnClickListener
                }
                dialog.dismiss()
                destroyAllPrivateDataAndRestart()
            }
        }
    }
    dialog.show()
}

internal fun MainActivity.destroyAllPrivateDataAndRestart() {
    AppStore.destroyAllPrivateData(this)
    CloudConversationContextStore.clear(this)
    messages.clear()
    summaries.clear()
    currentMessages.clear()
    Toast.makeText(this, getString(R.string.destroy_data_success), Toast.LENGTH_LONG).show()
    restartFreshApp()
}

internal fun MainActivity.showAboutSignalASIPage() {
    val versionName = runCatching {
        packageManager.getPackageInfo(packageName, 0).versionName
    }.getOrNull().orEmpty().ifBlank { "0.1.0" }
    showFeaturePage(getString(R.string.settings_about_signalasi))
    featureContent.addView(featureHeroCard(
        getString(R.string.app_name),
        getString(R.string.about_product_subtitle),
        R.mipmap.ic_launcher,
        "#16B981",
        "v$versionName"
    ))
    addSectionTitle(getString(R.string.about_section_product))
    featureContent.addView(featureRow(
        getString(R.string.about_version),
        getString(R.string.about_version_subtitle),
        R.drawable.ic_info_outline,
        "v$versionName"
    ))
    featureContent.addView(featureRow(
        getString(R.string.settings_signal_link_protocol),
        getString(R.string.about_protocol_subtitle),
        R.drawable.ic_protocol_link,
        "v1.0.3"
    ).apply { setOnClickListener { showSignalLinkProtocolPage() } })
    addSectionTitle(getString(R.string.about_section_trust))
    featureContent.addView(featureRow(
        getString(R.string.about_security),
        getString(R.string.about_security_subtitle),
        R.drawable.ic_security_shield,
        getString(R.string.common_view)
    ).apply {
        setOnClickListener {
            showSecurityFeaturePage()
            setFeatureBackAction { showAboutSignalASIPage() }
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.about_open_source),
        getString(R.string.about_open_source_subtitle),
        R.drawable.ic_protocol_link,
        getString(R.string.common_view)
    ).apply {
        setOnClickListener {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/signalasi/SignalASI")))
        }
    })
}

internal fun MainActivity.restartFreshApp() {
    val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
    }
    if (intent != null) startActivity(intent)
    finishAffinity()
    android.os.Process.killProcess(android.os.Process.myPid())
}

internal fun MainActivity.promptPassword(title: String, message: String, onPassword: (String) -> Unit) {
    showPasswordFeaturePage(title, message, getString(R.string.common_confirm), onPassword)
}

internal fun MainActivity.showPasswordFeaturePage(title: String, message: String, action: String, onPassword: (String) -> Unit) {
    showFeaturePage(title)
    featureContent.addView(featureHeroCard(title, message, R.drawable.ic_security_shield, "#5B6CFF", getString(R.string.backup_password_page_badge)))
    addSectionTitle(getString(R.string.backup_password_section_title))
    val input = EditText(this).apply {
        setSingleLine(true)
        hint = getString(R.string.backup_password_input_hint)
        setBackgroundResource(R.drawable.message_input_background)
        setPadding(dp(14), dp(10), dp(14), dp(10))
        textSize = 16f
    }
    featureContent.addView(input, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(48)).apply {
        bottomMargin = dp(18)
    })
    featureContent.addView(TextView(this).apply {
        text = action
        gravity = Gravity.CENTER
        setTextColor(Color.WHITE)
        textSize = 17f
        background = getDrawable(R.drawable.send_button_background)
        setOnClickListener {
            val pw = input.text?.toString().orEmpty()
            if (pw.isBlank()) {
                Toast.makeText(this@showPasswordFeaturePage, getString(R.string.backup_password_input_required), Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            onPassword(pw)
        }
    }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(46)))
}

internal fun MainActivity.importBackupWithPassword(uri: Uri, password: String) {
    runCatching {
        val target = File(cacheDir, "import_${System.currentTimeMillis()}.hcbak")
        contentResolver.openInputStream(uri)?.use { input ->
            target.outputStream().use { output -> input.copyTo(output) }
        }
        AppStore.importBackup(this, target, password)
        target.delete()
        runOnUiThread {
            pendingImportUri = null
            Toast.makeText(this, getString(R.string.backup_import_success), Toast.LENGTH_LONG).show()
            recreate()
        }
    }.onFailure {
        runOnUiThread { Toast.makeText(this, getString(R.string.backup_import_failed, it.message ?: ""), Toast.LENGTH_LONG).show() }
    }
}

internal fun MainActivity.confirmDeleteChat(contact: Contact): Boolean {
    showFeaturePage(getString(R.string.delete_chat_title))
    featureContent.addView(featureHeroCard(getString(R.string.delete_chat_hero_title, contact.name), getString(R.string.delete_chat_subtitle), R.drawable.ic_delete, "#FF3B30", getString(R.string.common_confirm)))
    featureContent.addView(TextView(this).apply {
        text = getString(R.string.delete_chat_title)
        gravity = Gravity.CENTER
        setTextColor(Color.WHITE)
        textSize = 17f
        background = GradientDrawable().apply {
            cornerRadius = dp(8).toFloat()
            setColor(Color.parseColor("#FF3B30"))
        }
        setOnClickListener {
            deleteChatConversationData(contact)
            Toast.makeText(this@confirmDeleteChat, getString(R.string.delete_chat_toast), Toast.LENGTH_SHORT).show()
            hideFeaturePage()
        }
    }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(46)).apply {
        topMargin = dp(18)
    })
    return true
}

internal fun MainActivity.deleteChatConversationData(contact: Contact) {
    val removedMessages = messages.remove(contact.id).orEmpty()
    val removedMessageIds = removedMessages.map(ChatMessage::id)
    discardPendingChatHistory(removedMessageIds)
    ChatHistoryStore.deleteContact(this, contact.id, removedMessageIds)
    summaries.remove(contact.id)
    ContactConversationPreferences.remove(this, contact.id)
    CloudConversationContextStore.removeContact(this, contact.id)
    refreshContactList()
}

internal fun MainActivity.confirmDeleteContact(contact: Contact): Boolean {
    val title = if (contact.id == CONTACT_HERMES.id) getString(R.string.delete_hermes_title) else getString(R.string.delete_contact_title)
    val message = if (contact.id == CONTACT_HERMES.id) {
        getString(R.string.delete_hermes_subtitle)
    } else {
        getString(R.string.delete_contact_subtitle)
    }
    val dialog = AlertDialog.Builder(this)
        .setTitle(title)
        .setMessage("${contact.name}\n\n$message")
        .setNegativeButton(R.string.common_cancel, null)
        .setPositiveButton(R.string.common_delete) { _, _ ->
            AppStore.deleteContact(this, contact.id, deleteMessages = false)
            CloudConversationContextStore.removeContact(this, contact.id)
            if (selectedContact?.id == contact.id) selectedContact = null
            refreshContactList()
            refreshDirectoryContacts()
            Toast.makeText(this, getString(R.string.delete_contact_toast), Toast.LENGTH_LONG).show()
        }
        .create()
    dialog.setOnShowListener {
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setTextColor(Color.parseColor("#FF3B30"))
    }
    dialog.show()
    return true
}

internal fun MainActivity.pickAvatar() {
    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
        addCategory(Intent.CATEGORY_OPENABLE)
        type = "image/*"
    }
    startActivityForResult(intent, REQUEST_PICK_AVATAR)
}

internal fun MainActivity.handleAvatarPicked(uri: Uri?) {
    if (uri == null) return
    try {
        contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
    } catch (_: Exception) {}
    showFeaturePage(getString(R.string.avatar_edit_title))
    featureContent.gravity = Gravity.CENTER_HORIZONTAL
    featureContent.addView(ImageView(this).apply {
        setImageURI(uri)
        scaleType = ImageView.ScaleType.CENTER_CROP
        setBackgroundResource(R.drawable.rounded_avatar_bg)
        clipToOutline = true
    }, LinearLayout.LayoutParams(dp(160), dp(160)).apply {
        topMargin = dp(24)
        bottomMargin = dp(24)
        gravity = Gravity.CENTER_HORIZONTAL
    })
    featureContent.addView(TextView(this).apply {
        text = getString(R.string.common_save)
        gravity = Gravity.CENTER
        setTextColor(Color.WHITE)
        textSize = 17f
        background = getDrawable(R.drawable.send_button_background)
        setOnClickListener {
            val profile = AppStore.profile(this@handleAvatarPicked)
            profile.put("avatar_uri", uri.toString())
            AppStore.updateProfile(this@handleAvatarPicked, profile)
            refreshMePage()
            Toast.makeText(this@handleAvatarPicked, getString(R.string.avatar_saved_toast), Toast.LENGTH_SHORT).show()
            featureContent.gravity = Gravity.NO_GRAVITY
            hideFeaturePage()
        }
    }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(46)))
}

internal fun MainActivity.hideKeyboard() {
    getSystemService(InputMethodManager::class.java).hideSoftInputFromWindow(messageInput.windowToken, 0)
}

internal fun MainActivity.showAgentAttachmentMenu() {
    setAgentActionTrayExpanded(!agentActionTrayExpanded)
}

internal fun MainActivity.openAgentCamera() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
        checkSelfPermission(android.Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED
    ) {
        requestPermissions(arrayOf(android.Manifest.permission.CAMERA), REQUEST_AGENT_CAMERA_PERMISSION)
        return
    }
    val values = ContentValues().apply {
        put(MediaStore.Images.Media.DISPLAY_NAME, "signalasi_${System.currentTimeMillis()}.jpg")
        put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/SignalASI")
        }
    }
    val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
    if (uri == null) {
        Toast.makeText(this, getString(R.string.agent_attachment_camera_unavailable), Toast.LENGTH_SHORT).show()
        return
    }
    pendingAgentCameraUri = uri
    val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
        putExtra(MediaStore.EXTRA_OUTPUT, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
    }
    if (intent.resolveActivity(packageManager) == null) {
        contentResolver.delete(uri, null, null)
        pendingAgentCameraUri = null
        Toast.makeText(this, getString(R.string.agent_attachment_camera_unavailable), Toast.LENGTH_SHORT).show()
        return
    }
    startActivityForResult(intent, REQUEST_AGENT_CAMERA)
}

internal fun MainActivity.openChatCamera() {
    val contact = selectedContact ?: return
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
        checkSelfPermission(android.Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED
    ) {
        requestPermissions(arrayOf(android.Manifest.permission.CAMERA), REQUEST_CHAT_CAMERA_PERMISSION)
        return
    }
    val values = ContentValues().apply {
        put(MediaStore.Images.Media.DISPLAY_NAME, "signalasi_${System.currentTimeMillis()}.jpg")
        put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/SignalASI")
        }
    }
    val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
    if (uri == null) {
        Toast.makeText(this, getString(R.string.agent_attachment_camera_unavailable), Toast.LENGTH_SHORT).show()
        return
    }
    rememberPendingChatCamera(uri, contact.id)
    val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
        putExtra(MediaStore.EXTRA_OUTPUT, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
    }
    if (intent.resolveActivity(packageManager) == null) {
        contentResolver.delete(uri, null, null)
        clearPendingChatCamera()
        Toast.makeText(this, getString(R.string.agent_attachment_camera_unavailable), Toast.LENGTH_SHORT).show()
        return
    }
    startActivityForResult(intent, REQUEST_CHAT_CAMERA)
}

internal fun MainActivity.openChatAttachmentPicker() {
    val contact = selectedContact ?: return
    val peerChat = AppStore.isDesktopDeviceContact(this, contact.id) ||
        AppStore.isPersonContact(this, contact.id)
    val intent = Intent(if (peerChat) Intent.ACTION_OPEN_DOCUMENT else Intent.ACTION_GET_CONTENT).apply {
        type = if (peerChat) "*/*" else "image/*"
        addCategory(Intent.CATEGORY_OPENABLE)
        if (peerChat) {
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
    }
    startActivityForResult(intent, REQUEST_IMAGE)
}

internal fun MainActivity.openAgentKnowledgeImportPicker() {
    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
        type = "*/*"
        addCategory(Intent.CATEGORY_OPENABLE)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        putExtra(Intent.EXTRA_MIME_TYPES, arrayOf(
            "text/*",
            "application/json",
            "application/pdf",
            "application/msword",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "application/octet-stream"
        ))
    }
    startActivityForResult(intent, REQUEST_IMPORT_KNOWLEDGE)
}

internal fun MainActivity.openAgentAttachmentPicker(imagesOnly: Boolean) {
    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
        type = if (imagesOnly) "image/*" else "*/*"
        addCategory(Intent.CATEGORY_OPENABLE)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
    }
    startActivityForResult(intent, if (imagesOnly) REQUEST_AGENT_IMAGES else REQUEST_AGENT_ATTACHMENTS)
}

internal fun MainActivity.addAgentInputUris(uris: List<Uri>) {
    var rejected = 0
    uris.distinct().forEach { uri ->
        if (agentInputAttachments.size >= MAX_AGENT_ATTACHMENTS) {
            rejected++
            return@forEach
        }
        val metadata = agentAttachmentMetadata(uri)
        if (metadata.sizeBytes > MAX_AGENT_ATTACHMENT_BYTES || metadata.sizeBytes < 0L) {
            rejected++
            return@forEach
        }
        if (agentInputAttachments.any { it.uri == uri }) return@forEach
        agentInputAttachments += metadata
    }
    renderAgentInputAttachments()
    if (rejected > 0) {
        Toast.makeText(this, getString(R.string.agent_attachment_rejected), Toast.LENGTH_LONG).show()
    }
}

internal fun MainActivity.agentAttachmentMetadata(uri: Uri): AgentInputAttachment {
    var name = uri.lastPathSegment?.substringAfterLast('/').orEmpty().ifBlank { "attachment" }
    var size = 0L
    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)
        ?.use { cursor ->
            if (cursor.moveToFirst()) {
                cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME).takeIf { it >= 0 }
                    ?.let { name = cursor.getString(it).orEmpty().ifBlank { name } }
                cursor.getColumnIndex(OpenableColumns.SIZE).takeIf { it >= 0 }
                    ?.let { if (!cursor.isNull(it)) size = cursor.getLong(it) }
            }
        }
    val mimeType = contentResolver.getType(uri).orEmpty().ifBlank {
        android.webkit.MimeTypeMap.getSingleton()
            .getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase(Locale.US))
            ?: "application/octet-stream"
    }
    return AgentInputAttachment(
        id = UUID.randomUUID().toString(),
        uri = uri,
        displayName = name.take(180),
        mimeType = mimeType.take(160),
        sizeBytes = size
    )
}

internal fun MainActivity.renderAgentInputAttachments() {
    agentAttachmentPreviewList.removeAllViews()
    agentInputAttachments.forEach { attachment ->
        agentAttachmentPreviewList.addView(agentInputAttachmentCard(attachment))
    }
    agentAttachmentPreviewScroll.visibility = if (agentInputAttachments.isEmpty()) View.GONE else View.VISIBLE
    updateAgentSubmitButtonAppearance(
        agentGoalInput.text?.toString()?.isNotBlank() == true || agentInputAttachments.isNotEmpty()
    )
    if (agentInputAttachments.isNotEmpty()) {
        agentAttachmentPreviewScroll.post { agentAttachmentPreviewScroll.fullScroll(View.FOCUS_RIGHT) }
    }
}

internal fun MainActivity.agentInputAttachmentCard(attachment: AgentInputAttachment): View {
    val cardBackground = GradientDrawable().apply {
        cornerRadius = dp(8).toFloat()
        setColor(Color.parseColor("#F4F6F8"))
        setStroke(dp(1), Color.parseColor("#DDE2E7"))
    }
    val container = FrameLayout(this).apply {
        background = cardBackground
        clipToOutline = true
    }
    if (attachment.isImage) {
        container.addView(ImageView(this).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            contentDescription = attachment.displayName
            loadAgentImageThumbnail(this, attachment.uri, dp(140), dp(132))
        }, FrameLayout.LayoutParams(dp(70), dp(66)))
    } else {
        container.addView(LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(10), dp(7), dp(30), dp(7))
            addView(ImageView(this@agentInputAttachmentCard).apply {
                setImageResource(R.drawable.ic_agent_attach)
                imageTintList = android.content.res.ColorStateList.valueOf(Color.parseColor("#53606D"))
            }, LinearLayout.LayoutParams(dp(26), dp(26)).apply { marginEnd = dp(8) })
            addView(LinearLayout(this@agentInputAttachmentCard).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER_VERTICAL
                addView(TextView(this@agentInputAttachmentCard).apply {
                    text = attachment.displayName
                    textSize = 13f
                    setTextColor(getColorCompat(R.color.text_primary))
                    maxLines = 1
                    ellipsize = android.text.TextUtils.TruncateAt.MIDDLE
                }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
                addView(TextView(this@agentInputAttachmentCard).apply {
                    text = AgentInputAttachment.humanSize(attachment.sizeBytes)
                    textSize = 11f
                    setTextColor(getColorCompat(R.color.text_secondary))
                })
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        }, FrameLayout.LayoutParams(dp(190), dp(66)))
    }
    container.addView(ImageButton(this).apply {
        setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
        imageTintList = android.content.res.ColorStateList.valueOf(Color.parseColor("#59636E"))
        setBackgroundColor(Color.TRANSPARENT)
        contentDescription = getString(R.string.agent_attachment_remove)
        setPadding(dp(5), dp(5), dp(5), dp(5))
        setOnClickListener {
            agentInputAttachments.removeAll { it.id == attachment.id }
            renderAgentInputAttachments()
        }
    }, FrameLayout.LayoutParams(dp(28), dp(28), Gravity.TOP or Gravity.END))
    val width = if (attachment.isImage) dp(70) else dp(190)
    return container.apply {
        layoutParams = LinearLayout.LayoutParams(width, dp(66)).apply { marginEnd = dp(8) }
    }
}

internal fun MainActivity.importAgentKnowledgeFromUri(uri: Uri) {
    runCatching {
        contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    thread(name = "signalasi-knowledge-import") {
        val result = AgentKnowledgeImporter(applicationContext).importDocument(uri)
        runOnUiThread {
            renderAgentState(mobileNativeAgent.recordKnowledgeImport(result))
            Toast.makeText(this, result.message, Toast.LENGTH_LONG).show()
            if (result.success) {
                showAgentKnowledgePage()
            }
        }
    }
}

internal fun MainActivity.imageMeta(uri: Uri): ImageMeta {
    var name = "image"
    var size = 0L
    contentResolver.query(uri, null, null, null, null)?.use { cursor ->
        if (cursor.moveToFirst()) {
            cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME).let { if (it >= 0) name = cursor.getString(it) ?: name }
            cursor.getColumnIndex(OpenableColumns.SIZE).let { if (it >= 0) size = cursor.getLong(it) }
        }
    }
    return ImageMeta(name, size)
}

internal fun MainActivity.jsonSignalasiId(json: JSONObject?, fallback: String = ""): String {
    if (json == null) return fallback
    return json.optString("signalasi_id")
        .ifBlank { json.optString("hermes_id") }
        .ifBlank { json.optString("id") }
        .ifBlank { fallback }
}

internal fun MainActivity.contactById(id: String): Contact {
    AppStore.contactById(this, id)?.let { raw ->
        if (!raw.optBoolean("deleted", false) && raw.optString("trust_state") != "deleted") {
            val contactId = raw.optString("id").ifBlank { jsonSignalasiId(raw, id) }
            return Contact(contactId, raw.optString("name", contactId), "")
        }
    }
    return when (id) {
        CONTACT_SYSTEM.id -> CONTACT_SYSTEM
        CONTACT_ME.id -> CONTACT_ME
        CONTACT_PC.id -> CONTACT_PC
        CONTACT_HOME.id -> CONTACT_HOME
        CONTACT_NEWS.id -> CONTACT_NEWS
        CONTACT_AUTOMATION.id -> CONTACT_AUTOMATION
        else -> {
            val contacts = AppStore.contacts(this)
            for (i in 0 until contacts.length()) {
                val c = contacts.optJSONObject(i) ?: continue
                val cid = c.optString("id").ifBlank { jsonSignalasiId(c) }
                if (cid == id) return Contact(cid, c.optString("name", cid), "")
            }
            id.let { Contact(it, it, "") }
        }
    }
}

internal fun MainActivity.dp(dp: Int): Int = (dp * resources.displayMetrics.density).toInt()

internal fun MainActivity.formatFingerprint(value: String): String {
    return value
        .filter { it.isLetterOrDigit() }
        .chunked(32)
        .take(2)
        .joinToString("\n")
}
