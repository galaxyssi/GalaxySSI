package com.signalasi.chat

import android.content.Context
import org.json.JSONObject
import java.util.Locale

internal object GlobalBackgroundReasoningResourcePolicy {
    private val REASONING_TYPES = setOf(
        AgentResourceType.ON_DEVICE_MODEL,
        AgentResourceType.REMOTE_LOCAL_MODEL,
        AgentResourceType.CLOUD_MODEL,
        AgentResourceType.LOCAL_AGENT,
        AgentResourceType.REMOTE_AGENT
    )

    fun allowed(
        resource: AgentResourceDescriptor,
        allowPaired: Boolean,
        allowCloud: Boolean,
        localModelReady: Boolean
    ): Boolean {
        if (resource.status != AgentConnectorStatus.AVAILABLE || resource.type !in REASONING_TYPES) return false
        return when (resource.location) {
            AgentResourceLocation.PHONE ->
                resource.trust == AgentResourceTrust.PHONE_SYSTEM && localModelReady
            AgentResourceLocation.TRUSTED_DESKTOP ->
                allowPaired && resource.trust == AgentResourceTrust.VERIFIED_PAIRED && resource.supportsBackground
            AgentResourceLocation.PRIVATE_NETWORK ->
                allowCloud && resource.trust == AgentResourceTrust.PRIVATE_CONFIGURED
            AgentResourceLocation.CLOUD ->
                allowCloud && resource.trust == AgentResourceTrust.CLOUD_CONFIGURED
        }
    }
}

internal class GlobalAgentResourceResolver(context: Context) {
    private val appContext = context.applicationContext
    private val registry = AppStoreAgentConnectorRegistry(appContext)
    private val router = AgentResourceRouter(appContext)

    fun route(
        goal: String,
        allowPaired: Boolean,
        allowCloud: Boolean
    ): List<String> {
        val snapshot = registry.planningSnapshot()
        val decision = router.route(goal, snapshot.targets, snapshot.registrations)
        val localModelReady = LocalModelCooperativeRuntime.readyForBackground(appContext) &&
            LocalModelInferenceRuntime.canRunBackground()
        return (listOfNotNull(decision.primary) + decision.fallbacks)
            .map(AgentResourceCandidate::resource)
            .filter { resource ->
                GlobalBackgroundReasoningResourcePolicy.allowed(
                    resource,
                    allowPaired,
                    allowCloud,
                    localModelReady
                )
            }
            .map(AgentResourceDescriptor::targetId)
            .filter(String::isNotBlank)
            .distinct()
    }

    fun cloudContact(resourceId: String): JSONObject? {
        if (resourceId != "cloud-models" && AppStore.isCloudApiContact(appContext, resourceId)) {
            val contact = AppStore.selectedCloudModelContact(appContext, resourceId)
                ?: AppStore.contactById(appContext, resourceId)
            if (contact != null && AgentConnectorAvailability.cloudModelReady(contact)) return contact
        }
        if (resourceId != "cloud-models" && !resourceId.startsWith("cloud-model:") && !resourceId.startsWith("cloud:")) {
            return null
        }
        val contacts = AppStore.contacts(appContext)
        for (index in 0 until contacts.length()) {
            val contact = contacts.optJSONObject(index) ?: continue
            if (contact.optBoolean("deleted") || contact.optString("delivery_mode") != "cloud_api") continue
            val id = contact.optString("id").ifBlank { contact.optString("signalasi_id") }
            val selected = AppStore.selectedCloudModelContact(appContext, id) ?: contact
            if (AgentConnectorAvailability.cloudModelReady(selected)) return selected
        }
        return null
    }

    fun resolvePairedContact(resourceId: String): String? {
        AppStore.contactById(appContext, resourceId)?.let { contact ->
            if (contact.optString("delivery_mode") != "cloud_api" &&
                AppStore.outgoingTopicForContact(appContext, resourceId) != null
            ) return resourceId
        }
        val canonical = canonicalResourceId(resourceId)
        val contacts = AppStore.contacts(appContext)
        for (index in 0 until contacts.length()) {
            val contact = contacts.optJSONObject(index) ?: continue
            if (contact.optBoolean("deleted")) continue
            val id = contact.optString("id").ifBlank { contact.optString("signalasi_id") }
            val agentId = contact.optString("agent_id")
            if (canonicalResourceId(id) == canonical || canonicalResourceId(agentId) == canonical) {
                if (AppStore.outgoingTopicForContact(appContext, id) != null) return id
            }
        }
        return null
    }

    private fun canonicalResourceId(value: String): String = value.lowercase(Locale.ROOT)
        .replace("claudecode", "claude-code")
        .replace(Regex("[^a-z0-9]+"), "-")
        .trim('-')
        .substringBefore("-desktop")
        .substringBefore("-pc")
}
