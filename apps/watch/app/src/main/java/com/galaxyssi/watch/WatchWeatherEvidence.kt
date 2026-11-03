package com.galaxyssi.watch

import org.json.JSONObject

/** Preserve verified forecast dates and units if the final model request fails. */
internal object WatchWeatherEvidence {
    fun fallback(raw: String, rainLabel: String, summary: String): String? = runCatching {
        val output = JSONObject(raw)
        if (output.optString("status") != "completed") return null
        val item = output.getJSONObject("evidence_pack").getJSONArray("items").getJSONObject(0)
        val weather = JSONObject(item.getString("content"))
        if (weather.optString("provider") != "Open-Meteo") return null
        val source = weather.optString("geocoding_source") // Require structured provenance as well as dates.
        if (!source.startsWith("https://geocoding-api.open-meteo.com/")) return null
        val daily = weather.getJSONObject("daily")
        val units = weather.getJSONObject("daily_units")
        val dates = daily.getJSONArray("time")
        if (dates.length() == 0 || dates.getString(0) != weather.getString("forecast_date")) return null
        val lines = (0 until dates.length()).map { i ->
            fun metric(key: String): String? {
                val value = daily.optJSONArray(key)?.opt(i)
                return if (value == null || value == JSONObject.NULL) null else "$value${units.optString(key)}"
            }
            val low = metric("temperature_2m_min")
            val high = metric("temperature_2m_max")
            val rain = metric("precipitation_probability_max")
            dates.getString(i) + ": " + listOfNotNull(
                if (low != null && high != null) "$low–$high" else low ?: high,
                rain?.let { "$rainLabel $it" }
            ).joinToString(" · ")
        }
        val url = item.getString("url")
        if (!url.startsWith("https://api.open-meteo.com/")) return null
        val place = weather.getJSONObject("location").getString("name")
        "$place (${weather.getString("timezone")})\n\n" + lines.joinToString("\n") +
            "\n\n[Open-Meteo]($url)\n" + summary
    }.getOrNull()
}
