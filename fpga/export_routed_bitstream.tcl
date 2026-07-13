# Export a bitstream from an existing routed implementation checkpoint.
# Usage:
#   vivado -mode batch -source fpga/export_routed_bitstream.tcl -tclargs \
#          <project.xpr> <routed.dcp> <output.bit>

if {[llength $argv] < 3} {
    error "usage: export_routed_bitstream.tcl <project.xpr> <routed.dcp> <output.bit>"
}

set project_file [file normalize [lindex $argv 0]]
set routed_dcp   [file normalize [lindex $argv 1]]
set output_bit   [file normalize [lindex $argv 2]]

open_project $project_file
open_checkpoint $routed_dcp
file mkdir [file dirname $output_bit]

report_drc -file "${output_bit}.drc.rpt"
write_bitstream -force $output_bit
puts "BITSTREAM_FILE=$output_bit"
