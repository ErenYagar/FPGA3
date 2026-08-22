if {$argc != 3} {
    error "Usage: audit_routed_board.tcl <routed_dcp> <expected_sha256> <unique_label>"
}

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set output_root [file join $repo_root engrenring synth_1g board output]
set top_name arty_a7_100t_aes_gcm_uart_rsp_top
set part_name xc7a100tcsg324-1
set routed_dcp [file normalize [lindex $argv 0]]
set expected_sha [string toupper [lindex $argv 1]]
set label [lindex $argv 2]

if {![file isfile $routed_dcp]} {
    error "Missing routed DCP: $routed_dcp"
}
if {![regexp {^[0-9A-F]{64}$} $expected_sha]} {
    error "Expected SHA-256 must be 64 hexadecimal characters"
}
if {![regexp {^[A-Za-z0-9_.-]+$} $label]} {
    error "Invalid label: $label"
}
set output_dir [file join $output_root $label]
if {[file exists $output_dir]} {
    error "Refusing to overwrite output directory: $output_dir"
}

set hash_text [exec certutil.exe -hashfile $routed_dcp SHA256]
set hash_lines [regexp -all -inline -line -nocase \
    {^[ \t]*[0-9a-f]{64}[ \t\r]*$} $hash_text]
if {[llength $hash_lines] != 1} {
    error "Unable to parse exactly one routed DCP SHA-256 hash line"
}
set actual_sha [string trim [lindex $hash_lines 0]]
set actual_sha [string toupper $actual_sha]
if {$actual_sha ne $expected_sha} {
    error "Routed DCP SHA-256 mismatch: expected=$expected_sha actual=$actual_sha"
}

proc timing_metrics {delay_type} {
    set worst [get_timing_paths -quiet -delay_type $delay_type \
        -max_paths 1 -nworst 1]
    if {[llength $worst] != 1} {
        error "Unable to obtain $delay_type timing path"
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

proc object_names {objects} {
    if {[llength $objects] == 0} {
        return {}
    }
    return [get_property NAME $objects]
}

proc require_exact_list {got expected description} {
    set got_sorted [lsort -unique $got]
    set expected_sorted [lsort -unique $expected]
    if {[llength $got_sorted] != [llength $expected_sorted] ||
        [join $got_sorted "\n"] ne [join $expected_sorted "\n"]} {
        error "$description changed: got={$got_sorted} expected={$expected_sorted}"
    }
}

proc fanout_endpoint_names {object} {
    return [object_names [all_fanout -quiet -flat -endpoints_only -from $object]]
}

proc fanin_startpoint_names {object} {
    return [object_names [all_fanin -quiet -flat -startpoints_only -to $object]]
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

proc unique_net_driver_cell {pin_name description} {
    set net [get_nets -quiet -of_objects [get_pins $pin_name]]
    set drivers [get_pins -quiet -leaf -of_objects $net \
        -filter {DIRECTION == OUT}]
    if {[llength $drivers] != 1} {
        error "$description must have exactly one driver"
    }
    set cell [get_cells -quiet -of_objects $drivers]
    if {[llength $cell] != 1} {
        error "$description driver cell is missing"
    }
    return $cell
}

file mkdir $output_dir
open_checkpoint $routed_dcp

set vivado_short [version -short]
set vivado_full [version]
if {$vivado_short ne "2021.1" ||
    ![regexp -line {^SW Build 3247384[ \t]} $vivado_full]} {
    error "Vivado build changed: short=$vivado_short"
}
if {[get_property TOP [current_design]] ne $top_name} {
    error "Top design changed: [get_property TOP [current_design]]"
}
if {[get_property PART [current_design]] ne $part_name} {
    error "Part changed: [get_property PART [current_design]]"
}

report_timing_summary -delay_type min_max -report_unconstrained \
    -file [file join $output_dir timing_routed.rpt]
set timing_summary_text [report_timing_summary -delay_type min_max \
    -report_unconstrained -return_string]
report_timing -delay_type max -max_paths 200 -sort_by slack \
    -file [file join $output_dir timing_setup_top200.rpt]
report_timing -delay_type min -max_paths 200 -sort_by slack \
    -file [file join $output_dir timing_hold_top200.rpt]
report_utilization -hierarchical \
    -file [file join $output_dir utilization_routed.rpt]
report_route_status -file [file join $output_dir route_status.rpt]
report_drc -file [file join $output_dir drc_routed.rpt]
report_methodology -name audit_methodology \
    -file [file join $output_dir methodology_routed.rpt]
report_cdc -details -file [file join $output_dir cdc_routed.rpt]
check_timing -verbose -file [file join $output_dir check_timing_routed.rpt]
report_exceptions -summary \
    -file [file join $output_dir exceptions_summary.rpt]
report_exceptions -coverage \
    -file [file join $output_dir exceptions_coverage.rpt]
report_clock_utilization \
    -file [file join $output_dir clock_utilization_routed.rpt]
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
    error "Clock configuration changed: input=$input_period core=$core_period"
}

set setup [timing_metrics max]
set hold [timing_metrics min]
set setup_wns [dict get $setup worst_slack]
set setup_tns [dict get $setup total_slack]
set setup_fep [dict get $setup failing_endpoints]
set hold_whs [dict get $hold worst_slack]
set hold_ths [dict get $hold total_slack]
set hold_fep [dict get $hold failing_endpoints]

set timing_number {[-+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)}
set timing_summary_pattern [format \
    {(?m)^[ \t]*(%s)[ \t]+(%s)[ \t]+([0-9]+)[ \t]+([0-9]+)[ \t]+(%s)[ \t]+(%s)[ \t]+([0-9]+)[ \t]+([0-9]+)[ \t]+(%s)[ \t]+(%s)[ \t]+([0-9]+)[ \t]+([0-9]+)[ \t\r]*$} \
    $timing_number $timing_number $timing_number $timing_number \
    $timing_number $timing_number]
if {![regexp -- $timing_summary_pattern $timing_summary_text whole \
    summary_wns summary_tns summary_setup_fep summary_setup_total \
    summary_whs summary_ths summary_hold_fep summary_hold_total \
    pulse_wpws pulse_tpws pulse_fep pulse_total]} {
    error "Unable to parse design timing summary including pulse width"
}

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
set drc_errors [llength [get_drc_violations -quiet \
    -filter {SEVERITY == "Error"}]]
set drc_critical [llength [get_drc_violations -quiet \
    -filter {SEVERITY == "Critical Warning"}]]
set methodology_errors 0
set methodology_critical 0
foreach violation [get_methodology_violations -quiet \
    -name audit_methodology] {
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
        error "check_timing $category expected $expected_count, got [dict get $check_counts $category]"
    }
}
if {[dict size $check_counts] != [llength $expected_categories]} {
    error "check_timing category set changed"
}
if {![regexp {There are 2 input ports with no input delay but user has a false path constraint} $check_text] ||
    ![regexp {There are 5 ports with no output delay but user has a false path constraint} $check_text]} {
    error "check_timing did not confirm asynchronous I/O false paths"
}
require_exact_list [object_names [get_ports -quiet -filter {DIRECTION == IN}]] \
    {clk rst_btn uart_txd_in} "Top-level input schema"
require_exact_list [object_names [get_ports -quiet -filter {DIRECTION == OUT}]] \
    {uart_rxd_out led[0] led[1] led[2] led[3]} "Top-level output schema"

set exception_summary_text [report_exceptions -summary -return_string]
set exception_coverage_text [report_exceptions -coverage -return_string]
set exception_summary_rows [regexp -all -inline -line \
    {^[ \t]*(?:False Path|Clock Groups|Multicycle Path|Max Delay(?: DPO)?|Min Delay)[ \t]+[0-9]+[ \t]+[0-9]+[ \t]+[0-9]+[ \t\r]*$} \
    $exception_summary_text]
if {[llength $exception_summary_rows] != 6 ||
    ![regexp -line {^[ \t]*False Path[ \t]+2[ \t]+7[ \t]+7[ \t\r]*$} $exception_summary_text] ||
    ![regexp -line {^[ \t]*Clock Groups[ \t]+0[ \t]+0[ \t]+0[ \t\r]*$} $exception_summary_text] ||
    ![regexp -line {^[ \t]*Multicycle Path[ \t]+0[ \t]+0[ \t]+0[ \t\r]*$} $exception_summary_text] ||
    ![regexp -line {^[ \t]*Max Delay[ \t]+0[ \t]+0[ \t]+0[ \t\r]*$} $exception_summary_text] ||
    ![regexp -line {^[ \t]*Max Delay DPO[ \t]+0[ \t]+0[ \t]+0[ \t\r]*$} $exception_summary_text] ||
    ![regexp -line {^[ \t]*Min Delay[ \t]+0[ \t]+0[ \t]+0[ \t\r]*$} $exception_summary_text]} {
    error "Timing exception summary changed"
}
set exception_coverage_rows [regexp -all -inline -line \
    {^[ \t]*[0-9]+[ \t]+False Path[ \t]+false[ \t]+false[^\r\n]*$} \
    $exception_coverage_text]
if {[llength $exception_coverage_rows] != 2 ||
    ![regexp -line {^[ \t]*[0-9]+[ \t]+False Path[ \t]+false[ \t]+false[ \t]+2 ports[ \t]+2[ \t]+100\.00[ \t\r]*$} $exception_coverage_text] ||
    ![regexp -line {^[ \t]*[0-9]+[ \t]+False Path[ \t]+false[ \t]+false[ \t]+5 ports[ \t]+5[ \t]+100\.00[ \t\r]*$} $exception_coverage_text]} {
    error "Timing exception coverage changed"
}

# Reset request: prove exact raw fanout, AND polarity, 2-FF synchronization,
# power-up value, unconditional sampling, and no stage-0 bypass.
require_exact_list [fanout_endpoint_names [get_ports rst_btn]] \
    {run_req_sync_r_reg[0]/D} "rst_btn raw fanout"
require_exact_list [fanout_endpoint_names [get_pins u_mmcm/LOCKED]] \
    {led[1] led[3] run_req_sync_r_reg[0]/D} "MMCME2 LOCKED raw fanout"
require_exact_list [fanin_startpoint_names \
    [get_pins {run_req_sync_r_reg[0]/D}]] \
    {rst_btn u_mmcm/LOCKED} "Reset stage-0 raw sources"

set reset_and_cell [unique_net_driver_cell \
    {run_req_sync_r_reg[0]/D} "Reset request AND"]
if {[get_property REF_NAME $reset_and_cell] ne "LUT2" ||
    [get_property INIT $reset_and_cell] ne "4'h8"} {
    error "Reset request function is no longer a two-input AND"
}
set reset_and_input_drivers {}
foreach pin_name [list [format "%s/I0" $reset_and_cell] \
    [format "%s/I1" $reset_and_cell]] {
    set input_net [get_nets -quiet -of_objects [get_pins $pin_name]]
    set input_driver [get_pins -quiet -leaf -of_objects $input_net \
        -filter {DIRECTION == OUT}]
    if {[llength $input_driver] != 1} {
        error "Reset request AND input has non-unique driver: $pin_name"
    }
    lappend reset_and_input_drivers [get_property NAME $input_driver]
}
require_exact_list $reset_and_input_drivers \
    {u_mmcm/LOCKED rst_btn_IBUF_inst/O} \
    "Reset request AND direct input drivers"
set rst_btn_ibuf [get_cells -quiet rst_btn_IBUF_inst]
if {[llength $rst_btn_ibuf] != 1 ||
    [get_property REF_NAME $rst_btn_ibuf] ne "IBUF"} {
    error "rst_btn input buffer changed"
}
set rst_btn_port_net [get_nets -quiet -of_objects [get_ports rst_btn]]
set rst_btn_ibuf_net [get_nets -quiet -of_objects \
    [get_pins rst_btn_IBUF_inst/I]]
if {[llength $rst_btn_port_net] != 1 ||
    [llength $rst_btn_ibuf_net] != 1 ||
    [get_property NAME $rst_btn_port_net] ne \
        [get_property NAME $rst_btn_ibuf_net]} {
    error "rst_btn no longer directly drives its IBUF"
}

set sync_cells [get_cells -quiet {
    run_req_sync_r_reg[0] run_req_sync_r_reg[1]
}]
if {[llength $sync_cells] != 2} {
    error "Reset synchronizer stage count changed"
}
foreach cell $sync_cells {
    if {[get_property REF_NAME $cell] ne "FDRE" ||
        ![string is true -strict [get_property ASYNC_REG $cell]] ||
        [get_property INIT $cell] ne "1'b0" ||
        [pin_net_name [format "%s/CE" $cell]] ne "<const1>" ||
        [pin_net_name [format "%s/R" $cell]] ne "<const0>" ||
        [pin_net_name [format "%s/C" $cell]] ne "core_clk"} {
        error "Reset synchronizer physical schema changed: $cell"
    }
}
require_exact_list [fanout_endpoint_names \
    [get_pins {run_req_sync_r_reg[0]/Q}]] \
    {run_req_sync_r_reg[1]/D} "Reset synchronizer stage-0 fanout"
require_same_net {run_req_sync_r_reg[0]/Q} \
    {run_req_sync_r_reg[1]/D} "Reset synchronizer chain"

# Qualifier: three early stages plus four physical copies of logical stage 3.
set stage3_names {
    reset_qual_r_reg[3]
    reset_qual_r_reg[3]_rep
    reset_qual_r_reg[3]_rep__0
    reset_qual_r_reg[3]_rep__1
}
set qualifier_names {
    reset_qual_r_reg[0]
    reset_qual_r_reg[1]
    reset_qual_r_reg[2]
    reset_qual_r_reg[3]
    reset_qual_r_reg[3]_rep
    reset_qual_r_reg[3]_rep__0
    reset_qual_r_reg[3]_rep__1
}
set all_qualifier_cells [get_cells -quiet -hier -regexp \
    {^reset_qual_r_reg.*$}]
set stage3_cells [get_cells -quiet -hier -regexp \
    {^reset_qual_r_reg\[3\](_rep.*)?$}]
set origin_stage3_cells [get_cells -quiet -hier \
    -filter {ORIG_CELL_NAME == "reset_qual_r_reg[3]"}]
require_exact_list [object_names $all_qualifier_cells] \
    $qualifier_names "Reset qualifier physical cells"
require_exact_list [object_names $stage3_cells] \
    $stage3_names "Reset qualifier stage-3 names"
require_exact_list [object_names $origin_stage3_cells] \
    $stage3_names "Reset qualifier stage-3 origin mapping"

set clear_cell [unique_net_driver_cell \
    {reset_qual_r_reg[0]/R} "Reset qualifier clear"]
if {[get_property REF_NAME $clear_cell] ne "LUT1" ||
    [get_property INIT $clear_cell] ne "2'h1"} {
    error "Reset qualifier clear is no longer the inverse synchronized request"
}
require_same_net {run_req_sync_r_reg[1]/Q} \
    [format "%s/I0" $clear_cell] "Reset qualifier clear polarity"

set expected_clear_endpoints {}
foreach cell $all_qualifier_cells {
    if {[get_property REF_NAME $cell] ne "FDRE" ||
        [get_property INIT $cell] ne "1'b0" ||
        [pin_net_name [format "%s/CE" $cell]] ne "<const1>" ||
        [pin_net_name [format "%s/C" $cell]] ne "core_clk"} {
        error "Reset qualifier register schema changed: $cell"
    }
    require_same_net {reset_qual_r_reg[0]/R} \
        [format "%s/R" $cell] "Reset qualifier clear distribution"
    lappend expected_clear_endpoints [format "%s/R" $cell]
}
require_exact_list [fanout_endpoint_names \
    [get_pins {run_req_sync_r_reg[1]/Q}]] \
    $expected_clear_endpoints "Reset synchronizer stage-1 fanout"

if {[pin_net_name {reset_qual_r_reg[0]/D}] ne "<const1>"} {
    error "Reset qualifier stage 0 no longer shifts a constant one"
}
require_exact_list [fanout_endpoint_names \
    [get_pins {reset_qual_r_reg[0]/Q}]] \
    {reset_qual_r_reg[1]/D} "Reset qualifier stage-0 fanout"
require_exact_list [fanout_endpoint_names \
    [get_pins {reset_qual_r_reg[1]/Q}]] \
    {reset_qual_r_reg[2]/D} "Reset qualifier stage-1 fanout"
require_same_net {reset_qual_r_reg[0]/Q} \
    {reset_qual_r_reg[1]/D} "Reset qualifier stage 0-to-1"
require_same_net {reset_qual_r_reg[1]/Q} \
    {reset_qual_r_reg[2]/D} "Reset qualifier stage 1-to-2"

set approved_early_endpoint {u_aes_gcm/u_core/u_key_context/u_key_sbox1/GEN_REGISTERED_OUTPUT.co_r_reg/ENARDEN}
set expected_stage2_endpoints [list $approved_early_endpoint]
foreach cell $stage3_cells {
    lappend expected_stage2_endpoints [format "%s/D" $cell]
    require_same_net {reset_qual_r_reg[2]/Q} \
        [format "%s/D" $cell] "Reset qualifier stage 2-to-3"
}
require_exact_list [fanout_endpoint_names \
    [get_pins {reset_qual_r_reg[2]/Q}]] \
    $expected_stage2_endpoints "Reset qualifier stage-2 fanout"
set early_enable_cell [unique_net_driver_cell \
    $approved_early_endpoint "Approved BRAM early-enable"]
if {[get_property REF_NAME $early_enable_cell] ne "LUT3" ||
    [get_property INIT $early_enable_cell] ne "8'hF4"} {
    error "Approved BRAM early-enable function changed"
}
require_exact_list [fanin_startpoint_names \
    [get_pins [format "%s/I0" $early_enable_cell]]] \
    {u_aes_gcm/u_registers/zeroize_pulse_o_reg/C} \
    "Approved BRAM early-enable I0 source"
require_exact_list [fanin_startpoint_names \
    [get_pins [format "%s/I1" $early_enable_cell]]] \
    {reset_qual_r_reg[3]_rep__1/C} \
    "Approved BRAM early-enable I1 source"
require_exact_list [fanin_startpoint_names \
    [get_pins [format "%s/I2" $early_enable_cell]]] \
    {reset_qual_r_reg[2]/C} \
    "Approved BRAM early-enable I2 source"

set expected_stage3_counts [dict create \
    {reset_qual_r_reg[3]} 57 \
    {reset_qual_r_reg[3]_rep} 1290 \
    {reset_qual_r_reg[3]_rep__0} 8553 \
    {reset_qual_r_reg[3]_rep__1} 3262]
set stage3_endpoint_occurrences [dict create]
set stage3_endpoint_sum 0
set stage3_mapping {}
foreach cell $stage3_cells {
    if {[get_property ORIG_CELL_NAME $cell] ne "reset_qual_r_reg[3]"} {
        error "Reset qualifier replica origin changed: $cell"
    }
    set q_pin [get_pins [format "%s/Q" $cell]]
    set q_net [get_nets -quiet -of_objects $q_pin]
    set q_drivers [get_pins -quiet -leaf -of_objects $q_net \
        -filter {DIRECTION == OUT}]
    if {[llength $q_drivers] != 1 ||
        [get_property NAME $q_drivers] ne [get_property NAME $q_pin]} {
        error "Reset qualifier stage-3 net driver changed: $cell"
    }
    set endpoints [lsort -unique [fanout_endpoint_names $q_pin]]
    set endpoint_count [llength $endpoints]
    if {$endpoint_count != [dict get $expected_stage3_counts \
        [get_property NAME $cell]]} {
        error "Reset qualifier stage-3 endpoint count changed: $cell=$endpoint_count"
    }
    incr stage3_endpoint_sum $endpoint_count
    foreach endpoint $endpoints {
        dict incr stage3_endpoint_occurrences $endpoint
    }
    lappend stage3_mapping [format "%s:%s:%s:%d" \
        [get_property NAME $cell] [get_property LOC $cell] \
        [get_property BEL $cell] $endpoint_count]
}
if {$stage3_endpoint_sum != 13162 ||
    [dict size $stage3_endpoint_occurrences] != 13161} {
    error "Reset qualifier stage-3 sink union changed"
}
set reconvergent_endpoints {}
dict for {endpoint count} $stage3_endpoint_occurrences {
    if {$count > 1} {
        lappend reconvergent_endpoints $endpoint
    }
}
require_exact_list $reconvergent_endpoints \
    {u_aes_gcm/u_core/gh_ctrl_valid_reg/D} \
    "Reset qualifier stage-3 reconvergence"
if {[pin_net_name {reset_qual_r_reg[3]/Q}] ne "aresetn"} {
    error "Distributed logical aresetn source changed"
}

# UART input: prove the asynchronous port has exactly one first-stage endpoint,
# the 2-FF chain cannot be bypassed, and both stages retain their synchronous
# active-high set to the inverse final reset qualifier.
set uart_sync_cells [get_cells -quiet {
    u_bridge/u_uart_rx/rx_meta_reg
    u_bridge/u_uart_rx/rx_sync_reg
}]
if {[llength $uart_sync_cells] != 2} {
    error "UART synchronizer stage count changed"
}
foreach cell $uart_sync_cells {
    if {[get_property REF_NAME $cell] ne "FDSE" ||
        ![string is true -strict [get_property ASYNC_REG $cell]] ||
        [get_property INIT $cell] ne "1'b1" ||
        [pin_net_name [format "%s/CE" $cell]] ne \
            "u_bridge/u_uart_rx/<const1>"} {
        error "UART synchronizer primitive/control schema changed: $cell"
    }
    require_exact_list [object_names [get_clocks -quiet -of_objects \
        [get_pins [format "%s/C" $cell]]]] \
        {core_clk_raw} "UART synchronizer clock"
    set uart_clock_net [get_nets -quiet -of_objects \
        [get_pins [format "%s/C" $cell]]]
    require_exact_list [object_names [get_pins -quiet -leaf \
        -of_objects $uart_clock_net -filter {DIRECTION == OUT}]] \
        {u_core_clk_buf/O} "UART synchronizer clock driver"
    set uart_ce_net [get_nets -quiet -of_objects \
        [get_pins [format "%s/CE" $cell]]]
    require_exact_list [object_names [get_pins -quiet -leaf \
        -of_objects $uart_ce_net -filter {DIRECTION == OUT}]] \
        {u_bridge/u_uart_rx/VCC/P} "UART synchronizer CE driver"
    require_same_net {u_bridge/u_uart_rx/rx_meta_reg/S} \
        [format "%s/S" $cell] "UART synchronizer synchronous set"
}
set uart_vcc_cell [get_cells -quiet u_bridge/u_uart_rx/VCC]
if {[llength $uart_vcc_cell] != 1 ||
    [get_property REF_NAME $uart_vcc_cell] ne "VCC"} {
    error "UART synchronizer constant-enable primitive changed"
}
require_exact_list [fanout_endpoint_names [get_ports uart_txd_in]] \
    {u_bridge/u_uart_rx/rx_meta_reg/D} "UART raw input fanout"
require_exact_list [fanout_endpoint_names \
    [get_pins {u_bridge/u_uart_rx/rx_meta_reg/Q}]] \
    {u_bridge/u_uart_rx/rx_sync_reg/D} "UART meta-stage fanout"
require_same_net {u_bridge/u_uart_rx/rx_meta_reg/Q} \
    {u_bridge/u_uart_rx/rx_sync_reg/D} "UART synchronizer chain"
set uart_set_cell [unique_net_driver_cell \
    {u_bridge/u_uart_rx/rx_meta_reg/S} "UART synchronizer set"]
if {[get_property REF_NAME $uart_set_cell] ne "LUT1" ||
    [get_property INIT $uart_set_cell] ne "2'h1"} {
    error "UART synchronizer set is no longer inverted aresetn"
}
require_exact_list [fanin_startpoint_names \
    [get_pins [format "%s/I0" $uart_set_cell]]] \
    {reset_qual_r_reg[3]_rep__0/C} \
    "UART synchronizer set source"

if {$setup_wns < 0.0 || $setup_tns != 0.0 || $setup_fep != 0} {
    error "Setup timing failed: WNS=$setup_wns TNS=$setup_tns FEP=$setup_fep"
}
if {$hold_whs < 0.0 || $hold_ths != 0.0 || $hold_fep != 0} {
    error "Hold timing failed: WHS=$hold_whs THS=$hold_ths FEP=$hold_fep"
}
if {$pulse_wpws < 0.0 || $pulse_tpws != 0.0 || $pulse_fep != 0} {
    error "Pulse-width timing failed: WPWS=$pulse_wpws TPWS=$pulse_tpws FEP=$pulse_fep"
}
if {$route_errors != 0 || $unrouted != 0 ||
    $fully_routed != $routable} {
    error "Routing failed: routable=$routable fully=$fully_routed errors=$route_errors"
}
if {$drc_errors != 0 || $drc_critical != 0} {
    error "DRC failed: errors=$drc_errors critical=$drc_critical"
}
if {$methodology_errors != 0 || $methodology_critical != 0} {
    error "Methodology failed: errors=$methodology_errors critical=$methodology_critical"
}
if {!$cdc_schema_pass} {
    error "CDC schema failed"
}

set bit_file [file join $output_dir $top_name.bit]
write_bitstream -bin_file $bit_file

set metrics [open [file join $output_dir signoff_metrics.txt] w]
puts $metrics "mode=verified_routed_dcp_audit"
puts $metrics "top=$top_name"
puts $metrics "part=[get_property PART [current_design]]"
puts $metrics "vivado_version=$vivado_short"
puts $metrics "vivado_sw_build=3247384"
puts $metrics "routed_dcp=$routed_dcp"
puts $metrics "routed_dcp_sha256=$actual_sha"
puts $metrics "input_clock_mhz=100"
puts $metrics "core_clock_mhz=175"
puts $metrics "input_clock_period_ns=$input_period"
puts $metrics "core_clock_period_ns=$core_period"
puts $metrics "setup_wns_ns=$setup_wns"
puts $metrics "setup_tns_ns=$setup_tns"
puts $metrics "setup_failing_endpoints=$setup_fep"
puts $metrics "hold_whs_ns=$hold_whs"
puts $metrics "hold_ths_ns=$hold_ths"
puts $metrics "hold_failing_endpoints=$hold_fep"
puts $metrics "pulse_wpws_ns=$pulse_wpws"
puts $metrics "pulse_tpws_ns=$pulse_tpws"
puts $metrics "pulse_failing_endpoints=$pulse_fep"
puts $metrics "routable_nets=$routable"
puts $metrics "fully_routed_nets=$fully_routed"
puts $metrics "unrouted_nets=$unrouted"
puts $metrics "route_errors=$route_errors"
puts $metrics "drc_errors=$drc_errors"
puts $metrics "drc_critical_warnings=$drc_critical"
puts $metrics "methodology_errors=$methodology_errors"
puts $metrics "methodology_critical_warnings=$methodology_critical"
puts $metrics "cdc_expected_schema_pass=$cdc_schema_pass"
puts $metrics "cdc_top_level_synchronizers=[llength $cdc_rows]"
puts $metrics "cdc_unsafe_categories=$cdc_has_unsafe"
puts $metrics "reset_request_function=LUT2_AND"
puts $metrics "reset_request_sync_stages=2"
puts $metrics "reset_release_qualifier_logical_stages=4"
puts $metrics "reset_release_stage3_physical_cells=[llength $stage3_cells]"
puts $metrics "reset_stage3_mapping=[join [lsort $stage3_mapping] ,]"
puts $metrics "reset_stage3_endpoint_sum=$stage3_endpoint_sum"
puts $metrics "reset_stage3_endpoint_union=[dict size $stage3_endpoint_occurrences]"
puts $metrics "reset_stage3_reconvergent_endpoint=[join $reconvergent_endpoints ,]"
puts $metrics "reset_stage3_sink_identity=sha_bound_counts_and_union"
puts $metrics "reset_stage2_approved_early_endpoint=$approved_early_endpoint"
puts $metrics "mmcm_locked_sta_model=structural_only_exact_fanout_gate"
foreach category $expected_categories {
    puts $metrics "check_timing_$category=[dict get $check_counts $category]"
}
close $metrics

puts "BOARD_ROUTED_AUDIT_PASS dcp_sha256=$actual_sha setup_wns=$setup_wns setup_tns=$setup_tns setup_fep=$setup_fep hold_whs=$hold_whs hold_ths=$hold_ths hold_fep=$hold_fep pulse_wpws=$pulse_wpws pulse_tpws=$pulse_tpws pulse_fep=$pulse_fep route_errors=$route_errors unrouted=$unrouted drc_errors=$drc_errors drc_critical=$drc_critical methodology_errors=$methodology_errors methodology_critical=$methodology_critical cdc_expected_schema_pass=$cdc_schema_pass reset_stage3_cells=[llength $stage3_cells] bit=$bit_file"
exit
