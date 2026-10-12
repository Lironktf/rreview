// Keeps the bridge symbols alive in the statically linked iOS binary so that
// Dart's DynamicLibrary.process() can resolve them in release builds.
#include "include/stockfish_ffi/stockfish_ffi.h"

__attribute__((used)) void* rreview_stockfish_symbols[] = {
    (void*)&sf_start, (void*)&sf_send, (void*)&sf_read_line, (void*)&sf_free,
    (void*)&sf_is_running, (void*)&sf_join, (void*)&sf_version,
};
