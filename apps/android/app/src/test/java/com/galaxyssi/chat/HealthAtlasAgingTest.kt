package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class HealthAtlasAgingTest {
    @Test fun savedSelectionUsesStableNamesAndRejectsInvalidSteps() {
        for (topic in HealthAtlasAgingTopic.entries) {
            for (step in 0..3) assertEquals(HealthAtlasAgingSelection(topic, step), HealthAtlasAgingSelection.restore(topic.name, step))
            assertNull(HealthAtlasAgingSelection.restore(topic.name, -1))
            assertNull(HealthAtlasAgingSelection.restore(topic.name, 4))
        }
        assertNull(HealthAtlasAgingSelection.restore("unknown", 0))
        assertNull(HealthAtlasAgingSelection.restore(null, 0))
    }

    @Test fun defaultsAndPrimaryStudiesAreTiedToExplicitContexts() {
        assertEquals(HealthAtlasAgingTopic.MITOCHONDRIA, HealthAtlasAgingTopic.forItem("heart"))
        assertEquals(HealthAtlasAgingTopic.TELOMERES, HealthAtlasAgingTopic.forItem("skin-organ"))
        assertEquals(HealthAtlasAgingTopic.SENESCENCE, HealthAtlasAgingTopic.forItem("cell-t-cell"))
        assertEquals(HealthAtlasAgingTopic.DYSBIOSIS, HealthAtlasAgingTopic.forItem("colon"))
        assertEquals(HealthAtlasAgingTopic.GENOME, HealthAtlasAgingTopic.forItem("unknown"))
        assertEquals(mapOf(
            HealthAtlasAgingTopic.TELOMERES to HealthAtlasAgingStudy.TELOMERES,
            HealthAtlasAgingTopic.SENESCENCE to HealthAtlasAgingStudy.T_CELLS,
        ), HealthAtlasAgingTopic.entries.mapNotNull { topic -> topic.study?.let { topic to it } }.toMap())
    }
}
