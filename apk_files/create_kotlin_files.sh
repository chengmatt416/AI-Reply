#!/data/data/com.termux/files/usr/bin/bash
# ════════════════════════════════════════════════════════════════════
#  Kotlin Source Code Files
#  Creates all Kotlin source files for the ChatAssistant app
# ════════════════════════════════════════════════════════════════════
set -euo pipefail

GREEN='\033[0;32m'
NC='\033[0m'
log() { echo -e "${GREEN}[✓]${NC} $*"; }

HOME_DIR=/data/data/com.termux/files/home
PROJ_DIR=$HOME_DIR/ChatAssistant

echo "Creating Kotlin source files..."

cat > "$PROJ_DIR/app/src/main/kotlin/com/chatassistant/MainActivity.kt" << 'KT'
package com.chatassistant
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.*
import android.net.Uri; import android.os.Bundle
import android.provider.Settings; import android.widget.Toast
import android.view.accessibility.AccessibilityManager
import androidx.appcompat.app.AppCompatActivity
import com.chatassistant.databinding.ActivityMainBinding
import kotlinx.coroutines.*
import okhttp3.OkHttpClient; import okhttp3.Request
import java.util.concurrent.TimeUnit

class MainActivity : AppCompatActivity() {
    private lateinit var b: ActivityMainBinding
    private val prefs by lazy { getSharedPreferences("assistant_prefs", MODE_PRIVATE) }
    private val http = OkHttpClient.Builder().connectTimeout(2, TimeUnit.SECONDS).build()

    override fun onCreate(s: Bundle?) {
        super.onCreate(s)
        window.statusBarColor = 0x00000000.toInt()
        window.navigationBarColor = 0x00000000.toInt()
        b = ActivityMainBinding.inflate(layoutInflater); setContentView(b.root)
        loadSettings(); setupListeners(); checkStatuses()
    }
    override fun onResume() { super.onResume(); checkStatuses() }

    private fun loadSettings() {
        b.etServerUrl.setText(prefs.getString("server_url","http://127.0.0.1:8080"))
        val t = prefs.getInt("max_tokens",256).toFloat().coerceIn(128f,512f)
        b.sliderTokens.value = t; b.tvTokenCount.text = t.toInt().toString()
    }
    private fun setupListeners() {
        b.btnOverlayPerm.setOnClickListener {
            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName")))
        }
        b.btnAccessibility.setOnClickListener {
            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        }
        b.btnStartService.setOnClickListener {
            if (!Settings.canDrawOverlays(this)) {
                Toast.makeText(this,"請先授予浮動視窗權限",Toast.LENGTH_SHORT).show(); return@setOnClickListener
            }
            if (!isAccessibilityEnabled()) {
                Toast.makeText(this,"請先開啟無障礙服務",Toast.LENGTH_SHORT).show(); return@setOnClickListener
            }
            startForegroundService(Intent(this,FloatingService::class.java).apply{action="START"})
            Toast.makeText(this,"✅ 助理服務已啟動",Toast.LENGTH_SHORT).show()
            b.btnStartService.text = "③ 服務運行中 ✓"
        }
        b.btnCheckStatus.setOnClickListener { checkStatuses(); checkLlm() }
        b.sliderTokens.addOnChangeListener { _,v,_ -> b.tvTokenCount.text = v.toInt().toString() }
        b.btnSaveSettings.setOnClickListener {
            prefs.edit()
                .putString("server_url", b.etServerUrl.text.toString())
                .putInt("max_tokens", b.sliderTokens.value.toInt()).apply()
            Toast.makeText(this,"設定已儲存",Toast.LENGTH_SHORT).show()
        }
    }
    private fun checkStatuses() {
        val ov = Settings.canDrawOverlays(this)
        b.tvOverlayStatus.text = if(ov) "✓ 已授權" else "未授權"
        b.tvOverlayStatus.setTextColor(if(ov) 0xFF03DAC5.toInt() else 0xFFFF6B6B.toInt())
        val ac = isAccessibilityEnabled()
        b.tvAccessStatus.text = if(ac) "✓ 已開啟" else "未開啟"
        b.tvAccessStatus.setTextColor(if(ac) 0xFF03DAC5.toInt() else 0xFFFF6B6B.toInt())
    }
    private fun checkLlm() {
        val url = prefs.getString("server_url","http://127.0.0.1:8080")!!
        CoroutineScope(Dispatchers.IO).launch {
            val ok = runCatching {
                http.newCall(Request.Builder().url("$url/health").build()).execute().isSuccessful
            }.getOrDefault(false)
            withContext(Dispatchers.Main) {
                b.tvLlmStatus.text = if(ok) "✓ 已連線" else "無法連線"
                b.tvLlmStatus.setTextColor(if(ok) 0xFF03DAC5.toInt() else 0xFFFF6B6B.toInt())
                b.dotLlm.background = getDrawable(if(ok) R.drawable.dot_green else R.drawable.dot_red)
            }
        }
    }
    private fun isAccessibilityEnabled(): Boolean {
        val am = getSystemService(AccessibilityManager::class.java)
        return am.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
            .any { it.resolveInfo.serviceInfo.packageName == packageName }
    }
}
KT

cat > "$PROJ_DIR/app/src/main/kotlin/com/chatassistant/ChatAccessibilityService.kt" << 'KT'
package com.chatassistant
import android.accessibilityservice.AccessibilityService
import android.content.Intent; import android.graphics.Rect
import android.view.accessibility.AccessibilityEvent; import android.view.accessibility.AccessibilityNodeInfo

class ChatAccessibilityService : AccessibilityService() {
    companion object {
        const val ACTION_NEW_CONTENT = "com.chatassistant.NEW_CONTENT"
        const val ACTION_UPDATE_POS  = "com.chatassistant.UPDATE_POS"
    }
    private val supported = setOf(
        "com.instagram.android",
        "com.linecorp.line", "jp.naver.line.android",
        "org.telegram.messenger",
        "com.whatsapp",
        "com.facebook.orca",
        "com.tencent.mm",
        "com.discord"
    )
    private var lastContent = ""; private var lastTop = -1

    override fun onAccessibilityEvent(e: AccessibilityEvent) {
        val pkg = e.packageName?.toString() ?: return
        if (pkg !in supported) return
        val root = rootInActiveWindow ?: return
        try {
            // Instagram: 僅在聊天室畫面才啟用（必須有輸入框且有「訊息/Send message」相關元素）
            if (pkg == "com.instagram.android" && !isInstagramChat(root)) return

            findInput(root)?.let { n ->
                val r = Rect(); n.getBoundsInScreen(r)
                if (r.top != lastTop) { lastTop = r.top; sendPos(r.top, r.bottom, pkg) }
                n.recycle()
            }
            val msgs = buildList { collectText(root, this, 0) }.takeLast(8).joinToString("\n")
            if (msgs.isNotBlank() && msgs != lastContent) { lastContent = msgs; sendContent(msgs, pkg) }
        } finally { root.recycle() }
    }

    private fun isInstagramChat(root: AccessibilityNodeInfo): Boolean {
        // 1) 必須找到可編輯的文字輸入框（聊天輸入欄）
        val input = findInput(root) ?: return false
        // 2) 畫面上需出現傳送訊息的提示文字/描述
        val hasSend = containsText(root, Regex("(Send message|發送訊息|傳送訊息|Message)", RegexOption.IGNORE_CASE))
        input.recycle()
        return hasSend
    }

    private fun containsText(n: AccessibilityNodeInfo, pattern: Regex): Boolean {
        val t = n.text?.toString() ?: n.contentDescription?.toString()
        if (t != null && pattern.containsMatchIn(t)) return true
        for (i in 0 until n.childCount) {
            val c = n.getChild(i) ?: continue
            val hit = containsText(c, pattern)
            c.recycle()
            if (hit) return true
        }
        return false
    }

    private fun findInput(n: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (n.isEditable && n.className?.contains("EditText") == true) return n
        for (i in 0 until n.childCount) {
            val c = n.getChild(i) ?: continue
            val f = findInput(c); if (f != null) return f; c.recycle()
        }; return null
    }
    private fun collectText(n: AccessibilityNodeInfo, out: MutableList<String>, depth: Int) {
        if (depth > 15) return
        val t = n.text?.toString()?.trim()
        if (!t.isNullOrBlank() && t.length > 3 &&
            !t.matches(Regex("""\d{1,2}:\d{2}(:\d{2})?""")) &&
            !t.matches(Regex("""\d{1,2}/\d{1,2}"""))) out.add(t)
        for (i in 0 until n.childCount) {
            val c = n.getChild(i) ?: continue; collectText(c, out, depth+1); c.recycle()
        }
    }
    private fun sendPos(top: Int, bot: Int, pkg: String) =
        startService(Intent(this, FloatingService::class.java).apply {
            action = ACTION_UPDATE_POS; putExtra("input_top",top); putExtra("input_bottom",bot); putExtra("pkg",pkg)
        })
    private fun sendContent(c: String, pkg: String) =
        startService(Intent(this, FloatingService::class.java).apply {
            action = ACTION_NEW_CONTENT; putExtra("content",c); putExtra("pkg",pkg)
        })
    override fun onInterrupt() {}
}
KT

cat > "$PROJ_DIR/app/src/main/kotlin/com/chatassistant/BootReceiver.kt" << 'KT'
package com.chatassistant
import android.content.BroadcastReceiver; import android.content.Context; import android.content.Intent
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, i: Intent) {
        if (i.action == Intent.ACTION_BOOT_COMPLETED)
            ctx.startForegroundService(Intent(ctx, FloatingService::class.java).apply{action="START"})
    }
}
KT

log "Basic Kotlin files created"
echo "Creating FloatingService.kt (this is a large file)..."

# FloatingService.kt is split due to size
cat > "$PROJ_DIR/app/src/main/kotlin/com/chatassistant/FloatingService.kt" << 'KTPART1'
package com.chatassistant
import android.animation.*; import android.app.*
import android.content.*; import android.content.res.ColorStateList
import android.graphics.*; import android.os.*
import android.provider.AlarmClock; import android.provider.CalendarContract
import android.view.*; import android.view.animation.*
import android.widget.*
import androidx.core.app.NotificationCompat
import com.google.android.material.card.MaterialCardView
import kotlinx.coroutines.*
import okhttp3.*; import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray; import org.json.JSONObject
import java.text.SimpleDateFormat; import java.util.*
import java.util.concurrent.TimeUnit

class FloatingService : Service() {
    private lateinit var wm: WindowManager; private lateinit var root: FrameLayout
    private lateinit var params: WindowManager.LayoutParams
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private lateinit var card: MaterialCardView; private lateinit var statusLabel: TextView
    private lateinit var loadingBar: ProgressBar; private lateinit var contentArea: LinearLayout
    private lateinit var chipRow: LinearLayout; private lateinit var actionRow: LinearLayout
    private val prefs by lazy { getSharedPreferences("assistant_prefs", MODE_PRIVATE) }
    private val http = OkHttpClient.Builder().connectTimeout(3,TimeUnit.SECONDS).readTimeout(20,TimeUnit.SECONDS).build()
    private var inputTop = 0; private var screenH = 0; private var isExpanded = true

    data class Ai(val replies: List<String>, val actions: List<Act>)
    data class Act(val type: String, val title: String="", val date: String="", val time: String="", val label: String="")

    override fun onCreate() {
        super.onCreate(); notif(); screenH = resources.displayMetrics.heightPixels; buildOverlay()
    }
    override fun onStartCommand(i: Intent?, f: Int, s: Int): Int {
        when (i?.action) {
            "START" -> show()
            ChatAccessibilityService.ACTION_UPDATE_POS -> {
                inputTop = i.getIntExtra("input_top", inputTop); updatePos(); show()
            }
            ChatAccessibilityService.ACTION_NEW_CONTENT -> {
                val c = i.getStringExtra("content") ?: return START_STICKY
                show(); if (isExpanded) generate(c, i.getStringExtra("pkg") ?: "")
            }
        }; return START_STICKY
    }
    override fun onBind(i: Intent?) = null
    override fun onDestroy() { scope.cancel(); runCatching { wm.removeView(root) }; super.onDestroy() }

    private fun buildOverlay() {
        wm = getSystemService(WINDOW_SERVICE) as WindowManager; root = FrameLayout(this)
        params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply { gravity = Gravity.BOTTOM or Gravity.START; y = 200 }
        buildUI(); wm.addView(root, params); root.visibility = View.GONE
    }

    private fun buildUI() {
        val dp = resources.displayMetrics.density; fun Int.dp() = (this * dp).toInt()
        card = MaterialCardView(this).apply {
            radius = 22f * dp; strokeWidth = 1.dp(); strokeColor = 0x33FFFFFF
            setCardBackgroundColor(0xCC0D1117.toInt()); cardElevation = 8f * dp; useCompatPadding = false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            card.setRenderEffect(RenderEffect.createBlurEffect(16f,16f,Shader.TileMode.CLAMP))
        }
        val inner = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; setPadding(14.dp(),10.dp(),14.dp(),12.dp())
        }
        val hdr = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        val dot = View(this).apply {
            background = getDrawable(R.drawable.dot_green)
            layoutParams = LinearLayout.LayoutParams(8.dp(),8.dp()).apply { marginEnd = 8.dp() }
        }
        statusLabel = TextView(this).apply {
            text = "✦ AI 回覆助理"; textSize = 13f; setTextColor(0xE0FFFFFFu.toInt())
            typeface = Typeface.DEFAULT_BOLD
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }
        val colBtn = ImageView(this).apply {
            setImageResource(android.R.drawable.arrow_down_float)
            setColorFilter(0x80FFFFFF.toInt())
            layoutParams = LinearLayout.LayoutParams(24.dp(),24.dp()).apply { marginStart=6.dp() }
            setOnClickListener { toggleExpand() }
        }
        val closeBtn = ImageView(this).apply {
            setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
            setColorFilter(0x60FFFFFF.toInt())
            layoutParams = LinearLayout.LayoutParams(24.dp(),24.dp()).apply { marginStart=6.dp() }
            setOnClickListener { hide() }
        }
        hdr.addView(dot); hdr.addView(statusLabel); hdr.addView(colBtn); hdr.addView(closeBtn)
        loadingBar = ProgressBar(this,null,android.R.attr.progressBarStyleHorizontal).apply {
            isIndeterminate = true; indeterminateTintList = ColorStateList.valueOf(0xFFA78BFA.toInt())
            visibility = View.GONE; layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,2.dp())
        }
        val div = View(this).apply {
            setBackgroundColor(0x1AFFFFFF); layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,1).apply{topMargin=8.dp();bottomMargin=8.dp()}
        }
        contentArea = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        chipRow = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        actionRow = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        contentArea.addView(chipRow); contentArea.addView(actionRow)
        inner.addView(hdr); inner.addView(loadingBar); inner.addView(div); inner.addView(contentArea)
        card.addView(inner)
        val lp = FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT).apply {
            leftMargin=12.dp(); rightMargin=12.dp(); bottomMargin=4.dp()
        }
        root.addView(card, lp)
    }

    private fun generate(chat: String, pkg: String) {
        loadingBar.visibility = View.VISIBLE; statusLabel.text = "⏳ 生成中..."
        chipRow.removeAllViews(); actionRow.removeAllViews()
        scope.launch {
            val cal = calCtx()
            val result = withContext(Dispatchers.IO) { callLlm(chat, pkg, cal) }
            loadingBar.visibility = View.GONE; statusLabel.text = "✦ AI 回覆助理"
            render(result)
        }
    }

    private fun callLlm(chat: String, pkg: String, cal: String): Ai {
        val app = mapOf("com.tencent.mm" to "WeChat","com.linecorp.line" to "LINE",
            "jp.naver.line.android" to "LINE","org.telegram.messenger" to "Telegram",
            "com.whatsapp" to "WhatsApp","com.facebook.orca" to "Messenger",
            "com.instagram.android" to "Instagram","com.discord" to "Discord")[pkg] ?: "Chat"
        val sys = """你是智慧回覆助理。日曆：$cal
輸出嚴格JSON（不含markdown）：{"replies":["回覆1","回覆2","回覆3"],"actions":[]}
actions格式：{"type":"add_alarm","time":"HH:mm","label":""}或{"type":"add_calendar","title":"","date":"yyyy-MM-dd","time":"HH:mm"}
僅在明確提到時間/行程時才填actions，否則[]。replies語言跟對話一致，簡短自然。"""
        val body = JSONObject().apply {
            put("messages", JSONArray().apply {
                put(JSONObject().put("role","system").put("content",sys))
                put(JSONObject().put("role","user").put("content","$app 對話：\n$chat"))
            })
            put("max_tokens", prefs.getInt("max_tokens",256))
            put("temperature",0.75); put("stream",false)
        }.toString()
        val url = prefs.getString("server_url","http://127.0.0.1:8080") + "/v1/chat/completions"
        return runCatching {
            val req = Request.Builder().url(url).post(body.toRequestBody("application/json".toMediaType())).build()
            val txt = http.newCall(req).execute().body?.string() ?: return fallback()
            val content = JSONObject(txt).getJSONArray("choices").getJSONObject(0).getJSONObject("message").getString("content").trim()
            parseAi(content)
        }.getOrElse { fallback() }
    }

    private fun parseAi(json: String): Ai {
        return runCatching {
            val o = JSONObject(json)
            val rep = (0 until o.getJSONArray("replies").length()).map { o.getJSONArray("replies").getString(it) }
            val acts = mutableListOf<Act>()
            o.optJSONArray("actions")?.let { arr ->
                for (i in 0 until arr.length()) {
                    val a = arr.getJSONObject(i)
                    acts.add(Act(a.getString("type"),a.optString("title"),a.optString("date"),a.optString("time"),a.optString("label")))
                }
            }
            Ai(rep, acts)
        }.getOrElse { fallback() }
    }
    private fun fallback() = Ai(listOf("好的","收到！","了解 👍"), emptyList())

    private fun render(ai: Ai) {
        chipRow.removeAllViews(); actionRow.removeAllViews()
        val colors = listOf(0x26A78BFA,0x261E40FF,0x26818CF8)
        val borders = listOf(0x4DA78BFA,0x4D1E40FF,0x4D818CF8)
        val textClrs= listOf(0xCCA78BFA,0xCC94A3F8.toInt(),0xCC818CF8.toInt())
        val dp = resources.displayMetrics.density; fun Int.dp()=(this*dp).toInt()
        ai.replies.forEachIndexed { i, reply ->
            val tv = TextView(this).apply {
                text = reply; textSize = 13.5f
                setTextColor(textClrs.getOrElse(i){0xCCFFFFFF.toInt()})
                setPadding(16.dp(),10.dp(),16.dp(),10.dp())
                background = rounded(colors.getOrElse(i){0x26FFFFFF},borders.getOrElse(i){0x33FFFFFF},18.dp().toFloat())
                layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,ViewGroup.LayoutParams.WRAP_CONTENT).apply{topMargin=5.dp()}
                maxLines=3; ellipsize=android.text.TextUtils.TruncateAt.END
                setOnClickListener { copyText(reply); pulse(this) }
            }
            chipRow.addView(tv)
            tv.alpha=0f; tv.translationY=12f
            tv.animate().alpha(1f).translationY(0f).setStartDelay((i*60).toLong()).setDuration(220).setInterpolator(DecelerateInterpolator()).start()
        }
        actionRow.visibility = if(ai.actions.isEmpty()) View.GONE else View.VISIBLE
        ai.actions.forEachIndexed { i, act ->
            val (em,lbl) = when(act.type) {
                "add_calendar" -> "📅" to "加入日曆：${act.title} ${act.date} ${act.time}"
                "add_alarm"    -> "⏰" to "設定鬧鐘：${act.time} ${act.label}"
                else -> "▶" to act.type
            }
            val row = LinearLayout(this).apply {
                orientation=LinearLayout.HORIZONTAL; gravity=Gravity.CENTER_VERTICAL
                setPadding(14.dp(),10.dp(),14.dp(),10.dp())
                background=rounded(0x20FFD700,0x40FFD700,16.dp().toFloat())
                layoutParams=LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,ViewGroup.LayoutParams.WRAP_CONTENT).apply{topMargin=5.dp()}
                addView(TextView(context).apply{text=em;textSize=16f;setPadding(0,0,10.dp(),0)})
                addView(TextView(context).apply{text=lbl;textSize=12.5f;setTextColor(0xCCFFD700.toInt())
                    layoutParams=LinearLayout.LayoutParams(0,ViewGroup.LayoutParams.WRAP_CONTENT,1f)})
                setOnClickListener{doAction(act)}
            }
            actionRow.addView(row)
            row.alpha=0f; row.animate().alpha(1f).setStartDelay(((ai.replies.size+i)*60).toLong()).setDuration(200).start()
        }
    }

    private fun rounded(fill:Int,stroke:Int,r:Float)=android.graphics.drawable.GradientDrawable().apply{
        shape=android.graphics.drawable.GradientDrawable.RECTANGLE;cornerRadius=r;setColor(fill);setStroke(1,stroke)
    }
    private fun updatePos() {
        if (inputTop<=0) return
        params.y = screenH - inputTop + (8*resources.displayMetrics.density).toInt()
        if (root.isAttachedToWindow) runCatching { wm.updateViewLayout(root,params) }
    }
    private fun show() {
        if (root.visibility==View.VISIBLE) return
        root.visibility=View.VISIBLE; root.alpha=0f; root.translationY=30f
        root.animate().alpha(1f).translationY(0f).setDuration(250).setInterpolator(DecelerateInterpolator(1.5f)).start()
    }
    private fun hide() {
        root.animate().alpha(0f).translationY(20f).setDuration(180).setInterpolator(AccelerateInterpolator())
            .withEndAction{root.visibility=View.GONE}.start()
    }
    private fun toggleExpand() {
        isExpanded=!isExpanded
        if (isExpanded) {
            contentArea.visibility=View.VISIBLE
            contentArea.measure(View.MeasureSpec.UNSPECIFIED,View.MeasureSpec.UNSPECIFIED)
            val h=contentArea.measuredHeight
            ValueAnimator.ofInt(0,h).apply{duration=220;interpolator=DecelerateInterpolator()
                addUpdateListener{contentArea.layoutParams.height=it.animatedValue as Int;contentArea.requestLayout()}
                addListener(object:AnimatorListenerAdapter(){override fun onAnimationEnd(a:Animator){contentArea.layoutParams.height=ViewGroup.LayoutParams.WRAP_CONTENT}})
            }.start()
        } else {
            val h=contentArea.height
            ValueAnimator.ofInt(h,0).apply{duration=180
                addUpdateListener{contentArea.layoutParams.height=it.animatedValue as Int;contentArea.requestLayout()}
                addListener(object:AnimatorListenerAdapter(){override fun onAnimationEnd(a:Animator){contentArea.visibility=View.GONE}})
            }.start()
        }
    }
    private fun pulse(v: View) {
        ObjectAnimator.ofPropertyValuesHolder(v,
            PropertyValuesHolder.ofFloat("scaleX",1f,.96f,1f),
            PropertyValuesHolder.ofFloat("scaleY",1f,.96f,1f)
        ).apply{duration=150;interpolator=DecelerateInterpolator()}.start()
        if (Build.VERSION.SDK_INT>=Build.VERSION_CODES.Q)
            getSystemService(Vibrator::class.java)?.vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_CLICK))
    }
    private fun copyText(t:String) {
        (getSystemService(ClipboardManager::class.java)).setPrimaryClip(ClipData.newPlainText("r",t))
        Toast.makeText(this,"✓ 已複製",Toast.LENGTH_SHORT).show()
    }
    private fun doAction(a:Act) { when(a.type){"add_alarm"->addAlarm(a);"add_calendar"->addCal(a)} }
    private fun addAlarm(a:Act) {
        val p=a.time.split(":").mapNotNull{it.toIntOrNull()}
        startActivity(Intent(AlarmClock.ACTION_SET_ALARM).apply{
            putExtra(AlarmClock.EXTRA_HOUR,p.getOrElse(0){8});putExtra(AlarmClock.EXTRA_MINUTES,p.getOrElse(1){0})
            putExtra(AlarmClock.EXTRA_MESSAGE,a.label.ifBlank{"助理鬧鐘"});putExtra(AlarmClock.EXTRA_SKIP_UI,true)
            flags=Intent.FLAG_ACTIVITY_NEW_TASK
        })
        Toast.makeText(this,"⏰ 已設定鬧鐘 ${a.time}",Toast.LENGTH_SHORT).show()
    }
    private fun addCal(a:Act) {
        runCatching {
            val sdf=SimpleDateFormat("yyyy-MM-dd HH:mm",Locale.getDefault())
            val s=sdf.parse("${a.date} ${a.time}")?.time?:(System.currentTimeMillis()+3600000)
            contentResolver.insert(CalendarContract.Events.CONTENT_URI, android.content.ContentValues().apply{
                put(CalendarContract.Events.TITLE,a.title);put(CalendarContract.Events.DTSTART,s)
                put(CalendarContract.Events.DTEND,s+3600000);put(CalendarContract.Events.CALENDAR_ID,defCal())
                put(CalendarContract.Events.EVENT_TIMEZONE,TimeZone.getDefault().id)
            })
            Toast.makeText(this,"📅 已加入日曆：${a.title}",Toast.LENGTH_SHORT).show()
        }.onFailure {
            startActivity(Intent(Intent.ACTION_INSERT).apply{
                data=CalendarContract.Events.CONTENT_URI;putExtra(CalendarContract.Events.TITLE,a.title)
                flags=Intent.FLAG_ACTIVITY_NEW_TASK
            })
        }
    }
    private fun defCal():Long {
        return contentResolver.query(CalendarContract.Calendars.CONTENT_URI,
            arrayOf(CalendarContract.Calendars._ID),"${CalendarContract.Calendars.IS_PRIMARY}=1",null,null)
            ?.use{if(it.moveToFirst())it.getLong(0) else 1L}?:1L
    }
    private fun calCtx():String {
        return runCatching {
            val c=contentResolver.query(CalendarContract.Events.CONTENT_URI,
                arrayOf(CalendarContract.Events.TITLE,CalendarContract.Events.DTSTART),
                "${CalendarContract.Events.DTSTART}>=?", arrayOf(System.currentTimeMillis().toString()),
                "${CalendarContract.Events.DTSTART} ASC")
            val l=mutableListOf<String>(); var n=0
            c?.use{while(it.moveToNext()&&n<4){l.add(SimpleDateFormat("MM/dd HH:mm",Locale.getDefault()).format(Date(it.getLong(1)))+" "+it.getString(0));n++}}
            if(l.isEmpty())"無近期行程" else l.joinToString("；")
        }.getOrDefault("")
    }
    private fun notif() {
        val ch="ca"; val nm=getSystemService(NotificationManager::class.java)
        if(nm.getNotificationChannel(ch)==null)
            nm.createNotificationChannel(NotificationChannel(ch,"Chat Assistant",NotificationManager.IMPORTANCE_MIN))
        startForeground(42,NotificationCompat.Builder(this,ch)
            .setContentTitle("Chat Assistant").setContentText("AI 回覆助理運行中")
            .setSmallIcon(android.R.drawable.ic_dialog_info).setOngoing(true).build())
    }
}
KTPART1

log "FloatingService.kt created"
log "All Kotlin source files created successfully"
