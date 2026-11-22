package com.galaxyssi.chat

import com.galaxyssi.chat.R.drawable
import com.galaxyssi.chat.R.string

internal object HealthAtlasUrinaryOutflowPlates {
    const val URETERS_VIEW_KEY = "ureter-course-wall-cutaway"
    const val BLADDER_VIEW_KEY = "bladder-wall-trigone-cutaway"
    const val URETHRA_VIEW_KEY = "female-urethral-channel-cutaway"

    private const val URINE_TRANSPORT_SOURCE =
        "https://openstax.org/books/anatomy-and-physiology-2e/pages/25-2-gross-anatomy-of-urine-transport"
    private const val URETER_WALL_SOURCE = "https://histology.leeds.ac.uk/home/urinary/ureter/"
    private const val FEMALE_URETHRA_SOURCE = "https://pubmed.ncbi.nlm.nih.gov/14672484/"

    // Course reference for the iliac crossing: https://doi.org/10.1002/uog.29122
    val ureters = HealthAtlasPlate(
        drawable = drawable.health_atlas_urinary_outflow_ureter,
        owner = "ureters",
        viewLabel = string.health_atlas_outflow_ureter_view,
        markers = emptyList(),
        source = URETER_WALL_SOURCE,
        viewKey = URETERS_VIEW_KEY,
        selectorLabel = string.health_atlas_outflow_ureter_selector,
        splitCallouts = true,
        features = listOf(
            feature("ureter-pelvis-junction", 116, 66, string.health_atlas_outflow_ureter_pelvis_junction,
                string.health_atlas_outflow_ureter_pelvis_junction_detail),
            feature("ureter-iliac-crossing", 112, 147, string.health_atlas_outflow_ureter_iliac_crossing,
                string.health_atlas_outflow_ureter_iliac_crossing_detail),
            feature("ureter-intramural-segment", 129, 224, string.health_atlas_outflow_ureter_intramural,
                string.health_atlas_outflow_ureter_intramural_detail),
            feature("ureter-section-urothelium", 242, 117, string.health_atlas_outflow_ureter_urothelium,
                string.health_atlas_outflow_ureter_urothelium_detail),
            feature("ureter-section-lumen", 256, 149, string.health_atlas_outflow_ureter_lumen,
                string.health_atlas_outflow_ureter_lumen_detail),
            feature("ureter-section-muscle", 299, 184, string.health_atlas_outflow_ureter_muscle,
                string.health_atlas_outflow_ureter_muscle_detail),
        ),
    )

    val bladder = HealthAtlasPlate(
        drawable = drawable.health_atlas_urinary_outflow_bladder,
        owner = "bladder",
        viewLabel = string.health_atlas_outflow_bladder_view,
        markers = emptyList(),
        source = URINE_TRANSPORT_SOURCE,
        viewKey = BLADDER_VIEW_KEY,
        selectorLabel = string.health_atlas_outflow_bladder_selector,
        splitCallouts = true,
        features = listOf(
            feature("bladder-section-urothelium", 105, 78, string.health_atlas_outflow_bladder_urothelium,
                string.health_atlas_outflow_bladder_urothelium_detail),
            feature("bladder-mucosal-folds", 137, 113, string.health_atlas_outflow_bladder_folds,
                string.health_atlas_outflow_bladder_folds_detail),
            feature("bladder-ureteric-orifice", 127, 174, string.health_atlas_outflow_bladder_ureteric_orifice,
                string.health_atlas_outflow_bladder_ureteric_orifice_detail),
            feature("bladder-section-detrusor", 265, 92, string.health_atlas_outflow_bladder_detrusor,
                string.health_atlas_outflow_bladder_detrusor_detail),
            feature("bladder-trigone-floor", 196, 198, string.health_atlas_outflow_bladder_trigone,
                string.health_atlas_outflow_bladder_trigone_detail),
            feature("bladder-internal-urethral-orifice", 182, 222, string.health_atlas_outflow_bladder_outlet,
                string.health_atlas_outflow_bladder_outlet_detail),
        ),
    )

    val urethra = HealthAtlasPlate(
        drawable = drawable.health_atlas_urinary_outflow_urethra,
        owner = "urethra",
        viewLabel = string.health_atlas_outflow_urethra_view,
        markers = emptyList(),
        source = FEMALE_URETHRA_SOURCE,
        viewKey = URETHRA_VIEW_KEY,
        selectorLabel = string.health_atlas_outflow_urethra_selector,
        splitCallouts = true,
        features = listOf(
            feature("female-urethral-internal-orifice", 166, 73, string.health_atlas_outflow_urethra_internal,
                string.health_atlas_outflow_urethra_internal_detail),
            feature("female-urethral-lumen", 151, 145, string.health_atlas_outflow_urethra_lumen,
                string.health_atlas_outflow_urethra_lumen_detail),
            feature("female-urethral-external-orifice", 135, 227, string.health_atlas_outflow_urethra_external,
                string.health_atlas_outflow_urethra_external_detail),
            feature("female-urethral-external-sphincter", 187, 134, string.health_atlas_outflow_urethra_sphincter,
                string.health_atlas_outflow_urethra_sphincter_detail),
            feature("female-urethral-vaginal-wall-relation", 209, 172, string.health_atlas_outflow_urethra_vaginal_wall,
                string.health_atlas_outflow_urethra_vaginal_wall_detail),
        ),
    )

    val all = listOf(ureters, bladder, urethra)

    fun forId(id: String?): HealthAtlasPlate? = all.firstOrNull { it.owner == id }

    private fun feature(id: String, x: Int, y: Int, title: Int, detail: Int) =
        HealthAtlasFeature(HealthAtlasMarker(id, x / 360f, y / 280f), title, detail)
}
