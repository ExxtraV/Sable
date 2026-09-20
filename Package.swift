// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Quill",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Quill", targets: ["Quill"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "QuillCore"),
        .executableTarget(name: "Quill", dependencies: ["QuillCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "QuillCoreTests", dependencies: ["QuillCore"])
    ]
)
