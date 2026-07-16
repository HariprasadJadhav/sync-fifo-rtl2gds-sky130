#===============================================================
# sta_final.tcl
# Final, sign-off-quality timing check: a FRESH OpenROAD/STA
# session reading back the real extracted parasitics (fifo.spef)
# against the fully-implemented post-route netlist. This is the
# only STA result in the whole project based on real routed wire
# geometry rather than estimation.
#===============================================================
#
# USAGE: openroad sta_final.tcl
#
# Deliberately NOT sourcing detailed_route.tcl -- a long-lived
# session accumulates state (from global_placement, CTS, routing,
# etc.) that could quietly influence report_checks results in ways
# that don't reflect a clean read of the actual SPEF data. Starting
# fresh guarantees these numbers come only from: liberty timing +
# SDC constraints + real extracted parasitics.
#---------------------------------------------------------------

# Metal layer / routing rules for this process
read_lef /home/hariprasadjadhav/asic/pdks/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__nom.tlef

# Physical description of every standard cell (width, height, pins)
read_lef /home/hariprasadjadhav/asic/pdks/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef

# Timing data (same file you already used in sta_run.tcl)
read_liberty /home/hariprasadjadhav/asic/pdks/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib

# Must be the POST-ROUTE netlist (write_verilog run after CTS/
# legalization/tapcell/filler placement), not the original
# synth.ys output -- the SPEF has parasitic data for nets
# connected to tie cells, CTS buffers, dummy loads, tap cells, and
# filler cells, none of which exist in the synthesis-only netlist.
read_verilog syn_fifo_netlist_postroute.v
link_design syn_fifo
read_sdc syn_fifo.sdc
read_spef fifo.spef

# Required again in this fresh session -- set_propagated_clock is
# session-scoped, does not carry over from the cts.tcl/cts_
# legalized.tcl session it was originally set in. Forgetting this
# here silently reverts the clock path to the "ideal" (zero-delay)
# assumption even though real routed-clock parasitics are loaded,
# which visibly distorted an earlier draft of this report (reg2reg
# paths incorrectly appeared worse than I/O-bound paths, the
# opposite of every other stage's result, until this was added).
set_propagated_clock [get_clocks clk]

report_checks -path_delay max -path_group clk -group_path_count 5
report_checks -path_delay min -path_group clk -group_path_count 5

#---------------------------------------------------------------
# FINAL SIGN-OFF RESULTS (real extracted parasitics, tt corner,
# 10ns / 100MHz clock, tap+filler cells included)
#---------------------------------------------------------------
# Worst setup slack: 5.69ns MET (I/O-bound path, rd_en -> underflow)
# Worst reg2reg setup slack: 6.22ns MET -- confirms, as at every
#   earlier stage, that the true bottleneck is the assumed 2ns I/O
#   timing budget, not this FIFO's internal logic.
# Worst hold slack: 0.58ns MET (real clock latency ~0.36ns cancels
#   between launch/capture on reg2reg paths, as expected).
#
# Achievable frequency under the assumed 2ns I/O delay budget:
#   period ~= 10 - 5.69 = 4.31ns -> ~232 MHz.
# (A separate, tighter-period STA run can find the exact edge by
#  bisection -- see syn_fifo.sdc's FINDINGS section for the method
#  used pre-routing, which found ~4.17ns/240MHz; post-routing the
#  true edge will be marginally different given the small real
#  wire-delay increases seen here.)
