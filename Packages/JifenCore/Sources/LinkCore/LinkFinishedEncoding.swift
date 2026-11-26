import Compression
import Foundation

/// Terminal frames use lossless compression before considering the existing
/// action-history trim. The prefix leaves persisted JSON frames readable.
public enum LinkFinishedEncoding {
    private static let marker: [UInt8] = [0x4A, 0x46, 0x01]
    private static let headerSize = marker.count + MemoryLayout<UInt32>.size
    private static let maximumDecodedSize = 2 * 1024 * 1024
    private static let compressionThreshold = 4_096

    public static func encode(
        _ envelope: LinkEnvelope<LinkMatchFinishedPayload>,
        compress: Bool
    ) -> Data {
        guard compress, let json = try? JSONEncoder().encode(envelope) else {
            return LinkEnvelopeEncoding.encodedData(envelope)
        }
        if json.count >= compressionThreshold,
           json.count <= maximumDecodedSize,
           let compressed = try? (json as NSData).compressed(using: .lzfse) as Data,
           headerSize + compressed.count < json.count,
           headerSize + compressed.count <= LinkEnvelopeEncoding.defaultByteLimit {
            var frame = Data(marker)
            var size = UInt32(json.count).bigEndian
            withUnsafeBytes(of: &size) { frame.append(contentsOf: $0) }
            frame.append(compressed)
            return frame
        }
        if json.count <= LinkEnvelopeEncoding.defaultByteLimit { return json }
        return LinkEnvelopeEncoding.encodedData(envelope)
    }

    public static func decode(_ data: Data) -> LinkEnvelope<LinkMatchFinishedPayload>? {
        guard data.starts(with: marker) else {
            return try? JSONDecoder().decode(LinkEnvelope<LinkMatchFinishedPayload>.self, from: data)
        }
        guard data.count > headerSize, data.count <= LinkEnvelopeEncoding.defaultByteLimit else { return nil }
        let size = data.dropFirst(marker.count).prefix(MemoryLayout<UInt32>.size)
            .reduce(0) { ($0 << 8) | Int($1) }
        guard size > 0, size <= maximumDecodedSize else { return nil }
        // One spare byte detects a frame that expands past its declared size.
        var json = Data(count: size + 1)
        let decoded = json.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) in
            data.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!,
                    destination.count,
                    source.bindMemory(to: UInt8.self).baseAddress!.advanced(by: headerSize),
                    source.count - headerSize,
                    nil,
                    COMPRESSION_LZFSE
                )
            }
        }
        guard decoded == size else { return nil }
        json.removeLast()
        return try? JSONDecoder().decode(LinkEnvelope<LinkMatchFinishedPayload>.self, from: json)
    }
}
