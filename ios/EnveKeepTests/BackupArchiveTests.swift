import Foundation
import Testing
@testable import EnveKeep

struct BackupArchiveTests {
    private let manifest = BackupManifest(
        exportedAt: "2026-09-29T10:00:00Z",
        products: [
            Product(
                id: 3,
                name: "Espresso machine",
                brand: "Brewco",
                serialNumber: "SN-42",
                purchaseDate: day("2025-03-01"),
                price: Decimal(string: "499.99"),
                currency: "EUR",
                warrantyExpires: day("2027-03-01")
            ),
        ],
        subscriptions: [
            Subscription(
                id: 7,
                name: "Music",
                price: Decimal(string: "10.99"),
                currency: "USD",
                nextRenewal: day("2026-10-31"),
                anchorDate: day("2026-01-31")
            ),
        ],
        documents: [Document(id: 2, title: "Passport", expiresOn: day("2031-05-05"))],
        attachments: [
            EnveKeep.Attachment(id: 5, ownerType: .product, ownerId: 3, displayName: "receipt.pdf",
                                mimeType: "application/pdf", fileName: "0f1e2d3c.pdf", sizeBytes: 4),
            EnveKeep.Attachment(id: 6, ownerType: .document, ownerId: 2, displayName: "scan.jpg",
                                mimeType: "image/jpeg", fileName: "a1b2c3.jpg", sizeBytes: 3),
        ],
        settings: Settings(documentLeadDays: 90, defaultCurrency: "EUR")
    )

    private func manifestJSON(_ value: BackupManifest? = nil) throws -> Data {
        try BackupArchive.encodeManifest(value ?? manifest)
    }

    @Test func importsAndroidDeviceBackup() throws {
        let staging = try temporaryDirectory()
        let restored = try BackupArchive.read(from: Fixtures.url("android-device-backup.zip"), staging: staging)

        #expect(restored.format == "enve-keep-backup")
        #expect(restored.version == 1)
        #expect(restored.exportedAt == "2026-09-30T04:33:49.794202Z")
        #expect(restored.products.isEmpty)
        #expect(restored.subscriptions.isEmpty)
        #expect(restored.attachments.isEmpty)
        #expect(restored.documents == [
            Document(id: 1, title: "Passport", issuer: "", reference: "", issuedOn: nil, expiresOn: day("2026-09-29"), notes: ""),
        ])
        #expect(restored.settings == Settings(
            themeMode: .system,
            remindersEnabled: true,
            warrantyLeadDays: 30,
            subscriptionLeadDays: 7,
            documentLeadDays: 60,
            defaultCurrency: "USD",
            reminderPromptDismissed: true
        ))
    }

    @Test func reencodingAndroidManifestKeepsItsShape() throws {
        let staging = try temporaryDirectory()
        let restored = try BackupArchive.read(from: Fixtures.url("android-device-backup.zip"), staging: staging)
        let original = #"{"format":"enve-keep-backup","version":1,"exportedAt":"2026-09-30T04:33:49.794202Z","products":[],"subscriptions":[],"documents":[{"id":1,"title":"Passport","issuer":"","reference":"","issuedOn":null,"expiresOn":"2026-09-29","notes":""}],"attachments":[],"settings":{"themeMode":"SYSTEM","remindersEnabled":true,"warrantyLeadDays":30,"subscriptionLeadDays":7,"documentLeadDays":60,"defaultCurrency":"USD","reminderPromptDismissed":true}}"#
        let reencoded = try JSONSerialization.jsonObject(with: BackupArchive.encodeManifest(restored)) as! NSDictionary
        let expected = try JSONSerialization.jsonObject(with: Data(original.utf8)) as! NSDictionary
        #expect(reencoded == expected)
    }

    @Test func exportUsesAndroidJSONTypes() throws {
        let json = try JSONSerialization.jsonObject(with: manifestJSON()) as! [String: Any]
        let product = (json["products"] as! [[String: Any]])[0]
        #expect(product["id"] as? Int == 3)
        #expect(product["price"] as? String == "499.99")
        #expect(product["purchaseDate"] as? String == "2025-03-01")
        #expect(product["model"] as? String == "")
        #expect(product.keys.sorted() == [
            "brand", "currency", "id", "model", "name", "notes", "price", "purchaseDate", "retailer", "serialNumber",
            "warrantyExpires",
        ])
        let subscription = (json["subscriptions"] as! [[String: Any]])[0]
        #expect(subscription["cycleUnit"] as? String == "MONTHS")
        #expect(subscription["cycleCount"] as? Int == 1)
        #expect(subscription["anchorDate"] as? String == "2026-01-31")
        #expect(subscription["canceledOn"] is NSNull)
        let document = (json["documents"] as! [[String: Any]])[0]
        #expect(document["issuedOn"] is NSNull)
        let attachment = (json["attachments"] as! [[String: Any]])[0]
        #expect(attachment["ownerType"] as? String == "PRODUCT")
        #expect(attachment["sizeBytes"] as? Int == 4)
        let settings = json["settings"] as! [String: Any]
        #expect(settings["themeMode"] as? String == "SYSTEM")
        #expect(settings["documentLeadDays"] as? Int == 90)
    }

    @Test func decodesMinimalAndroidRecordsWithDefaults() throws {
        let json = #"{"exportedAt":"x","subscriptions":[{"id":4,"name":"News","currency":"GBP","nextRenewal":"2026-02-28","price":"4.50"}]}"#
        let decoded = try JSONDecoder().decode(BackupManifest.self, from: Data(json.utf8))
        let subscription = try #require(decoded.subscriptions.first)
        #expect(decoded.format == BackupManifest.format)
        #expect(subscription.cycleCount == 1)
        #expect(subscription.cycleUnit == .months)
        #expect(subscription.anchorDate == day("2026-02-28"))
        #expect(subscription.price == Decimal(string: "4.5"))
        #expect(decoded.settings == nil)
    }

    @Test func roundTripsRecordsAndAttachments() throws {
        let source = try temporaryDirectory()
        try Data([1, 2, 3, 4]).write(to: source.appending(path: "0f1e2d3c.pdf"))
        try Data([9, 8, 7]).write(to: source.appending(path: "a1b2c3.jpg"))
        let archive = source.appending(path: "backup.zip")
        try BackupArchive.write(manifest, attachmentsDirectory: source, to: archive)

        let staging = try temporaryDirectory()
        let restored = try BackupArchive.read(from: archive, staging: staging)

        #expect(restored == manifest)
        #expect(try Data(contentsOf: staging.appending(path: "attachments/0f1e2d3c.pdf")) == Data([1, 2, 3, 4]))
        #expect(try Data(contentsOf: staging.appending(path: "attachments/a1b2c3.jpg")) == Data([9, 8, 7]))
    }

    @Test(arguments: [
        "../evil.txt",
        "attachments/../../evil.txt",
        "attachments/..",
        "attachments/nested/file.jpg",
        "/attachments/abs.jpg",
        "attachments\\..\\evil.txt",
        "attachments/.hidden",
        "notes.txt",
    ])
    func rejectsUnexpectedEntries(name: String) throws {
        let directory = try temporaryDirectory()
        let staging = directory.appending(path: "staging")
        var zip = TestZip()
        zip.add(BackupArchive.manifestName, try manifestJSON(BackupManifest(exportedAt: "x")))
        zip.add(name, Data([1]))
        let archive = try zip.write(in: directory)

        #expect(throws: BackupError.self) { try BackupArchive.read(from: archive, staging: staging) }
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "evil.txt").path))
    }

    @Test func rejectsSymlinkEntries() throws {
        let directory = try temporaryDirectory()
        var zip = TestZip()
        zip.add(BackupArchive.manifestName, try manifestJSON(BackupManifest(exportedAt: "x")))
        zip.add("attachments/link.jpg", Data("/etc/passwd".utf8), unixMode: 0o120777)
        let archive = try zip.write(in: directory)

        #expect(throws: BackupError.self) { try BackupArchive.read(from: archive, staging: directory.appending(path: "staging")) }
    }

    @Test func rejectsMalformedArchives() throws {
        let directory = try temporaryDirectory()
        let garbage = directory.appending(path: "garbage.zip")
        try Data("definitely not a zip".utf8).write(to: garbage)
        #expect(throws: BackupError.self) { try BackupArchive.read(from: garbage, staging: directory.appending(path: "a")) }

        var noManifest = TestZip()
        noManifest.add("attachments/a1b2c3.jpg", Data([1]))
        #expect(throws: BackupError.invalid("Missing backup.json")) {
            try BackupArchive.read(from: noManifest.write(in: directory), staging: directory.appending(path: "b"))
        }

        var duplicate = TestZip()
        duplicate.add(BackupArchive.manifestName, try manifestJSON())
        duplicate.add(BackupArchive.manifestName, try manifestJSON())
        #expect(throws: BackupError.invalid("Duplicate manifest")) {
            try BackupArchive.read(from: duplicate.write(in: directory), staging: directory.appending(path: "c"))
        }

        var badJSON = TestZip()
        badJSON.add(BackupArchive.manifestName, "{\"format\":")
        #expect(throws: BackupError.invalid("Unreadable manifest")) {
            try BackupArchive.read(from: badJSON.write(in: directory), staging: directory.appending(path: "d"))
        }
    }

    @Test func rejectsForeignOrNewerManifests() throws {
        let directory = try temporaryDirectory()
        var foreign = TestZip()
        foreign.add(BackupArchive.manifestName, #"{"format":"other","exportedAt":"x"}"#)
        #expect(throws: BackupError.invalid("Not an Enve Keep backup")) {
            try BackupArchive.read(from: foreign.write(in: directory), staging: directory.appending(path: "a"))
        }

        var newer = TestZip()
        newer.add(BackupArchive.manifestName, #"{"format":"enve-keep-backup","version":4,"exportedAt":"x"}"#)
        #expect(throws: BackupError.self) {
            try BackupArchive.read(from: newer.write(in: directory), staging: directory.appending(path: "b"))
        }
    }

    @Test func rejectsMissingAttachmentFile() throws {
        let directory = try temporaryDirectory()
        var zip = TestZip()
        zip.add(BackupArchive.manifestName, try manifestJSON())
        zip.add("attachments/0f1e2d3c.pdf", Data([1]))
        #expect(throws: BackupError.self) {
            try BackupArchive.read(from: zip.write(in: directory), staging: directory.appending(path: "staging"))
        }
    }

    @Test func rejectsInvalidIdsAndOwnership() throws {
        var orphan = manifest
        orphan.attachments[1].ownerId = 99
        var duplicateIds = manifest
        duplicateIds.products.append(duplicateIds.products[0])
        var zeroId = manifest
        zeroId.documents[0].id = 0
        zeroId.attachments.removeLast()
        var wrongOwnerType = manifest
        wrongOwnerType.attachments[0].ownerType = .document
        var badCycle = manifest
        badCycle.subscriptions[0].cycleCount = 0

        for invalid in [orphan, duplicateIds, zeroId, wrongOwnerType, badCycle] {
            #expect(throws: BackupError.self) {
                try BackupArchive.validate(invalid, files: ["0f1e2d3c.pdf", "a1b2c3.jpg"])
            }
        }
        try BackupArchive.validate(manifest, files: ["0f1e2d3c.pdf", "a1b2c3.jpg"])
    }

    @Test func dropsUnreferencedFiles() throws {
        let directory = try temporaryDirectory()
        let staging = directory.appending(path: "staging")
        var empty = manifest
        empty.attachments = []
        var zip = TestZip()
        zip.add(BackupArchive.manifestName, try manifestJSON(empty))
        zip.add("attachments/stray.bin", Data([1]))
        _ = try BackupArchive.read(from: zip.write(in: directory), staging: staging)

        #expect(try FileManager.default.contentsOfDirectory(atPath: staging.appending(path: "attachments").path).isEmpty)
    }

    @Test func rejectsCorruptedEntryData() throws {
        let directory = try temporaryDirectory()
        var zip = TestZip()
        zip.add(BackupArchive.manifestName, try manifestJSON(BackupManifest(exportedAt: "x")))
        var bytes = zip.build()
        let flipAt = 30 + BackupArchive.manifestName.utf8.count
        bytes[flipAt] ^= 0xFF
        let archive = directory.appending(path: "corrupt.zip")
        try bytes.write(to: archive)

        #expect(throws: BackupError.self) { try BackupArchive.read(from: archive, staging: directory.appending(path: "staging")) }
    }

    @Test func safeFileNames() {
        #expect(BackupArchive.isSafeFileName("0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0.jpg"))
        #expect(BackupArchive.isSafeFileName("scan"))
        #expect(!BackupArchive.isSafeFileName(".jpg"))
        #expect(!BackupArchive.isSafeFileName("a/b.jpg"))
        #expect(!BackupArchive.isSafeFileName("a..jpg"))
        #expect(!BackupArchive.isSafeFileName("résumé.pdf"))
        #expect(!BackupArchive.isSafeFileName(String(repeating: "a", count: 129)))
    }
}
