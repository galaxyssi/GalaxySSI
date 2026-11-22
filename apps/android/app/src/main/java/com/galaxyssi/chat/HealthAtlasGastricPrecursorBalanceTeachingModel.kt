package com.galaxyssi.chat

internal object HealthAtlasGastricPrecursorBalanceTeachingModel {
    private const val MAX_AMOUNT = 20
    private const val MAX_PERCENT = 100
    private const val MODEL_UNIT = "MU"

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("gastric-precursor-amount", 0..MAX_AMOUNT, 12),
                R.string.health_atlas_gastric_precursor_balance_amount,
                MODEL_UNIT,
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("gastric-precursor-converted-percent", 0..MAX_PERCENT, 35),
                R.string.health_atlas_gastric_precursor_balance_converted_percent,
                "%",
                digits = 0,
            ),
        ),
        axis = 1,
        unit = MODEL_UNIT,
        minimum = 0.0,
        maximum = MAX_AMOUNT.toDouble(),
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/23-4-the-stomach",
        title = R.string.health_atlas_gastric_precursor_balance_title,
        scope = R.string.health_atlas_gastric_precursor_balance_scope,
        formula = R.string.health_atlas_gastric_precursor_balance_formula,
        companionTitle = R.string.health_atlas_gastric_precursor_balance_companion,
        entryIds = setOf("cell-gastric-chief-cell", "cell-gastric-parietal-cell"),
        evaluate = { (amount, percent) -> convertedAmount(amount, percent) },
        companionValue = { (amount, percent) -> amount - convertedAmount(amount, percent) },
    )

    private fun convertedAmount(amount: Double, percent: Double): Double =
        amount * (percent / MAX_PERCENT)
}
