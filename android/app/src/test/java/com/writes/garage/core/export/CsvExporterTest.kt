package com.writes.garage.core.export

import com.writes.garage.TestFixtures.entry
import com.writes.garage.core.model.Entry
import com.writes.garage.core.model.EntryType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class CsvExporterTest {
    @Test
    fun headerMatchesTheIosRawSchemaAndIsCrlfTerminated() {
        val out = CsvExporter.export(emptyList())
        assertEquals(
            "schema_version,id,vehicleId,userId,entryType,entryDate,odometerReading,cost,isDiy,shopName,notes," +
                "attachmentPaths,isResolved,details,createdAt,updatedAt\r\n",
            out,
        )
    }

    @Test
    fun rfc4180Quoting() {
        assertEquals("plain", CsvExporter.escapeField("plain"))
        assertEquals("\"a,b\"", CsvExporter.escapeField("a,b"))
        assertEquals("\"say \"\"hi\"\"\"", CsvExporter.escapeField("say \"hi\""))
        assertEquals("\"line1\nline2\"", CsvExporter.escapeField("line1\nline2"))
        assertEquals("\"cr\rhere\"", CsvExporter.escapeField("cr\rhere"))
        assertEquals("", CsvExporter.escapeField(""))
    }

    @Test
    fun formulaInjectionIsNeutralised() {
        assertEquals("'=SUM(A1)", CsvExporter.safeFreeText("=SUM(A1)"))
        assertEquals("'+1", CsvExporter.safeFreeText("+1"))
        assertEquals("'-2", CsvExporter.safeFreeText("-2"))
        assertEquals("'@cmd", CsvExporter.safeFreeText("@cmd"))
        assertEquals("'  =x", CsvExporter.safeFreeText("  =x"))
        assertEquals("'\t=x", CsvExporter.safeFreeText("\t=x"))
        assertEquals("normal -text", CsvExporter.safeFreeText("normal -text"))
        assertEquals("", CsvExporter.safeFreeText(""))
    }

    @Test
    fun fullRowIncludingQuotedNotesAndSortedDetails() {
        val e = Entry(
            id = "e1", vehicleId = "v1", userId = "u1", entryType = EntryType.OIL_CHANGE,
            entryDate = Instant.parse("2026-03-03T10:15:30.987Z"), odometerReading = 42_180, cost = 89.95, isDiy = false,
            shopName = "Joe's, Inc.", notes = "Used \"Mobil 1\"\nand a filter", attachmentPaths = listOf("p/a.jpg", "p/b.pdf"),
            isResolved = null, details = mapOf("oilGrade" to "5W-30", "quantityQuarts" to 5.5, "brand" to "Mobil 1", "flag" to true),
            createdAt = Instant.parse("2026-03-03T10:16:00Z"), updatedAt = null,
        )
        val row = CsvExporter.row(e)
        assertEquals(
            "2,e1,v1,u1,oil_change,2026-03-03T10:15:30Z,42180,89.95,false,\"Joe's, Inc.\"," +
                "\"Used \"\"Mobil 1\"\"\nand a filter\",p/a.jpg|p/b.pdf,," +
                "\"{\"\"brand\"\":\"\"Mobil 1\"\",\"\"flag\"\":true,\"\"oilGrade\"\":\"\"5W-30\"\",\"\"quantityQuarts\"\":5.5}\"," +
                "2026-03-03T10:16:00Z,",
            row,
        )
    }

    @Test
    fun nullableFieldsAreEmptyAndEmptyDetailsAreBraces() {
        val row = CsvExporter.row(entry("e2", EntryType.FUEL, odo = 100))
        val fields = row.split(",")
        assertEquals("fuel", fields[4])
        assertEquals("100", fields[6])
        assertEquals("", fields[7]) // cost
        assertEquals("", fields[8]) // isDiy
        assertTrue(row.contains(",{},"))
    }

    @Test
    fun exportJoinsRowsWithCrlf() {
        val out = CsvExporter.export(listOf(entry("a"), entry("b")))
        val lines = out.split("\r\n")
        assertEquals(4, lines.size) // header, 2 rows, trailing empty after final CRLF
        assertEquals("", lines.last())
    }

    // ---- T14

    private fun rowOf(e: Entry) = CsvExporter.row(e)

    @Test
    fun attachmentPathsAreNeutralisedIndividually() {
        val row = rowOf(entry("e").copy(attachmentPaths = listOf("=cmd|x", "ok", "+evil")))
        // The apostrophe guards each path on its own, and '|' joins them (the field itself has no comma/quote).
        assertTrue(row, row.contains("'=cmd|x|ok|'+evil"))
    }

    @Test
    fun aPipeInsideAPathIsKeptVerbatim() {
        val row = rowOf(entry("e").copy(attachmentPaths = listOf("a|b.jpg", "c.pdf")))
        assertTrue(row.contains("a|b.jpg|c.pdf"))
    }

    @Test
    fun negativeNumbersStayRawAndAreNotApostrophePrefixed() {
        val e = entry("e", cost = -5.0, odo = 10)
        val fields = rowOf(e).split(",")
        assertEquals("-5.0", fields[7])
        assertEquals("-12.5", rowOf(entry("e2", cost = -12.5)).split(",")[7])
    }

    @Test
    fun notesAndShopStartingWithAFormulaCharacterArePrefixedInTheFullRow() {
        val row = rowOf(entry("e", shop = "=SUM(A1)", notes = "@cmd"))
        val fields = row.split(",")
        assertEquals("'=SUM(A1)", fields[9])
        assertEquals("'@cmd", fields[10])
    }

    @Test
    fun costsNeverUseExponentNotation() {
        assertEquals("10000000.0", rowOf(entry("e", cost = 1.0E7)).split(",")[7])
        assertEquals("0.0005", rowOf(entry("e", cost = 5.0E-4)).split(",")[7])
        assertEquals("89.95", rowOf(entry("e", cost = 89.95)).split(",")[7])
        assertEquals("100.0", rowOf(entry("e", cost = 100.0)).split(",")[7])
        assertEquals("0.0", rowOf(entry("e", cost = 0.0)).split(",")[7])
        assertEquals("123456789012.5", rowOf(entry("e", cost = 123456789012.5)).split(",")[7])
    }

    @Test
    fun numbersInsideTheDetailsJsonUsePlainDecimalsToo() {
        val json = CsvExporter.detailsJson(mapOf("big" to 1.0E7, "tiny" to 5.0E-4, "int" to 5, "long" to 10_000_000_000L, "f" to 2.5f, "nested" to mapOf("x" to 3.0E8)))
        assertEquals("""{"big":10000000.0,"f":2.5,"int":5,"long":10000000000,"nested":{"x":300000000.0},"tiny":0.0005}""", json)
    }

    @Test
    fun nonFiniteNumbersDoNotCrashTheExport() {
        assertEquals("NaN", CsvExporter.plainNumber(Double.NaN))
        assertEquals("Infinity", CsvExporter.plainNumber(Double.POSITIVE_INFINITY))
        // JSON has no NaN literal; it is exported as the string "NaN" rather than throwing.
        val json = CsvExporter.detailsJson(mapOf("bad" to Double.NaN))
        assertTrue(json, json.contains("NaN"))
    }
}
