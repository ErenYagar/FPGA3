set script_dir [file dirname [file normalize [info script]]]
set run_dir [file join $script_dir round52_BF73AC63_8F1E6F26_C73046F1]
open_checkpoint [file join $run_dir checkpoints aes_gcm_axi_top_synth.dcp]

proc fail {message} {
    puts stderr "Q52_HARDGATE_FAIL $message"
    close_design
    exit 2
}

proc endpoint_summary {label paths} {
    set tns 0.0
    foreach path $paths { set tns [expr {$tns + double([get_property SLACK $path])}] }
    set wns 0.0
    if {[llength $paths] > 0} { set wns [get_property SLACK [lindex $paths 0]] }
    puts "Q52_${label} WNS=$wns TNS=$tns FEP=[llength $paths]"
}

proc family {label from_pins to_pins} {
    puts "Q52_${label}_OBJECTS FROM=[llength $from_pins] TO=[llength $to_pins]"
    if {[llength $from_pins] == 0 || [llength $to_pins] == 0} {
        puts "Q52_${label}_COUNT EMPTY_OBJECT_SET"
        return -1
    }
    set paths [get_timing_paths -quiet -from $from_pins -to $to_pins -delay_type max -max_paths 10000 -nworst 1]
    set neg 0
    foreach path $paths { if {[get_property SLACK $path] < 0.0} { incr neg } }
    puts "Q52_${label}_COUNT [llength $paths] NEG=$neg"
    if {[llength $paths] > 0} {
        set path [lindex $paths 0]
        puts "Q52_${label}_WORST slack=[get_property SLACK $path] start={[get_property STARTPOINT_PIN $path]} end={[get_property ENDPOINT_PIN $path]} levels=[get_property LOGIC_LEVELS $path] delay=[get_property DATAPATH_DELAY $path]"
    }
    return [llength $paths]
}

proc input_pin_details {label cell pin_name} {
    set pin [get_pins -quiet ${cell}/${pin_name}]
    set net [get_nets -quiet -of_objects $pin]
    set drivers [get_pins -quiet -leaf -of_objects $net -filter {DIRECTION == OUT}]
    set driver_cells [get_cells -quiet -of_objects $drivers]
    puts "Q52_${label}_PIN pin=$pin_name net={$net} drivers={$drivers} driver_cells={$driver_cells}"
    foreach dc $driver_cells {
        puts "Q52_${label}_DRIVER cell=$dc ref=[get_property REF_NAME $dc] init=[get_property -quiet INIT $dc]"
    }
    return $drivers
}

set regs [all_registers]
set overall_setup [get_timing_paths -quiet -delay_type max -slack_lesser_than 0.0 -max_paths 100000 -nworst 1]
set overall_hold [get_timing_paths -quiet -delay_type min -slack_lesser_than 0.0 -max_paths 100000 -nworst 1]
set internal_setup [get_timing_paths -quiet -from $regs -to $regs -delay_type max -slack_lesser_than 0.0 -max_paths 100000 -nworst 1]
set internal_hold [get_timing_paths -quiet -from $regs -to $regs -delay_type min -slack_lesser_than 0.0 -max_paths 100000 -nworst 1]
endpoint_summary OVERALL_SETUP $overall_setup
endpoint_summary OVERALL_HOLD $overall_hold
endpoint_summary INTERNAL_SETUP $internal_setup
endpoint_summary INTERNAL_HOLD $internal_hold

set top [get_timing_paths -quiet -from $regs -to $regs -delay_type max -max_paths 40 -nworst 1]
foreach path $top {
    puts "Q52_INTERNAL slack=[get_property SLACK $path] start={[get_property STARTPOINT_PIN $path]} end={[get_property ENDPOINT_PIN $path]} levels=[get_property LOGIC_LEVELS $path] delay=[get_property DATAPATH_DELAY $path]"
}

# Recheck the mandatory explicit descriptor token mapping.
set token [get_cells -hier -quiet -filter {NAME =~ *u_descriptor_idle_token_ff && REF_NAME == FDRE}]
puts "Q52_TOKEN_COUNT [llength $token] cells={$token}"
if {[llength $token] != 1} { fail "descriptor token cell count is [llength $token], expected 1" }
set token [lindex $token 0]
puts "Q52_TOKEN name=$token ref=[get_property REF_NAME $token] init=[get_property INIT $token] keep=[get_property -quiet KEEP $token] dont_touch=[get_property -quiet DONT_TOUCH $token]"
if {[get_property INIT $token] ne "1'b0"} { fail "descriptor token INIT is not zero" }
set token_d_drivers [input_pin_details TOKEN $token D]
input_pin_details TOKEN $token R
input_pin_details TOKEN $token CE
if {[llength [get_cells -quiet -of_objects $token_d_drivers -filter {REF_NAME == VCC}]] != 1} { fail "descriptor token D is not VCC" }

set old_token [get_cells -hier -quiet -filter {NAME =~ *descriptor_idle_token_r_reg* && REF_NAME =~ FD*}]
set canonical_p [get_cells -hier -quiet -filter {NAME =~ *public_frames_idle_r_reg* && REF_NAME =~ FD*}]
set pcore [get_cells -hier -quiet -filter {NAME =~ public_frames_idle_core_r_reg && REF_NAME =~ FD*}]
puts "Q52_OLD_TOKEN_COUNT [llength $old_token]"
puts "Q52_CANONICAL_P_COUNT [llength $canonical_p]"
puts "Q52_PCORE_COUNT [llength $pcore] cells={$pcore}"
if {[llength $old_token] != 0 || [llength $canonical_p] != 0 || [llength $pcore] != 1} { fail "token/P structural count mismatch" }
foreach c $pcore { puts "Q52_PCORE name=$c ref=[get_property REF_NAME $c] init=[get_property INIT $c] keep=[get_property -quiet KEEP $c] eqrm=[get_property -quiet EQUIVALENT_REGISTER_REMOVAL $c]" }

# Build source/endpoint groups from actual sequential cells, then use C as the
# timing startpoint to avoid empty or invalid Q-pin filters in Vivado 2021.1.
set busy_cells [get_cells -hier -quiet -filter {NAME =~ *zeroize_busy_r_reg* && REF_NAME =~ FD*}]
set zero_cells [get_cells -hier -quiet -filter {NAME =~ *zeroize_pulse_o_reg* && REF_NAME =~ FD*}]
set live_cells [get_cells -hier -quiet -filter {NAME =~ *crypto_context_live_r_reg* && REF_NAME =~ FD*}]
set mode_cells [get_cells -hier -quiet -filter {NAME =~ *input_field_mode_r_reg* && REF_NAME =~ FD*}]
set cap_cells [concat $mode_cells \
    [get_cells -hier -quiet -filter {NAME =~ *gh_input_slot_free_r_reg* && REF_NAME =~ FD*}] \
    [get_cells -hier -quiet -filter {NAME =~ *data_block_capacity_r_reg* && REF_NAME =~ FD*}] \
    [get_cells -hier -quiet -filter {NAME =~ *block_beat_15_r_reg* && REF_NAME =~ FD*}] \
    [get_cells -hier -quiet -filter {NAME =~ *field_last_r_reg* && REF_NAME =~ FD*}]]
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
set cap_c [get_pins -quiet -of_objects $cap_cells -filter {REF_PIN_NAME == C}]
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
set busy_state [family BUSY_TO_MAIN_STATE $busy_c $state_d]
set busy_live [family BUSY_TO_CRYPTO_LIVE_D $busy_c $live_d]
set cap_iv [family CAPACITY_TO_IV_D $cap_c $iv_d]
if {$busy_j0 != 0 || $busy_live != 0 || $cap_iv != 0} { fail "one or more Round52 cut target paths remain" }

family ZEROIZE_TO_J0_CE $zero_c $j0_ce
family LIVE_TO_J0_CE $live_c $j0_ce
family STATE_TO_IV_D $state_c $iv_d
family RECIV_TO_IV_D $reciv_c $iv_d
family INPUTQ_TO_IV_D $inputq_c $iv_d
family ABORT_COUNT_TO_FINAL_R $abort_count_c $final_r
family RESULT_ROLE_TO_FINAL_R $result_role_c $final_r

report_timing_summary -delay_type min_max -max_paths 30 -report_unconstrained -file [file join $script_dir round52_synth_targets_timing_summary.rpt]
puts "Q52_HARDGATE_PASS"
close_design
exit 0
