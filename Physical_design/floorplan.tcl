#===============================================================
# floorplan.tcl
# Stage 1 of physical implementation: load design, define die/core
# geometry, place I/O pins, insert tie cells and tap cells.
#===============================================================
#
# USAGE: openroad floorplan.tcl
#---------------------------------------------------------------

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

read_verilog syn_fifo_netlist_sky130.v
link_design syn_fifo
read_sdc syn_fifo.sdc

#---------------------------------------------------------------
# Die/core geometry
#---------------------------------------------------------------
# utilization 50%: reasonable starting point for a small design
# with no macros and fairly dense wiring -- leaves headroom for
# routing without wasting silicon. aspect_ratio 1 = square core,
# since there's no directional I/O clustering need for this design.
# core_space 9um: sized so the later PDN ring (which needs
# core_offset + 2*width + spacing = 2+2+2+2 = 8um) physically fits
# inside the die margin -- see powerplanning.tcl PDN-0351 note.
# site unithd: single-height site, matches every cell in this
# design (all sky130_fd_sc_hd__* cells are single-height "hd" cells;
# unithddbl is for double-height cells, none used here).
initialize_floorplan -utilization 50 -aspect_ratio 1 -core_space 9 -site unithd

# Generates the routing track grid for every metal layer, using
# pitch/offset rules from the tech LEF. Required before place_pins,
# which snaps I/O pins onto specific track coordinates -- without
# this, place_pins errors with "Horizontal routing tracks not found".
make_tracks

# I/O pins placed here, BEFORE any standard-cell placement pass,
# so global_placement's wirelength optimization can pull cells
# toward known pin locations.
# -annealing Enables an optimization-based placement approach (simulated annealing style) rather than a simple sequential/random placement.
place_pins -hor_layers met3 -ver_layers met2 -annealing

# Yosys/ABC's optimizer ties some internal signals to a constant
# 0 or 1 rather than instantiating real logic for them. Those
# constant nets get tagged signal-type GROUND/POWER, which
# TritonRoute cannot route as an ordinary signal net (no real
# driver). insert_tiecells adds an actual physical tie cell
# (conb_1) so the net has a genuine electrical source before
# routing is attempted. Root-caused via DRT-0305 in detailed_route.
insert_tiecells sky130_fd_sc_hd__conb_1/HI -prefix TIE_ONE_
insert_tiecells sky130_fd_sc_hd__conb_1/LO -prefix TIE_ZERO_

# Substrate/well body-tie cells, inserted every 15um along each
# row. Prevents latch-up in real silicon -- standard, expected
# step. NOTE: their VPB/VNB body-tie pins need explicit
# add_global_connection rules in powerplanning.tcl (VPB/VNB are
# different pin names from the VPWR/VGND used by regular cells) --
# see PDN-0189 fix.
tapcell -tapcell_master sky130_fd_sc_hd__tap_1 -distance 15

report_design_area
write_def floorplan.def

#---------------------------------------------------------------
# FINDINGS
#---------------------------------------------------------------
# Die BBox:  (0, 0) to (96.125, 96.125) um
# Core BBox: (9.200, 10.880) to (86.940, 87.040) um
#   -- core lower-left snapped from requested (9,9) to (9.2, 10.88)
#      because the core boundary must align to whole site-grid
#      units (site size 0.46 x 2.72 um); this is why the margins
#      on all four sides ended up slightly different (2.3/2.72
#      on the snapped corner vs 2.085/3.245 on the far edges --
#      the far edges are just wherever the last whole row/column
#      happens to stop, unrelated to the snap amount).
# Core area: 5920.678 um^2, Total instances area: 3051.677 um^2
# Effective utilization: 51.5% (not exactly 50% -- same grid-
#   snapping effect: the tool rounds up to the nearest legal
#   row/column count).
# I/O: 24 pins placed (10 scalar ports + 8-bit data_in + 8-bit
#   data_out = 1+1+1+1+1+1+1+1+8+8 = 24), all with sinks, none
#   dropped.
# Tapcell: 75 tap cells inserted.
