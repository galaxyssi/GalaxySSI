package com.galaxyssi.chat

import com.galaxyssi.chat.R.drawable
import com.galaxyssi.chat.R.string

internal object HealthAtlasReproductiveAnatomyDetailPlates {
    val all = listOf(
        HealthAtlasPlate(
            drawable = drawable.health_atlas_ovarian_section,
            owner = "ovaries",
            viewLabel = string.health_atlas_ovarian_section_view,
            markers = listOf(marker("uterine-tubes", 318, 83)),
            source = "https://histology.oit.duke.edu/NormalBody/FemaleRepro/FemaleRepro.html",
            viewKey = "ovarian-section",
            selectorLabel = string.health_atlas_ovarian_section_selector,
            features = listOf(
                feature("ovarian-cortex-band", 62, 145, string.health_atlas_ovarian_cortex_band,
                    string.health_atlas_ovarian_cortex_band_detail),
                feature("ovarian-small-follicle", 111, 93, string.health_atlas_ovarian_small_follicle,
                    string.health_atlas_ovarian_small_follicle_detail),
                feature("ovarian-antral-follicle", 215, 113, string.health_atlas_ovarian_antral_follicle,
                    string.health_atlas_ovarian_antral_follicle_detail),
                feature("ovarian-medulla-core", 145, 150, string.health_atlas_ovarian_medulla_core,
                    string.health_atlas_ovarian_medulla_core_detail),
                feature("ovarian-hilum", 221, 184, string.health_atlas_ovarian_hilum,
                    string.health_atlas_ovarian_hilum_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = drawable.health_atlas_testicular_section,
            owner = "testes",
            viewLabel = string.health_atlas_testicular_section_view,
            markers = listOf(marker("epididymis", 242, 134), marker("vas-deferens", 268, 94)),
            source = "https://openstax.org/books/anatomy-and-physiology-2e/pages/27-1-anatomy-and-physiology-of-the-testicular-reproductive-system",
            viewKey = "testicular-section",
            selectorLabel = string.health_atlas_testicular_section_selector,
            features = listOf(
                feature("testicular-tunica-albuginea", 97, 86, string.health_atlas_testicular_tunica_albuginea,
                    string.health_atlas_testicular_tunica_albuginea_detail),
                feature("testicular-septum", 135, 103, string.health_atlas_testicular_septum,
                    string.health_atlas_testicular_septum_detail),
                feature("testicular-tubules", 128, 156, string.health_atlas_testicular_tubules,
                    string.health_atlas_testicular_tubules_detail),
                feature("testicular-rete", 211, 128, string.health_atlas_testicular_rete,
                    string.health_atlas_testicular_rete_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = drawable.health_atlas_uterine_tube_cutaway,
            owner = "uterine-tubes",
            viewLabel = string.health_atlas_uterine_tube_cutaway_view,
            markers = listOf(marker("ovaries", 61, 187), marker("uterus", 294, 170)),
            source = "https://histopathology.pennstatehealth.net/slideview/MH-171-oviduct/18-slide-1.html",
            viewKey = "uterine-tube-cutaway",
            selectorLabel = string.health_atlas_uterine_tube_cutaway_selector,
            features = listOf(
                feature("tubal-fimbriae", 41, 138, string.health_atlas_tubal_fimbriae,
                    string.health_atlas_tubal_fimbriae_detail),
                feature("tubal-infundibulum", 68, 112, string.health_atlas_tubal_infundibulum,
                    string.health_atlas_tubal_infundibulum_detail),
                feature("tubal-ampulla", 128, 76, string.health_atlas_tubal_ampulla,
                    string.health_atlas_tubal_ampulla_detail),
                feature("tubal-isthmus", 217, 95, string.health_atlas_tubal_isthmus,
                    string.health_atlas_tubal_isthmus_detail),
                feature("tubal-mucosal-folds", 190, 204, string.health_atlas_tubal_mucosal_folds,
                    string.health_atlas_tubal_mucosal_folds_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = drawable.health_atlas_endometrial_layers,
            owner = "endometrium",
            viewLabel = string.health_atlas_endometrial_layers_view,
            markers = listOf(marker("uterus", 48, 140)),
            source = "https://histology.leeds.ac.uk/home/female/uterus/",
            viewKey = "endometrial-layers",
            selectorLabel = string.health_atlas_endometrial_layers_selector,
            features = listOf(
                feature("endometrial-luminal-epithelium", 232, 88, string.health_atlas_endometrial_luminal_epithelium,
                    string.health_atlas_endometrial_luminal_epithelium_detail),
                feature("endometrial-functional-layer", 250, 120, string.health_atlas_endometrial_functional_layer,
                    string.health_atlas_endometrial_functional_layer_detail),
                feature("endometrial-uterine-gland", 169, 138, string.health_atlas_endometrial_uterine_gland,
                    string.health_atlas_endometrial_uterine_gland_detail),
                feature("endometrial-basal-layer", 252, 174, string.health_atlas_endometrial_basal_layer,
                    string.health_atlas_endometrial_basal_layer_detail),
                feature("endometrial-myometrium-bed", 149, 222, string.health_atlas_endometrial_myometrium_bed,
                    string.health_atlas_endometrial_myometrium_bed_detail),
            ),
            splitCallouts = true,
        ),
    )

    private fun marker(id: String, x: Int, y: Int) = HealthAtlasMarker(id, x / 360f, y / 280f)

    private fun feature(id: String, x: Int, y: Int, title: Int, detail: Int) =
        HealthAtlasFeature(marker(id, x, y), title, detail)
}
