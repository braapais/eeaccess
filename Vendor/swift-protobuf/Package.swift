// swift-tools-version:6.2

// Trimmed, vendored copy of apple/swift-protobuf 1.38.0 — the runtime
// `SwiftProtobuf` library only (TeslaBLE links this; the protoc / plugin /
// test targets and bundled C++ are not shipped).
//
// The ONE substantive change vs. upstream is the `platforms:` declaration.
// Upstream declares no platforms, so Xcode builds it at watchOS 8.0 — below
// the 9.0 floor of current watchOS SDKs — which fails `archive`. Intermediate
// SwiftPM packages don't reliably raise a remote dependency's deployment
// target in Xcode, so the only robust fix is for swift-protobuf's own manifest
// to declare it. Apache-2.0 with Runtime Library Exception; see LICENSE.txt.

import PackageDescription

#if canImport(Darwin)
let resources: [Resource] = [
    .copy("PrivacyInfo.xcprivacy")
]
#else
let resources = [Resource]()
#endif

let package = Package(
    name: "SwiftProtobuf",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
        .watchOS(.v10),
        .tvOS(.v15),
    ],
    products: [
        .library(
            name: "SwiftProtobuf",
            targets: ["SwiftProtobuf"]
        ),
    ],
    traits: [
        .trait(
            name: "BinaryDelimitedStreams",
            description:
                "This trait enables the APIs to serializing binary delimited messages with Foundation Input/Output streams."
        ),
        .trait(name: "FieldMaskUtilities", description: "This trait enables APIs for improved FieldMask support."),
        .default(enabledTraits: ["BinaryDelimitedStreams", "FieldMaskUtilities"]),
    ],
    targets: [
        .target(
            name: "SwiftProtobuf",
            exclude: ["CMakeLists.txt"],
            resources: resources,
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
    ]
)
