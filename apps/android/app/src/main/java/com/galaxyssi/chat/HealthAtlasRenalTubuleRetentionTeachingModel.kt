package com.galaxyssi.chat

internal object HealthAtlasRenalTubuleRetentionTeachingModel {
    private const val STARTING_AMOUNT = 100.0
    private const val WHOLE_PERCENT = 100.0
    private const val MAX_RECLAMATION_PERCENT = 80

    data class Amounts(val starting: Double, val afterA: Double, val remaining: Double) {
        val reclaimedInA get() = starting - afterA
        val reclaimedInB get() = afterA - remaining
        val totalReclaimed get() = starting - remaining
    }

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("renal-tubule-retention-segment-a", 0..MAX_RECLAMATION_PERCENT, 40),
                R.string.health_atlas_renal_tubule_retention_segment_a,
                "%",
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("renal-tubule-retention-segment-b", 0..MAX_RECLAMATION_PERCENT, 25),
                R.string.health_atlas_renal_tubule_retention_segment_b,
                "%",
                digits = 0,
            ),
        ),
        axis = 1,
        unit = "a.u.",
        minimum = 0.0,
        maximum = STARTING_AMOUNT,
        source = "https://www.niddk.nih.gov/health-information/kidney-disease/kidneys-how-they-work",
        title = R.string.health_atlas_renal_tubule_retention_title,
        scope = R.string.health_atlas_renal_tubule_retention_scope,
        formula = R.string.health_atlas_renal_tubule_retention_formula,
        companionTitle = R.string.health_atlas_renal_tubule_retention_companion,
        entryIds = setOf("tissue-renal-tubular-epithelium", "renal-cortex", "renal-medulla"),
        evaluate = { (segmentAPercent, segmentBPercent) -> amounts(segmentAPercent, segmentBPercent).remaining },
        companionValue = { (segmentAPercent, segmentBPercent) ->
            amounts(segmentAPercent, segmentBPercent).totalReclaimed
        },
        extraSource = "https://openstax.org/books/anatomy-and-physiology-2e/pages/25-6-tubular-reabsorption",
    )

    fun amounts(segmentAPercent: Double, segmentBPercent: Double): Amounts {
        val allowed = 0.0..MAX_RECLAMATION_PERCENT.toDouble()
        require(segmentAPercent in allowed && segmentBPercent in allowed)
        val afterA = STARTING_AMOUNT * (1.0 - segmentAPercent / WHOLE_PERCENT)
        val afterB = afterA * (1.0 - segmentBPercent / WHOLE_PERCENT)
        return Amounts(STARTING_AMOUNT, afterA, afterB)
    }
}
