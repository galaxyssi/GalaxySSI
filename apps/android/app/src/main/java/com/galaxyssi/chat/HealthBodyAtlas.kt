package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

internal enum class HealthAtlasKind { SYSTEM, ORGAN, CELL, FRAGMENT }
internal enum class HealthAtlasTab { STRUCTURE, FUNCTION, VALUES, SIMULATION }

internal data class HealthAtlasItem(
    val id: String, val kind: HealthAtlasKind, val name: String, val description: String,
    val systems: List<String>, val related: List<String>, val mechanism: String,
    val aliases: String, val color: String, val icon: String,
)

internal data class HealthAtlasMechanism(val id: String, val kind: String, val title: String,
    val stages: List<String>, val chapter: String, val reference: String? = null) {
    init { require(reference == null || reference.matches(Regex("https://pubmed\\.ncbi\\.nlm\\.nih\\.gov/[1-9][0-9]*/"))) }
    val source get() = reference ?: "https://openstax.org/books/anatomy-and-physiology-2e/pages/$chapter"
}

/** Public teaching catalogue only. Personal observations never enter this model or its search index. */
internal class HealthBodyAtlas(val items: List<HealthAtlasItem>, val mechanisms: List<HealthAtlasMechanism>) {
    private val index = items.associateBy { it.id }
    private val models = mechanisms.associateBy { it.id }
    val systems get() = items.filter { it.kind == HealthAtlasKind.SYSTEM }
    init {
        require(index.size == items.size && models.size == mechanisms.size)
        require(items.all { it.id.matches(Regex("[a-z0-9]+(?:-[a-z0-9]+)*")) && it.name.isNotBlank() && it.description.isNotBlank() })
        require(items.all { item -> item.systems.isNotEmpty() && item.systems.all { index[it]?.kind == HealthAtlasKind.SYSTEM } &&
            item.related.all(index::containsKey) && item.id !in item.related && models.containsKey(item.mechanism) })
        require(mechanisms.all { it.stages.size == 4 && it.stages.all(String::isNotBlank) && it.chapter.matches(Regex("[a-z0-9-]+")) })
        val microscopicKinds = setOf("cell", "fragment")
        require(items.filter { it.kind == HealthAtlasKind.CELL || it.kind == HealthAtlasKind.FRAGMENT }.all {
            it.mechanism == it.id && models.getValue(it.mechanism).kind == it.kind.name.lowercase(Locale.ROOT)
        }) { "Each microscopic entry requires its own matching mechanism" }
        require(mechanisms.filter { it.kind in microscopicKinds }.all { model ->
            index[model.id]?.let { it.kind.name.lowercase(Locale.ROOT) == model.kind && it.mechanism == model.id } == true
        }) { "Microscopic mechanism owner is missing or mismatched" }
        require(items.all { models.getValue(it.mechanism).kind !in microscopicKinds || it.mechanism == it.id }) {
            "Microscopic mechanisms cannot be assigned to other entries"
        }
    }
    operator fun get(id: String) = index[id]
    fun mechanism(item: HealthAtlasItem) = models.getValue(item.mechanism)
    fun children(item: HealthAtlasItem) = item.related.mapNotNull(index::get)
    fun parents(item: HealthAtlasItem) = items.filter { item.id in it.related && it.kind != HealthAtlasKind.SYSTEM }
    fun cells(item: HealthAtlasItem) = items.filter { it.kind in setOf(HealthAtlasKind.CELL, HealthAtlasKind.FRAGMENT) &&
        (if (item.kind == HealthAtlasKind.SYSTEM) item.id in it.systems else item.id in it.related) }
    fun search(query: String, kind: HealthAtlasKind?, system: String = ""): List<HealthAtlasItem> {
        val words = query.trim().lowercase(Locale.ROOT).split(Regex("\\s+")).filter(String::isNotBlank)
        return items.filter { item ->
            (kind == null || item.kind == kind || kind == HealthAtlasKind.CELL && item.kind == HealthAtlasKind.FRAGMENT) &&
                (system.isEmpty() || system in item.systems) && words.all {
                    (item.name + " " + item.aliases + " " + item.id + " " + item.description).lowercase(Locale.ROOT).contains(it)
                }
        }
    }
    companion object {
        fun load(context: Context): HealthBodyAtlas {
            val root = context.assets.open("health/body-atlas.json").bufferedReader().use { JSONObject(it.readText()) }
            require(root.getInt("schema") == 1)
            fun text(key: String): String {
                require(key.startsWith("health_atlas_"))
                val id = context.resources.getIdentifier(key, "string", context.packageName)
                require(id != 0) { "Missing atlas resource: $key" }
                return context.getString(id)
            }
            val items = root.getJSONArray("entries").objects().map { value ->
                HealthAtlasItem(value.getString("id"), HealthAtlasKind.valueOf(value.getString("kind").uppercase(Locale.ROOT)),
                    text(value.getString("name")), text(value.getString("description")), value.getJSONArray("systems").strings(),
                    value.getJSONArray("related").strings(), value.getString("mechanism"), text(value.getString("aliases")),
                    value.getString("color"), value.getString("icon"))
            }
            val models = root.getJSONArray("mechanisms").objects().map { value ->
                HealthAtlasMechanism(value.getString("id"), value.getString("kind"), text(value.getString("title")),
                    value.getJSONArray("stages").strings().map(::text), value.getString("chapter"),
                    if (value.has("reference")) value.getString("reference") else null)
            }
            return HealthBodyAtlas(items, models)
        }
        private fun JSONArray.strings() = (0 until length()).map(::getString)
        private fun JSONArray.objects() = (0 until length()).map(::getJSONObject)
    }
}

internal object HealthAtlasMetrics {
    fun forItem(item: HealthAtlasItem): List<HealthMetric> = when (item.id) {
        "cardio", "heart", "atria", "ventricles", "heart-valves", "coronary-vessels", "cell-cardiomyocyte" ->
            listOf(HealthMetric.BLOOD_PRESSURE, HealthMetric.RESTING_HEART_RATE, HealthMetric.LDL, HealthMetric.HDL, HealthMetric.TRIGLYCERIDES)
        "blood-vessels", "arteries", "veins", "capillaries", "cell-vascular-endothelial-cell" ->
            listOf(HealthMetric.BLOOD_PRESSURE, HealthMetric.LDL, HealthMetric.HDL)
        "pancreas", "pancreatic-islets", "cell-pancreatic-beta-cell", "cell-pancreatic-alpha-cell" ->
            listOf(HealthMetric.GLUCOSE, HealthMetric.HBA1C)
        "endocrine" -> listOf(HealthMetric.GLUCOSE, HealthMetric.HBA1C, HealthMetric.TSH)
        "thyroid-gland", "cell-thyroid-follicular-cell", "cell-thyrotroph" -> listOf(HealthMetric.TSH)
        "liver", "cell-hepatocyte", "digestive" -> listOf(HealthMetric.ALT, HealthMetric.AST, HealthMetric.ALBUMIN, HealthMetric.TOTAL_BILIRUBIN)
        "urinary", "kidneys", "renal-cortex", "renal-medulla", "renal-pelvis", "nephron", "glomerulus", "renal-tubules", "collecting-ducts", "cell-podocyte",
        "bowmans-capsule", "proximal-tubule", "nephron-loop", "distal-tubule" ->
            listOf(HealthMetric.CREATININE, HealthMetric.UREA, HealthMetric.URINE_PROTEIN)
        "respiratory", "lungs", "alveoli", "respiratory-membrane", "pulmonary-capillaries",
        "cell-type-i-pneumocyte", "cell-type-ii-pneumocyte" -> listOf(HealthMetric.OXYGEN_SATURATION)
        "blood", "bone-marrow", "immune" -> listOf(HealthMetric.HEMOGLOBIN, HealthMetric.RED_BLOOD_CELLS, HealthMetric.WHITE_BLOOD_CELLS, HealthMetric.PLATELETS)
        "cell-erythrocyte" -> listOf(HealthMetric.RED_BLOOD_CELLS, HealthMetric.HEMOGLOBIN, HealthMetric.HEMATOCRIT)
        "fragment-platelet", "cell-megakaryocyte" -> listOf(HealthMetric.PLATELETS)
        "cell-neutrophil" -> listOf(HealthMetric.NEUTROPHIL_COUNT, HealthMetric.NEUTROPHIL_PERCENT)
        else -> emptyList()
    }
}

/** Fixed-input teaching equations, not a patient model or treatment prediction. */
internal data class HealthAtlasSimulation(val first: Int = 70, val second: Int = 70, val phase: Float = 0f, val speed: Float = 1f) {
    init { require(phase.isFinite() && phase in 0f..1f && speed.isFinite() && speed in .5f..2f) }
    fun cardiacOutput(): Double { require(first in 40..160 && second in 30..120); return first * second / 1000.0 }
    fun minuteVentilation(): Double { require(first in 6..30 && second in 200..900); return first * second / 1000.0 }
    val stage get() = (phase.coerceIn(0f, 1f) * 4).toInt().coerceIn(0, 3)
    companion object { fun initial(id: String) = if (id in setOf("respiratory", "lungs", "alveoli")) HealthAtlasSimulation(12, 500) else HealthAtlasSimulation() }
}
