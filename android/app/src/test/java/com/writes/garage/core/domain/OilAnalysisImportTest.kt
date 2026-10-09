package com.writes.garage.core.domain

import com.writes.garage.feature.entry.EntryFieldSpecs
import com.writes.garage.core.model.EntryType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class OilAnalysisImportTest {
    @Test
    fun everyImportKeyIsAFieldOfTheOilAnalysisForm() {
        val fields = EntryFieldSpecs.forType(EntryType.OIL_ANALYSIS).fields.map { it.key }.toSet()
        assertTrue("import keys missing from the form: ${OilAnalysisImport.FIELD_KEYS - fields}", fields.containsAll(OilAnalysisImport.FIELD_KEYS))
    }

    @Test
    fun prefillFormatsNumbersAndKeepsZeroReadings() {
        val p = OilAnalysisImport.prefill(
            mapOf(
                "labName" to " Blackstone ", "iron" to 12.0, "copper" to 0, "aluminum" to 3.25, "milesOnOil" to 5_400.0,
                "viscosity" to "13.4 cSt", "lead" to null, "tin" to "", "unknownKey" to 5, "silver" to -1.0,
            ),
        )
        assertEquals("Blackstone", p["labName"])
        assertEquals("12", p["iron"])
        assertEquals("0", p["copper"]) // a printed 0 is a real measurement
        assertEquals("3.25", p["aluminum"])
        assertEquals("5400", p["milesOnOil"])
        assertEquals("13.4 cSt", p["viscosity"])
        assertNull(p["lead"])
        assertNull(p["tin"])
        assertNull(p["unknownKey"])
        assertNull(p["silver"]) // nonsense negative reading
    }

    @Test
    fun aRecommendationAloneIsNotAnAnalysis() {
        assertFalse(OilAnalysisImport.isUsable(OilAnalysisImport.prefill(mapOf("labRecommendation" to "Change oil"))))
        assertTrue(OilAnalysisImport.isUsable(OilAnalysisImport.prefill(mapOf("labName" to "Lab"))))
        assertFalse(OilAnalysisImport.isUsable(OilAnalysisImport.prefill(emptyMap())))
    }
}
