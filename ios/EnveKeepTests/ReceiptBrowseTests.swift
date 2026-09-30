import Foundation
import Testing
@testable import EnveKeep

struct ReceiptBrowseTests {
    private func receipt(
        _ id: Int64, _ merchant: String, _ date: String, total: String?, currency: String = "USD", category: String = "",
        from origin: String = "", to destination: String = "", address: String = "", fields: [ReceiptField] = []
    ) -> Receipt {
        var receipt = Receipt(id: id, merchant: merchant, purchaseDate: day(date), currency: currency,
                              total: total.flatMap { Decimal(string: $0) }, category: category, addedOn: day("2026-09-29"))
        receipt.origin = origin
        receipt.destination = destination
        receipt.storeAddress = address
        receipt.customFields = fields
        return receipt
    }

    /// Hundreds of fuel receipts on a few routes, plus unrelated ones.
    private var receipts: [Receipt] {
        var receipts: [Receipt] = []
        for index in 0..<300 {
            let (origin, destination) = [("San Francisco", "Los Angeles"), ("Los Angeles", "San Francisco"), ("Oakland", "Reno")][index % 3]
            receipts.append(receipt(Int64(index + 1), index.isMultiple(of: 2) ? "Shell" : "Chevron",
                                    day("2026-01-01").adding(days: index).iso, total: "40.00", category: "Fuel",
                                    from: origin, to: destination))
        }
        receipts.append(receipt(301, "Esso", "2026-08-01", total: "55.10", currency: "CAD", category: "fuel",
                                from: "san  francisco", to: "Los Angeles", address: "1 Main St, Vancouver",
                                fields: [ReceiptField(name: "Vehicle", value: "Civic"), ReceiptField(name: "Project", value: "")]))
        receipts.append(receipt(302, "Grocer", "2026-09-01", total: "20.00", category: "Groceries",
                                fields: [ReceiptField(name: "vehicle", value: "Truck")]))
        return receipts
    }

    @Test func routeFacetFindsOneDirectionAcrossSpellingsAndCurrencies() throws {
        let routes = ReceiptOrganizer.facets(.route, in: receipts)
        let sfToLA = try #require(routes.first { $0.facet.title == "San Francisco → Los Angeles" })

        #expect(routes.count == 3)
        #expect(sfToLA.count == 101)
        #expect(sfToLA.totals.map(\.currency) == ["CAD", "USD"])
        #expect(sfToLA.totals.map(\.amount) == [Decimal(string: "55.1")!, 4000])

        let shown = receipts.filter(ReceiptFilter(facets: [sfToLA.facet]).includes)
        #expect(shown.count == 101)
        #expect(shown.allSatisfy { Search.key($0.origin) == "san francisco" && $0.destination == "Los Angeles" })
    }

    @Test func categoryFacetsGroupCaseInsensitivelyAndCountMostUsedFirst() {
        let categories = ReceiptOrganizer.facets(.category, in: receipts)
        #expect(categories.map(\.facet.title) == ["Fuel", "Groceries"])
        #expect(categories.map(\.count) == [301, 1])
        #expect(categories[0].totals.map(\.currency) == ["CAD", "USD"])
    }

    @Test func customFieldFacetsOfferNamesAndValues() {
        let fields = ReceiptOrganizer.facets(.field, in: receipts)
        let titles = Set(fields.map(\.facet.title))
        #expect(titles == ["Vehicle", "Vehicle: Civic", "vehicle: Truck", "Project"])
        #expect(fields.first { $0.facet == .field(name: "Vehicle", value: nil) }?.count == 2)

        let civic = receipts.filter(ReceiptFilter(facets: [.field(name: "VEHICLE", value: "civic")]).includes)
        #expect(civic.map(\.id) == [301])
        let anyVehicle = receipts.filter(ReceiptFilter(facets: [.field(name: "Vehicle", value: nil)]).includes)
        #expect(anyVehicle.map(\.id) == [301, 302])
    }

    @Test func searchCoversCustomFieldsAndStructuredDetails() {
        var receipt = receipt(1, "Shell", "2026-09-01", total: nil, from: "Portland", to: "Seattle",
                              fields: [ReceiptField(name: "Purpose", value: "Client visit")])
        receipt.transactionId = "TX-9981"
        receipt.fuelGrade = "Diesel"
        receipt.storeAddress = "12 Pine St"
        #expect(receipt.matches("client visit"))
        #expect(receipt.matches("purpose"))
        #expect(receipt.matches("seattle"))
        #expect(receipt.matches("tx-9981"))
        #expect(receipt.matches("diesel pine"))
        #expect(!receipt.matches("gasoline"))
    }

    @Test func filterCombinesFacetsTextRouteDatesAmountsAndCurrency() {
        var filter = ReceiptFilter(facets: [.category("Fuel")])
        filter.origin = "san fran"
        filter.destination = "los"
        filter.fromDate = day("2026-06-01")
        filter.toDate = day("2026-09-30")
        let routeAndDates = receipts.filter(filter.includes)
        #expect(!routeAndDates.isEmpty)
        #expect(routeAndDates.allSatisfy { $0.sortDate >= day("2026-06-01") && Search.key($0.origin) == "san francisco" })

        filter.minTotal = 50
        #expect(receipts.filter(filter.includes).map(\.id) == [301])
        filter.currency = "USD"
        #expect(receipts.filter(filter.includes).isEmpty)
        #expect(filter.refinementCount == 5)

        var query = ReceiptFilter(query: "chevron")
        query.maxTotal = 10
        #expect(receipts.filter(query.includes).isEmpty)
    }

    @Test func sortsByLowestTotalLocationAndRoute() {
        let sample = [
            receipt(1, "A", "2026-09-01", total: "9", from: "Reno", to: "Oakland", address: "B Street"),
            receipt(2, "B", "2026-09-02", total: nil, address: "A Avenue"),
            receipt(3, "C", "2026-09-03", total: "3", from: "Oakland", to: "Reno"),
        ]
        let ids = { (sort: ReceiptSort) in ReceiptOrganizer.groups(sample, sort: sort, grouping: .none).first?.receipts.map(\.id) }
        #expect(ids(.lowestTotal) == [3, 1, 2])
        #expect(ids(.location) == [2, 1, 3], "Blank locations last")
        #expect(ids(.route) == [3, 1, 2], "Blank routes last")
    }
}
