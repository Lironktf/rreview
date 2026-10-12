#
# OpenReview Stockfish FFI plugin (CocoaPods). Compiles the vendored, unmodified
# Stockfish 19 sources (GPLv3) plus a small bridge into the app binary.
# Flags mirror lichess's production multistockfish podspec (Stockfish 19 on iOS).
# A Swift Package manifest for the same sources lives in stockfish_ffi/Package.swift.
#
Pod::Spec.new do |s|
  s.name             = 'stockfish_ffi'
  s.version          = '1.0.0'
  s.summary          = 'Stockfish 19 chess engine for OpenReview, driven over UCI through Dart FFI.'
  s.description      = <<-DESC
Stockfish 19 (GPLv3) compiled from source for iOS with NEON, driven in-process through Dart FFI.
                       DESC
  s.homepage         = 'https://github.com/Lironktf/openreview'
  s.license          = { :type => 'GPL-3.0-or-later', :file => '../LICENSE' }
  s.author           = { 'OpenReview' => 'openreview@lironkatsif.com' }

  s.source           = { :path => '.' }
  s.source_files = [
    'stockfish_ffi/Sources/stockfish_ffi/*.{c,cpp}',
    'stockfish_ffi/Sources/stockfish_ffi/include/**/*.h',
    'stockfish_ffi/Sources/stockfish_ffi/Stockfish/src/**/*.{cpp,h}',
  ]
  s.public_header_files = 'stockfish_ffi/Sources/stockfish_ffi/include/**/*.h'
  s.exclude_files = [
    'stockfish_ffi/Sources/stockfish_ffi/Stockfish/src/main.cpp',
    'stockfish_ffi/Sources/stockfish_ffi/Stockfish/src/universal/**/*',
  ]
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.library = 'c++'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/stockfish_ffi/Sources/stockfish_ffi" "${PODS_TARGET_SRCROOT}/stockfish_ffi/Sources/stockfish_ffi/Stockfish/src"',
    'OTHER_CPLUSPLUSFLAGS' => '$(inherited) -std=c++17 -DNNUE_EMBEDDING_OFF -DUSE_PTHREADS -DIS_64BIT -DUSE_POPCNT',
    'OTHER_CPLUSPLUSFLAGS[config=Profile]' => '$(inherited) -std=c++17 -DNNUE_EMBEDDING_OFF -DUSE_PTHREADS -DIS_64BIT -DUSE_POPCNT -fno-exceptions -DNDEBUG -funroll-loops -O3 -DUSE_NEON=8 -flto=full',
    'OTHER_CPLUSPLUSFLAGS[config=Release]' => '$(inherited) -std=c++17 -DNNUE_EMBEDDING_OFF -DUSE_PTHREADS -DIS_64BIT -DUSE_POPCNT -fno-exceptions -DNDEBUG -funroll-loops -O3 -DUSE_NEON=8 -flto=full',
    'OTHER_LDFLAGS[config=Release]' => '$(inherited) -flto=full',
    'OTHER_LDFLAGS[config=Profile]' => '$(inherited) -flto=full',
    'GCC_SYMBOLS_PRIVATE_EXTERN' => 'NO',
  }
  s.swift_version = '5.0'
end
