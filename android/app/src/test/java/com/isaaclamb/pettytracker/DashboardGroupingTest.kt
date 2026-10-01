package com.isaaclamb.pettytracker

import com.isaaclamb.pettytracker.domain.DeadlineStatus
import com.isaaclamb.pettytracker.ui.components.StatusSection
import com.isaaclamb.pettytracker.ui.dashboard.DashboardBand
import org.junit.Assert.assertEquals
import org.junit.Test

class DashboardGroupingTest {
    @Test
    fun bandsFollowHowSoonADateFalls() {
        assertEquals(DashboardBand.WEEK, DashboardBand.of(0))
        assertEquals(DashboardBand.WEEK, DashboardBand.of(7))
        assertEquals(DashboardBand.MONTH, DashboardBand.of(8))
        assertEquals(DashboardBand.MONTH, DashboardBand.of(30))
        assertEquals(DashboardBand.LATER, DashboardBand.of(31))
    }

    @Test
    fun sectionsKeepReadingOrderAndSkipEmptyOnes() {
        val items = listOf(DeadlineStatus.PAST, DeadlineStatus.OK, DeadlineStatus.TODAY, DeadlineStatus.SOON)
        val sections = StatusSection.group(items) { it }
        assertEquals(listOf(StatusSection.SOON, StatusSection.OK, StatusSection.PAST), sections.map { it.first })
        assertEquals(listOf(DeadlineStatus.TODAY, DeadlineStatus.SOON), sections.first().second)
    }
}
