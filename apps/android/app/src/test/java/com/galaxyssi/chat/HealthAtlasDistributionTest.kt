package com.galaxyssi.chat

import kotlin.math.exp
import org.junit.Assert.*
import org.junit.Test

class HealthAtlasDistributionTest {
    @Test fun analyticalSolutionMatchesIndependentMatrixExponentialFixtures() {
        // expm([[-k10-k12,k21,0],[k12,-k21,0],[k10,0,0]]*t) * [100,0,0].
        // Independent SciPy matrix-exponential fixtures, not outputs of the production formula.
        val cases = listOf(
            HealthAtlasDistribution(30, 15, 10, 16) to doubleArrayOf(31.31146654418996, 46.72275917640283, 21.96577427940722),
            HealthAtlasDistribution(300, 100, 10, 8) to doubleArrayOf(22.94872068963114, 70.48922199949571, 6.56205731087311),
            HealthAtlasDistribution(1, 300, 1, 192) to doubleArrayOf(61.77014723483772, .20658681812629, 38.02326594703583),
            HealthAtlasDistribution(300, 0, 10, 16) to doubleArrayOf(.000411858870753571, 96.7737949752864, 3.22579316584287),
        )
        cases.forEach { (model, expected) ->
            val actual = model.amounts
            listOf(actual.central, actual.peripheral, actual.eliminated).forEachIndexed { i, amount -> assertEquals(expected[i], amount, 1e-10) }
        }
    }
    @Test fun initialTotalIsCentralForEveryRateCombination() {
        for (a in listOf(0, 1, 15, 300)) for (b in listOf(0, 1, 15, 300)) for (e in listOf(0, 1, 15, 300))
            assertEquals(HealthAtlasDistributionAmounts(100.0, 0.0, 0.0), HealthAtlasDistribution(a, b, e, 0).amounts)
    }
    @Test fun amountsStayFinitePositiveAndConservedAcrossTheControlDomain() {
        for (a in listOf(0, 1, 10, 99, 300)) for (b in listOf(0, 1, 10, 99, 300)) for (e in listOf(0, 1, 10, 99, 300)) {
            val model = HealthAtlasDistribution(a, b, e)
            var previousLoss = 0.0
            for (t in 0..192) {
                val result = model.at(t / 4.0)
                listOf(result.central, result.peripheral, result.eliminated).forEach { assertTrue(it.isFinite() && it in 0.0..100.0) }
                assertEquals(100.0, result.central + result.peripheral + result.eliminated, 1e-10)
                assertTrue(result.eliminated + 1e-10 >= previousLoss); previousLoss = result.eliminated
            }
        }
    }
    @Test fun noOutwardTransferReducesToSingleCompartmentEvenAtRepeatedRoots() {
        for (rate in listOf(0, 10, 300)) for (t in listOf(0.0, 1e-8, 1.0, 48.0)) {
            val result = HealthAtlasDistribution(0, rate, rate).at(t)
            assertEquals(100.0 * exp(-rate / 100.0 * t), result.central, 1e-12)
            assertEquals(0.0, result.peripheral, 0.0)
        }
    }
    @Test fun zeroEliminationApproachesPartitionEquilibriumWithoutLosingMass() {
        val result = HealthAtlasDistribution(30, 15, 0).at(48.0)
        assertEquals(100.0 / 3.0, result.central, 1e-6)
        assertEquals(200.0 / 3.0, result.peripheral, 1e-6)
        assertEquals(0.0, result.eliminated, 1e-10)
    }
    @Test fun derivativesFollowTheDocumentedAmountEquations() {
        val model = HealthAtlasDistribution()
        val t = 2.0; val h = 1e-5; val now = model.at(t); val before = model.at(t - h); val after = model.at(t + h)
        assertEquals(-(model.k10 + model.k12) * now.central + model.k21 * now.peripheral,
            (after.central - before.central) / (2 * h), 1e-7)
        assertEquals(model.k12 * now.central - model.k21 * now.peripheral,
            (after.peripheral - before.peripheral) / (2 * h), 1e-7)
        assertEquals(model.k10 * now.central, (after.eliminated - before.eliminated) / (2 * h), 1e-7)
    }
    @Test fun invalidInputsAndSavedStatesCannotProduceAModel() {
        listOf(-1, 301).forEach { bad ->
            assertThrows(IllegalArgumentException::class.java) { HealthAtlasDistribution(outward = bad) }
            assertThrows(IllegalArgumentException::class.java) { HealthAtlasDistribution(returning = bad) }
            assertThrows(IllegalArgumentException::class.java) { HealthAtlasDistribution(elimination = bad) }
        }
        listOf(-1, 193).forEach { assertThrows(IllegalArgumentException::class.java) { HealthAtlasDistribution(quarterHours = it) } }
        listOf(Double.NaN, Double.POSITIVE_INFINITY, -1.0, 49.0).forEach {
            assertThrows(IllegalArgumentException::class.java) { HealthAtlasDistribution().at(it) }
        }
        listOf(null, intArrayOf(), intArrayOf(2, 30, 15, 10, 16), intArrayOf(1, 301, 15, 10, 16),
            intArrayOf(1, 30, 15, 10, -1)).forEach { assertNull(HealthAtlasDrugState.restore(it)) }
    }
    @Test fun drugModesAndAllInputsRoundTripIndependently() {
        val state = HealthAtlasDrugState(HealthAtlasDrugMode.TWO, HealthAtlasDistribution(100, 50, 20, 47))
        assertEquals(state, HealthAtlasDrugState.restore(state.encode()))
        assertEquals(11.75, state.distribution.hours, 0.0)
        assertEquals(state.distribution, state.copy(mode = HealthAtlasDrugMode.SINGLE).distribution)
    }
}
