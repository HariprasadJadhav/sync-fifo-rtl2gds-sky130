#===============================================================
# sta.tcl
# OpenSTA script for timing sign-off on the synthesized FIFO netlist
#===============================================================
#
# USAGE:
#   source sta.tcl
#
# Update LIB_PATH and NETLIST below if file locations change.
#---------------------------------------------------------------

# ---- Real sky130 standard cell library (has timing arcs, unlike
#      a plain synthesis-only generic library) ----
read_liberty /home/hariprasadjadhav/asic/pdks/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib

# ---- Gate-level netlist produced by synthesis.ys (Yosys + sky130 techmap) ----
read_verilog syn_fifo_netlist_sky130.v

# ---- Which module is top -- same idea as `hierarchy -top` in Yosys ----
link_design syn_fifo

# ---- Clock + I/O timing assumptions (see syn_fifo.sdc for full
#      reasoning and the findings log) ----
read_sdc syn_fifo.sdc

#---------------------------------------------------------------
# DEFAULT REPORT -- worst single path, setup (max) check
#---------------------------------------------------------------
report_checks

#---------------------------------------------------------------
# USEFUL VARIANTS (uncomment as needed -- kept here as a reference
# rather than run every time, since some of these produce long output)
#---------------------------------------------------------------

# --- See more than just the single worst setup path ---
# report_checks -path_delay max -path_group clk -group_path_count 30

# --- Hold (min-delay) check -- NOT covered by the default report_checks
#     above. Setup and hold are genuinely separate risks; short
#     combinational paths especially need this checked. ---
# report_checks -path_delay min -path_group clk -group_path_count 30

# --- Isolate TRUE reg2reg paths only (flop clock-pin to flop
#     data-pin), cutting out every I/O-port path. This is how we
#     found the FIFO's real internal-logic speed limit, separate
#     from the I/O timing assumptions in the SDC. ---
# report_checks -path_delay max -from [get_pins */CLK] -to [get_pins */D]

#---------------------------------------------------------------
# NOTE on flags that look similar but are NOT interchangeable:
#   -path_group   <name>   -> WHICH path group to report (we have
#                              one clock, "clk")
#   -group_path_count <N>  -> HOW MANY paths to show within that
#                              group (replaces the deprecated
#                              -group_count, which is what -group
#                              silently aliases to -- easy to
#                              mix up, don't use bare -group)
#---------------------------------------------------------------
