// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Dayfolio", platforms: [.macOS(.v14)], products: [.executable(name: "Dayfolio", targets: ["Dayfolio"])], targets: [
    .target(name: "DiaryCore"),
    .executableTarget(name: "Dayfolio", dependencies: ["DiaryCore"]),
    .executableTarget(name: "DiaryCoreChecks", dependencies: ["DiaryCore"], path: "Tests/DiaryCoreTests")
])
