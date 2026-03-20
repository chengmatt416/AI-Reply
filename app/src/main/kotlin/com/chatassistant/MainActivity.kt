package com.chatassistant

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.provider.Settings
import android.view.View
import android.view.accessibility.AccessibilityManager
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.chatassistant.databinding.ActivityMainBinding
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.TimeUnit

class MainActivity : AppCompatActivity() {
    companion object {
        private const val PERMISSION_REQUEST_CODE = 100
    }
    private lateinit var b: ActivityMainBinding
    private val prefs by lazy { getSharedPreferences("assistant_prefs", MODE_PRIVATE) }
    private val http = OkHttpClient.Builder()
        .connectTimeout(2, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .build()
    private var inferenceService: InferenceService? = null
    private var isBound = false

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            val binder = service as InferenceService.LocalBinder
            inferenceService = binder.getService()
            isBound = true
            updateModelStatus()
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            inferenceService = null
            isBound = false
        }
    }

    override fun onCreate(s: Bundle?) {
        super.onCreate(s)
        window.statusBarColor = 0x00000000.toInt()
        window.navigationBarColor = 0x00000000.toInt()
        b = ActivityMainBinding.inflate(layoutInflater)
        setContentView(b.root)
        loadSettings()
        setupListeners()
        checkStatuses()

        // Request runtime permissions
        requestNecessaryPermissions()

        // Bind to InferenceService
        Intent(this, InferenceService::class.java).also { intent ->
            bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE)
        }

        // Start context indexing service
        startService(Intent(this, ContextIndexService::class.java).apply {
            action = ContextIndexService.ACTION_GENERATE_INDEX
        })
    }

    override fun onDestroy() {
        super.onDestroy()
        if (isBound) {
            unbindService(serviceConnection)
            isBound = false
        }
    }

    override fun onResume() {
        super.onResume()
        checkStatuses()
        updateModelStatus()
    }

    private fun loadSettings() {
        b.etServerUrl.setText(prefs.getString("server_url", "http://127.0.0.1:8080"))
        val t = prefs.getInt("max_tokens", 256).toFloat().coerceIn(128f, 512f)
        b.sliderTokens.value = t
        b.tvTokenCount.text = t.toInt().toString()
    }

    private fun setupListeners() {
        b.btnOverlayPerm.setOnClickListener {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName")
                )
            )
        }
        b.btnAccessibility.setOnClickListener {
            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        }
        b.btnStartService.setOnClickListener {
            if (!Settings.canDrawOverlays(this)) {
                Toast.makeText(this, "請先授予浮動視窗權限", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            if (!isAccessibilityEnabled()) {
                Toast.makeText(this, "請先開啟無障礙服務", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            startForegroundService(Intent(this, FloatingService::class.java).apply { action = FloatingService.ACTION_START })
            startForegroundService(Intent(this, InferenceService::class.java).apply { action = InferenceService.ACTION_START })
            Toast.makeText(this, "✅ 助理服務已啟動", Toast.LENGTH_SHORT).show()
            b.btnStartService.text = "③ 服務運行中 ✓"
        }
        b.btnCheckStatus.setOnClickListener { checkStatuses(); checkLlm() }
        b.sliderTokens.addOnChangeListener { _, v, _ -> b.tvTokenCount.text = v.toInt().toString() }
        b.btnSaveSettings.setOnClickListener {
            prefs.edit()
                .putString("server_url", b.etServerUrl.text.toString())
                .putInt("max_tokens", b.sliderTokens.value.toInt())
                .apply()
            Toast.makeText(this, "設定已儲存", Toast.LENGTH_SHORT).show()
        }
        b.btnDownloadModel.setOnClickListener {
            downloadModel()
        }
        b.btnLoadModel.setOnClickListener {
            loadModel()
        }
    }

    private fun checkStatuses() {
        val ov = Settings.canDrawOverlays(this)
        b.tvOverlayStatus.text = if (ov) "✓ 已授權" else "未授權"
        b.tvOverlayStatus.setTextColor(if (ov) 0xFF03DAC5.toInt() else 0xFFFF6B6B.toInt())
        val ac = isAccessibilityEnabled()
        b.tvAccessStatus.text = if (ac) "✓ 已開啟" else "未開啟"
        b.tvAccessStatus.setTextColor(if (ac) 0xFF03DAC5.toInt() else 0xFFFF6B6B.toInt())
    }

    private fun checkLlm() {
        val url = prefs.getString("server_url", "http://127.0.0.1:8080")!!
        CoroutineScope(Dispatchers.IO).launch {
            val ok = runCatching {
                http.newCall(Request.Builder().url("$url/health").build()).execute().isSuccessful
            }.getOrDefault(false)
            withContext(Dispatchers.Main) {
                b.tvLlmStatus.text = if (ok) "✓ 已連線" else "無法連線"
                b.tvLlmStatus.setTextColor(if (ok) 0xFF03DAC5.toInt() else 0xFFFF6B6B.toInt())
                b.dotLlm.background = ContextCompat.getDrawable(this@MainActivity, if (ok) R.drawable.dot_green else R.drawable.dot_red)
            }
        }
    }

    private fun isAccessibilityEnabled(): Boolean {
        val am = getSystemService(AccessibilityManager::class.java)
        return am.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
            .any { it.resolveInfo.serviceInfo.packageName == packageName }
    }

    private fun getModelPath(): String {
        return File(filesDir, "gemma-2b-it-q4_0.gguf").absolutePath
    }

    private fun updateModelStatus() {
        val modelFile = File(getModelPath())
        val exists = modelFile.exists()
        val isLoaded = inferenceService?.isModelLoaded() ?: false

        b.tvModelStatus.text = when {
            isLoaded -> "✓ 已載入"
            exists -> "已下載"
            else -> "未下載"
        }
        b.tvModelStatus.setTextColor(
            when {
                isLoaded -> 0xFF03DAC5.toInt()
                exists -> 0xFFFFA726.toInt()
                else -> 0xFFFF6B6B.toInt()
            }
        )
        b.btnDownloadModel.visibility = if (exists) View.GONE else View.VISIBLE
        b.btnLoadModel.visibility = if (exists && !isLoaded) View.VISIBLE else View.GONE
    }

    private fun downloadModel() {
        b.btnDownloadModel.isEnabled = false
        b.progressDownload.visibility = View.VISIBLE
        b.tvDownloadProgress.visibility = View.VISIBLE
        b.tvDownloadProgress.text = "準備下載..."

        CoroutineScope(Dispatchers.IO).launch {
            try {
                // Using HuggingFace model URL for Gemma 2B quantized
                val url = "https://huggingface.co/lmstudio-community/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf"
                val request = Request.Builder().url(url).build()
                val response = http.newCall(request).execute()

                if (!response.isSuccessful) {
                    withContext(Dispatchers.Main) {
                        Toast.makeText(this@MainActivity, "下載失敗: ${response.code}", Toast.LENGTH_SHORT).show()
                        b.btnDownloadModel.isEnabled = true
                        b.progressDownload.visibility = View.GONE
                        b.tvDownloadProgress.visibility = View.GONE
                    }
                    return@launch
                }

                val totalBytes = response.body?.contentLength() ?: 0
                val outputFile = File(getModelPath())
                val inputStream = response.body?.byteStream()
                val outputStream = FileOutputStream(outputFile)

                val buffer = ByteArray(8192)
                var downloadedBytes = 0L
                var bytesRead: Int

                while (inputStream?.read(buffer).also { bytesRead = it ?: -1 } != -1) {
                    outputStream.write(buffer, 0, bytesRead)
                    downloadedBytes += bytesRead

                    val progress = if (totalBytes > 0) {
                        (downloadedBytes * 100 / totalBytes).toInt()
                    } else 0

                    withContext(Dispatchers.Main) {
                        b.progressDownload.progress = progress
                        val mb = downloadedBytes / (1024 * 1024)
                        val totalMb = totalBytes / (1024 * 1024)
                        b.tvDownloadProgress.text = "已下載: ${mb}MB / ${totalMb}MB ($progress%)"
                    }
                }

                outputStream.close()
                inputStream?.close()

                withContext(Dispatchers.Main) {
                    Toast.makeText(this@MainActivity, "✓ 模型下載完成", Toast.LENGTH_SHORT).show()
                    b.progressDownload.visibility = View.GONE
                    b.tvDownloadProgress.visibility = View.GONE
                    b.btnDownloadModel.isEnabled = true
                    updateModelStatus()
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    Toast.makeText(this@MainActivity, "下載錯誤: ${e.message}", Toast.LENGTH_LONG).show()
                    b.btnDownloadModel.isEnabled = true
                    b.progressDownload.visibility = View.GONE
                    b.tvDownloadProgress.visibility = View.GONE
                }
            }
        }
    }

    private fun loadModel() {
        b.btnLoadModel.isEnabled = false
        b.btnLoadModel.text = "載入中..."

        CoroutineScope(Dispatchers.Main).launch {
            try {
                inferenceService?.loadModel(getModelPath())
                Toast.makeText(this@MainActivity, "✓ 模型已載入", Toast.LENGTH_SHORT).show()
                updateModelStatus()
            } catch (e: Exception) {
                Toast.makeText(this@MainActivity, "載入失敗: ${e.message}", Toast.LENGTH_SHORT).show()
            } finally {
                b.btnLoadModel.isEnabled = true
                b.btnLoadModel.text = "載入模型"
            }
        }
    }

    private fun requestNecessaryPermissions() {
        val permissions = mutableListOf<String>()

        // Check for storage/media permissions
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_MEDIA_IMAGES)
                != PackageManager.PERMISSION_GRANTED) {
                permissions.add(android.Manifest.permission.READ_MEDIA_IMAGES)
            }
        } else {
            if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_EXTERNAL_STORAGE)
                != PackageManager.PERMISSION_GRANTED) {
                permissions.add(android.Manifest.permission.READ_EXTERNAL_STORAGE)
            }
        }

        // Check for calendar permissions
        if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_CALENDAR)
            != PackageManager.PERMISSION_GRANTED) {
            permissions.add(android.Manifest.permission.READ_CALENDAR)
        }

        if (permissions.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, permissions.toTypedArray(), PERMISSION_REQUEST_CODE)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val allGranted = grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            if (allGranted) {
                Toast.makeText(this, "✓ 權限已授予", Toast.LENGTH_SHORT).show()
                // Restart context indexing after permissions granted
                startService(Intent(this, ContextIndexService::class.java).apply {
                    action = ContextIndexService.ACTION_GENERATE_INDEX
                })
            } else {
                Toast.makeText(this, "需要權限以啟用完整功能", Toast.LENGTH_LONG).show()
            }
        }
    }
}
