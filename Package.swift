// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DICOMKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "DICOMKit",
            targets: ["DICOMKit"]
        )
    ],
    targets: [
        .target(
            name: "CharLS",
            path: "Vendor/CharLS",
            exclude: [
                "benchmark", "cli", "doc", "fuzzing", "samples", "test",
                "CMakeLists.txt", "CMakePresets.json", "LICENSES", "README.md"
            ],
            sources: [
                "src/charls_jpegls_decoder.cpp",
                "src/charls_jpegls_encoder.cpp",
                "src/golomb_lut.cpp",
                "src/jpeg_stream_reader.cpp",
                "src/jpeg_stream_writer.cpp",
                "src/jpegls_error.cpp",
                "src/make_scan_codec.cpp",
                "src/pch.cpp",
                "src/quantization_lut.cpp",
                "src/validate_spiff_header.cpp",
                "src/version.cpp"
            ],
            publicHeadersPath: "include/charls",
            cxxSettings: [
                .headerSearchPath("include"),
                .unsafeFlags(["-std=c++17"])
            ]
        ),
        .target(
            name: "DICOMKit",
            dependencies: ["CharLS"],
            path: "DICOMKit",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "DICOMKitTests",
            dependencies: ["DICOMKit"],
            path: "DICOMKitTests",
            // Copied as a directory so fixtures resolve from the test bundle
            // rather than from a source-tree path, which CI checkouts don't
            // share.
            resources: [
                .copy("Fixtures")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
