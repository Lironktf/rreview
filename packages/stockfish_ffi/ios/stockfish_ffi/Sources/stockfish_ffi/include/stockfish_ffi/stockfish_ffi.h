// C interface of the OpenReview Stockfish bridge (see sf_bridge.cpp).
#ifndef STOCKFISH_FFI_H
#define STOCKFISH_FFI_H

#ifdef __cplusplus
extern "C" {
#endif

int sf_start(void);
void sf_send(const char* command);
char* sf_read_line(int timeout_ms);
void sf_free(char* p);
int sf_is_running(void);
void sf_join(void);
const char* sf_version(void);

#ifdef __cplusplus
}
#endif

#endif
