`timescale 1ns / 1ps

// Shared AES block engine for pre-expanded keys.
//
// The engine has three state contexts around one bank of sixteen registered
// S-boxes.  The S-box output and selected round key are registered before
// MixColumns/AddRoundKey.  Contexts alternate through the resulting
// three-clock round recurrence, so continuously supplied blocks complete at
// an average interval of 10, 12, or 14 clocks for AES-128, AES-192, or AES-256
// respectively.
//
// A request is accepted when start && ready.  round_keys and key_size must
// remain stable while busy is asserted.  done may pulse on consecutive clocks
// for the three interleaved contexts.
module aes_block_engine
(
    input              clk,
    input              rst_n,
    input              start,
    input      [1:0]   key_size,
    input      [1919:0] round_keys,
    input      [127:0] block_in,
    output             ready,
    output             busy,
    output             done,
    output     [127:0] block_out
);

localparam KEY_SIZE_128 = 2'd0;
localparam KEY_SIZE_192 = 2'd1;
localparam KEY_SIZE_256 = 2'd2;

reg          ctx0_valid_r;
reg          ctx0_waiting_r;
reg  [127:0] ctx0_state_r;
reg  [3:0]   ctx0_round_r;
reg  [3:0]   ctx0_last_round_r;

reg          ctx1_valid_r;
reg          ctx1_waiting_r;
reg  [127:0] ctx1_state_r;
reg  [3:0]   ctx1_round_r;
reg  [3:0]   ctx1_last_round_r;

reg          ctx2_valid_r;
reg          ctx2_waiting_r;
reg  [127:0] ctx2_state_r;
reg  [3:0]   ctx2_round_r;
reg  [3:0]   ctx2_last_round_r;

(* KEEP = "TRUE", EQUIVALENT_REGISTER_REMOVAL = "NO" *)
reg          contexts_full_r;

reg          pipe_valid_r;
reg  [1:0]   pipe_context_r;
reg          pipe_final_r;
// Four kept copies localize the 4-bit round selector near each 32-bit quarter
// of the 128-bit key mux.  A single copy has fanout 128 and becomes a routing
// bottleneck after the S-box path is pipelined.
(* KEEP = "TRUE" *) reg [3:0] pipe_round_index0_r;
(* KEEP = "TRUE" *) reg [3:0] pipe_round_index1_r;
(* KEEP = "TRUE" *) reg [3:0] pipe_round_index2_r;
(* KEEP = "TRUE" *) reg [3:0] pipe_round_index3_r;

reg          xform_valid_r;
reg  [1:0]   xform_context_r;
reg          xform_final_r;
(* KEEP = "TRUE", EQUIVALENT_REGISTER_REMOVAL = "NO" *)
reg          xform_capacity_valid_r;
(* KEEP = "TRUE", EQUIVALENT_REGISTER_REMOVAL = "NO" *)
reg          xform_capacity_final_r;
reg  [127:0] xform_shifted_r;
reg  [127:0] xform_round_key_r;

reg          done_r;
reg  [127:0] block_out_r;

wire         ctx0_can_issue_w;
wire         ctx1_can_issue_w;
wire         ctx2_can_issue_w;
wire         issue_valid_w;
wire [1:0]   issue_context_w;
wire [127:0] issue_state_w;
wire [3:0]   issue_round_w;
wire [3:0]   issue_last_round_w;

wire         key_size_valid_w;
wire         finish_now_w;
wire         contexts_exactly_two_w;
wire         capacity_w;
wire         accept_w;
wire [1:0]   accept_context_w;
wire [3:0]   accepted_last_round_w;

wire [127:0] sbox_output_w;
wire [127:0] shifted_state_w;
wire [127:0] mixed_state_w;
wire [127:0] round_result_w;
wire [127:0] selected_round_key0_w;
wire [127:0] selected_round_key1_w;
wire [127:0] selected_round_key2_w;
wire [127:0] selected_round_key3_w;

function [3:0] last_round_for_size;
input [1:0] size;
begin
    case(size)
        KEY_SIZE_128: last_round_for_size = 4'd10;
        KEY_SIZE_192: last_round_for_size = 4'd12;
        default:      last_round_for_size = 4'd14;
    endcase
end
endfunction

function [127:0] select_round_key;
input [1919:0] keys;
input [3:0]    round_index;
begin
    case(round_index)
        4'd0:  select_round_key = keys[127:0];
        4'd1:  select_round_key = keys[255:128];
        4'd2:  select_round_key = keys[383:256];
        4'd3:  select_round_key = keys[511:384];
        4'd4:  select_round_key = keys[639:512];
        4'd5:  select_round_key = keys[767:640];
        4'd6:  select_round_key = keys[895:768];
        4'd7:  select_round_key = keys[1023:896];
        4'd8:  select_round_key = keys[1151:1024];
        4'd9:  select_round_key = keys[1279:1152];
        4'd10: select_round_key = keys[1407:1280];
        4'd11: select_round_key = keys[1535:1408];
        4'd12: select_round_key = keys[1663:1536];
        4'd13: select_round_key = keys[1791:1664];
        default: select_round_key = keys[1919:1792];
    endcase
end
endfunction

function [7:0] xtime;
input [7:0] value;
begin
    xtime = {value[6:0], 1'b0} ^ (value[7] ? 8'h1b : 8'h00);
end
endfunction

function [31:0] mix_column;
input [31:0] column;
reg [7:0] b0;
reg [7:0] b1;
reg [7:0] b2;
reg [7:0] b3;
begin
    b0 = column[31:24];
    b1 = column[23:16];
    b2 = column[15:8];
    b3 = column[7:0];
    mix_column[31:24] = xtime(b0) ^ (xtime(b1) ^ b1) ^ b2 ^ b3;
    mix_column[23:16] = b0 ^ xtime(b1) ^ (xtime(b2) ^ b2) ^ b3;
    mix_column[15:8]  = b0 ^ b1 ^ xtime(b2) ^ (xtime(b3) ^ b3);
    mix_column[7:0]   = (xtime(b0) ^ b0) ^ b1 ^ b2 ^ xtime(b3);
end
endfunction

function [127:0] shift_rows;
input [127:0] state;
begin
    shift_rows = {
        state[127:120], state[87:80],    state[47:40],   state[7:0],
        state[95:88],   state[55:48],    state[15:8],    state[103:96],
        state[63:56],   state[23:16],    state[111:104], state[71:64],
        state[31:24],   state[119:112],  state[79:72],   state[39:32]
    };
end
endfunction

function [127:0] mix_columns;
input [127:0] state;
begin
    mix_columns = {
        mix_column(state[127:96]),
        mix_column(state[95:64]),
        mix_column(state[63:32]),
        mix_column(state[31:0])
    };
end
endfunction

assign ctx0_can_issue_w = ctx0_valid_r && !ctx0_waiting_r;
assign ctx1_can_issue_w = ctx1_valid_r && !ctx1_waiting_r;
assign ctx2_can_issue_w = ctx2_valid_r && !ctx2_waiting_r;

// A waiting context owns the current S-box pipeline result, so this fixed
// priority naturally rotates when all three contexts are active.
assign issue_valid_w      = ctx0_can_issue_w || ctx1_can_issue_w ||
                            ctx2_can_issue_w;
assign issue_context_w    = ctx0_can_issue_w ? 2'd0 :
                            ctx1_can_issue_w ? 2'd1 : 2'd2;
assign issue_state_w      = ctx0_can_issue_w ? ctx0_state_r :
                            ctx1_can_issue_w ? ctx1_state_r :
                                               ctx2_state_r;
assign issue_round_w      = ctx0_can_issue_w ? ctx0_round_r :
                            ctx1_can_issue_w ? ctx1_round_r :
                                               ctx2_round_r;
assign issue_last_round_w = ctx0_can_issue_w ? ctx0_last_round_r :
                            ctx1_can_issue_w ? ctx1_last_round_r :
                                               ctx2_last_round_r;

assign key_size_valid_w = (key_size == KEY_SIZE_128) ||
                          (key_size == KEY_SIZE_192) ||
                          (key_size == KEY_SIZE_256);

// Look ahead to the result that will finish on the next edge.  This permits
// the just-freed context to accept its replacement on that same edge and
// preserves the average 10/12/14-clock block interval.
assign finish_now_w = xform_capacity_valid_r && xform_capacity_final_r;
assign contexts_exactly_two_w =
                    ( ctx0_valid_r &&  ctx1_valid_r && !ctx2_valid_r) ||
                    ( ctx0_valid_r && !ctx1_valid_r &&  ctx2_valid_r) ||
                    (!ctx0_valid_r &&  ctx1_valid_r &&  ctx2_valid_r);
assign capacity_w = !contexts_full_r || finish_now_w;
assign ready = capacity_w && key_size_valid_w;
assign accept_w = start && ready;

always @(posedge clk)
begin
    if(!rst_n)
        contexts_full_r <= 1'b0;
    else
    begin
        case({accept_w, finish_now_w})
            2'b10: contexts_full_r <= contexts_exactly_two_w;
            2'b01: contexts_full_r <= 1'b0;
            default: contexts_full_r <= contexts_full_r;
        endcase
    end
end

assign accept_context_w = !ctx0_valid_r ? 2'd0 :
                          !ctx1_valid_r ? 2'd1 :
                          !ctx2_valid_r ? 2'd2 : xform_context_r;
assign accepted_last_round_w = last_round_for_size(key_size);

genvar byte_index;
generate
    for(byte_index = 0; byte_index < 16; byte_index = byte_index + 1)
    begin : GEN_DATA_SBOX
        sbox #(.REGISTERED(1)) u_data_sbox
        (
            .clk   (clk),
            .rst_n (rst_n),
            // The output is ignored when issue_valid_w is low.  Keeping the
            // valid arbitration out of the BRAM address path is intentional.
            .a     (issue_state_w[127 - byte_index*8 -: 8]),
            .co    (sbox_output_w[127 - byte_index*8 -: 8])
        );
    end
endgenerate

assign shifted_state_w = shift_rows(sbox_output_w);
assign mixed_state_w   = mix_columns(xform_shifted_r);
assign round_result_w  = (xform_final_r ? xform_shifted_r :
                                           mixed_state_w) ^ xform_round_key_r;
assign selected_round_key0_w = select_round_key(round_keys,
                                                 pipe_round_index0_r);
assign selected_round_key1_w = select_round_key(round_keys,
                                                 pipe_round_index1_r);
assign selected_round_key2_w = select_round_key(round_keys,
                                                 pipe_round_index2_r);
assign selected_round_key3_w = select_round_key(round_keys,
                                                 pipe_round_index3_r);

always @(posedge clk)
begin
    if(!rst_n)
    begin
        ctx0_valid_r      <= 1'b0;
        ctx0_waiting_r    <= 1'b0;
        ctx0_state_r      <= 128'd0;
        ctx0_round_r      <= 4'd0;
        ctx0_last_round_r <= 4'd0;
        ctx1_valid_r      <= 1'b0;
        ctx1_waiting_r    <= 1'b0;
        ctx1_state_r      <= 128'd0;
        ctx1_round_r      <= 4'd0;
        ctx1_last_round_r <= 4'd0;
        ctx2_valid_r      <= 1'b0;
        ctx2_waiting_r    <= 1'b0;
        ctx2_state_r      <= 128'd0;
        ctx2_round_r      <= 4'd0;
        ctx2_last_round_r <= 4'd0;
        pipe_valid_r      <= 1'b0;
        pipe_context_r    <= 2'd0;
        pipe_final_r      <= 1'b0;
        pipe_round_index0_r <= 4'd0;
        pipe_round_index1_r <= 4'd0;
        pipe_round_index2_r <= 4'd0;
        pipe_round_index3_r <= 4'd0;
        xform_valid_r     <= 1'b0;
        xform_context_r   <= 2'd0;
        xform_final_r     <= 1'b0;
        xform_capacity_valid_r <= 1'b0;
        xform_capacity_final_r <= 1'b0;
        xform_shifted_r   <= 128'd0;
        xform_round_key_r <= 128'd0;
        done_r            <= 1'b0;
        block_out_r       <= 128'd0;
    end
    else
    begin
        done_r       <= 1'b0;
        pipe_valid_r <= issue_valid_w;

        if(issue_valid_w)
        begin
            pipe_context_r   <= issue_context_w;
            pipe_final_r     <= (issue_round_w == issue_last_round_w);
            pipe_round_index0_r <= issue_round_w;
            pipe_round_index1_r <= issue_round_w;
            pipe_round_index2_r <= issue_round_w;
            pipe_round_index3_r <= issue_round_w;

            case(issue_context_w)
                2'd0: ctx0_waiting_r <= 1'b1;
                2'd1: ctx1_waiting_r <= 1'b1;
                default: ctx2_waiting_r <= 1'b1;
            endcase
        end

        // Capture every cycle and qualify the contents only with xform_valid_r.
        // This avoids a high-fanout pipe_valid clock-enable net across all 260
        // transform-stage registers.
        xform_context_r   <= pipe_context_r;
        xform_final_r     <= pipe_final_r;
        xform_capacity_valid_r <= pipe_valid_r;
        xform_capacity_final_r <= pipe_final_r;
        xform_shifted_r   <= shifted_state_w;
        xform_round_key_r[31:0]   <= selected_round_key0_w[31:0];
        xform_round_key_r[63:32]  <= selected_round_key1_w[63:32];
        xform_round_key_r[95:64]  <= selected_round_key2_w[95:64];
        xform_round_key_r[127:96] <= selected_round_key3_w[127:96];

        xform_valid_r <= pipe_valid_r;

        if(xform_valid_r)
        begin
            case(xform_context_r)
            2'd0:
            begin
                if(xform_final_r)
                begin
                    ctx0_valid_r   <= 1'b0;
                    ctx0_waiting_r <= 1'b0;
                    block_out_r    <= round_result_w;
                    done_r         <= 1'b1;
                end
                else
                begin
                    ctx0_state_r   <= round_result_w;
                    ctx0_round_r   <= ctx0_round_r + 4'd1;
                    ctx0_waiting_r <= 1'b0;
                end
            end
            2'd1:
            begin
                if(xform_final_r)
                begin
                    ctx1_valid_r   <= 1'b0;
                    ctx1_waiting_r <= 1'b0;
                    block_out_r    <= round_result_w;
                    done_r         <= 1'b1;
                end
                else
                begin
                    ctx1_state_r   <= round_result_w;
                    ctx1_round_r   <= ctx1_round_r + 4'd1;
                    ctx1_waiting_r <= 1'b0;
                end
            end
            default:
            begin
                if(xform_final_r)
                begin
                    ctx2_valid_r   <= 1'b0;
                    ctx2_waiting_r <= 1'b0;
                    block_out_r    <= round_result_w;
                    done_r         <= 1'b1;
                end
                else
                begin
                    ctx2_state_r   <= round_result_w;
                    ctx2_round_r   <= ctx2_round_r + 4'd1;
                    ctx2_waiting_r <= 1'b0;
                end
            end
            endcase
        end

        // Keep this block after pipeline completion: when a finishing context
        // is reused on the same edge, the new request owns the final values.
        if(accept_w)
        begin
            case(accept_context_w)
            2'd0:
            begin
                ctx0_valid_r      <= 1'b1;
                ctx0_waiting_r    <= 1'b0;
                ctx0_state_r      <= block_in ^ round_keys[127:0];
                ctx0_round_r      <= 4'd1;
                ctx0_last_round_r <= accepted_last_round_w;
            end
            2'd1:
            begin
                ctx1_valid_r      <= 1'b1;
                ctx1_waiting_r    <= 1'b0;
                ctx1_state_r      <= block_in ^ round_keys[127:0];
                ctx1_round_r      <= 4'd1;
                ctx1_last_round_r <= accepted_last_round_w;
            end
            default:
            begin
                ctx2_valid_r      <= 1'b1;
                ctx2_waiting_r    <= 1'b0;
                ctx2_state_r      <= block_in ^ round_keys[127:0];
                ctx2_round_r      <= 4'd1;
                ctx2_last_round_r <= accepted_last_round_w;
            end
            endcase
        end
    end
end

assign busy      = ctx0_valid_r || ctx1_valid_r || ctx2_valid_r ||
                   pipe_valid_r || xform_valid_r;
assign done      = done_r;
assign block_out = block_out_r;

endmodule
