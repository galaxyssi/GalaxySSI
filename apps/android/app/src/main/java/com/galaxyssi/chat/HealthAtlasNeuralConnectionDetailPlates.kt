package com.galaxyssi.chat

import com.galaxyssi.chat.R.drawable
import com.galaxyssi.chat.R.string

internal object HealthAtlasNeuralConnectionDetailPlates {
    private const val CEREBRUM_SOURCE = "https://brain.oit.duke.edu/lab01/lab01.html"
    private const val PERIPHERAL_SOURCE =
        "https://openstax.org/books/anatomy-and-physiology-2e/pages/13-4-the-peripheral-nervous-system"
    private const val SPINAL_SOURCE = "https://nba.uth.tmc.edu/neuroscience/m/s2/chapter03.html"
    private const val GANGLION_SOURCE = "https://pmc.ncbi.nlm.nih.gov/articles/PMC6598622/"

    private fun marker(id: String, x: Int, y: Int) = HealthAtlasMarker(id, x / 360f, y / 280f)
    private fun feature(id: String, x: Int, y: Int, title: Int, explanation: Int) =
        HealthAtlasFeature(marker(id, x, y), title, explanation)

    val all: List<HealthAtlasPlate> = listOf(
        HealthAtlasPlate(
            drawable = drawable.health_atlas_cerebrum_medial_cutaway,
            owner = "cerebrum",
            viewLabel = string.health_atlas_cerebrum_medial_cutaway_view,
            markers = listOf(marker("cerebellum", 254, 221)),
            source = CEREBRUM_SOURCE,
            viewKey = "cerebrum-medial-cutaway",
            selectorLabel = string.health_atlas_cerebrum_medial_cutaway_selector,
            features = listOf(
                feature("cerebrum-medial-cortex", 104, 49, string.health_atlas_cerebrum_medial_cortex,
                    string.health_atlas_cerebrum_medial_cortex_detail),
                feature("cerebrum-medial-white-matter", 112, 127, string.health_atlas_cerebrum_medial_white_matter,
                    string.health_atlas_cerebrum_medial_white_matter_detail),
                feature("cerebrum-medial-callosum", 178, 133, string.health_atlas_cerebrum_medial_callosum,
                    string.health_atlas_cerebrum_medial_callosum_detail),
                feature("cerebrum-medial-cingulate", 221, 99, string.health_atlas_cerebrum_medial_cingulate,
                    string.health_atlas_cerebrum_medial_cingulate_detail),
                feature("cerebrum-medial-parieto-occipital", 281, 125,
                    string.health_atlas_cerebrum_medial_parieto_occipital,
                    string.health_atlas_cerebrum_medial_parieto_occipital_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = drawable.health_atlas_peripheral_nerve_fascicle_cutaway,
            owner = "peripheral-nerves",
            viewLabel = string.health_atlas_peripheral_nerve_fascicle_cutaway_view,
            markers = listOf(marker("cell-schwann-cell", 295, 204)),
            source = PERIPHERAL_SOURCE,
            viewKey = "peripheral-nerve-fascicle-cutaway",
            selectorLabel = string.health_atlas_peripheral_nerve_fascicle_cutaway_selector,
            features = listOf(
                feature("peripheral-nerve-epineurium", 84, 128, string.health_atlas_peripheral_nerve_epineurium,
                    string.health_atlas_peripheral_nerve_epineurium_detail),
                feature("peripheral-nerve-fascicle", 146, 106, string.health_atlas_peripheral_nerve_fascicle,
                    string.health_atlas_peripheral_nerve_fascicle_detail),
                feature("peripheral-nerve-perineurium", 246, 139, string.health_atlas_peripheral_nerve_perineurium,
                    string.health_atlas_peripheral_nerve_perineurium_detail),
                feature("peripheral-nerve-endoneurium", 261, 191, string.health_atlas_peripheral_nerve_endoneurium,
                    string.health_atlas_peripheral_nerve_endoneurium_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = drawable.health_atlas_spinal_nerve_roots_and_rami,
            owner = "spinal-nerves",
            viewLabel = string.health_atlas_spinal_nerve_roots_and_rami_view,
            markers = listOf(marker("spinal-cord", 77, 127), marker("ganglia", 201, 105)),
            source = SPINAL_SOURCE,
            viewKey = "spinal-nerve-roots-and-rami",
            selectorLabel = string.health_atlas_spinal_nerve_roots_and_rami_selector,
            features = listOf(
                feature("spinal-nerve-dorsal-root", 151, 95, string.health_atlas_spinal_nerve_dorsal_root,
                    string.health_atlas_spinal_nerve_dorsal_root_detail),
                feature("spinal-nerve-ventral-root", 151, 169, string.health_atlas_spinal_nerve_ventral_root,
                    string.health_atlas_spinal_nerve_ventral_root_detail),
                feature("spinal-nerve-mixed-trunk", 255, 143, string.health_atlas_spinal_nerve_mixed_trunk,
                    string.health_atlas_spinal_nerve_mixed_trunk_detail),
                feature("spinal-nerve-dorsal-ramus", 302, 91, string.health_atlas_spinal_nerve_dorsal_ramus,
                    string.health_atlas_spinal_nerve_dorsal_ramus_detail),
                feature("spinal-nerve-ventral-ramus", 313, 190, string.health_atlas_spinal_nerve_ventral_ramus,
                    string.health_atlas_spinal_nerve_ventral_ramus_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = drawable.health_atlas_dorsal_root_ganglion_cutaway,
            owner = "ganglia",
            viewLabel = string.health_atlas_dorsal_root_ganglion_cutaway_view,
            markers = listOf(marker("cell-satellite-glial-cell", 222, 77)),
            source = GANGLION_SOURCE,
            viewKey = "dorsal-root-ganglion-cutaway",
            selectorLabel = string.health_atlas_dorsal_root_ganglion_cutaway_selector,
            features = listOf(
                feature("dorsal-root-ganglion-capsule", 105, 65, string.health_atlas_dorsal_root_ganglion_capsule,
                    string.health_atlas_dorsal_root_ganglion_capsule_detail),
                feature("dorsal-root-ganglion-soma", 125, 98, string.health_atlas_dorsal_root_ganglion_soma,
                    string.health_atlas_dorsal_root_ganglion_soma_detail),
                feature("dorsal-root-ganglion-fiber-bundles", 103, 155,
                    string.health_atlas_dorsal_root_ganglion_fiber_bundles,
                    string.health_atlas_dorsal_root_ganglion_fiber_bundles_detail),
                feature("dorsal-root-ganglion-t-junction", 208, 140,
                    string.health_atlas_dorsal_root_ganglion_t_junction,
                    string.health_atlas_dorsal_root_ganglion_t_junction_detail),
            ),
            splitCallouts = true,
        ),
    )
}
