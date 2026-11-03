package com.galaxyssi.chat

import android.content.Context
import android.net.Uri
import android.widget.ImageView
import java.lang.ref.WeakReference
import java.util.concurrent.Executors

internal object ComposerThumbnailLoader {
    private val executor = Executors.newFixedThreadPool(2) { Thread(it, "composer-thumbnail").apply { isDaemon = true } }

    fun load(context: Context, view: ImageView, uri: Uri, edge: Int) {
        view.tag = uri
        val target = WeakReference(view)
        val app = context.applicationContext
        executor.execute {
            val bitmap = AgentImagePipeline.loadPreview(app, uri, edge, edge) ?: return@execute
            val image = target.get()
            if (image == null) { bitmap.recycle(); return@execute }
            image.post {
                if (image.tag == uri && image.isAttachedToWindow) image.setImageBitmap(bitmap) else bitmap.recycle()
            }
        }
    }
}
