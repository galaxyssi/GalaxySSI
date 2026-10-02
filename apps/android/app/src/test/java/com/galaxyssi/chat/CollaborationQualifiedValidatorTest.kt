package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationQualifiedValidatorTest {
    private val validator = CollaborationExactIntegerSumValidator
    private fun spec(values: List<String> = listOf("2", "3")) = JSONObject().put("id", validator.id).put("operands", JSONArray(values))
    private fun result(value: String = "5") = JSONObject().put("validator_id", validator.id).put("result", value)
    private fun fixture(value: String = "5", values: List<String> = listOf("2", "3"),
                        requirement: String = validator.requirement(values), verification: String = "computational",
                        specification: JSONObject = spec(values), reviewer: String = "reviewer") =
        CollaborationGoalAcceptanceTest.Fixture(requirement = requirement, verification = verification,
            validator = specification, computation = result(value), reviewer = reviewer)

    @Test fun deterministicFixtureUsesProductionGateAndHostRecomputation() {
        val f = fixture()
        val receipt = f.evaluate()
        assertTrue(receipt.feedback, receipt.accepted)
        assertFalse(fixture(value = "6").evaluate().accepted)
        assertFalse(fixture(reviewer = "author").evaluate().accepted)
    }

    @Test fun exactArithmeticDoesNotOverflowMachineIntegers() {
        val f = fixture(values = listOf("9223372036854775807", "1"), value = "9223372036854775808")
        assertTrue(f.evaluate().feedback, f.evaluate().accepted)
        assertTrue(fixture(values = listOf("-100", "100"), value = "0").evaluate().accepted)
        assertFalse(fixture(value = "05").evaluate().accepted)
    }

    @Test fun broaderClaimsAndAllPhysicalDomainsRemainUnsupported() {
        val physical = fixture(verification = "physical")
        assertFalse(physical.evaluate().accepted)
        assertFalse(fixture(requirement = "Prove this reactor is safe using the sum 2 + 3").evaluate().accepted)
        assertFalse(fixture(specification = spec().put("id", "model_says_verified")).evaluate().accepted)
        assertFalse(fixture(verification = "documentary").evaluate().accepted)
    }

    @Test fun simulationsAndProposalsNeverBecomeObservedPhysicalOrComputationalResults() {
        listOf("physical", "computational").forEach { verification ->
            listOf("simulation", "proposal").forEach { kind ->
                val f = fixture(verification = verification)
                val report = f.assessment()
                report.getJSONArray("criteria").getJSONObject(0).put("evidence_kind", kind)
                val receipt = f.evaluate(report.toString())
                assertFalse(receipt.accepted)
                assertTrue(receipt.feedback.contains("simulations"))
            }
        }
    }

    @Test fun validatorInputsCannotBeSubstitutedDroppedOrAddedAtCompletion() {
        listOf(spec(listOf("1", "4")), JSONObject.NULL, spec().put("id", "physical.v1")).forEach { replacement ->
            val f = fixture()
            val report = f.assessment()
            report.getJSONArray("criteria").getJSONObject(0).put("validator", replacement)
            assertFalse(f.evaluate(report.toString()).accepted)
        }
        val f = fixture()
        val priorWithoutSpec = JSONArray(f.prior).apply { getJSONObject(0).remove("validator") }
        assertFalse(f.evaluate(previous = priorWithoutSpec.toString()).accepted)
        val missing = f.assessment()
        missing.getJSONArray("criteria").getJSONObject(0).remove("validator")
        assertFalse(f.evaluate(missing.toString()).accepted)
    }

    @Test fun boundedCanonicalInputsRejectCoercionFloatingPointAndResourceAbuse() {
        listOf(JSONArray().put(2).put(3), JSONArray().put("2.0").put("3"), JSONArray().put("+2").put("3"),
            JSONArray().put("02").put("3"), JSONArray().put("-0").put("3"), JSONArray().put("1".repeat(257)).put("3"),
            JSONArray(), JSONArray().put("5"), JSONArray(List(33) { "1" })).forEach { values ->
            assertThrows(IllegalArgumentException::class.java) { validator.operands(spec().put("operands", values)) }
        }
        assertThrows(IllegalArgumentException::class.java) { validator.operands(spec().put("command", "external execution")) }
    }

    @Test fun fabricatedModelValidationMetadataDoesNotReplaceHostCheck() {
        val f = fixture(value = "wrong")
        val report = f.assessment().put("validator_result", JSONObject().put("accepted", true).put("qualified", true))
        assertFalse(f.evaluate(report.toString()).accepted)
    }

    @Test fun resultTypesAndExtraClaimsCannotBeCoercedIntoQualification() {
        val f = fixture()
        listOf(result().put("result", 5), result().put("physical", true), result().put("validator_id", "physical.v1")).forEach { value ->
            assertThrows(IllegalArgumentException::class.java) { validator.validate(f.criterion, JSONObject().put("computation", value)) }
        }
    }
}
