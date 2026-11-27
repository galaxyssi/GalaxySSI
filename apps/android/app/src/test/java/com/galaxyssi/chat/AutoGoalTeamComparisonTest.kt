package com.galaxyssi.chat

import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AutoGoalTeamComparisonTest {
    private val sheet = """
        Compare alternative bids; retain the unit.
        | input | gate | west | east |
        |---|---|---|---|
        | price | < 2.10 | 2.10 | 2.09 |
        | reserve | >= 3 | 4 | 3 |
        | other | - | -4 | 2 |
        Both figures are hypothetical.
    """.trimIndent()

    @Test fun exactSourceValuesAndStrictVsInclusiveGatesDetermineTheSet() {
        val result = requireNotNull(TeamComparisonSheet.evaluate(sheet))
        assertTrue(result.plannerObjective.startsWith("Compare alternative bids"))
        assertTrue(result.plannerObjective.endsWith("Both figures are hypothetical."))
        assertEquals("""["east"]""", result.evidence.getJSONArray("pass_all").toString())
        val row = result.evidence.getJSONArray("rows").getJSONObject(0).getJSONObject("series")
        assertEquals("2.10", row.getJSONObject("west").getString("value"))
        assertFalse(row.getJSONObject("west").getBoolean("pass"))
        val swapped = sheet.replace("< 2.10", ">= 2.10")
        assertEquals("""["west"]""", TeamComparisonSheet.evaluate(swapped)!!.evidence.getJSONArray("pass_all").toString())
        val localized = sheet.replace("input | gate", "输入 | 门槛")
        assertNotNull(TeamComparisonSheet.evaluate(localized))
    }

    @Test fun doesNotInferMissingUnitsDataOrAmbiguousInputs() {
        for (bad in listOf(sheet.replace("2.09", "2.09 mg"), sheet.replace("east", "west"),
            sheet.replace("reserve", "price"), sheet.replace("< 2.10", "~2.10"),
            sheet.replace(">= 3", "-").replace("< 2.10", "-"), sheet+"\n"+sheet)) {
            assertNull(TeamComparisonSheet.evaluate(bad))
        }
    }

    @Test fun auditCannotApproveTheWrongSourceSeriesOrSkipTheStructuredCheck() = runBlocking {
        for (tail in listOf("", ""","pass_all":["west"]""", ""","pass_all":["east","east"]""", ""","pass_all":["east"]""")) {
            val events = mutableListOf<String>()
            val result = runCatching {
                runAutoGoalTeam(sheet, { _, input ->
                    val p = JSONObject(input)
                    when (p.getString("stage")) {
                        "plan" -> "WORK|-|Compare values\nREVIEW|1|Verify gates\nSYNTHESIS|Report alternatives"
                        "role" -> {
                            assertEquals(sheet, p.getString("objective"))
                            """{"finding":"A strict boundary excludes equality."}"""
                        }
                        "synthesis" -> """{"answer":"Only east meets every gate."}"""
                        else -> {
                            assertEquals("east", p.getJSONObject("verified_table").getJSONArray("pass_all").getString(0))
                            """{"purpose":"Compare the bids.","limitation":"Quoted bids only."$tail}"""
                        }
                    }
                }, events::add)
            }
            if (tail.endsWith("""["east"]""")) {
                val answer = result.getOrThrow()
                assertTrue("Pass all gates: east" in answer && "Quoted bids only." in answer)
                assertFalse("Only east meets every gate." in answer)
            }
            else {
                val mismatch = result.exceptionOrNull() as TeamTableMismatch
                assertTrue("Pass all gates: east" in mismatch.verified)
                assertFalse("Only east meets every gate." in mismatch.verified)
                assertFalse("Team completed." in events)
            }
        }
    }
}
