package com.signalasi.chat

import java.net.URI
import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.Callable
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorCompletionService
import java.util.concurrent.Executors
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit
import kotlin.math.max
import kotlin.math.min

internal data class AgentWebEvidenceFetchedDocument(
    val document: AgentWebIntelligenceDocument,
    val receipt: AgentWebIntelligenceReceipt
)

internal data class AgentWebEvidenceReadBatch(
    val documents: List<AgentWebIntelligenceDocument>,
    val receipts: List<AgentNativeJsonObject>,
    val candidateCount: Int,
    val completedCount: Int,
    val domainCount: Int,
    val sufficient: Boolean,
    val earlyCompleted: Boolean,
    val completionReason: String,
    val elapsedMillis: Long
)

private data class AgentWebEvidenceReadOutcome(
    val index: Int,
    val document: AgentWebIntelligenceDocument? = null,
    val receipt: AgentWebIntelligenceReceipt
)

internal object AgentWebEvidenceCompletionPolicy {
    private const val MIN_SUBSTANTIAL_CONTENT_CHARS = 600

    fun hasSufficientEvidence(
        documents: Collection<AgentWebIntelligenceDocument>,
        evidenceLimit: Int
    ): Boolean {
        val requiredDocuments = min(evidenceLimit.coerceAtLeast(2), 4)
        if (documents.size < requiredDocuments) return false
        val substantial = documents.count { it.content.length >= MIN_SUBSTANTIAL_CONTENT_CHARS }
        if (substantial < requiredDocuments) return false
        val independentDomains = documents.mapNotNull { document ->
            runCatching { URI(document.url).host?.lowercase(Locale.ROOT) }.getOrNull()
        }.filter(String::isNotBlank).toSet().size
        val requiredDomains = min(requiredDocuments, 3)
        val evidenceChars = documents.sumOf { it.content.length.coerceAtMost(2_500) }
        return independentDomains >= requiredDomains &&
            evidenceChars >= requiredDocuments * MIN_SUBSTANTIAL_CONTENT_CHARS
    }
}

internal fun readAgentWebEvidence(
    results: Collection<AgentNativeJsonObject>,
    evidenceLimit: Int,
    parallelism: Int,
    perHostParallelism: Int,
    timeoutMillis: Long,
    maxRequestTimeoutMillis: Long = 12_000L,
    earlyComplete: Boolean,
    cancellationToken: AgentNativeToolCancellationToken,
    checkpoint: () -> Unit,
    fetchDocument: (
        url: String,
        timeoutMillis: Long,
        cancellationToken: AgentNativeToolCancellationToken,
        checkpoint: () -> Unit
    ) -> AgentWebEvidenceFetchedDocument
): AgentWebEvidenceReadBatch {
    val candidateLimit = min(24, max(evidenceLimit * 2, evidenceLimit + parallelism))
    val seen = linkedSetOf<String>()
    val candidates = results.mapNotNull { result ->
        val rawUrl = result["url"]?.toString().orEmpty()
        if (rawUrl.isBlank()) return@mapNotNull null
        val canonical = runCatching { AgentWebIntelligenceText.canonicalUrl(rawUrl) }.getOrNull()
            ?: return@mapNotNull null
        canonical.takeIf(seen::add)
    }.take(candidateLimit)
    if (candidates.isEmpty()) return emptyEvidenceReadBatch()

    val startedNanos = System.nanoTime()
    val deadlineNanos = startedNanos + TimeUnit.MILLISECONDS.toNanos(timeoutMillis)
    val workerCount = min(parallelism, candidates.size).coerceAtLeast(1)
    val executor = Executors.newFixedThreadPool(workerCount) { runnable ->
        Thread(runnable, "signalasi-web-evidence").apply { isDaemon = true }
    }
    val completion = ExecutorCompletionService<AgentWebEvidenceReadOutcome>(executor)
    val hostGates = ConcurrentHashMap<String, Semaphore>()
    val localCancellation = AgentNativeToolCancellationSource()
    val parentRegistration = cancellationToken.invokeOnCancellation(localCancellation::cancel)
    val documents = linkedMapOf<Int, AgentWebIntelligenceDocument>()
    val receiptByIndex = linkedMapOf<Int, AgentNativeJsonObject>()
    var completedCount = 0
    var completionReason = "all_candidates_read"
    var earlyCompleted = false

    try {
        candidates.forEachIndexed { index, url ->
            completion.submit(Callable {
                readCandidate(
                    index = index,
                    url = url,
                    deadlineNanos = deadlineNanos,
                    maxRequestTimeoutMillis = maxRequestTimeoutMillis,
                    perHostParallelism = perHostParallelism,
                    hostGates = hostGates,
                    cancellationToken = localCancellation.token,
                    checkpoint = checkpoint,
                    fetchDocument = fetchDocument
                )
            })
        }

        while (completedCount < candidates.size) {
            if (cancellationToken.isCancellationRequested) throw AgentNativeToolCancelledException()
            checkpoint()
            val waitMillis = remainingMillis(deadlineNanos)
            if (waitMillis <= 0L) {
                completionReason = "shared_deadline"
                break
            }
            val future = completion.poll(waitMillis, TimeUnit.MILLISECONDS)
            if (future == null) {
                completionReason = "shared_deadline"
                break
            }
            val outcome = future.get()
            completedCount += 1
            receiptByIndex[outcome.index] = outcome.receipt.publicValue()
            outcome.document?.let { documents[outcome.index] = it }
            val rankedDocuments = documents.toSortedMap().values.take(evidenceLimit)
            val sufficient = AgentWebEvidenceCompletionPolicy.hasSufficientEvidence(
                rankedDocuments,
                evidenceLimit
            )
            if (rankedDocuments.size >= evidenceLimit) {
                completionReason = "evidence_limit_reached"
                earlyCompleted = completedCount < candidates.size
                break
            }
            if (earlyComplete && sufficient) {
                completionReason = "sufficient_diverse_evidence"
                earlyCompleted = completedCount < candidates.size
                break
            }
        }
    } finally {
        localCancellation.cancel()
        parentRegistration.dispose()
        executor.shutdownNow()
    }

    candidates.indices.filterNot(receiptByIndex::containsKey).forEach { index ->
        receiptByIndex[index] = unfinishedReceipt(candidates[index], completionReason).publicValue()
    }
    val rankedDocuments = documents.toSortedMap().values.take(evidenceLimit)
    val sufficient = AgentWebEvidenceCompletionPolicy.hasSufficientEvidence(rankedDocuments, evidenceLimit)
    val domains = rankedDocuments.mapNotNull { document ->
        runCatching { URI(document.url).host?.lowercase(Locale.ROOT) }.getOrNull()
    }.filter(String::isNotBlank).toSet().size
    return AgentWebEvidenceReadBatch(
        documents = rankedDocuments,
        receipts = receiptByIndex.toSortedMap().values.toList(),
        candidateCount = candidates.size,
        completedCount = completedCount,
        domainCount = domains,
        sufficient = sufficient,
        earlyCompleted = earlyCompleted,
        completionReason = completionReason,
        elapsedMillis = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startedNanos)
    )
}

private fun readCandidate(
    index: Int,
    url: String,
    deadlineNanos: Long,
    maxRequestTimeoutMillis: Long,
    perHostParallelism: Int,
    hostGates: ConcurrentHashMap<String, Semaphore>,
    cancellationToken: AgentNativeToolCancellationToken,
    checkpoint: () -> Unit,
    fetchDocument: (
        String,
        Long,
        AgentNativeToolCancellationToken,
        () -> Unit
    ) -> AgentWebEvidenceFetchedDocument
): AgentWebEvidenceReadOutcome {
    val host = runCatching { URI(url).host?.lowercase(Locale.ROOT) }.getOrNull().orEmpty()
    val gate = hostGates.computeIfAbsent(host) { Semaphore(perHostParallelism, true) }
    val waitMillis = remainingMillis(deadlineNanos)
    if (waitMillis <= 0L || !gate.tryAcquire(waitMillis, TimeUnit.MILLISECONDS)) {
        return AgentWebEvidenceReadOutcome(index, receipt = sharedDeadlineReceipt(url))
    }
    return try {
        if (cancellationToken.isCancellationRequested) throw AgentNativeToolCancelledException()
        val requestTimeout = min(
            maxRequestTimeoutMillis.coerceAtLeast(1_000L),
            remainingMillis(deadlineNanos)
        ).coerceAtLeast(1_000L)
        val fetched = fetchDocument(url, requestTimeout, cancellationToken) {
            if (cancellationToken.isCancellationRequested) throw AgentNativeToolCancelledException()
            checkpoint()
        }
        AgentWebEvidenceReadOutcome(index, fetched.document, fetched.receipt)
    } catch (error: Exception) {
        AgentWebEvidenceReadOutcome(index, receipt = evidenceErrorReceipt(url, error))
    } finally {
        gate.release()
    }
}

private fun unfinishedReceipt(url: String, completionReason: String): AgentWebIntelligenceReceipt =
    if (completionReason == "shared_deadline") {
        sharedDeadlineReceipt(url)
    } else {
        AgentWebIntelligenceReceipt(
            sourceId = evidenceSourceId(url),
            status = "cancelled",
            durationMillis = 0L,
            resultCount = 0,
            errorCode = "sufficient_evidence",
            errorMessage = "Evidence target was met before this page was needed"
        )
    }

private fun sharedDeadlineReceipt(url: String) = AgentWebIntelligenceReceipt(
    sourceId = evidenceSourceId(url),
    status = "timeout",
    durationMillis = 0L,
    resultCount = 0,
    errorCode = "shared_deadline",
    errorMessage = "Shared evidence-read deadline elapsed",
    retryable = true
)

private fun evidenceErrorReceipt(url: String, error: Throwable): AgentWebIntelligenceReceipt {
    val webError = error as? AgentWebMediaException
    val code = when (error) {
        is AgentNativeToolCancelledException -> "cancelled"
        is AgentNativeToolTimeoutException -> "timeout"
        else -> webError?.code ?: "fetch_failed"
    }
    return AgentWebIntelligenceReceipt(
        sourceId = evidenceSourceId(url),
        status = when {
            code == "cancelled" -> "cancelled"
            code.contains("timeout") -> "timeout"
            code.contains("private") -> "blocked"
            else -> "failed"
        },
        durationMillis = 0L,
        resultCount = 0,
        errorCode = code,
        errorMessage = error.message.orEmpty(),
        retryable = webError?.retryable ?: (error is AgentNativeToolTimeoutException)
    )
}

private fun emptyEvidenceReadBatch() = AgentWebEvidenceReadBatch(
    documents = emptyList(),
    receipts = emptyList(),
    candidateCount = 0,
    completedCount = 0,
    domainCount = 0,
    sufficient = false,
    earlyCompleted = false,
    completionReason = "no_candidates",
    elapsedMillis = 0L
)

private fun evidenceSourceId(url: String): String = "research:${sha256EvidenceUrl(url).take(12)}"

private fun sha256EvidenceUrl(value: String): String = MessageDigest.getInstance("SHA-256")
    .digest(value.toByteArray(Charsets.UTF_8))
    .joinToString("") { "%02x".format(it) }

private fun remainingMillis(deadlineNanos: Long): Long =
    TimeUnit.NANOSECONDS.toMillis(deadlineNanos - System.nanoTime()).coerceAtLeast(0L)
