package com.galaxyssi.chat

/** Agent execution failure is not evidence that its shared Desktop transport failed. */
internal object AgentConnectorFailureScope {
    fun sharedTransportFailed(metadata: Map<String, String>): Boolean =
        metadata["delivery_failed"] == "true" ||
            metadata["timeout_stage"] == AgentConnectorTimeoutStage.NOT_ACCEPTED.name

    fun permitsFallback(metadata: Map<String, String>, candidateDomain: String): Boolean =
        !sharedTransportFailed(metadata) || metadata["failure_domain"].isNullOrBlank() ||
            candidateDomain != metadata["failure_domain"]

    fun remoteExecutionReached(metadata: Map<String, String>): Boolean =
        metadata["resource_location"] == "desktop" || metadata["resource_location"] == "peer"
}
