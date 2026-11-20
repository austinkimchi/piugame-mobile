package com.austinkimchi.mypiu.ui

import com.austinkimchi.mypiu.R
import com.austinkimchi.mypiu.core.model.PiuGameVersion
import java.io.File
import java.security.MessageDigest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PerformanceResultArtworkTest {
    @Test
    fun gradeAliasesFailedArtworkAndSmallPlateCodesResolveToVerifiedResources() {
        val normal = resultArtwork(" AAA+ ", "s_rg", PiuGameVersion.PHOENIX_2)
        assertEquals(R.drawable.piu_phoenix2_grade_aaa_p, normal.grade?.resourceId)
        assertEquals("Grade AAA+", normal.grade?.label)
        assertEquals(R.drawable.piu_phoenix2_plate_rg, normal.plate?.resourceId)
        assertEquals("Plate RG", normal.plate?.label)
        val failed = resultArtwork("X_AAA_P", "fg", PiuGameVersion.PHOENIX)
        assertEquals(R.drawable.piu_phoenix_grade_x_aaa_p, failed.grade?.resourceId)
        assertEquals("Failed grade AAA+", failed.grade?.label)
        assertEquals(R.drawable.piu_phoenix_plate_fg, failed.plate?.resourceId)
    }

    @Test
    fun unknownVersionOrCodeUsesTextWithoutInventingAnImage() {
        val noVersion = resultArtwork("aaa", "rg", null)
        assertNull(noVersion.grade?.resourceId)
        assertNull(noVersion.plate?.resourceId)
        assertEquals("AAA", noVersion.grade?.text)
        assertEquals("RG", noVersion.plate?.text)
        val unknown = resultArtwork("new_grade", "new_plate", PiuGameVersion.PHOENIX_2)
        assertNull(unknown.grade?.resourceId)
        assertNull(unknown.plate?.resourceId)
        assertEquals("NEW GRADE", unknown.grade?.text)
        assertEquals("NEW_PLATE", unknown.plate?.text)
    }

    @Test
    fun missingResultsAndStageBreakDoNotFabricateSuccessBadges() {
        val missing = resultArtwork(null, " ", PiuGameVersion.PHOENIX_2)
        assertEquals("Played; grade unavailable", missing.grade?.label)
        assertNull(missing.grade?.resourceId)
        assertNull(missing.plate)
        val interrupted = resultArtwork("sss_p", "pg", PiuGameVersion.PHOENIX_2, stageBreak = true)
        assertEquals("Stage Break", interrupted.grade?.text)
        assertEquals("Stage Break", interrupted.grade?.label)
        assertNull(interrupted.grade?.resourceId)
        assertNull(interrupted.plate)
    }

    @Test
    fun bothVersionsHaveSeparateCompleteKnownResultSets() {
        val grades = listOf("sss_p", "sss", "ss_p", "ss", "s_p", "s", "aaa_p", "aaa", "aa_p", "aa", "a_p", "a", "b", "c", "d", "f")
        val plates = listOf("pg", "ug", "eg", "sg", "mg", "tg", "fg", "rg")
        val ids = mutableSetOf<Int>()
        for (version in PiuGameVersion.entries) {
            for (grade in grades.flatMap { listOf(it, "x_$it") }) {
                val id = resultArtwork(grade, null, version).grade?.resourceId
                assertNotNull("$version/$grade", id)
                assertTrue(ids.add(requireNotNull(id)))
            }
            for (plate in plates) {
                val id = resultArtwork(null, plate, version).plate?.resourceId
                assertNotNull("$version/$plate", id)
                assertTrue(ids.add(requireNotNull(id)))
            }
        }
        assertEquals(80, ids.size)
    }

    @Test
    fun bundledOriginalsMatchTheirRecordedOfficialProvenance() {
        val androidRoot = File("..").canonicalFile
        val manifest = Json.parseToJsonElement(File(androidRoot, "piu-result-artwork-manifest.json").readText()).jsonObject
        val assets = manifest.getValue("assets").jsonArray
        assertEquals(80, assets.size)
        val paths = mutableSetOf<String>()
        for (entry in assets) {
            val asset = entry.jsonObject
            val path = asset.getValue("androidPath").jsonPrimitive.content
            assertTrue(paths.add(path))
            val bytes = File(androidRoot, path).readBytes()
            val sha = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
            assertEquals(path, asset.getValue("sha256").jsonPrimitive.content, sha)
            assertEquals(path, asset.getValue("bytes").jsonPrimitive.content.toInt(), bytes.size)
            assertTrue(asset.getValue("sourceUrl").jsonPrimitive.content.startsWith("https://piugame.com/"))
            assertFalse(path.contains(".."))
        }
    }
}
