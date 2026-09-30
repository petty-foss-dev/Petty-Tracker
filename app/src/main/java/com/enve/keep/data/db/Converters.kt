package com.enve.keep.data.db

import androidx.room.TypeConverter
import java.math.BigDecimal
import java.time.LocalDate

class Converters {
    @TypeConverter fun fromDate(value: LocalDate?): Long? = value?.toEpochDay()
    @TypeConverter fun toDate(value: Long?): LocalDate? = value?.let(LocalDate::ofEpochDay)
    @TypeConverter fun fromDecimal(value: BigDecimal?): String? = value?.toPlainString()
    @TypeConverter fun toDecimal(value: String?): BigDecimal? = value?.let(::BigDecimal)
}
