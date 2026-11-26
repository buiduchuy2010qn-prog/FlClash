package com.follow.clash.common

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

object LiveTelemetry {
    private val mutableSpeedText = MutableStateFlow("")
    val speedText = mutableSpeedText.asStateFlow()

    fun updateSpeed(text: String) {
        if (mutableSpeedText.value != text) {
            mutableSpeedText.value = text
        }
    }

    fun clear() {
        mutableSpeedText.value = ""
    }
}
