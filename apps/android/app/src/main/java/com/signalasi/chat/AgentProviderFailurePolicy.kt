package com.signalasi.chat

import com.signalasi.chat.voice.modelstream.ModelStreamError
import java.util.Locale

internal enum class AgentProviderFailureClass {
    PERMANENT_CREDENTIAL,
    PERMANENT_BILLING,
    PERMANENT_MODEL,
    TRANSIENT,
    UNKNOWN
}

internal data class AgentProviderFailure(
    val failureClass: AgentProviderFailureClass,
    val retryable: Boolean
) {
    val permanent: Boolean
        get() = failureClass in setOf(
            AgentProviderFailureClass.PERMANENT_CREDENTIAL,
            AgentProviderFailureClass.PERMANENT_BILLING,
            AgentProviderFailureClass.PERMANENT_MODEL
        )
}

internal data class AgentProviderAttemptProfile(
    val maxAttempts: Int,
    val connectTimeoutMillis: Long,
    val readTimeoutMillis: Long
) {
    init {
        require(maxAttempts > 0)
        require(connectTimeoutMillis > 0L)
        require(readTimeoutMillis > 0L)
    }
}

/** Keeps provider failures from turning an Auto-routed run into a retry loop. */
internal object AgentProviderFailurePolicy {
    const val MAX_AUTO_FAILURES_PER_RESOURCE = 5

    fun attemptProfile(
        manuallyLocked: Boolean,
        hasAlternativeResource: Boolean,
        supervisedProject: Boolean
    ): AgentProviderAttemptProfile = when {
        manuallyLocked || !hasAlternativeResource -> PATIENT_SINGLE_RESOURCE_PROFILE
        supervisedProject -> SUPERVISED_AUTO_FAILOVER_PROFILE
        else -> INTERACTIVE_AUTO_FAILOVER_PROFILE
    }

    fun classify(error: ModelStreamError?): AgentProviderFailure = classify(
        code = error?.code.orEmpty(),
        message = error?.message.orEmpty(),
        httpStatus = error?.httpStatus,
        providerRetryable = error?.retryable
    )

    fun classify(
        code: String = "",
        message: String = "",
        httpStatus: Int? = null,
        providerRetryable: Boolean? = null
    ): AgentProviderFailure {
        val normalized = "$code $message".lowercase(Locale.ROOT)
        val failureClass = when {
            normalized.containsAny(
                "insufficient balance", "insufficient_balance", "insufficient quota",
                "quota exhausted", "billing", "payment required", "account balance"
            ) -> AgentProviderFailureClass.PERMANENT_BILLING
            httpStatus == 401 || normalized.containsAny(
                "invalid api key", "invalid_api_key", "authentication failed",
                "unauthorized", "credential revoked", "api key expired"
            ) -> AgentProviderFailureClass.PERMANENT_CREDENTIAL
            normalized.containsAny(
                "model not found", "model_not_found", "model retired", "model deprecated",
                "unsupported model"
            ) -> AgentProviderFailureClass.PERMANENT_MODEL
            providerRetryable == true || httpStatus == 408 || httpStatus == 429 ||
                (httpStatus != null && httpStatus >= 500) -> AgentProviderFailureClass.TRANSIENT
            else -> AgentProviderFailureClass.UNKNOWN
        }
        return AgentProviderFailure(
            failureClass = failureClass,
            retryable = when {
                failureClass in setOf(
                    AgentProviderFailureClass.PERMANENT_CREDENTIAL,
                    AgentProviderFailureClass.PERMANENT_BILLING,
                    AgentProviderFailureClass.PERMANENT_MODEL
                ) -> false
                failureClass == AgentProviderFailureClass.TRANSIENT -> true
                else -> providerRetryable == true
            }
        )
    }

    fun classify(message: String): AgentProviderFailure = classify(
        code = "",
        message = message,
        httpStatus = null,
        providerRetryable = null
    )

    fun shouldRetrySameResource(
        failure: AgentProviderFailure,
        failureCount: Int,
        profile: AgentProviderAttemptProfile = PATIENT_SINGLE_RESOURCE_PROFILE
    ): Boolean = !failure.permanent && failureCount < profile.maxAttempts

    fun retryDelayMillis(failureCount: Int): Long = when (failureCount.coerceAtLeast(1)) {
        1 -> 250L
        2 -> 500L
        3 -> 1_000L
        else -> 2_000L
    }

    private fun String.containsAny(vararg terms: String): Boolean = terms.any(::contains)

    private val INTERACTIVE_AUTO_FAILOVER_PROFILE = AgentProviderAttemptProfile(
        maxAttempts = 2,
        connectTimeoutMillis = 10_000L,
        readTimeoutMillis = 15_000L
    )
    private val SUPERVISED_AUTO_FAILOVER_PROFILE = AgentProviderAttemptProfile(
        maxAttempts = 2,
        connectTimeoutMillis = 15_000L,
        readTimeoutMillis = 60_000L
    )
    private val PATIENT_SINGLE_RESOURCE_PROFILE = AgentProviderAttemptProfile(
        maxAttempts = MAX_AUTO_FAILURES_PER_RESOURCE,
        connectTimeoutMillis = 20_000L,
        readTimeoutMillis = 300_000L
    )
}
