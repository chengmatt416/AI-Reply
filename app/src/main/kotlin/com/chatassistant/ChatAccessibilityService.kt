package com.chatassistant

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.graphics.Rect
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class ChatAccessibilityService : AccessibilityService() {
    companion object {
        const val ACTION_NEW_CONTENT = "com.chatassistant.NEW_CONTENT"
        const val ACTION_UPDATE_POS = "com.chatassistant.UPDATE_POS"

        private val TIMESTAMP_REGEX = Regex("""\d{1,2}:\d{2}(:\d{2})?""")
        private val DATE_REGEX = Regex("""\d{1,2}/\d{1,2}""")
        private val INSTAGRAM_SEND_REGEX = Regex("(Send message|發送訊息|傳送訊息|Message)", RegexOption.IGNORE_CASE)
    }

    private val supported = setOf(
        "com.instagram.android",
        "com.linecorp.line",
        "jp.naver.line.android",
        "org.telegram.messenger",
        "com.whatsapp",
        "com.facebook.orca",
        "com.tencent.mm",
        "com.discord"
    )
    private var lastContent = ""
    private var lastTop = -1

    override fun onAccessibilityEvent(e: AccessibilityEvent) {
        val pkg = e.packageName?.toString() ?: return
        if (pkg !in supported) return
        val root = rootInActiveWindow ?: return
        try {
            if (pkg == "com.instagram.android" && !isInstagramChat(root)) return

            findInput(root)?.let { n ->
                val r = Rect()
                n.getBoundsInScreen(r)
                if (r.top != lastTop) {
                    lastTop = r.top
                    sendPos(r.top, r.bottom, pkg)
                }
                n.recycle()
            }
            val msgs = buildList { collectText(root, this, 0) }.takeLast(8).joinToString("\n")
            if (msgs.isNotBlank() && msgs != lastContent) {
                lastContent = msgs
                sendContent(msgs, pkg)
            }
        } finally {
            root.recycle()
        }
    }

    private fun isInstagramChat(root: AccessibilityNodeInfo): Boolean {
        val input = findInput(root) ?: return false
        val hasSend = containsText(root, INSTAGRAM_SEND_REGEX)
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
            val f = findInput(c)
            if (f != null) return f
            c.recycle()
        }
        return null
    }

    private fun collectText(n: AccessibilityNodeInfo, out: MutableList<String>, depth: Int) {
        if (depth > 15) return
        val t = n.text?.toString()?.trim()
        if (!t.isNullOrBlank() && t.length > 3 &&
            !t.matches(TIMESTAMP_REGEX) &&
            !t.matches(DATE_REGEX)
        ) out.add(t)
        for (i in 0 until n.childCount) {
            val c = n.getChild(i) ?: continue
            collectText(c, out, depth + 1)
            c.recycle()
        }
    }

    private fun sendPos(top: Int, bot: Int, pkg: String) =
        startService(Intent(this, FloatingService::class.java).apply {
            action = ACTION_UPDATE_POS
            putExtra("input_top", top)
            putExtra("input_bottom", bot)
            putExtra("pkg", pkg)
        })

    private fun sendContent(c: String, pkg: String) =
        startService(Intent(this, FloatingService::class.java).apply {
            action = ACTION_NEW_CONTENT
            putExtra("content", c)
            putExtra("pkg", pkg)
        })

    override fun onInterrupt() {}
}
