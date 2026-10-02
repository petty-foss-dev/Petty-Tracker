package com.isaaclamb.pettytracker

import com.isaaclamb.pettytracker.domain.normalizeProductUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ProductPagesTest {
    @Test
    fun acceptsBareAddressesAndFullLinks() {
        assertEquals("https://example.com/desk", normalizeProductUrl("  example.com/desk "))
        assertEquals("http://shop.test/item?id=4", normalizeProductUrl("http://shop.test/item?id=4"))
        assertEquals("", normalizeProductUrl("   "))
    }

    @Test
    fun rejectsTextThatIsNotAWebAddress() {
        assertNull(normalizeProductUrl("ftp://example.com/file"))
        assertNull(normalizeProductUrl("not a link"))
    }
}
