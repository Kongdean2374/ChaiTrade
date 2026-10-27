// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChaiTradeCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "ChaiTradeCore", targets: ["ChaiTradeCore"])],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3", providers: [.apt(["libsqlite3-dev"])]),
        .systemLibrary(name: "COpenSSL", pkgConfig: "openssl", providers: [.apt(["libssl-dev"])]),
        .target(name: "ChaiTradeCore", dependencies: ["CSQLite", .target(name: "COpenSSL", condition: .when(platforms: [.linux]))]),
        .testTarget(name: "ChaiTradeCoreTests", dependencies: ["ChaiTradeCore"])
    ], swiftLanguageModes: [.v6]
)
