package com.galaxyssi.chat

import java.util.concurrent.Executors

/** Size previews never decode on the UI thread or compete with unbounded picker workers. */
internal val ComposerImagePreviewWorker = Executors.newSingleThreadExecutor { task ->
    Thread(task, "composer-image-size").apply { isDaemon = true }
}
