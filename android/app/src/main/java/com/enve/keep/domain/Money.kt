package com.enve.keep.domain

import java.math.BigDecimal
import java.text.DecimalFormatSymbols
import java.text.NumberFormat
import java.util.Currency
import java.util.Locale

object Money {
    /** Accepts either '.' or ',' as the decimal separator, with optional grouping. */
    fun parse(text: String, locale: Locale = Locale.getDefault()): BigDecimal? {
        val raw = text.filterNot { it.isWhitespace() || it == ' ' || it == '\'' }
        if (raw.isEmpty() || raw.any { !it.isDigit() && it != '.' && it != ',' }) return null
        val lastDot = raw.lastIndexOf('.')
        val lastComma = raw.lastIndexOf(',')
        val normalized = when {
            lastDot >= 0 && lastComma >= 0 ->
                if (lastDot > lastComma) raw.replace(",", "") else raw.replace(".", "").replace(',', '.')
            lastDot >= 0 || lastComma >= 0 -> {
                val separator = if (lastDot >= 0) '.' else ','
                val occurrences = raw.count { it == separator }
                val decimals = raw.length - raw.lastIndexOf(separator) - 1
                val localDecimal = DecimalFormatSymbols.getInstance(locale).decimalSeparator
                val isDecimal = occurrences == 1 && (separator == localDecimal || decimals != 3)
                if (isDecimal) raw.replace(separator, '.') else raw.replace(separator.toString(), "")
            }
            else -> raw
        }
        return normalized.toBigDecimalOrNull()?.takeIf { it.scale() <= 4 }
    }

    fun format(amount: BigDecimal, currencyCode: String, locale: Locale = Locale.getDefault()): String {
        val format = NumberFormat.getCurrencyInstance(locale)
        currency(currencyCode)?.let {
            format.currency = it
            format.maximumFractionDigits = maxOf(it.defaultFractionDigits, 0)
            format.minimumFractionDigits = maxOf(it.defaultFractionDigits, 0)
        }
        return format.format(amount)
    }

    fun formatForInput(amount: BigDecimal): String = amount.stripTrailingZeros().let {
        if (it.scale() < 0) it.setScale(0) else it
    }.toPlainString()

    fun currency(code: String): Currency? = runCatching { Currency.getInstance(code) }.getOrNull()

    val allCurrencies: List<Currency> by lazy {
        Currency.getAvailableCurrencies().sortedBy { it.currencyCode }
    }
}
