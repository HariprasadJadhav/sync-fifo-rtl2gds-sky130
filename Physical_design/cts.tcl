#===============================================================
# cts.tcl
# Stage 5: Clock Tree Synthesis -- builds a real buffered tree
# (root -> branch buffers -> leaf buffers -> each flip-flop) so
# the clock reaches all 80 flip-flops with minimal skew. Replaces
# every earlier STA report's "clock network delay (ideal)"
# assumption with a real, physically buffered network.
#===============================================================
#
# USAGE: openroad cts.tcl
#---------------------------------------------------------------
source detailed_placement.tcl

# Dedicated clock-routing layer: NOT met1 (already the most
# congested layer -- local cell rows/rails live there), and
# distinct from met2/met3 (I/O pins) and met4/met5 (power straps/
# ring). met3 is a reasonable, relatively clear mid layer for the
# clock tree specifically.
set_wire_rc -clock -layer met3

# Buffer list gives the tool a small range of drive strengths to
# choose from (not just one -- CTS needs range to characterize
# delay-vs-wirelength curves; a too-narrow list, e.g. just
# clkbuf_1+clkbuf_2, breaks CTS's own characterization step with
# CTS-0075). Root buffer is the single strongest in the list,
# since it alone drives the entire tree before any fanout --a weak
# root would bottleneck everything downstream of it.
clock_tree_synthesis -buf_list {sky130_fd_sc_hd__clkbuf_1 sky130_fd_sc_hd__clkbuf_2 sky130_fd_sc_hd__clkbuf_4} -root_buf sky130_fd_sc_hd__clkbuf_4

# Tells STA to stop assuming "ideal" (zero-delay) clock and use
# the real tree just built. Without this, all future timing
# checks silently keep using the optimistic ideal-clock numbers
# even though a real tree now exists.
set_propagated_clock [get_clocks clk]

report_clock_skew
report_cts
write_def cts.def

#---------------------------------------------------------------
# FINDINGS
#---------------------------------------------------------------
# 9 clock buffers inserted (sky130_fd_sc_hd__clkbuf_4 x9), 2
#   levels of buffering to every flop, max tree level 3.
# 7 dummy loads inserted (non-functional capacitive loads added
#   purely to balance branch loading across the tree, so all
#   branches present similar electrical load to their shared
#   parent buffer) -- explains "Sinks 87" in the CTS summary vs
#   80 real flip-flops (80 + 7 dummy = 87).
# setup skew: 0.00 (essentially perfect balance).
#
# IMPORTANT: CTS inserts brand-new physical cells (9 buffers + 7
#   dummy loads) that are placed using CTS's own H-tree topology
#   math -- NOT re-legalized onto the site grid. This was later
#   found to be the root cause of DRT-0073 "No access point"
#   errors during detailed routing, affecting only these
#   CTS-inserted cells (never the original 150 logic/tie cells,
#   which were legalized back in detailed.tcl). See
#   cts_legalized.tcl for the fix -- always run detailed_placement
#   again after CTS, before routing.
