package com.writes.garage.core.data

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.ExifInterface
import com.writes.garage.core.data.firebase.ImageReencoder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.GraphicsMode
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ImageReencoderTest {
    /** A real JPEG, optionally carrying an EXIF orientation and a GPS position. */
    private fun jpeg(width: Int, height: Int, orientation: Int? = null, gps: Boolean = false): ByteArray {
        val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val raw = ByteArrayOutputStream().also { bmp.compress(Bitmap.CompressFormat.JPEG, 90, it) }.toByteArray()
        if (orientation == null && !gps) return raw
        val f = File.createTempFile("exif", ".jpg").apply { writeBytes(raw); deleteOnExit() }
        ExifInterface(f.absolutePath).apply {
            if (orientation != null) setAttribute(ExifInterface.TAG_ORIENTATION, orientation.toString())
            if (gps) {
                setAttribute(ExifInterface.TAG_GPS_LATITUDE, "37/1,46/1,30/1")
                setAttribute(ExifInterface.TAG_GPS_LATITUDE_REF, "N")
                setAttribute(ExifInterface.TAG_GPS_LONGITUDE, "122/1,25/1,10/1")
                setAttribute(ExifInterface.TAG_GPS_LONGITUDE_REF, "W")
            }
            saveAttributes()
        }
        return f.readBytes()
    }

    private fun size(bytes: ByteArray): Pair<Int, Int> {
        val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, o)
        return o.outWidth to o.outHeight
    }

    @Test
    fun outputIsAJpegWithTheSameDimensionsWhenSmallEnough() {
        val out = ImageReencoder.reencodeJpeg(jpeg(400, 300), 2560, 85)
        assertEquals(0xFF, out[0].toInt() and 0xFF)
        assertEquals(0xD8, out[1].toInt() and 0xFF)
        assertEquals(400 to 300, size(out))
    }

    @Test
    fun largeImagesAreDownscaledSoTheLongEdgeIsCapped() {
        val out = ImageReencoder.reencodeJpeg(jpeg(4000, 1000), 1000, 85)
        val (w, h) = size(out)
        assertTrue("long edge $w must be <= 1000", w <= 1000 && h <= 1000)
        assertTrue("aspect ratio kept (4:1), got ${w}x$h", Math.abs(w.toDouble() / h - 4.0) < 0.1)
    }

    @Test
    fun exifRotate90IsBakedIntoThePixels() {
        val out = ImageReencoder.reencodeJpeg(jpeg(400, 200, orientation = ExifInterface.ORIENTATION_ROTATE_90), 2560, 85)
        assertEquals("a landscape photo tagged ROTATE_90 comes out portrait", 200 to 400, size(out))
    }

    @Test
    fun exifRotate180KeepsTheDimensions() {
        val out = ImageReencoder.reencodeJpeg(jpeg(400, 200, orientation = ExifInterface.ORIENTATION_ROTATE_180), 2560, 85)
        assertEquals(400 to 200, size(out))
    }

    @Test
    fun gpsAndOrientationMetadataAreStrippedFromTheOutput() {
        val src = jpeg(300, 200, orientation = ExifInterface.ORIENTATION_ROTATE_90, gps = true)
        // Sanity: the fixture really carries the GPS tag.
        assertTrue(ExifInterface(ByteArrayInputStream(src)).getAttribute(ExifInterface.TAG_GPS_LATITUDE) != null)
        val out = ImageReencoder.reencodeJpeg(src, 2560, 85)
        val exif = ExifInterface(ByteArrayInputStream(out))
        assertNull("GPS position must not survive re-encoding", exif.getAttribute(ExifInterface.TAG_GPS_LONGITUDE))
        assertNull(exif.getAttribute(ExifInterface.TAG_GPS_LATITUDE))
        val orientation = exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        assertTrue("orientation must be normal/undefined after baking, was $orientation", orientation == ExifInterface.ORIENTATION_NORMAL || orientation == ExifInterface.ORIENTATION_UNDEFINED)
    }

    @Test
    fun undecodableBytesAreRejectedWithAFriendlyError() {
        try {
            ImageReencoder.reencodeJpeg(byteArrayOf(1, 2, 3, 4), 2560, 85)
            fail("expected IllegalArgumentException")
        } catch (e: IllegalArgumentException) {
            assertEquals("That image couldn't be read.", e.message)
        }
    }
}
