package com.writes.garage.core.data.firebase

import java.io.ByteArrayOutputStream
import java.io.InputStream

/** Pure helpers that keep untrusted content URIs from exhausting memory. */
object BoundedRead {
    class TooLargeException(val limit: Int) : Exception("That file is larger than ${limit / (1024 * 1024)} MB.")

    /** Reads at most [limit] bytes; fails as soon as the stream proves to be bigger (works when the length is unknown). */
    fun readBounded(input: InputStream, limit: Int): ByteArray {
        val out = ByteArrayOutputStream(minOf(limit, 64 * 1024))
        val buf = ByteArray(16 * 1024)
        var total = 0
        while (true) {
            val n = input.read(buf)
            if (n < 0) break
            total += n
            if (total > limit) throw TooLargeException(limit)
            out.write(buf, 0, n)
        }
        return out.toByteArray()
    }

    /** Power-of-two `inSampleSize` that keeps both edges at or above [maxEdge] (decode close to, not below, the target). */
    fun sampleSize(width: Int, height: Int, maxEdge: Int): Int {
        var sample = 1
        while (width / (sample * 2) >= maxEdge || height / (sample * 2) >= maxEdge) sample *= 2
        return sample
    }
}
