#include "sim_control.h"

#include <csignal>

namespace sim {
namespace {

volatile std::sig_atomic_t g_stop_signal = 0;

void handle_signal(int sig) {
    g_stop_signal = sig;
}

}  // namespace

void install_signal_handlers() {
    std::signal(SIGINT, handle_signal);
    std::signal(SIGTERM, handle_signal);
}

bool stop_requested() {
    return g_stop_signal != 0;
}

const char* stop_reason() {
    if (g_stop_signal == SIGINT) return "interrupted by SIGINT";
    if (g_stop_signal == SIGTERM) return "interrupted by SIGTERM";
    return "interrupted";
}

}  // namespace sim
