#===============================================================
# powerplan.tcl
# Stage 2: build the power delivery network (ring -> straps ->
# rails -> cell pins) on top of the floorplan.
#===============================================================
#
# USAGE: openroad powerplan.tcl
#
# OpenROAD keeps no memory between separate script invocations,
# so this file pulls in the entire floorplan stage via `source`
# (Tcl's real include mechanism -- works because OpenROAD scripts
# are genuine Tcl, unlike Yosys's `-s` mode) rather than repeating
# those commands here.
#---------------------------------------------------------------
source floorplan.tcl

#---------------------------------------------------------------
# Global net connections
#---------------------------------------------------------------
# Maps every cell's physical VPWR/VGND pins to the chip-wide nets
# VDD/VGND. This is a NAMING step only -- no geometry yet.
add_global_connection -net VDD -pin_pattern "VPWR" -power
add_global_connection -net VGND -pin_pattern "VGND" -ground

# Tap cells (inserted in floorplan.tcl) use DIFFERENT pin names
# for their body-tie connections (VPB = n-well tie, VNB = p-well/
# substrate tie) -- these are a separate pin pattern from VPWR/
# VGND and need their own explicit rules, or the tap cells sit in
# the layout with unconnected body ties (PDN-0189), which defeats
# their entire purpose (latch-up prevention needs a real electrical
# connection, not just physical presence).
add_global_connection -net VDD -pin_pattern "VPB" -power
add_global_connection -net VGND -pin_pattern "VNB" -ground

#---------------------------------------------------------------
# Voltage domain
#---------------------------------------------------------------
# A voltage domain bundles a power net + ground net under ONE
# name. define_pdn_grid below references this domain by name, not
# by the individual net names -- easy to conflate the two (see
# PDN-1032 note): add_global_connection operates on NET names
# (VDD/VGND), define_pdn_grid operates on DOMAIN names (CORE).
set_voltage_domain -name CORE -power VDD -ground VGND

#---------------------------------------------------------------
# Grid definition: rings -> straps -> connects
#---------------------------------------------------------------
define_pdn_grid -name "core_grid" -starts_with POWER -voltage_domains {CORE}

# Straps on met4 (vertical) / met5 (horizontal) -- adjacent layers,
# perpendicular directions, so they physically cross and can be
# joined by vias (see add_pdn_connect below). Chosen above met1
# (already busy with local cell/row routing) and above the met2/
# met3 layers used for I/O pins.
add_pdn_stripe -grid "core_grid" -layer met4 -width 1.6 -pitch 27.14 -offset 13.57 -starts_with POWER
add_pdn_stripe -grid "core_grid" -layer met5 -width 1.6 -pitch 27.14 -offset 13.57 -starts_with POWER -extend_to_core_ring

# Ring around the core perimeter. Total radial space consumed =
# core_offset + width + spacing + width = 2+2+2+2 = 8um -- this
# is why floorplan.tcl's core_space was increased from 2 to 9um
# (see PDN-0351: "PDN rings do not fit inside the die area").
add_pdn_ring -grid "core_grid" -layer {met4 met5} -widths 2.0 -spacings 2.0 -core_offsets 2.0

# Two overlapping metal shapes on different layers are NOT
# automatically electrically joined in real silicon -- a via is
# required, and vias are only placed where explicitly told to.
# Without these lines, straps/rings/rails could visually overlap
# in the layout while remaining electrically isolated pieces of
# metal -- a silent, dangerous class of bug.
add_pdn_connect -grid "core_grid" -layers {met1 met4}
add_pdn_connect -grid "core_grid" -layers {met4 met5}

pdngen

report_voltage_domains
report_global_connect
write_def powerplan.def

#---------------------------------------------------------------
# FINDINGS
#---------------------------------------------------------------
# Global connection rules: 4 (VPWR->VDD, VGND->VGND, VPB->VDD,
#   VNB->VGND) -- confirmed via report_global_connect.
# pdngen completes with no PDN-0351 (ring fit) or PDN-1032 (missing
#   domain) errors once floorplan.tcl's core_space and this file's
#   -name CORE / VPB+VNB rules are both correct.
