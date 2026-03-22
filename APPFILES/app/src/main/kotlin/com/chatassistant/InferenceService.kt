package com.chatassistant

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Binder
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.chatassistant.llama.AiChat
import com.chatassistant.llama.InferenceEngine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.io.File

class InferenceService : Service() {
    companion object {
        const val ACTION_START = "START"
        const val ACTION_LOAD_MODEL = "LOAD_MODEL"
        const val ACTION_SEND_PROMPT = "SEND_PROMPT"
        const val EXTRA_MODEL_PATH = "model_path"
        const val EXTRA_MESSAGE = "message"
        const val EXTRA_MAX_TOKENS = "max_tokens"
    }

    private lateinit var inferenceEngine: InferenceEngine
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private val binder = LocalBinder()

    inner class LocalBinder : Binder() {
        fun getService(): InferenceService = this@InferenceService
    }

    override fun onCreate() {
        super.onCreate()
        inferenceEngine = AiChat.getInferenceEngine(applicationContext)
        notif()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                // Service started
            }
            ACTION_LOAD_MODEL -> {
                val modelPath = intent.getStringExtra(EXTRA_MODEL_PATH)
                if (modelPath != null) {
                    loadModel(modelPath)
                }
            }
            ACTION_SEND_PROMPT -> {
                val message = intent.getStringExtra(EXTRA_MESSAGE)
                val maxTokens = intent.getIntExtra(EXTRA_MAX_TOKENS, 256)
                if (message != null) {
                    sendPrompt(message, maxTokens)
                }
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onDestroy() {
        scope.cancel()
        inferenceEngine.cleanUp()
        inferenceEngine.destroy()
        super.onDestroy()
    }

    fun getState(): StateFlow<InferenceEngine.State> = inferenceEngine.state

    fun loadModel(modelPath: String) {
        scope.launch {
            try {
                inferenceEngine.loadModel(modelPath)
                val systemPrompt = """你是智慧回覆助理。
輸出嚴格JSON（不含markdown）：{"replies":["回覆1","回覆2","回覆3"],"actions":[]}
actions格式：{"type":"add_alarm","time":"HH:mm","label":""}或{"type":"add_calendar","title":"","date":"yyyy-MM-dd","time":"HH:mm"}
僅在明確提到時間/行程時才填actions，否則[]。replies語言跟對話一致，簡短自然。"""
                inferenceEngine.setSystemPrompt(systemPrompt)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    fun sendPrompt(message: String, maxTokens: Int = 256): Flow<String> {
        return inferenceEngine.sendUserPrompt(message, maxTokens)
    }

    fun isModelLoaded(): Boolean {
        return inferenceEngine.state.value.isModelLoaded
    }

    private fun notif() {
        val ch = "llama_inference"
        val nm = getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(ch) == null) {
            nm.createNotificationChannel(
                NotificationChannel(ch, "LLM Inference", NotificationManager.IMPORTANCE_MIN)
            )
        }
        startForeground(
            43,
            NotificationCompat.Builder(this, ch)
                .setContentTitle("AI 推理引擎")
                .setContentText("本地模型運行中")
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setOngoing(true)
                .build()
        )
    }
}
