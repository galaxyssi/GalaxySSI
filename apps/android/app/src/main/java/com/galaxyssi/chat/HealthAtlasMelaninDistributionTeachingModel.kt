package com.galaxyssi.chat

internal object HealthAtlasMelaninDistributionTeachingModel {
    private const val MAX_PACKET_UNITS = 24
    private const val MIN_RECIPIENT_CELLS = 2
    private const val PACKET_UNIT = "PPU"

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("melanin-distribution-packet-units", 0..MAX_PACKET_UNITS, 12),
                label = R.string.health_atlas_melanin_distribution_packet_units,
                unit = PACKET_UNIT,
                digits = 0,
            ),
            HealthAtlasTeachingInput(
                control = HealthAtlasInput("melanin-distribution-recipient-cells", MIN_RECIPIENT_CELLS..8, 4),
                label = R.string.health_atlas_melanin_distribution_recipient_cells,
                unit = "",
                digits = 0,
            ),
        ),
        axis = 0,
        unit = "$PACKET_UNIT/cell",
        minimum = 0.0,
        maximum = MAX_PACKET_UNITS.toDouble() / MIN_RECIPIENT_CELLS,
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/5-1-layers-of-the-skin",
        extraSource = "https://www.cancer.gov/types/skin/hp/skin-genetics-pdq",
        title = R.string.health_atlas_melanin_distribution_title,
        scope = R.string.health_atlas_melanin_distribution_scope,
        formula = R.string.health_atlas_melanin_distribution_formula,
        companionTitle = R.string.health_atlas_melanin_distribution_companion,
        entryIds = setOf("cell-melanocyte"),
        evaluate = { (packetUnits, recipientCells) -> packetUnits / recipientCells },
        companionValue = { (packetUnits) -> packetUnits },
    )
}
