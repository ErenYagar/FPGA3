set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. .. ..]]
set rtl_root [file join $repo_root engrenring rtl source]
set output_root [file join $script_dir output]
set top_name arty_a7_100t_aes_gcm_uart_rsp_top
set part_name xc7a100tcsg324-1

proc timing_metrics {delay_type} {
    set worst [get_timing_paths -quiet -delay_type $delay_type \
        -max_paths 1 -nworst 1]
    if {[llength $worst] != 1} {
        error "Unable to obtain routed $delay_type timing path"
    }
    set failing [get_timing_paths -quiet -delay_type $delay_type \
        -slack_lesser_than 0.0 -max_paths 100000 -nworst 1]
    set total_slack 0.0
    foreach path $failing {
        set total_slack [expr {$total_slack + \
            double([get_property SLACK $path])}]
    }
    return [dict create \
        worst_slack [expr {double([get_property SLACK $worst])}] \
        total_slack $total_slack \
        failing_endpoints [llength $failing]]
}

proc pin_net_name {pin_name} {
    set pin [get_pins -quiet $pin_name]
    if {[llength $pin] != 1} {
        error "Expected exactly one pin: $pin_name"
    }
    set net [get_nets -quiet -of_objects $pin]
    if {[llength $net] != 1} {
        error "Expected exactly one net on pin: $pin_name"
    }
    return [get_property NAME $net]
}

proc require_same_net {first_pin second_pin description} {
    set first_net [pin_net_name $first_pin]
    set second_net [pin_net_name $second_pin]
    if {$first_net ne $second_net} {
        error "$description changed: $first_pin=$first_net $second_pin=$second_net"
    }
}

if {$argc != 1} {
    error "Usage: run_arty_a7_100t_uart_rsp.tcl <unique_label>"
}
set label [lindex $argv 0]
if {![regexp {^[A-Za-z0-9_.-]+$} $label]} {
    error "Invalid label '$label'"
}
set output_dir [file join $output_root $label]
if {[file exists $output_dir]} {
    error "Refusing to overwrite output directory $output_dir"
}
file mkdir $output_dir

set_part $part_name
read_verilog [file join $rtl_root aes_core sbox.v]
read_verilog [file join $rtl_root stream_aes aes_block_engine.v]
read_verilog [file join $rtl_root stream_aes aes_first_block_engine.v]
read_verilog [file join $rtl_root stream_aes aes_key_context.v]
read_verilog [file join $rtl_root stream_ghash ghash16.v]
read_verilog [file join $rtl_root stream_axi axi_lite_regs.v]
read_verilog [file join $rtl_root stream_axi axis_output_skid_8.v]
read_verilog [file join $rtl_root stream_core aes_gcm_stream_core.v]
read_verilog [file join $rtl_root stream_core stream_fifo.v]
read_verilog [file join $rtl_root aes_gcm_axi_top.v]
read_verilog [file join $rtl_root board uart_rx.v]
read_verilog [file join $rtl_root board uart_tx.v]
read_verilog [file join $rtl_root board aes_gcm_uart_rsp_bridge.v]
read_verilog [file join $rtl_root board arty_a7_100t_aes_gcm_uart_rsp_top.v]
read_xdc [file join $script_dir arty_a7_100t_aes_gcm_uart_rsp.xdc]

synth_design -top $top_name -part $part_name -flatten_hierarchy rebuilt
write_checkpoint [file join $output_dir ${top_name}_synth.dcp]
report_utilization -hierarchical -file [file join $output_dir utilization_synth.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -file [file join $output_dir timing_synth.rpt]

opt_design -directive ExploreWithRemap
place_design -directive ExtraNetDelay_high
phys_opt_design -directive AggressiveExplore
write_checkpoint [file join $output_dir ${top_name}_placed.dcp]
report_timing_summary -delay_type min_max -report_unconstrained \
    -file [file join $output_dir timing_placed.rpt]

route_design -directive Explore
# The baseline route is within a few picoseconds of closure on this dense
# board design.  Post-route physical optimization rewires only the remaining
# critical path and preserves a fully routed design.
phys_opt_design -directive AggressiveExplore
write_checkpoint [file join $output_dir ${top_name}_routed.dcp]
report_timing_summary -delay_type min_max -report_unconstrained \
    -file [file join $output_dir timing_routed.rpt]
report_timing -delay_type max -max_paths 200 -sort_by slack \
    -file [file join $output_dir timing_setup_top200.rpt]
report_timing -delay_type min -max_paths 200 -sort_by slack \
    -file [file join $output_dir timing_hold_top200.rpt]
report_utilization -hierarchical -file [file join $output_dir utilization_routed.rpt]
report_route_status -file [file join $output_dir route_status.rpt]
report_drc -file [file join $output_dir drc_routed.rpt]
report_methodology -name routed_methodology \
    -file [file join $output_dir methodology_routed.rpt]
report_cdc -details -file [file join $output_dir cdc_routed.rpt]
check_timing -verbose -file [file join $output_dir check_timing_routed.rpt]
report_clock_utilization -file [file join $output_dir clock_utilization_routed.rpt]
report_power -file [file join $output_dir power_vectorless_routed.rpt]

set sys_clock [get_clocks -quiet sys_clk_pin]
set core_clock [get_clocks -quiet core_clk_raw]
if {[llength $sys_clock] != 1 || [llength $core_clock] != 1} {
    error "Expected exactly one sys_clk_pin and core_clk_raw clock"
}
set input_period [expr {double([get_property PERIOD $sys_clock])}]
set core_period [expr {double([get_property PERIOD $core_clock])}]
if {abs($input_period - 10.000) > 0.0005 ||
    abs($core_period - (40.0 / 7.0)) > 0.0005} {
    error "Board clock configuration failed: input_period=$input_period core_period=$core_period"
}

set setup [timing_metrics max]
set hold [timing_metrics min]
set setup_wns [dict get $setup worst_slack]
set setup_tns [dict get $setup total_slack]
set setup_fep [dict get $setup failing_endpoints]
set hold_whs [dict get $hold worst_slack]
set hold_ths [dict get $hold total_slack]
set hold_fep [dict get $hold failing_endpoints]

set route_text [report_route_status -return_string]
foreach {key pattern} [list \
    routable {# of routable nets[^:]*:[ \t]*([0-9]+)} \
    fully_routed {# of fully routed nets[^:]*:[ \t]*([0-9]+)} \
    route_errors {# of nets with routing errors[^:]*:[ \t]*([0-9]+)}] {
    if {![regexp -nocase -- $pattern $route_text match value]} {
        error "Unable to parse $key from report_route_status"
    }
    set $key $value
}
set unrouted [expr {$routable - $fully_routed}]

set drc_errors [llength [get_drc_violations -quiet -filter {SEVERITY == "Error"}]]
set drc_critical [llength [get_drc_violations -quiet -filter {SEVERITY == "Critical Warning"}]]
set methodology_errors 0
set methodology_critical 0
foreach violation [get_methodology_violations -quiet -name routed_methodology] {
    set severity [get_property SEVERITY $violation]
    if {[string equal -nocase $severity "Error"]} {
        incr methodology_errors
    } elseif {[string equal -nocase $severity "Critical Warning"]} {
        incr methodology_critical
    }
}
set cdc_text [report_cdc -details -return_string]
set cdc_has_unsafe [regexp -line \
    {^CDC-[0-9]+[ \t]+(Critical|Warning)[ \t]+[1-9][0-9]*} $cdc_text]
set cdc_safe_summary [regexp -line \
    {^CDC-3[ \t]+Info[ \t]+2[ \t]+1-bit synchronized with ASYNC_REG property[ \t]*$} \
    $cdc_text]
set cdc_rows [regexp -all -inline -line \
    {^[ \t]*[0-9]+[ \t]+CDC-[0-9]+[^\r\n]*$} $cdc_text]
set cdc_reset_safe [regexp -line \
    {^[ \t]*[0-9]+[ \t]+CDC-3[ \t]+Info[^\r\n]*[ \t]2[ \t]+False Path[ \t]+rst_btn[ \t]+run_req_sync_r_reg\[0\]/D[ \t]*$} \
    $cdc_text]
set cdc_uart_safe [regexp -line \
    {^[ \t]*[0-9]+[ \t]+CDC-3[ \t]+Info[^\r\n]*[ \t]2[ \t]+False Path[ \t]+uart_txd_in[ \t]+u_bridge/u_uart_rx/rx_meta_reg/D[ \t]*$} \
    $cdc_text]
set cdc_schema_pass [expr {!$cdc_has_unsafe && $cdc_safe_summary &&
    [llength $cdc_rows] == 2 && $cdc_reset_safe && $cdc_uart_safe}]

# report_cdc recognizes the asynchronous board port, but MMCME2/LOCKED is not
# a timed startpoint in Vivado 2021.1.  Gate the physical reset-request
# synchronizer and its complete raw fanin explicitly so the LOCKED source
# cannot bypass or enter a later stage unnoticed.
set reset_sync_cells [get_cells -quiet {
    run_req_sync_r_reg[0] run_req_sync_r_reg[1]
}]
set reset_qual_cells [get_cells -quiet {
    reset_qual_r_reg[0] reset_qual_r_reg[1]
    reset_qual_r_reg[2] reset_qual_r_reg[3]
}]
if {[llength $reset_sync_cells] != 2 || [llength $reset_qual_cells] != 4} {
    error "Reset synchronizer/qualifier register schema changed"
}
foreach cell $reset_sync_cells {
    if {![string is true -strict [get_property ASYNC_REG $cell]]} {
        error "Reset synchronizer cell lacks ASYNC_REG: $cell"
    }
    if {[get_property REF_NAME $cell] ne "FDRE"} {
        error "Reset synchronizer primitive changed: $cell"
    }
}
set reset_raw_sources [lsort [get_property NAME [all_fanin -flat \
    -startpoints_only -to [get_pins run_req_sync_r_reg[0]/D]]]]
if {$reset_raw_sources ne [lsort {rst_btn u_mmcm/LOCKED}]} {
    error "Reset stage-0 raw sources changed: $reset_raw_sources"
}
set reset_stage0_endpoints [lsort [get_property NAME [all_fanout -flat \
    -endpoints_only -from [get_pins run_req_sync_r_reg[0]/Q]]]]
if {$reset_stage0_endpoints ne {run_req_sync_r_reg[1]/D}} {
    error "Reset synchronizer stage-0 fanout changed: $reset_stage0_endpoints"
}
require_same_net {run_req_sync_r_reg[0]/Q} {run_req_sync_r_reg[1]/D} \
    "Reset synchronizer chain"

# Gate the complete qualifier topology after physical replication.  The final
# stage may be replicated for fanout, but every copy must sample stage 2 and
# share the stage-1 synchronizer's synchronous reset control.
set all_reset_qual_cells [get_cells -quiet -hier -regexp \
    {^reset_qual_r_reg.*$}]
set reset_stage3_cells [get_cells -quiet -hier -regexp \
    {^reset_qual_r_reg\[3\](_rep.*)?$}]
if {[llength $all_reset_qual_cells] != [expr {3 + [llength $reset_stage3_cells]}] ||
    [llength $reset_stage3_cells] < 1} {
    error "Reset qualifier physical schema changed"
}
foreach cell $all_reset_qual_cells {
    if {[get_property REF_NAME $cell] ne "FDRE"} {
        error "Reset qualifier primitive changed: $cell"
    }
    require_same_net {reset_qual_r_reg[0]/R} ${cell}/R \
        "Reset qualifier synchronous clear distribution"
    require_same_net {run_req_sync_r_reg[0]/C} ${cell}/C \
        "Reset qualifier clock"
}
set reset_clear_sources [lsort [get_property NAME [all_fanin -flat \
    -startpoints_only -to [get_pins {reset_qual_r_reg[0]/R}]]]]
if {$reset_clear_sources ne {run_req_sync_r_reg[1]/C}} {
    error "Reset qualifier clear source changed: $reset_clear_sources"
}
if {[pin_net_name {reset_qual_r_reg[0]/D}] ne "<const1>"} {
    error "Reset qualifier stage-0 no longer shifts a constant one"
}
require_same_net {reset_qual_r_reg[0]/Q} {reset_qual_r_reg[1]/D} \
    "Reset qualifier stage 0-to-1 chain"
require_same_net {reset_qual_r_reg[1]/Q} {reset_qual_r_reg[2]/D} \
    "Reset qualifier stage 1-to-2 chain"
set reset_stage3_mapping {}
foreach cell $reset_stage3_cells {
    require_same_net {reset_qual_r_reg[2]/Q} ${cell}/D \
        "Reset qualifier stage 2-to-3 chain"
    set endpoint_count [llength [all_fanout -quiet -flat -endpoints_only \
        -from [get_pins ${cell}/Q]]]
    if {$endpoint_count == 0} {
        error "Reset qualifier final-stage cell has no endpoint: $cell"
    }
    lappend reset_stage3_mapping "${cell}:${endpoint_count}"
}
if {[pin_net_name {reset_qual_r_reg[3]/Q}] ne "aresetn"} {
    error "Distributed aresetn logical source changed"
}

set check_text [check_timing -verbose -return_string]
set expected_categories {no_clock constant_clock pulse_width_clock unconstrained_internal_endpoints no_input_delay no_output_delay multiple_clock generated_clocks loops partial_input_delay partial_output_delay latch_loops}
set expected_check_counts [dict create no_input_delay 2 no_output_delay 5]
set check_counts [dict create]
foreach {whole category count} [regexp -all -inline -line \
    {checking ([a-z_]+) \(([0-9]+)\)} $check_text] {
    dict set check_counts $category $count
}
foreach category $expected_categories {
    if {![dict exists $check_counts $category]} {
        error "check_timing category missing: $category"
    }
    set expected_count 0
    if {[dict exists $expected_check_counts $category]} {
        set expected_count [dict get $expected_check_counts $category]
    }
    if {[dict get $check_counts $category] != $expected_count} {
        error "check_timing category $category expected $expected_count, got [dict get $check_counts $category]"
    }
}
if {[dict size $check_counts] != [llength $expected_categories]} {
    error "check_timing category set changed: found={[dict keys $check_counts]}"
}

# Vivado reports asynchronous/status ports in no_input_delay/no_output_delay
# even when it confirms that each is covered by a false-path exception.  Gate
# the exact board schema and prove that no timed path survives either cut;
# do not invent a clock-relative I/O delay for asynchronous UART or LEDs.
set async_inputs [get_ports -quiet {rst_btn uart_txd_in}]
set async_outputs [get_ports -quiet {uart_rxd_out led[0] led[1] led[2] led[3]}]
if {[llength $async_inputs] != 2 || [llength $async_outputs] != 5} {
    error "Board asynchronous I/O schema changed"
}
set clock_input [get_ports -quiet clk]
set all_inputs [get_ports -quiet -filter {DIRECTION == IN}]
set all_outputs [get_ports -quiet -filter {DIRECTION == OUT}]
if {[lsort $all_inputs] ne [lsort [concat $clock_input $async_inputs]] ||
    [lsort $all_outputs] ne [lsort $async_outputs]} {
    error "Unexpected top-level I/O outside the clock and false-path allowlists"
}
if {![regexp {There are 2 input ports with no input delay but user has a false path constraint} $check_text] ||
    ![regexp {There are 5 ports with no output delay but user has a false path constraint} $check_text]} {
    error "check_timing did not confirm the asynchronous I/O false-path exceptions"
}

if {$setup_wns < 0.0 || $setup_tns != 0.0 || $setup_fep != 0} {
    error "Board setup timing failed: WNS=$setup_wns TNS=$setup_tns FEP=$setup_fep"
}
if {$hold_whs < 0.0 || $hold_ths != 0.0 || $hold_fep != 0} {
    error "Board hold timing failed: WHS=$hold_whs THS=$hold_ths FEP=$hold_fep"
}
if {$route_errors != 0 || $unrouted != 0 || $fully_routed != $routable} {
    error "Board routing failed: routable=$routable fully_routed=$fully_routed unrouted=$unrouted errors=$route_errors"
}
if {$drc_errors != 0 || $drc_critical != 0} {
    error "Board DRC failed: errors=$drc_errors critical_warnings=$drc_critical"
}
if {$methodology_errors != 0 || $methodology_critical != 0} {
    error "Board methodology failed: errors=$methodology_errors critical_warnings=$methodology_critical"
}
if {!$cdc_schema_pass} {
    error "Board CDC failed: expected exactly the safe 2-stage reset-request and 2-stage UART synchronizers"
}

set bit_file [file join $output_dir ${top_name}.bit]
write_bitstream -force -bin_file $bit_file

set metrics [open [file join $output_dir signoff_metrics.txt] w]
puts $metrics "top=$top_name"
puts $metrics "part=$part_name"
puts $metrics "input_clock_mhz=100"
puts $metrics "core_clock_mhz=175"
puts $metrics "place_directive=ExtraNetDelay_high"
puts $metrics "pre_route_phys_opt_directive=AggressiveExplore"
puts $metrics "route_directive=Explore"
puts $metrics "post_route_phys_opt_directive=AggressiveExplore"
puts $metrics "input_clock_period_ns=$input_period"
puts $metrics "core_clock_period_ns=$core_period"
puts $metrics "uart_baud=115200"
puts $metrics "setup_wns_ns=$setup_wns"
puts $metrics "setup_tns_ns=$setup_tns"
puts $metrics "setup_failing_endpoints=$setup_fep"
puts $metrics "hold_whs_ns=$hold_whs"
puts $metrics "hold_ths_ns=$hold_ths"
puts $metrics "hold_failing_endpoints=$hold_fep"
puts $metrics "routable_nets=$routable"
puts $metrics "fully_routed_nets=$fully_routed"
puts $metrics "unrouted_nets=$unrouted"
puts $metrics "route_errors=$route_errors"
puts $metrics "drc_errors=$drc_errors"
puts $metrics "drc_critical_warnings=$drc_critical"
puts $metrics "methodology_errors=$methodology_errors"
puts $metrics "methodology_critical_warnings=$methodology_critical"
puts $metrics "cdc_expected_schema_pass=$cdc_schema_pass"
puts $metrics "cdc_safe_synchronizers=[llength $cdc_rows]"
puts $metrics "cdc_unsafe_categories=$cdc_has_unsafe"
puts $metrics "reset_request_sync_stages=[llength $reset_sync_cells]"
puts $metrics "reset_release_qualifier_stages=[llength $reset_qual_cells]"
puts $metrics "reset_qualifier_physical_cells=[llength $all_reset_qual_cells]"
puts $metrics "reset_stage3_physical_cells=[llength $reset_stage3_cells]"
puts $metrics "reset_stage3_mapping=[join [lsort $reset_stage3_mapping] ,]"
puts $metrics "reset_raw_sources=[join $reset_raw_sources ,]"
puts $metrics "reset_stage0_endpoints=[join $reset_stage0_endpoints ,]"
puts $metrics "mmcm_locked_sta_model=structural_only_sync_gate"
foreach category $expected_categories {
    puts $metrics "check_timing_${category}=[dict get $check_counts $category]"
}
puts $metrics "check_timing_async_input_false_path_allowlist=2"
puts $metrics "check_timing_async_output_false_path_allowlist=5"
close $metrics

puts "ARTY_UART_RSP_BUILD_PASS top=$top_name part=$part_name setup_wns=$setup_wns setup_tns=$setup_tns setup_fep=$setup_fep hold_whs=$hold_whs hold_ths=$hold_ths hold_fep=$hold_fep route_errors=$route_errors unrouted=$unrouted drc_errors=$drc_errors drc_critical_warnings=$drc_critical methodology_errors=$methodology_errors methodology_critical_warnings=$methodology_critical cdc_expected_schema_pass=$cdc_schema_pass reset_stage3_physical_cells=[llength $reset_stage3_cells] bit=$bit_file"
exit
