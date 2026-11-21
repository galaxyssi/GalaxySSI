package com.galaxyssi.chat

internal object HealthAtlasSkullVaultLayersTeachingModel {
    private const val TABLE_WIDTH = 1.0
    private const val WIDTH_SCALE = 10.0
    private val diploeSteps = 10..50
    private val fluidSteps = 5..25

    val spec = HealthAtlasTeachingModelSpec(
        inputs = listOf(
            HealthAtlasTeachingInput(
                HealthAtlasInput("skull-vault-layers-diploe", diploeSteps, 25, scale = WIDTH_SCALE),
                R.string.health_atlas_skull_vault_layers_diploe, "u", digits = 1,
            ),
            HealthAtlasTeachingInput(
                HealthAtlasInput("skull-vault-layers-fluid", fluidSteps, 15, scale = WIDTH_SCALE),
                R.string.health_atlas_skull_vault_layers_fluid, "u", digits = 1,
            ),
        ),
        axis = 0,
        unit = "u",
        minimum = boneWidth(diploeSteps.first / WIDTH_SCALE) + fluidSteps.first / WIDTH_SCALE,
        maximum = boneWidth(diploeSteps.last / WIDTH_SCALE) + fluidSteps.last / WIDTH_SCALE,
        source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/6-3-bone-structure",
        extraSource = "https://openstax.org/books/anatomy-and-physiology-2e/pages/13-3-circulation-and-the-central-nervous-system",
        title = R.string.health_atlas_skull_vault_layers_title,
        scope = R.string.health_atlas_skull_vault_layers_scope,
        formula = R.string.health_atlas_skull_vault_layers_formula,
        companionTitle = R.string.health_atlas_skull_vault_layers_bone,
        entryIds = setOf("skull"),
        evaluate = { (diploe, fluid) -> boneWidth(diploe) + fluid },
        companionValue = { (diploe, _) -> boneWidth(diploe) },
        digits = 1,
    )

    private fun boneWidth(diploe: Double) = TABLE_WIDTH + diploe + TABLE_WIDTH
}
