package com.galaxyssi.chat.voice.correction

import com.galaxyssi.chat.voice.TranscriptHypothesis
import java.text.Normalizer
import java.util.Locale

enum class VoiceCommandRisk {
    CONVERSATION,
    LOW,
    MEDIUM,
    HIGH,
    CRITICAL
}

enum class VoiceEntityType {
    RECIPIENT,
    PHONE_NUMBER,
    AMOUNT,
    DATE_TIME,
    FILE_PATH,
    APPLICATION,
    DEVICE,
    NEGATION,
    ACTION
}

data class VoiceEntity(
    val type: VoiceEntityType,
    val value: String,
    val canonicalValue: String
)

data class VoiceEntityDifference(
    val type: VoiceEntityType,
    val fastValues: List<String>,
    val accurateValues: List<String>
)

data class TranscriptDiff(
    val fastText: String,
    val accurateText: String,
    val normalizedFastText: String,
    val normalizedAccurateText: String,
    val entityDifferences: List<VoiceEntityDifference>
) {
    val changed: Boolean
        get() = normalizedFastText != normalizedAccurateText

    val hasCriticalEntityChange: Boolean
        get() = entityDifferences.any { it.type in CRITICAL_ENTITY_TYPES }

    fun compactSummary(): String = entityDifferences.joinToString("; ") { difference ->
        "${difference.type.name.lowercase(Locale.ROOT)}: " +
            "${difference.fastValues.joinToString("|").ifBlank { "-" }} -> " +
            difference.accurateValues.joinToString("|").ifBlank { "-" }
    }.ifBlank { "transcript wording changed" }

    private companion object {
        val CRITICAL_ENTITY_TYPES = setOf(
            VoiceEntityType.RECIPIENT,
            VoiceEntityType.PHONE_NUMBER,
            VoiceEntityType.AMOUNT,
            VoiceEntityType.DATE_TIME,
            VoiceEntityType.FILE_PATH,
            VoiceEntityType.APPLICATION,
            VoiceEntityType.DEVICE,
            VoiceEntityType.NEGATION,
            VoiceEntityType.ACTION
        )
    }
}

data class EntityConsistencyResult(
    val fastEntities: List<VoiceEntity>,
    val accurateEntities: List<VoiceEntity>,
    val differences: List<VoiceEntityDifference>
) {
    val consistent: Boolean
        get() = differences.isEmpty()
}

data class VoiceSecondPassTrigger(
    val requested: Boolean,
    val reasons: Set<String>
)

object VoiceSecondPassTriggerPolicy {
    fun evaluate(
        fast: TranscriptHypothesis,
        utteranceDurationMs: Long,
        userRequestedAccuracy: Boolean = false,
        meetingOrLongRecordMode: Boolean = false,
        onlineProviderUnstable: Boolean = false
    ): VoiceSecondPassTrigger {
        val reasons = linkedSetOf<String>()
        if (userRequestedAccuracy) reasons += "user_requested_accuracy"
        if (meetingOrLongRecordMode || utteranceDurationMs >= LONG_RECORD_THRESHOLD_MS) {
            reasons += "long_recording"
        }
        if (fast.confidence != null && fast.confidence < LOW_CONFIDENCE_THRESHOLD) {
            reasons += "low_confidence"
        }
        if (containsDenseProperNouns(fast.text)) reasons += "proper_nouns"
        if (onlineProviderUnstable) reasons += "online_provider_unstable"
        return VoiceSecondPassTrigger(reasons.isNotEmpty(), reasons)
    }

    private fun containsDenseProperNouns(text: String): Boolean {
        val normalized = Normalizer.normalize(text, Normalizer.Form.NFKC)
        val tokens = Regex("[\\p{L}\\p{N}_.@+-]{2,}").findAll(normalized).map { it.value }.toList()
        val namedTokens = tokens.count { token ->
            token.drop(1).any(Char::isUpperCase) ||
                (token.any(Char::isLetter) && token.any(Char::isDigit)) ||
                token.contains('.') || token.contains('@') || token.contains('_')
        }
        val quotedTerms = Regex("[\"'\\u201c\\u201d\\u300c\\u300d][^\"'\\u201c\\u201d\\u300c\\u300d]{2,48}[\"'\\u201c\\u201d\\u300c\\u300d]")
            .findAll(normalized)
            .count()
        return namedTokens >= 2 || quotedTerms >= 1
    }

    private const val LOW_CONFIDENCE_THRESHOLD = 0.72f
    private const val LONG_RECORD_THRESHOLD_MS = 15_000L
}

fun interface VoiceCommandRiskClassifier {
    fun classify(text: String): VoiceCommandRisk
}

interface EntityConsistencyChecker {
    fun extract(text: String): List<VoiceEntity>
    fun compare(fastText: String, accurateText: String): EntityConsistencyResult
}

object DefaultVoiceCommandRiskClassifier : VoiceCommandRiskClassifier {
    override fun classify(text: String): VoiceCommandRisk {
        val normalized = text.normalizedForMatching()
        return when {
            CRITICAL_PATTERNS.any { it.containsMatchIn(normalized) } -> VoiceCommandRisk.CRITICAL
            HIGH_PATTERNS.any { it.containsMatchIn(normalized) } -> VoiceCommandRisk.HIGH
            MEDIUM_PATTERNS.any { it.containsMatchIn(normalized) } -> VoiceCommandRisk.MEDIUM
            LOW_PATTERNS.any { it.containsMatchIn(normalized) } -> VoiceCommandRisk.LOW
            else -> VoiceCommandRisk.CONVERSATION
        }
    }

    private val CRITICAL_PATTERNS = patterns(
        "\\b(?:transfer money|wire money|make a payment|pay|purchase|place an order|publish publicly|factory reset|wipe all|grant admin|elevate privilege)\\b",
        "(?:\\u8f6c\\u8d26|\\u4ed8\\u6b3e|\\u652f\\u4ed8|\\u8d2d\\u4e70|\\u4e0b\\u5355|\\u516c\\u5f00\\u53d1\\u5e03|\\u6062\\u590d\\u51fa\\u5382|\\u6e05\\u7a7a\\u6240\\u6709|\\u6388\\u4e88\\u7ba1\\u7406\\u5458|\\u63d0\\u6743)"
    )
    private val HIGH_PATTERNS = patterns(
        "\\b(?:send|message|call|dial|delete|remove|overwrite|disable service|uninstall|install apk|lock device|unlock device)\\b",
        "(?:\\u53d1\\u9001|\\u53d1\\u7ed9|\\u53d1\\u6d88\\u606f|\\u6253\\u7535\\u8bdd|\\u62e8\\u6253|\\u5220\\u9664|\\u79fb\\u9664|\\u8986\\u76d6|\\u505c\\u7528\\u670d\\u52a1|\\u5378\\u8f7d|\\u5b89\\u88c5apk|\\u9501\\u5c4f|\\u89e3\\u9501)"
    )
    private val MEDIUM_PATTERNS = patterns(
        "\\b(?:draft|change settings|modify settings|download|create contact|update contact|create calendar|schedule event|start a long task)\\b",
        "(?:\\u8349\\u7a3f|\\u4fee\\u6539\\u8bbe\\u7f6e|\\u66f4\\u6539\\u8bbe\\u7f6e|\\u4e0b\\u8f7d|\\u521b\\u5efa\\u8054\\u7cfb\\u4eba|\\u4fee\\u6539\\u8054\\u7cfb\\u4eba|\\u521b\\u5efa\\u65e5\\u5386|\\u65b0\\u5efa\\u65e5\\u7a0b|\\u542f\\u52a8\\u957f\\u4efb\\u52a1)"
    )
    private val LOW_PATTERNS = patterns(
        "\\b(?:open|launch|show|query|check|volume|flashlight|timer|alarm|battery|device status)\\b",
        "(?:\\u6253\\u5f00|\\u542f\\u52a8|\\u67e5\\u770b|\\u67e5\\u8be2|\\u97f3\\u91cf|\\u624b\\u7535\\u7b52|\\u8ba1\\u65f6\\u5668|\\u95f9\\u949f|\\u7535\\u91cf|\\u8bbe\\u5907\\u72b6\\u6001)"
    )

    private fun patterns(vararg values: String): List<Regex> =
        values.map { Regex(it, setOf(RegexOption.IGNORE_CASE)) }
}

object DefaultEntityConsistencyChecker : EntityConsistencyChecker {
    override fun extract(text: String): List<VoiceEntity> {
        val normalized = Normalizer.normalize(text, Normalizer.Form.NFKC)
        return buildList {
            RECIPIENT_PATTERNS.forEach { pattern ->
                pattern.findAll(normalized).forEach { match ->
                    match.groups[1]?.value?.trim()?.trimEndPunctuation()
                        ?.takeIf(String::isNotBlank)
                        ?.let { add(entity(VoiceEntityType.RECIPIENT, it)) }
                }
            }
            addMatches(VoiceEntityType.PHONE_NUMBER, normalized, PHONE_PATTERN)
            addMatches(VoiceEntityType.AMOUNT, normalized, AMOUNT_PATTERN)
            DATE_TIME_PATTERNS.forEach { addMatches(VoiceEntityType.DATE_TIME, normalized, it) }
            FILE_PATH_PATTERNS.forEach { addMatches(VoiceEntityType.FILE_PATH, normalized, it) }
            APPLICATION_PATTERNS.forEach { pattern -> addCaptured(VoiceEntityType.APPLICATION, normalized, pattern) }
            DEVICE_PATTERNS.forEach { pattern -> addCaptured(VoiceEntityType.DEVICE, normalized, pattern) }
            NEGATION_TERMS.forEach { (canonical, pattern) ->
                if (pattern.containsMatchIn(normalized)) add(entity(VoiceEntityType.NEGATION, canonical))
            }
            ACTION_TERMS.forEach { (canonical, pattern) ->
                if (pattern.containsMatchIn(normalized)) add(entity(VoiceEntityType.ACTION, canonical))
            }
        }.distinctBy { it.type to it.canonicalValue }
            .sortedWith(compareBy<VoiceEntity> { it.type.ordinal }.thenBy(VoiceEntity::canonicalValue))
    }

    override fun compare(fastText: String, accurateText: String): EntityConsistencyResult {
        val fast = extract(fastText)
        val accurate = extract(accurateText)
        val differences = VoiceEntityType.entries.mapNotNull { type ->
            val fastValues = fast.filter { it.type == type }.map(VoiceEntity::canonicalValue).distinct().sorted()
            val accurateValues = accurate.filter { it.type == type }.map(VoiceEntity::canonicalValue).distinct().sorted()
            if (fastValues == accurateValues) null else VoiceEntityDifference(type, fastValues, accurateValues)
        }
        return EntityConsistencyResult(fast, accurate, differences)
    }

    private fun MutableList<VoiceEntity>.addMatches(type: VoiceEntityType, text: String, pattern: Regex) {
        pattern.findAll(text).forEach { match ->
            match.value.trim().trimEndPunctuation().takeIf(String::isNotBlank)?.let { add(entity(type, it)) }
        }
    }

    private fun MutableList<VoiceEntity>.addCaptured(type: VoiceEntityType, text: String, pattern: Regex) {
        pattern.findAll(text).forEach { match ->
            match.groups[1]?.value?.trim()?.trimEndPunctuation()
                ?.takeIf(String::isNotBlank)
                ?.let { add(entity(type, it)) }
        }
    }

    private fun entity(type: VoiceEntityType, value: String): VoiceEntity = VoiceEntity(
        type = type,
        value = value,
        canonicalValue = value.normalizedEntityValue()
    )

    private val RECIPIENT_PATTERNS = listOf(
        Regex("(?:\\u7ed9|\\u5411)([\\p{L}\\p{N}_.@+-]{1,48}?)(?=\\u53d1\\u9001|\\u53d1|\\u8f6c\\u8d26|\\u6253\\u7535\\u8bdd|\\u62e8\\u6253|\\u5206\\u4eab)"),
        Regex("(?:\\u53d1\\u9001|\\u53d1|\\u5206\\u4eab)(?:\\u6d88\\u606f|\\u6587\\u4ef6)?(?:\\u7ed9|\\u5230)([\\p{L}\\p{N}_.@+-]{1,48})"),
        Regex("\\b(?:send|message|call|dial|pay|transfer|share)(?:\\s+(?:a|the|this|file|message|money))*\\s+(?:to\\s+)?([\\p{L}\\p{N}_.@+-]{1,48})\\b", RegexOption.IGNORE_CASE)
    )
    private val PHONE_PATTERN = Regex("(?<![\\d.])(?:\\+?\\d[\\d ()-]{5,}\\d)(?![\\d.])")
    private val AMOUNT_PATTERN = Regex(
        "(?:[$\\u00a5\\uffe5\\u20ac\\u00a3]\\s*\\d+(?:[.,]\\d{1,2})?)|" +
            "(?:\\d+(?:[.,]\\d{1,2})?\\s*(?:\\u5143|\\u7f8e\\u5143|\\u4eba\\u6c11\\u5e01|usd|cny|rmb|eur|gbp))",
        RegexOption.IGNORE_CASE
    )
    private val DATE_TIME_PATTERNS = listOf(
        Regex("\\b\\d{4}[-/.]\\d{1,2}[-/.]\\d{1,2}\\b"),
        Regex("\\b\\d{1,2}:\\d{2}(?::\\d{2})?\\s*(?:am|pm)?\\b", RegexOption.IGNORE_CASE),
        Regex("\\d{1,2}\\s*(?:\\u6708)\\s*\\d{1,2}\\s*(?:\\u65e5|\\u53f7)"),
        Regex("\\d{1,2}\\s*(?:\\u70b9|\\u65f6)(?:\\s*\\d{1,2}\\s*\\u5206)?")
    )
    private val FILE_PATH_PATTERNS = listOf(
        Regex("\\b[A-Za-z]:[\\\\/](?:[^\\s\\\"'<>|]+[\\\\/]?)+"),
        Regex("(?<![A-Za-z0-9])/(?:[^\\s\\\"']+/)*[^\\s\\\"']+"),
        Regex("\\b(?:Downloads?|Documents?|Pictures?|DCIM|Movies|Music)[\\\\/][^\\s\\\"']+", RegexOption.IGNORE_CASE),
        Regex("(?<![\\p{L}\\p{N}_.-])[\\p{L}\\p{N}_-]{1,96}\\.(?:txt|csv|json|xml|pdf|docx?|xlsx?|pptx?|zip|tar|gz|7z|rar|jpg|jpeg|png|gif|webp|mp3|wav|m4a|mp4|mkv|py|js|ts|kt|java|c|cc|cpp|h|hpp|rs|go|sh|apk)(?![\\p{L}\\p{N}_.-])", RegexOption.IGNORE_CASE)
    )
    private val APPLICATION_PATTERNS = listOf(
        Regex("(?:\\u6253\\u5f00|\\u542f\\u52a8|\\u5173\\u95ed|\\u5378\\u8f7d)([\\p{L}\\p{N}_.+-]{1,48})"),
        Regex("\\b(?:open|launch|close|uninstall)\\s+([A-Za-z][A-Za-z0-9_.+-]*(?:\\s+[A-Za-z0-9_.+-]+){0,2})", RegexOption.IGNORE_CASE)
    )
    private val DEVICE_PATTERNS = listOf(
        Regex("(?:\\u5728|\\u7528)([\\p{L}\\p{N}_.+-]{1,48})(?:\\u4e0a|\\u8bbe\\u5907)"),
        Regex("\\b(?:on|using)\\s+(?:the\\s+)?([A-Za-z][A-Za-z0-9_.+-]*(?:\\s+[A-Za-z0-9_.+-]+){0,2})", RegexOption.IGNORE_CASE)
    )
    private val NEGATION_TERMS = listOf(
        "negated" to Regex("\\b(?:not|never|do not|don't|without)\\b|(?:\\u4e0d\\u8981|\\u4e0d\\u7528|\\u522b|\\u7981\\u6b62|\\u672a|\\u65e0)", RegexOption.IGNORE_CASE)
    )
    private val ACTION_TERMS = listOf(
        "send" to Regex("\\b(?:send|message|share)\\b|(?:\\u53d1\\u9001|\\u53d1\\u7ed9|\\u5206\\u4eab)", RegexOption.IGNORE_CASE),
        "delete" to Regex("\\b(?:delete|remove|erase|wipe)\\b|(?:\\u5220\\u9664|\\u79fb\\u9664|\\u6e05\\u7a7a)", RegexOption.IGNORE_CASE),
        "overwrite" to Regex("\\b(?:overwrite|replace)\\b|(?:\\u8986\\u76d6|\\u66ff\\u6362)", RegexOption.IGNORE_CASE),
        "pay" to Regex("\\b(?:pay|transfer|purchase|order)\\b|(?:\\u652f\\u4ed8|\\u8f6c\\u8d26|\\u8d2d\\u4e70|\\u4e0b\\u5355)", RegexOption.IGNORE_CASE),
        "call" to Regex("\\b(?:call|dial)\\b|(?:\\u6253\\u7535\\u8bdd|\\u62e8\\u6253)", RegexOption.IGNORE_CASE),
        "install" to Regex("\\b(?:install|uninstall)\\b|(?:\\u5b89\\u88c5|\\u5378\\u8f7d)", RegexOption.IGNORE_CASE),
        "publish" to Regex("\\b(?:publish|post publicly)\\b|(?:\\u53d1\\u5e03|\\u516c\\u5f00)", RegexOption.IGNORE_CASE)
    )
}

data class VoiceExecutionRecord(
    val sessionId: String,
    val idempotencyKey: String,
    val fastTranscriptHash: String,
    val fastRevision: Int,
    val risk: VoiceCommandRisk,
    val primaryDispatchClaimed: Boolean = false,
    val externalSideEffectCount: Int = 0,
    val agentRunCount: Int = 0,
    val ttsCorrectionCount: Int = 0,
    val highestCorrectionRevision: Int = 0,
    val userEdited: Boolean = false,
    val updatedAtMillis: Long = System.currentTimeMillis()
) {
    val executionStarted: Boolean
        get() = primaryDispatchClaimed || externalSideEffectCount > 0 || agentRunCount > 0
}

sealed interface CorrectionDecision {
    data object NoMaterialChange : CorrectionDecision
    data class DisplayOnly(val diff: TranscriptDiff) : CorrectionDecision
    data class UpdateFutureContext(val diff: TranscriptDiff) : CorrectionDecision
    data class WarnUser(val diff: TranscriptDiff, val reason: String) : CorrectionDecision
    data class RequireConfirmationBeforeExecution(
        val corrected: TranscriptHypothesis,
        val reason: String
    ) : CorrectionDecision
}

interface TranscriptCorrectionController {
    fun compare(
        fast: TranscriptHypothesis,
        accurate: TranscriptHypothesis,
        executionRecord: VoiceExecutionRecord
    ): CorrectionDecision
}

class DefaultTranscriptCorrectionController(
    private val entityChecker: EntityConsistencyChecker = DefaultEntityConsistencyChecker
) : TranscriptCorrectionController {
    override fun compare(
        fast: TranscriptHypothesis,
        accurate: TranscriptHypothesis,
        executionRecord: VoiceExecutionRecord
    ): CorrectionDecision {
        if (accurate.revision <= executionRecord.highestCorrectionRevision) {
            return CorrectionDecision.NoMaterialChange
        }
        val consistency = entityChecker.compare(fast.text, accurate.text)
        val diff = TranscriptDiff(
            fastText = fast.text.trim(),
            accurateText = accurate.text.trim(),
            normalizedFastText = fast.text.normalizedTranscript(),
            normalizedAccurateText = accurate.text.normalizedTranscript(),
            entityDifferences = consistency.differences
        )
        if (!diff.changed) return CorrectionDecision.NoMaterialChange
        if (executionRecord.userEdited) return CorrectionDecision.UpdateFutureContext(diff)

        if (diff.hasCriticalEntityChange) {
            return when {
                executionRecord.executionStarted -> CorrectionDecision.WarnUser(
                    diff,
                    "A protected entity changed after execution started"
                )
                executionRecord.risk >= VoiceCommandRisk.HIGH ->
                    CorrectionDecision.RequireConfirmationBeforeExecution(
                        corrected = accurate,
                        reason = "Protected entities differ between fast and accurate transcription"
                    )
                else -> CorrectionDecision.WarnUser(
                    diff,
                    "A command entity changed during the accuracy pass"
                )
            }
        }
        return if (executionRecord.executionStarted) {
            CorrectionDecision.UpdateFutureContext(diff)
        } else {
            CorrectionDecision.DisplayOnly(diff)
        }
    }
}

internal fun String.normalizedTranscript(): String = Normalizer.normalize(trim(), Normalizer.Form.NFKC)
    .lowercase(Locale.ROOT)
    .replace(Regex("[\\p{P}\\p{Z}\\s]+"), "")

private fun String.normalizedForMatching(): String = Normalizer.normalize(trim(), Normalizer.Form.NFKC)
    .lowercase(Locale.ROOT)
    .replace(Regex("\\s+"), " ")

private fun String.normalizedEntityValue(): String = Normalizer.normalize(trim(), Normalizer.Form.NFKC)
    .lowercase(Locale.ROOT)
    .replace(Regex("\\s+"), "")

private fun String.trimEndPunctuation(): String = trimEnd { character ->
    character.isWhitespace() || character in ",.;:!?)]}>\uFF0C\u3002\uFF1B\uFF1A\uFF01\uFF1F\uFF09\u3011\u300B"
}
