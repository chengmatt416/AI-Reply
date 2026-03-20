package com.chatassistant

import android.app.AlarmManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.util.*

/**
 * ContextIndexService: Background service that generates daily context indices
 */
class ContextIndexService : Service() {
    companion object {
        private const val TAG = "ContextIndexService"
        const val ACTION_GENERATE_INDEX = "com.chatassistant.GENERATE_INDEX"
    }

    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private lateinit var contextIndexer: ContextIndexer

    override fun onCreate() {
        super.onCreate()
        contextIndexer = ContextIndexer(applicationContext)
        scheduleDailyIndexing()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_GENERATE_INDEX -> {
                scope.launch {
                    try {
                        contextIndexer.generateDailyIndex()
                        contextIndexer.cleanupOldIndices()
                        Log.d(TAG, "Daily index generated successfully")
                    } catch (e: Exception) {
                        Log.e(TAG, "Error generating daily index", e)
                    }
                }
            }
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    /**
     * Schedule daily indexing at midnight
     */
    private fun scheduleDailyIndexing() {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, ContextIndexReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Calculate next midnight
        val calendar = Calendar.getInstance().apply {
            timeInMillis = System.currentTimeMillis()
            add(Calendar.DAY_OF_YEAR, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
        }

        // Schedule repeating alarm at midnight daily
        alarmManager.setRepeating(
            AlarmManager.RTC_WAKEUP,
            calendar.timeInMillis,
            AlarmManager.INTERVAL_DAY,
            pendingIntent
        )

        Log.d(TAG, "Scheduled daily indexing at midnight")
    }
}

/**
 * Receiver for daily context index generation
 */
class ContextIndexReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val serviceIntent = Intent(context, ContextIndexService::class.java).apply {
            action = ContextIndexService.ACTION_GENERATE_INDEX
        }
        context.startService(serviceIntent)
    }
}
