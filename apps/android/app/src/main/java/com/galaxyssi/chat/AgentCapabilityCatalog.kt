package com.galaxyssi.chat

import android.content.Context
import java.util.Base64
import java.util.Locale
import java.util.UUID

enum class AgentCapabilityCatalogKind(val wireValue: String) {
    NATIVE_TOOL("native_tool"),
    MCP("mcp"),
    AUTOMATION("automation")
}

enum class AgentMarketplaceInstallState(val wireValue: String) {
    BUILT_IN("built_in"),
    AVAILABLE("available"),
    INSTALLED("installed"),
    NEEDS_SETUP("needs_setup"),
    UNAVAILABLE("unavailable")
}

data class AgentMarketplacePermission(
    val id: String,
    val title: String = id,
    val description: String = "",
    val scope: String = "item",
    val risk: String = "medium"
)

data class AgentMarketplacePermissionDiff(
    val added: List<AgentMarketplacePermission> = emptyList(),
    val removed: List<AgentMarketplacePermission> = emptyList(),
    val unchanged: List<AgentMarketplacePermission> = emptyList()
) {
    val requiresApproval: Boolean get() = added.isNotEmpty()
}

data class AgentMarketplaceItem(
    val id: String,
    val kind: AgentCapabilityCatalogKind,
    val name: String,
    val summary: String,
    val version: String,
    val publisher: String = "GalaxySSI",
    val installState: AgentMarketplaceInstallState,
    val enabled: Boolean = true,
    val featured: Boolean = true,
    val trusted: Boolean = true,
    val tags: Set<String> = emptySet(),
    val dependencies: Set<String> = emptySet(),
    val requiresLocalPackage: Boolean = false,
    val capabilities: Set<String> = emptySet(),
    val permissions: List<AgentMarketplacePermission> = emptyList(),
    val permissionDiff: AgentMarketplacePermissionDiff = AgentMarketplacePermissionDiff(),
    val installedVersion: String = "",
    val availableVersion: String = version,
    val updateAvailable: Boolean = false,
    val rollbackVersions: List<String> = emptyList(),
    val revocable: Boolean = false,
    val revoked: Boolean = false
) {
    init {
        require(id.isNotBlank())
        require(name.isNotBlank())
        require(summary.isNotBlank())
        require(version.isNotBlank())
    }
}

enum class AgentMcpDistribution(val wireValue: String) {
    REMOTE("remote"),
    LOCAL_PACKAGE("local_package")
}

enum class AgentMcpTransportKind(val wireValue: String) {
    STREAMABLE_HTTP("streamable_http"),
    DECLARATIVE_HTTP("declarative_http"),
    LOCAL_STDIO("local_stdio")
}

enum class AgentMcpAuthMethod(val wireValue: String) {
    NONE("none"),
    BEARER_TOKEN("bearer_token"),
    API_KEY("api_key"),
    USERNAME_PASSWORD("username_password"),
    OAUTH2("oauth2"),
    DEVICE_CODE("device_code"),
    DYNAMIC("dynamic");

    companion object {
        fun fromWireValue(value: String): AgentMcpAuthMethod = entries.firstOrNull {
            it.wireValue == value.trim().lowercase(Locale.ROOT)
        } ?: NONE
    }
}

enum class AgentMcpAuthFieldType(val wireValue: String) {
    TEXT("text"),
    PASSWORD("password"),
    API_KEY("api_key"),
    PHONE("phone"),
    EMAIL("email"),
    OTP("otp"),
    TOTP("totp"),
    CAPTCHA("captcha"),
    SELECT("select"),
    CHECKBOX("checkbox"),
    URL("url");

    companion object {
        fun fromWireValue(value: String): AgentMcpAuthFieldType = entries.firstOrNull {
            it.wireValue == value.trim().lowercase(Locale.ROOT)
        } ?: TEXT
    }
}

enum class AgentMcpAuthState(val wireValue: String) {
    NOT_REQUIRED("not_required"),
    NOT_CONFIGURED("not_configured"),
    CHALLENGE_REQUIRED("challenge_required"),
    AUTHENTICATING("authenticating"),
    AUTHENTICATED("authenticated"),
    REFRESHING("refreshing"),
    REAUTHENTICATION_REQUIRED("reauthentication_required"),
    ERROR("error");

    companion object {
        fun fromWireValue(value: String): AgentMcpAuthState = entries.firstOrNull {
            it.wireValue == value.trim().lowercase(Locale.ROOT)
        } ?: NOT_CONFIGURED
    }
}

enum class AgentMcpConnectionState(val wireValue: String) {
    INSTALLED("installed"),
    CONNECTING("connecting"),
    CONNECTED("connected"),
    NEEDS_SETUP("needs_setup"),
    UNAVAILABLE("unavailable"),
    ERROR("error");

    companion object {
        fun fromWireValue(value: String): AgentMcpConnectionState = entries.firstOrNull {
            it.wireValue == value.trim().lowercase(Locale.ROOT)
        } ?: INSTALLED
    }
}

data class AgentMcpAuthFieldSpec(
    val id: String,
    val label: String,
    val type: AgentMcpAuthFieldType,
    val required: Boolean = true,
    val secret: Boolean = type in setOf(
        AgentMcpAuthFieldType.PASSWORD,
        AgentMcpAuthFieldType.API_KEY,
        AgentMcpAuthFieldType.OTP,
        AgentMcpAuthFieldType.TOTP
    ),
    val placeholder: String = "",
    val options: List<String> = emptyList()
) {
    init {
        require(ID_PATTERN.matches(id)) { "Invalid MCP authentication field id: $id" }
        require(label.isNotBlank()) { "MCP authentication field label must not be blank" }
        require(options.none(String::isBlank)) { "MCP authentication field options must not be blank" }
    }

    companion object {
        private val ID_PATTERN = Regex("[a-z][a-z0-9_.-]{0,95}")
    }
}

data class AgentMcpAuthExchangeSpec(
    val method: String,
    val pathTemplate: String,
    val headerTemplates: Map<String, String> = emptyMap(),
    val bodyTemplate: String = "",
    val responseMappings: Map<String, String> = emptyMap(),
    val acceptedStatusCodes: Set<Int> = setOf(200)
) {
    init {
        require(method.uppercase(Locale.ROOT) in setOf("GET", "POST", "PUT", "PATCH"))
        require(pathTemplate.startsWith('/') && !pathTemplate.contains("..") && !pathTemplate.contains("://"))
        require(responseMappings.keys.all { it.matches(Regex("[a-z][a-z0-9_.-]{0,95}")) })
        require(acceptedStatusCodes.isNotEmpty() && acceptedStatusCodes.all { it in 200..299 })
    }
}

data class AgentMcpAuthStepSpec(
    val id: String,
    val title: String,
    val description: String = "",
    val fields: List<AgentMcpAuthFieldSpec>,
    val expiresInSeconds: Long = 0L,
    val exchange: AgentMcpAuthExchangeSpec? = null
) {
    init {
        require(id.isNotBlank())
        require(title.isNotBlank())
        require(fields.map { it.id }.distinct().size == fields.size)
        require(expiresInSeconds >= 0L)
    }
}

data class AgentMcpAuthProfile(
    val method: AgentMcpAuthMethod,
    val steps: List<AgentMcpAuthStepSpec> = defaultSteps(method),
    val accessTokenTtlMillis: Long = 0L,
    val refreshLeadMillis: Long = 5 * 60_000L,
    val supportsRefresh: Boolean = false,
    val refreshExchange: AgentMcpAuthExchangeSpec? = null,
    val authorizationUrl: String = "",
    val tokenUrl: String = "",
    val scopes: List<String> = emptyList()
) {
    init {
        require(steps.map { it.id }.distinct().size == steps.size)
        require(accessTokenTtlMillis >= 0L)
        require(refreshLeadMillis >= 0L)
    }

    companion object {
        fun defaultSteps(method: AgentMcpAuthMethod): List<AgentMcpAuthStepSpec> = when (method) {
            AgentMcpAuthMethod.NONE -> emptyList()
            AgentMcpAuthMethod.BEARER_TOKEN -> listOf(
                AgentMcpAuthStepSpec(
                    "token",
                    "Access token",
                    fields = listOf(AgentMcpAuthFieldSpec("access_token", "Access token", AgentMcpAuthFieldType.API_KEY))
                )
            )
            AgentMcpAuthMethod.API_KEY -> listOf(
                AgentMcpAuthStepSpec(
                    "api_key",
                    "API key",
                    fields = listOf(
                        AgentMcpAuthFieldSpec("api_key", "API key", AgentMcpAuthFieldType.API_KEY),
                        AgentMcpAuthFieldSpec("header_name", "Header name", AgentMcpAuthFieldType.TEXT, required = false, secret = false, placeholder = "X-API-Key")
                    )
                )
            )
            AgentMcpAuthMethod.USERNAME_PASSWORD -> listOf(
                AgentMcpAuthStepSpec(
                    "credentials",
                    "Sign in",
                    fields = listOf(
                        AgentMcpAuthFieldSpec("username", "Username", AgentMcpAuthFieldType.TEXT, secret = false),
                        AgentMcpAuthFieldSpec("password", "Password", AgentMcpAuthFieldType.PASSWORD)
                    )
                )
            )
            AgentMcpAuthMethod.OAUTH2 -> listOf(
                AgentMcpAuthStepSpec(
                    "oauth",
                    "Authorize access",
                    fields = listOf(AgentMcpAuthFieldSpec("access_token", "OAuth access token", AgentMcpAuthFieldType.API_KEY))
                )
            )
            AgentMcpAuthMethod.DEVICE_CODE -> listOf(
                AgentMcpAuthStepSpec(
                    "device_code",
                    "Device authorization",
                    fields = listOf(AgentMcpAuthFieldSpec("device_code", "Device code", AgentMcpAuthFieldType.OTP))
                )
            )
            AgentMcpAuthMethod.DYNAMIC -> listOf(
                AgentMcpAuthStepSpec(
                    "credentials",
                    "Sign in",
                    fields = listOf(
                        AgentMcpAuthFieldSpec("username", "Username", AgentMcpAuthFieldType.TEXT, secret = false),
                        AgentMcpAuthFieldSpec("password", "Password", AgentMcpAuthFieldType.PASSWORD)
                    )
                ),
                AgentMcpAuthStepSpec(
                    "verification",
                    "Verify sign-in",
                    fields = listOf(AgentMcpAuthFieldSpec("otp", "Verification code", AgentMcpAuthFieldType.OTP)),
                    expiresInSeconds = 300L
                )
            )
        }
    }
}

data class AgentMcpCatalogEntry(
    val id: String,
    val name: String,
    val summary: String,
    val distribution: AgentMcpDistribution,
    val transport: AgentMcpTransportKind = AgentMcpTransportKind.STREAMABLE_HTTP,
    val defaultEndpoint: String = "",
    val authProfiles: List<AgentMcpAuthProfile> = listOf(AgentMcpAuthProfile(AgentMcpAuthMethod.NONE)),
    val version: String = "1.0.0",
    val toolHints: List<String> = emptyList(),
    val tags: Set<String> = emptySet(),
    val featured: Boolean = true,
    val requiresPackage: Boolean = false
) {
    init {
        require(ID_PATTERN.matches(id)) { "Invalid MCP catalog id: $id" }
        require(name.isNotBlank())
        require(summary.isNotBlank())
        require(authProfiles.isNotEmpty())
        require(authProfiles.map { it.method }.distinct().size == authProfiles.size)
    }

    companion object {
        private val ID_PATTERN = Regex("[a-z][a-z0-9]*(?:[._-][a-z0-9]+)+")
    }
}

data class AgentSkillCatalogEntry(
    val id: String,
    val name: String,
    val summary: String,
    val requiredNativeTools: Set<String> = emptySet(),
    val requiredMcpCatalogIds: Set<String> = emptySet(),
    val featured: Boolean = true,
    val manifest: AgentSkillManifest
)

data class AgentMcpConnection(
    val id: String,
    val catalogId: String = "",
    val displayName: String,
    val endpoint: String,
    val distribution: AgentMcpDistribution,
    val transport: AgentMcpTransportKind,
    val authProfile: AgentMcpAuthProfile,
    val authState: AgentMcpAuthState,
    val authStepIndex: Int = 0,
    val state: AgentMcpConnectionState = AgentMcpConnectionState.INSTALLED,
    val enabled: Boolean = true,
    val permissionMode: AgentMcpPermissionMode = AgentMcpPermissionMode.TRUSTED,
    val installedAtMillis: Long = 0L,
    val updatedAtMillis: Long = installedAtMillis,
    val expiresAtMillis: Long = 0L,
    val refreshAtMillis: Long = 0L,
    val lastValidatedAtMillis: Long = 0L,
    val lastError: String = "",
    val toolIds: List<String> = emptyList(),
    val packageVersion: String = "",
    val packageSha256: String = ""
) {
    val currentAuthStep: AgentMcpAuthStepSpec?
        get() = authProfile.steps.getOrNull(authStepIndex)

    fun effectiveAuthState(nowMillis: Long): AgentMcpAuthState = when {
        authProfile.method == AgentMcpAuthMethod.NONE -> AgentMcpAuthState.NOT_REQUIRED
        authState == AgentMcpAuthState.AUTHENTICATED && expiresAtMillis > 0L && nowMillis >= expiresAtMillis ->
            AgentMcpAuthState.REAUTHENTICATION_REQUIRED
        authState == AgentMcpAuthState.AUTHENTICATED && refreshAtMillis > 0L && nowMillis >= refreshAtMillis ->
            AgentMcpAuthState.REFRESHING
        else -> authState
    }

    fun isCallable(nowMillis: Long): Boolean {
        val auth = effectiveAuthState(nowMillis)
        return enabled && endpoint.isNotBlank() && state != AgentMcpConnectionState.ERROR &&
            auth in setOf(
                AgentMcpAuthState.NOT_REQUIRED,
                AgentMcpAuthState.AUTHENTICATED,
                AgentMcpAuthState.REFRESHING
            )
    }
}

interface AgentMcpStore {
    fun list(): List<AgentMcpConnection>
    fun upsert(connection: AgentMcpConnection)
    fun delete(id: String): Boolean
    fun readSecrets(id: String): Map<String, String>
    fun writeSecrets(id: String, values: Map<String, String>)
    fun clearSecrets(id: String)
    fun clear()
}

class InMemoryAgentMcpStore(
    initialConnections: List<AgentMcpConnection> = emptyList()
) : AgentMcpStore {
    private var connections = initialConnections.associateBy { it.id }.toMutableMap()
    private val secrets = mutableMapOf<String, Map<String, String>>()

    @Synchronized
    override fun list(): List<AgentMcpConnection> = connections.values.sortedBy { it.displayName.lowercase(Locale.ROOT) }

    @Synchronized
    override fun upsert(connection: AgentMcpConnection) {
        connections[connection.id] = connection
    }

    @Synchronized
    override fun delete(id: String): Boolean {
        secrets.remove(id)
        return connections.remove(id) != null
    }

    @Synchronized
    override fun readSecrets(id: String): Map<String, String> = secrets[id].orEmpty().toMap()

    @Synchronized
    override fun writeSecrets(id: String, values: Map<String, String>) {
        secrets[id] = values.toMap()
    }

    @Synchronized
    override fun clearSecrets(id: String) {
        secrets.remove(id)
    }

    @Synchronized
    override fun clear() {
        connections.clear()
        secrets.clear()
    }
}

class EncryptedAgentMcpStore(
    context: Context,
    preferencesName: String = PREFERENCES_NAME
) : AgentMcpStore {
    private val appContext = context.applicationContext
    private val preferences = AgentEncryptedPreferences(appContext, preferencesName)

    @Synchronized
    override fun list(): List<AgentMcpConnection> = AgentMcpConnectionCodec.decode(
        preferences.readString(KEY_CONNECTIONS, AgentMcpConnectionCodec.emptyDocument())
    )

    @Synchronized
    override fun upsert(connection: AgentMcpConnection) {
        val before = list()
        val next = before.filterNot { it.id == connection.id } + connection
        preferences.writeString(KEY_CONNECTIONS, AgentMcpConnectionCodec.encode(next))
        GlobalConversationEventBus.publishCapabilityEvents(
            appContext,
            GlobalCapabilityObservationExtractor.mcpMutations(before, next)
        )
    }

    @Synchronized
    override fun delete(id: String): Boolean {
        val current = list()
        val next = current.filterNot { it.id == id }
        if (next.size == current.size) return false
        preferences.writeString(KEY_CONNECTIONS, AgentMcpConnectionCodec.encode(next))
        clearSecrets(id)
        GlobalConversationEventBus.publishCapabilityEvents(
            appContext,
            GlobalCapabilityObservationExtractor.mcpMutations(current, next)
        )
        return true
    }

    override fun readSecrets(id: String): Map<String, String> = AgentMcpConnectionCodec.decodeSecrets(
        preferences.readString(secretKey(id), AgentMcpConnectionCodec.emptySecretsDocument())
    )

    override fun writeSecrets(id: String, values: Map<String, String>) {
        preferences.writeString(secretKey(id), AgentMcpConnectionCodec.encodeSecrets(values))
    }

    override fun clearSecrets(id: String) = preferences.remove(secretKey(id))

    override fun clear() = preferences.clear()

    private fun secretKey(id: String): String = "secret_${Base64.getUrlEncoder().withoutPadding().encodeToString(id.toByteArray())}"

    companion object {
        const val PREFERENCES_NAME = "galaxyssi_mcp_connections"
        const val KEY_CONNECTIONS = "connections"
    }
}

object AgentMcpConnectionCodec {
    fun emptyDocument(): String = "{\"version\":1,\"connections\":[]}"
    fun emptySecretsDocument(): String = "{\"version\":1,\"values\":{}}"

    fun encode(connections: List<AgentMcpConnection>): String = McpJson.stringify(
        McpJsonObject.of(
            "version" to 1,
            "connections" to connections.sortedBy { it.id }.map(::connectionValue)
        )
    )

    fun decode(document: String): List<AgentMcpConnection> = runCatching {
        val root = McpJson.parseObject(document)
        root.array("connections")?.values.orEmpty().mapNotNull { (it as? McpJsonObject)?.let(::connectionFromValue) }
    }.getOrDefault(emptyList())

    fun encodeSecrets(values: Map<String, String>): String = McpJson.stringify(
        McpJsonObject.of("version" to 1, "values" to values.toSortedMap())
    )

    fun decodeSecrets(document: String): Map<String, String> = runCatching {
        McpJson.parseObject(document).objectValue("values")?.entries.orEmpty().mapNotNull { (key, value) ->
            (value as? McpJsonString)?.value?.let { key to it }
        }.toMap()
    }.getOrDefault(emptyMap())

    private fun connectionValue(connection: AgentMcpConnection): McpJsonObject = McpJsonObject.of(
        "id" to connection.id,
        "catalog_id" to connection.catalogId,
        "display_name" to connection.displayName,
        "endpoint" to connection.endpoint,
        "distribution" to connection.distribution.wireValue,
        "transport" to connection.transport.wireValue,
        "auth_profile" to authProfileValue(connection.authProfile),
        "auth_state" to connection.authState.wireValue,
        "auth_step_index" to connection.authStepIndex,
        "state" to connection.state.wireValue,
        "enabled" to connection.enabled,
        "permission_mode" to connection.permissionMode.wireValue,
        "installed_at" to connection.installedAtMillis,
        "updated_at" to connection.updatedAtMillis,
        "expires_at" to connection.expiresAtMillis,
        "refresh_at" to connection.refreshAtMillis,
        "last_validated_at" to connection.lastValidatedAtMillis,
        "last_error" to connection.lastError,
        "tool_ids" to connection.toolIds,
        "package_version" to connection.packageVersion,
        "package_sha256" to connection.packageSha256
    )

    private fun connectionFromValue(value: McpJsonObject): AgentMcpConnection? {
        val id = value.string("id").orEmpty().trim()
        val name = value.string("display_name").orEmpty().trim()
        if (id.isBlank() || name.isBlank()) return null
        return AgentMcpConnection(
            id = id,
            catalogId = value.string("catalog_id").orEmpty(),
            displayName = name,
            endpoint = value.string("endpoint").orEmpty(),
            distribution = AgentMcpDistribution.entries.firstOrNull {
                it.wireValue == value.string("distribution")
            } ?: AgentMcpDistribution.REMOTE,
            transport = AgentMcpTransportKind.entries.firstOrNull {
                it.wireValue == value.string("transport")
            } ?: AgentMcpTransportKind.STREAMABLE_HTTP,
            authProfile = value.objectValue("auth_profile")?.let(::authProfileFromValue)
                ?: AgentMcpAuthProfile(AgentMcpAuthMethod.NONE),
            authState = AgentMcpAuthState.fromWireValue(value.string("auth_state").orEmpty()),
            authStepIndex = value.int("auth_step_index").coerceAtLeast(0),
            state = AgentMcpConnectionState.fromWireValue(value.string("state").orEmpty()),
            enabled = value.boolean("enabled") ?: true,
            permissionMode = AgentMcpPermissionMode.fromWireValue(value.string("permission_mode")),
            installedAtMillis = value.long("installed_at"),
            updatedAtMillis = value.long("updated_at"),
            expiresAtMillis = value.long("expires_at"),
            refreshAtMillis = value.long("refresh_at"),
            lastValidatedAtMillis = value.long("last_validated_at"),
            lastError = value.string("last_error").orEmpty(),
            toolIds = value.stringList("tool_ids"),
            packageVersion = value.string("package_version").orEmpty(),
            packageSha256 = value.string("package_sha256").orEmpty()
        )
    }

    private fun authProfileValue(profile: AgentMcpAuthProfile): McpJsonObject = McpJsonObject.of(
        "method" to profile.method.wireValue,
        "steps" to profile.steps.map { step ->
            McpJsonObject.of(
                "id" to step.id,
                "title" to step.title,
                "description" to step.description,
                "expires_in_seconds" to step.expiresInSeconds,
                "exchange" to step.exchange?.let(::authExchangeValue),
                "fields" to step.fields.map { field ->
                    McpJsonObject.of(
                        "id" to field.id,
                        "label" to field.label,
                        "type" to field.type.wireValue,
                        "required" to field.required,
                        "secret" to field.secret,
                        "placeholder" to field.placeholder,
                        "options" to field.options
                    )
                }
            )
        },
        "token_ttl_ms" to profile.accessTokenTtlMillis,
        "refresh_lead_ms" to profile.refreshLeadMillis,
        "supports_refresh" to profile.supportsRefresh,
        "refresh_exchange" to profile.refreshExchange?.let(::authExchangeValue),
        "authorization_url" to profile.authorizationUrl,
        "token_url" to profile.tokenUrl,
        "scopes" to profile.scopes
    )

    private fun authProfileFromValue(value: McpJsonObject): AgentMcpAuthProfile {
        val method = AgentMcpAuthMethod.fromWireValue(value.string("method").orEmpty())
        val steps = value.array("steps")?.values.orEmpty().mapNotNull { raw ->
            val step = raw as? McpJsonObject ?: return@mapNotNull null
            val id = step.string("id").orEmpty()
            val title = step.string("title").orEmpty()
            if (id.isBlank() || title.isBlank()) return@mapNotNull null
            val fields = step.array("fields")?.values.orEmpty().mapNotNull { fieldRaw ->
                val field = fieldRaw as? McpJsonObject ?: return@mapNotNull null
                val fieldId = field.string("id").orEmpty()
                val label = field.string("label").orEmpty()
                if (fieldId.isBlank() || label.isBlank()) return@mapNotNull null
                AgentMcpAuthFieldSpec(
                    id = fieldId,
                    label = label,
                    type = AgentMcpAuthFieldType.fromWireValue(field.string("type").orEmpty()),
                    required = field.boolean("required") ?: true,
                    secret = field.boolean("secret") ?: true,
                    placeholder = field.string("placeholder").orEmpty(),
                    options = field.stringList("options")
                )
            }
            AgentMcpAuthStepSpec(
                id,
                title,
                step.string("description").orEmpty(),
                fields,
                step.long("expires_in_seconds"),
                step.objectValue("exchange")?.let(::authExchangeFromValue)
            )
        }
        return AgentMcpAuthProfile(
            method = method,
            steps = steps.ifEmpty { AgentMcpAuthProfile.defaultSteps(method) },
            accessTokenTtlMillis = value.long("token_ttl_ms"),
            refreshLeadMillis = value.long("refresh_lead_ms").takeIf { it > 0 } ?: 5 * 60_000L,
            supportsRefresh = value.boolean("supports_refresh") ?: false,
            refreshExchange = value.objectValue("refresh_exchange")?.let(::authExchangeFromValue),
            authorizationUrl = value.string("authorization_url").orEmpty(),
            tokenUrl = value.string("token_url").orEmpty(),
            scopes = value.stringList("scopes")
        )
    }

    private fun authExchangeValue(exchange: AgentMcpAuthExchangeSpec): McpJsonObject = McpJsonObject.of(
        "method" to exchange.method,
        "path" to exchange.pathTemplate,
        "headers" to exchange.headerTemplates,
        "body_template" to exchange.bodyTemplate,
        "response_mappings" to exchange.responseMappings,
        "accepted_status_codes" to exchange.acceptedStatusCodes.sorted()
    )

    private fun authExchangeFromValue(value: McpJsonObject): AgentMcpAuthExchangeSpec = AgentMcpAuthExchangeSpec(
        method = value.string("method").orEmpty(),
        pathTemplate = value.string("path").orEmpty(),
        headerTemplates = value.objectValue("headers")?.entries.orEmpty().mapNotNull { (key, raw) ->
            (raw as? McpJsonString)?.value?.let { key to it }
        }.toMap(),
        bodyTemplate = value.string("body_template").orEmpty(),
        responseMappings = value.objectValue("response_mappings")?.entries.orEmpty().mapNotNull { (key, raw) ->
            (raw as? McpJsonString)?.value?.let { key to it }
        }.toMap(),
        acceptedStatusCodes = value.array("accepted_status_codes")?.values.orEmpty()
            .mapNotNull { (it as? McpJsonNumber)?.longOrNull()?.toInt() }.toSet().ifEmpty { setOf(200) }
    )

    private fun McpJsonObject.long(name: String): Long = (this[name] as? McpJsonNumber)?.longOrNull() ?: 0L
    private fun McpJsonObject.int(name: String): Int = long(name).toInt()
    private fun McpJsonObject.stringList(name: String): List<String> = array(name)?.values.orEmpty()
        .mapNotNull { (it as? McpJsonString)?.value }
}

class AgentMcpRegistry(
    private val store: AgentMcpStore,
    private val clock: () -> Long = System::currentTimeMillis
) {
    fun list(): List<AgentMcpConnection> = store.list()

    fun get(id: String): AgentMcpConnection? = list().firstOrNull { it.id == id }

    fun readyConnections(): List<AgentMcpConnection> = list().filter { it.isCallable(clock()) }

    fun addRemote(
        displayName: String,
        endpoint: String,
        authProfile: AgentMcpAuthProfile,
        catalogId: String = "",
        id: String = UUID.randomUUID().toString()
    ): AgentMcpConnection {
        val normalizedName = displayName.trim()
        require(normalizedName.isNotBlank()) { "MCP name must not be blank" }
        val normalizedEndpoint = AgentMcpEndpointPolicy.normalize(endpoint)
        val now = clock()
        val authState = if (authProfile.method == AgentMcpAuthMethod.NONE) {
            AgentMcpAuthState.NOT_REQUIRED
        } else {
            AgentMcpAuthState.NOT_CONFIGURED
        }
        val connection = AgentMcpConnection(
            id = id,
            catalogId = catalogId,
            displayName = normalizedName,
            endpoint = normalizedEndpoint,
            distribution = AgentMcpDistribution.REMOTE,
            transport = AgentMcpTransportKind.STREAMABLE_HTTP,
            authProfile = authProfile,
            authState = authState,
            state = if (authState == AgentMcpAuthState.NOT_REQUIRED) AgentMcpConnectionState.INSTALLED else AgentMcpConnectionState.NEEDS_SETUP,
            installedAtMillis = now,
            updatedAtMillis = now
        )
        store.upsert(connection)
        return connection
    }

    fun installCatalogEntry(
        entry: AgentMcpCatalogEntry,
        endpoint: String = entry.defaultEndpoint,
        authMethod: AgentMcpAuthMethod = entry.authProfiles.first().method
    ): AgentMcpConnection {
        require(!entry.requiresPackage) { "This MCP catalog entry requires a local package" }
        val profile = entry.authProfiles.firstOrNull { it.method == authMethod }
            ?: throw IllegalArgumentException("Unsupported authentication method: ${authMethod.wireValue}")
        val existing = list().firstOrNull { it.catalogId == entry.id }
        if (existing != null) return existing
        return addRemote(entry.name, endpoint, profile, entry.id)
    }

    fun installPackage(manifest: AgentMcpPackageManifest, packageSha256: String): AgentMcpConnection {
        val now = clock()
        val profile = manifest.authProfiles.firstOrNull() ?: AgentMcpAuthProfile(AgentMcpAuthMethod.NONE)
        val connection = AgentMcpConnection(
            id = manifest.id,
            catalogId = manifest.catalogId,
            displayName = manifest.name,
            endpoint = when (manifest.transport) {
                AgentMcpTransportKind.LOCAL_STDIO -> manifest.endpoint
                else -> AgentMcpEndpointPolicy.normalize(manifest.endpoint)
            },
            distribution = AgentMcpDistribution.LOCAL_PACKAGE,
            transport = manifest.transport,
            authProfile = profile,
            authState = if (profile.method == AgentMcpAuthMethod.NONE) AgentMcpAuthState.NOT_REQUIRED else AgentMcpAuthState.NOT_CONFIGURED,
            state = if (profile.method == AgentMcpAuthMethod.NONE) AgentMcpConnectionState.INSTALLED else AgentMcpConnectionState.NEEDS_SETUP,
            installedAtMillis = now,
            updatedAtMillis = now,
            toolIds = manifest.tools.map { it.name },
            packageVersion = manifest.version,
            packageSha256 = packageSha256
        )
        store.upsert(connection)
        return connection
    }

    fun beginAuthentication(id: String): AgentMcpAuthStepSpec? {
        val connection = requireConnection(id)
        if (connection.authProfile.method == AgentMcpAuthMethod.NONE) return null
        val next = connection.copy(
            authState = AgentMcpAuthState.CHALLENGE_REQUIRED,
            authStepIndex = 0,
            state = AgentMcpConnectionState.NEEDS_SETUP,
            updatedAtMillis = clock(),
            lastError = ""
        )
        store.clearSecrets(id)
        store.upsert(next)
        return next.currentAuthStep
    }

    fun submitAuthenticationStep(id: String, values: Map<String, String>): AgentMcpConnection {
        val current = requireConnection(id)
        val step = current.currentAuthStep ?: throw IllegalStateException("No authentication step is pending")
        val normalized = values.mapValues { it.value.trim() }
        val missing = step.fields.filter { it.required && normalized[it.id].isNullOrBlank() }
        require(missing.isEmpty()) { "Missing authentication fields: ${missing.joinToString { it.label }}" }
        val merged = store.readSecrets(id) + normalized.filterValues(String::isNotBlank)
        store.writeSecrets(id, merged)
        val nextIndex = current.authStepIndex + 1
        val now = clock()
        val finished = nextIndex >= current.authProfile.steps.size
        val expiresAt = if (finished && current.authProfile.accessTokenTtlMillis > 0L) {
            now + current.authProfile.accessTokenTtlMillis
        } else 0L
        val refreshAt = if (expiresAt > 0L && current.authProfile.supportsRefresh) {
            (expiresAt - current.authProfile.refreshLeadMillis).coerceAtLeast(now)
        } else 0L
        val next = current.copy(
            authState = if (finished) AgentMcpAuthState.AUTHENTICATED else AgentMcpAuthState.CHALLENGE_REQUIRED,
            authStepIndex = if (finished) current.authStepIndex else nextIndex,
            state = if (finished) AgentMcpConnectionState.INSTALLED else AgentMcpConnectionState.NEEDS_SETUP,
            expiresAtMillis = expiresAt,
            refreshAtMillis = refreshAt,
            updatedAtMillis = now,
            lastError = ""
        )
        store.upsert(next)
        return next
    }

    fun updateAuthProfile(id: String, profile: AgentMcpAuthProfile): AgentMcpConnection {
        val current = requireConnection(id)
        store.clearSecrets(id)
        val updated = current.copy(
            authProfile = profile,
            authState = if (profile.method == AgentMcpAuthMethod.NONE) AgentMcpAuthState.NOT_REQUIRED else AgentMcpAuthState.NOT_CONFIGURED,
            authStepIndex = 0,
            state = if (profile.method == AgentMcpAuthMethod.NONE) AgentMcpConnectionState.INSTALLED else AgentMcpConnectionState.NEEDS_SETUP,
            expiresAtMillis = 0L,
            refreshAtMillis = 0L,
            updatedAtMillis = clock(),
            lastError = ""
        )
        store.upsert(updated)
        return updated
    }

    fun markConnecting(id: String) = update(id) { it.copy(state = AgentMcpConnectionState.CONNECTING, updatedAtMillis = clock(), lastError = "") }

    fun markConnected(id: String, toolIds: List<String>) = update(id) {
        it.copy(
            state = AgentMcpConnectionState.CONNECTED,
            toolIds = toolIds.distinct().sorted(),
            lastValidatedAtMillis = clock(),
            updatedAtMillis = clock(),
            lastError = ""
        )
    }

    fun markFailure(id: String, message: String, authenticationFailure: Boolean = false) = update(id) {
        it.copy(
            state = if (authenticationFailure) AgentMcpConnectionState.NEEDS_SETUP else AgentMcpConnectionState.ERROR,
            authState = if (authenticationFailure) AgentMcpAuthState.REAUTHENTICATION_REQUIRED else it.authState,
            updatedAtMillis = clock(),
            lastError = message.take(500)
        )
    }

    fun markAuthenticationRefreshed(id: String, values: Map<String, String>): AgentMcpConnection {
        val current = requireConnection(id)
        val now = clock()
        store.writeSecrets(id, store.readSecrets(id) + values.filterValues(String::isNotBlank))
        val expiresAt = if (current.authProfile.accessTokenTtlMillis > 0L) {
            now + current.authProfile.accessTokenTtlMillis
        } else 0L
        val refreshAt = if (expiresAt > 0L && current.authProfile.supportsRefresh) {
            (expiresAt - current.authProfile.refreshLeadMillis).coerceAtLeast(now)
        } else 0L
        return current.copy(
            authState = AgentMcpAuthState.AUTHENTICATED,
            state = AgentMcpConnectionState.INSTALLED,
            expiresAtMillis = expiresAt,
            refreshAtMillis = refreshAt,
            updatedAtMillis = now,
            lastError = ""
        ).also(store::upsert)
    }

    fun setEnabled(id: String, enabled: Boolean) = update(id) { it.copy(enabled = enabled, updatedAtMillis = clock()) }

    fun setPermissionMode(id: String, mode: AgentMcpPermissionMode) = update(id) {
        it.copy(permissionMode = mode, updatedAtMillis = clock())
    }

    fun delete(id: String): Boolean = store.delete(id)

    fun secrets(id: String): Map<String, String> = store.readSecrets(id)

    fun requestHeaders(id: String): Map<String, String> {
        val connection = requireConnection(id)
        val secrets = store.readSecrets(id)
        return when (connection.authProfile.method) {
            AgentMcpAuthMethod.NONE -> emptyMap()
            AgentMcpAuthMethod.BEARER_TOKEN,
            AgentMcpAuthMethod.OAUTH2,
            AgentMcpAuthMethod.DEVICE_CODE -> secrets.tokenHeader()
            AgentMcpAuthMethod.API_KEY -> {
                val key = secrets["api_key"].orEmpty()
                val header = secrets["header_name"].orEmpty().ifBlank { "X-API-Key" }
                if (key.isBlank()) emptyMap() else mapOf(header to key)
            }
            AgentMcpAuthMethod.USERNAME_PASSWORD -> {
                val username = secrets["username"].orEmpty()
                val password = secrets["password"].orEmpty()
                if (username.isBlank() || password.isBlank()) emptyMap() else mapOf(
                    "Authorization" to "Basic ${Base64.getEncoder().encodeToString("$username:$password".toByteArray())}"
                )
            }
            AgentMcpAuthMethod.DYNAMIC -> buildMap {
                putAll(secrets.tokenHeader())
                secrets["session_cookie"]?.takeIf(String::isNotBlank)?.let { put("Cookie", it) }
                secrets.filterKeys { it.startsWith("header.") }.forEach { (key, value) ->
                    if (value.isNotBlank()) put(key.removePrefix("header."), value)
                }
            }
        }
    }

    private fun Map<String, String>.tokenHeader(): Map<String, String> {
        val token = get("access_token").orEmpty().ifBlank { get("token").orEmpty() }.ifBlank { get("device_code").orEmpty() }
        return if (token.isBlank()) emptyMap() else mapOf("Authorization" to "Bearer $token")
    }

    private fun requireConnection(id: String): AgentMcpConnection = get(id)
        ?: throw IllegalArgumentException("MCP connection not found: $id")

    private fun update(id: String, transform: (AgentMcpConnection) -> AgentMcpConnection): AgentMcpConnection {
        val next = transform(requireConnection(id))
        store.upsert(next)
        return next
    }
}

object AgentMcpEndpointPolicy {
    private const val MAX_ENDPOINT_CHARS = 2_048

    fun normalize(value: String): String {
        val endpoint = value.trim()
        require(endpoint.length in 8..MAX_ENDPOINT_CHARS) { "MCP endpoint is invalid" }
        val uri = java.net.URI(endpoint)
        require(uri.scheme.equals("https", true) || uri.scheme.equals("http", true)) {
            "MCP endpoint must use HTTP or HTTPS"
        }
        require(!uri.host.isNullOrBlank()) { "MCP endpoint must include a host" }
        require(uri.userInfo == null) { "Credentials must not be embedded in the MCP endpoint" }
        require(uri.fragment == null) { "MCP endpoint must not include a fragment" }
        return uri.normalize().toASCIIString()
    }
}

data class AgentCapabilityDependencyStatus(
    val available: Boolean,
    val missingNativeTools: Set<String> = emptySet(),
    val missingMcpCatalogIds: Set<String> = emptySet()
)

object AgentCapabilityDependencyResolver {
    fun resolve(
        skill: AgentSkillCatalogEntry,
        installedMcp: List<AgentMcpConnection>,
        nativeToolIds: Set<String>,
        nowMillis: Long = System.currentTimeMillis()
    ): AgentCapabilityDependencyStatus {
        val readyMcpIds = installedMcp.filter { it.isCallable(nowMillis) }.mapTo(mutableSetOf()) { it.catalogId }
        val missingNative = skill.requiredNativeTools - nativeToolIds
        val missingMcp = skill.requiredMcpCatalogIds - readyMcpIds
        return AgentCapabilityDependencyStatus(missingNative.isEmpty() && missingMcp.isEmpty(), missingNative, missingMcp)
    }
}

object AgentDefaultCapabilityCatalog {
    val mcpEntries: List<AgentMcpCatalogEntry> = listOf(
        AgentMcpCatalogEntry(
            id = "galaxyssi.mcp.github",
            name = "GitHub",
            summary = "Repositories, issues, pull requests, and code workflows",
            distribution = AgentMcpDistribution.REMOTE,
            defaultEndpoint = "https://api.githubcopilot.com/mcp/",
            authProfiles = listOf(
                AgentMcpAuthProfile(AgentMcpAuthMethod.OAUTH2, supportsRefresh = true),
                AgentMcpAuthProfile(AgentMcpAuthMethod.BEARER_TOKEN)
            ),
            toolHints = listOf("github.repositories", "github.issues", "github.pull_requests"),
            tags = setOf("development", "source-control")
        ),
        AgentMcpCatalogEntry(
            id = "galaxyssi.mcp.notion",
            name = "Notion",
            summary = "Search, read, and update Notion workspaces",
            distribution = AgentMcpDistribution.REMOTE,
            defaultEndpoint = "https://mcp.notion.com/mcp",
            authProfiles = listOf(AgentMcpAuthProfile(AgentMcpAuthMethod.OAUTH2, supportsRefresh = true)),
            toolHints = listOf("notion.search", "notion.pages"),
            tags = setOf("knowledge", "documents")
        ),
        AgentMcpCatalogEntry(
            id = "galaxyssi.mcp.home_assistant",
            name = "Home Assistant",
            summary = "Control trusted smart-home entities and automations",
            distribution = AgentMcpDistribution.REMOTE,
            authProfiles = listOf(
                AgentMcpAuthProfile(AgentMcpAuthMethod.BEARER_TOKEN),
                AgentMcpAuthProfile(AgentMcpAuthMethod.OAUTH2, supportsRefresh = true)
            ),
            toolHints = listOf("home_assistant.entities", "home_assistant.services"),
            tags = setOf("smart-home", "automation")
        ),
        AgentMcpCatalogEntry(
            id = "galaxyssi.mcp.relay_controller",
            name = "Relay Controller",
            summary = "Install a signed local package for authenticated relay control",
            distribution = AgentMcpDistribution.LOCAL_PACKAGE,
            authProfiles = listOf(AgentMcpAuthProfile(AgentMcpAuthMethod.DYNAMIC)),
            toolHints = listOf("relay.devices", "relay.switch"),
            tags = setOf("devices", "automation"),
            requiresPackage = true
        )
    )

    val skillEntries: List<AgentSkillCatalogEntry> by lazy {
        listOf(
            skill(
                id = "galaxyssi.catalog.deep-research",
                title = "Deep Research",
                summary = "Search, compare sources, and produce a cited brief",
                tools = listOf(
                    AgentWebIntelligenceNativeTools.SEARCH,
                    AgentWebIntelligenceNativeTools.FETCH,
                    AgentWebIntelligenceNativeTools.RESEARCH,
                    AgentWebIntelligenceNativeTools.DIFF
                )
            ),
            skill(
                id = "galaxyssi.catalog.device-health",
                title = "Device Health",
                summary = "Summarize battery, storage, power, and network health",
                tools = listOf(
                    AgentHardwareNativeTools.BATTERY_STATUS,
                    AgentHardwareNativeTools.MEMORY_STATUS,
                    AgentHardwareNativeTools.STORAGE_STATUS,
                    AgentHardwareNativeTools.NETWORK_STATUS
                )
            ),
            skill(
                id = "galaxyssi.catalog.github-triage",
                title = "GitHub Triage",
                summary = "Review issues and pull requests using the GitHub MCP",
                tools = listOf(AgentMcpNativeTools.CALL_TOOL),
                requiredMcp = setOf("galaxyssi.mcp.github")
            ),
            skill(
                id = "galaxyssi.catalog.notion-brief",
                title = "Notion Brief",
                summary = "Turn selected workspace pages into a concise brief",
                tools = listOf(AgentMcpNativeTools.CALL_TOOL),
                requiredMcp = setOf("galaxyssi.mcp.notion")
            ),
            skill(
                id = "galaxyssi.catalog.smart-home-routine",
                title = "Smart Home Routine",
                summary = "Run a verified multi-device routine through Home Assistant",
                tools = listOf(AgentMcpNativeTools.CALL_TOOL),
                requiredMcp = setOf("galaxyssi.mcp.home_assistant")
            )
        )
    }

    fun mcp(id: String): AgentMcpCatalogEntry? = mcpEntries.firstOrNull { it.id == id }
    fun skill(id: String): AgentSkillCatalogEntry? = skillEntries.firstOrNull { it.id == id }

    fun marketplaceItems(
        nativeTools: List<AgentNativeToolDescriptor>,
        installedMcp: List<AgentMcpConnection>,
        installedAutomations: List<AgentSkillInstallation>,
        nowMillis: Long = System.currentTimeMillis()
    ): List<AgentMarketplaceItem> {
        val native = nativeTools.map { tool ->
            val permissions = buildList {
                tool.requiredPermissions.forEach { requirement ->
                    add(AgentMarketplacePermission(
                        requirement.id,
                        requirement.title,
                        requirement.description,
                        scope = "android_permission",
                        risk = tool.risk.wireValue
                    ))
                }
                tool.requiredConsents.forEach { requirement ->
                    add(AgentMarketplacePermission(
                        requirement.id,
                        requirement.title,
                        requirement.description,
                        scope = "user_consent",
                        risk = tool.risk.wireValue
                    ))
                }
            }
            AgentMarketplaceItem(
                id = tool.id,
                kind = AgentCapabilityCatalogKind.NATIVE_TOOL,
                name = tool.title,
                summary = tool.description,
                version = tool.version,
                installState = when {
                    tool.availability.status == AgentNativeToolAvailabilityStatus.AVAILABLE ->
                        AgentMarketplaceInstallState.BUILT_IN
                    tool.availability.status == AgentNativeToolAvailabilityStatus.REQUIRES_SETUP ->
                        AgentMarketplaceInstallState.NEEDS_SETUP
                    else -> AgentMarketplaceInstallState.UNAVAILABLE
                },
                enabled = tool.availability.status == AgentNativeToolAvailabilityStatus.AVAILABLE,
                tags = tool.capabilities,
                capabilities = tool.capabilities,
                permissions = permissions,
                permissionDiff = AgentMarketplacePermissionDiff(unchanged = permissions),
                installedVersion = tool.version,
                dependencies = buildSet {
                    addAll(tool.requiredPermissions.map { it.id })
                    addAll(tool.requiredConsents.map { it.id })
                }
            )
        }
        val mcp = mcpEntries.map { entry ->
            val connection = installedMcp.firstOrNull { it.catalogId == entry.id }
            val permissions = mcpMarketplacePermissions(entry)
            val installedVersion = connection?.packageVersion?.ifBlank { entry.version }.orEmpty()
            AgentMarketplaceItem(
                id = entry.id,
                kind = AgentCapabilityCatalogKind.MCP,
                name = entry.name,
                summary = entry.summary,
                version = entry.version,
                installState = when {
                    connection == null -> AgentMarketplaceInstallState.AVAILABLE
                    connection.isCallable(nowMillis) -> AgentMarketplaceInstallState.INSTALLED
                    else -> AgentMarketplaceInstallState.NEEDS_SETUP
                },
                enabled = connection?.enabled ?: false,
                featured = entry.featured,
                tags = entry.tags,
                dependencies = entry.toolHints.toSet(),
                requiresLocalPackage = entry.requiresPackage,
                capabilities = entry.toolHints.toSet(),
                permissions = permissions,
                permissionDiff = if (connection == null) {
                    AgentMarketplacePermissionDiff(added = permissions)
                } else {
                    AgentMarketplacePermissionDiff(unchanged = permissions)
                },
                installedVersion = installedVersion,
                updateAvailable = installedVersion.isNotBlank() &&
                    compareMarketplaceVersions(entry.version, installedVersion) > 0,
                revocable = connection != null,
                revoked = connection?.enabled == false
            )
        }
        val groupedInstallations = installedAutomations.groupBy { it.id }
        val automations = skillEntries.map { entry ->
            val versions = groupedInstallations[entry.id].orEmpty()
                .sortedWith { left, right -> compareMarketplaceVersions(right.version, left.version) }
            val installation = versions.firstOrNull { it.enabled } ?: versions.firstOrNull()
            val dependency = AgentCapabilityDependencyResolver.resolve(
                entry,
                installedMcp,
                nativeTools.mapTo(mutableSetOf()) { it.id },
                nowMillis
            )
            val availablePermissions = skillMarketplacePermissions(entry.manifest)
            val installedPermissions = installation?.manifest?.let(::skillMarketplacePermissions).orEmpty()
            val availableById = availablePermissions.associateBy { it.id }
            val installedById = installedPermissions.associateBy { it.id }
            AgentMarketplaceItem(
                id = entry.id,
                kind = AgentCapabilityCatalogKind.AUTOMATION,
                name = entry.name,
                summary = entry.summary,
                version = entry.manifest.version,
                installState = when {
                    installation != null -> AgentMarketplaceInstallState.INSTALLED
                    dependency.available -> AgentMarketplaceInstallState.AVAILABLE
                    else -> AgentMarketplaceInstallState.NEEDS_SETUP
                },
                enabled = installation?.enabled ?: false,
                featured = entry.featured,
                tags = setOf("automation", "workflow"),
                dependencies = entry.requiredNativeTools + entry.requiredMcpCatalogIds,
                capabilities = entry.requiredNativeTools + entry.requiredMcpCatalogIds,
                permissions = availablePermissions,
                permissionDiff = AgentMarketplacePermissionDiff(
                    added = (availableById.keys - installedById.keys).mapNotNull(availableById::get),
                    removed = (installedById.keys - availableById.keys).mapNotNull(installedById::get),
                    unchanged = (availableById.keys intersect installedById.keys).mapNotNull(availableById::get)
                ),
                installedVersion = installation?.version.orEmpty(),
                updateAvailable = installation != null &&
                    compareMarketplaceVersions(entry.manifest.version, installation.version) > 0,
                rollbackVersions = versions
                    .filter { installation != null && compareMarketplaceVersions(it.version, installation.version) < 0 }
                    .map { it.version },
                revocable = installation != null,
                revoked = installation?.enabled == false
            )
        }
        return (native + mcp + automations).sortedWith(
            compareBy<AgentMarketplaceItem>({ it.kind.ordinal }, { !it.featured }, { it.name.lowercase(Locale.ROOT) })
        )
    }

    private fun mcpMarketplacePermissions(entry: AgentMcpCatalogEntry): List<AgentMarketplacePermission> =
        buildList {
            add(AgentMarketplacePermission(
                "network.${entry.id}",
                "Connect to ${entry.name}",
                "Exchange requests with the configured MCP server.",
                scope = "network",
                risk = "low"
            ))
            entry.toolHints.forEach { capability ->
                add(AgentMarketplacePermission(
                    capability,
                    capability,
                    "Allow the MCP server to expose this capability.",
                    scope = "mcp_tool",
                    risk = if (capability.contains("write") || capability.contains("control")) "high" else "medium"
                ))
            }
        }

    private fun skillMarketplacePermissions(manifest: AgentSkillManifest): List<AgentMarketplacePermission> =
        (manifest.permissions + manifest.nativeTools).distinct().map { permissionId ->
            AgentMarketplacePermission(
                permissionId,
                permissionId,
                "Required by this automation workflow.",
                scope = if (permissionId in manifest.nativeTools) "native_tool" else "skill",
                risk = "medium"
            )
        }

    private fun compareMarketplaceVersions(left: String, right: String): Int {
        val leftParts = left.split('.').map { it.filter(Char::isDigit).toIntOrNull() ?: 0 }
        val rightParts = right.split('.').map { it.filter(Char::isDigit).toIntOrNull() ?: 0 }
        return (0 until maxOf(leftParts.size, rightParts.size, 3))
            .firstNotNullOfOrNull { index ->
                (leftParts.getOrElse(index) { 0 } - rightParts.getOrElse(index) { 0 })
                    .takeIf { it != 0 }
            } ?: 0
    }

    private fun skill(
        id: String,
        title: String,
        summary: String,
        tools: List<String>,
        requiredMcp: Set<String> = emptySet()
    ): AgentSkillCatalogEntry {
        val manifest = AgentSkillManifest(
            id = id,
            version = "1.0.0",
            title = title,
            description = summary,
            instructions = summary,
            nativeTools = tools.toSet(),
            steps = tools.mapIndexed { index, tool ->
                AgentSkillStep("step-${index + 1}", tool, dependsOn = if (index == 0) emptyList() else listOf("step-$index"))
            },
            source = "galaxyssi_catalog",
            autoInvoke = false
        )
        return AgentSkillCatalogEntry(id, title, summary, tools.toSet(), requiredMcp, manifest = manifest)
    }
}
