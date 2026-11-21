package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class HealthAtlasGasExchangeTest {
    @Test fun gasesHaveOppositeDirectionsAndDifferentPartialPressureGradients() {
        val (oxygen, carbon) = HealthAtlasGasExchange.gradients
        assertEquals(HealthAtlasGas.OXYGEN, oxygen.gas)
        assertTrue(oxygen.towardBlood); assertEquals(64, oxygen.difference)
        assertEquals(HealthAtlasGas.CARBON_DIOXIDE, carbon.gas)
        assertFalse(carbon.towardBlood); assertEquals(5, carbon.difference)
    }
    @Test fun bothGasMarkersMoveAtEveryPhaseWithoutInferringARealSpeed() {
        for (phase in listOf(0f, .1f, .25f, .5f, .8f, 1f)) {
            assertEquals(phase, HealthAtlasGasExchange.position(HealthAtlasGas.OXYGEN, phase), 0f)
            assertEquals(1f - phase, HealthAtlasGasExchange.position(HealthAtlasGas.CARBON_DIOXIDE, phase), 0f)
        }
        assertEquals(0f, HealthAtlasGasExchange.phase(Float.NaN), 0f)
        assertEquals(0f, HealthAtlasGasExchange.phase(-1f), 0f)
        assertEquals(3, HealthAtlasGasExchange.stage(2f))
    }
    @Test fun illustrativePressuresStayIndependentOfVentilationAndDiffusionControls() {
        val examples = HealthAtlasGasExchange.gradients.toList()
        assertEquals(HealthAtlasPhysiologyKind.VENTILATION, HealthAtlasPhysiologyKind.forItem("alveoli"))
        val ventilation = HealthAtlasPhysiology(HealthAtlasPhysiologyKind.VENTILATION)
        assertEquals(4.2, ventilation.result, 1e-9)
        assertEquals(10.5, ventilation.withInput(0, 30).result, 1e-9)
        val diffusion = requireNotNull(HealthAtlasPhysiology.restore("respiratory-membrane", intArrayOf(100, 100, 100)))
        assertEquals(HealthAtlasPhysiologyKind.ALVEOLAR_DIFFUSION, diffusion.kind)
        assertEquals(1.0, diffusion.result, 1e-9)
        assertEquals(0.0, diffusion.withInput(0, 0).result, 1e-9)
        assertEquals(examples, HealthAtlasGasExchange.gradients)
        assertTrue(HealthAtlasGasExchange.supports("pulmonary-capillaries"))
        assertFalse(HealthAtlasGasExchange.supports("cell-type-i-pneumocyte"))
        assertFalse(HealthAtlasGasExchange.supports("capillaries"))
    }
    @Test fun pulmonaryInitialStateAndOldStateFallbackRemainValid() {
        val initial = HealthAtlasSimulation.initial("alveoli")
        assertEquals(6.0, initial.minuteVentilation(), 1e-9)
        assertNotNull(HealthAtlasPhysiology.restore("alveoli", intArrayOf(initial.first, initial.second, 150)))
        assertNull(HealthAtlasPhysiology.restore("alveoli", intArrayOf(70, 70, 150)))
    }
    @Test fun optionalReferencesRejectNonPaperOrPrivateLocations() {
        fun model(reference: String?) = HealthAtlasMechanism("test", "cell", "Test", listOf("A", "B", "C", "D"), "22-1-organs", reference)
        assertTrue(model(null).source.startsWith("https://openstax.org/"))
        val paper = "https://pubmed.ncbi.nlm.nih.gov/29874100/"
        assertEquals(paper, model(paper).source)
        for (bad in listOf("", "file:///private", "$paper?secret=x", "http://pubmed.ncbi.nlm.nih.gov/29874100/",
            "https://pubmed.ncbi.nlm.nih.gov.evil/29874100/")) assertTrue(runCatching { model(bad) }.isFailure)
    }
}
