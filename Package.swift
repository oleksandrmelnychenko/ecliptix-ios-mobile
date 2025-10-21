// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "EcliptixWorkspace",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
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
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.23.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.27.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "EcliptixCore",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]),
        .testTarget(
            name: "EcliptixCoreTests",
            dependencies: ["EcliptixCore"]),

        .target(
            name: "EcliptixNetworking",
            dependencies: [
                "EcliptixCore",
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]),
        .testTarget(
            name: "EcliptixNetworkingTests",
            dependencies: ["EcliptixNetworking"]),

        .target(
            name: "EcliptixSecurity",
            dependencies: [
                "EcliptixCore",
                .product(name: "Crypto", package: "swift-crypto"),
            ]),
        .testTarget(
            name: "EcliptixSecurityTests",
            dependencies: ["EcliptixSecurity"]),

        .target(
            name: "EcliptixAuthentication",
            dependencies: [
                "EcliptixCore",
                "EcliptixNetworking",
                "EcliptixSecurity",
            ]),
        .testTarget(
            name: "EcliptixAuthenticationTests",
            dependencies: ["EcliptixAuthentication"]),
    ]
)
