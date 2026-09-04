package com.galaxyssi.chat.voice.audio

class PcmRingBuffer(capacitySamples: Int) {
    private val samples = ShortArray(capacitySamples.coerceAtLeast(1))
    private var totalWritten = 0L

    val capacity: Int
        get() = samples.size

    @Synchronized
    fun append(source: ShortArray, count: Int): LongRange {
        val safeCount = count.coerceIn(0, source.size)
        val start = totalWritten
        val sourceStart = (safeCount - samples.size).coerceAtLeast(0)
        var sourceOffset = sourceStart
        var absolute = totalWritten + sourceStart
        while (sourceOffset < safeCount) {
            val ringIndex = (absolute % samples.size).toInt()
            val chunk = minOf(safeCount - sourceOffset, samples.size - ringIndex)
            source.copyInto(samples, ringIndex, sourceOffset, sourceOffset + chunk)
            sourceOffset += chunk
            absolute += chunk
        }
        totalWritten += safeCount
        return start until totalWritten
    }

    @Synchronized
    fun retainedStartSample(): Long = (totalWritten - samples.size).coerceAtLeast(0L)

    @Synchronized
    fun endSampleExclusive(): Long = totalWritten

    @Synchronized
    fun clear() {
        samples.fill(0)
        totalWritten = 0L
    }

    @Synchronized
    fun snapshot(startSample: Long, endSampleExclusive: Long): ShortArray {
        val retainedStart = retainedStartSample()
        val start = startSample.coerceIn(retainedStart, totalWritten)
        val end = endSampleExclusive.coerceIn(start, totalWritten)
        val count = (end - start).toInt()
        if (count == 0) return ShortArray(0)
        val output = ShortArray(count)
        var outputOffset = 0
        var absolute = start
        while (outputOffset < count) {
            val ringIndex = (absolute % samples.size).toInt()
            val chunk = minOf(count - outputOffset, samples.size - ringIndex)
            samples.copyInto(output, outputOffset, ringIndex, ringIndex + chunk)
            outputOffset += chunk
            absolute += chunk
        }
        return output
    }
}

data class SegmentRange(
    val preRollMs: Int = 300,
    val postRollMs: Int = 400,
    val includeAllWhenSpeechMissing: Boolean = true
)

interface SpeechSegmentStore {
    fun append(frame: AudioFrame)
    fun markSpeechStart(sequence: Long)
    fun markSpeechEnd(sequence: Long)
    fun snapshot(segment: SegmentRange = SegmentRange()): PcmSnapshot
    fun snapshotWindow(maxDurationMs: Long, segment: SegmentRange = SegmentRange()): PcmSnapshot
    fun trimBefore(sequence: Long)
    fun clear()
}

class InMemorySpeechSegmentStore(
    private val sampleRateHz: Int,
    maxDurationMs: Long
) : SpeechSegmentStore {
    private val ring = PcmRingBuffer(
        (sampleRateHz.toLong() * maxDurationMs / 1_000L).toInt().coerceAtLeast(sampleRateHz)
    )
    private val sequenceOffsets = LinkedHashMap<Long, LongRange>()
    private var speechStartSample: Long? = null
    private var speechEndSampleExclusive: Long? = null

    @Synchronized
    override fun append(frame: AudioFrame) {
        val range = ring.append(frame.samples, frame.validSamples)
        sequenceOffsets[frame.sequence] = range
        while (sequenceOffsets.size > MAX_SEQUENCE_INDEX_SIZE) {
            sequenceOffsets.remove(sequenceOffsets.keys.first())
        }
    }

    @Synchronized
    override fun markSpeechStart(sequence: Long) {
        val range = sequenceOffsets[sequence] ?: return
        if (speechStartSample == null) speechStartSample = range.first
        speechEndSampleExclusive = null
    }

    @Synchronized
    override fun markSpeechEnd(sequence: Long) {
        val range = sequenceOffsets[sequence] ?: return
        speechEndSampleExclusive = range.first.coerceAtLeast(speechStartSample ?: range.first)
    }

    @Synchronized
    override fun snapshot(segment: SegmentRange): PcmSnapshot {
        val (start, end) = snapshotBounds(segment)
        return snapshot(start, end)
    }

    @Synchronized
    override fun snapshotWindow(maxDurationMs: Long, segment: SegmentRange): PcmSnapshot {
        require(maxDurationMs > 0L)
        val (segmentStart, end) = snapshotBounds(segment)
        val windowSamples = maxDurationMs * sampleRateHz / 1_000L
        val start = (end - windowSamples).coerceAtLeast(segmentStart)
        return snapshot(start, end)
    }

    private fun snapshotBounds(segment: SegmentRange): Pair<Long, Long> {
        val retainedStart = ring.retainedStartSample()
        val retainedEnd = ring.endSampleExclusive()
        val start = speechStartSample?.let {
            it - segment.preRollMs.toLong() * sampleRateHz / 1_000L
        }?.coerceAtLeast(retainedStart) ?: if (segment.includeAllWhenSpeechMissing) retainedStart else retainedEnd
        val end = speechEndSampleExclusive?.let {
            it + segment.postRollMs.toLong() * sampleRateHz / 1_000L
        }?.coerceAtMost(retainedEnd) ?: retainedEnd
        return start to end
    }

    private fun snapshot(start: Long, end: Long): PcmSnapshot {
        return PcmSnapshot(
            samples = ring.snapshot(start, end),
            sampleRateHz = sampleRateHz,
            speechDetected = speechStartSample != null,
            speechStartSample = speechStartSample,
            speechEndSampleExclusive = speechEndSampleExclusive,
            captureStartSample = start,
            captureEndSampleExclusive = end
        )
    }

    @Synchronized
    override fun trimBefore(sequence: Long) {
        val trimSample = sequenceOffsets[sequence]?.first ?: return
        sequenceOffsets.entries.removeAll { it.value.last < trimSample }
        if ((speechStartSample ?: Long.MAX_VALUE) < trimSample) speechStartSample = trimSample
    }

    @Synchronized
    override fun clear() {
        sequenceOffsets.clear()
        speechStartSample = null
        speechEndSampleExclusive = null
        ring.clear()
    }

    private companion object {
        const val MAX_SEQUENCE_INDEX_SIZE = 4_096
    }
}
