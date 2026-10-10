// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PetAssistant",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PetAssistant", targets: ["PetAssistant"])
    ],
    targets: [
        .executableTarget(
            name: "PetAssistant",
            path: "Sources/PetAssistant"
        )
    ]
)
