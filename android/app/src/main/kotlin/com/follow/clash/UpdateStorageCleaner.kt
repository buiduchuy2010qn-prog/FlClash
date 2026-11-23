package com.follow.clash

import android.app.DownloadManager
import android.content.Context
import android.os.Environment
import java.io.File

object UpdateStorageCleaner {
    private const val CLEANED_MARKER = "cleaned_update_apk_bytes"
    private const val UPDATE_DIR = "update"

    private fun dirSize(target: File): Long {
        if (!target.exists()) return 0L
        return runCatching {
            target.walkTopDown().filter { it.isFile }.sumOf { it.length() }
        }.getOrDefault(0L)
    }

    fun clean(context: Context): Long {
        val dirsToClean = buildList {
            context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)?.let { extDownloads ->
                add(File(extDownloads, UPDATE_DIR))
            }
            add(File(context.cacheDir, UPDATE_DIR))
        }
        val looseApks = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?.listFiles { file -> file.isFile && file.extension.equals("apk", ignoreCase = true) }
            ?.toList()
            .orEmpty()

        var freedBytes = 0L
        for (dir in dirsToClean) {
            freedBytes += dirSize(dir)
        }
        for (apk in looseApks) {
            freedBytes += runCatching { apk.length() }.getOrDefault(0L)
        }

        runCatching {
            val downloadManager = context.getSystemService(DownloadManager::class.java)
            val ids = downloadManager?.query(DownloadManager.Query())?.use { cursor ->
                val column = cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_ID)
                buildList { while (cursor.moveToNext()) add(cursor.getLong(column)) }
            }.orEmpty()
            if (ids.isNotEmpty()) {
                downloadManager?.remove(*ids.toLongArray())
            }
        }

        for (dir in dirsToClean) {
            runCatching { dir.deleteRecursively() }
        }
        for (apk in looseApks) {
            runCatching { apk.delete() }
        }
        return freedBytes
    }

    fun recordCleanedBytes(context: Context, bytes: Long) {
        if (bytes <= 0L) return
        runCatching {
            File(context.filesDir, CLEANED_MARKER).writeText(bytes.toString())
        }
    }

    fun consumeCleanedBytes(context: Context): Long {
        val marker = File(context.filesDir, CLEANED_MARKER)
        if (!marker.exists()) return 0L
        val value = runCatching { marker.readText().trim().toLong() }.getOrDefault(0L)
        runCatching { marker.delete() }
        return value
    }
}
