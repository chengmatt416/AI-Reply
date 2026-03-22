package com.chatassistant

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, i: Intent) {
        if (i.action == Intent.ACTION_BOOT_COMPLETED) {
            ctx.startForegroundService(Intent(ctx, FloatingService::class.java).apply { action = FloatingService.ACTION_START })
            // Start context indexing service
            ctx.startService(Intent(ctx, ContextIndexService::class.java).apply {
                action = ContextIndexService.ACTION_GENERATE_INDEX
            })
        }
    }
}
