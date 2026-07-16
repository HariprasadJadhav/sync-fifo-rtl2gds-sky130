#===============================================================
# syn_fifo.sdc
# Timing constraints for the synchronous FIFO (8 x 8-bit, depth 8)
#===============================================================
#
# HOW TO USE THIS FILE
#   - Default clock period below (10ns / 100MHz) is a safe, easy
#     verification target -- matches the period used in the RTL
#     testbench simulations.
#   - See the "FINDINGS" section at the bottom for the actual
#     max-frequency numbers derived from STA runs, and how to
#     re-derive them if the design changes.
#
#---------------------------------------------------------------
# CLOCK DEFINITION
#---------------------------------------------------------------
# Every timing check is measured relative to this clock. Without
# create_clock, OpenSTA has no reference and cannot check anything.
create_clock -name clk -period 10 [get_ports clk]

#---------------------------------------------------------------
# INPUT DELAYS
#---------------------------------------------------------------
# Models: "these inputs are driven by some other block's flip-flop,
# which itself has some delay after ITS clock edge before the
# signal becomes valid." 2ns is a placeholder assumption (~20% of
# clock period is a common rule-of-thumb starting point, not a law)
# -- refine this once you know the real driving block's timing.
#
# Applies to every port declared as `input` in syn_fifo.v except
# clk itself (clk is the timing reference, not a data signal).
set_input_delay -clock clk 2 [get_ports {wr_en rd_en data_in rst}]

#---------------------------------------------------------------
# OUTPUT DELAYS
#---------------------------------------------------------------
# Models: "whatever block consumes these outputs needs them stable
# X ns before ITS next clock edge." Same 2ns placeholder logic as
# above, mirrored for outputs.
#
# Applies to every port declared as `output` in syn_fifo.v.
set_output_delay -clock clk 2 [get_ports {full empty overflow underflow data_out}]

#---------------------------------------------------------------
# FINDINGS (from STA runs on the sky130_fd_sc_hd__tt_025C_1v80 lib)
#---------------------------------------------------------------
# At 10ns (100MHz):
#   - Setup: all paths MET. Worst slack 5.84ns, on an I/O-bound
#     path (rd_en -> underflow), NOT a real internal (reg2reg) path.
#   - True internal reg2reg critical path (_367_ -> _367_, part of
#     the full/empty flag feedback logic): slack 7.48ns -- i.e. the
#     FIFO's own logic is comfortably faster than the I/O timing
#     budget we assumed above.
#   - Hold: all paths MET, smallest slack 0.54ns (no violations
#     found at any period, since hold doesn't depend on clock period).
#
# Max frequency search (tightening the clock period until the
# I/O-bound setup path breaks):
#   - period = 4.16ns -> VIOLATED (slack ~0, right at the edge)
#   - period = 4.17ns -> MET
#   => Max operating frequency, GIVEN the 2ns I/O delay assumption
#      above, is ~4.17ns period (~240 MHz).
#
# Separately, the pure internal-logic speed limit (reg2reg only,
# ignoring I/O assumptions) is period = 10 - 7.48 = 2.52ns (~396MHz).
# This is a DIFFERENT number for a DIFFERENT question ("how fast
# could the core logic run if I/O weren't the bottleneck") -- do
# not conflate the two in the README; report both, labeled.
#
# To re-derive these numbers after any RTL change:
#   1. Re-run synthesis (see synthesis.ys) to get a fresh netlist.
#   2. Set create_clock period here to something safe (e.g. 10ns).
#   3. Run: report_checks -path_delay max -path_group clk -group_path_count 30
#      Note the worst slack from an I/O-bound (port-to-port or
#      port-to-flop) path.
#   4. Run: report_checks -path_delay max -from [get_pins */CLK] -to [get_pins */D]
#      This isolates TRUE reg2reg paths only -- gives the internal
#      logic speed limit directly.
#   5. Run: report_checks -path_delay min -path_group clk -group_path_count 30
#      Confirm hold is still clean (independent of clock period).
#   6. To pin down the exact max frequency: set period = (step 2's
#      period) - (step 3's worst slack), re-run step 3's command,
#      confirm slack lands near 0 / VIOLATED, then nudge the period
#      up slightly (~0.01-0.05ns) until it flips back to MET.
