// swift-tools-version: 5.9
// Swift Package manifest for the OpenReview Stockfish FFI plugin (Flutter SPM
// integration). Mirrors the CocoaPods podspec next to it; flags follow the
// production multistockfish package (lichess) for Stockfish 19 on iOS.
import PackageDescription

let baseFlags = [
    "-DNNUE_EMBEDDING_OFF",
    "-DUSE_PTHREADS",
    "-DIS_64BIT",
    "-DUSE_POPCNT",
]
let releaseFlags = [
    "-fno-exceptions",
    "-DNDEBUG",
    "-funroll-loops",
    "-O3",
    "-DUSE_NEON=8",
    "-flto=full",
]

let package = Package(
    name: "stockfish_ffi",
    platforms: [
        .iOS("15.0"),
    ],
    products: [
        .library(name: "stockfish-ffi", targets: ["stockfish_ffi"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "stockfish_ffi",
            dependencies: [],
            exclude: [
                "Stockfish/src/main.cpp",
                "Stockfish/src/incbin/UNLICENCE",
                "Stockfish/src/universal",
                "Stockfish/AUTHORS",
                "Stockfish/CITATION.cff",
                "Stockfish/Copying.txt",
                "Stockfish/README.md",
            ],
            cSettings: [
                .headerSearchPath("include/stockfish_ffi"),
                .headerSearchPath("Stockfish/src"),
            ],
            cxxSettings: [
                .headerSearchPath("include/stockfish_ffi"),
                .headerSearchPath("Stockfish/src"),
                .headerSearchPath("."),
                .unsafeFlags(baseFlags),
                .unsafeFlags(releaseFlags, .when(configuration: .release)),
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
            ]
        )
    ],
    cxxLanguageStandard: .cxx17
)
