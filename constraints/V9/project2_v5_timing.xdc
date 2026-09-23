# Clock definitions and CDC exceptions are supplied by the Clocking Wizard,
# MIG, FIFO Generator, and Ethernet IP constraints used by this project.

# The 125 MHz acquisition/Ethernet clock and MIG UI clock are generated through
# separate clock-management trees. All payload transfers between them use the
# course asynchronous FIFO blocks; sticky status indications are synchronized
# explicitly. They therefore form asynchronous clock domains for STA.
#
# Vivado 2018.3 does not support Tcl `if` commands inside an XDC file. The
# generated clocks also do not exist during every XDC read. The asynchronous
# clock grouping is consequently applied, with an explicit one-clock check,
# by scripts/apply_post_link_constraints.tcl at implementation opt-design PRE.
