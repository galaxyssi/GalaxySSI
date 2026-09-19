package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

/** Shares the packaged contract with Desktop. Lint success never proves factual truth. */
internal class ResearchQualityStandard(private val contract: JSONObject) {
    val version: String = contract.getString("version")
    val prompt: String = "GalaxySSI research quality ($version):\n" +
        contract.getJSONArray("rules").let { rules ->
            (0 until rules.length()).joinToString("\n") { "- ${rules.getString(it)}" }
        }
    private val rules = contract.getJSONArray("risk_rules").let { rules ->
        (0 until rules.length()).map { rules.getJSONObject(it).let { rule ->
            rule.getString("id") to Regex(rule.getString("pattern"))
        } }
    }

    fun assess(answer: String, researchObserved: Boolean): JSONObject {
        val prose = Regex("```[\\s\\S]*?```").replace(answer, "").lineSequence()
            .filterNot { it.trimStart().startsWith(">") }.joinToString("\n")
        val observed = researchObserved || Regex("\\]\\(https?://").containsMatchIn(prose)
        val risks = rules.filter { observed && it.second.containsMatchIn(prose) }.map { it.first }
        return JSONObject().put("contract", version)
            .put("status", if (risks.isNotEmpty()) "needs_review" else if (observed) "no_structural_risk_detected" else "not_applicable")
            .put("risks", org.json.JSONArray(risks))
            .put("semantic_verification", "not_independently_verified")
            .put("research_observed", observed)
    }

    fun repairPrompt(report: JSONObject): String =
        "GalaxySSI research quality review: ${report.getJSONArray("risks")}. " + contract.getString("repair")

    companion object {
        @Volatile private var cached: ResearchQualityStandard? = null
        val loaded: ResearchQualityStandard? get() = cached
        fun get(context: Context): ResearchQualityStandard = cached ?: synchronized(this) {
            cached ?: ResearchQualityStandard(JSONObject(context.assets.open("research-quality.json")
                .bufferedReader().use { it.readText() })).also { cached = it }
        }
    }
}
