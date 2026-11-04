package com.galaxyssi.chat

/** Suggestions only. Unknown units and measurement times deliberately remain unset. */
internal object HealthOcrCandidates {
    private val number = "([0-9]+(?:[.,][0-9]+)?)"
    private val units = mapOf(
        "mmHg" to "mmHg|\u6beb\u7c73\u6c5e\u67f1", "kPa" to "\\bkPa\\b",
        "mmol/L" to "\\bmmol\\s*/\\s*l\\b", "mg/dL" to "\\bmg\\s*/\\s*dl\\b",
        "g/L" to "\\bg\\s*/\\s*l\\b", "g/dL" to "\\bg\\s*/\\s*dl\\b",
        "kg" to "\\bkg\\b|\u5343\u514b|\u516c\u65a4", "lb" to "\\blbs?\\b|\u78c5", "bpm" to "\\bbpm\\b|\u6b21\\s*/\\s*\u5206"
    ).mapValues { Regex(it.value, RegexOption.IGNORE_CASE) }
    private fun unit(text: String, metric: HealthMetric) = metric.units.filter { units.getValue(it).containsMatchIn(text) }.singleOrNull().orEmpty()
    private val aliases = linkedMapOf(
        "systolic" to Regex("(?:\u6536\u7f29\u538b|\u9ad8\u538b|\\bSYS\\b|\\bsystolic\\b)", RegexOption.IGNORE_CASE),
        "diastolic" to Regex("(?:\u8212\u5f20\u538b|\u4f4e\u538b|\\bDIA\\b|\\bdiastolic\\b)", RegexOption.IGNORE_CASE),
        "pulse" to Regex("(?:\u8109\u640f|\u5fc3\u7387|\\bPUL\\b|\\bpulse\\b|\\bheart rate\\b)", RegexOption.IGNORE_CASE),
        "glucose" to Regex("(?:\u8461\u8404\u7cd6|\u8840\u7cd6|\\bglucose\\b|\\bGLU\\b)", RegexOption.IGNORE_CASE),
        "weight" to Regex("(?:\u4f53\u91cd|\\bweight\\b)", RegexOption.IGNORE_CASE),
        "cholesterol" to Regex("(?:\u603b\u80c6\u56fa\u9187|\\bTC\\b|\\btotal cholesterol\\b)", RegexOption.IGNORE_CASE),
        "hemoglobin" to Regex("(?:(?<!\u5e73\u5747|\u7cd6\u5316)\u8840\u7ea2\u86cb\u767d(?!\u6d53\u5ea6|\u542b\u91cf|A1c)|\\bHGB\\b|\\bhemoglobin\\b(?!\\s*A1c))", RegexOption.IGNORE_CASE)
    )
    fun suggest(job: HealthImportJob, original: HealthOriginal, input: HealthOcrPage): List<HealthDraft> {
        val page = if (job.mode == "device") input.copy(lines = alignDeviceLines(input.lines)) else input
        val drafts = mutableListOf<HealthDraft>()
        fun draft(metric: HealthMetric, values: Map<String, String>, unit: String, lines: List<HealthOcrLine>) {
            val identity = (listOf(metric.name, unit) + values.toSortedMap().map { "${it.key}=${it.value}" } +
                lines.map { it.text.trim().replace(Regex("\\s+"), " ") + "|" + it.box.joinToString(",") }).joinToString("\u0000").toByteArray(Charsets.UTF_8)
            val key = try { java.security.MessageDigest.getInstance("SHA-256").digest(identity).take(20).joinToString("") { "%02x".format(it) } }
                finally { identity.fill(0) }
            val evidence = HealthEvidence(original.id, job.id, "${metric.name.lowercase(java.util.Locale.ROOT)}-$key", original.sha256, page.page,
                lines.joinToString("\n") { it.text }.take(8000), lines.map { it.box }.filter { it.size == 4 })
            drafts += HealthDraft(metric, values, unit, measuredAt = 0, evidence = evidence)
        }
        val pressureLines = page.lines.mapIndexedNotNull { index, line ->
            if (!Regex("\u8840\u538b|\\bBP\\b|blood pressure", RegexOption.IGNORE_CASE).containsMatchIn(line.text)) return@mapIndexedNotNull null
            val pair = Regex("$number\\s*[/\uff0f]\\s*$number").find(line.text) ?: return@mapIndexedNotNull null
            if (!safeValue(line.text, pair.range.first) || !safeSuffix(line.text, pair.range.last + 1)) return@mapIndexedNotNull null
            val prefix = line.text.substring(0, pair.range.first)
            if (!Regex("(?:\u8840\u538b|\\bBP\\b|blood pressure)[\\s:\uff1a=]*(?:mmHg|kPa)?[\\s:\uff1a=]*$", RegexOption.IGNORE_CASE).containsMatchIn(prefix)) return@mapIndexedNotNull null
            draft(HealthMetric.BLOOD_PRESSURE, mapOf("systolic" to pair.groupValues[1], "diastolic" to pair.groupValues[2]),
                unit(line.text, HealthMetric.BLOOD_PRESSURE), listOf(line))
            index
        }
        val components = linkedMapOf<String, MutableList<Pair<Int, String>>>()
        page.lines.forEachIndexed { index, line ->
            if (index in pressureLines) return@forEachIndexed
            for ((field, alias) in aliases) {
                val label = alias.find(line.text) ?: continue
                val match = Regex(number).find(line.text, label.range.last + 1) ?: continue
                val gap = line.text.substring(label.range.last + 1, match.range.first)
                if (!gap.matches(Regex("[\\s:\uff1a=()\uff08\uff09]*(?:(?:mmHg|kPa|bpm|mmol/L|mg/dL|g/dL|g/L|kg|lb)[\\s:\uff1a=()\uff08\uff09]*)?", RegexOption.IGNORE_CASE))) continue
                if (field == "hemoglobin" && Regex("\u5e73\u5747|\u7ea2\u7ec6\u80de|\u7cd6\u5316|\\bMCHC?\\b|A1c|glycated|corpuscular|mean", RegexOption.IGNORE_CASE).containsMatchIn(line.text)) continue
                if (!safeValue(line.text, match.range.first) || !safeSuffix(line.text, match.range.last + 1)) continue
                val value = HealthObservationPolicy.canonicalNumber(match.groupValues[1]) ?: continue
                when (field) {
                    "systolic", "diastolic", "pulse" -> components.getOrPut(field) { mutableListOf() }.add(index to value)
                    "glucose", "cholesterol" -> draft(if (field == "glucose") HealthMetric.GLUCOSE else HealthMetric.CHOLESTEROL, mapOf(field to value),
                        unit(line.text, HealthMetric.GLUCOSE), listOf(line))
                    "weight" -> draft(HealthMetric.WEIGHT, mapOf(field to value),
                        unit(line.text, HealthMetric.WEIGHT), listOf(line))
                    "hemoglobin" -> draft(HealthMetric.HEMOGLOBIN, mapOf(field to value),
                        unit(line.text, HealthMetric.HEMOGLOBIN), listOf(line))
                }
            }
        }
        val systolic = components["systolic"].orEmpty()
        val diastolic = components["diastolic"].orEmpty()
        val pulse = components["pulse"].orEmpty()
        if (systolic.size == 1 && diastolic.size == 1 && kotlin.math.abs(systolic[0].first - diastolic[0].first) <= 5) {
            val selected = listOf(systolic[0], diastolic[0]) + pulse.singleOrNull()?.takeIf {
                kotlin.math.abs(it.first - diastolic[0].first) <= 3
            }.let { listOfNotNull(it) }
            val lines = selected.map { page.lines[it.first] }
            val fields = linkedMapOf("systolic" to systolic[0].second, "diastolic" to diastolic[0].second)
            if (selected.size == 3) fields["pulse"] = selected[2].second
            // Device displays often omit the unit; confirmation must not silently assume it.
            val unitLines = lines + if (job.mode == "device") page.lines.filter { line ->
                line.text.trim().matches(Regex("mmHg|kPa|\u6beb\u7c73\u6c5e\u67f1", RegexOption.IGNORE_CASE))
            } else emptyList()
            draft(HealthMetric.BLOOD_PRESSURE, fields, unit(unitLines.joinToString("\n") { it.text }, HealthMetric.BLOOD_PRESSURE), lines)
        } else if (systolic.isEmpty() && diastolic.isEmpty()) {
            pulse.forEach { (index, value) -> draft(HealthMetric.HEART_RATE, mapOf("pulse" to value),
                if (Regex("bpm|\u6b21\\s*/\\s*\u5206", RegexOption.IGNORE_CASE).containsMatchIn(page.lines[index].text)) "bpm" else "",
                listOf(page.lines[index])) }
        }
        return drafts.distinctBy { it.evidence!!.candidateId }
    }
    private fun alignDeviceLines(lines: List<HealthOcrLine>): List<HealthOcrLine> = lines.map { line ->
        if (line.box.size != 4 || aliases.filterKeys { it in listOf("systolic", "diastolic", "pulse") }.values.none { it.containsMatchIn(line.text) } ||
            Regex(number).containsMatchIn(line.text)) return@map line
        val box = line.box
        val center = (box[1] + box[3]) / 2
        val candidates = lines.filter { candidate ->
            candidate.box.size == 4 && candidate.text.trim().matches(Regex("[0-9]+(?:[.,][0-9]+)?")) &&
                kotlin.math.abs((candidate.box[1] + candidate.box[3]) / 2 - center) <= maxOf(25, box[3] - box[1])
        }
        if (candidates.size != 1) line else {
            val value = candidates.single()
            line.copy(text = line.text + "\n" + value.text, box = listOf(minOf(box[0], value.box[0]), minOf(box[1], value.box[1]),
                maxOf(box[2], value.box[2]), maxOf(box[3], value.box[3])))
        }
    }
    private fun safeValue(text: String, start: Int): Boolean =
        !Regex("\u53c2\u8003|\u6b63\u5e38\u8303\u56f4|reference|range", RegexOption.IGNORE_CASE).containsMatchIn(text) &&
            text.take(start).takeLast(3).none { it in "<>\u2264\u2265\u00b1~\uff5e-" }
    private fun safeSuffix(text: String, end: Int): Boolean =
        !Regex("^\\s*(?:[-\u2013\u2014~\uff5e\u00b1/\uff0f]|[.,][0-9]|[eE][+-]?[0-9]|\u81f3\\s*[0-9])").containsMatchIn(text.substring(end))
}
