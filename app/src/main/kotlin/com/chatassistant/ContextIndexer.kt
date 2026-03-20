package com.chatassistant

import android.content.ContentResolver
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.provider.CalendarContract
import android.provider.MediaStore
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.*

/**
 * ContextIndexer: Creates daily index files containing photos, calendar events, and notes
 * to provide richer context for AI assistant responses
 */
class ContextIndexer(private val context: Context) {
    companion object {
        private const val TAG = "ContextIndexer"
        private const val INDEX_FILE_PREFIX = "context_index_"
        private const val MAX_PHOTOS_PER_DAY = 20
        private const val MAX_CALENDAR_EVENTS = 30
    }

    private val dateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
    private val datetimeFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())

    /**
     * Generate daily index file with all context data
     */
    suspend fun generateDailyIndex(): File = withContext(Dispatchers.IO) {
        val today = dateFormat.format(Date())
        val indexFile = File(context.filesDir, "$INDEX_FILE_PREFIX$today.json")

        try {
            val indexData = JSONObject().apply {
                put("generated_at", datetimeFormat.format(Date()))
                put("date", today)
                put("photos", indexRecentPhotos())
                put("calendar_events", indexCalendarEvents())
                put("notes", indexNotes())
            }

            indexFile.writeText(indexData.toString(2))
            Log.d(TAG, "Generated daily index: ${indexFile.absolutePath}")
        } catch (e: Exception) {
            Log.e(TAG, "Error generating daily index", e)
        }

        indexFile
    }

    /**
     * Index recent photos (last 7 days)
     */
    private fun indexRecentPhotos(): JSONArray {
        val photos = JSONArray()
        val sevenDaysAgo = System.currentTimeMillis() - (7 * 24 * 60 * 60 * 1000)

        try {
            val projection = arrayOf(
                MediaStore.Images.Media._ID,
                MediaStore.Images.Media.DISPLAY_NAME,
                MediaStore.Images.Media.DATE_TAKEN,
                MediaStore.Images.Media.DATA,
                MediaStore.Images.Media.SIZE
            )

            val selection = "${MediaStore.Images.Media.DATE_TAKEN} >= ?"
            val selectionArgs = arrayOf(sevenDaysAgo.toString())
            val sortOrder = "${MediaStore.Images.Media.DATE_TAKEN} DESC"

            context.contentResolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                sortOrder
            )?.use { cursor ->
                var count = 0
                while (cursor.moveToNext() && count < MAX_PHOTOS_PER_DAY) {
                    val id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID))
                    val name = cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME))
                    val dateTaken = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_TAKEN))
                    val path = cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATA))

                    photos.put(JSONObject().apply {
                        put("id", id)
                        put("name", name)
                        put("date", datetimeFormat.format(Date(dateTaken)))
                        put("uri", "content://media/external/images/media/$id")
                        put("path", path)
                    })
                    count++
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error indexing photos", e)
        }

        return photos
    }

    /**
     * Index calendar events (upcoming 30 events)
     */
    private fun indexCalendarEvents(): JSONArray {
        val events = JSONArray()
        val now = System.currentTimeMillis()

        try {
            val projection = arrayOf(
                CalendarContract.Events._ID,
                CalendarContract.Events.TITLE,
                CalendarContract.Events.DTSTART,
                CalendarContract.Events.DTEND,
                CalendarContract.Events.DESCRIPTION,
                CalendarContract.Events.EVENT_LOCATION
            )

            val selection = "${CalendarContract.Events.DTSTART} >= ?"
            val selectionArgs = arrayOf(now.toString())
            val sortOrder = "${CalendarContract.Events.DTSTART} ASC"

            context.contentResolver.query(
                CalendarContract.Events.CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                sortOrder
            )?.use { cursor ->
                var count = 0
                while (cursor.moveToNext() && count < MAX_CALENDAR_EVENTS) {
                    val id = cursor.getLong(cursor.getColumnIndexOrThrow(CalendarContract.Events._ID))
                    val title = cursor.getString(cursor.getColumnIndexOrThrow(CalendarContract.Events.TITLE)) ?: ""
                    val dtStart = cursor.getLong(cursor.getColumnIndexOrThrow(CalendarContract.Events.DTSTART))
                    val dtEnd = cursor.getLong(cursor.getColumnIndexOrThrow(CalendarContract.Events.DTEND))
                    val description = cursor.getString(cursor.getColumnIndexOrThrow(CalendarContract.Events.DESCRIPTION)) ?: ""
                    val location = cursor.getString(cursor.getColumnIndexOrThrow(CalendarContract.Events.EVENT_LOCATION)) ?: ""

                    events.put(JSONObject().apply {
                        put("id", id)
                        put("title", title)
                        put("start", datetimeFormat.format(Date(dtStart)))
                        put("end", datetimeFormat.format(Date(dtEnd)))
                        put("description", description)
                        put("location", location)
                    })
                    count++
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error indexing calendar events", e)
        }

        return events
    }

    /**
     * Index Google Keep notes (via content provider if available)
     * Note: Google Keep doesn't have a public API, so this is a placeholder
     * In production, this would need to use Keep API or alternative methods
     */
    private fun indexNotes(): JSONArray {
        val notes = JSONArray()

        // Google Keep doesn't expose a public content provider
        // This is a placeholder that could be implemented with:
        // 1. Keep API (requires authentication)
        // 2. Accessibility service to read Keep app content
        // 3. Third-party note apps with content providers

        Log.d(TAG, "Note indexing: Google Keep integration requires additional setup")

        return notes
    }

    /**
     * Read today's index file
     */
    suspend fun readTodayIndex(): JSONObject? = withContext(Dispatchers.IO) {
        val today = dateFormat.format(Date())
        val indexFile = File(context.filesDir, "$INDEX_FILE_PREFIX$today.json")

        if (!indexFile.exists()) {
            Log.d(TAG, "No index file for today, generating...")
            generateDailyIndex()
        }

        try {
            val content = indexFile.readText()
            JSONObject(content)
        } catch (e: Exception) {
            Log.e(TAG, "Error reading index file", e)
            null
        }
    }

    /**
     * Get formatted context summary for AI prompt
     */
    suspend fun getContextSummary(): String = withContext(Dispatchers.IO) {
        val index = readTodayIndex() ?: return@withContext ""

        val summary = StringBuilder()

        // Add calendar context
        val events = index.optJSONArray("calendar_events")
        if (events != null && events.length() > 0) {
            summary.append("近期行程：")
            for (i in 0 until minOf(5, events.length())) {
                val event = events.optJSONObject(i)
                event?.let {
                    val title = it.optString("title")
                    val start = it.optString("start")
                    summary.append("\n- $start: $title")
                }
            }
            summary.append("\n")
        }

        // Add photo context
        val photos = index.optJSONArray("photos")
        if (photos != null && photos.length() > 0) {
            summary.append("\n最近照片：${photos.length()} 張")
        }

        summary.toString()
    }

    /**
     * Clean up old index files (keep only last 7 days)
     */
    suspend fun cleanupOldIndices() = withContext(Dispatchers.IO) {
        try {
            val sevenDaysAgo = System.currentTimeMillis() - (7 * 24 * 60 * 60 * 1000)
            context.filesDir.listFiles { file ->
                file.name.startsWith(INDEX_FILE_PREFIX) && file.lastModified() < sevenDaysAgo
            }?.forEach { file ->
                file.delete()
                Log.d(TAG, "Deleted old index: ${file.name}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error cleaning up old indices", e)
        }
    }
}
