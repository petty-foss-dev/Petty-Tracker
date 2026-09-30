package com.enve.keep

import com.enve.keep.domain.Money
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.math.BigDecimal
import java.util.Locale

class MoneyTest {
    private fun parse(text: String, locale: Locale = Locale.US) = Money.parse(text, locale)

    @Test
    fun parsesCommonFormats() {
        assertEquals(BigDecimal("12.50"), parse("12.50"))
        assertEquals(BigDecimal("12.50"), parse("12,50"))
        assertEquals(BigDecimal("1234.56"), parse("1,234.56"))
        assertEquals(BigDecimal("1234.56"), parse("1.234,56"))
        assertEquals(BigDecimal("1234567"), parse("1.234.567"))
        assertEquals(BigDecimal("1500"), parse(" 1 500 "))
    }

    @Test
    fun ambiguousGroupingFollowsLocale() {
        assertEquals(BigDecimal("1234"), parse("1,234", Locale.US))
        assertEquals(BigDecimal("1.234"), parse("1,234", Locale.GERMANY))
    }

    @Test
    fun rejectsInvalidInput() {
        assertNull(parse(""))
        assertNull(parse("abc"))
        assertNull(parse("-5"))
        assertNull(parse("1.23456"))
    }
}
