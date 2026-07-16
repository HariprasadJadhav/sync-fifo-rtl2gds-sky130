#===============================================================
# cts_legalized.tcl
# Stage 6: re-legalizes placement after CTS. This step is easy to
# skip by mistake -- and skipping it was the actual root cause of
# a full debugging investigation (see notes below).
#===============================================================
#
# USAGE: openroad cts_legalized.tcl
#---------------------------------------------------------------
source cts.tcl

# Re-running detailed_placement here is safe: it only nudges
# already-legal cells minimally to accommodate the newly-added
# CTS cells, using the same diamond-search legalizer already
# proven (100% success) on the original 150 cells.
detailed_placement
check_placement -verbose

# Legalization can shift buffer positions slightly, which can
# change wire lengths/delays -- so skew and timing must be
# re-checked here rather than trusting the pre-legalization
# numbers from cts.tcl.
report_clock_skew
report_checks -path_delay max -path_group clk -group_path_count 5

global_connect -verbose #for lvs

write_def cts_legalized.def

#---------------------------------------------------------------
# FINDINGS / ROOT CAUSE NOTE
#---------------------------------------------------------------
# Before this fix: detailed_route consistently failed with
# DRT-0073 "No access point" errors on a specific, repeatable set
# of instances (clkbuf_3_0, clkbuf_3_1, clkbuf_3_3, clkbuf_3_5,
# clkbuf_3_6, clkbuf_3_7, and several clkload dummy-load cells) --
# always the SAME instance names regardless of buffer size
# (clkbuf_4 vs clkbuf_8 tested), CTS obstruction-awareness flag,
# or sink-clustering topology changes. This ruled out buffer
# sizing, obstruction-awareness, and tree topology as causes.
# GUI inspection confirmed a failing pin's shape did not align
# with the routing track grid.
#
# The actual cause: CTS-inserted cells were never legalized onto
# the site grid (CTS runs after detailed.tcl's one and only
# legalization pass). Adding this legalization step here resolved
# DRT-0073 completely -- confirmed by detailed_route.tcl afterward
# reporting 0 violations and 0 unmapped pin accesses
# (#stdCellPinNoAp = 0).
#
# Post-fix legalization cost: only 0.3um average displacement,
# 0% HPWL delta -- confirms CTS's placement was only slightly
# off-grid, not grossly wrong, which is why the symptom was subtle
# enough to require this investigation to find.
