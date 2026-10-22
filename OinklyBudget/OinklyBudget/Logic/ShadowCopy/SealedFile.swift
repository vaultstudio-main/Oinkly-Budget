import Foundation
import Compression
import CryptoKit

/// What a sealed file says about itself, without opening what is inside it.
nonisolated struct SealedHeader: Codable, Equatable, Sendable {
    var formatVersion: Int
    /// "data" for a copy of the data file, "receipt" for a receipt or photo.
    var kind: String
    var createdAt: Date
    var appVersion: String
    /// How big the file was before it was sealed.
    var plainSize: Int64
    /// Notes the caller keeps with the file, as a binary property list.
    var info: Data?
}

nonisolated enum SealedError: LocalizedError {
    case notSealed
    case newerFormat
    case damaged(String)

    var errorDescription: String? {
        switch self {
        case .notSealed: "That isn't an Oinkly Budget file."
        case .newerFormat: "That file was made by a newer version of Oinkly Budget. Update the app and try again."
        case .damaged(let why): "That file is damaged: \(why)"
        }
    }
}

/// Oinkly Budget's own file format for the copies it keeps outside the app: the data inside is compressed and wrapped
/// with an Oinkly Budget header and a fingerprint, so a text editor, a database viewer or a renamed file shows nothing
/// useful and only Oinkly Budget can unpack it. It is a wrapper, not encryption: it keeps the files from being read by
/// accident or by ordinary tools, and tells a damaged file from a good one without opening it.
///
/// The file is: a fixed marker, the size of the header, the header (a binary property list), the compressed body, and
/// a 32 byte fingerprint of the body.
nonisolated enum SealedFile {
    static let marker = Data([0x4F, 0x49, 0x4E, 0x4B, 0x50, 0x49, 0x47, 0x01])
    static let formatVersion = 1
    static let fingerprintLength = 32
    static let chunkSize = 1 << 20
    /// The extension for a sealed copy of the data file, and for a sealed receipt.
    static let fileExtension = "pigdata"

    struct Layout {
        var header: SealedHeader
        var bodyStart: UInt64
        var bodyLength: UInt64
    }

    // MARK: Notes kept with a file

    static func encodeInfo<T: Encodable>(_ value: T) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(value)
    }

    static func decodeInfo<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try PropertyListDecoder().decode(type, from: data)
    }

    // MARK: Sealing

    /// Seals `plain` into `destination`. The file is written beside its destination and renamed into place, so a reader
    /// never sees half a file.
    @discardableResult
    static func seal(_ plain: URL, to destination: URL, kind: String, info: Data? = nil, appVersion: String, now: Date = .now) throws -> SealedHeader {
        let manager = FileManager.default
        let size = (try? manager.attributesOfItem(atPath: plain.path)[.size] as? NSNumber)?.int64Value ?? 0
        let header = SealedHeader(formatVersion: formatVersion, kind: kind, createdAt: now, appVersion: appVersion, plainSize: size, info: info)
        let headerData = try encodeInfo(header)
        var prefix = marker
        var length = UInt32(headerData.count).bigEndian
        prefix.append(Data(bytes: &length, count: 4))
        prefix.append(headerData)

        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        guard manager.createFile(atPath: temporary.path, contents: nil) else { throw SealedError.damaged("it couldn't be written") }
        defer { try? manager.removeItem(at: temporary) }
        let input = try FileHandle(forReadingFrom: plain)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: temporary)
        defer { try? output.close() }
        try output.write(contentsOf: prefix)

        var hasher = SHA256()
        var failure: Error?
        let filter = try OutputFilter(.compress, using: .lzfse) { data in
            guard let data, failure == nil else { return }
            hasher.update(data: data)
            do { try output.write(contentsOf: data) } catch { failure = error }
        }
        while let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty {
            try filter.write(chunk)
            if let failure { throw failure }
        }
        try filter.finalize()
        if let failure { throw failure }
        try output.write(contentsOf: Data(hasher.finalize()))
        try output.synchronize()
        try output.close()
        if rename(temporary.path, destination.path) != 0 {
            throw SealedError.damaged("it couldn't be put in place (\(String(cString: strerror(errno))))")
        }
        return header
    }

    // MARK: Reading

    /// Reads the header of a sealed file, and where its body is. Cheap: it never reads the body.
    static func layout(of url: URL) throws -> Layout {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let total = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
        guard let start = try handle.read(upToCount: marker.count + 4), start.count == marker.count + 4, start.prefix(marker.count) == marker else {
            throw SealedError.notSealed
        }
        let headerLength = start.suffix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let bodyStart = UInt64(marker.count + 4) + UInt64(headerLength)
        guard headerLength > 0, headerLength < 1_000_000, bodyStart + UInt64(fingerprintLength) <= total else { throw SealedError.damaged("its header is cut short") }
        guard let headerData = try handle.read(upToCount: Int(headerLength)), headerData.count == Int(headerLength),
              let header = try? decodeInfo(SealedHeader.self, from: headerData) else { throw SealedError.damaged("its header can't be read") }
        if header.formatVersion > formatVersion { throw SealedError.newerFormat }
        return Layout(header: header, bodyStart: bodyStart, bodyLength: total - bodyStart - UInt64(fingerprintLength))
    }

    static func readHeader(_ url: URL) throws -> SealedHeader { try layout(of: url).header }

    /// Whether the body matches the fingerprint stored with it. Reads the file once; opens nothing.
    static func isIntact(_ url: URL) -> Bool {
        guard let layout = try? layout(of: url), let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: layout.bodyStart)
            var remaining = layout.bodyLength
            var hasher = SHA256()
            while remaining > 0 {
                let want = Int(min(UInt64(chunkSize), remaining))
                guard let data = try handle.read(upToCount: want), !data.isEmpty else { return false }
                hasher.update(data: data)
                remaining -= UInt64(data.count)
            }
            guard let stored = try handle.read(upToCount: fingerprintLength), stored.count == fingerprintLength else { return false }
            return Data(hasher.finalize()) == stored
        } catch {
            return false
        }
    }

    /// Unpacks a sealed file into `plain`. The fingerprint is checked as it is read; if it doesn't match, nothing is left behind.
    static func unseal(_ sealed: URL, to plain: URL) throws {
        let manager = FileManager.default
        let layout = try layout(of: sealed)
        let input = try FileHandle(forReadingFrom: sealed)
        defer { try? input.close() }
        try input.seek(toOffset: layout.bodyStart)
        var remaining = layout.bodyLength
        var hasher = SHA256()

        try manager.createDirectory(at: plain.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = plain.deletingLastPathComponent().appendingPathComponent(".\(plain.lastPathComponent).\(UUID().uuidString).tmp")
        guard manager.createFile(atPath: temporary.path, contents: nil) else { throw SealedError.damaged("it couldn't be unpacked") }
        defer { try? manager.removeItem(at: temporary) }
        let output = try FileHandle(forWritingTo: temporary)
        defer { try? output.close() }

        let filter = try InputFilter<Data>(.decompress, using: .lzfse) { (length: Int) -> Data? in
            let want = Int(min(UInt64(length), remaining))
            guard want > 0, let data = try input.read(upToCount: want), !data.isEmpty else { return nil }
            remaining -= UInt64(data.count)
            hasher.update(data: data)
            return data
        }
        var written: Int64 = 0
        do {
            while let data = try filter.readData(ofLength: chunkSize) {
                try output.write(contentsOf: data)
                written += Int64(data.count)
            }
        } catch {
            throw SealedError.damaged("its contents can't be unpacked")
        }
        let computed = Data(hasher.finalize())
        let stored = try input.read(upToCount: fingerprintLength)
        guard remaining == 0, stored == computed else { throw SealedError.damaged("its fingerprint doesn't match") }
        guard written == layout.header.plainSize else { throw SealedError.damaged("its size is wrong") }
        try output.close()
        try? manager.removeItem(at: plain)
        if rename(temporary.path, plain.path) != 0 {
            throw SealedError.damaged("it couldn't be put in place (\(String(cString: strerror(errno))))")
        }
    }
}
