package com.writes.garage.core.domain

import com.writes.garage.core.data.MediaFolder
import com.writes.garage.core.data.firebase.BoundedRead
import com.writes.garage.core.data.firebase.StoragePaths
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.InputStream

class AttachmentsAndPathsTest {
    @Test
    fun kindComesFromTheExtensionOrMime() {
        assertEquals(AttachmentKind.PDF, AttachmentKind.fromPath("users/u/entry-attachments/v/e/abc.pdf"))
        assertEquals(AttachmentKind.PDF, AttachmentKind.fromPath("X.PDF"))
        assertEquals(AttachmentKind.IMAGE, AttachmentKind.fromPath("a.jpg"))
        assertEquals(AttachmentKind.IMAGE, AttachmentKind.fromPath("a.pdf.jpg"))
        assertEquals(AttachmentKind.IMAGE, AttachmentKind.fromPath("no-extension"))
        assertEquals(AttachmentKind.PDF, AttachmentKind.fromMime("application/pdf"))
        assertEquals(AttachmentKind.IMAGE, AttachmentKind.fromMime("image/png"))
    }

    @Test
    fun attachmentRulesCapTheCountAndTheMimeTypes() {
        assertTrue(AttachmentRules.canAddMore(0, 0))
        assertTrue(AttachmentRules.canAddMore(5, 4))
        assertFalse(AttachmentRules.canAddMore(5, 5))
        assertFalse(AttachmentRules.canAddMore(10, 0))
        assertFalse(AttachmentRules.canAddMore(0, 11))
        assertTrue(AttachmentRules.isAllowedMime("application/pdf"))
        assertTrue(AttachmentRules.isAllowedMime("image/jpeg"))
        assertTrue(AttachmentRules.isAllowedMime("image/heic"))
        assertFalse(AttachmentRules.isAllowedMime("image/"))
        assertFalse(AttachmentRules.isAllowedMime("text/plain"))
        assertFalse(AttachmentRules.isAllowedMime("application/x-msdownload"))
        assertFalse(AttachmentRules.isAllowedMime(""))
    }

    @Test
    fun mediaPathsPutTheOwnerFolderOnlyWhereIosDoes() {
        assertEquals("users/u/vehicles/v/gallery/f.jpg", StoragePaths.media("u", "v", MediaFolder.GALLERY, null, "f.jpg"))
        assertEquals("a gallery photo ignores any owner id", "users/u/vehicles/v/gallery/f.jpg", StoragePaths.media("u", "v", MediaFolder.GALLERY, "p1", "f.jpg"))
        assertEquals("users/u/vehicles/v/photos/p1/f.jpg", StoragePaths.media("u", "v", MediaFolder.PHOTOS, "p1", "f.jpg"))
        assertEquals("users/u/vehicles/v/receipts/p1/f.pdf", StoragePaths.media("u", "v", MediaFolder.RECEIPTS, "p1", "f.pdf"))
        assertEquals("users/u/vehicles/v/photos/f.jpg", StoragePaths.media("u", "v", MediaFolder.PHOTOS, null, "f.jpg"))
    }

    @Test
    fun extensionsFollowTheContentTypeCaseInsensitively() {
        assertEquals("pdf", StoragePaths.extensionFor("APPLICATION/PDF"))
        assertEquals("png", StoragePaths.extensionFor("image/PNG"))
        assertEquals("webp", StoragePaths.extensionFor("image/webp"))
        assertEquals("heic", StoragePaths.extensionFor("image/heic"))
        assertEquals("jpg", StoragePaths.extensionFor("image/gif"))
    }

    // ---- BoundedRead

    @Test
    fun readBoundedReturnsExactlyWhatWasThereUpToTheLimit() {
        val data = ByteArray(40_000) { (it % 251).toByte() } // bigger than the 16 KiB read buffer
        assertArrayEquals(data, BoundedRead.readBounded(ByteArrayInputStream(data), 40_000))
        assertEquals(0, BoundedRead.readBounded(ByteArrayInputStream(ByteArray(0)), 10).size)
        assertThrows(BoundedRead.TooLargeException::class.java) { BoundedRead.readBounded(ByteArrayInputStream(data), 39_999) }
    }

    @Test
    fun readBoundedStopsReadingOnceTheStreamProvesTooBigEvenWithoutALength() {
        // A provider that reports no length and never ends: the cap must trip long before memory does.
        var served = 0L
        val endless = object : InputStream() {
            override fun read(): Int = 1
            override fun read(b: ByteArray, off: Int, len: Int): Int { served += len; return len }
        }
        val e = assertThrows(BoundedRead.TooLargeException::class.java) { BoundedRead.readBounded(endless, 100_000) }
        assertEquals(100_000, e.limit)
        assertTrue("read ${served} bytes", served < 100_000 + 2 * 16 * 1024)
        assertTrue(e.message!!.contains("MB"))
    }

    @Test
    fun sampleSizeKeepsBothEdgesAtOrAboveTheTarget() {
        assertEquals(1, BoundedRead.sampleSize(800, 600, 1000))
        assertEquals(1, BoundedRead.sampleSize(1000, 1000, 1000))
        assertEquals(2, BoundedRead.sampleSize(4000, 3000, 2000)) // 4000/2 = 2000 still >= target
        assertEquals(4, BoundedRead.sampleSize(4000, 3000, 1000))
        assertEquals(1, BoundedRead.sampleSize(1999, 1999, 1000))
        assertEquals(2, BoundedRead.sampleSize(2000, 500, 1000))
        assertEquals(1, BoundedRead.sampleSize(0, 0, 1000))
    }
}
