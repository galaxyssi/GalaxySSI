package com.galaxyssi.chat

import android.view.View
import java.io.Closeable

internal fun MainActivity.knowledgeSourceCountState(): Pair<Int?, String> =
    runCatching { mobileNativeAgent.knowledgeStore.sourceCount() }.fold({ it to it.toString() }, { error ->
        null to if (error is KnowledgeSourceDirectoryNotReady) getString(R.string.navigation_content_loading)
        else getString(R.string.knowledge_model_error, error.message.orEmpty())
    })

internal fun MainActivity.showKnowledgeDirectoryWaiting(query: String, processed: Long) {
    val marker = featureValueRow(getString(R.string.agent_knowledge_title),
        getString(R.string.knowledge_sources_preparing, processed), R.drawable.ic_agent_knowledge,
        getString(R.string.navigation_content_loading))
    featureContent.addView(marker)
    var subscription: Closeable? = null
    marker.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(view: View) = Unit
        override fun onViewDetachedFromWindow(view: View) { subscription?.close(); subscription = null }
    })
    subscription = mobileNativeAgent.knowledgeStore.observeSourceDirectory {
        handler.post {
            subscription?.close(); subscription = null
            if (marker.parent === featureContent) showAgentKnowledgePage(query)
        }
    }
}
