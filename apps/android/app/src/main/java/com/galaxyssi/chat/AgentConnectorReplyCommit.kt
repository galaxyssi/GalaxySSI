package com.galaxyssi.chat

/** Ordered, replayable commits, not an atomic transaction spanning the three stores. */
internal object AgentConnectorReplyCommit {
    fun run(
        checkpoint: () -> Unit,
        project: () -> Unit,
        completeDelivery: () -> Unit,
        bindContinuation: () -> Unit,
        retire: () -> Unit
    ) {
        checkpoint()
        project()
        completeDelivery()
        bindContinuation()
        retire()
    }
}
