package com.isaaclamb.pettytracker.ui.settings

import android.content.res.Resources
import com.isaaclamb.pettytracker.R
import com.isaaclamb.pettytracker.data.CycleUnit
import com.isaaclamb.pettytracker.domain.DeadlineStatus
import com.isaaclamb.pettytracker.domain.ExportText
import com.isaaclamb.pettytracker.domain.Money
import com.isaaclamb.pettytracker.domain.RecordKind
import java.math.BigDecimal

/** Export wording from the app's string resources. */
class ResourceExportText(private val resources: Resources) : ExportText {
    override fun warrantyEnds(name: String) = resources.getString(R.string.export_warranty_ends, name)
    override fun expires(title: String) = resources.getString(R.string.export_expires, title)
    override fun renews(name: String, price: String?) =
        if (price == null) resources.getString(R.string.export_renews, name) else resources.getString(R.string.export_renews_price, name, price)
    override fun serialNumber(value: String) = resources.getString(R.string.export_serial_number, value)
    override fun documentNumber(value: String) = resources.getString(R.string.export_document_number, value)
    override fun price(amount: BigDecimal, currency: String) = Money.format(amount, currency)
    override val canceled: String get() = resources.getString(R.string.filter_canceled)

    override fun cycle(count: Int, unit: CycleUnit): String = resources.getQuantityString(
        when (unit) {
            CycleUnit.DAYS -> R.plurals.cycle_days
            CycleUnit.WEEKS -> R.plurals.cycle_weeks
            CycleUnit.MONTHS -> R.plurals.cycle_months
            CycleUnit.YEARS -> R.plurals.cycle_years
        },
        count,
        count,
    )

    override fun type(kind: RecordKind): String = resources.getString(
        when (kind) {
            RecordKind.WARRANTY -> R.string.record_product
            RecordKind.SUBSCRIPTION -> R.string.kind_subscription
            RecordKind.DOCUMENT -> R.string.kind_document
        }
    )

    override fun status(status: DeadlineStatus, kind: RecordKind): String = resources.getString(
        when (status) {
            DeadlineStatus.NONE -> R.string.export_status_no_date
            DeadlineStatus.TODAY, DeadlineStatus.SOON -> R.string.export_status_due_soon
            DeadlineStatus.PAST -> when (kind) {
                RecordKind.WARRANTY -> R.string.section_ended
                RecordKind.SUBSCRIPTION -> R.string.export_status_overdue
                RecordKind.DOCUMENT -> R.string.filter_expired
            }
            DeadlineStatus.OK -> when (kind) {
                RecordKind.WARRANTY -> R.string.filter_covered
                RecordKind.SUBSCRIPTION -> R.string.filter_active
                RecordKind.DOCUMENT -> R.string.filter_valid
            }
        }
    )
}
