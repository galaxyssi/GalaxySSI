package com.galaxyssi.watch

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.location.LocationManager
import android.os.CancellationSignal
import android.os.SystemClock
import org.json.JSONObject
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import java.util.Locale
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit

internal object WatchLocationIntent {
    fun matches(text: String): Boolean {
        val value = text.lowercase(Locale.ROOT).replace(Regex("[\\s，。？！?,.!]"), "")
        if (value.length > 100 || listOf("怎么实现", "如何开发", "翻译", "什么意思", "代码", "不要定位", "不要获取", "别定位", "donot", "don't").any(value::contains)) return false
        if (Regex("我(现在|目前)?(在|位于)(哪(里|儿|个地方|条(路|道路|街道))|什么(地方|位置|路|道路|街道))").containsMatchIn(value)) return true
        return listOf("我在哪", "我现在在哪", "我现在的位置", "我的位置", "当前位置", "现在的位置", "现在是什么地方",
            "现在是什么位置", "现在是什么路", "现在是什么道路", "现在在哪条路", "我在什么路", "这里是什么地方", "这里是什么路", "我在哪里",
            "定位我", "获取位置", "重新定位").any(value::contains) ||
            value in setOf("whereami", "whereaminow", "mylocation", "mycurrentlocation", "whatroadamion", "whatstreetamion")
    }
}

internal data class WatchLocationFix(val latitude: Double, val longitude: Double, val accuracy: Float, val time: Long, val provider: String) {
    fun json() = JSONObject().put("latitude", latitude).put("longitude", longitude).put("accuracy", accuracy)
        .put("time", time).put("provider", provider).toString()
    companion object {
        fun parse(raw: String): WatchLocationFix? = runCatching {
            val j = JSONObject(raw)
            WatchLocationFix(j.getDouble("latitude"), j.getDouble("longitude"), j.getDouble("accuracy").toFloat(), j.getLong("time"), j.optString("provider"))
                .also { require(it.latitude.isFinite() && it.latitude in -90.0..90.0 && it.longitude.isFinite() && it.longitude in -180.0..180.0 && it.accuracy.isFinite() && it.accuracy >= 0 && it.time > 0) }
        }.getOrNull()
    }
}

internal class WatchLocation(private val context: Context) {
    data class Result(val reply: String, val fix: WatchLocationFix)
    fun answer(operation: WatchApiOperation, progress: (String) -> Unit): Result {
        if (!permitted(context)) throw ApiFailure(R.string.location_permission)
        val manager = context.getSystemService(LocationManager::class.java)
        if (!manager.isLocationEnabled) throw ApiFailure(R.string.location_disabled)
        progress(context.getString(R.string.location_locating))
        val fine = context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.FUSED_PROVIDER, LocationManager.NETWORK_PROVIDER)
            .filter { (fine || it != LocationManager.GPS_PROVIDER) && manager.hasProvider(it) && manager.isProviderEnabled(it) }
        if (providers.isEmpty()) throw ApiFailure(R.string.location_disabled)
        val signals = mutableListOf<CancellationSignal>()
        val samples = java.util.concurrent.ConcurrentLinkedQueue<Location>()
        val start = SystemClock.elapsedRealtime()
        try {
            providers.forEach { provider ->
                val signal = CancellationSignal(); signals.add(signal)
                runCatching {
                    manager.getCurrentLocation(provider, signal, context.mainExecutor) { sample ->
                        if (sample != null && sample.hasAccuracy() && sample.accuracy >= 0 &&
                            validSample(sample.latitude, sample.longitude, sample.accuracy, SystemClock.elapsedRealtimeNanos() - sample.elapsedRealtimeNanos)) samples.add(sample)
                    }
                }
            }
            while (SystemClock.elapsedRealtime() - start < 25_000) {
                operation.checkActive()
                if (samples.any { it.accuracy <= 40f } || (samples.isNotEmpty() && SystemClock.elapsedRealtime() - start > 10_000)) break
                Thread.sleep(100)
            }
        } finally { signals.forEach { it.cancel() } }
        operation.checkActive()
        val sample = samples.filter { validSample(it.latitude, it.longitude, it.accuracy, SystemClock.elapsedRealtimeNanos() - it.elapsedRealtimeNanos) }
            .minByOrNull { it.accuracy } ?: throw ApiFailure(R.string.location_unavailable)
        val fix = WatchLocationFix(sample.latitude, sample.longitude, sample.accuracy, sample.time, sample.provider.orEmpty())
        progress(context.getString(R.string.location_address_loading))
        var address = ""
        if (Geocoder.isPresent()) {
            val future = CompletableFuture<List<android.location.Address>>()
            runCatching {
                Geocoder(context, Locale.getDefault()).getFromLocation(fix.latitude, fix.longitude, 1, object : Geocoder.GeocodeListener {
                    override fun onGeocode(addresses: MutableList<android.location.Address>) { future.complete(addresses) }
                    override fun onError(errorMessage: String?) { future.complete(emptyList()) }
                })
                val until = SystemClock.elapsedRealtime() + 8_000
                while (!future.isDone && SystemClock.elapsedRealtime() < until) { operation.checkActive(); Thread.sleep(100) }
                val found = if (future.isDone) future.get(1, TimeUnit.MILLISECONDS).firstOrNull() else null
                if (found != null) {
                    val parts = listOf(found.adminArea, found.locality, found.subLocality, found.thoroughfare).filterNotNull().filter(String::isNotBlank).distinct()
                    address = parts.joinToString(" ").ifBlank { found.getAddressLine(0).orEmpty() }.take(200)
                }
            }
        }
        operation.checkActive()
        if (address.isBlank()) {
            val endpoint = context.getSharedPreferences("watch-location", Context.MODE_PRIVATE).getString("address_endpoint", "https://photon.komoot.io/reverse").orEmpty()
            val base = endpoint.toHttpUrlOrNull()
            if (base != null && base.isHttps) {
                progress(context.getString(R.string.location_address_loading))
                val key = endpoint + String.format(Locale.US, ":%.4f,%.4f:%s", fix.latitude, fix.longitude, Locale.getDefault().language)
                address = synchronized(addressCache) { addressCache[key].orEmpty() }
                if (address.isBlank()) runCatching {
                    val builder = base.newBuilder()
                        .addQueryParameter("lat", fix.latitude.toString()).addQueryParameter("lon", fix.longitude.toString())
                    if (base.host == "photon.komoot.io") builder.addQueryParameter("limit", "1").addQueryParameter("radius", "1")
                    else builder.addQueryParameter("format", "jsonv2").addQueryParameter("addressdetails", "1").addQueryParameter("zoom", "17")
                    val url = builder.build()
                    val request = okhttp3.Request.Builder().url(url).header("User-Agent", "GalaxySSI-Watch/0.3.0 (+https://github.com/galaxyssi/GalaxySSI)").build()
                    synchronized(addressLock) {
                        while (SystemClock.elapsedRealtime() - lastAddressRequest < 2000) { operation.checkActive(); Thread.sleep(100) }
                        lastAddressRequest = SystemClock.elapsedRealtime()
                    }
                    val call = addressClient.newCall(request)
                    operation.attach(call).execute().use { response ->
                        check(response.isSuccessful)
                        val bytes = requireNotNull(response.body).byteStream().use { it.readNBytes(64_001) }
                        require(bytes.size <= 64_000)
                        val json = JSONObject(bytes.toString(Charsets.UTF_8))
                        address = addressText(json)
                    }
                    if (address.isNotBlank()) synchronized(addressCache) {
                        addressCache[key] = address
                        while (addressCache.size > 20) addressCache.remove(addressCache.keys.first())
                    }
                }
            }
        }
        operation.checkActive()
        val coordinate = String.format(Locale.US, "%.5f, %.5f", fix.latitude, fix.longitude)
        val text = (if (address.isBlank()) context.getString(R.string.location_address_missing) else context.getString(R.string.location_near, address)) +
            (if (address.isBlank()) "\n$coordinate" else "")
        return Result(text, fix)
    }
    companion object {
        internal fun addressText(json: JSONObject): String {
            if (json.has("features")) {
                val properties = json.optJSONArray("features")?.optJSONObject(0)?.optJSONObject("properties") ?: return ""
                return listOf("state", "city", "district", "street", "name").map { properties.optString(it) }.filter(String::isNotBlank).distinct().joinToString(" ").take(200)
            }
            return json.optString("display_name").take(200)
        }
        internal fun validSample(lat: Double, lon: Double, accuracy: Float, ageNanos: Long) =
            lat.isFinite() && lat in -90.0..90.0 && lon.isFinite() && lon in -180.0..180.0 && accuracy.isFinite() && accuracy >= 0 && ageNanos in 0..30_000_000_000L
        private val addressCache = linkedMapOf<String, String>()
        private val addressLock = Any()
        private var lastAddressRequest = 0L
        private val addressClient = okhttp3.OkHttpClient.Builder().callTimeout(8, TimeUnit.SECONDS).build()
        fun permitted(context: Context) = context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
    }
}
