#include "checker.h"

#include "checker_rv32.h"
#include "checker_src.h"

#include <memory>
#include <stdexcept>

namespace sim {

std::unique_ptr<Checker> make_checker(const Options& opt) {
    if (opt.mode == "rv32") {
        return std::make_unique<Rv32Checker>(opt);
    }
    if (opt.mode == "src") {
        if (opt.src_checker == "ledseg") {
            return std::make_unique<SrcLedSegChecker>(opt);
        }
        if (opt.src_checker == "observe") {
            return std::make_unique<SrcObserveChecker>(opt);
        }
        if (opt.src_checker == "memcnt") {
            return std::make_unique<SrcMemCntChecker>(opt);
        }
        if (opt.src_checker == "lampseg") {
            return std::make_unique<SrcLampSegChecker>(opt);
        }
        throw std::runtime_error("unknown src checker: " + opt.src_checker);
    }
    throw std::runtime_error("unknown mode: " + opt.mode);
}

}  // namespace sim
