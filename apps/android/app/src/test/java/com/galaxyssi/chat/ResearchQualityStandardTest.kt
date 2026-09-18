package com.galaxyssi.chat

import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ResearchQualityStandardTest {
    private val directory = File("../../desktop/core/galaxyssi-link/backend/research_contract")
    private val standard = ResearchQualityStandard(JSONObject(File(directory, "research-quality.json").readText()))

    @Test fun sameCrossPlatformCasesNeverClaimSemanticTruth() {
        val cases = JSONArray(File(directory, "quality-cases.json").readText())
        for (index in 0 until cases.length()) {
            val case = cases.getJSONObject(index)
            val report = standard.assess(case.getString("answer"), case.getBoolean("research"))
            assertEquals(case.getString("id"), case.getJSONArray("risks").toString(), report.getJSONArray("risks").toString())
            assertEquals("not_independently_verified", report.getString("semantic_verification"))
        }
    }

    @Test fun promptCoversEvidenceScopeNativeLoopsAndDelivery() {
        assertTrue(standard.prompt.contains("claim against a specific source passage"))
        assertTrue(standard.prompt.contains("Remote Agents own their native research loop"))
        assertTrue(standard.prompt.contains("application receipt"))
        assertTrue(standard.prompt.contains("matching initials alone are insufficient"))
        assertTrue(standard.repairPrompt(standard.assess("No authoritative records exist.", true)).contains("not proof"))
    }
}
