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
        .binaryTarget(
            name: "TurboJPEG",
            url: "https://github.com/TimOliver/libjpeg-turbo-cocoa/releases/download/3.1.3/libjpeg-turbo-v3.1.3-xcframework-turbojpeg-static.zip",
            checksum: "f1eef005e7236b9b2c93a9abc104933f302ceac49b272467cd8083c91ca428d6"
        ),
        .target(
            name: "CharLS",
            path: "Vendor/CharLS",
            exclude: [
                "benchmark", "cli", "doc", "fuzzing", "samples", "test",
                "CMakeLists.txt", "CMakePresets.json", "LICENSES", "README.md",
                "src/charls.rc", "src/charls-template.pc", "src/charls.vcxproj",
                "src/charls.vcxproj.filters"
            ],
            // This target supplies a static implementation library only. The
            // Swift-facing C API lives in CCharLS so Xcode does not infer an
            // umbrella module from CharLS' optional C++ headers.
            publicHeadersPath: "src",
            cxxSettings: [
                .headerSearchPath("include")
            ]
        ),
        .target(
            name: "CCharLS",
            dependencies: ["CharLS"],
            path: "Sources/CCharLS",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("../../Vendor/CharLS/include")
            ]
        ),
        .target(
            name: "CTurboJPEG",
            dependencies: ["TurboJPEG"],
            path: "Sources/CTurboJPEG",
            publicHeadersPath: "include"
        ),
        .target(
            name: "DICOMKit",
            dependencies: ["CCharLS", "CTurboJPEG"],
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
    ],
    cxxLanguageStandard: .cxx17
)
