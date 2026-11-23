package com.follow.clash

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class UpdateCleanupReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent?.action != Intent.ACTION_MY_PACKAGE_REPLACED) {
            return
        }
        val freed = UpdateStorageCleaner.clean(context)
        if (freed > 0L) {
            UpdateStorageCleaner.recordCleanedBytes(context, freed)
        }
    }
}
