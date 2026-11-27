package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class TeamPredictionContrastTest {
    private val words = TeamContrastText()
    private fun row(inputDirection: String = "higher", expected: String = "lower") = JSONObject()
        .put("purpose", "Estimate spare capacity")
        .put("input", "arrival rate")
        .put("input_direction", inputDirection)
        .put("readout", "free slots")
        .put("expected_direction", expected)
        .put("alternative", "A scheduled release freed slots")
        .put("gap", "Independent release records")

    @Test fun onlyReadoutDirectionChangesUnderTheSameAssumptions() {
        for (input in listOf("lower", "higher")) for ((predicted, contrary) in listOf("higher" to "lower", "lower" to "higher")) {
            val lines = TeamPredictionContrast.render(row(input, predicted), words).lines()
            assertEquals(4, lines.size)
            assertEquals("Purpose: Estimate spare capacity", lines[0])
            assertEquals("Prediction: If arrival rate is $input, a valid reading of free slots should be $predicted.", lines[1])
            assertTrue(lines[2].contains("under the same assumptions, if arrival rate is $input, a valid reading of free slots that is $contrary", ignoreCase = true))
            assertTrue(lines[2].contains("a missing, invalid or uninterpretable measurement would not"))
            assertTrue(lines[3].contains("Alternative explanation: A scheduled release freed slots; missing evidence: Independent release records."))
            assertTrue(lines[3].contains("not an experimental or clinical conclusion"))
        }
    }

    @Test fun localizedFormatCanReorderAndRepeatSlots() {
        val localized = TeamContrastText("%8\$s|%7\$s|%2\$s%3\$s|%4\$s%5\$s|%2\$s%3\$s|%4\$s%6\$s|%1\$s", "更高", "更低")
        assertEquals("Independent release records|A scheduled release freed slots|arrival rate更低|free slots更高|arrival rate更低|free slots更低|Estimate spare capacity",
            TeamPredictionContrast.render(row("lower", "higher"), localized))
    }

    @Test fun allSevenKeysAreRequiredAndValuesAreNotCoerced() {
        for (key in row().keys().asSequence().toList()) {
            assertThrows(IllegalArgumentException::class.java) { TeamPredictionContrast.render(row().apply { remove(key) }, words) }
            for (wrong in listOf(JSONObject.NULL, 42, true, JSONObject())) {
                assertThrows(IllegalArgumentException::class.java) { TeamPredictionContrast.render(row().put(key, wrong), words) }
            }
        }
        assertThrows(IllegalArgumentException::class.java) { TeamPredictionContrast.render(row().put("contrary_direction", "higher"), words) }
        for (key in listOf("input_direction", "expected_direction")) for (invalid in listOf("Higher", "down", "lower ")) {
            assertThrows(IllegalArgumentException::class.java) { TeamPredictionContrast.render(row().put(key, invalid), words) }
        }
    }

    @Test fun rejectsEquivalentLabelsPlaceholdersAndUnsafeOrOversizeFields() {
        for ((key, invalid) in listOf("input" to " ＦＲＥＥ   slots ", "purpose" to "", "gap" to "  ",
            "purpose" to "TBD", "input" to "input", "alternative" to "[insert explanation]", "gap" to "待补充",
            "readout" to "...", "gap" to "count\n", "alternative" to "one\u2028two", "gap" to "one\u202etwo",
            "input" to "<tag>", "purpose" to "slot %1\$s", "readout" to "a".repeat(121), "purpose" to "b".repeat(401))) {
            assertThrows(IllegalArgumentException::class.java) { TeamPredictionContrast.render(row().put(key, invalid), words) }
        }
    }

    @Test fun explicitContraryObservationQuestionsOnly() {
        for (ask in listOf("Under the same assumptions, which observation would be incompatible with the prediction?",
            "What would make you abandon this explanation?", "What result would prove this hypothesis wrong?",
            "Which observation would falsify the prediction?", "同样前提下哪种观察与该预测不能同时成立", "什么现象会让你放弃这个解释",
            "请预测队列长度；哪种结果能推翻这个预测？")) {
            assertTrue(ask, TeamPredictionContrast.requested(ask))
        }
        for (other in listOf("Predict queue length and identify missing evidence.", "Discuss falsifiability.",
            "Which result supports the prediction?", "What result would not contradict this prediction?",
            "Translate: What would make you abandon this explanation?", "The title is “Which observation would falsify the prediction?”",
            "在相同前提下，队列会怎样变化？", "哪些观察不能推翻该预测？", "不要讨论什么现象会让你放弃这个解释。")) {
            assertFalse(other, TeamPredictionContrast.requested(other))
        }
    }
}
