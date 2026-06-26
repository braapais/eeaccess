// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swift-tesla-ble",
    // iOS 17 is the product target. macOS 13 is declared ONLY so that
    // `swift test` can compile the pure-logic test suite against a macOS
    // host — CryptoKit / CheckedContinuation / os.Logger availability
    // requires this. The product itself is not intended to run on macOS
    // (no CoreBluetooth BLE validation has been done there).
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v13)],
    products: [
        .library(name: "TeslaBLE", targets: ["TeslaBLE"]),
    ],
    dependencies: [
        // Vendored swift-protobuf (1.38.0, runtime library only) — local copy
        // adds a `platforms:` declaration so it builds at watchOS 10, not the
        // upstream-implied 8.0 that fails `archive` on current watchOS SDKs.
        .package(path: "../Vendor/swift-protobuf"),
    ],
    targets: [
        .target(
            name: "TeslaBLE",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ],
        ),
        .testTarget(
            name: "TeslaBLETests",
            dependencies: ["TeslaBLE"],
            resources: [.copy("Fixtures")],
        ),
    ],
)
