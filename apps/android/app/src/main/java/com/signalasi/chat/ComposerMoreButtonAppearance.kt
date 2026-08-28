package com.signalasi.chat

import android.widget.ImageButton

internal fun ImageButton.renderComposerMoreButton(expanded: Boolean) {
    rotation = 0f
    setImageResource(
        if (expanded) R.drawable.ic_input_menu_collapse
        else R.drawable.ic_input_menu_grid
    )
    setBackgroundResource(
        if (expanded) R.drawable.input_menu_expanded_background
        else android.R.color.transparent
    )
}
