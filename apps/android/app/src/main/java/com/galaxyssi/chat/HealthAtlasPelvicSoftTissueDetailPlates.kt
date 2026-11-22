package com.galaxyssi.chat

import com.galaxyssi.chat.R.drawable
import com.galaxyssi.chat.R.string

internal object HealthAtlasPelvicSoftTissueDetailPlates {
    val all: List<HealthAtlasPlate> = listOf(
        HealthAtlasPlate(
            drawable = drawable.health_atlas_prostate_sagittal_zones,
            owner = "prostate",
            viewLabel = string.health_atlas_prostate_sagittal_view,
            markers = listOf(
                marker("bladder", 128, 66),
                marker("seminal-vesicles", 223, 76),
                marker("rectum", 287, 212),
            ),
            source = "https://training.seer.cancer.gov/prostate/anatomy/",
            viewKey = "prostate-sagittal-zones",
            selectorLabel = string.health_atlas_prostate_sagittal_selector,
            features = listOf(
                feature("prostate-base", 114, 114, string.health_atlas_prostate_base,
                    string.health_atlas_prostate_base_detail),
                feature("prostatic-urethra", 162, 154, string.health_atlas_prostatic_urethra,
                    string.health_atlas_prostatic_urethra_detail),
                feature("prostate-central-zone", 210, 129, string.health_atlas_prostate_central_zone,
                    string.health_atlas_prostate_central_zone_detail),
                feature("prostate-peripheral-zone", 218, 178, string.health_atlas_prostate_peripheral_zone,
                    string.health_atlas_prostate_peripheral_zone_detail),
                feature("prostate-apex", 173, 222, string.health_atlas_prostate_apex,
                    string.health_atlas_prostate_apex_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = drawable.health_atlas_vagina_sagittal_cutaway,
            owner = "vagina",
            viewLabel = string.health_atlas_vagina_sagittal_view,
            markers = listOf(
                marker("bladder", 104, 113),
                marker("urethra", 114, 200),
                marker("cervix", 205, 109),
                marker("rectum", 286, 162),
            ),
            source = "https://pmc.ncbi.nlm.nih.gov/articles/PMC3312145/",
            viewKey = "vagina-sagittal-cutaway",
            selectorLabel = string.health_atlas_vagina_sagittal_selector,
            features = listOf(
                feature("vagina-posterior-fornix", 232, 93, string.health_atlas_vagina_posterior_fornix,
                    string.health_atlas_vagina_posterior_fornix_detail),
                feature("vagina-anterior-wall", 168, 151, string.health_atlas_vagina_anterior_wall,
                    string.health_atlas_vagina_anterior_wall_detail),
                feature("vagina-rugae", 186, 181, string.health_atlas_vagina_rugae,
                    string.health_atlas_vagina_rugae_detail),
                feature("vaginal-opening", 143, 244, string.health_atlas_vaginal_opening,
                    string.health_atlas_vaginal_opening_detail),
            ),
            splitCallouts = true,
        ),
    )

    private fun marker(id: String, x: Int, y: Int) = HealthAtlasMarker(id, x / 360f, y / 280f)

    private fun feature(id: String, x: Int, y: Int, title: Int, detail: Int) =
        HealthAtlasFeature(marker(id, x, y), title, detail)
}
