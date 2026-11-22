package com.galaxyssi.chat

import com.galaxyssi.chat.R.string

internal object HealthAtlasGanglionRelayAssignment {
    const val GANGLIA_ID = "ganglia"
    const val SATELLITE_GLIA_ID = "cell-satellite-glial-cell"
    const val SENSORY = 0
    const val AUTONOMIC = 1
    const val SATELLITE = 2

    val owners = setOf(GANGLIA_ID, SATELLITE_GLIA_ID)
    val title = string.health_atlas_ganglion_relay_title
    val scope = string.health_atlas_ganglion_relay_scope
    val choice = string.health_atlas_ganglion_relay_choice
    val chapterIds = listOf("sensory-ganglion", "autonomic-ganglion", SATELLITE_GLIA_ID)
    val chapters = listOf(
        string.health_atlas_ganglion_relay_sensory to string.health_atlas_ganglion_relay_sensory_caption,
        string.health_atlas_ganglion_relay_autonomic to string.health_atlas_ganglion_relay_autonomic_caption,
        string.health_atlas_ganglion_relay_satellite to string.health_atlas_ganglion_relay_satellite_caption,
    )
    val references = listOf(
        string.health_atlas_ganglion_relay_ref_drg to "https://www.ncbi.nlm.nih.gov/books/NBK532291/",
        string.health_atlas_ganglion_relay_ref_sensory to "https://pmc.ncbi.nlm.nih.gov/articles/PMC8364508/",
        string.health_atlas_ganglion_relay_ref_autonomic to HealthAtlasAutonomicNervesPlate.SOURCE,
        string.health_atlas_ganglion_relay_ref_synapse to "https://pubmed.ncbi.nlm.nih.gov/4331152/",
        string.health_atlas_ganglion_relay_ref_sheath to "https://hdl.handle.net/2434/22963",
        string.health_atlas_ganglion_relay_ref_local to "https://pubmed.ncbi.nlm.nih.gov/20074622/",
    )
    const val durationMs = 15_000L

    fun entryChapter(id: String) = if (id == SATELLITE_GLIA_ID) SATELLITE else SENSORY
}
