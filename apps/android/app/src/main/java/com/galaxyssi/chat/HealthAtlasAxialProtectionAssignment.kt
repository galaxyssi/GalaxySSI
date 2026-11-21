package com.galaxyssi.chat

import com.galaxyssi.chat.R.drawable
import com.galaxyssi.chat.R.string

/** Isolated handoff for the story and structure registries. */
internal object HealthAtlasAxialProtectionAssignment {
    private const val SKULL_SOURCE = "https://openstax.org/books/anatomy-and-physiology-2e/pages/7-2-the-skull"
    private const val BONE_SOURCE = "https://openstax.org/books/anatomy-and-physiology-2e/pages/6-3-bone-structure"
    private const val MENINGES_SOURCE = "https://openstax.org/books/anatomy-and-physiology-2e/pages/13-3-circulation-and-the-central-nervous-system"
    private const val SPINE_SOURCE = "https://openstax.org/books/anatomy-and-physiology-2e/pages/7-3-the-vertebral-column"
    private const val FACET_SOURCE = "https://pubmed.ncbi.nlm.nih.gov/19730201/"

    object Skull {
        const val ENTRY_ID = "skull"
        const val ORIENTATION = 0
        const val SUTURES = 1
        const val BONE = 2
        const val MENINGES = 3
        const val durationMs = 20_000L
        val owners = setOf(ENTRY_ID)
        val title = string.health_atlas_skull_protection_title
        val scope = string.health_atlas_skull_protection_scope
        val choice = string.health_atlas_skull_protection_choice
        val chapterIds = listOf("vault-orientation", "cranial-sutures", "calvarial-bone", "meninges-and-csf")
        val chapters = listOf(
            string.health_atlas_skull_protection_orientation to string.health_atlas_skull_protection_orientation_caption,
            string.health_atlas_skull_protection_sutures to string.health_atlas_skull_protection_sutures_caption,
            string.health_atlas_skull_protection_bone to string.health_atlas_skull_protection_bone_caption,
            string.health_atlas_skull_protection_meninges to string.health_atlas_skull_protection_meninges_caption,
        )
        val references = listOf(
            string.health_atlas_skull_protection_ref_skull to SKULL_SOURCE,
            string.health_atlas_skull_protection_ref_bone to BONE_SOURCE,
            string.health_atlas_skull_protection_ref_meninges to MENINGES_SOURCE,
        )
        val plate = HealthAtlasPlate(
            drawable = drawable.health_atlas_skull_vault_section,
            owner = ENTRY_ID,
            viewLabel = string.health_atlas_skull_protection_plate_caption,
            markers = emptyList(),
            source = MENINGES_SOURCE,
            viewKey = "skull-vault-section",
            selectorLabel = string.health_atlas_skull_protection_plate_title,
            features = listOf(
                feature("skull-vault-outer-table", 100, 86, string.health_atlas_skull_protection_art_outer,
                    string.health_atlas_skull_protection_plate_outer),
                feature("skull-vault-diploe", 180, 81, string.health_atlas_skull_protection_art_diploe,
                    string.health_atlas_skull_protection_plate_diploe),
                feature("skull-vault-inner-table", 254, 105, string.health_atlas_skull_protection_art_inner,
                    string.health_atlas_skull_protection_plate_inner),
                feature("skull-vault-dura", 64, 127, string.health_atlas_skull_protection_art_dura,
                    string.health_atlas_skull_protection_plate_dura),
                feature("skull-vault-arachnoid", 279, 123, string.health_atlas_skull_protection_art_arachnoid,
                    string.health_atlas_skull_protection_plate_arachnoid),
                feature("skull-vault-pia", 67, 155, string.health_atlas_skull_protection_art_pia,
                    string.health_atlas_skull_protection_plate_pia),
                feature("skull-vault-csf", 288, 136, string.health_atlas_skull_protection_art_csf,
                    string.health_atlas_skull_protection_plate_csf),
                feature("skull-vault-cortex", 155, 167, string.health_atlas_skull_protection_art_brain,
                    string.health_atlas_skull_protection_plate_brain),
            ),
            splitCallouts = true,
        )
    }

    object Vertebral {
        const val ENTRY_ID = "vertebrae"
        const val FIT = 0
        const val FLEXION = 1
        const val EXTENSION = 2
        const val durationMs = 15_000L
        val owners = setOf(ENTRY_ID)
        val title = string.health_atlas_vertebral_motion_title
        val scope = string.health_atlas_vertebral_motion_scope
        val choice = string.health_atlas_vertebral_motion_choice
        val chapterIds = listOf("lumbar-segment-fit", "lumbar-flexion", "lumbar-extension")
        val chapters = listOf(
            string.health_atlas_vertebral_motion_fit to string.health_atlas_vertebral_motion_fit_caption,
            string.health_atlas_vertebral_motion_flexion to string.health_atlas_vertebral_motion_flexion_caption,
            string.health_atlas_vertebral_motion_extension to string.health_atlas_vertebral_motion_extension_caption,
        )
        val references = listOf(
            string.health_atlas_vertebral_motion_ref_spine to SPINE_SOURCE,
            string.health_atlas_vertebral_motion_ref_facets to FACET_SOURCE,
        )
        val plate = HealthAtlasPlate(
            drawable = drawable.health_atlas_lumbar_motion_segment_section,
            owner = ENTRY_ID,
            viewLabel = string.health_atlas_vertebral_motion_plate_caption,
            markers = emptyList(),
            source = SPINE_SOURCE,
            viewKey = "lumbar-motion-segment-section",
            selectorLabel = string.health_atlas_vertebral_motion_plate_title,
            features = listOf(
                feature("lumbar-segment-body", 115, 97, string.health_atlas_vertebral_motion_art_body,
                    string.health_atlas_vertebral_motion_plate_body),
                feature("lumbar-segment-annulus", 82, 152, string.health_atlas_vertebral_motion_plate_annulus_title,
                    string.health_atlas_vertebral_motion_plate_annulus),
                feature("lumbar-segment-nucleus", 118, 151, string.health_atlas_vertebral_motion_plate_nucleus_title,
                    string.health_atlas_vertebral_motion_plate_nucleus),
                feature("lumbar-segment-pedicle", 188, 96, string.health_atlas_vertebral_motion_plate_pedicle_title,
                    string.health_atlas_vertebral_motion_plate_pedicle),
                feature("lumbar-segment-facet", 232, 161, string.health_atlas_vertebral_motion_art_facet,
                    string.health_atlas_vertebral_motion_plate_facet),
                feature("lumbar-segment-spinous", 280, 95, string.health_atlas_vertebral_motion_plate_spinous_title,
                    string.health_atlas_vertebral_motion_plate_spinous),
            ),
            splitCallouts = true,
        )
    }

    private fun feature(id: String, x: Int, y: Int, title: Int, detail: Int) =
        HealthAtlasFeature(HealthAtlasMarker(id, x / 360f, y / 280f), title, detail)
}
