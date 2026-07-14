# Paths are relative to the repository root. Packages are pulled in first by
# the existing core filelist; the PYNQ board wrapper is deliberately last.
-f scripts/filelists/core.f

rtl/soc/seg7.sv
rtl/soc/display_seg.sv
rtl/soc/counter.sv
rtl/soc/DramBramAdapter.sv
rtl/soc/SocMemBridge.sv
rtl/soc/student_top.sv

fpga/test_prj/pynq_top.sv
