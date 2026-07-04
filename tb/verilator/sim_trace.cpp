#include "sim_trace.h"

namespace sim {

Trace::~Trace() {
    close();
}

void Trace::dump(uint64_t time) {
    if (tfp_) tfp_->dump(time);
}

void Trace::close() {
    if (!tfp_) return;
    tfp_->close();
    delete tfp_;
    tfp_ = nullptr;
}

}  // namespace sim
