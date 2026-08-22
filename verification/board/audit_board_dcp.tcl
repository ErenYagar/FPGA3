proc audit_fail {message} {puts stderr "BOARD_DCP_AUDIT status=FAIL error={$message}";exit 1}
if {[llength $argv]!=1} {audit_fail "expected synth DCP"}
set dcp [file normalize [lindex $argv 0]]
if {![file isfile $dcp]} {audit_fail "missing DCP: $dcp"}
if {[catch {
 open_checkpoint $dcp
 set input_cells [get_cells -hier -quiet -filter {REF_NAME == RAMB18E1 && NAME =~ *input_bram*}]
 set output_cells [get_cells -hier -quiet -filter {REF_NAME == RAMB18E1 && NAME =~ *output_bram*}]
 if {[llength $input_cells]!=1||[llength $output_cells]!=1} {
  error "expected one RAMB18 for each shell BRAM; input=$input_cells output=$output_cells"
 }
 puts "BOARD_DCP_AUDIT status=PASS input_RAMB18={$input_cells} output_RAMB18={$output_cells}"
} message options]} {audit_fail $message}
exit 0
