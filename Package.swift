// swift-tools-version: 5.9
import PackageDescription

// CadenceCore is deliberately Foundation-only: every number the app reasons
// about is computed here, so it can be compiled and unit-tested on any machine,
// not just a Mac with Xcode. The Apple layer (AVFoundation, SwiftUI, WatchKit)
// sits on top and contains no logic worth testing.
let package = Package(
    name: "CadenceCore",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [.library(name: "CadenceCore", targets: ["CadenceCore"])],
    targets: [
        .target(name: "CadenceCore"),
        .testTarget(name: "CadenceCoreTests", dependencies: ["CadenceCore"])
    ]
)
