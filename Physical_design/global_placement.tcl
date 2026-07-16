#===============================================================
# global_placement.tcl
# Stage 3: global placement -- assigns every cell a rough (x, y)
# coordinate, optimizing for wirelength within density limits.
# Does NOT yet snap cells to the legal site/row grid -- that's
# detailed placement (next stage).
#===============================================================
#
# USAGE: openroad global_placement.tcl
#---------------------------------------------------------------
source powerplan.tcl

# -density 0.6: cap on local-region cell density, set modestly
#   above the actual utilization (~51.5%) to give the optimizer
#   room to work. NOTE: the tool auto-adjusted this to 0.68 at
#   runtime (GPL-0302 warning) because -pad_left/-pad_right below
#   inflate the *effective* area used in the density calculation
#   (real cell area is unchanged -- only the accounting for
#   available free space shrinks), pushing the achievable minimum
#   density above the requested 0.6.
# -pad_left/-pad_right 2: reserves empty site-columns on both
#   sides of every cell, leaving room for the router to draw wires
#   between adjacent cells' pins.
# -timing_driven intentionally omitted: this design has large
#   timing margin (~7.5ns slack at a 10ns clock from earlier STA),
#   so plain wirelength-driven placement is sufficient for a first
#   pass -- no evidence timing-aware placement is needed here.
global_placement -density 0.6 -pad_left 2 -pad_right 2

write_def global_placement.def

#---------------------------------------------------------------
# FINDINGS
#---------------------------------------------------------------
# Converged at iteration 382, overflow 0.0988 (~legal).
# Final HPWL (half-perimeter wirelength) estimate: ~3380.68 um.
#   NOTE on units: this is already in um, not raw DBU needing
#   conversion -- confirmed by sanity-checking average wire length
#   per net (3380.68 / 164 nets =~ 20.6 um/net, physically
#   reasonable against a ~77x76um core; the alternate reading of
#   ~3.38um total would imply ~20nm/net, smaller than a single
#   standard cell -- not physically possible).
# report_wire_length is NOT the right tool for this stage's
#   wirelength estimate -- it's a global-routing-stage command
#   (GRT error namespace) and requires an actual routed net
#   (-net argument, GRT-0238) which doesn't exist yet at placement
#   time. Use global_placement's own inline HPWL log instead.
