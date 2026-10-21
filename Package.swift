// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "LifeEditor",
    platforms: [.macOS(.v15)],
    products: [.library(name: "LifeCore", targets: ["LifeCore"]), .library(name: "LifeMedia", targets: ["LifeMedia"]), .executable(name: "LifeEditor", targets: ["LifeEditor"])],
    targets: [.target(name: "LifeCore"), .target(name: "LifeMedia", dependencies: ["LifeCore"]), .target(name:"LifeAnalysis",dependencies:["LifeCore"]), .testTarget(name:"LifeAnalysisTests",dependencies:["LifeAnalysis"]), .executableTarget(name: "LifeEditor", dependencies: ["LifeCore", "LifeMedia", "LifeAnalysis"]), .testTarget(name:"LifeEditorTests",dependencies:["LifeEditor"]), .testTarget(name: "LifeCoreTests", dependencies: ["LifeCore"]), .testTarget(name: "LifeMediaTests", dependencies: ["LifeCore", "LifeMedia"])]
)
