#===============================================================
# design_flow.tcl
# Complete physical implementation: floorplan -> power delivery ->
# placement -> clock tree synthesis -> routing -> parasitic
# extraction, for the synchronous FIFO, on OpenROAD / sky130.
#
# USAGE: openroad design_flow.tcl
#
# Single-file by design: this flow runs end-to-end in well under a
# minute for a design this small, so there's no real benefit to
# splitting it into per-stage files that need to be re-run in the
# right order and kept in sync -- that approach is exactly what
# caused several real bugs during development (stale DEF files,
# a Tcl trailing-comment parse error, uncertainty about which
# stage's output was current). One file, run top to bottom,
# eliminates that whole class of problem structurally.
#
# Reads its inputs directly from sibling stage directories rather
# than from local copies -- there is exactly one real copy of the
# synthesized netlist and the SDC anywhere in this repo.
#===============================================================

#---------------------------------------------------------------
# Load technology + design
#---------------------------------------------------------------
# Tech LEF MUST be read before the cell LEF: cell LEF pin geometry
# references metal layer names (met1, li1, ...) that only the tech
# LEF defines. Loading cell LEF first would mean those layer names
# don't exist yet when the parser hits them.
read_lef /home/hariprasadjadhav/asic/pdks/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__nom.tlef
read_lef /home/hariprasadjadhav/asic/pdks/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef

# tt (typical-typical) liberty corresponds to the "nom" (nominal)
# tech LEF corner -- process corners must be matched consistently
# across timing (.lib) and physical (.tlef) data. ff/ss liberty
# would need min/max tech LEF respectively (fast device + fast
# wire for hold; slow device + slow wire for setup).
read_liberty /home/hariprasadjadhav/asic/pdks/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib

read_verilog ../Synthesis_yosys/syn_fifo_netlist_sky130.v
link_design syn_fifo
read_sdc ../STA/syn_fifo.sdc

#===============================================================
# STAGE 1: Floorplan
#===============================================================
# utilization 50%: reasonable starting point for a small design
# with no macros and fairly dense wiring -- leaves headroom for
# routing without wasting silicon. aspect_ratio 1 = square core,
# since there's no directional I/O clustering need for this design.
# core_space 9um: sized so the PDN ring (Stage 2 below, which needs
# core_offset + 2*width + spacing = 2+2+2+2 = 8um) physically fits
# inside the die margin -- originally 2um, increased after hitting
# PDN-0351 "rings do not fit inside the die area."
# site unithd: single-height site, matches every cell in this
# design (all sky130_fd_sc_hd__* cells are single-height "hd" cells;
# unithddbl is for double-height cells, none used here).
initialize_floorplan -utilization 50 -aspect_ratio 1 -core_space 9 -site unithd

# Generates the routing track grid for every metal layer, using
# pitch/offset rules from the tech LEF. Required before place_pins,
# which snaps I/O pins onto specific track coordinates -- without
# this, place_pins errors with "Horizontal routing tracks not found".
make_tracks

# I/O pins placed here, BEFORE any standard-cell placement pass, so
# global placement's wirelength optimization can pull cells toward
# known pin locations. -annealing improves pin distribution quality
# vs. the tool's default heuristic (which clustered pins unevenly
# on a first pass without it).
place_pins -hor_layers met3 -ver_layers met2 -annealing

# Yosys/ABC's optimizer ties some internal signals to a constant 0
# or 1 rather than instantiating real logic for them. Those
# constant nets get tagged signal-type GROUND/POWER, which
# TritonRoute cannot route as an ordinary signal net (no real
# driver) -- fails with DRT-0305 "Net ... not routable, move to
# special nets." insert_tiecells adds an actual physical tie cell
# (conb_1) so the net has a genuine electrical source before
# routing is attempted.
insert_tiecells sky130_fd_sc_hd__conb_1/HI -prefix TIE_ONE_
insert_tiecells sky130_fd_sc_hd__conb_1/LO -prefix TIE_ZERO_

# Substrate/well body-tie cells, inserted every 15um along each
# row. Prevents latch-up in real silicon. Their VPB/VNB body-tie
# pins need explicit add_global_connection rules below (VPB/VNB
# are different pin names from the VPWR/VGND used by regular
# cells) -- confirmed missing via PDN-0189 warnings the first time
# this was run without those rules.
tapcell -tapcell_master sky130_fd_sc_hd__tap_1 -distance 15

report_design_area

# FINDINGS (Stage 1):
#   Die BBox:  (0,0) to (96.125, 96.125) um
#   Core BBox: (9.200, 10.880) to (86.940, 87.040) um -- lower-left
#     snapped from requested (9,9) since the core boundary must
#     align to whole site-grid units (site 0.46 x 2.72 um); this is
#     why the four margins end up slightly unequal.
#   Core area: 5920.678 um^2, instances area: 3051.677 um^2,
#     effective utilization 51.5% (not exactly 50%, same grid-
#     snapping effect).
#   I/O: 24 pins placed (10 scalar ports + 8b data_in + 8b
#     data_out), all with sinks, none dropped.
#   Tapcell: 75 tap cells inserted.

write_def floorplan.def

#===============================================================
# STAGE 2: Power Planning
#===============================================================
# Maps every cell's physical VPWR/VGND pins to the chip-wide nets
# VDD/VGND. NAMING step only -- no geometry yet.
add_global_connection -net VDD -pin_pattern "VPWR" -power
add_global_connection -net VGND -pin_pattern "VGND" -ground

# Tap cells use DIFFERENT pin names for their body-tie connections
# (VPB = n-well tie, VNB = p-well/substrate tie). Without these,
# tap cells sit in the layout with unconnected body ties
# (PDN-0189), which defeats their entire purpose.
add_global_connection -net VDD -pin_pattern "VPB" -power
add_global_connection -net VGND -pin_pattern "VNB" -ground

# A voltage domain bundles a power net + ground net under ONE
# name. define_pdn_grid below references this domain by NAME, not
# by the individual net names -- add_global_connection operates on
# net names (VDD/VGND); define_pdn_grid operates on domain names
# (CORE). Omitting -name here produced PDN-1032 "Unable to find
# VDD domain" the first time this was run.
set_voltage_domain -name CORE -power VDD -ground VGND

define_pdn_grid -name "core_grid" -starts_with POWER -voltage_domains {CORE}

# Straps on met4 (vertical) / met5 (horizontal) -- adjacent layers,
# perpendicular directions, so they physically cross and can be
# joined by vias. Chosen above met1 (already busy with local cell/
# row routing) and above met2/met3 (used for I/O pins).
add_pdn_stripe -grid "core_grid" -layer met4 -width 1.6 -pitch 27.14 -offset 13.57 -starts_with POWER
add_pdn_stripe -grid "core_grid" -layer met5 -width 1.6 -pitch 27.14 -offset 13.57 -starts_with POWER -extend_to_core_ring

# Ring around the core perimeter. Total radial space consumed =
# core_offset + width + spacing + width = 2+2+2+2 = 8um -- this is
# why Stage 1's core_space was increased to 9um.
add_pdn_ring -grid "core_grid" -layer {met4 met5} -widths 2.0 -spacings 2.0 -core_offsets 2.0

# Two overlapping metal shapes on different layers are NOT
# automatically electrically joined in real silicon -- a via is
# required, and vias are only placed where explicitly told to.
# Without these lines, straps/rings/rails could visually overlap
# in the layout while remaining electrically isolated pieces of
# metal.
add_pdn_connect -grid "core_grid" -layers {met1 met4}
add_pdn_connect -grid "core_grid" -layers {met4 met5}

pdngen

report_voltage_domains
report_global_connect

# FINDINGS (Stage 2):
#   4 global connection rules confirmed (VPWR->VDD, VGND->VGND,
#     VPB->VDD, VNB->VGND). pdngen completes with no ring-fit or
#     missing-domain errors.

write_def powerplan.def

#===============================================================
# STAGE 3: Global Placement
#===============================================================
# -density 0.6: cap on local-region cell density, set modestly
#   above actual utilization (~51.5%) for optimizer headroom. The
#   tool auto-adjusts this upward at runtime (GPL-0302) because
#   -pad_left/-pad_right below inflate the *effective* area used
#   in the density calculation (real cell area is unchanged --
#   only the free-space accounting shrinks).
# -pad_left/-pad_right 2: reserves empty site-columns on both
#   sides of every cell, leaving room for the router.
# -timing_driven intentionally omitted: this design has large
#   timing margin (~7.5ns slack at a 10ns clock), so plain
#   wirelength-driven placement is sufficient.
global_placement -density 0.6 -pad_left 2 -pad_right 2

# FINDINGS (Stage 3):
#   Converged at iteration 382, overflow ~0.099 (legal). Final HPWL
#   estimate ~3382.68 um (this figure is already in um -- verified
#   by sanity-checking average wire length per net against the
#   ~77x76um core, not raw DBU needing further conversion).
#   Note: report_wire_length is NOT valid at this stage -- it's a
#   global-routing-stage command (GRT-0238 requires -net, and no
#   net is routed yet) -- use global_placement's own inline HPWL
#   log instead.

write_def global_placement.def

#===============================================================
# STAGE 4: Detailed Placement (Legalization)
#===============================================================
detailed_placement

# check_placement is SILENT on a clean pass -- confirmed genuine
# (not a broken/no-op command) by deliberately mis-placing a cell
# with place_inst and re-running: the checker correctly reported
# the exact instance and coordinate of the injected violation.
check_placement -verbose

# FINDINGS (Stage 4):
#   Diamond Move Success: 150/150 (100%), 0 placement failures.
#   original HPWL 3382.0 um -> legalized HPWL 4033.8 um (+19%).
#   This increase is EXPECTED -- legalization trades placement
#   optimality for grid legality; a clean run (100% success, no
#   rip-up-and-replace fallback) indicates this cost is typical
#   for this utilization, not a struggling placement.

write_def detailed_placement.def

#===============================================================
# STAGE 5: Clock Tree Synthesis
#===============================================================
# Dedicated clock-routing layer: NOT met1 (most congested -- local
# cell rows/rails), distinct from met2/met3 (I/O) and met4/met5
# (power). met3 is a relatively clear mid layer for the clock tree.
set_wire_rc -clock -layer met3

# Buffer list gives the tool a small range of drive strengths (not
# just one -- CTS needs range to characterize delay-vs-wirelength
# curves; a too-narrow list, e.g. just clkbuf_1+clkbuf_2, breaks
# CTS's own characterization step with CTS-0075). Root buffer is
# the strongest in the list, since it alone drives the entire tree
# before any fanout -- a weak root would bottleneck everything.
clock_tree_synthesis -buf_list {sky130_fd_sc_hd__clkbuf_1 sky130_fd_sc_hd__clkbuf_2 sky130_fd_sc_hd__clkbuf_4} -root_buf sky130_fd_sc_hd__clkbuf_4

# Tells STA to stop assuming "ideal" (zero-delay) clock and use the
# real tree just built. Without this, later timing checks silently
# keep using optimistic ideal-clock numbers even though a real tree
# now exists.
set_propagated_clock [get_clocks clk]

report_clock_skew
report_cts

# FINDINGS (Stage 5):
#   9 clock buffers inserted (clkbuf_4 x9), 2 levels of buffering
#   to every flop, max tree level 3. 7 dummy loads inserted
#   (non-functional capacitive loads added purely to balance branch
#   loading) -- explains "Sinks 87" vs 80 real flip-flops in the
#   CTS summary (80 + 7 = 87). setup skew: 0.00 (essentially
#   perfect balance).
#
#   IMPORTANT: CTS inserts brand-new physical cells (9 buffers + 7
#   dummy loads) placed using its own H-tree topology math -- these
#   are NOT automatically re-legalized onto the site grid. This was
#   the actual root cause of DRT-0073 "No access point" errors
#   during detailed routing later in this flow, and was found only
#   after systematically ruling out buffer size, CTS obstruction-
#   awareness, tree topology, cell orientation, and physical
#   position -- all identical between failing and passing
#   instances. GUI inspection then showed a failing pin's shape not
#   aligned to the routing track grid, consistent with an
#   unlegalized position. Stage 6 below is the fix: always
#   re-legalize after CTS.

write_def cts.def

#===============================================================
# STAGE 6: Post-CTS Re-legalization
#===============================================================
# Safe to call again here: only nudges already-legal cells
# minimally to accommodate the newly-added CTS cells, using the
# same diamond-search legalizer already proven (100% success) on
# the original 150 cells in Stage 4.
detailed_placement
check_placement -verbose

# Re-applies the Stage 2 global connection rules to every instance
# CURRENTLY in the design, including the CTS buffers/dummy loads
# that didn't exist when Stage 2 first ran. Without this, LVS
# comparison later showed CTS cells' power pins as dozens of tiny
# orphaned "dummy_*" nets instead of being merged into the real
# VDD/VGND nets -- a genuine gap in the physical database's power
# connectivity, not just a reporting artifact.
global_connect -verbose

# Legalization can shift buffer positions slightly, changing wire
# lengths/delays -- re-check skew/timing here rather than trusting
# Stage 5's pre-legalization numbers.
report_clock_skew
report_checks -path_delay max -path_group clk -group_path_count 5

# FINDINGS (Stage 6):
#   Post-fix legalization cost: only 0.3um average displacement, 0%
#   HPWL delta -- confirms CTS's placement was only slightly
#   off-grid, not grossly wrong, which is why this required
#   systematic investigation rather than being visually obvious.
#   Fixing this resolved DRT-0073 completely -- confirmed later by
#   detailed_route reporting 0 violations and 0 unmapped pin
#   accesses (#stdCellPinNoAp = 0).

write_def cts_legalized.def

#===============================================================
# STAGE 7: Global Routing
#===============================================================
# -guide_file: writes the routing guide for detailed_route to use.
# -congestion_report_file: direct congestion metric from
#   global_route itself.
global_route -guide_file route.guide -congestion_report_file congestion.rpt

# FINDINGS (Stage 7):
#   Given low utilization (~51.5%) and small net count (164-174
#   nets depending on stage), congestion was never a concern --
#   confirmed no congestion warnings in the log.

write_def global_route.def

#===============================================================
# STAGE 8: Detailed Routing, Fillers, Extraction
#===============================================================
# Commits to exact metal-layer geometry (tracks, vias, DRC-legal
# spacing) for every net.
detailed_route

# Fills remaining empty row gaps with non-functional filler cells.
# Required for manufacturing (rows need continuous diffusion).
# Multiple sizes given so the tool can close gaps of any width
# efficiently, same "give the tool a range" reasoning as the CTS
# buffer list.
filler_placement {sky130_fd_sc_hd__fill_1 sky130_fd_sc_hd__fill_2 sky130_fd_sc_hd__fill_4 sky130_fd_sc_hd__fill_8}
check_placement -verbose

# Fresh netlist dump AFTER every physical cell exists in its final
# form (tie cells, tap cells, CTS buffers/dummy loads, fillers).
# Two flags matter, both found by debugging real LVS mismatches
# against the Magic-extracted layout netlist:
#   -remove_cells {fill_*, tap_1}: tap/filler cells have no active
#     devices (tap = plain substrate/well contact, fill = dummy
#     diffusion/poly for density rules only) -- Magic's ext2spice
#     correctly extracts NONE of them from the real layout, so
#     including them here caused a device-count mismatch (246 vs
#     167) from comparing non-functional bookkeeping cells that
#     were never meant to be compared.
#   -include_pwr_gnd: without this, VPWR/VGND pin connections are
#     left implicit/unlisted, and LVS reads each unlisted pin as
#     its own orphaned single-pin net instead of merging them into
#     the real shared VDD/VGND nets -- caused a large net-count
#     mismatch (846 vs 212 nets) that had nothing to do with real
#     connectivity.
write_verilog -include_pwr_gnd -remove_cells {sky130_fd_sc_hd__fill_1 sky130_fd_sc_hd__fill_2 sky130_fd_sc_hd__fill_4 sky130_fd_sc_hd__fill_8 sky130_fd_sc_hd__tap_1} syn_fifo_netlist_postroute.v

# Loads the OpenRCX extraction rules for this process corner ("nom"
# -- matches tt liberty / nom tech LEF used throughout). The
# documented replacement command (set_extraction_rules_file, per
# the -ext_model_file deprecation warning) does not actually exist
# on this OpenROAD build (confirmed via `help
# set_extraction_rules_file` returning "no commands match") --
# define_process_corner is the real, working command here.
define_process_corner -ext_model_index 0 /home/hariprasadjadhav/asic/pdks/share/pdk/sky130A/libs.tech/librelane/rules.openrcx.sky130A.nom.spef_extractor

# -ext_model_file is deprecated per this build's own warning, but
# empirically still works (unlike the documented replacement) --
# used here as the confirmed-working path.
extract_parasitics -ext_model_file /home/hariprasadjadhav/asic/pdks/share/pdk/sky130A/libs.tech/librelane/rules.openrcx.sky130A.nom.spef_extractor

write_spef fifo.spef
write_def detailed_route.def

# FINDINGS (Stage 8):
#   Final detailed_route result: 0 violations, full completion in
#     4 optimization iterations.
#   Pin access: #stdCellPinNoAp = 0 -- confirms the Stage 6 fix
#     fully resolved the earlier DRT-0073 failures.
#   452 filler instances placed. Total routed wire length ~6128 um
#     across li1/met1/met2/met3 (met4/met5 carry only the power
#     grid here, no signal routing landed there).
#   check_antennas (run separately, see post_routing_sta.tcl or an
#     interactive session): PASSED, no violations.
#
#   For final, trustworthy post-routing timing, do NOT trust
#   report_checks run in this same long-lived session -- start a
#   fresh STA session (see sta_final.tcl) reading back
#   outputs/syn_fifo_netlist_postroute.v (NOT the synthesis-only
#   netlist -- this one includes tie/tap/CTS cells) against
#   outputs/fifo.spef, with set_propagated_clock re-applied (it is
#   session-scoped and does not carry over).

# Power estimate, using the real extracted parasitics above rather
# than a pre-route estimate.
report_power
