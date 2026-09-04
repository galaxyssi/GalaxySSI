package com.galaxyssi.chat.voice.asr.online

import com.galaxyssi.chat.voice.asr.AsrProvider
import com.galaxyssi.chat.voice.asr.AsrSession
import com.galaxyssi.chat.voice.asr.AsrSessionConfig
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class RealtimeAsrPreconnector(
    private val provider: AsrProvider,
    private val nowEpochMs: () -> Long = System::currentTimeMillis,
    private val idleTtlMs: Long = 30_000L
) : AutoCloseable {
    private data class Prepared(
        val key: String,
        val session: AsrSession,
        val expiresAtEpochMs: Long
    )

    private val mutex = Mutex()
    private var prepared: Prepared? = null

    init {
        require(idleTtlMs in 1_000L..120_000L)
    }

    suspend fun preconnect(config: AsrSessionConfig): Boolean = mutex.withLock {
        removeExpiredLocked()
        val key = key(config)
        if (prepared?.key == key) return@withLock true
        prepared?.session?.close()
        prepared = null
        val available = provider.isAvailable(config)
        if (!available.available) return@withLock false
        val session = provider.createSession(config)
        return@withLock runCatching {
            session.start()
            prepared = Prepared(key, session, nowEpochMs() + idleTtlMs)
            true
        }.getOrElse {
            session.close()
            false
        }
    }

    suspend fun acquire(config: AsrSessionConfig): AsrSession = mutex.withLock {
        removeExpiredLocked()
        val key = key(config)
        prepared?.takeIf { it.key == key }?.let {
            prepared = null
            return@withLock it.session
        }
        provider.createSession(config).also { it.start() }
    }

    suspend fun discard() = mutex.withLock {
        prepared?.session?.close()
        prepared = null
    }

    override fun close() {
        prepared?.session?.close()
        prepared = null
    }

    private fun removeExpiredLocked() {
        val current = prepared ?: return
        if (current.expiresAtEpochMs <= nowEpochMs()) {
            current.session.close()
            prepared = null
        }
    }

    private fun key(config: AsrSessionConfig): String = listOf(
        config.voiceSessionId,
        config.transcriptId,
        config.language,
        config.networkType.name,
        config.privacy.hashCode().toString()
    ).joinToString(":")
}
