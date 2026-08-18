set script_dir [file dirname [file normalize [info script]]]
set run_dir [file join $script_dir round52_route_BF73AC63_8F1E6F26_C73046F1]
set dcp_path [file join $run_dir checkpoints aes_gcm_axi_top_routed.dcp]
puts "Q52R_DCP {$dcp_path}"
open_checkpoint $dcp_path

proc fail {message} {
    puts stderr "Q52R_HARDGATE_FAIL $message"
    close_design
    exit 2
}

proc is_true {value} {
    expr {[string equal -nocase $value "true"] ||
          [string equal -nocase $value "yes"] ||
          $value eq "1"}
}

proc family {label from_pins to_pins} {
    puts "Q52R_${label}_OBJECTS FROM=[llength $from_pins] TO=[llength $to_pins]"
    if {[llength $from_pins] == 0 || [llength $to_pins] == 0} {
        puts "Q52R_${label}_COUNT EMPTY_OBJECT_SET"
        return -1
    }

    set paths [get_timing_paths -quiet -from $from_pins -to $to_pins \
        -delay_type max -max_paths 10000 -nworst 1]
    set negative 0
    set tns 0.0
    foreach path $paths {
        set slack [get_property SLACK $path]
        if {$slack < 0.0} {
            incr negative
            set tns [expr {$tns + double($slack)}]
        }
    }
    puts "Q52R_${label}_COUNT [llength $paths] NEG=$negative TNS=$tns"
    if {[llength $paths] > 0} {
        set path [lindex $paths 0]
        puts "Q52R_${label}_WORST slack=[get_property SLACK $path] start={[get_property STARTPOINT_PIN $path]} end={[get_property ENDPOINT_PIN $path]} levels=[get_property LOGIC_LEVELS $path] delay=[get_property DATAPATH_DELAY $path]"
    } else {
        puts "Q52R_${label}_WORST slack=NA start={} end={} levels=NA delay=NA"
    }
    return [llength $paths]
}

proc pin_detail {label cell pin_name} {
    set pin [get_pins -quiet ${cell}/${pin_name}]
    set net [get_nets -quiet -of_objects $pin]
    set drivers [get_pins -quiet -leaf -of_objects $net -filter {DIRECTION == OUT}]
    set driver_cells [get_cells -quiet -of_objects $drivers]
    puts "Q52R_${label}_${pin_name} pin={$pin} net={$net} drivers={$drivers} driver_cells={$driver_cells}"
    foreach driver_cell $driver_cells {
        puts "Q52R_${label}_${pin_name}_DRIVER cell=$driver_cell ref=[get_property REF_NAME $driver_cell] init=[get_property -quiet INIT $driver_cell]"
    }
    return [list $pin $net $drivers $driver_cells]
}

# Mandatory explicit descriptor-token structural hardgate.
set token_named [get_cells -hier -quiet -filter {NAME =~ *u_descriptor_idle_token_ff}]
puts "Q52R_TOKEN_NAMED_COUNT [llength $token_named] cells={$token_named}"
if {[llength $token_named] != 1} {
    fail "descriptor token named-cell count is [llength $token_named], expected 1"
}
set token [lindex $token_named 0]
set token_ref [get_property REF_NAME $token]
set token_init [get_property INIT $token]
set token_keep [get_property -quiet KEEP $token]
set token_dont_touch [get_property -quiet DONT_TOUCH $token]
puts "Q52R_TOKEN name=$token ref=$token_ref init=$token_init keep=$token_keep dont_touch=$token_dont_touch"
if {$token_ref ne "FDRE"} { fail "descriptor token REF_NAME is $token_ref, expected FDRE" }
if {$token_init ne "1'b0"} { fail "descriptor token INIT is $token_init, expected 1'b0" }
if {![is_true $token_keep]} { fail "descriptor token KEEP is $token_keep, expected true" }
if {![is_true $token_dont_touch]} { fail "descriptor token DONT_TOUCH is $token_dont_touch, expected true" }

set token_d [pin_detail TOKEN $token D]
set token_r [pin_detail TOKEN $token R]
set token_ce [pin_detail TOKEN $token CE]
set token_d_cells [lindex $token_d 3]
set token_r_net [lindex $token_r 1]
set token_r_cells [lindex $token_r 3]
set token_ce_net [lindex $token_ce 1]
set token_ce_cells [lindex $token_ce 3]
if {[llength $token_d_cells] != 1 || [get_property REF_NAME [lindex $token_d_cells 0]] ne "VCC"} {
    fail "descriptor token D is not driven solely by VCC"
}
if {[llength $token_r_net] != 1 || ![string match "*descriptor_idle_token_clear_w*" [lindex $token_r_net 0]]} {
    fail "descriptor token R is not the descriptor_idle_token_clear_w net"
}
if {[llength $token_r_cells] != 1 || ![string match "LUT*" [get_property REF_NAME [lindex $token_r_cells 0]]]} {
    fail "descriptor token R clear net is not driven by exactly one LUT"
}
if {[llength $token_ce_net] != 1 || ![string match "*descriptor_idle_token_set_w*" [lindex $token_ce_net 0]]} {
    fail "descriptor token CE is not the descriptor_idle_token_set_w net"
}
if {[llength $token_ce_cells] != 1 || ![string match "LUT*" [get_property REF_NAME [lindex $token_ce_cells 0]]]} {
    fail "descriptor token CE set net is not driven by exactly one LUT"
}

set old_token [get_cells -hier -quiet -filter {NAME =~ *descriptor_idle_token_r_reg* && REF_NAME =~ FD*}]
set canonical_p [get_cells -hier -quiet -filter {NAME =~ *public_frames_idle_r_reg* && REF_NAME =~ FD*}]
set pcore [get_cells -hier -quiet -filter {NAME =~ public_frames_idle_core_r_reg && REF_NAME =~ FD*}]
puts "Q52R_OLD_TOKEN_COUNT [llength $old_token] cells={$old_token}"
puts "Q52R_CANONICAL_PUBLIC_P_COUNT [llength $canonical_p] cells={$canonical_p}"
puts "Q52R_PCORE_COUNT [llength $pcore] cells={$pcore}"
if {[llength $old_token] != 0} { fail "old inferred descriptor token still exists" }
if {[llength $canonical_p] != 0} { fail "canonical public P cell still exists" }
if {[llength $pcore] != 1} { fail "Pcore cell count is [llength $pcore], expected 1" }
set pcore [lindex $pcore 0]
set pcore_ref [get_property REF_NAME $pcore]
set pcore_init [get_property INIT $pcore]
set pcore_keep [get_property -quiet KEEP $pcore]
set pcore_eqrm [get_property -quiet EQUIVALENT_REGISTER_REMOVAL $pcore]
puts "Q52R_PCORE name=$pcore ref=$pcore_ref init=$pcore_init keep=$pcore_keep eqrm=$pcore_eqrm"
if {$pcore_ref ne "FDSE" || $pcore_init ne "1'b1"} {
    fail "Pcore is not the sole FDSE INIT1 cell"
}

# Use the sequential cells' C pins as source selectors. This preserves the
# exact source-register grouping used by the frozen synth-DCP query.
set busy_cells [get_cells -hier -quiet -filter {NAME =~ *zeroize_busy_r_reg* && REF_NAME =~ FD*}]
set zero_cells [get_cells -hier -quiet -filter {NAME =~ *zeroize_pulse_o_reg* && REF_NAME =~ FD*}]
set live_cells [get_cells -hier -quiet -filter {NAME =~ *crypto_context_live_r_reg* && REF_NAME =~ FD*}]
set mode_cells [get_cells -hier -quiet -filter {NAME =~ *input_field_mode_r_reg* && REF_NAME =~ FD*}]
set ghslot_cells [get_cells -hier -quiet -filter {NAME =~ *gh_input_slot_free_r_reg* && REF_NAME =~ FD*}]
set data_capacity_cells [get_cells -hier -quiet -filter {NAME =~ *data_block_capacity_r_reg* && REF_NAME =~ FD*}]
set beat15_cells [get_cells -hier -quiet -filter {NAME =~ *block_beat_15_r_reg* && REF_NAME =~ FD*}]
set field_last_cells [get_cells -hier -quiet -filter {NAME =~ *field_last_r_reg* && REF_NAME =~ FD*}]
set capacity_cells [concat $mode_cells $ghslot_cells $data_capacity_cells $beat15_cells $field_last_cells]
set state_cells [get_cells -hier -quiet -filter {NAME =~ u_core/state_reg* && REF_NAME =~ FD*}]
set reciv_cells [get_cells -hier -quiet -filter {NAME =~ *rec_iv_is_96_r_reg* && REF_NAME =~ FD*}]
set inputq_cells [get_cells -hier -quiet -filter {NAME =~ *u_input_queue/count_r_reg* && REF_NAME =~ FD*}]
set abort_count_cells [get_cells -hier -quiet -filter {NAME =~ *zeroize_abort_count_reg* && REF_NAME =~ FD*}]
set result_role_cells [concat \
    [get_cells -hier -quiet -filter {NAME =~ *result_valid_r_reg* && REF_NAME =~ FD*}] \
    [get_cells -hier -quiet -filter {NAME =~ *result_data_r_reg* && REF_NAME =~ FD*}]]

set busy_c [get_pins -quiet -of_objects $busy_cells -filter {REF_PIN_NAME == C}]
set zero_c [get_pins -quiet -of_objects $zero_cells -filter {REF_PIN_NAME == C}]
set live_c [get_pins -quiet -of_objects $live_cells -filter {REF_PIN_NAME == C}]
set live_d [get_pins -quiet -of_objects $live_cells -filter {REF_PIN_NAME == D}]
set mode_c [get_pins -quiet -of_objects $mode_cells -filter {REF_PIN_NAME == C}]
set ghslot_c [get_pins -quiet -of_objects $ghslot_cells -filter {REF_PIN_NAME == C}]
set data_capacity_c [get_pins -quiet -of_objects $data_capacity_cells -filter {REF_PIN_NAME == C}]
set beat15_c [get_pins -quiet -of_objects $beat15_cells -filter {REF_PIN_NAME == C}]
set field_last_c [get_pins -quiet -of_objects $field_last_cells -filter {REF_PIN_NAME == C}]
set capacity_c [get_pins -quiet -of_objects $capacity_cells -filter {REF_PIN_NAME == C}]
set state_c [get_pins -quiet -of_objects $state_cells -filter {REF_PIN_NAME == C}]
set state_d [get_pins -quiet -of_objects $state_cells -filter {REF_PIN_NAME == D}]
set reciv_c [get_pins -quiet -of_objects $reciv_cells -filter {REF_PIN_NAME == C}]
set inputq_c [get_pins -quiet -of_objects $inputq_cells -filter {REF_PIN_NAME == C}]
set abort_count_c [get_pins -quiet -of_objects $abort_count_cells -filter {REF_PIN_NAME == C}]
set result_role_c [get_pins -quiet -of_objects $result_role_cells -filter {REF_PIN_NAME == C}]

set j0_cells [get_cells -hier -quiet -filter {NAME =~ *j0_reg_reg* && REF_NAME =~ FD*}]
set iv_cells [get_cells -hier -quiet -filter {NAME =~ *iv96_shadow_r_reg* && REF_NAME =~ FD*}]
set final_cells [get_cells -hier -quiet -filter {NAME =~ *final_tag_reg_reg* && REF_NAME =~ FD*}]
set j0_ce [get_pins -quiet -of_objects $j0_cells -filter {REF_PIN_NAME == CE}]
set iv_d [get_pins -quiet -of_objects $iv_cells -filter {REF_PIN_NAME == D}]
set final_r [get_pins -quiet -of_objects $final_cells -filter {REF_PIN_NAME == R}]

set busy_j0 [family BUSY_TO_J0_CE $busy_c $j0_ce]
set busy_live [family BUSY_TO_CRYPTO_LIVE_D $busy_c $live_d]
set mode_iv [family MODE_TO_IV_D $mode_c $iv_d]
set ghslot_iv [family GHSLOT_TO_IV_D $ghslot_c $iv_d]
set data_capacity_iv [family DATA_CAPACITY_TO_IV_D $data_capacity_c $iv_d]
set beat15_iv [family BEAT15_TO_IV_D $beat15_c $iv_d]
set field_last_iv [family FIELD_LAST_TO_IV_D $field_last_c $iv_d]
set capacity_iv [family CAPACITY_COMBINED_TO_IV_D $capacity_c $iv_d]
family BUSY_TO_MAIN_STATE $busy_c $state_d
family ZEROIZE_TO_J0_CE $zero_c $j0_ce
family LIVE_TO_J0_CE $live_c $j0_ce
family STATE_TO_IV_D $state_c $iv_d
family RECIV_TO_IV_D $reciv_c $iv_d
family INPUTQ_TO_IV_D $inputq_c $iv_d
family ABORT_COUNT_TO_FINAL_R $abort_count_c $final_r
family RESULT_ROLE_TO_FINAL_R $result_role_c $final_r

if {$busy_j0 != 0 || $busy_live != 0 || $mode_iv != 0 ||
    $ghslot_iv != 0 || $data_capacity_iv != 0 || $beat15_iv != 0 ||
    $field_last_iv != 0 || $capacity_iv != 0} {
    fail "one or more Round52 routed cut-target paths remain"
}

# Exact top 15 internal register-to-register max-delay paths.
set regs [all_registers]
set top15 [get_timing_paths -quiet -from $regs -to $regs \
    -delay_type max -max_paths 15 -nworst 1]
puts "Q52R_INTERNAL_TOP15_COUNT [llength $top15]"
set rank 0
foreach path $top15 {
    incr rank
    puts "Q52R_INTERNAL_TOP15 rank=$rank slack=[get_property SLACK $path] start={[get_property STARTPOINT_PIN $path]} end={[get_property ENDPOINT_PIN $path]} levels=[get_property LOGIC_LEVELS $path] delay=[get_property DATAPATH_DELAY $path]"
}

report_timing -quiet -from $regs -to $regs -delay_type max -max_paths 15 \
    -nworst 1 -path_type full_clock_expanded \
    -file [file join $script_dir round52_routed_internal_top15.rpt]
puts "Q52R_HARDGATE_PASS"
close_design
exit 0
