# Usage: vivado -mode batch -source program_board.tcl -tclargs BITFILE ?DEVICE_PATTERN?
proc program_fail {message} { puts stderr "BOARD_PROGRAM_SUMMARY status=FAIL error={$message}"; exit 1 }
if {[llength $argv]<1||[llength $argv]>2} {program_fail "expected BITFILE and optional DEVICE_PATTERN"}
set bitfile [file normalize [lindex $argv 0]]
if {![file isfile $bitfile]} {program_fail "bitfile not found: $bitfile"}
set pattern [expr {[llength $argv]==2?[lindex $argv 1]:"*xc7a100t*"}]
if {[catch {
 open_hw_manager;connect_hw_server;open_hw_target
 set devices [get_hw_devices -quiet $pattern]
 if {[llength $devices]!=1} {error "device pattern '$pattern' matched [llength $devices] devices"}
 set device [lindex $devices 0]
 current_hw_device $device
 set_property PROGRAM.FILE $bitfile $device
 program_hw_devices $device
 refresh_hw_device $device
 puts "BOARD_PROGRAM_SUMMARY status=PASS device=$device bitfile=$bitfile"
} message options]} {program_fail $message}
exit 0
