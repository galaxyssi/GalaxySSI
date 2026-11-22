package com.galaxyssi.chat

import com.galaxyssi.chat.R.drawable
import com.galaxyssi.chat.R.string

internal object HealthAtlasOuterSensoryDetailPlates {
    val all: List<HealthAtlasPlate> = listOf(
        plate(
            "external-ear", drawable.health_atlas_external_ear_canal_cutaway, "external-ear-canal-cutaway",
            string.health_atlas_outer_ear_selector, string.health_atlas_outer_ear_view,
            "https://pmc.ncbi.nlm.nih.gov/articles/PMC11630884/",
            listOf(marker("middle-ear", 312, 150)),
            feature("external-ear-helix", 102, 40, string.health_atlas_outer_ear_helix,
                string.health_atlas_outer_ear_helix_detail),
            feature("external-ear-concha", 131, 126, string.health_atlas_outer_ear_concha,
                string.health_atlas_outer_ear_concha_detail),
            feature("external-ear-canal", 211, 128, string.health_atlas_outer_ear_canal,
                string.health_atlas_outer_ear_canal_detail),
            feature("external-ear-eardrum", 282, 132, string.health_atlas_outer_ear_eardrum,
                string.health_atlas_outer_ear_eardrum_detail),
        ),
        plate(
            "inner-ear", drawable.health_atlas_inner_ear_bony_labyrinth, "inner-ear-bony-labyrinth",
            string.health_atlas_outer_inner_ear_selector, string.health_atlas_outer_inner_ear_view,
            "https://www.nature.com/articles/s41598-021-82716-0",
            listOf(marker("vestibular-apparatus", 83, 119), marker("cochlea", 240, 220)),
            feature("inner-ear-semicircular-loops", 124, 30, string.health_atlas_outer_inner_ear_loops,
                string.health_atlas_outer_inner_ear_loops_detail),
            feature("inner-ear-vestibule", 151, 147, string.health_atlas_outer_inner_ear_vestibule,
                string.health_atlas_outer_inner_ear_vestibule_detail),
            feature("inner-ear-vestibulocochlear-nerve", 287, 98, string.health_atlas_outer_inner_ear_nerve,
                string.health_atlas_outer_inner_ear_nerve_detail),
        ),
        plate(
            "nose", drawable.health_atlas_nose_lateral_wall_cutaway, "nose-lateral-wall-cutaway",
            string.health_atlas_outer_nose_selector, string.health_atlas_outer_nose_view,
            "https://openstax.org/books/anatomy-and-physiology-2e/pages/22-1-organs-and-structures-of-the-respiratory-system",
            listOf(marker("olfactory-mucosa", 150, 77), marker("pharynx", 275, 179)),
            feature("nose-vestibule", 91, 158, string.health_atlas_outer_nose_vestibule,
                string.health_atlas_outer_nose_vestibule_detail),
            feature("nose-middle-concha", 197, 115, string.health_atlas_outer_nose_middle_concha,
                string.health_atlas_outer_nose_middle_concha_detail),
            feature("nose-inferior-concha", 165, 149, string.health_atlas_outer_nose_inferior_concha,
                string.health_atlas_outer_nose_inferior_concha_detail),
        ),
        plate(
            "tongue", drawable.health_atlas_tongue_dorsal_cutaway, "tongue-dorsal-cutaway",
            string.health_atlas_outer_tongue_selector, string.health_atlas_outer_tongue_view,
            "https://peir.path.uab.edu/wiki/Histologic:Chapter_11#Tongue",
            listOf(marker("taste-buds", 113, 172)),
            feature("tongue-lingual-tonsil", 172, 73, string.health_atlas_outer_tongue_tonsil,
                string.health_atlas_outer_tongue_tonsil_detail),
            feature("tongue-terminal-sulcus", 117, 108, string.health_atlas_outer_tongue_sulcus,
                string.health_atlas_outer_tongue_sulcus_detail),
            feature("tongue-vallate-row", 213, 116, string.health_atlas_outer_tongue_vallate,
                string.health_atlas_outer_tongue_vallate_detail),
            feature("tongue-intrinsic-muscle", 246, 175, string.health_atlas_outer_tongue_muscle,
                string.health_atlas_outer_tongue_muscle_detail),
        ),
    )

    private fun plate(
        owner: String, art: Int, viewKey: String, selector: Int, caption: Int, source: String,
        markers: List<HealthAtlasMarker>, vararg features: HealthAtlasFeature,
    ) = HealthAtlasPlate(art, owner, caption, markers, source, viewKey,
        selectorLabel = selector, features = features.toList(), splitCallouts = true)

    private fun marker(id: String, x: Int, y: Int) = HealthAtlasMarker(id, x / 360f, y / 280f)

    private fun feature(id: String, x: Int, y: Int, title: Int, detail: Int) =
        HealthAtlasFeature(marker(id, x, y), title, detail)
}
