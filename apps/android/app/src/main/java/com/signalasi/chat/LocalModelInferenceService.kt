package com.signalasi.chat

import android.app.Application
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.RemoteException
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

internal object LocalModelInferenceProcess {
    private const val PROCESS_SUFFIX = ":local_model_runtime"

    fun isRuntimeProcess(): Boolean {
        val processName = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            Application.getProcessName()
        } else {
            runCatching {
                File("/proc/self/cmdline").readText().substringBefore('\u0000')
            }.getOrDefault("")
        }
        return processName.endsWith(PROCESS_SUFFIX)
    }
}

private object LocalModelInferenceProtocol {
    const val GENERATE = 1
    const val RELEASE = 2
    const val RESULT = 3

    const val REQUEST_ID = "request_id"
    const val PROFILE_ID = "profile_id"
    const val SYSTEM_PROMPT = "system_prompt"
    const val USER_PROMPT = "user_prompt"
    const val MAXIMUM_TOKENS = "maximum_tokens"
    const val TEMPERATURE = "temperature"
    const val THINKING_MODE = "thinking_mode"
    const val WORK_CLASS = "work_class"
    const val SUCCESS = "success"
    const val ERROR = "error"
    const val TEXT = "text"
    const val BACKEND = "backend"
    const val SME_AVAILABLE = "sme_available"
    const val ELAPSED_MILLIS = "elapsed_millis"
    const val PREPARATION_MILLIS = "preparation_millis"
    const val TOTAL_ELAPSED_MILLIS = "total_elapsed_millis"
    const val TIME_TO_FIRST_TOKEN_MILLIS = "time_to_first_token_millis"
    const val PROMPT_TOKENS = "prompt_tokens"
    const val GENERATED_TOKENS = "generated_tokens"
    const val PREFILL_TOKENS_PER_SECOND = "prefill_tokens_per_second"
    const val DECODE_TOKENS_PER_SECOND = "decode_tokens_per_second"
    const val STOP_REASON = "stop_reason"
}

/** Keeps all native local-model allocations and failures outside the UI and messaging process. */
class LocalModelInferenceService : Service() {
    private val executor = Executors.newSingleThreadExecutor { task ->
        Thread(task, "SignalASI-Local-Runtime").apply { isDaemon = true }
    }
    private val messenger = Messenger(Handler(Looper.getMainLooper()) { message ->
        when (message.what) {
            LocalModelInferenceProtocol.GENERATE -> executeGenerate(message)
            LocalModelInferenceProtocol.RELEASE -> executeRelease(message)
            else -> return@Handler false
        }
        true
    })

    override fun onBind(intent: Intent?): IBinder = messenger.binder

    override fun onDestroy() {
        executor.shutdownNow()
        runCatching { LocalModelInferenceRuntime.releaseForAsr() }
        super.onDestroy()
    }

    private fun executeGenerate(message: Message) {
        val request = message.data
        val replyTo = message.replyTo
        val requestId = request.getLong(LocalModelInferenceProtocol.REQUEST_ID)
        executor.execute {
            val response = Bundle().apply {
                putLong(LocalModelInferenceProtocol.REQUEST_ID, requestId)
            }
            runCatching {
                val profile = LocalModelCatalog.find(
                    this@LocalModelInferenceService,
                    request.getString(LocalModelInferenceProtocol.PROFILE_ID).orEmpty()
                )
                LocalModelInferenceRuntime.generate(
                    context = this@LocalModelInferenceService,
                    profile = profile,
                    systemPrompt = request.getString(LocalModelInferenceProtocol.SYSTEM_PROMPT).orEmpty(),
                    userPrompt = request.getString(LocalModelInferenceProtocol.USER_PROMPT).orEmpty(),
                    maximumTokens = request.getInt(LocalModelInferenceProtocol.MAXIMUM_TOKENS),
                    temperature = request.getFloat(LocalModelInferenceProtocol.TEMPERATURE),
                    thinkingMode = enumValueOrDefault(
                        request.getString(LocalModelInferenceProtocol.THINKING_MODE),
                        LocalModelThinkingMode.AUTOMATIC
                    ),
                    workClass = enumValueOrDefault(
                        request.getString(LocalModelInferenceProtocol.WORK_CLASS),
                        LocalModelWorkClass.INTERACTIVE
                    )
                )
            }.onSuccess { result ->
                response.putBoolean(LocalModelInferenceProtocol.SUCCESS, true)
                response.putString(LocalModelInferenceProtocol.TEXT, result.text)
                response.putString(LocalModelInferenceProtocol.PROFILE_ID, result.profileId)
                response.putString(LocalModelInferenceProtocol.BACKEND, result.backend)
                response.putBoolean(LocalModelInferenceProtocol.SME_AVAILABLE, result.smeAvailable)
                response.putLong(LocalModelInferenceProtocol.ELAPSED_MILLIS, result.elapsedMillis)
                response.putLong(LocalModelInferenceProtocol.PREPARATION_MILLIS, result.preparationMillis)
                response.putLong(LocalModelInferenceProtocol.TOTAL_ELAPSED_MILLIS, result.totalElapsedMillis)
                response.putDouble(
                    LocalModelInferenceProtocol.TIME_TO_FIRST_TOKEN_MILLIS,
                    result.timeToFirstTokenMillis
                )
                response.putLong(LocalModelInferenceProtocol.PROMPT_TOKENS, result.promptTokens)
                response.putLong(LocalModelInferenceProtocol.GENERATED_TOKENS, result.generatedTokens)
                response.putDouble(
                    LocalModelInferenceProtocol.PREFILL_TOKENS_PER_SECOND,
                    result.prefillTokensPerSecond
                )
                response.putDouble(
                    LocalModelInferenceProtocol.DECODE_TOKENS_PER_SECOND,
                    result.decodeTokensPerSecond
                )
                response.putString(LocalModelInferenceProtocol.STOP_REASON, result.stopReason)
            }.onFailure { error ->
                response.putBoolean(LocalModelInferenceProtocol.SUCCESS, false)
                response.putString(
                    LocalModelInferenceProtocol.ERROR,
                    error.message?.take(500) ?: error::class.java.simpleName
                )
            }
            // Native models may retain large CPU or HTP allocations. Release them before
            // returning so the next voice turn can prepare Whisper without overlapping graphs.
            runCatching { LocalModelInferenceRuntime.releaseForAsr() }
            sendResponse(replyTo, response)
        }
    }

    private fun executeRelease(message: Message) {
        val requestId = message.data.getLong(LocalModelInferenceProtocol.REQUEST_ID)
        val replyTo = message.replyTo
        executor.execute {
            val response = Bundle().apply {
                putLong(LocalModelInferenceProtocol.REQUEST_ID, requestId)
            }
            runCatching { LocalModelInferenceRuntime.releaseForAsr() }
                .onSuccess { response.putBoolean(LocalModelInferenceProtocol.SUCCESS, true) }
                .onFailure { error ->
                    response.putBoolean(LocalModelInferenceProtocol.SUCCESS, false)
                    response.putString(LocalModelInferenceProtocol.ERROR, error.message.orEmpty())
                }
            sendResponse(replyTo, response)
        }
    }

    private fun sendResponse(replyTo: Messenger?, response: Bundle) {
        runCatching {
            replyTo?.send(Message.obtain(null, LocalModelInferenceProtocol.RESULT).apply { data = response })
        }
    }

    private inline fun <reified T : Enum<T>> enumValueOrDefault(value: String?, fallback: T): T =
        enumValues<T>().firstOrNull { it.name == value } ?: fallback
}

internal object LocalModelInferenceProcessClient {
    private data class PendingRequest(
        val monitor: Object = Object(),
        @Volatile var response: Bundle? = null,
        @Volatile var failure: Throwable? = null
    )

    private val connectionMonitor = Object()
    private val pending = ConcurrentHashMap<Long, PendingRequest>()
    private val requestIds = AtomicLong(1L)
    private val replyMessenger = Messenger(Handler(Looper.getMainLooper()) { message ->
        if (message.what != LocalModelInferenceProtocol.RESULT) return@Handler false
        val response = message.data
        val request = pending.remove(response.getLong(LocalModelInferenceProtocol.REQUEST_ID))
            ?: return@Handler true
        synchronized(request.monitor) {
            request.response = response
            request.monitor.notifyAll()
        }
        true
    })
    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            synchronized(connectionMonitor) {
                remote = service?.let(::Messenger)
                binding = false
                connectionMonitor.notifyAll()
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            handleConnectionLoss("The local QNN runtime process stopped")
        }

        override fun onBindingDied(name: ComponentName?) {
            handleConnectionLoss("The local QNN runtime process was reclaimed by Android")
        }

        override fun onNullBinding(name: ComponentName?) {
            handleConnectionLoss("The local QNN runtime service could not be bound")
        }
    }

    @Volatile private var remote: Messenger? = null
    @Volatile private var binding = false
    @Volatile private var applicationContext: Context? = null
    @Volatile private var remoteLoadedProfileId = ""

    fun generate(
        context: Context,
        profile: LocalModelRuntimeProfile,
        systemPrompt: String,
        userPrompt: String,
        maximumTokens: Int,
        temperature: Float,
        thinkingMode: LocalModelThinkingMode,
        workClass: LocalModelWorkClass
    ): LocalModelInferenceResult {
        check(Looper.myLooper() != Looper.getMainLooper()) {
            "Local inference must not block the UI thread"
        }
        return try {
            val response = transact(
                context,
                LocalModelInferenceProtocol.GENERATE,
                Bundle().apply {
                    putString(LocalModelInferenceProtocol.PROFILE_ID, profile.id)
                    putString(LocalModelInferenceProtocol.SYSTEM_PROMPT, systemPrompt)
                    putString(LocalModelInferenceProtocol.USER_PROMPT, userPrompt)
                    putInt(LocalModelInferenceProtocol.MAXIMUM_TOKENS, maximumTokens)
                    putFloat(LocalModelInferenceProtocol.TEMPERATURE, temperature)
                    putString(LocalModelInferenceProtocol.THINKING_MODE, thinkingMode.name)
                    putString(LocalModelInferenceProtocol.WORK_CLASS, workClass.name)
                }
            )
            requireSuccess(response)
            LocalModelInferenceResult(
                text = response.getString(LocalModelInferenceProtocol.TEXT).orEmpty(),
                profileId = response.getString(LocalModelInferenceProtocol.PROFILE_ID).orEmpty(),
                backend = response.getString(LocalModelInferenceProtocol.BACKEND).orEmpty(),
                smeAvailable = response.getBoolean(LocalModelInferenceProtocol.SME_AVAILABLE),
                elapsedMillis = response.getLong(LocalModelInferenceProtocol.ELAPSED_MILLIS),
                preparationMillis = response.getLong(LocalModelInferenceProtocol.PREPARATION_MILLIS),
                totalElapsedMillis = response.getLong(LocalModelInferenceProtocol.TOTAL_ELAPSED_MILLIS),
                timeToFirstTokenMillis = response.getDouble(
                    LocalModelInferenceProtocol.TIME_TO_FIRST_TOKEN_MILLIS
                ),
                promptTokens = response.getLong(LocalModelInferenceProtocol.PROMPT_TOKENS),
                generatedTokens = response.getLong(LocalModelInferenceProtocol.GENERATED_TOKENS),
                prefillTokensPerSecond = response.getDouble(
                    LocalModelInferenceProtocol.PREFILL_TOKENS_PER_SECOND
                ),
                decodeTokensPerSecond = response.getDouble(
                    LocalModelInferenceProtocol.DECODE_TOKENS_PER_SECOND
                ),
                stopReason = response.getString(LocalModelInferenceProtocol.STOP_REASON).orEmpty()
            )
        } finally {
            // The service unloads the model before returning the response. Do not retain a stale
            // profile or a bound helper process after an interactive turn has completed.
            disconnect()
        }
    }

    fun release() {
        val context = applicationContext ?: return
        try {
            if (remote != null) {
                runCatching {
                    requireSuccess(transact(context, LocalModelInferenceProtocol.RELEASE, Bundle()))
                }
            }
        } finally {
            disconnect()
        }
    }

    fun loadedProfileId(): String = remoteLoadedProfileId

    private fun transact(context: Context, what: Int, payload: Bundle): Bundle {
        val requestId = requestIds.getAndIncrement()
        payload.putLong(LocalModelInferenceProtocol.REQUEST_ID, requestId)
        val request = PendingRequest()
        pending[requestId] = request
        val target = try {
            ensureConnected(context)
        } catch (error: Throwable) {
            pending.remove(requestId)
            throw error
        }
        try {
            target.send(Message.obtain(null, what).apply {
                data = payload
                replyTo = replyMessenger
            })
        } catch (error: RemoteException) {
            pending.remove(requestId)
            handleConnectionLoss("The local model runtime connection was lost")
            throw IllegalStateException("The local model runtime could not start", error)
        }
        synchronized(request.monitor) {
            while (request.response == null && request.failure == null) {
                request.monitor.wait()
            }
        }
        request.failure?.let { throw IllegalStateException(it.message, it) }
        return checkNotNull(request.response)
    }

    private fun ensureConnected(context: Context): Messenger {
        applicationContext = context.applicationContext
        synchronized(connectionMonitor) {
            remote?.let { return it }
            if (!binding) {
                binding = true
                val bound = context.applicationContext.bindService(
                    Intent(context, LocalModelInferenceService::class.java),
                    connection,
                    Context.BIND_AUTO_CREATE or Context.BIND_IMPORTANT
                )
                if (!bound) {
                    binding = false
                    throw IllegalStateException("The local model runtime service is unavailable")
                }
            }
            val deadline = System.currentTimeMillis() + SERVICE_BIND_TIMEOUT_MILLIS
            while (remote == null && binding) {
                val remaining = deadline - System.currentTimeMillis()
                if (remaining <= 0L) break
                connectionMonitor.wait(remaining)
            }
            return remote ?: throw IllegalStateException("The local model runtime service did not start")
        }
    }

    private fun handleConnectionLoss(message: String) {
        synchronized(connectionMonitor) {
            remote = null
            binding = false
            remoteLoadedProfileId = ""
            connectionMonitor.notifyAll()
        }
        val error = IllegalStateException(message)
        pending.values.forEach { request ->
            synchronized(request.monitor) {
                request.failure = error
                request.monitor.notifyAll()
            }
        }
        pending.clear()
    }

    private fun disconnect() {
        val context = applicationContext
        synchronized(connectionMonitor) {
            if (context != null && (remote != null || binding)) {
                runCatching { context.unbindService(connection) }
            }
            remote = null
            binding = false
            remoteLoadedProfileId = ""
            connectionMonitor.notifyAll()
        }
    }

    private fun requireSuccess(response: Bundle) {
        check(response.getBoolean(LocalModelInferenceProtocol.SUCCESS)) {
            response.getString(LocalModelInferenceProtocol.ERROR)
                ?.takeIf(String::isNotBlank)
                ?: "The local model runtime failed"
        }
    }

    private const val SERVICE_BIND_TIMEOUT_MILLIS = 15_000L
}
