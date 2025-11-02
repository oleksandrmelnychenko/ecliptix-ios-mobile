// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "EcliptixWorkspace",
    platforms: [
        .iOS("18.0"),
        .macOS("15.0")
    ],
    products: [

        .library(
            name: "EcliptixCore",
            targets: ["EcliptixCore"]),
        .library(
            name: "EcliptixNetworking",
            targets: ["EcliptixNetworking"]),
        .library(
            name: "EcliptixSecurity",
            targets: ["EcliptixSecurity"]),
        .library(
            name: "EcliptixAuthentication",
            targets: ["EcliptixAuthentication"]),
        .library(
            name: "EcliptixProto",
            targets: ["EcliptixProto"]),
        .library(
            name: "EcliptixOPAQUE",
            targets: ["EcliptixOPAQUE"]),

    ],
    dependencies: [

        .package(url: "https://github.com/grpc/grpc-swift-2.git", from: "2.1.0"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "2.0.0"),
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "2.2.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.32.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.15.1"),
    ],
    targets: [

        .target(
            name: "EcliptixCore",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "Packages/EcliptixCore/Sources"),
        .target(
            name: "EcliptixNetworking",
            dependencies: [
                "EcliptixCore",
                "EcliptixSecurity",
                "EcliptixProto",
                "Clibsodium",
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "Packages/EcliptixNetworking/Sources"),

        .target(
            name: "EcliptixSecurity",
            dependencies: [
                "EcliptixCore",
                "EcliptixProto",
                "Clibsodium",
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: "Packages/EcliptixSecurity/Sources"),
        .testTarget(
            name: "EcliptixSecurityTests",
            dependencies: ["EcliptixSecurity"],
            path: "Packages/EcliptixSecurity/Tests"),

        .target(
            name: "EcliptixAuthentication",
            dependencies: [
                "EcliptixCore",
                "EcliptixNetworking",
                "EcliptixSecurity",
                "EcliptixOPAQUE",
                "EcliptixProto",
            ],
            path: "Packages/EcliptixAuthentication/Sources"),

        .target(
            name: "EcliptixProto",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
            ],
            path: "Protobufs/Generated"
        ),

        // OPAQUE C wrapper - pure C header for Swift interop
        .target(
            name: "COpaqueClient",
            path: "Packages/EcliptixOPAQUE/Sources/COpaqueClient"
        ),

        // OPAQUE client library - iOS static library with C API
        // Note: libsodium is statically linked into libopaque_client.a, no XCFramework dependency needed
        .target(
            name: "OpaqueClient",
            dependencies: ["COpaqueClient"],
            path: "Packages/EcliptixOPAQUE",
            sources: ["Sources/OpaqueClient"],
            linkerSettings: [
                .linkedLibrary("c++"),
                .unsafeFlags([
                    "-L\(Context.packageDirectory)/Packages/EcliptixOPAQUE/lib",
                    "-lopaque_client"
                ])
            ]
        ),

        // Certificate Pinning C header - pure C API
        .target(
            name: "CCertificatePinning",
            path: "Packages/EcliptixCertificatePinning/Sources/CCertificatePinning"
        ),

        // Certificate Pinning client library - iOS static library
        .target(
            name: "CertificatePinning",
            dependencies: ["CCertificatePinning"],
            path: "Packages/EcliptixCertificatePinning",
            exclude: ["include"],
            sources: [],
            linkerSettings: [
                .linkedLibrary("c++"),
                .unsafeFlags([
                    "-L\(Context.packageDirectory)/Packages/EcliptixCertificatePinning/lib",
                    "-lcertificate_pinning_client"
                ])
            ]
        ),
        .binaryTarget(
            name: "Clibsodium",
            path: "ThirdParty/xcframeworks/Clibsodium.xcframework"
        ),

        .binaryTarget(
            name: "ecliptix_client",
            path: "ThirdParty/xcframeworks/ecliptix_client.xcframework"
        ),
        .binaryTarget(
            name: "OpenSSLCrypto",
            path: "ThirdParty/xcframeworks/OpenSSL-crypto.xcframework"
        ),

        .target(
            name: "EcliptixOPAQUE",
            dependencies: [
                "EcliptixCore",
                "COpaqueClient",
                "OpaqueClient",
                "Clibsodium",
            ],
            path: "Packages/EcliptixOPAQUE/Sources/EcliptixOPAQUE"
        ),

    ]
)
