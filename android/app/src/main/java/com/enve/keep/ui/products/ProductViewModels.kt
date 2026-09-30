@file:UseSerializers(LocalDateSerializer::class)

package com.enve.keep.ui.products

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.navigation.toRoute
import com.enve.keep.KeepApplication
import com.enve.keep.data.Attachment
import com.enve.keep.data.LocalDateSerializer
import com.enve.keep.data.OwnerType
import com.enve.keep.data.Product
import com.enve.keep.domain.DeadlineStatus
import com.enve.keep.domain.Money
import com.enve.keep.domain.deadlineSortKey
import com.enve.keep.domain.deadlineStatus
import com.enve.keep.domain.sortRank
import com.enve.keep.domain.matches
import com.enve.keep.ui.AttachmentDraft
import com.enve.keep.ui.AttachmentFormViewModel
import com.enve.keep.ui.ProductDetailRoute
import com.enve.keep.ui.ProductEditRoute
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers
import java.time.LocalDate

enum class ProductFilter { ALL, COVERED, ENDING, EXPIRED }

data class ProductItem(val product: Product, val status: DeadlineStatus)

data class ProductListState(
    val loaded: Boolean = false,
    val hasAny: Boolean = false,
    val items: List<ProductItem> = emptyList(),
)

class ProductListViewModel(app: KeepApplication) : ViewModel() {
    val query = MutableStateFlow("")
    val filter = MutableStateFlow(ProductFilter.ALL)

    val state: StateFlow<ProductListState> = combine(
        app.container.repository.products,
        app.container.settingsRepository.settings,
        query,
        filter,
    ) { products, settings, query, filter ->
        val today = LocalDate.now()
        val items = products
            .filter { it.matches(query) }
            .map { ProductItem(it, deadlineStatus(it.warrantyExpires, today, settings.warrantyLeadDays)) }
            .filter {
                when (filter) {
                    ProductFilter.ALL -> true
                    ProductFilter.COVERED -> it.status in setOf(DeadlineStatus.OK, DeadlineStatus.SOON, DeadlineStatus.TODAY)
                    ProductFilter.ENDING -> it.status == DeadlineStatus.SOON || it.status == DeadlineStatus.TODAY
                    ProductFilter.EXPIRED -> it.status == DeadlineStatus.PAST
                }
            }
            .sortedWith(compareBy({ it.status.sortRank }, { deadlineSortKey(it.product.warrantyExpires, it.status) }))
        ProductListState(loaded = true, hasAny = products.isNotEmpty(), items = items)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), ProductListState())
}

data class ProductDetailState(
    val loaded: Boolean = false,
    val product: Product? = null,
    val attachments: List<Attachment> = emptyList(),
    val leadDays: Int = 0,
)

class ProductDetailViewModel(private val app: KeepApplication, handle: SavedStateHandle) : ViewModel() {
    private val id = handle.toRoute<ProductDetailRoute>().id
    val attachmentStore = app.container.attachmentStore

    val state: StateFlow<ProductDetailState> = combine(
        app.container.repository.product(id),
        app.container.repository.attachments(OwnerType.PRODUCT, id),
        app.container.settingsRepository.settings,
    ) { product, attachments, settings ->
        ProductDetailState(true, product, attachments, settings.warrantyLeadDays)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), ProductDetailState())

    fun delete() {
        viewModelScope.launch { app.container.repository.deleteProduct(id) }
    }
}

@Serializable
data class ProductForm(
    val loaded: Boolean = false,
    val changed: Boolean = false,
    val showErrors: Boolean = false,
    val name: String = "",
    val brand: String = "",
    val model: String = "",
    val serialNumber: String = "",
    val purchaseDate: LocalDate? = null,
    val retailer: String = "",
    val price: String = "",
    val currency: String = "",
    val warrantyExpires: LocalDate? = null,
    val notes: String = "",
    val attachments: AttachmentDraft = AttachmentDraft(),
) {
    val nameError get() = showErrors && name.isBlank()
    val priceError get() = showErrors && price.isNotBlank() && Money.parse(price) == null
    val warrantyBeforePurchase get() =
        purchaseDate != null && warrantyExpires != null && warrantyExpires.isBefore(purchaseDate)
}

class ProductEditViewModel(private val app: KeepApplication, handle: SavedStateHandle) :
    AttachmentFormViewModel<ProductForm>(
        handle,
        ProductForm.serializer(),
        ProductForm(),
        app.container.attachmentStore,
        OwnerType.PRODUCT,
    ) {
    val id = handle.toRoute<ProductEditRoute>().id
    private var saving = false

    override fun ProductForm.draft() = attachments
    override fun ProductForm.withDraft(draft: AttachmentDraft) = copy(attachments = draft, changed = true)

    init {
        if (!restored) viewModelScope.launch {
            val repository = app.container.repository
            val product = if (id != 0L) repository.product(id).first() else null
            if (product == null) {
                val currency = app.container.settingsRepository.current().defaultCurrency
                update { it.copy(loaded = true, currency = currency) }
            } else {
                val attachments = repository.attachments(OwnerType.PRODUCT, id).first()
                update {
                    ProductForm(
                        loaded = true,
                        name = product.name,
                        brand = product.brand,
                        model = product.model,
                        serialNumber = product.serialNumber,
                        purchaseDate = product.purchaseDate,
                        retailer = product.retailer,
                        price = product.price?.let(Money::formatForInput).orEmpty(),
                        currency = product.currency,
                        warrantyExpires = product.warrantyExpires,
                        notes = product.notes,
                        attachments = AttachmentDraft(current = attachments),
                    )
                }
            }
        }
    }

    fun edit(transform: (ProductForm) -> ProductForm) = update { transform(it).copy(changed = true) }

    fun setWarrantyYears(years: Long) = edit {
        it.copy(warrantyExpires = (it.purchaseDate ?: LocalDate.now()).plusYears(years))
    }

    fun save(onSaved: (id: Long, isNew: Boolean) -> Unit) {
        val form = form
        val price = form.price.takeIf { it.isNotBlank() }?.let(Money::parse)
        val invalid = form.name.isBlank() ||
            (form.price.isNotBlank() && price == null) ||
            Money.currency(form.currency) == null
        if (invalid) {
            update { it.copy(showErrors = true) }
            return
        }
        if (saving) return
        saving = true
        viewModelScope.launch {
            val product = Product(
                id = id,
                name = form.name.trim(),
                brand = form.brand.trim(),
                model = form.model.trim(),
                serialNumber = form.serialNumber.trim(),
                purchaseDate = form.purchaseDate,
                retailer = form.retailer.trim(),
                price = price,
                currency = form.currency,
                warrantyExpires = form.warrantyExpires,
                notes = form.notes.trim(),
            )
            val savedId = app.container.repository.saveProduct(product, form.attachments.added, form.attachments.removed)
            saved = true
            onSaved(savedId, id == 0L)
        }
    }
}
