#ifndef TB_VERILATOR_SIM_CONTROL_H
#define TB_VERILATOR_SIM_CONTROL_H

namespace sim {

void install_signal_handlers();
bool stop_requested();
const char* stop_reason();

}  // namespace sim

#endif  // TB_VERILATOR_SIM_CONTROL_H
