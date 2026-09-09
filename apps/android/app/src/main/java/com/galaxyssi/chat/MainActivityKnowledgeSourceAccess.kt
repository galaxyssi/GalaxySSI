package com.galaxyssi.chat

internal fun MainActivity.updateKnowledgeSourceAccessInBackground(group: AgentKnowledgeSourceGroup,
    cloudAccess: AgentKnowledgeCloudAccess, agentAccess: AgentKnowledgeAgentAccess, allowedAgentIds: List<String> = emptyList()) {
    val anchor = android.widget.ProgressBar(this)
    featureContent.addView(anchor)
    cloudExecutor.execute {
        val result = runCatching {
            val ids = group.reference?.let { mobileNativeAgent.knowledgeStore.sourceItemIds(it) } ?: group.itemIds
            mobileNativeAgent.updateKnowledgeSourceAccess(ids, cloudAccess, agentAccess, allowedAgentIds)
        }
        handler.post {
            if (anchor.parent !== featureContent) return@post
            featureContent.removeView(anchor)
            result.onSuccess { showAgentKnowledgePage() }.onFailure { error ->
                android.widget.Toast.makeText(this, error.message.orEmpty(), android.widget.Toast.LENGTH_LONG).show()
            }
        }
    }
}
