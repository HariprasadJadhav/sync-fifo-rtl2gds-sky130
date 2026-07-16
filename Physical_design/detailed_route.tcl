#===============================================================
# detailed_route.tcl
# Stage 8 (final physical stage): detailed routing -- commits to
# exact metal-layer geometry (tracks, vias, DRC-legal spacing) for
# every net. Followed by filler placement and real parasitic
# extraction from the actual routed wires.
#===============================================================
#
# USAGE: openroad detailed_route.tcl
#---------------------------------------------------------------
source global_route.tcl

# TritonRoute commits to real geometry here -- this is the stage
# that can genuinely fail if the design is too congested, or (as
# happened here) if some cells were never legalized. Both were
# investigated and resolved before this file reached its final
# form -- see cts_legalized.tcl and the tie-cell notes in
# floorplan.tcl.
detailed_route

# Fills remaining empty row gaps with non-functional filler cells.
# Required for manufacturing (rows need continuous diffusion) --
# without this, the design has real physical gaps, not GDS-ready.
# Multiple sizes given so the tool can close gaps of any width
# efficiently, same "give the tool a range" reasoning as the CTS
# buffer list.
filler_placement {sky130_fd_sc_hd__fill_1 sky130_fd_sc_hd__fill_2 sky130_fd_sc_hd__fill_4 sky130_fd_sc_hd__fill_8}
check_placement -verbose

# Fresh netlist dump AFTER every physical cell exists in its final
# form (tie cells, tap cells, CTS buffers + dummy loads, fillers).
# The original synth.ys netlist only has the logic Yosys produced --
# none of the cells added during physical implementation. sta_final.tcl
# needs THIS netlist, since fifo.spef has parasitic data for nets
# connected to all of those physically-added cells too.
#
# Two flags matter here, both found by debugging real LVS mismatches
# against the Magic-extracted layout netlist (see lvs_extract.tcl):
#
# -remove_cells {fill_* tap_1}: tap and filler cells have no active
#   devices (tap = plain substrate/well contact, fill = dummy
#   diffusion/poly for density rules only) -- Magic's ext2spice
#   correctly extracts NONE of them from the real layout, since
#   there's nothing electrically meaningful to extract. Leaving them
#   in this netlist caused a device-count mismatch in LVS (246 vs
#   167) purely from comparing non-functional bookkeeping cells that
#   were never meant to be compared. This mirrors the reference
#   ORFS flow, which strips filler cells at this exact step for the
#   same reason (`write_verilog -remove_cells $filler_cells ...`) --
#   tap_1 needed the same treatment here since this flow, unlike the
#   reference, inserts tap cells explicitly via tapcell in
#   floorplan.tcl.
#
# -include_pwr_gnd: without this, VPWR/VGND pin connections are left
#   implicit/unlisted in the Verilog output. netgen then reads each
#   unlisted power/ground pin as its own orphaned single-pin net,
#   instead of correctly merging them into the shared VDD/VGND nets
#   that physically exist as continuous power straps in the real
#   layout. This produced a huge net-count mismatch in LVS (846 vs
#   212 nets, with 81 "disconnected pins" reported) that had nothing
#   to do with real connectivity -- purely an artifact of this flag
#   being off by default.
write_verilog -include_pwr_gnd -remove_cells {sky130_fd_sc_hd__fill_1 sky130_fd_sc_hd__fill_2 sky130_fd_sc_hd__fill_4 sky130_fd_sc_hd__fill_8 sky130_fd_sc_hd__tap_1} syn_fifo_netlist_postroute.v

# Loads the OpenRCX extraction rules for this process corner.
# NOTE: the documented replacement command (set_extraction_rules_
# file, per the deprecation warning on -ext_model_file) does not
# actually exist on this OpenROAD build -- confirmed via `help
# set_extraction_rules_file` returning "no commands match".
# define_process_corner is the real, working command for this
# build; matches its documented purpose ("defines process corner")
# and its -ext_model_index/filename argument shape.
# "nom" corner matches the tt liberty / nom tech LEF used
# throughout this flow (see floorplan.tcl's corner-matching note).
define_process_corner -ext_model_index 0 /home/hariprasadjadhav/asic/pdks/share/pdk/sky130A/libs.tech/librelane/rules.openrcx.sky130A.nom.spef_extractor

# The -ext_model_file flag is deprecated per this build's own
# warning message, but empirically still works (unlike the
# documented replacement above) -- used here as the confirmed-
# working path.
extract_parasitics -ext_model_file /home/hariprasadjadhav/asic/pdks/share/pdk/sky130A/libs.tech/librelane/rules.openrcx.sky130A.nom.spef_extractor

write_spef fifo.spef
write_def detailed_route.def

#---------------------------------------------------------------
# FINDINGS
#---------------------------------------------------------------
# Final detailed_route result: 0 violations (Number of violations
#   = 0), full completion in 4 optimization iterations.
# Pin access: #stdCellPinNoAp = 0 -- zero pins without an access
#   point, confirming the CTS-legalization fix fully resolved the
#   earlier DRT-0073 failures.
# 452 filler instances placed to close remaining row gaps.
# Total routed wire length: ~6128 um across li1/met1/met2/met3.
#   (met4/met5 carry only the power grid in this design, no signal
#   routing landed there.)
#
# For final, trustworthy post-routing timing, do NOT trust
# report_checks run in this same long-lived session -- start a
# fresh STA session (read_liberty, read_verilog of the POST-ROUTE
# netlist -- not the original synth-only netlist, since tie cells/
# CTS buffers/dummy loads/tap/filler cells only exist in the
# physically-implemented design -- link_design, read_sdc,
# read_spef, set_propagated_clock, then report_checks). See the
# separate sta_final.tcl.
