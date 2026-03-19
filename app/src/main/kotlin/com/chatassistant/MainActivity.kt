package com.chatassistant

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.chatassistant.databinding.ActivityMainBinding
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

class MainActivity : AppCompatActivity() {
    private lateinit var b: ActivityMainBinding
    private val prefs by lazy { getSharedPreferences("assistant_prefs", MODE_PRIVATE) }
    private val http = OkHttpClient.Builder().connectTimeout(2, TimeUnit.SECONDS).build()

    override fun onCreate(s: Bundle?) {
        super.onCreate(s)
        window.statusBarColor = 0x00000000.toInt()
        window.navigationBarColor = 0x00000000.toInt()
        b = ActivityMainBinding.inflate(layoutInflater)
        setContentView(b.root)
        loadSettings()
        setupListeners()
        checkStatuses()
    }

    override fun onResume() {
        super.onResume()
        checkStatuses()
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
}
