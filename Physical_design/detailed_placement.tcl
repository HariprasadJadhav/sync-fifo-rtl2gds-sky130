#===============================================================
# detailed_placement.tcl
# Stage 4: detailed placement (legalization) -- snaps every cell
# from global placement's continuous coordinates onto the nearest
# legal site/row position, resolving any remaining overlaps.
#===============================================================
#
# USAGE: openroad detailed_placement.tcl
#---------------------------------------------------------------
source global_placement.tcl

detailed_placement

# check_placement is SILENT on a clean pass (no violations) --
# confirmed genuine (not a broken command) by deliberately
# mis-placing a cell with place_inst and re-running: the checker
# correctly reported the exact instance and coordinate of the
# injected violation, both via -verbose to the terminal and via
# -report_file_name as a JSON report.
check_placement -verbose

write_def detailed_placement.def

#---------------------------------------------------------------
# FINDINGS
#---------------------------------------------------------------
# Diamond Move Success: 150/150 (100%), 0 placement failures.
# original HPWL 3382.0 um -> legalized HPWL 4033.8 um (+19%).
#   This increase is EXPECTED and normal -- legalization trades
#   placement optimality for grid legality. A clean run (100%
#   diamond-move success, no rip-up-and-replace fallback) like
#   this one indicates the ~19% cost is typical for this
#   utilization, not a sign of a struggling placement (much higher
#   utilization designs typically see a larger penalty here, or
#   outright placement failures).
