# PYNQ-Z2 PL reference clock: 125 MHz from the Ethernet PHY.
set_property PACKAGE_PIN H16 [get_ports sys_clk_125mhz]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk_125mhz]
create_clock -name sys_clk_125mhz -period 8.000 [get_ports sys_clk_125mhz]

# Board push buttons. BTN0 resets and restarts the design.
set_property PACKAGE_PIN D19 [get_ports {btn[0]}]
set_property PACKAGE_PIN D20 [get_ports {btn[1]}]
set_property PACKAGE_PIN L20 [get_ports {btn[2]}]
set_property PACKAGE_PIN L19 [get_ports {btn[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {btn[*]}]

# Board slide switches. SW0 selects the displayed 16-bit half.
set_property PACKAGE_PIN M20 [get_ports {sw[0]}]
set_property PACKAGE_PIN M19 [get_ports {sw[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[*]}]

# Board LEDs, active high.
set_property PACKAGE_PIN R14 [get_ports {led[0]}]
set_property PACKAGE_PIN P14 [get_ports {led[1]}]
set_property PACKAGE_PIN N16 [get_ports {led[2]}]
set_property PACKAGE_PIN M14 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]
set_property DRIVE 8 [get_ports {led[*]}]
set_property SLEW SLOW [get_ports {led[*]}]

# EES_363DP Arduino daughterboard common-anode display.
# daughter_seg_n is {DP,G,F,E,D,C,B,A}; all segment outputs are active low.
set_property PACKAGE_PIN H15 [get_ports {daughter_seg_n[0]}]
set_property PACKAGE_PIN F16 [get_ports {daughter_seg_n[1]}]
set_property PACKAGE_PIN T15 [get_ports {daughter_seg_n[2]}]
set_property PACKAGE_PIN V17 [get_ports {daughter_seg_n[3]}]
set_property PACKAGE_PIN U17 [get_ports {daughter_seg_n[4]}]
set_property PACKAGE_PIN T12 [get_ports {daughter_seg_n[5]}]
set_property PACKAGE_PIN V15 [get_ports {daughter_seg_n[6]}]
set_property PACKAGE_PIN R16 [get_ports {daughter_seg_n[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {daughter_seg_n[*]}]
set_property DRIVE 8 [get_ports {daughter_seg_n[*]}]
set_property SLEW SLOW [get_ports {daughter_seg_n[*]}]

# Digit enables K1..K4 use PNP high-side drivers and are active low.
set_property PACKAGE_PIN V13 [get_ports {daughter_digit_n[0]}]
set_property PACKAGE_PIN U13 [get_ports {daughter_digit_n[1]}]
set_property PACKAGE_PIN U12 [get_ports {daughter_digit_n[2]}]
set_property PACKAGE_PIN T14 [get_ports {daughter_digit_n[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {daughter_digit_n[*]}]
set_property DRIVE 8 [get_ports {daughter_digit_n[*]}]
set_property SLEW SLOW [get_ports {daughter_digit_n[*]}]

set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
