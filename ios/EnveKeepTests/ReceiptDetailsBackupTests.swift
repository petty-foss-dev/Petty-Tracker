import Foundation
import Testing
@testable import EnveKeep

struct ReceiptDetailsBackupTests {
    private func decode(_ json: String) throws -> BackupManifest {
        try JSONDecoder().decode(BackupManifest.self, from: Data(json.utf8))
    }

    private func manifest(receipt: String) -> String {
        #"{"format":"enve-keep-backup","version":2,"exportedAt":"x","receipts":["# + receipt + "]}"
    }

    @Test func readsVersionTwoReceiptsWrittenBeforeStructuredDetails() throws {
        let decoded = try decode(manifest(receipt: #"{"id":3,"merchant":"Deli","purchaseDate":"2026-09-01","currency":"USD","items":[],"subtotal":null,"tax":null,"tip":null,"total":"12.5","category":"","tags":[],"notes":"","recognizedText":{},"pageConfidence":{},"pageDigests":{},"productIds":[],"resolvedFlags":[],"addedOn":"2026-09-02"}"#))
        let receipt = try #require(decoded.receipts.first)

        #expect(receipt.total == Decimal(string: "12.5"))
        #expect(receipt.purchaseTime == nil)
        #expect(receipt.storeAddress.isEmpty && receipt.origin.isEmpty && receipt.fuelGrade.isEmpty)
        #expect(receipt.fuelVolume == nil && receipt.fuelUnit == nil)
        #expect(receipt.customFields.isEmpty)
        try BackupArchive.validate(decoded, files: [])
    }

    @Test func rejectsBackupsFromNewerVersions() throws {
        let newer = BackupManifest(version: 4, exportedAt: "x")
        #expect(throws: BackupError.self) { try BackupArchive.validate(newer, files: []) }
    }

    @Test func structuredDetailsRoundTripWithExplicitKeys() throws {
        var receipt = Receipt(id: 1, merchant: "Shell", purchaseDate: day("2026-09-14"), currency: "USD", addedOn: day("2026-09-14"))
        receipt.purchaseTime = ClockTime(hour: 6, minute: 5)
        receipt.storeAddress = "1500 Market St, San Francisco, CA 94103"
        receipt.storePhone = "(415) 555-0199"
        receipt.transactionId = "004521"
        receipt.paymentMethod = "Visa"
        receipt.cardLastFour = "1234"
        receipt.origin = "San Francisco"
        receipt.destination = "Los Angeles"
        receipt.fuelGrade = "Unleaded"
        receipt.fuelVolume = Decimal(string: "10.543")
        receipt.fuelUnit = .gallons
        receipt.fuelUnitPrice = Decimal(string: "3.459")
        receipt.pumpNumber = "07"
        receipt.odometer = "45210"
        receipt.customFields = [ReceiptField(name: "Vehicle", value: "Civic"), ReceiptField(name: "Reimbursed", value: "")]
        let original = BackupManifest(version: 3, exportedAt: "x", receipts: [receipt])

        let data = try BackupArchive.encodeManifest(original)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let encoded = (json["receipts"] as! [[String: Any]])[0]

        #expect(encoded["purchaseTime"] as? String == "06:05")
        #expect(encoded["fuelVolume"] as? String == "10.543")
        #expect(encoded["fuelUnit"] as? String == "GALLONS")
        #expect((encoded["customFields"] as? [[String: String]])?.first == ["name": "Vehicle", "value": "Civic"])
        #expect(try JSONDecoder().decode(BackupManifest.self, from: data) == original)

        let blank = BackupManifest(version: 3, exportedAt: "x", receipts: [Receipt(id: 1, merchant: "A", currency: "USD", addedOn: day("2026-09-14"))])
        let blankJSON = try JSONSerialization.jsonObject(with: BackupArchive.encodeManifest(blank)) as! [String: Any]
        let blankReceipt = (blankJSON["receipts"] as! [[String: Any]])[0]
        #expect(blankReceipt["purchaseTime"] is NSNull)
        #expect(blankReceipt["fuelUnit"] is NSNull)
        #expect(blankReceipt["customFields"] as? [Any] != nil)
    }

    @Test(arguments: [
        #"{"id":1,"merchant":"A","currency":"USD","addedOn":"2026-09-01","purchaseTime":"25:00"}"#,
        #"{"id":1,"merchant":"A","currency":"USD","addedOn":"2026-09-01","purchaseTime":"6:5"}"#,
        #"{"id":1,"merchant":"A","currency":"USD","addedOn":"2026-09-01","fuelUnit":"BARRELS"}"#,
        #"{"id":1,"merchant":"A","currency":"USD","addedOn":"2026-09-01","fuelVolume":"ten"}"#,
        #"{"id":1,"merchant":"A","currency":"USD","addedOn":"2026-09-01","customFields":[{"value":"Civic"}]}"#,
        #"{"id":1,"merchant":"A","currency":"USD","addedOn":"2026-09-01","customFields":"Vehicle"}"#,
    ])
    func rejectsMalformedDetailsWhenDecoding(receipt: String) {
        #expect(throws: DecodingError.self) { try decode(manifest(receipt: receipt)) }
    }

    @Test func rejectsInvalidDetailsWhenValidating() throws {
        let valid = Receipt(id: 1, merchant: "A", currency: "USD", addedOn: day("2026-09-01"))
        var blankName = valid
        blankName.customFields = [ReceiptField(name: "  ", value: "Civic")]
        var shortCard = valid
        shortCard.cardLastFour = "12"
        var negativeVolume = valid
        negativeVolume.fuelVolume = -1

        try BackupArchive.validate(BackupManifest(version: 2, exportedAt: "x", receipts: [valid]), files: [])
        for invalid in [blankName, shortCard, negativeVolume] {
            #expect(throws: BackupError.self) {
                try BackupArchive.validate(BackupManifest(version: 2, exportedAt: "x", receipts: [invalid]), files: [])
            }
        }
    }
}
