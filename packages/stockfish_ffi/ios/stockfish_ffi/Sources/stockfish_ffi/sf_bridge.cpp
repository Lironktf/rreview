// rreview Stockfish bridge.
//
// Runs an unmodified Stockfish UCI loop on a background thread inside the host
// process. Instead of pipes or dup2 (fragile on iOS), the process-wide
// std::cin / std::cout / std::cerr stream buffers are replaced with in-memory
// queues owned by this file. Dart talks UCI text through sf_send / sf_read_line.
//
// Only one engine instance per process is supported, which is all the app needs.
//
// SPDX-License-Identifier: GPL-3.0-or-later (links against Stockfish, GPLv3).

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <iostream>
#include <memory>
#include <mutex>
#include <streambuf>
#include <string>
#include <thread>

#include "Stockfish/src/attacks.h"
#include "Stockfish/src/misc.h"
#include "Stockfish/src/position.h"
#include "Stockfish/src/tune.h"
#include "Stockfish/src/uci.h"
#include "include/stockfish_ffi/stockfish_ffi.h"

#if defined(_WIN32)
#define SF_EXPORT __declspec(dllexport)
#else
#define SF_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

namespace {

// A blocking line source: Dart pushes whole commands, the engine's getline()
// consumes them one at a time.
class InputBuffer : public std::streambuf {
public:
    void push(std::string line) {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            line.push_back('\n');
            queue_.push_back(std::move(line));
        }
        cv_.notify_all();
    }

    void close() {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            closed_ = true;
        }
        cv_.notify_all();
    }

protected:
    int_type underflow() override {
        if (gptr() < egptr())
            return traits_type::to_int_type(*gptr());
        std::unique_lock<std::mutex> lock(mutex_);
        cv_.wait(lock, [this] { return !queue_.empty() || closed_; });
        if (queue_.empty())
            return traits_type::eof();
        current_ = std::move(queue_.front());
        queue_.pop_front();
        char* begin = current_.data();
        setg(begin, begin, begin + current_.size());
        return traits_type::to_int_type(*gptr());
    }

private:
    std::mutex              mutex_;
    std::condition_variable cv_;
    std::deque<std::string> queue_;
    std::string             current_;
    bool                    closed_ = false;
};

// Collects the engine's output into complete lines.
class OutputBuffer : public std::streambuf {
public:
    // Returns false on timeout.
    bool pop(std::string& out, int timeout_ms) {
        std::unique_lock<std::mutex> lock(mutex_);
        if (!cv_.wait_for(lock, std::chrono::milliseconds(timeout_ms),
                          [this] { return !lines_.empty(); }))
            return false;
        out = std::move(lines_.front());
        lines_.pop_front();
        return true;
    }

    void push_line(std::string line) {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            lines_.push_back(std::move(line));
        }
        cv_.notify_all();
    }

protected:
    int_type overflow(int_type ch) override {
        if (traits_type::eq_int_type(ch, traits_type::eof()))
            return traits_type::not_eof(ch);
        put(traits_type::to_char_type(ch));
        return ch;
    }

    std::streamsize xsputn(const char* s, std::streamsize n) override {
        for (std::streamsize i = 0; i < n; ++i)
            put(s[i]);
        return n;
    }

private:
    void put(char c) {
        if (c == '\n') {
            std::string done;
            {
                std::lock_guard<std::mutex> lock(partial_mutex_);
                done = std::move(partial_);
                partial_.clear();
            }
            push_line(std::move(done));
        } else if (c != '\r') {
            std::lock_guard<std::mutex> lock(partial_mutex_);
            partial_.push_back(c);
        }
    }

    std::mutex              partial_mutex_;
    std::string             partial_;
    std::mutex              mutex_;
    std::condition_variable cv_;
    std::deque<std::string> lines_;
};

std::mutex        g_state_mutex;
InputBuffer*      g_in     = nullptr;
OutputBuffer*     g_out    = nullptr;
std::thread*      g_thread = nullptr;
std::atomic<bool> g_running{false};
std::streambuf*   g_old_cin  = nullptr;
std::streambuf*   g_old_cout = nullptr;
std::streambuf*   g_old_cerr = nullptr;
bool              g_tables_initialised = false;

void engine_thread_main(OutputBuffer* out) {
    {
        // Mirrors Stockfish's main(): one-time table initialisation.
        std::lock_guard<std::mutex> lock(g_state_mutex);
        if (!g_tables_initialised) {
            Stockfish::Attacks::init();
            Stockfish::Position::init();
            g_tables_initialised = true;
        }
    }
    static char arg0[] = "stockfish";
    char*       argv[] = {arg0, nullptr};
    auto        cli    = Stockfish::CommandLine(1, argv);
    {
        auto uci = std::make_unique<Stockfish::UCIEngine>(std::move(cli));
        Stockfish::Tune::init(uci->engine_options());
        out->push_line("info string rreview bridge ready, " + Stockfish::engine_info());
        uci->loop();
    }
    out->push_line("quitok");
    g_running = false;
}

}  // namespace

extern "C" {

/// Starts the engine thread. Returns 1 on success, 0 if already running.
SF_EXPORT int sf_start(void) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    if (g_running)
        return 0;
    if (g_thread) {
        if (g_thread->joinable())
            g_thread->join();
        delete g_thread;
        g_thread = nullptr;
    }
    delete g_in;
    delete g_out;
    g_in  = new InputBuffer();
    g_out = new OutputBuffer();
    if (!g_old_cin) {
        g_old_cin  = std::cin.rdbuf();
        g_old_cout = std::cout.rdbuf();
        g_old_cerr = std::cerr.rdbuf();
    }
    std::cin.rdbuf(g_in);
    std::cout.rdbuf(g_out);
    std::cerr.rdbuf(g_out);
    g_running = true;
    g_thread  = new std::thread(engine_thread_main, g_out);
    return 1;
}

/// Queues one UCI command line (without the trailing newline).
SF_EXPORT void sf_send(const char* command) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    if (g_in && command)
        g_in->push(std::string(command));
}

/// Blocks up to timeout_ms for the next output line. Returns a malloc'd C
/// string (free with sf_free) or NULL on timeout / when no engine exists.
SF_EXPORT char* sf_read_line(int timeout_ms) {
    OutputBuffer* out;
    {
        std::lock_guard<std::mutex> lock(g_state_mutex);
        out = g_out;
    }
    if (!out)
        return nullptr;
    std::string line;
    if (!out->pop(line, timeout_ms))
        return nullptr;
    char* result = static_cast<char*>(std::malloc(line.size() + 1));
    if (!result)
        return nullptr;
    std::memcpy(result, line.data(), line.size());
    result[line.size()] = '\0';
    return result;
}

SF_EXPORT void sf_free(char* p) { std::free(p); }

/// 1 while the engine thread is alive.
SF_EXPORT int sf_is_running(void) { return g_running ? 1 : 0; }

/// Waits for the engine thread to finish after a "quit" command.
SF_EXPORT void sf_join(void) {
    std::thread* t = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_state_mutex);
        t        = g_thread;
        g_thread = nullptr;
        if (g_in)
            g_in->close();
    }
    if (t) {
        if (t->joinable())
            t->join();
        delete t;
    }
}

/// Engine name and version string, e.g. "Stockfish 19".
SF_EXPORT const char* sf_version(void) {
    static std::string v = Stockfish::engine_info();
    return v.c_str();
}

}  // extern "C"
