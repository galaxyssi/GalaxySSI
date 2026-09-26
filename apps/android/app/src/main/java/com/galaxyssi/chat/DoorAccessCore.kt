package com.galaxyssi.chat

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import okhttp3.FormBody
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.security.KeyStore
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal fun Context.doorAccessText(name: String, vararg args: Any): String =
    getString(resources.getIdentifier("door_access_$name", "string", packageName), *args)

data class DoorAccessDoor(val name: String, val channel: String, val community: String)
data class DoorAccessSession(val token: String, val userId: String, val serviceUrl: String)
internal enum class DoorAccessOpenStatus { ACCEPTED, REJECTED, UNCONFIRMED, NO_UNIQUE_MATCH }
internal data class DoorAccessOpenResult(val status: DoorAccessOpenStatus, val doorName: String = "")

internal sealed class DoorAccessCommand {
    object ListDoors : DoorAccessCommand()
    data class Open(val target: String?) : DoorAccessCommand()

}

internal interface DoorAccessTransport {
    fun request(url: String, form: Map<String, String>? = null): JSONObject
}

internal class HttpsDoorAccessTransport : DoorAccessTransport {
    private val client = OkHttpClient.Builder()
        .followRedirects(false)
        .retryOnConnectionFailure(false)
        .callTimeout(12, TimeUnit.SECONDS)
        .connectTimeout(7, TimeUnit.SECONDS)
        .readTimeout(12, TimeUnit.SECONDS)
        .build()

    override fun request(url: String, form: Map<String, String>?): JSONObject {
        val target = url.toHttpUrl()
        require(target.isHttps && DoorAccessClient.trustedHost(target.host)) { "Untrusted door service" }
        val builder = Request.Builder().url(target).header("Cache-Control", "no-store")
        if (form != null) {
            val body = FormBody.Builder().apply { form.forEach { (key, value) -> add(key, value) } }.build()
            builder.post(body)
        }
        client.newCall(builder.build()).execute().use { response ->
            if (!response.isSuccessful || response.isRedirect) throw IllegalStateException("Door service unavailable")
            val body = response.body ?: throw IllegalStateException("Empty door service response")
            val bytes = body.byteStream().use { input ->
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (output.size() <= 256 * 1024) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    output.write(buffer, 0, count)
                }
                output.toByteArray()
            }
            if (bytes.size > 256 * 1024) throw IllegalStateException("Door service response too large")
            return JSONObject(bytes.toString(Charsets.UTF_8))
        }
    }
}

internal class DoorAccessClient(private val transport: DoorAccessTransport = HttpsDoorAccessTransport()) {
    fun openUnique(
        account: String,
        password: String,
        command: DoorAccessCommand.Open,
        timestampMillis: Long,
        configuration: DoorAccessConfiguration,
        checkpoint: () -> Unit = {}
    ): DoorAccessOpenResult {
        checkpoint()
        val session = login(account, password)
        checkpoint()
        val door = configuration.select(command, listDoors(session))
            ?: return DoorAccessOpenResult(DoorAccessOpenStatus.NO_UNIQUE_MATCH)
        checkpoint()
        return try {
            val accepted = unlock(session, door, timestampMillis)
            DoorAccessOpenResult(if (accepted) DoorAccessOpenStatus.ACCEPTED else DoorAccessOpenStatus.REJECTED, door.name)
        } catch (_: Exception) {
            DoorAccessOpenResult(DoorAccessOpenStatus.UNCONFIRMED, door.name)
        }
    }

    fun login(account: String, password: String): DoorAccessSession {
        require(account.isNotBlank() && password.isNotBlank()) { "Account and password required" }
        val result = transport.request("$BASE/MobileApi/House/Login", mapOf(
            "account" to account.trim(), "password" to password, "loginType" to "0"))
        check(result.optBoolean("State")) { "Door login failed" }
        val data = result.optJSONObject("Data") ?: throw IllegalStateException("Missing login data")
        val token = data.optString("Token")
        check(token.isNotBlank()) { "Missing door token" }
        val userId = data.optJSONObject("House")?.optString("ID").orEmpty()
        val systems = transport.request("$BASE/GuestApi/PrivateCloud/GetSubSystems")
        check(systems.optBoolean("State")) { "Door service discovery failed" }
        val entries = systems.optJSONArray("Data") ?: throw IllegalStateException("Missing door service")
        val host = (0 until entries.length()).asSequence().mapNotNull(entries::optJSONObject)
            .firstOrNull { it.optInt("SubSystem") == 1 }?.optString("SubSystemHost").orEmpty()
        return DoorAccessSession(token, userId, secureServiceUrl(host))
    }

    fun listDoors(session: DoorAccessSession): List<DoorAccessDoor> {
        val base = session.serviceUrl.toHttpUrl()
        val url = base.newBuilder().addPathSegments("Api/MobileApi/Index/SearchEquipment")
            .addQueryParameter("token", session.token).build().toString()
        val result = transport.request(url)
        check(result.optBoolean("State")) { "Door list unavailable" }
        val entries = result.optJSONArray("Data") ?: return emptyList()
        return (0 until entries.length()).mapNotNull { index ->
            val item = entries.optJSONObject(index) ?: return@mapNotNull null
            val channel = item.optString("EQ_Num").trim()
            if (channel.isBlank() || channel.length > 128) return@mapNotNull null
            DoorAccessDoor(item.optString("EQ_Name").ifBlank { "Door" }.take(100), channel,
                item.optString("EQ_CommunityName").take(100))
        }
    }

    fun unlock(session: DoorAccessSession, door: DoorAccessDoor, timestampMillis: Long): Boolean {
        require(door.channel.isNotBlank()) { "Door channel required" }
        val message = JSONObject().put("messageSenderType", 1).put("formuid", session.userId)
            .put("msg", "tc_20150330_unlock$timestampMillis").toString()
        val result = transport.request("$BASE/MobileApi/Publisher/Publish", mapOf(
            "channel" to door.channel, "message" to message, "token" to session.token))
        return result.optBoolean("State")
    }

    companion object {
        private const val BASE = "https://haina.taichuan.net"

        fun trustedHost(host: String): Boolean = host == "taichuan.net" || host.endsWith(".taichuan.net")

        fun secureServiceUrl(raw: String): String {
            val parsed = raw.toHttpUrl()
            require(trustedHost(parsed.host) && parsed.username.isEmpty() && parsed.password.isEmpty() &&
                parsed.port in setOf(80, 443) && parsed.encodedPath == "/" && parsed.query == null &&
                parsed.fragment == null) { "Untrusted door service" }
            return HttpUrl.Builder().scheme("https").host(parsed.host).build().toString().trimEnd('/')
        }
    }
}

internal class DoorAccessCredentialStore(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences("door_access_credentials_v1", Context.MODE_PRIVATE)

    fun save(account: String, password: String) {
        val payload = JSONObject().put("account", account).put("password", password).toString().toByteArray()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val encrypted = cipher.doFinal(payload)
        check(preferences.edit().putString("secret", Base64.encodeToString(cipher.iv + encrypted, Base64.NO_WRAP)).commit())
    }

    fun load(): Pair<String, String>? {
        val encoded = preferences.getString("secret", null) ?: return null
        return runCatching {
            val data = Base64.decode(encoded, Base64.NO_WRAP)
            require(data.size > 12)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, data.copyOfRange(0, 12)))
            val value = JSONObject(cipher.doFinal(data.copyOfRange(12, data.size)).toString(Charsets.UTF_8))
            value.getString("account") to value.getString("password")
        }.getOrNull()
    }

    fun clear() { preferences.edit().remove("secret").apply() }

    private fun key(): SecretKey {
        val alias = "galaxyssi_door_access_key_v1"
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build())
        }.generateKey()
    }
}
