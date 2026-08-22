# Runs one host-prepared vector through the dual AXI-Lite shell.
# VECTOR_FILE is key=value text with KEY_MODE, KEY_HEX, DECRYPT, TAG_BITS,
# IV_BITS, AAD_BITS, DATA_BITS, INPUT_HEX, and EXPECTED_OUTPUT_HEX.
proc vector_fail {message} {puts stderr "BOARD_VECTOR_SUMMARY status=FAIL error={$message}";exit 1}
if {[llength $argv]!=4} {vector_fail "expected HW_AXI SHELL_BASE DUT_BASE VECTOR_FILE"}
set hw_axi_name [lindex $argv 0];scan [lindex $argv 1] %x shell_base;scan [lindex $argv 2] %x dut_base
set vector_file [file normalize [lindex $argv 3]]
if {![file isfile $vector_file]} {vector_fail "vector file missing: $vector_file"}
set values [dict create];set ch [open $vector_file r]
while {[gets $ch line]>=0} {if {[regexp {^([A-Z_]+)=(.*)$} [string trim $line] all key value]} {dict set values $key [string trim $value]}}
close $ch
foreach key {KEY_MODE KEY_HEX DECRYPT TAG_BITS IV_BITS AAD_BITS DATA_BITS INPUT_HEX EXPECTED_OUTPUT_HEX} {
 if {![dict exists $values $key]} {vector_fail "missing $key"}
}
proc axi_write {axis address data name} {
 create_hw_axi_txn $name $axis -address [format %08x $address] -data [format %08x $data] -type write -force
 run_hw_axi [get_hw_axi_txns $name];delete_hw_axi_txn [get_hw_axi_txns $name]
}
proc axi_read {axis address name} {
 create_hw_axi_txn $name $axis -address [format %08x $address] -len 1 -type read -force
 run_hw_axi [get_hw_axi_txns $name];set data [get_property DATA [get_hw_axi_txns $name]]
 delete_hw_axi_txn [get_hw_axi_txns $name];scan $data %x value;return $value
}
if {[catch {
 open_hw_manager;connect_hw_server;open_hw_target
 set axis [get_hw_axis -quiet $hw_axi_name];if {[llength $axis]!=1} {error "HW AXI '$hw_axi_name' not found"}
 set key_hex [dict get $values KEY_HEX];set input_hex [dict get $values INPUT_HEX]
 set input_bytes [expr {[string length $input_hex]/2}]
 for {set i 0}{$i<8}{incr i} {scan [string range $key_hex [expr {$i*8}] [expr {$i*8+7}]] %x word;axi_write $axis [expr {$dut_base+0x20+4*$i}] $word key_$i}
 axi_write $axis [expr {$dut_base+0x00}] 2 key_commit
 set status 0;for {set poll 0}{$poll<10000&&!(($status)&1)}{incr poll} {set status [axi_read $axis [expr {$dut_base+0x04}] key_status]}
 if {!($status&1)} {error "key expansion timeout"}
 scan [dict get $values DECRYPT] %d decrypt;scan [dict get $values TAG_BITS] %d tag_bits
 axi_write $axis [expr {$dut_base+0x08}] [expr {($tag_bits<<8)|$decrypt}] cfg
 foreach {name offset} {IV_BITS 0x0c AAD_BITS 0x10 DATA_BITS 0x14} {scan [dict get $values $name] %d bits;axi_write $axis [expr {$dut_base+$offset}] $bits $name}
 axi_write $axis [expr {$dut_base+0x00}] 1 cmd_push
 for {set i 0}{$i<$input_bytes}{incr i} {scan [string range $input_hex [expr {$i*2}] [expr {$i*2+1}]] %x byte;axi_write $axis [expr {$shell_base+0x100+4*$i}] $byte input_$i}
 axi_write $axis [expr {$shell_base+0x008}] $input_bytes input_len;axi_write $axis [expr {$shell_base+0x000}] 1 shell_start
 set shell_status 0;for {set poll 0}{$poll<1000000&&!(($shell_status)&2)}{incr poll} {set shell_status [axi_read $axis [expr {$shell_base+0x004}] shell_status]}
 if {!($shell_status&2)} {error "board vector timeout"}
 set out_count [axi_read $axis [expr {$shell_base+0x018}] output_count];set actual ""
 for {set i 0}{$i<$out_count}{incr i} {set word [axi_read $axis [expr {$shell_base+0x800+4*$i}] output_$i];append actual [format %02x [expr {$word&0xff}]]}
 set expected [string tolower [dict get $values EXPECTED_OUTPUT_HEX]]
 if {$actual ne $expected} {error "output mismatch expected=$expected actual=$actual"}
 set cycles [axi_read $axis [expr {$shell_base+0x010}] cycles]
 set stalls [axi_read $axis [expr {$shell_base+0x01c}] stalls]
 puts "BOARD_VECTOR_SUMMARY status=PASS bytes=$out_count cycles=$cycles stalls=$stalls vector=$vector_file"
} message options]} {vector_fail $message}
exit 0
