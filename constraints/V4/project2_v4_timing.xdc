# Clock definitions and CDC exceptions are supplied by the Clocking Wizard,
# MIG, FIFO Generator, and Ethernet IP constraints used by this project.

# The 125 MHz acquisition/Ethernet clock and MIG UI clock are generated through
# separate clock-management trees. All payload transfers between them use the
# asynchronous FIFO blocks; sticky status indications are synchronized
# explicitly. They therefore form asynchronous clock domains for STA.
set_clock_groups -asynchronous \
    -group [get_clocks clk_out2_clk_wiz_0] \
    -group [get_clocks clk_pll_i]
