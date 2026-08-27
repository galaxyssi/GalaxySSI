package com.signalasi.chat

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.os.StatFs
import android.os.SystemClock
import android.provider.AlarmClock
import android.provider.CalendarContract
import android.provider.ContactsContract
import android.util.Log
import com.signalasi.chat.voice.VoiceFeatureFlags
import com.signalasi.chat.voice.agent.VoiceAgentRunBridge
import com.signalasi.chat.voice.agent.VoiceAgentRunRequest
import com.signalasi.chat.voice.metrics.VoiceLatencyTraceContext
import com.signalasi.chat.voice.modelstream.ModelStreamEvent
import com.signalasi.chat.voice.modelstream.ModelStreamUiMerger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Locale
import java.util.Date
import java.text.SimpleDateFormat
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.FutureTask
import java.util.concurrent.TimeUnit

data class AgentConnectorPlanningSnapshot(
    val targets: List<AgentCallableTarget>,
    val registrations: List<AgentRegistration>
)

interface AgentConnectorRegistry {
    fun availableTargets(): List<AgentCallableTarget>

    fun planningSnapshot(): AgentConnectorPlanningSnapshot {
        val targets = availableTargets()
        return AgentConnectorPlanningSnapshot(targets, registrations(targets))
    }

    fun registrations(): List<AgentRegistration> = registrations(availableTargets())

    fun registrations(targets: List<AgentCallableTarget>): List<AgentRegistration> = targets.map { target ->
        val fallbackLocation = when {
            target.id == "local-llm" -> AgentResourceLocation.PHONE
            target.kind == AgentConnectorKind.MODEL -> AgentResourceLocation.CLOUD
            target.kind == AgentConnectorKind.AGENT -> AgentResourceLocation.TRUSTED_DESKTOP
            target.kind == AgentConnectorKind.DEVICE -> AgentResourceLocation.PRIVATE_NETWORK
            else -> AgentResourceLocation.CLOUD
        }
        val providerProfile = target.providerProfile ?: ProviderProfileCatalog.fromTarget(target)
        val location = if (target.kind in setOf(AgentConnectorKind.AGENT, AgentConnectorKind.MODEL)) {
            providerProfile.location
        } else {
            fallbackLocation
        }
        val capabilities = target.capabilities.toSet()
        AgentRegistration(
            agentId = target.id,
            installationId = target.failureDomain.ifBlank { "installation:${target.id}" },
            deviceId = target.failureDomain.ifBlank { "device:${target.id}" },
            providerId = providerProfile.providerId,
            displayName = target.title,
            kind = target.kind,
            location = location,
            status = when (target.status) {
                AgentConnectorStatus.AVAILABLE -> AgentEndpointStatus.ONLINE
                AgentConnectorStatus.DISCONNECTED -> AgentEndpointStatus.OFFLINE
                AgentConnectorStatus.NEEDS_SETUP -> AgentEndpointStatus.PERMISSION_REQUIRED
            },
            capabilities = capabilities,
            protocol = AgentProtocolRange(
                preferred = "1.0",
                minimum = "1.0",
                maximum = "1.0",
                features = setOf("run.cancel", "run.events", "message.respond", "message.observe")
            ),
            connectionKind = when (location) {
                AgentResourceLocation.PHONE -> AgentConnectionKind.IN_PROCESS
                AgentResourceLocation.TRUSTED_DESKTOP -> AgentConnectionKind.SIGNALASI_LINK
                AgentResourceLocation.PRIVATE_NETWORK -> AgentConnectionKind.HTTP
                AgentResourceLocation.CLOUD -> AgentConnectionKind.HTTP
            },
            cost = providerProfile.pricing.tier,
            latency = providerProfile.latency.takeIf {
                target.kind in setOf(AgentConnectorKind.AGENT, AgentConnectorKind.MODEL)
            } ?: when (location) {
                AgentResourceLocation.PHONE -> AgentResourceLatency.INSTANT
                AgentResourceLocation.TRUSTED_DESKTOP, AgentResourceLocation.PRIVATE_NETWORK -> AgentResourceLatency.FAST
                AgentResourceLocation.CLOUD -> AgentResourceLatency.NORMAL
            },
            trust = when (location) {
                AgentResourceLocation.PHONE -> AgentResourceTrust.PHONE_SYSTEM
                AgentResourceLocation.TRUSTED_DESKTOP -> AgentResourceTrust.VERIFIED_PAIRED
                AgentResourceLocation.PRIVATE_NETWORK -> AgentResourceTrust.PRIVATE_CONFIGURED
                AgentResourceLocation.CLOUD -> AgentResourceTrust.CLOUD_CONFIGURED
            },
            capabilitiesHash = MessageDigest.getInstance("SHA-256")
                .digest(capabilities.map { it.name }.sorted().joinToString("\n").toByteArray(Charsets.UTF_8))
                .joinToString("") { "%02x".format(it) },
            failureDomain = target.failureDomain,
            runtimeFailureDomain = target.runtimeFailureDomain.ifBlank {
                val installation = target.failureDomain.ifBlank { "installation:${target.id}" }
                "$installation:${target.adapterType.ifBlank { target.id }}"
            },
            adapterType = target.adapterType.ifBlank { defaultAdapterType(target) },
            independentlyUpgradeable = target.independentlyUpgradeable,
            providerProfile = providerProfile
        )
    }

    private fun defaultAdapterType(target: AgentCallableTarget): String {
        val identity = "${target.id} ${target.title}".lowercase(Locale.ROOT)
        return when {
            "codex" in identity -> "codex-app-server-or-cli"
            "claude" in identity -> "claude-code-cli"
            "openclaw" in identity -> "openclaw-cli"
            "hermes" in identity -> "hermes-cli"
            "home-assistant" in identity || "home assistant" in identity -> "home-assistant-api"
            target.kind == AgentConnectorKind.MODEL && target.id == "local-llm" -> "local-model-api"
            target.kind == AgentConnectorKind.MODEL -> "cloud-model-api"
            target.kind == AgentConnectorKind.DEVICE -> "custom-device-api"
            else -> "custom-agent"
        }
    }
}

class StaticAgentConnectorRegistry : AgentConnectorRegistry {
    override fun availableTargets(): List<AgentCallableTarget> = listOf(
        AgentCallableTarget(
            id = "cloud-models",
            title = "Cloud Models",
            kind = AgentConnectorKind.MODEL,
            status = AgentConnectorStatus.AVAILABLE,
            capabilities = listOf(
                AgentCapability.CHAT,
                AgentCapability.REASONING,
                AgentCapability.LIVE_DATA,
                AgentCapability.TOOL_USE
            ),
            adapterType = "cloud-model-api"
        ),
        AgentCallableTarget(
            id = "local-llm",
            title = "Local LLM",
            kind = AgentConnectorKind.MODEL,
            status = AgentConnectorStatus.NEEDS_SETUP,
            capabilities = listOf(AgentCapability.CHAT, AgentCapability.LOCAL_INFERENCE),
            adapterType = "local-model-api"
        ),
        AgentCallableTarget(
            id = "hermes",
            title = "Hermes",
            kind = AgentConnectorKind.AGENT,
            status = AgentConnectorStatus.AVAILABLE,
            capabilities = listOf(
                AgentCapability.CHAT,
                AgentCapability.RESEARCH,
                AgentCapability.LIVE_DATA,
                AgentCapability.TOOL_USE,
                AgentCapability.MCP,
                AgentCapability.SKILL
            ),
            adapterType = "hermes-cli"
        ),
        AgentCallableTarget(
            id = "codex",
            title = "Codex",
            kind = AgentConnectorKind.AGENT,
            status = AgentConnectorStatus.AVAILABLE,
            capabilities = listOf(
                AgentCapability.CHAT,
                AgentCapability.REASONING,
                AgentCapability.RESEARCH,
                AgentCapability.LIVE_DATA,
                AgentCapability.CODE,
                AgentCapability.TASK_EXECUTION,
                AgentCapability.TOOL_USE,
                AgentCapability.MCP,
                AgentCapability.SKILL
            ),
            adapterType = "codex-app-server-or-cli"
        ),
        AgentCallableTarget(
            id = "claude-code",
            title = "Claude Code",
            kind = AgentConnectorKind.AGENT,
            status = AgentConnectorStatus.NEEDS_SETUP,
            capabilities = listOf(
                AgentCapability.CODE,
                AgentCapability.TASK_EXECUTION,
                AgentCapability.TOOL_USE,
                AgentCapability.MCP,
                AgentCapability.SKILL
            ),
            adapterType = "claude-code-cli"
        ),
        AgentCallableTarget(
            id = "openclaw",
            title = "OpenClaw",
            kind = AgentConnectorKind.AGENT,
            status = AgentConnectorStatus.NEEDS_SETUP,
            capabilities = listOf(
                AgentCapability.CHAT,
                AgentCapability.RESEARCH,
                AgentCapability.LIVE_DATA,
                AgentCapability.TASK_EXECUTION,
                AgentCapability.TOOL_USE,
                AgentCapability.MCP,
                AgentCapability.SKILL
            ),
            adapterType = "openclaw-cli"
        ),
        AgentCallableTarget(
            id = "home-assistant",
            title = "Home Assistant",
            kind = AgentConnectorKind.DEVICE,
            status = AgentConnectorStatus.NEEDS_SETUP,
            capabilities = listOf(AgentCapability.SMART_HOME, AgentCapability.DEVICE_CONTROL),
            adapterType = "home-assistant-api"
        )
    )
}

class AppStoreAgentConnectorRegistry(
    context: Context,
    internal val fallback: AgentConnectorRegistry = StaticAgentConnectorRegistry(),
    internal val providerHealthLedger: AgentProviderHealthLedger = EncryptedAgentProviderHealthLedger(context)
) : AgentConnectorRegistry {
    internal val appContext = context.applicationContext
    private val resourceHealth = AgentResourceHealthStore(appContext)
    private val contactSnapshotCache = AgentConnectorContactSnapshotCache()

    override fun registrations(): List<AgentRegistration> {
        val contacts = contactSnapshot()
        val targets = availableTargets(contacts)
        return projectRegistrations(super<AgentConnectorRegistry>.registrations(targets), contacts)
    }

    override fun planningSnapshot(): AgentConnectorPlanningSnapshot {
        val contacts = contactSnapshot()
        val targets = availableTargets(contacts)
        return AgentConnectorPlanningSnapshot(
            targets = targets,
            registrations = projectRegistrations(super<AgentConnectorRegistry>.registrations(targets), contacts)
        )
    }

    private fun projectRegistrations(
        registrations: List<AgentRegistration>,
        contacts: AgentConnectorContactSnapshot
    ): List<AgentRegistration> {
        val healthSnapshots = providerHealthLedger.snapshots().associateBy { it.scopeId }
        return registrations.map { registration ->
            val contact = contacts.contactForAgent(registration.agentId) ?: return@map registration
            val projectedStatus = registration.status
            val reportedStatus = when (contact.optString("setup_status").lowercase(Locale.ROOT)) {
                "ready", "online" -> AgentEndpointStatus.ONLINE
                "idle" -> AgentEndpointStatus.IDLE
                "busy", "running" -> AgentEndpointStatus.BUSY
                "degraded", "error" -> AgentEndpointStatus.DEGRADED
                "updating" -> AgentEndpointStatus.UPDATING
                "permission_required", "needs_permission" -> AgentEndpointStatus.PERMISSION_REQUIRED
                "unreachable", "timed_out" -> AgentEndpointStatus.UNREACHABLE
                "offline", "disconnected" -> AgentEndpointStatus.OFFLINE
                else -> projectedStatus
            }
            val status = if (projectedStatus == AgentEndpointStatus.ONLINE) reportedStatus else projectedStatus
            val desktopId = contact.optString("desktop_id")
            val adapterDescriptor = contact.optJSONObject("adapter") ?: JSONObject()
            val projected = registration.copy(
                installationId = contact.optString("installation_id")
                    .ifBlank { desktopId }
                    .ifBlank { registration.installationId },
                deviceId = contact.optString("device_id")
                    .ifBlank { desktopId }
                    .ifBlank { registration.deviceId },
                providerId = contact.optString("provider_id")
                    .ifBlank { contact.optString("cloud_provider") }
                    .ifBlank { desktopId }
                    .ifBlank { registration.providerId },
                status = status,
                protocol = AgentProtocolRange(
                    preferred = contact.optString("protocol_version").ifBlank { registration.protocol.preferred },
                    minimum = contact.optString("protocol_min_version").ifBlank { registration.protocol.minimum },
                    maximum = contact.optString("protocol_max_version").ifBlank { registration.protocol.maximum },
                    features = registration.protocol.features + contact.optJSONArray("protocol_features").stringSetValues()
                ),
                activeRuns = contact.optInt("active_runs", registration.activeRuns).coerceAtLeast(0),
                maxParallelRuns = contact.optInt("max_parallel_runs", registration.maxParallelRuns).coerceAtLeast(1),
                capabilitiesHash = contact.optString("capabilities_hash").ifBlank { registration.capabilitiesHash },
                runtimeFailureDomain = registration.runtimeFailureDomain.ifBlank {
                    val installation = contact.optString("installation_id")
                        .ifBlank { desktopId }
                        .ifBlank { registration.installationId }
                    "$installation:${adapterDescriptor.optString("adapter_type").ifBlank { registration.adapterType }}"
                },
                adapterType = adapterDescriptor.optString("adapter_type").ifBlank { registration.adapterType },
                independentlyUpgradeable = adapterDescriptor.optBoolean(
                    "independently_upgradeable",
                    registration.independentlyUpgradeable
                ),
                providerProfile = ProviderProfileCatalog.decode(
                    contact.optJSONObject("provider_profile")
                ) ?: registration.providerProfile,
                lastHeartbeatMillis = contact.optLong("setup_updated_at", registration.lastHeartbeatMillis),
                updatedAtMillis = contact.optLong("setup_updated_at", registration.updatedAtMillis)
            )
            val healthState = healthSnapshots[projected.runtimeHealthScope()]
                ?.circuitState(System.currentTimeMillis())
                ?: AgentProviderCircuitState.CLOSED
            projected.copy(
                status = when {
                    projected.status !in setOf(
                        AgentEndpointStatus.ONLINE,
                        AgentEndpointStatus.IDLE,
                        AgentEndpointStatus.BUSY,
                        AgentEndpointStatus.DEGRADED
                    ) -> projected.status
                    healthState == AgentProviderCircuitState.OPEN -> AgentEndpointStatus.UNREACHABLE
                    healthState == AgentProviderCircuitState.HALF_OPEN -> AgentEndpointStatus.DEGRADED
                    else -> projected.status
                }
            )
        }
    }

    override fun availableTargets(): List<AgentCallableTarget> = availableTargets(contactSnapshot())

    private fun availableTargets(contacts: AgentConnectorContactSnapshot): List<AgentCallableTarget> {
        val cloudProviders = cloudProviderTargets(contacts)
        val activeLocalProfile = LocalModelRuntimeSettings.activeProfiles(appContext).firstOrNull()
        val builtIn = fallback.availableTargets().mapNotNull { target ->
            if (target.id == "local-llm" && activeLocalProfile == null) return@mapNotNull null
            val contact = contacts.contactForAgent(target.id)
            val desktopDomain = contact?.optString("desktop_id").orEmpty()
            target.copy(
                title = if (target.id == "local-llm") {
                    checkNotNull(activeLocalProfile).displayName
                } else {
                    target.title
                },
                status = statusFor(target, contacts),
                failureDomain = target.failureDomain.ifBlank { desktopDomain },
                desktopAccessProfile = contact?.optString("desktop_access_profile")
                    .orEmpty().ifBlank { target.desktopAccessProfile },
                providerProfile = ProviderProfileCatalog.decode(
                    contact?.optJSONObject("provider_profile")
                ) ?: target.providerProfile
            )
        }.filterNot { target ->
            // Configured providers own their health circuit. Keeping this
            // aggregate alias would let Auto select the failed provider again.
            target.id == "cloud-models" && cloudProviders.isNotEmpty()
        }
        val desktopExtensions = desktopConnectorTargets(contacts)
        val customDevices = CustomDeviceConnectorStore(appContext).list().filter { it.enabled }.map { connector ->
            AgentCallableTarget(
                id = "custom-device:${connector.id}",
                title = connector.name,
                kind = AgentConnectorKind.DEVICE,
                status = if (connector.configured) AgentConnectorStatus.AVAILABLE else AgentConnectorStatus.NEEDS_SETUP,
                capabilities = listOf(AgentCapability.DEVICE_CONTROL),
                failureDomain = "custom-device:${connector.id}",
                runtimeFailureDomain = "custom-device:${connector.id}",
                adapterType = "custom-device-api"
            )
        }
        return (builtIn + cloudProviders + desktopExtensions + customDevices).distinctBy { it.id }
    }

    internal fun cloudProviderTargets(
        contacts: AgentConnectorContactSnapshot = contactSnapshot()
    ): List<AgentCallableTarget> {
        return buildList {
            for (contact in contacts.contacts) {
                if (contact.optBoolean("deleted", false)) continue
                if (contact.optString("delivery_mode") != "cloud_api") continue
                val id = contact.optString("id").ifBlank { contact.optString("signalasi_id") }
                if (id.isBlank()) continue
                val selected = contacts.selectedCloudModel(contact)
                val ready = AgentConnectorAvailability.cloudModelReady(selected)
                val provider = selected.optString("cloud_provider").ifBlank { id }
                val circuitOpen = resourceHealth.snapshot("target:$id").circuitOpen ||
                    resourceHealth.snapshot("domain:cloud:$provider").circuitOpen
                val endpoint = selected.optString("cloud_endpoint")
                val localEndpoint = endpoint.contains("127.0.0.1") ||
                    endpoint.contains("localhost") ||
                    endpoint.contains("192.168.") ||
                    endpoint.contains("10.") ||
                    endpoint.contains("172.16.")
                val status = when {
                    !ready -> AgentConnectorStatus.NEEDS_SETUP
                    circuitOpen -> AgentConnectorStatus.DISCONNECTED
                    else -> AgentConnectorStatus.AVAILABLE
                }
                val profile = ProviderProfileCatalog.fromCloudContact(selected, status)
                add(
                    AgentCallableTarget(
                        id = id,
                        title = selected.optString("display_name")
                            .ifBlank { selected.optString("name") }
                            .ifBlank { selected.optString("cloud_provider") }
                            .ifBlank { id },
                        kind = AgentConnectorKind.MODEL,
                        status = status,
                        failureDomain = "cloud:$provider",
                        runtimeFailureDomain = "cloud:$provider:$id",
                        adapterType = "cloud-model-api",
                        providerProfile = profile,
                        capabilities = buildList {
                            add(AgentCapability.CHAT)
                            add(AgentCapability.REASONING)
                            add(AgentCapability.TOOL_USE)
                            add(AgentCapability.LIVE_DATA)
                            if (localEndpoint) add(AgentCapability.LOCAL_INFERENCE)
                        }
                    )
                )
            }
        }
    }

    internal fun JSONArray?.stringSetValues(): Set<String> = buildSet {
        val values = this@stringSetValues ?: return@buildSet
        for (index in 0 until values.length()) {
            values.optString(index).takeIf(String::isNotBlank)?.let(::add)
        }
    }

    internal fun desktopConnectorTargets(
        contacts: AgentConnectorContactSnapshot = contactSnapshot()
    ): List<AgentCallableTarget> {
        return buildList {
            for (contact in contacts.contacts) {
                if (contact.optBoolean("deleted", false)) continue
                if (contact.optString("delivery_mode") != "pc_connector") continue
                val id = contact.optString("id").ifBlank { contact.optString("signalasi_id") }
                if (id.isBlank()) continue
                val kindText = contact.optString("agent_kind").lowercase(Locale.US)
                val search = "$id $kindText ${contact.optString("name")}".lowercase(Locale.US)
                val kind = when {
                    "model" in kindText || "llm" in search -> AgentConnectorKind.MODEL
                    "device" in kindText -> AgentConnectorKind.DEVICE
                    else -> AgentConnectorKind.AGENT
                }
                val advertisedCapabilities = advertisedCapabilities(contact)
                val adapterDescriptor = contact.optJSONObject("adapter") ?: JSONObject()
                val capabilities = advertisedCapabilities.ifEmpty { buildList {
                    add(AgentCapability.CHAT)
                    when {
                        "codex" in search -> {
                            add(AgentCapability.REASONING)
                            add(AgentCapability.RESEARCH)
                            add(AgentCapability.LIVE_DATA)
                            add(AgentCapability.CODE)
                            add(AgentCapability.TASK_EXECUTION)
                            add(AgentCapability.TOOL_USE)
                        }
                        "mcp" in search -> {
                            add(AgentCapability.MCP)
                            add(AgentCapability.TOOL_USE)
                            add(AgentCapability.TASK_EXECUTION)
                        }
                        "skill" in search -> {
                            add(AgentCapability.SKILL)
                            add(AgentCapability.TASK_EXECUTION)
                        }
                        kind == AgentConnectorKind.MODEL -> {
                            add(AgentCapability.REASONING)
                            add(AgentCapability.LOCAL_INFERENCE)
                        }
                        else -> {
                            add(AgentCapability.TASK_EXECUTION)
                            add(AgentCapability.TOOL_USE)
                        }
                    }
                } }
                add(
                    AgentCallableTarget(
                        id = id,
                        title = contact.optString("display_name")
                            .ifBlank { contact.optString("name") }
                            .ifBlank { id },
                        kind = kind,
                        status = if (contactReady(id, contacts)) AgentConnectorStatus.AVAILABLE else AgentConnectorStatus.DISCONNECTED,
                        failureDomain = contact.optString("desktop_id").ifBlank { "desktop:$id" },
                        runtimeFailureDomain = adapterDescriptor.optString("failure_domain").ifBlank {
                            val installation = contact.optString("installation_id")
                                .ifBlank { contact.optString("desktop_id") }
                                .ifBlank { "desktop:$id" }
                            "$installation:${adapterDescriptor.optString("adapter_type").ifBlank { agentIdForContact(contact, id) }}"
                        },
                        adapterType = adapterDescriptor.optString("adapter_type").ifBlank {
                            defaultDesktopAdapterType(contact, id)
                        },
                        independentlyUpgradeable = adapterDescriptor.optBoolean("independently_upgradeable", true),
                        capabilities = capabilities,
                        desktopAccessProfile = contact.optString(
                            "desktop_access_profile",
                            SignalASILinkProtocol.ACCESS_RESTRICTED
                        ),
                        providerProfile = ProviderProfileCatalog.decode(
                            contact.optJSONObject("provider_profile")
                        )
                    )
                )
            }
        }
    }

    internal fun advertisedCapabilities(contact: JSONObject): List<AgentCapability> {
        val values = contact.optJSONArray("capabilities") ?: return emptyList()
        return buildSet {
            for (index in 0 until values.length()) {
                when (values.optString(index).lowercase(Locale.US)) {
                    "conversation", "chat" -> add(AgentCapability.CHAT)
                    "reasoning", "cloud_inference" -> add(AgentCapability.REASONING)
                    "research" -> add(AgentCapability.RESEARCH)
                    "web", "live_data" -> add(AgentCapability.LIVE_DATA)
                    "tools", "tool_use", "terminal" -> add(AgentCapability.TOOL_USE)
                    "mcp" -> add(AgentCapability.MCP)
                    "skill", "skills" -> add(AgentCapability.SKILL)
                    "local_inference" -> add(AgentCapability.LOCAL_INFERENCE)
                    "code" -> add(AgentCapability.CODE)
                    "tasks", "task_execution", "automation", "files", "custom_tools" ->
                        add(AgentCapability.TASK_EXECUTION)
                    "smart_home" -> add(AgentCapability.SMART_HOME)
                    "device_control" -> add(AgentCapability.DEVICE_CONTROL)
                    "knowledge_search" -> add(AgentCapability.KNOWLEDGE_SEARCH)
                    "screen_reading" -> add(AgentCapability.SCREEN_READING)
                    "clipboard" -> add(AgentCapability.CLIPBOARD)
                    "system_settings" -> add(AgentCapability.SYSTEM_SETTINGS)
                    "app_navigation" -> add(AgentCapability.APP_NAVIGATION)
                    "alarm" -> add(AgentCapability.ALARM)
                }
            }
        }.toList()
    }

    internal fun agentIdForContact(contact: JSONObject, fallbackId: String): String =
        contact.optString("agent_id").ifBlank { fallbackId.substringAfter(':', fallbackId) }

    internal fun defaultDesktopAdapterType(contact: JSONObject, fallbackId: String): String {
        val identity = listOf(
            contact.optString("agent_id"),
            contact.optString("agent_kind"),
            contact.optString("name"),
            fallbackId
        ).joinToString(" ").lowercase(Locale.ROOT)
        return when {
            "codex" in identity -> "codex-app-server-or-cli"
            "claude" in identity -> "claude-code-cli"
            "openclaw" in identity -> "openclaw-cli"
            "hermes" in identity -> "hermes-cli"
            "local-llm" in identity || "local model" in identity -> "local-model-api"
            "windows" in identity -> "windows-host-tools"
            else -> "custom-agent"
        }
    }

    internal fun statusFor(
        target: AgentCallableTarget,
        contacts: AgentConnectorContactSnapshot = contactSnapshot()
    ): AgentConnectorStatus = when (target.id) {
        "cloud-models" -> if (hasConfiguredCloudModel(contacts)) AgentConnectorStatus.AVAILABLE else AgentConnectorStatus.NEEDS_SETUP
        "local-llm" -> when {
            LocalModelInferenceRuntime.ready(appContext) -> AgentConnectorStatus.AVAILABLE
            LocalModelManager.profiles(appContext).any { LocalModelManager.isInstalled(appContext, it) } ->
                AgentConnectorStatus.DISCONNECTED
            else -> AgentConnectorStatus.NEEDS_SETUP
        }
        "home-assistant" -> when {
            HomeAssistantSettingsStore.load(appContext).configured -> AgentConnectorStatus.AVAILABLE
            contacts.matchingContactIds(target.id).any { AppStore.outgoingTopicForContact(appContext, it) != null } ->
                AgentConnectorStatus.AVAILABLE
            contacts.matchingContactIds(target.id).isNotEmpty() -> AgentConnectorStatus.DISCONNECTED
            else -> AgentConnectorStatus.NEEDS_SETUP
        }
        else -> {
            val contactIds = contacts.matchingContactIds(target.id)
            when {
                contactIds.any { contactReady(it, contacts) } -> AgentConnectorStatus.AVAILABLE
                contactIds.isNotEmpty() -> AgentConnectorStatus.DISCONNECTED
                else -> AgentConnectorStatus.NEEDS_SETUP
            }
        }
    }

    internal fun contactReady(
        contactId: String,
        contacts: AgentConnectorContactSnapshot = contactSnapshot()
    ): Boolean {
        if (AppStore.outgoingTopicForContact(appContext, contactId) == null) return false
        val contact = contacts.contactById(contactId) ?: return false
        return if (AppStore.usesPcConnectorTunnel(appContext, contactId)) {
            val desktopId = AppStore.desktopIdForContact(appContext, contactId)
            desktopId.isNotBlank() &&
                SignalASICrypto.hasDesktopSession(appContext, desktopId) &&
                AgentConnectorAvailability.desktopAgentReady(contact)
        } else {
            SignalASICrypto.hasPeerSession(appContext, contactId)
        }
    }

    internal fun matchingContactIds(targetId: String): List<String> =
        contactSnapshot().matchingContactIds(targetId)

    internal fun hasConfiguredCloudModel(
        contacts: AgentConnectorContactSnapshot = contactSnapshot()
    ): Boolean {
        for (contact in contacts.contacts) {
            if (contact.optBoolean("deleted", false)) continue
            if (contact.optString("delivery_mode") != "cloud_api") continue
            val selected = contacts.selectedCloudModel(contact)
            if (AgentConnectorAvailability.cloudModelReady(selected)) return true
        }
        return false
    }

    private fun contactSnapshot(): AgentConnectorContactSnapshot {
        val source = AppStore.encodedContactsSnapshot(appContext)
        return contactSnapshotCache.get(source.revision) {
            AgentConnectorContactSnapshot.from(JSONArray(source.rawJson))
        }
    }
}

object AgentConnectorAvailability {
    internal val routableDesktopStates = setOf("ready", "busy")
    internal const val DESKTOP_STATUS_TTL_MILLIS = 10 * 60_000L
    internal const val MAX_CLOCK_SKEW_MILLIS = 60_000L

    fun desktopAgentReady(
        contact: JSONObject,
        nowMillis: Long = System.currentTimeMillis()
    ): Boolean {
        val statusReady = contact.optString("setup_status")
            .ifBlank { "unknown" }
            .lowercase(Locale.US) in routableDesktopStates
        if (!statusReady) return false
        val updatedAtMillis = contact.optLong("setup_updated_at", 0L)
        if (updatedAtMillis <= 0L) return false
        val ageMillis = nowMillis - updatedAtMillis
        return ageMillis in -MAX_CLOCK_SKEW_MILLIS..DESKTOP_STATUS_TTL_MILLIS
    }

    fun cloudModelReady(contact: JSONObject): Boolean = CloudModelCredentialPolicy.isAutoRoutable(contact)
}
