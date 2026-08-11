import CZlib
import Foundation

enum DeflateCodec {
    static func inflateRaw(_ input: Data) throws -> Data {
        try transform(input, operation: dicomkit_inflate_raw)
    }

    static func deflateRaw(_ input: Data) throws -> Data {
        try transform(input, operation: dicomkit_deflate_raw)
    }

    private static func transform(
        _ input: Data,
        operation: (UnsafePointer<UInt8>?, Int, UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, UnsafeMutablePointer<Int>?) -> Int32
    ) throws -> Data {
        var output: UnsafeMutablePointer<UInt8>?
        var outputSize = 0
        let result = input.withUnsafeBytes { bytes in
            operation(bytes.bindMemory(to: UInt8.self).baseAddress, input.count, &output, &outputSize)
        }
        guard result == 0, let output, outputSize >= 0 else { throw DICOMError.invalidDeflatedData }
        defer { dicomkit_zlib_free(output) }
        return Data(bytes: output, count: outputSize)
    }
}
