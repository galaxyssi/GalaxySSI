package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthAtlasUreterDeliveryTeachingModelTest {
    private val kind = HealthAtlasPhysiologyKind.URETER_DELIVERY

    @Test fun deliveredAndRemainingFluidAccountForAllSixPackets() {
        val initial = HealthAtlasPhysiology(kind)
        assertEquals(6.0, initial.result, 0.0)
        assertEquals(6.0, initial.companionValue, 0.0)
        for (count in kind.inputs[0].range) for (volume in kind.inputs[1].range) {
            val sample = initial.withInput(0, count).withInput(1, volume)
            assertEquals(6.0 * sample.input(1), sample.result + sample.companionValue, 1e-9)
            assertTrue(sample.result in kind.minimum..kind.maximum)
            assertEquals(sample.result, sample.resultAt(count.toDouble()), 0.0)
        }
    }

    @Test fun playbackCommitsOnePacketOnlyWhenItsTripFinishes() {
        val frame = HealthAtlasUreterDeliveryTeachingModel::frame
        assertEquals(0, frame(0, .5f).arrived)
        assertNull(frame(0, .5f).inTransit)
        assertEquals(0, frame(4, 0f).arrived)
        assertEquals(.5f, requireNotNull(frame(4, .125f).inTransit), 1e-6f)
        assertEquals(1, frame(4, .25f).arrived)
        assertEquals(0f, requireNotNull(frame(4, .25f).inTransit), 0f)
        assertEquals(4, frame(4, 1f).arrived)
        assertNull(frame(4, 1f).inTransit)
    }

    @Test fun modelIsScopedToTheRenalPelvisAndUreters() {
        assertEquals(setOf("renal-pelvis", "ureters"), kind.teaching?.entryIds)
        assertEquals(HealthAtlasPhysiologyKind.RENAL_EXCRETION, HealthAtlasPhysiologyKind.forItem("kidneys"))
        assertEquals(HealthAtlasPhysiologyKind.BLADDER_EXPANSION, HealthAtlasPhysiologyKind.forItem("bladder"))
    }
}
