package com.writes.garage.core.data

import java.io.File

/**
 * Removes the signed-out/deleted account's data from this device: the Firestore offline cache, shared exports and
 * receipt captures, the active-vehicle preference and the persisted reminder alarm plan.
 */
interface LocalDataWiper {
    suspend fun wipe()

    /** true when the wipe leaves the Firestore instance terminated, so the process must be relaunched. */
    val needsRestart: Boolean get() = false
}

object NoopLocalDataWiper : LocalDataWiper {
    override suspend fun wipe() = Unit
}

/** Pure file helpers (unit-testable on the JVM). */
object LocalFiles {
    /** Deletes everything inside [dir] (not [dir] itself). Returns how many files were removed; missing dir = 0. */
    fun clearDirectory(dir: File): Int {
        val children = dir.listFiles() ?: return 0
        var removed = 0
        for (f in children) {
            if (f.isDirectory) removed += clearDirectory(f)
            if (f.delete()) removed++
        }
        return removed
    }

    /** Deletes one file by name inside [dir], refusing path separators so a crafted uri can't escape it. */
    fun deleteNamed(dir: File, name: String?): Boolean {
        if (name.isNullOrBlank() || name.contains('/') || name.contains('\\') || name == "." || name == "..") return false
        return File(dir, name).takeIf { it.isFile }?.delete() == true
    }
}
