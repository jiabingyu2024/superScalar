#ifndef TB_VERILATOR_CHECKER_SRC_H
#define TB_VERILATOR_CHECKER_SRC_H

#include "checker.h"
#include "sim_display.h"

namespace sim {

class SrcLedSegChecker : public Checker {
public:
    explicit SrcLedSegChecker(const Options& opt) : opt_(opt) {}
    std::string kind() const override { return "src_ledseg"; }
    void pre_tick(uint64_t cycle, const Request& req, const MemoryModel& mem,
                  SimResult& result) override;
    void post_tick(uint64_t cycle, const Request& req, const MemoryModel& mem,
                   SimResult& result) override;
    bool done() const override { return done_; }

private:
    const Options& opt_;
    VirtualSegDecoder seg_decoder_;
    bool done_ = false;
};

class SrcLedOnlyChecker : public Checker {
public:
    explicit SrcLedOnlyChecker(const Options& opt) : opt_(opt) {}
    std::string kind() const override { return "src_ledonly"; }
    void pre_tick(uint64_t cycle, const Request& req, const MemoryModel& mem,
                  SimResult& result) override;
    void post_tick(uint64_t cycle, const Request& req, const MemoryModel& mem,
                   SimResult& result) override;
    bool done() const override { return done_; }

private:
    const Options& opt_;
    bool done_ = false;
};

class SrcObserveChecker : public Checker {
public:
    explicit SrcObserveChecker(const Options& opt) : opt_(opt) {}
    std::string kind() const override { return "src_observe"; }
    void pre_tick(uint64_t cycle, const Request& req, const MemoryModel& mem,
                  SimResult& result) override;
    void post_tick(uint64_t cycle, const Request& req, const MemoryModel& mem,
                   SimResult& result) override;
    bool done() const override { return false; }

protected:
    void observe_counter_write(const Request& req, SimResult& result);
    const Options& opt_;
};

class SrcMemCntChecker : public SrcObserveChecker {
public:
    explicit SrcMemCntChecker(const Options& opt) : SrcObserveChecker(opt) {}
    std::string kind() const override { return "src_memcnt"; }
    void pre_tick(uint64_t cycle, const Request& req, const MemoryModel& mem,
                  SimResult& result) override;
    bool done() const override { return done_; }

private:
    bool done_ = false;
};

class SrcLampSegChecker : public SrcObserveChecker {
public:
    explicit SrcLampSegChecker(const Options& opt) : SrcObserveChecker(opt) {}
    std::string kind() const override { return "src_lampseg"; }
    void pre_tick(uint64_t cycle, const Request& req, const MemoryModel& mem,
                  SimResult& result) override;
    void post_tick(uint64_t cycle, const Request& req, const MemoryModel& mem,
                   SimResult& result) override;
    bool done() const override { return done_; }

private:
    bool done_ = false;
};

}  // namespace sim

#endif  // TB_VERILATOR_CHECKER_SRC_H
