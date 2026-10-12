# Shared native build for the rreview Stockfish FFI plugin (Linux desktop and Android).
# iOS compiles the same sources through the CocoaPods podspec in ../ios.
cmake_minimum_required(VERSION 3.10)

project(stockfish_ffi_library VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(SF_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../ios/stockfish_ffi/Sources/stockfish_ffi")
file(GLOB_RECURSE SF_SOURCES "${SF_ROOT}/Stockfish/src/*.cpp")
# main.cpp defines main(); universal/ is only for upstream's macOS universal builds.
list(FILTER SF_SOURCES EXCLUDE REGEX "/Stockfish/src/main\\.cpp$")
list(FILTER SF_SOURCES EXCLUDE REGEX "/Stockfish/src/universal/")

add_library(stockfish_ffi SHARED
  "${SF_ROOT}/sf_bridge.cpp"
  ${SF_SOURCES}
)

set_target_properties(stockfish_ffi PROPERTIES
  PUBLIC_HEADER "${SF_ROOT}/include/stockfish_ffi/stockfish_ffi.h"
  OUTPUT_NAME "stockfish_ffi"
  CXX_VISIBILITY_PRESET hidden
)

target_include_directories(stockfish_ffi PRIVATE "${SF_ROOT}" "${SF_ROOT}/include/stockfish_ffi")
target_compile_definitions(stockfish_ffi PUBLIC DART_SHARED_LIB)

# The NNUE network is shipped as an app asset and loaded with `setoption name EvalFile`.
set(SF_DEFS -DNNUE_EMBEDDING_OFF -DUSE_PTHREADS -DNDEBUG)
set(SF_OPTS -fno-exceptions -funroll-loops -O3)

if (ANDROID)
  # Android 15 16 KB page size requirement.
  target_link_options(stockfish_ffi PRIVATE "-Wl,-z,max-page-size=16384")
  if (ANDROID_ABI STREQUAL "arm64-v8a")
    list(APPEND SF_DEFS -DIS_64BIT -DUSE_POPCNT -DUSE_NEON=8)
  elseif (ANDROID_ABI STREQUAL "x86_64")
    list(APPEND SF_DEFS -DIS_64BIT -DUSE_POPCNT -DUSE_SSE2 -DUSE_SSSE3 -DUSE_SSE41)
    list(APPEND SF_OPTS -msse -msse2 -mssse3 -msse4.1 -mpopcnt)
  endif()
else()
  if (CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|AMD64")
    # x86-64-v3 baseline (Haswell+/Zen+), the same the Stockfish release binaries assume.
    list(APPEND SF_DEFS -DIS_64BIT -DUSE_POPCNT -DUSE_SSE2 -DUSE_SSSE3 -DUSE_SSE41 -DUSE_AVX2 -DUSE_PEXT)
    list(APPEND SF_OPTS -msse -msse2 -mssse3 -msse4.1 -mpopcnt -mavx2 -mbmi -mbmi2 -mfma)
  elseif (CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
    list(APPEND SF_DEFS -DIS_64BIT -DUSE_POPCNT -DUSE_NEON=8)
  endif()
  find_package(Threads REQUIRED)
  target_link_libraries(stockfish_ffi PRIVATE Threads::Threads)
endif()

target_compile_options(stockfish_ffi PRIVATE ${SF_DEFS} ${SF_OPTS})
