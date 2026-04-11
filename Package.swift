// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpeakFlow",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "SpeakFlowCore", targets: ["SpeakFlowCore"])
    ],
    targets: [
        .target(
            name: "SpeakFlowCore",
            path: "Sources",
            exclude: [
                "App",
                "Audio",
                "Core/AppSupport.swift",
                "Core/PlatformPermissions.swift",
                "Networking/ElevenLabsRealtimeTranscriber.swift",
                "Services",
                "Storage/ClipboardSnapshot.swift",
                "UI"
            ],
            sources: [
                "Core/AppDomain.swift",
                "Models/AppConfig.swift",
                "Storage/Persistence.swift",
                "Networking/NetworkSession.swift",
                "Networking/OpenAICompatibleClient.swift",
                "Networking/ElevenLabsBatchTranscriberClient.swift"
            ]
        ),
        .testTarget(
            name: "SpeakFlowCoreTests",
            dependencies: ["SpeakFlowCore"],
            path: "Tests/SpeakFlowCoreTests"
        )
    ]
)
