package com.galaxyssi.chat.voice.correction

import com.galaxyssi.chat.voice.TranscriptHypothesis
import com.galaxyssi.chat.voice.model.WhisperExecutionMode
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import java.util.concurrent.ConcurrentHashMap

data class VoiceSecondPassRequest(
    val sessionId: String,
    val pcm16: ShortArray,
    val sampleRateHz: Int,
    val language: String,
    val fast: TranscriptHypothesis,
    val accurateProfileId: String,
    val accurateModelSha256: String,
    val mode: WhisperExecutionMode = WhisperExecutionMode.SECOND_PASS,
    val requestedAtMillis: Long = System.currentTimeMillis()
) {
    init {
        require(sessionId.isNotBlank())
        require(pcm16.isNotEmpty())
        require(sampleRateHz == 16_000)
        require(accurateProfileId.isNotBlank())
        require(accurateModelSha256.matches(Regex("[0-9a-f]{64}")))
        require(mode == WhisperExecutionMode.SECOND_PASS || mode == WhisperExecutionMode.FINAL_ONLY)
    }

    fun frozenCopy(): VoiceSecondPassRequest = copy(pcm16 = pcm16.copyOf())
}

data class VoiceSecondPassMetadata(
    val sessionId: String,
    val fast: TranscriptHypothesis,
    val accurateProfileId: String,
    val accurateModelSha256: String,
    val mode: WhisperExecutionMode,
    val requestedAtMillis: Long
)

data class VoiceSecondPassResult(
    val metadata: VoiceSecondPassMetadata,
    val accurate: TranscriptHypothesis,
    val diff: TranscriptDiff,
    val decision: CorrectionDecision,
    val completedAtMillis: Long
)

class VoiceSecondPassCoordinator(
    private val correctionController: TranscriptCorrectionController = DefaultTranscriptCorrectionController(),
    private val entityChecker: EntityConsistencyChecker = DefaultEntityConsistencyChecker,
    private val clock: () -> Long = System::currentTimeMillis
) {
    private val jobs = ConcurrentHashMap<String, Job>()

    fun schedule(
        scope: CoroutineScope,
        request: VoiceSecondPassRequest,
        executionLedger: VoiceExecutionLedger,
        decoder: suspend (VoiceSecondPassRequest) -> TranscriptHypothesis,
        onResult: (VoiceSecondPassResult) -> Unit,
        onFailure: (Throwable) -> Unit = {}
    ): Boolean {
        val frozen = request.frozenCopy()
        if (jobs.containsKey(frozen.sessionId)) return false
        val job = scope.launch(start = CoroutineStart.LAZY) {
            try {
                val accurate = decoder(frozen)
                require(accurate.text.isNotBlank()) { "Accurate transcription is empty" }
                val recordBeforeCorrection = executionLedger.snapshot(frozen.sessionId) ?: return@launch
                val decision = correctionController.compare(frozen.fast, accurate, recordBeforeCorrection)
                if (!executionLedger.acceptCorrectionRevision(frozen.sessionId, accurate.revision)) return@launch
                val consistency = entityChecker.compare(frozen.fast.text, accurate.text)
                val diff = TranscriptDiff(
                    fastText = frozen.fast.text.trim(),
                    accurateText = accurate.text.trim(),
                    normalizedFastText = frozen.fast.text.normalizedTranscript(),
                    normalizedAccurateText = accurate.text.normalizedTranscript(),
                    entityDifferences = consistency.differences
                )
                onResult(
                    VoiceSecondPassResult(
                        metadata = VoiceSecondPassMetadata(
                            sessionId = frozen.sessionId,
                            fast = frozen.fast,
                            accurateProfileId = frozen.accurateProfileId,
                            accurateModelSha256 = frozen.accurateModelSha256,
                            mode = frozen.mode,
                            requestedAtMillis = frozen.requestedAtMillis
                        ),
                        accurate = accurate,
                        diff = diff,
                        decision = decision,
                        completedAtMillis = clock()
                    )
                )
            } catch (_: CancellationException) {
                // A new foreground utterance is expected to preempt background accuracy work.
            } catch (error: Throwable) {
                onFailure(error)
            } finally {
                jobs.remove(frozen.sessionId)
                frozen.pcm16.fill(0)
            }
        }
        if (jobs.putIfAbsent(frozen.sessionId, job) != null) {
            job.cancel()
            frozen.pcm16.fill(0)
            return false
        }
        job.invokeOnCompletion { jobs.remove(frozen.sessionId, job) }
        job.start()
        return true
    }

    fun cancel(sessionId: String): Boolean = jobs.remove(sessionId)?.let { job ->
        job.cancel(CancellationException("Second pass preempted"))
        true
    } ?: false

    fun cancelForInteractiveVoice(): Int {
        val active = jobs.entries.toList()
        active.forEach { (sessionId, job) ->
            jobs.remove(sessionId, job)
            job.cancel(CancellationException("New interactive voice session"))
        }
        return active.size
    }

    fun activeSessionIds(): Set<String> = jobs.keys.toSet()
}
