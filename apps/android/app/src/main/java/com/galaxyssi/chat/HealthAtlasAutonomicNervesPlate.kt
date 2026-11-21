package com.galaxyssi.chat

import com.galaxyssi.chat.R.string

internal object HealthAtlasAutonomicNervesPlate {
    const val ID = "autonomic-nerves"
    const val VIEW_KEY = "autonomic-outflows"
    const val SOURCE = "https://openstax.org/books/anatomy-and-physiology-2e/pages/15-1-divisions-of-the-autonomic-nervous-system"

    val plate = HealthAtlasPlate(
        R.drawable.health_atlas_autonomic_outflows, ID, string.health_atlas_autonomic_outflows_view,
        emptyList(), SOURCE, viewKey = VIEW_KEY, features = listOf(
            feature("autonomic-thoracolumbar-outflow", 166, 139,
                string.health_atlas_autonomic_outflows_thoracolumbar, string.health_atlas_autonomic_outflows_thoracolumbar_detail),
            feature("autonomic-sympathetic-chain", 119, 117,
                string.health_atlas_autonomic_outflows_chain, string.health_atlas_autonomic_outflows_chain_detail),
            feature("autonomic-cranial-outflow", 224, 56,
                string.health_atlas_autonomic_outflows_cranial, string.health_atlas_autonomic_outflows_cranial_detail),
            feature("autonomic-sacral-outflow", 171, 219,
                string.health_atlas_autonomic_outflows_sacral, string.health_atlas_autonomic_outflows_sacral_detail),
            feature("autonomic-terminal-ganglion", 288, 175,
                string.health_atlas_autonomic_outflows_terminal, string.health_atlas_autonomic_outflows_terminal_detail),
        ), splitCallouts = true,
    )
    val all = listOf(plate)

    fun forId(id: String?) = plate.takeIf { id == ID }

    private fun feature(id: String, x: Int, y: Int, title: Int, detail: Int) =
        HealthAtlasFeature(HealthAtlasMarker(id, x / 360f, y / 280f), title, detail)
}
