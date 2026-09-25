# Clock definitions and CDC exceptions are supplied by the Clocking Wizard,
# MIG, FIFO Generator, and Ethernet IP constraints used by this project.

# The 125 MHz acquisition/Ethernet clock and MIG UI clock are generated through
# separate clock-management trees. All payload transfers between them use the
# asynchronous FIFO blocks; sticky status indications are synchronized
# explicitly. They therefore form asynchronous clock domains for STA.
set acquisition_clocks [get_clocks -quiet clk_out2_clk_wiz_0]
set ddr_ui_clocks [get_clocks -quiet clk_pll_i]

# During out-of-context/top-level synthesis the generated clock objects may not
# exist yet.  Vivado rereads this XDC during implementation after the IP clock
# constraints have created them, so apply the exception only when both objects
# are available instead of producing a misleading critical warning.
if {[llength $acquisition_clocks] > 0 && [llength $ddr_ui_clocks] > 0} {
    set_clock_groups -asynchronous \
        -group $acquisition_clocks \
        -group $ddr_ui_clocks
}
