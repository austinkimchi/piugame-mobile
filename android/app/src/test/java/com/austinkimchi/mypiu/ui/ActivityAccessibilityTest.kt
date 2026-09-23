package com.austinkimchi.mypiu.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ActivityAccessibilityTest {
    @Test
    fun chartTokensExpandIntoSpokenLabels() {
        assertEquals("Single level 19", performanceChartTokenAccessibilityLabel("S19"))
        assertEquals("Double level 24", performanceChartTokenAccessibilityLabel("d24"))
        assertEquals("Co-op level 2", performanceChartTokenAccessibilityLabel("C2"))
        assertEquals("Single level 20 plus", performanceChartTokenAccessibilityLabel("S20+"))
        assertEquals("half-double:18", performanceChartTokenAccessibilityLabel("half-double:18"))
    }

    @Test
    fun failedPlaysAreIdentifiedByStageBreakOrFailedGrade() {
        assertTrue(performancePlayIsFailed(grade = "x_AA", stageBreak = false))
        assertTrue(performancePlayIsFailed(grade = "S", stageBreak = true))
        assertFalse(performancePlayIsFailed(grade = "S", stageBreak = false))
    }
}
