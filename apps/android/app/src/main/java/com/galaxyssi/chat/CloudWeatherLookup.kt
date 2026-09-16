package com.galaxyssi.chat

import org.json.JSONObject
import org.json.JSONArray
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.net.URLEncoder
import java.time.Instant
import java.time.ZoneId

/** Model-selected structured lookup. No prompt keyword routing or guessed coordinates. */
internal object CloudWeatherLookup {
    fun execute(arguments: JSONObject, fetch: (String) -> String, now: Long = System.currentTimeMillis()): AgentNativeJsonObject {
        val location = arguments.optString("location").trim()
        val country = arguments.optString("country_code").trim().uppercase(java.util.Locale.ROOT)
        val region = arguments.optString("region").trim()
        require(location.length in 2..120 && country.matches(Regex("[A-Z]{2}")) && region.length in 1..120) {
            "Provide a city name, ISO country_code and first-level region in English for location verification."
        }
        val offset = arguments.optInt("day_offset", 0)
        val days = arguments.optInt("days", 1)
        val date = arguments.optString("date").trim().takeIf { it.isNotEmpty() }?.let(LocalDate::parse)
        require(offset in 0..15 && days in 1..16 && offset + days <= 16) { "Forecast range must be within the next 16 local days." }
        require(date == null || !arguments.has("day_offset")) { "Use either date or day_offset, not both." }
        val forecastDays = if (date == null) offset + days else 16
        val geoUrl = "https://geocoding-api.open-meteo.com/v1/search?name=${encode(location)}" +
            "&count=10&language=en&format=json&countryCode=$country"
        val rawGeo = JSONObject(fetch(geoUrl))
        val results = rawGeo.optJSONArray("results")
        val candidates = (0 until (results?.length() ?: 0)).mapNotNull { results?.optJSONObject(it) }
            .filter { it.optString("country_code").equals(country, true) && it.optString("admin1").equals(region, true) }
        if (candidates.size != 1) return mapOf("status" to "needs_location_clarification", "operation" to "weather",
            "message" to "No unique city matches the requested country and region. Verify the place; do not substitute another region.",
            "geocoding_source" to geoUrl)
        val place = candidates.single()
        val latitude = place.getDouble("latitude")
        val longitude = place.getDouble("longitude")
        require(latitude.isFinite() && latitude in -90.0..90.0 && longitude.isFinite() && longitude in -180.0..180.0)
        val url = "https://api.open-meteo.com/v1/forecast?latitude=$latitude&longitude=$longitude" +
            "&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m" +
            "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max" +
            "&timezone=auto&forecast_days=$forecastDays"
        val raw = fetch(url)
        val weather = JSONObject(raw)
        require(!weather.optBoolean("error")) { "Weather provider returned an error." }
        val zone = ZoneId.of(weather.getString("timezone"))
        val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
        val requestedDate = date ?: today.plusDays(offset.toLong())
        val requestedOffset = ChronoUnit.DAYS.between(today, requestedDate)
        require(requestedOffset >= 0 && requestedOffset + days <= 16) { "Requested dates are outside the supported forecast horizon; use another source." }
        val fullDaily = weather.getJSONObject("daily")
        val dates = fullDaily.getJSONArray("time")
        val indices = (0 until days).map { day ->
            val expected = requestedDate.plusDays(day.toLong()).toString()
            (0 until dates.length()).firstOrNull { dates.optString(it) == expected }
                ?: throw IllegalArgumentException("Weather provider did not return requested local forecast date $expected.")
        }
        val daily = JSONObject()
        fullDaily.keys().forEach { key ->
            val values = fullDaily.getJSONArray(key)
            require(indices.all { it < values.length() }) { "Weather provider returned misaligned daily values." }
            daily.put(key, JSONArray().apply { indices.forEach { put(values.get(it)) } })
        }
        val currentDate = requestedDate.toString()
        val content = JSONObject().put("provider", "Open-Meteo").put("location", JSONObject()
            .put("name", place.getString("name")).put("region", place.getString("admin1"))
            .put("country_code", country).put("latitude", latitude).put("longitude", longitude))
            .put("timezone", zone.id).put("forecast_date", currentDate)
            .put("forecast_end_date", requestedDate.plusDays(days.toLong() - 1).toString())
            .put("conditions_type", if (requestedDate == today) "weather_model_estimate_not_station_observation" else "weather_model_forecast_not_observation")
            .apply {
                if (requestedDate == today) {
                    put("current", weather.getJSONObject("current"))
                    put("current_units", weather.getJSONObject("current_units"))
                }
            }
            .put("daily", daily).put("daily_units", weather.getJSONObject("daily_units"))
            .put("geocoding_source", geoUrl)
            .put("note", "Current time is the model estimate's valid time, not a measured observation or publication timestamp. " +
                "Weather codes use WMO interpretation. Null fields are unavailable, never zero. Cite the forecast source.").toString()
        val pack = AgentWebEvidencePack.build(location, "completed", listOf(mapOf(
            "url" to url, "title" to "Open-Meteo: ${place.getString("name")}, ${place.getString("admin1")} ($currentDate)",
            "content" to content, "content_type" to "application/json", "content_sha256" to AgentNativeJsonCodec.sha256(raw),
            "retrieved_at_millis" to now
        )), emptyList(), emptyList(), now)
        return mapOf("operation" to "weather", "status" to "completed", "evidence_pack" to pack)
    }

    private fun encode(value: String): String = URLEncoder.encode(value, "UTF-8")
}
