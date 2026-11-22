package com.galaxyssi.chat

import com.galaxyssi.chat.R.drawable
import com.galaxyssi.chat.R.string

internal object HealthAtlasHearingBalancePlates {
    const val MIDDLE_EAR_VIEW_KEY = "middle-ear-ossicular-cutaway"
    const val COCHLEA_VIEW_KEY = "cochlea-scala-cross-section"
    const val VESTIBULAR_VIEW_KEY = "vestibular-labyrinth-cutaway"

    val middleEar = HealthAtlasPlate(
        drawable = drawable.health_atlas_middle_ear_ossicular_cutaway,
        owner = "middle-ear",
        viewLabel = string.health_atlas_hb_middle_ear_caption,
        markers = emptyList(),
        source = "https://pmc.ncbi.nlm.nih.gov/articles/PMC4718166/",
        viewKey = MIDDLE_EAR_VIEW_KEY,
        selectorLabel = string.health_atlas_hb_middle_ear_selector,
        features = listOf(
            feature("middle-ear-tympanic-membrane", 95, 167, string.health_atlas_hb_eardrum,
                string.health_atlas_hb_eardrum_detail),
            feature("middle-ear-malleus", 132, 81, string.health_atlas_hb_malleus,
                string.health_atlas_hb_malleus_detail),
            feature("middle-ear-incus", 174, 82, string.health_atlas_hb_incus,
                string.health_atlas_hb_incus_detail),
            feature("middle-ear-stapes", 222, 137, string.health_atlas_hb_stapes,
                string.health_atlas_hb_stapes_detail),
            feature("middle-ear-oval-window", 257, 129, string.health_atlas_hb_oval_window,
                string.health_atlas_hb_oval_window_detail),
            feature("middle-ear-round-window", 264, 192, string.health_atlas_hb_round_window,
                string.health_atlas_hb_round_window_detail),
        ),
        splitCallouts = true,
    )

    val cochlea = HealthAtlasPlate(
        drawable = drawable.health_atlas_cochlea_scala_cross_section,
        owner = "cochlea",
        viewLabel = string.health_atlas_hb_cochlea_caption,
        markers = emptyList(),
        source = "https://pmc.ncbi.nlm.nih.gov/articles/PMC6753699/",
        viewKey = COCHLEA_VIEW_KEY,
        selectorLabel = string.health_atlas_hb_cochlea_selector,
        features = listOf(
            feature("cochlea-scala-vestibuli", 157, 91, string.health_atlas_hb_scala_vestibuli,
                string.health_atlas_hb_scala_vestibuli_detail),
            feature("cochlea-reissners-membrane", 207, 115, string.health_atlas_hb_reissners,
                string.health_atlas_hb_reissners_detail),
            feature("cochlea-cochlear-duct", 249, 132, string.health_atlas_hb_cochlear_duct,
                string.health_atlas_hb_cochlear_duct_detail),
            feature("cochlea-organ-of-corti", 163, 164, string.health_atlas_hb_corti,
                string.health_atlas_hb_corti_detail),
            feature("cochlea-basilar-membrane", 226, 176, string.health_atlas_hb_basilar,
                string.health_atlas_hb_basilar_detail),
            feature("cochlea-scala-tympani", 162, 208, string.health_atlas_hb_scala_tympani,
                string.health_atlas_hb_scala_tympani_detail),
        ),
        splitCallouts = true,
    )

    val vestibularApparatus = HealthAtlasPlate(
        drawable = drawable.health_atlas_vestibular_labyrinth_cutaway,
        owner = "vestibular-apparatus",
        viewLabel = string.health_atlas_hb_vestibular_caption,
        markers = emptyList(),
        source = "https://pmc.ncbi.nlm.nih.gov/articles/PMC10039035/",
        viewKey = VESTIBULAR_VIEW_KEY,
        selectorLabel = string.health_atlas_hb_vestibular_selector,
        features = listOf(
            feature("vestibular-anterior-canal", 122, 44, string.health_atlas_hb_anterior_canal,
                string.health_atlas_hb_anterior_canal_detail),
            feature("vestibular-posterior-canal", 258, 71, string.health_atlas_hb_posterior_canal,
                string.health_atlas_hb_posterior_canal_detail),
            feature("vestibular-lateral-canal", 84, 128, string.health_atlas_hb_lateral_canal,
                string.health_atlas_hb_lateral_canal_detail),
            feature("vestibular-posterior-ampulla", 242, 191, string.health_atlas_hb_ampulla,
                string.health_atlas_hb_ampulla_detail),
            feature("vestibular-utricle", 155, 190, string.health_atlas_hb_utricle,
                string.health_atlas_hb_utricle_detail),
            feature("vestibular-saccule", 205, 223, string.health_atlas_hb_saccule,
                string.health_atlas_hb_saccule_detail),
        ),
        splitCallouts = true,
    )

    val all = listOf(middleEar, cochlea, vestibularApparatus)

    fun forId(id: String?): HealthAtlasPlate? = when (id) {
        "middle-ear" -> middleEar
        "cochlea" -> cochlea
        "vestibular-apparatus" -> vestibularApparatus
        else -> null
    }

    private fun feature(id: String, x: Int, y: Int, title: Int, detail: Int) =
        HealthAtlasFeature(HealthAtlasMarker(id, x / 360f, y / 280f), title, detail)
}
