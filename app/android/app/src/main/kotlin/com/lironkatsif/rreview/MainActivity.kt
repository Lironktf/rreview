package com.lironkatsif.rreview

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

/**
 * Hosts the Flutter engine and implements the native half of the share intake:
 *
 *  MethodChannel "rreview/share_intake"         -> takePending(): List<Map>
 *  EventChannel  "rreview/share_intake/events"  -> items arriving while running
 *
 * Share / VIEW intents are converted into items (see [makeItem] for the wire
 * format shared with lib/platform/share_intake.dart). Items are emitted to the
 * Dart listener when one is attached, otherwise persisted in SharedPreferences
 * until Dart calls takePending.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "ShareIntake"
        private const val METHOD_CHANNEL = "rreview/share_intake"
        private const val EVENT_CHANNEL = "rreview/share_intake/events"
        private const val PREFS_NAME = "rreview_share_intake"
        private const val KEY_PENDING = "pending"
        private const val SOURCE = "android-intent"
        private const val IMPORTS_DIR = "imports"
        private const val MAX_FILE_BYTES = 5L * 1024L * 1024L
        private val PGN_MIME_TYPES = setOf("application/x-chess-pgn", "application/vnd.chess-pgn")
    }

    private var eventSink: EventChannel.EventSink? = null

    private val prefs: SharedPreferences
        get() = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "takePending" -> result.success(takePending())
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                if (events != null) {
                    // Flush anything that arrived before Dart started listening.
                    for (item in takePending()) {
                        events.success(item)
                    }
                }
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Only the first creation handles the launch intent; a re-creation
        // (rotation, process restore) would otherwise deliver the same share twice.
        if (savedInstanceState == null) {
            handleIntent(intent)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    // ---------------------------------------------------------------- intents

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        // Relaunch from the recents screen re-delivers the original intent.
        if ((intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return
        val items = itemsFrom(intent)
        if (items.isNotEmpty()) {
            deliver(items)
        }
    }

    private fun itemsFrom(intent: Intent): List<Map<String, Any>> {
        val items = ArrayList<Map<String, Any>>()
        when (intent.action) {
            Intent.ACTION_SEND -> {
                val stream = streamUri(intent)
                val fileItem = if (stream != null) fileItem(stream, intent.type) else null
                if (fileItem != null) {
                    items.add(fileItem)
                } else {
                    val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                    if (text != null) {
                        textItem(text)?.let { items.add(it) }
                    }
                }
            }
            Intent.ACTION_VIEW -> {
                val uri = intent.data
                if (uri != null) {
                    when (uri.scheme?.lowercase(Locale.ROOT)) {
                        "content", "file" -> fileItem(uri, intent.type)?.let { items.add(it) }
                        // "rreview" just brings the app to the front; nothing to import.
                    }
                }
            }
        }
        return items
    }

    @Suppress("DEPRECATION")
    private fun streamUri(intent: Intent): Uri? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        }
    }

    /** Text that is exactly one http(s) URL is reported as `url`, otherwise `text`. */
    private fun textItem(raw: String): Map<String, Any>? {
        val text = raw.trim()
        if (text.isEmpty()) return null
        val isUrl = text.none { it.isWhitespace() } && isHttpUrl(text)
        return makeItem(kind = if (isUrl) "url" else "text", value = text, fileName = null)
    }

    private fun isHttpUrl(text: String): Boolean {
        val uri = Uri.parse(text)
        val scheme = uri.scheme?.lowercase(Locale.ROOT) ?: return false
        return (scheme == "http" || scheme == "https") && !uri.host.isNullOrEmpty()
    }

    /** Copies an acceptable PGN/text file into filesDir/imports and describes it. */
    private fun fileItem(uri: Uri, intentType: String?): Map<String, Any>? {
        val mime = contentResolver.getType(uri) ?: intentType
        val name = displayName(uri) ?: "shared.pgn"
        val acceptable = name.lowercase(Locale.ROOT).endsWith(".pgn") ||
            (mime != null && (mime.startsWith("text/") || mime in PGN_MIME_TYPES))
        if (!acceptable) {
            Log.i(TAG, "Ignoring shared file $name ($mime)")
            return null
        }

        val id = UUID.randomUUID().toString()
        val directory = File(filesDir, IMPORTS_DIR)
        directory.mkdirs()
        val safeName = name.replace(Regex("[^A-Za-z0-9._-]"), "_")
        val destination = File(directory, "$id-$safeName")
        try {
            val input = contentResolver.openInputStream(uri) ?: return null
            input.use { source ->
                FileOutputStream(destination).use { sink ->
                    val buffer = ByteArray(64 * 1024)
                    var total = 0L
                    while (true) {
                        val read = source.read(buffer)
                        if (read < 0) break
                        total += read
                        if (total > MAX_FILE_BYTES) throw IOException("file larger than $MAX_FILE_BYTES bytes")
                        sink.write(buffer, 0, read)
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not import $uri: $e")
            destination.delete()
            return null
        }
        return makeItem(id = id, kind = "file", value = destination.absolutePath, fileName = name)
    }

    private fun displayName(uri: Uri): String? {
        if (uri.scheme == "content") {
            try {
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (index >= 0) {
                            val value = cursor.getString(index)
                            if (!value.isNullOrBlank()) return value
                        }
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "DISPLAY_NAME query failed for $uri: $e")
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/')?.takeIf { it.isNotBlank() }
    }

    // ------------------------------------------------------------ items/queue

    private fun makeItem(
        id: String = UUID.randomUUID().toString(),
        kind: String,
        value: String,
        fileName: String?,
    ): Map<String, Any> {
        val item = HashMap<String, Any>()
        item["id"] = id
        item["kind"] = kind
        item["value"] = value
        item["receivedAt"] = isoNow()
        item["source"] = SOURCE
        if (!fileName.isNullOrEmpty()) item["fileName"] = fileName
        return item
    }

    private fun isoNow(): String {
        val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        format.timeZone = TimeZone.getTimeZone("UTC")
        return format.format(Date())
    }

    /** Emits to the Dart listener when attached, otherwise persists for takePending. */
    private fun deliver(items: List<Map<String, Any>>) {
        val sink = eventSink
        if (sink != null) {
            for (item in items) sink.success(item)
        } else {
            storePending(items)
        }
    }

    private fun storePending(items: List<Map<String, Any>>) {
        val array = try {
            JSONArray(prefs.getString(KEY_PENDING, null) ?: "[]")
        } catch (e: Exception) {
            JSONArray()
        }
        for (item in items) array.put(JSONObject(item))
        prefs.edit().putString(KEY_PENDING, array.toString()).apply()
    }

    /** Returns and clears the persisted pending items. */
    private fun takePending(): List<Map<String, Any>> {
        val raw = prefs.getString(KEY_PENDING, null) ?: return emptyList()
        prefs.edit().remove(KEY_PENDING).apply()
        val result = ArrayList<Map<String, Any>>()
        try {
            val array = JSONArray(raw)
            for (i in 0 until array.length()) {
                val obj = array.getJSONObject(i)
                val map = HashMap<String, Any>()
                for (key in obj.keys()) {
                    map[key] = obj.get(key)
                }
                result.add(map)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Discarding unreadable pending list: $e")
        }
        return result
    }
}
