package com.writes.garage.core.domain

/**
 * The Pro accent themes, ids and colours from iOS `AccentScheme` (BrandPrimary / AccentGraphite / AccentMarine /
 * AccentPlum asset colours). [darkArgb]/[lightArgb] are the primary colour in each appearance; [CLASSIC] has none
 * because it is the app's own default accent.
 */
enum class AccentScheme(val id: String, val displayName: String, val lightArgb: Long?, val darkArgb: Long?) {
    CLASSIC("classic", "Classic", null, null),
    GRAPHITE("graphite", "Graphite", 0xFF384050, 0xFFAAB4C4),
    MARINE("marine", "Marine", 0xFF0D598C, 0xFF5AA9DE),
    PLUM("plum", "Plum", 0xFF6B3380, 0xFFC89AD8);

    companion object {
        /** Unknown / blank ids clear the choice (a bad stored value must never break the UI). */
        fun fromId(id: String?): AccentScheme? = entries.firstOrNull { it.id == id?.trim()?.lowercase() }
    }
}
