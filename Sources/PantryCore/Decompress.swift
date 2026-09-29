import Foundation
#if canImport(Compression)
import Compression
#endif

public enum DecompressError: Error { case unsupported, badHeader, failed }

public protocol Decompressor { func decompress(_ data: Data) throws -> Data }

/// gzip is built in. bzip2 and xz have no system API on iOS: plug in your own
/// (libbz2/liblzma, or a root helper that runs `bzip2 -dc` / `xz -dc`).
public struct Decompressors {
    public var gzip: Decompressor?   // optional override; defaults to the built-in Compression-based one
    public var bzip2: Decompressor?
    public var xz: Decompressor?
    public init(gzip: Decompressor? = nil, bzip2: Decompressor? = nil, xz: Decompressor? = nil) {
        self.gzip = gzip; self.bzip2 = bzip2; self.xz = xz
    }
}

public enum Gzip {
    public static func decompress(_ data: Data) throws -> Data {
        #if canImport(Compression)
        let b = [UInt8](data)
        guard b.count > 18, b[0] == 0x1f, b[1] == 0x8b, b[2] == 8 else { throw DecompressError.badHeader }
        let flags = b[3]
        var pos = 10
        if flags & 4 != 0 { guard pos + 2 <= b.count else { throw DecompressError.badHeader }
            pos += 2 + Int(b[pos]) + (Int(b[pos + 1]) << 8) }
        if flags & 8 != 0 { while pos < b.count && b[pos] != 0 { pos += 1 }; pos += 1 }
        if flags & 16 != 0 { while pos < b.count && b[pos] != 0 { pos += 1 }; pos += 1 }
        if flags & 2 != 0 { pos += 2 }
        guard pos < b.count - 8 else { throw DecompressError.badHeader }
        let deflated = Data(b[pos..<(b.count - 8)])   // strip header + CRC32/ISIZE trailer
        return try inflate(deflated)
        #else
        throw DecompressError.unsupported
        #endif
    }

    #if canImport(Compression)
    private static func inflate(_ input: Data) throws -> Data {
        let chunk = 64 * 1024
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { dst.deallocate() }
        var stream = compression_stream(dst_ptr: dst, dst_size: 0, src_ptr: dst, src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK
        else { throw DecompressError.failed }
        defer { compression_stream_destroy(&stream) }

        var out = Data()
        try input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { throw DecompressError.failed }
            stream.src_ptr = base
            stream.src_size = raw.count
            while true {
                stream.dst_ptr = dst
                stream.dst_size = chunk
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                guard status == COMPRESSION_STATUS_OK || status == COMPRESSION_STATUS_END
                else { throw DecompressError.failed }
                out.append(dst, count: chunk - stream.dst_size)
                if status == COMPRESSION_STATUS_END { break }
            }
        }
        return out
    }
    #endif
}
