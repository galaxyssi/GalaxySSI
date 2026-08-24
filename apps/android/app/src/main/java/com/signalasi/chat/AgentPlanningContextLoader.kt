package com.signalasi.chat

import java.util.concurrent.ExecutionException
import java.util.concurrent.ExecutorCompletionService
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.atomic.AtomicInteger

internal data class AgentPlanningContextInputs(
    val targets: List<AgentCallableTarget>,
    val registrations: List<AgentRegistration>,
    val memories: List<AgentMemoryItem>,
    val knowledge: AgentKnowledgeQuerySnapshot,
    val timing: AgentPlanningContextTiming
)

internal data class AgentPlanningContextTiming(
    val totalMillis: Long,
    val connectorsMillis: Long,
    val memoriesMillis: Long,
    val knowledgeMillis: Long
)

internal object AgentPlanningContextLoader {
    private val threadCounter = AtomicInteger()
    private val executor = Executors.newFixedThreadPool(3) { runnable ->
        Thread(runnable, "signalasi-planning-${threadCounter.incrementAndGet()}").apply {
            isDaemon = true
        }
    }

    fun load(
        connectorsProvider: () -> AgentConnectorPlanningSnapshot,
        memoriesProvider: () -> List<AgentMemoryItem>,
        knowledgeProvider: () -> AgentKnowledgeQuerySnapshot
    ): AgentPlanningContextInputs {
        val startedAt = System.nanoTime()
        val completion = ExecutorCompletionService<PlanningSourceResult>(executor)
        val futures = listOf(
            completion.submit { connectorsProvider.measure(::ConnectorsResult) },
            completion.submit { memoriesProvider.measure(::MemoriesResult) },
            completion.submit { knowledgeProvider.measure(::KnowledgeResult) }
        )

        return try {
            var connectorResult: ConnectorsResult? = null
            var memoryResult: MemoriesResult? = null
            var knowledgeResult: KnowledgeResult? = null
            repeat(futures.size) {
                when (val result = completion.take().awaitResult()) {
                    is ConnectorsResult -> connectorResult = result
                    is MemoriesResult -> memoryResult = result
                    is KnowledgeResult -> knowledgeResult = result
                }
            }
            val loadedConnectors = checkNotNull(connectorResult)
            val loadedMemories = checkNotNull(memoryResult)
            val loadedKnowledge = checkNotNull(knowledgeResult)
            AgentPlanningContextInputs(
                targets = loadedConnectors.value.targets,
                registrations = loadedConnectors.value.registrations,
                memories = loadedMemories.value,
                knowledge = loadedKnowledge.value,
                timing = AgentPlanningContextTiming(
                    totalMillis = startedAt.elapsedMillis(),
                    connectorsMillis = loadedConnectors.elapsedMillis,
                    memoriesMillis = loadedMemories.elapsedMillis,
                    knowledgeMillis = loadedKnowledge.elapsedMillis
                )
            )
        } catch (failure: InterruptedException) {
            futures.forEach { it.cancel(true) }
            Thread.currentThread().interrupt()
            throw failure
        } catch (failure: Throwable) {
            futures.forEach { it.cancel(true) }
            throw failure
        }
    }

    private fun <T, R : PlanningSourceResult> (() -> T).measure(
        result: (T, Long) -> R
    ): R {
        val startedAt = System.nanoTime()
        return result(invoke(), startedAt.elapsedMillis())
    }

    private fun Future<PlanningSourceResult>.awaitResult(): PlanningSourceResult = try {
        get()
    } catch (failure: ExecutionException) {
        throw failure.cause ?: failure
    }

    private fun Long.elapsedMillis(): Long =
        ((System.nanoTime() - this) / NANOS_PER_MILLISECOND).coerceAtLeast(0L)

    private sealed interface PlanningSourceResult {
        val elapsedMillis: Long
    }

    private data class ConnectorsResult(
        val value: AgentConnectorPlanningSnapshot,
        override val elapsedMillis: Long
    ) : PlanningSourceResult

    private data class MemoriesResult(
        val value: List<AgentMemoryItem>,
        override val elapsedMillis: Long
    ) : PlanningSourceResult

    private data class KnowledgeResult(
        val value: AgentKnowledgeQuerySnapshot,
        override val elapsedMillis: Long
    ) : PlanningSourceResult

    private const val NANOS_PER_MILLISECOND = 1_000_000L
}
