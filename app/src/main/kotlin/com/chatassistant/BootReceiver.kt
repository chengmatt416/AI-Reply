package com.chatassistant

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, i: Intent) {
        if (i.action == Intent.ACTION_BOOT_COMPLETED) {
            ctx.startForegroundService(Intent(ctx, FloatingService::class.java).apply { action = FloatingService.ACTION_START })
        }
    }
}
