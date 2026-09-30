import Foundation
@testable import EnveKeep

private final class BundleToken {}

enum Fixtures {
    static func url(_ name: String) -> URL {
        Bundle(for: BundleToken.self).url(forResource: name, withExtension: nil)!
    }
}

func day(_ iso: String) -> Day { Day(iso: iso)! }

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "enve-keep-tests/\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Builds stored (uncompressed) ZIP archives with arbitrary entry names, including hostile ones that
/// well-behaved ZIP writers refuse to produce.
struct TestZip {
    struct Entry {
        var name: String
        var data: Data
        var unixMode: UInt32?
    }

    var entries: [Entry] = []

    mutating func add(_ name: String, _ data: Data, unixMode: UInt32? = nil) {
        entries.append(Entry(name: name, data: data, unixMode: unixMode))
    }

    mutating func add(_ name: String, _ text: String) {
        add(name, Data(text.utf8))
    }

    func build() -> Data {
        var out = Data()
        var central = Data()
        for entry in entries {
            let name = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let offset = UInt32(out.count)
            out.append(le32: 0x0403_4b50)
            out.append(le16: 20)
            out.append(le16: 0x0800)
            out.append(le16: 0)
            out.append(le16: 0)
            out.append(le16: 0x21)
            out.append(le32: crc)
            out.append(le32: UInt32(entry.data.count))
            out.append(le32: UInt32(entry.data.count))
            out.append(le16: UInt16(name.count))
            out.append(le16: 0)
            out.append(name)
            out.append(entry.data)

            central.append(le32: 0x0201_4b50)
            central.append(le16: entry.unixMode == nil ? 20 : 0x0314)
            central.append(le16: 20)
            central.append(le16: 0x0800)
            central.append(le16: 0)
            central.append(le16: 0)
            central.append(le16: 0x21)
            central.append(le32: crc)
            central.append(le32: UInt32(entry.data.count))
            central.append(le32: UInt32(entry.data.count))
            central.append(le16: UInt16(name.count))
            central.append(le16: 0)
            central.append(le16: 0)
            central.append(le16: 0)
            central.append(le16: 0)
            central.append(le32: (entry.unixMode ?? 0) << 16)
            central.append(le32: offset)
            central.append(name)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        out.append(le32: 0x0605_4b50)
        out.append(le16: 0)
        out.append(le16: 0)
        out.append(le16: UInt16(entries.count))
        out.append(le16: UInt16(entries.count))
        out.append(le32: UInt32(central.count))
        out.append(le32: centralOffset)
        out.append(le16: 0)
        return out
    }

    func write(in directory: URL) throws -> URL {
        let url = directory.appending(path: "\(UUID().uuidString).zip")
        try build().write(to: url)
        return url
    }

    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (0xEDB8_8320 & (0 &- (crc & 1)))
            }
        }
        return ~crc
    }
}

private extension Data {
    mutating func append(le16 value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func append(le32 value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
