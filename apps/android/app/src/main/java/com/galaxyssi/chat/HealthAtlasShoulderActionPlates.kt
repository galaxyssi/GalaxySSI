package com.galaxyssi.chat

import com.galaxyssi.chat.R.string

internal object HealthAtlasShoulderActionPlates {
    private fun feature(id: String, x: Int, y: Int, title: Int, detail: Int) =
        HealthAtlasFeature(HealthAtlasMarker(id, x / 360f, y / 280f), title, detail)

    val pectoral = HealthAtlasPlate(
        drawable = R.drawable.health_atlas_pectoral_action_cutaway,
        owner = HealthAtlasPectoralActionAssignment.OWNER_ID,
        viewLabel = string.health_atlas_pectoral_plate_caption,
        markers = emptyList(),
        source = HealthAtlasPectoralActionAssignment.ANATOMY,
        viewKey = "pectoralis-major-cutaway",
        selectorLabel = string.health_atlas_pectoral_plate_title,
        features = listOf(
            feature("pectoral-clavicular-part", 173, 91, string.health_atlas_pectoral_plate_clavicular,
                string.health_atlas_pectoral_plate_clavicular_detail),
            feature("pectoral-sternocostal-part", 195, 150, string.health_atlas_pectoral_plate_sternocostal,
                string.health_atlas_pectoral_plate_sternocostal_detail),
            feature("pectoral-rib-cartilage", 111, 157, string.health_atlas_pectoral_plate_cartilage,
                string.health_atlas_pectoral_plate_cartilage_detail),
            feature("pectoral-humeral-tendon", 267, 118, string.health_atlas_pectoral_plate_humeral_tendon,
                string.health_atlas_pectoral_plate_humeral_tendon_detail),
        ),
        splitCallouts = true,
    )

    val latissimus = HealthAtlasPlate(
        drawable = R.drawable.health_atlas_latissimus_action_cutaway,
        owner = HealthAtlasLatissimusActionAssignment.OWNER_ID,
        viewLabel = string.health_atlas_latissimus_plate_caption,
        markers = emptyList(),
        source = HealthAtlasLatissimusActionAssignment.ANATOMY,
        viewKey = "latissimus-dorsi-cutaway",
        selectorLabel = string.health_atlas_latissimus_plate_title,
        features = listOf(
            feature("latissimus-thoracolumbar-fascia", 137, 202, string.health_atlas_latissimus_plate_fascia,
                string.health_atlas_latissimus_plate_fascia_detail),
            feature("latissimus-iliac-crest", 106, 242, string.health_atlas_latissimus_plate_crest,
                string.health_atlas_latissimus_plate_crest_detail),
            feature("latissimus-muscle-sheet", 195, 178, string.health_atlas_latissimus_plate_sheet,
                string.health_atlas_latissimus_plate_sheet_detail),
            feature("latissimus-humeral-tendon", 262, 106, string.health_atlas_latissimus_plate_humeral_tendon,
                string.health_atlas_latissimus_plate_humeral_tendon_detail),
        ),
        splitCallouts = true,
    )

    val all = listOf(pectoral, latissimus)

    fun forId(id: String?) = all.firstOrNull { it.owner == id }
}
