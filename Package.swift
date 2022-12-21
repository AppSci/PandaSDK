// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PandaSDK",
    platforms: [.iOS("13.0")],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "PandaSDK",
            targets: ["PandaSDK"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/ninjaprox/NVActivityIndicatorView.git", from: "5.1.1"),
        .package(url: "https://github.com/tikhop/TPInAppReceipt.git", .upToNextMajor(from: "3.0.0"))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "PandaSDK",
            dependencies: [
                .product(name: "NVActivityIndicatorViewExtended", package: "NVActivityIndicatorView"),
                .product(name: "TPInAppReceipt", package: "tpinappreceipt")
            ]
        )
    ]
)
