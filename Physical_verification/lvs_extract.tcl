#===============================================================
# lvs_extract.tcl
# Extracts a SPICE netlist directly from the real, GDS-based
# layout geometry -- this is the "layout" half of Layout Versus
# Schematic (LVS). Compared afterward (via netgen) against the
# post-route Verilog netlist -- the "schematic" half -- to confirm
# the physical layout's actual connectivity matches the intended
# circuit.
#
# NOTE the distinction from DRC: DRC checks whether the GEOMETRY
# obeys manufacturing spacing/width rules. LVS checks whether the
# geometry's CONNECTIVITY (as physically extracted from the shapes
# and vias) matches the circuit that was supposed to be built --
# a design can be perfectly DRC-clean and still be functionally
# wrong (e.g. a via missing where two nets were meant to connect,
# or a short between two nets that were never meant to touch).
#===============================================================
#
# USAGE:
#   Run inside the SAME Magic session as gds_out.tcl (i.e. after
#   `load syn_fifo` has already loaded the real, GDS-backed
#   layout) -- extraction needs real geometry loaded, the same
#   reason gds_out.tcl loads the PDK's sky130_fd_sc_hd.gds before
#   reading the DEF.
#
#   e.g., interactively:
#     magic -dnull -noconsole -T <TECHFILE> gds_out.tcl
#     % source lvs_extract.tcl
#---------------------------------------------------------------
ext2spice global off
# Extracts circuit connectivity (devices + nets) from the loaded
# layout geometry into Magic's internal .ext representation.
extract all

# Configures ext2spice's output specifically for LVS comparison
# (e.g. omits parasitic R/C detail that's irrelevant to a pure
# connectivity check, unlike a full SPICE simulation deck).
ext2spice lvs

# Writes the actual SPICE netlist file (syn_fifo.spice), derived
# purely from what's physically present in the layout.
ext2spice

#===============================================================
# RUN LVS (netgen) -- after this script produces syn_fifo.spice
#===============================================================
#   netgen -batch lvs "syn_fifo.spice syn_fifo" \
#     "syn_fifo_netlist_postroute.v syn_fifo" \
#     /home/hariprasadjadhav/asic/pdks/share/pdk/sky130A/libs.tech/netgen/sky130A_setup.tcl \
#     -json
#
#   Compares:
#     - "layout" side:    syn_fifo.spice     (from THIS script)
#     - "schematic" side: syn_fifo_netlist_postroute.v (from
#                          detailed_route.tcl's write_verilog,
#                          the fully physically-implemented
#                          netlist -- includes tie cells, tap
#                          cells, CTS buffers/dummy loads, fillers)
#     - sky130A_setup.tcl: PDK-specific device/pin matching rules
#                          netgen needs to correctly pair up
#                          transistors and nets across the two
#                          very different netlist formats.
