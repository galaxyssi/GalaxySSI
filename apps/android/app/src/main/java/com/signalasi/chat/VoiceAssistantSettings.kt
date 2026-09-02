package com.signalasi.chat

import android.content.Context
import com.signalasi.chat.voice.asr.AsrPrivacyPolicy
import com.signalasi.chat.voice.asr.VoiceRecognitionPreference
import com.signalasi.chat.voice.benchmark.WhisperUserVoiceMode

data class VoiceAssistantConfig(
    val enabled: Boolean,
    val wakeWords: List<String>,
    val wakeProvider: String,
    val wakeModel: String,
    val wakeThreshold: Float,
    val asrProvider: String,
    val recognitionPreference: VoiceRecognitionPreference,
    val onlineAsrPrivacy: AsrPrivacyPolicy,
    val remoteWhisperAllowed: Boolean,
    val asrModel: String,
    val asrAcceleration: String,
    val asrQnnPackage: String,
    val asrRuntimeMode: WhisperUserVoiceMode,
    val asrLanguage: String,
    val ttsProvider: String,
    val ttsLanguage: String,
    val responseLanguage: String,
    val microsoftVoice: String,
    val welcomeText: String,
    val targetContactId: String,
    val speakReplies: Boolean,
    val routingMode: String
)

object VoiceAssistantSettings {
    private const val PREFS = "signalasi_voice_assistant"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_WAKE_PROVIDER = "wake_provider"
    private const val KEY_WAKE_MODEL = "wake_model"
    private const val KEY_WAKE_THRESHOLD = "wake_threshold"
    private const val KEY_ASR_PROVIDER = "asr_provider"
    private const val KEY_ASR_RECOGNITION_PREFERENCE = "asr_recognition_preference"
    private const val KEY_ONLINE_ASR_ALLOWED = "online_asr_allowed"
    private const val KEY_ONLINE_ASR_WIFI_ONLY = "online_asr_wifi_only"
    private const val KEY_ONLINE_ASR_MOBILE_ALLOWED = "online_asr_mobile_allowed"
    private const val KEY_ONLINE_ASR_AUDIO_UPLOAD_ALLOWED = "online_asr_audio_upload_allowed"
    private const val KEY_ONLINE_ASR_DELETE_SERVER_DATA = "online_asr_delete_server_data"
    private const val KEY_LOCAL_ASR_ALWAYS_PREFERRED = "local_asr_always_preferred"
    private const val KEY_REMOTE_WHISPER_ALLOWED = "remote_whisper_allowed"
    private const val KEY_ASR_MODEL = "asr_model"
    private const val KEY_ASR_ACCELERATION = "asr_acceleration"
    private const val KEY_ASR_QNN_PACKAGE = "asr_qnn_package"
    private const val KEY_ASR_RUNTIME_MODE = "asr_runtime_mode"
    private const val KEY_TTS_PROVIDER = "tts_provider"
    private const val KEY_MICROSOFT_VOICE = "microsoft_voice"
    private const val KEY_WELCOME_TEXT = "welcome_text"
    private const val KEY_TARGET_CONTACT = "target_contact"
    private const val KEY_SPEAK_REPLIES = "speak_replies"
    private const val KEY_ROUTING_MODE = "routing_mode"

    const val PROVIDER_MICROSOFT_EDGE = "microsoft_edge"
    const val PROVIDER_ANDROID = "android"
    const val WAKE_PROVIDER_OPEN_WAKE_WORD = "openwakeword"
    const val WAKE_PROVIDER_ANDROID_ASR = "android_asr"
    const val ASR_PROVIDER_LOCAL_WHISPER = "local_whisper_cpp"
    const val ASR_PROVIDER_AUTO = "auto"
    const val ASR_PROVIDER_ONLINE_REALTIME = "online_realtime"
    const val ASR_PROVIDER_REMOTE_WHISPER = "remote_whisper"
    const val ASR_ACCELERATION_GGML = "ggml"
    const val ASR_ACCELERATION_QNN = "qnn"
    const val ROUTING_MODE_NATIVE_AGENT = "native_agent"
    const val ROUTING_MODE_CONTACT = "contact"
    const val DEFAULT_WAKE_MODEL = "hello_world.onnx"
    val SUPPORTED_WAKE_MODELS = listOf(DEFAULT_WAKE_MODEL)

    fun get(context: Context): VoiceAssistantConfig {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val languagePolicy = LanguagePolicySettings.get(context)
        val defaultWelcomeText = context.getString(R.string.voice_default_welcome_text)
        val storedAsrModel = prefs.getString(KEY_ASR_MODEL, "tiny").orEmpty()
        val canonicalAsrModel = WhisperModelManager.model(storedAsrModel).id
        if (storedAsrModel != canonicalAsrModel) {
            prefs.edit().putString(KEY_ASR_MODEL, canonicalAsrModel).apply()
        }
        return VoiceAssistantConfig(
            enabled = prefs.getBoolean(KEY_ENABLED, true),
            wakeWords = WakeWordPolicy.configuredWords,
            wakeProvider = prefs.getString(KEY_WAKE_PROVIDER, WAKE_PROVIDER_OPEN_WAKE_WORD).orEmpty()
                .ifBlank { WAKE_PROVIDER_OPEN_WAKE_WORD },
            wakeModel = prefs.getString(KEY_WAKE_MODEL, DEFAULT_WAKE_MODEL).orEmpty()
                .takeIf { it in SUPPORTED_WAKE_MODELS }
                ?: DEFAULT_WAKE_MODEL,
            wakeThreshold = prefs.getFloat(KEY_WAKE_THRESHOLD, 0.5f).coerceIn(0.01f, 0.99f),
            asrProvider = prefs.getString(KEY_ASR_PROVIDER, ASR_PROVIDER_AUTO).orEmpty()
                .takeIf { it in SUPPORTED_ASR_PROVIDERS }
                ?: ASR_PROVIDER_AUTO,
            recognitionPreference = runCatching {
                enumValueOf<VoiceRecognitionPreference>(
                    prefs.getString(KEY_ASR_RECOGNITION_PREFERENCE, VoiceRecognitionPreference.AUTO.name).orEmpty()
                )
            }.getOrDefault(VoiceRecognitionPreference.AUTO),
            onlineAsrPrivacy = AsrPrivacyPolicy(
                allowOnlineVoice = prefs.getBoolean(KEY_ONLINE_ASR_ALLOWED, false),
                wifiOnly = prefs.getBoolean(KEY_ONLINE_ASR_WIFI_ONLY, true),
                allowMobileNetwork = prefs.getBoolean(KEY_ONLINE_ASR_MOBILE_ALLOWED, false),
                allowRawAudioUpload = prefs.getBoolean(KEY_ONLINE_ASR_AUDIO_UPLOAD_ALLOWED, false),
                requestServerDataDeletion = prefs.getBoolean(KEY_ONLINE_ASR_DELETE_SERVER_DATA, true),
                localAlwaysPreferred = prefs.getBoolean(KEY_LOCAL_ASR_ALWAYS_PREFERRED, false)
            ),
            remoteWhisperAllowed = prefs.getBoolean(KEY_REMOTE_WHISPER_ALLOWED, false),
            asrModel = canonicalAsrModel,
            asrAcceleration = prefs.getString(KEY_ASR_ACCELERATION, ASR_ACCELERATION_GGML).orEmpty()
                .takeIf { it == ASR_ACCELERATION_GGML || it == ASR_ACCELERATION_QNN }
                ?: ASR_ACCELERATION_GGML,
            asrQnnPackage = prefs.getString(KEY_ASR_QNN_PACKAGE, "").orEmpty(),
            asrRuntimeMode = runCatching {
                enumValueOf<WhisperUserVoiceMode>(
                    prefs.getString(KEY_ASR_RUNTIME_MODE, WhisperUserVoiceMode.AUTOMATIC.name).orEmpty()
                )
            }.getOrDefault(WhisperUserVoiceMode.AUTOMATIC),
            asrLanguage = languagePolicy.asrLanguage,
            ttsProvider = prefs.getString(KEY_TTS_PROVIDER, PROVIDER_MICROSOFT_EDGE).orEmpty()
                .takeIf { it == PROVIDER_ANDROID || it == PROVIDER_MICROSOFT_EDGE }
                ?: PROVIDER_MICROSOFT_EDGE,
            ttsLanguage = languagePolicy.ttsLanguage,
            responseLanguage = languagePolicy.responseLanguage,
            microsoftVoice = MicrosoftTtsVoiceCatalog.canonical(
                prefs.getString(KEY_MICROSOFT_VOICE, MicrosoftTtsVoiceCatalog.XIAOXIAO)
            ),
            welcomeText = prefs.getString(KEY_WELCOME_TEXT, defaultWelcomeText).orEmpty()
                .ifBlank { defaultWelcomeText },
            targetContactId = prefs.getString(KEY_TARGET_CONTACT, "hermes").orEmpty().ifBlank { "hermes" },
            speakReplies = prefs.getBoolean(KEY_SPEAK_REPLIES, false),
            routingMode = prefs.getString(KEY_ROUTING_MODE, ROUTING_MODE_NATIVE_AGENT).orEmpty()
                .takeIf { it in setOf(ROUTING_MODE_NATIVE_AGENT, ROUTING_MODE_CONTACT) }
                ?: ROUTING_MODE_NATIVE_AGENT
        )
    }

    fun setEnabled(context: Context, value: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY_ENABLED, value).apply()
    }

    fun setWakeProvider(context: Context, value: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_WAKE_PROVIDER, value).apply()
    }

    fun setWakeModel(context: Context, value: String) {
        val model = value.takeIf { it in SUPPORTED_WAKE_MODELS } ?: DEFAULT_WAKE_MODEL
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_WAKE_MODEL, model).apply()
    }

    fun setWakeThreshold(context: Context, value: Float) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putFloat(KEY_WAKE_THRESHOLD, value.coerceIn(0.01f, 0.99f)).apply()
    }

    fun setAsrProvider(context: Context, value: String) {
        val provider = value.takeIf { it in SUPPORTED_ASR_PROVIDERS } ?: ASR_PROVIDER_AUTO
        val preference = when (provider) {
            ASR_PROVIDER_LOCAL_WHISPER -> VoiceRecognitionPreference.LOCAL_PRIVATE
            ASR_PROVIDER_ONLINE_REALTIME -> VoiceRecognitionPreference.ONLINE_FAST
            ASR_PROVIDER_REMOTE_WHISPER -> VoiceRecognitionPreference.REMOTE_NODE
            else -> VoiceRecognitionPreference.AUTO
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_ASR_PROVIDER, provider)
            .putString(KEY_ASR_RECOGNITION_PREFERENCE, preference.name)
            .apply()
    }

    fun setRecognitionPreference(context: Context, value: VoiceRecognitionPreference) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_ASR_RECOGNITION_PREFERENCE, value.name)
            .apply()
    }

    fun setOnlineAsrPrivacy(context: Context, value: AsrPrivacyPolicy) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_ONLINE_ASR_ALLOWED, value.allowOnlineVoice)
            .putBoolean(KEY_ONLINE_ASR_WIFI_ONLY, value.wifiOnly)
            .putBoolean(KEY_ONLINE_ASR_MOBILE_ALLOWED, value.allowMobileNetwork)
            .putBoolean(KEY_ONLINE_ASR_AUDIO_UPLOAD_ALLOWED, value.allowRawAudioUpload)
            .putBoolean(KEY_ONLINE_ASR_DELETE_SERVER_DATA, value.requestServerDataDeletion)
            .putBoolean(KEY_LOCAL_ASR_ALWAYS_PREFERRED, value.localAlwaysPreferred)
            .apply()
    }

    fun setRemoteWhisperAllowed(context: Context, value: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_REMOTE_WHISPER_ALLOWED, value)
            .apply()
    }

    fun setAsrLanguage(context: Context, value: String) {
        LanguagePolicySettings.setAsrLanguage(context, value)
    }

    fun setTtsLanguage(context: Context, value: String) {
        LanguagePolicySettings.setTtsLanguage(context, value)
    }

    fun setResponseLanguage(context: Context, value: String) {
        LanguagePolicySettings.setResponseLanguage(context, value)
    }

    fun setAsrModel(context: Context, value: String) {
        val model = WhisperModelManager.model(value).id
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_ASR_MODEL, model)
            .putString(KEY_ASR_ACCELERATION, ASR_ACCELERATION_GGML)
            .remove(KEY_ASR_QNN_PACKAGE)
            .putString(KEY_ASR_RUNTIME_MODE, WhisperUserVoiceMode.MANUAL.name)
            .apply()
    }

    fun setAsrQnnPackage(context: Context, packageId: String, profileId: String) {
        val model = WhisperModelManager.model(profileId).id
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_ASR_MODEL, model)
            .putString(KEY_ASR_ACCELERATION, ASR_ACCELERATION_QNN)
            .putString(KEY_ASR_QNN_PACKAGE, packageId)
            .putString(KEY_ASR_RUNTIME_MODE, WhisperUserVoiceMode.MANUAL.name)
            .apply()
    }

    fun setAsrAcceleration(context: Context, value: String) {
        val acceleration = value.takeIf {
            it == ASR_ACCELERATION_GGML || it == ASR_ACCELERATION_QNN
        } ?: ASR_ACCELERATION_GGML
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_ASR_ACCELERATION, acceleration)
            .apply()
    }

    fun setAsrRuntimeMode(context: Context, value: WhisperUserVoiceMode) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_ASR_RUNTIME_MODE, value.name)
            .apply()
    }

    fun setTtsProvider(context: Context, value: String) {
        val provider = value.takeIf {
            it == PROVIDER_ANDROID || it == PROVIDER_MICROSOFT_EDGE
        } ?: PROVIDER_MICROSOFT_EDGE
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_TTS_PROVIDER, provider)
            .apply()
    }

    fun setMicrosoftVoice(context: Context, value: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_MICROSOFT_VOICE, MicrosoftTtsVoiceCatalog.canonical(value))
            .apply()
    }

    fun setWelcomeText(context: Context, value: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_WELCOME_TEXT, value).apply()
    }

    fun setTargetContact(context: Context, value: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_TARGET_CONTACT, value).apply()
    }

    fun setSpeakReplies(context: Context, value: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY_SPEAK_REPLIES, value).apply()
    }

    fun setRoutingMode(context: Context, value: String) {
        val mode = value.takeIf { it in setOf(ROUTING_MODE_NATIVE_AGENT, ROUTING_MODE_CONTACT) }
            ?: ROUTING_MODE_NATIVE_AGENT
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_ROUTING_MODE, mode).apply()
    }

    fun clear(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().commit()
        LanguagePolicySettings.clear(context)
    }

    private val SUPPORTED_ASR_PROVIDERS = setOf(
        ASR_PROVIDER_AUTO,
        ASR_PROVIDER_LOCAL_WHISPER,
        ASR_PROVIDER_ONLINE_REALTIME,
        ASR_PROVIDER_REMOTE_WHISPER
    )
}
