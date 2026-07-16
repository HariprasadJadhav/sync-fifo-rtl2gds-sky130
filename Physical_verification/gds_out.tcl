#===============================================================
# gds_out.tcl
# Final physical stage: stream out real GDSII geometry for the
# fully routed design, using Magic.
#===============================================================
#
# USAGE:
#   magic -dnull -noconsole -T <TECHFILE> gds_out.tcl
#
# TECHFILE: use the plain sky130A.tech, NOT sky130A-GDS.tech --
#   despite the "-GDS" name suggesting it's the right one for GDS
#   output, it does NOT match this LEF's layer names and produces
#   thousands of "Don't know how to parse layer" errors. sky130A.tech
#   read the same LEF/DEF cleanly (only harmless "unknown keyword,
#   ignoring" messages for newer LEF syntax Magic doesn't need).
#   Confirmed by directly testing both.
#
#   e.g.: magic -dnull -noconsole \
#           -T /home/hariprasadjadhav/asic/pdks/share/pdk/sky130A/libs.tech/magic/sky130A.tech \
#           gds_out.tcl
#---------------------------------------------------------------

# Router-level DRC (detailed_route.tcl) already confirmed 0
# violations; full foundry-grade DRC is a separate step done
# afterward in KLayout (see DRC note at the bottom of this file).
# No need for Magic's own interactive DRC while loading here.
drc off

#---------------------------------------------------------------
# Load REAL cell geometry before the DEF
#---------------------------------------------------------------
# LEF only contains abstract cell views (outline, pins, blockages
# -- "LEF" literally stands for Library Exchange Format, by design
# it never carries real transistor-level polygons). Reading only
# LEF+DEF and trying to write GDS fails with:
#   "Error: Cell '<name>' is an abstract view; cannot write GDS."
# The fix: load the PDK's pre-built GDS (real polygon geometry for
# every standard cell) FIRST, so DEF-instantiated cells resolve to
# real geometry instead of falling back to LEF abstracts.
gds read /home/hariprasadjadhav/asic/pdks/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/gds/sky130_fd_sc_hd.gds

#---------------------------------------------------------------
# Load technology + physical description + routed design
#---------------------------------------------------------------
lef read /home/hariprasadjadhav/asic/pdks/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__nom.tlef
lef read /home/hariprasadjadhav/asic/pdks/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef

def read detailed_route.def

load syn_fifo
gds write syn_fifo.gds

#===============================================================
# DOWNSTREAM SIGN-OFF STEPS (run separately, after this script)
#===============================================================
#
# --- Antenna check (already done, in OpenROAD, before this stage) ---
#   source detailed_route.tcl
#   check_antennas
#   -> PASSED, no violations. Given short average routed wire
#      length (~35um/net, 6128um total / 174 nets) and a buffered
#      9-cell clock tree, this is a low-risk design for antenna
#      effect, and the check confirms it directly rather than by
#      inference alone.
#
# --- DRC (KLayout) ---
#   The sky130A.lydrc runset is packaged as a KLayout MACRO (XML/
#   DSL format), not a plain batch .drc script -- run it as a
#   macro against the GDS, not via -rd variable substitution:
#
#     klayout -b -r /home/hariprasadjadhav/asic/pdks/share/pdk/sky130A/libs.tech/klayout/macros/run_drc_beol.lydrc syn_fifo.gds
#
#   BEOL (back-end-of-line: metal/via layers) is the appropriate
#   check here, not FEOL (front-end-of-line: transistor-level) --
#   this design only did placement/routing on pre-verified sky130
#   standard cells; their internal transistor geometry was never
#   touched, so re-checking FEOL rules inside untouched cells adds
#   little. run_drc_full.lydrc is a reasonable secondary/belt-and-
#   suspenders run if time allows.
#
#   RESULT: all rules green, 0 violations. The one "Cell exclusion
#   list" note in the log (rule nwell.6, cells sky130_fd_io__*) is
#   inert boilerplate for I/O pad-ring cells this design doesn't
#   use (it's a standalone block, no pad ring) -- not a skipped
#   check on anything actually present in this layout.
#   Report written to: sky130_drc.txt
#
# --- LVS (netgen) ---
#   Needs a layout-extracted SPICE netlist first -- see
#   lvs_extract.tcl (run in Magic, produces syn_fifo.spice) --
#   then compare it against the post-route Verilog netlist:
#
#     netgen -batch lvs "syn_fifo.spice syn_fifo" \
#       "syn_fifo_netlist_postroute.v syn_fifo" \
#       /home/hariprasadjadhav/asic/pdks/share/pdk/sky130A/libs.tech/netgen/sky130A_setup.tcl \
#       -json
#
#   NOTE: sky130A_setup.tcl is the correct entry point to pass on
#   the command line (it's what LVS docs/convention point to), even
#   though the real comparison logic lives in the plain setup.tcl
#   it sources -- confirmed by inspecting both files directly
#   rather than assuming from filename alone.
