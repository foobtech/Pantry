import Foundation
import Darwin

/// bzip2 through the system's libbz2 (loaded at runtime, so there is nothing to link or bundle).
struct Bzip2Decompressor: Decompressor {
    // int BZ2_bzBuffToBuffDecompress(char *dest, unsigned int *destLen, char *source, unsigned int sourceLen, int small, int verbosity)
    private typealias Fn = @convention(c) (UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<UInt32>?,
                                           UnsafeMutablePointer<CChar>?, UInt32, Int32, Int32) -> Int32

    func decompress(_ data: Data) throws -> Data {
        guard !data.isEmpty,
              let lib = dlopen("/usr/lib/libbz2.1.0.dylib", RTLD_NOW),
              let symbol = dlsym(lib, "BZ2_bzBuffToBuffDecompress") else { throw DecompressError.unsupported }
        let fn = unsafeBitCast(symbol, to: Fn.self)

        var source = [UInt8](data)
        var capacity = max(source.count * 8, 1 << 20)
        while capacity <= (1 << 29) {
            var output = [UInt8](repeating: 0, count: capacity)
            var outLength = UInt32(capacity)
            let inLength = UInt32(source.count)
            let rc: Int32 = source.withUnsafeMutableBufferPointer { s in
                output.withUnsafeMutableBufferPointer { o in
                    fn(UnsafeMutableRawPointer(o.baseAddress!).assumingMemoryBound(to: CChar.self), &outLength,
                       UnsafeMutableRawPointer(s.baseAddress!).assumingMemoryBound(to: CChar.self), inLength, 0, 0)
                }
            }
            if rc == 0 { return Data(output[0..<Int(outLength)]) }
            if rc == -8 { capacity *= 2; continue }   // BZ_OUTBUFF_FULL: output buffer too small, retry bigger
            throw DecompressError.failed
        }
        throw DecompressError.failed
    }
}
