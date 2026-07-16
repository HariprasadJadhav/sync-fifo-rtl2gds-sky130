#===============================================================
# global_route.tcl
# Stage 7: global routing -- plans coarse paths for every net
# through a grid of routing tiles, without yet committing to
# exact tracks/vias. Also reports routing congestion (regions
# where more wires want through a tile than there's track
# capacity for).
#===============================================================
#
# USAGE: openroad global_route.tcl
#---------------------------------------------------------------
source cts_legalized.tcl

# -guide_file: writes the routing guide global_route produces, used
#   as input by detailed_route next.
# -congestion_report_file: direct congestion metric from
#   global_route itself, rather than a separate report_* call --
#   simpler than hunting for a dedicated congestion report command.
global_route -guide_file route.guide -congestion_report_file congestion.rpt

write_def global_route.def

#---------------------------------------------------------------
# FINDINGS
#---------------------------------------------------------------
# Given very low utilization (~51.5%) and small net count (164
# nets, 150-167 cells depending on stage), congestion was never a
# concern for this design -- confirmed no congestion warnings in
# the global_route log.
