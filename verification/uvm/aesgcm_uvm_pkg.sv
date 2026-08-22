`timescale 1ns/1ps

package aesgcm_uvm_pkg;
    import uvm_pkg::*;
    import aesgcm_reference_model_pkg::*;
    `include "uvm_macros.svh"

    typedef enum int {BP_NONE, BP_DATA, BP_TAG, BP_RESULT, BP_ALL}
        backpressure_channel_e;
    typedef enum int {ZP_NONE, ZP_KEY_EXPAND, ZP_IV, ZP_AAD, ZP_DATA,
                      ZP_TAG_INPUT, ZP_TAG_OUTPUT, ZP_RESULT}
        zeroize_phase_e;
    typedef enum int {FAULT_NONE, FAULT_TAG_BIT, FAULT_CIPHERTEXT_BIT,
                      FAULT_EARLY_TLAST, FAULT_LATE_TLAST}
        injected_fault_e;

    class aesgcm_record_item extends uvm_sequence_item;
        rand bit [2:0] key_mode;
        rand bit [255:0] key;
        rand bit decrypt;
        rand int unsigned tag_bits;
        rand int unsigned iv_bits;
        rand int unsigned aad_bits;
        rand int unsigned data_bits;
        rand byte unsigned iv[];
        rand byte unsigned aad[];
        rand byte unsigned payload[];
        rand byte unsigned received_tag[];
        rand int unsigned input_gap_percent;
        rand backpressure_channel_e backpressure_channel;
        rand int unsigned backpressure_percent;
        rand zeroize_phase_e zeroize_phase;
        rand injected_fault_e injected_fault;
        byte unsigned observed_data[$];
        byte unsigned observed_tag[$];
        byte unsigned observed_result[$];
        int unsigned queue_depth;
        int unsigned ghash_digit_index;
        longint unsigned start_cycle, result_cycle;

        constraint legal_key_mode { key_mode inside {[0:2]}; }
        constraint legal_tag { tag_bits inside {32,64,96,104,112,120,128}; }
        constraint bounded_lengths {
            iv_bits inside {[1:2047]}; aad_bits inside {[0:2047]};
            data_bits inside {[0:2047]};
            iv.size() == ((iv_bits+7)/8);
            aad.size() == ((aad_bits+7)/8);
            payload.size() == ((data_bits+7)/8);
            if (decrypt) received_tag.size() == ((tag_bits+7)/8);
            else received_tag.size() == 0;
        }
        constraint legal_stalls {
            input_gap_percent inside {[0:90]};
            backpressure_percent inside {[0:90]};
        }

        `uvm_object_utils_begin(aesgcm_record_item)
            `uvm_field_int(key_mode, UVM_ALL_ON)
            `uvm_field_int(key, UVM_ALL_ON)
            `uvm_field_int(decrypt, UVM_ALL_ON)
            `uvm_field_int(tag_bits, UVM_ALL_ON)
            `uvm_field_int(iv_bits, UVM_ALL_ON)
            `uvm_field_int(aad_bits, UVM_ALL_ON)
            `uvm_field_int(data_bits, UVM_ALL_ON)
            `uvm_field_array_int(iv, UVM_ALL_ON)
            `uvm_field_array_int(aad, UVM_ALL_ON)
            `uvm_field_array_int(payload, UVM_ALL_ON)
            `uvm_field_array_int(received_tag, UVM_ALL_ON)
            `uvm_field_enum(backpressure_channel_e, backpressure_channel, UVM_ALL_ON)
            `uvm_field_enum(zeroize_phase_e, zeroize_phase, UVM_ALL_ON)
            `uvm_field_enum(injected_fault_e, injected_fault, UVM_ALL_ON)
        `uvm_object_utils_end
        function new(string name="aesgcm_record_item"); super.new(name); endfunction
    endclass

    class axi_lite_item extends uvm_sequence_item;
        rand bit write;
        rand bit [6:0] addr;
        rand bit [31:0] data;
        rand bit [3:0] strb;
        bit [2:0] key_mode;
        bit [1:0] response;
        `uvm_object_utils_begin(axi_lite_item)
            `uvm_field_int(write, UVM_ALL_ON)
            `uvm_field_int(addr, UVM_ALL_ON)
            `uvm_field_int(data, UVM_ALL_ON)
            `uvm_field_int(strb, UVM_ALL_ON)
            `uvm_field_int(key_mode, UVM_ALL_ON)
            `uvm_field_int(response, UVM_ALL_ON)
        `uvm_object_utils_end
        function new(string name="axi_lite_item"); super.new(name); strb=4'hf; endfunction
    endclass

    class axis_byte_item extends uvm_sequence_item;
        rand byte unsigned data;
        rand bit last;
        rand int unsigned gap_cycles;
        bit [3:0] user;
        `uvm_object_utils_begin(axis_byte_item)
            `uvm_field_int(data, UVM_ALL_ON)
            `uvm_field_int(last, UVM_ALL_ON)
            `uvm_field_int(gap_cycles, UVM_ALL_ON)
            `uvm_field_int(user, UVM_ALL_ON)
        `uvm_object_utils_end
        function new(string name="axis_byte_item"); super.new(name); endfunction
    endclass

    class ready_profile_item extends uvm_sequence_item;
        rand int unsigned stall_percent;
        rand int unsigned cycles;
        rand bit [15:0] lfsr_seed;
        constraint legal { stall_percent inside {[0:100]}; cycles > 0; lfsr_seed != 0; }
        `uvm_object_utils_begin(ready_profile_item)
            `uvm_field_int(stall_percent, UVM_ALL_ON)
            `uvm_field_int(cycles, UVM_ALL_ON)
            `uvm_field_int(lfsr_seed, UVM_ALL_ON)
        `uvm_object_utils_end
        function new(string name="ready_profile_item"); super.new(name); lfsr_seed=16'h1; endfunction
    endclass

    class axi_lite_sequencer extends uvm_sequencer #(axi_lite_item);
        `uvm_component_utils(axi_lite_sequencer)
        function new(string n, uvm_component p); super.new(n,p); endfunction
    endclass

    class axi_lite_driver extends uvm_driver #(axi_lite_item);
        `uvm_component_utils(axi_lite_driver)
        virtual axi_lite_if vif;
        function new(string n, uvm_component p); super.new(n,p); endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual axi_lite_if)::get(this,"","vif",vif))
                `uvm_fatal("NOVIF","AXI-Lite vif not configured")
        endfunction
        task run_phase(uvm_phase phase);
            axi_lite_item tr;
            vif.driver_cb.awvalid <= 0; vif.driver_cb.wvalid <= 0;
            vif.driver_cb.bready <= 1; vif.driver_cb.arvalid <= 0;
            vif.driver_cb.rready <= 1;
            wait(vif.aresetn===1'b1);
            @(vif.driver_cb);
            forever begin
                seq_item_port.get_next_item(tr);
                vif.driver_cb.key_mode <= tr.key_mode;
                if (tr.write) begin
                    vif.driver_cb.awaddr <= tr.addr; vif.driver_cb.awprot <= 0;
                    vif.driver_cb.wdata <= tr.data; vif.driver_cb.wstrb <= tr.strb;
                    vif.driver_cb.awvalid <= 1; vif.driver_cb.wvalid <= 1;
                    do @(vif.driver_cb); while (!(vif.driver_cb.awready && vif.driver_cb.wready));
                    vif.driver_cb.awvalid <= 0; vif.driver_cb.wvalid <= 0;
                    do @(vif.driver_cb); while (!vif.driver_cb.bvalid);
                    tr.response = vif.driver_cb.bresp;
                end else begin
                    vif.driver_cb.araddr <= tr.addr; vif.driver_cb.arprot <= 0;
                    vif.driver_cb.arvalid <= 1;
                    do @(vif.driver_cb); while (!vif.driver_cb.arready);
                    vif.driver_cb.arvalid <= 0;
                    do @(vif.driver_cb); while (!vif.driver_cb.rvalid);
                    tr.data = vif.driver_cb.rdata; tr.response = vif.driver_cb.rresp;
                end
                seq_item_port.item_done();
            end
        endtask
    endclass

    class axi_lite_monitor extends uvm_monitor;
        `uvm_component_utils(axi_lite_monitor)
        virtual axi_lite_if vif;
        uvm_analysis_port #(axi_lite_item) ap;
        function new(string n, uvm_component p); super.new(n,p); ap=new("ap",this); endfunction
        function void build_phase(uvm_phase phase);
            if (!uvm_config_db#(virtual axi_lite_if)::get(this,"","vif",vif))
                `uvm_fatal("NOVIF","AXI-Lite monitor vif not configured")
        endfunction
        task run_phase(uvm_phase phase);
            axi_lite_item tr;
            forever begin
                @(vif.monitor_cb);
                if (vif.monitor_cb.awvalid && vif.monitor_cb.awready &&
                    vif.monitor_cb.wvalid && vif.monitor_cb.wready) begin
                    tr=axi_lite_item::type_id::create("write"); tr.write=1;
                    tr.addr=vif.monitor_cb.awaddr; tr.data=vif.monitor_cb.wdata;
                    tr.strb=vif.monitor_cb.wstrb; ap.write(tr);
                end
                if (vif.monitor_cb.arvalid && vif.monitor_cb.arready) begin
                    tr=axi_lite_item::type_id::create("read"); tr.write=0;
                    tr.addr=vif.monitor_cb.araddr; ap.write(tr);
                end
            end
        endtask
    endclass

    class axi_lite_agent extends uvm_agent;
        `uvm_component_utils(axi_lite_agent)
        axi_lite_sequencer sequencer; axi_lite_driver driver; axi_lite_monitor monitor;
        function new(string n, uvm_component p); super.new(n,p); endfunction
        function void build_phase(uvm_phase phase);
            monitor=axi_lite_monitor::type_id::create("monitor",this);
            if (get_is_active()==UVM_ACTIVE) begin
                sequencer=axi_lite_sequencer::type_id::create("sequencer",this);
                driver=axi_lite_driver::type_id::create("driver",this);
            end
        endfunction
        function void connect_phase(uvm_phase phase);
            if (get_is_active()==UVM_ACTIVE) driver.seq_item_port.connect(sequencer.seq_item_export);
        endfunction
    endclass

    class axis_input_sequencer extends uvm_sequencer #(axis_byte_item);
        `uvm_component_utils(axis_input_sequencer)
        function new(string n, uvm_component p); super.new(n,p); endfunction
    endclass
    class axis_input_driver extends uvm_driver #(axis_byte_item);
        `uvm_component_utils(axis_input_driver)
        virtual axis_input_if vif;
        function new(string n, uvm_component p); super.new(n,p); endfunction
        function void build_phase(uvm_phase phase);
            if(!uvm_config_db#(virtual axis_input_if)::get(this,"","vif",vif))
                `uvm_fatal("NOVIF","input AXIS vif not configured")
        endfunction
        task run_phase(uvm_phase phase);
            axis_byte_item tr;
            vif.driver_cb.tvalid<=0; vif.driver_cb.tlast<=0;
            forever begin
                seq_item_port.get_next_item(tr);
                repeat(tr.gap_cycles) @(vif.driver_cb);
                vif.driver_cb.tdata<=tr.data; vif.driver_cb.tlast<=tr.last;
                vif.driver_cb.tvalid<=1;
                do @(vif.driver_cb); while(!vif.driver_cb.tready);
                vif.driver_cb.tvalid<=0; vif.driver_cb.tlast<=0;
                seq_item_port.item_done();
            end
        endtask
    endclass
    class axis_input_monitor extends uvm_monitor;
        `uvm_component_utils(axis_input_monitor)
        virtual axis_input_if vif; uvm_analysis_port #(axis_byte_item) ap;
        function new(string n,uvm_component p);super.new(n,p);ap=new("ap",this);endfunction
        function void build_phase(uvm_phase phase);
            if(!uvm_config_db#(virtual axis_input_if)::get(this,"","vif",vif))
                `uvm_fatal("NOVIF","input monitor vif not configured")
        endfunction
        task run_phase(uvm_phase phase); axis_byte_item tr;
            forever begin @(vif.monitor_cb);
                if(vif.monitor_cb.tvalid&&vif.monitor_cb.tready) begin
                    tr=axis_byte_item::type_id::create("input_beat");
                    tr.data=vif.monitor_cb.tdata; tr.last=vif.monitor_cb.tlast; ap.write(tr);
                end
            end
        endtask
    endclass
    class axis_input_agent extends uvm_agent;
        `uvm_component_utils(axis_input_agent)
        axis_input_sequencer sequencer; axis_input_driver driver; axis_input_monitor monitor;
        function new(string n,uvm_component p);super.new(n,p);endfunction
        function void build_phase(uvm_phase phase);
            monitor=axis_input_monitor::type_id::create("monitor",this);
            if(get_is_active()==UVM_ACTIVE) begin
                sequencer=axis_input_sequencer::type_id::create("sequencer",this);
                driver=axis_input_driver::type_id::create("driver",this);
            end
        endfunction
        function void connect_phase(uvm_phase phase);
            if(get_is_active()==UVM_ACTIVE)driver.seq_item_port.connect(sequencer.seq_item_export);
        endfunction
    endclass

    class output_ready_sequencer extends uvm_sequencer #(ready_profile_item);
        `uvm_component_utils(output_ready_sequencer)
        function new(string n,uvm_component p);super.new(n,p);endfunction
    endclass
    class output_ready_driver extends uvm_driver #(ready_profile_item);
        `uvm_component_utils(output_ready_driver)
        virtual axis_output_if #(4) vif;
        function new(string n,uvm_component p);super.new(n,p);endfunction
        function void build_phase(uvm_phase phase);
            if(!uvm_config_db#(virtual axis_output_if #(4))::get(this,"","vif",vif))
                `uvm_fatal("NOVIF","output AXIS vif not configured")
        endfunction
        task run_phase(uvm_phase phase); ready_profile_item tr; bit[15:0] lfsr;
            vif.driver_cb.tready<=1;
            forever begin
                seq_item_port.get_next_item(tr); lfsr=tr.lfsr_seed;
                repeat(tr.cycles) begin
                    @(vif.driver_cb);
                    lfsr={lfsr[14:0],lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
                    vif.driver_cb.tready<=((lfsr%100)>=tr.stall_percent);
                end
                vif.driver_cb.tready<=1; seq_item_port.item_done();
            end
        endtask
    endclass
    class axis_output_monitor extends uvm_monitor;
        `uvm_component_utils(axis_output_monitor)
        virtual axis_output_if #(4) vif; uvm_analysis_port #(axis_byte_item) ap;
        function new(string n,uvm_component p);super.new(n,p);ap=new("ap",this);endfunction
        function void build_phase(uvm_phase phase);
            if(!uvm_config_db#(virtual axis_output_if #(4))::get(this,"","vif",vif))
                `uvm_fatal("NOVIF","output monitor vif not configured")
        endfunction
        task run_phase(uvm_phase phase); axis_byte_item tr;
            forever begin @(vif.monitor_cb);
                if(vif.monitor_cb.tvalid&&vif.monitor_cb.tready) begin
                    tr=axis_byte_item::type_id::create("output_beat");
                    tr.data=vif.monitor_cb.tdata;tr.last=vif.monitor_cb.tlast;
                    tr.user=vif.monitor_cb.tuser;ap.write(tr);
                end
            end
        endtask
    endclass
    class axis_output_agent extends uvm_agent;
        `uvm_component_utils(axis_output_agent)
        output_ready_sequencer sequencer; output_ready_driver driver; axis_output_monitor monitor;
        function new(string n,uvm_component p);super.new(n,p);endfunction
        function void build_phase(uvm_phase phase);
            monitor=axis_output_monitor::type_id::create("monitor",this);
            if(get_is_active()==UVM_ACTIVE) begin
                sequencer=output_ready_sequencer::type_id::create("sequencer",this);
                driver=output_ready_driver::type_id::create("driver",this);
            end
        endfunction
        function void connect_phase(uvm_phase phase);
            if(get_is_active()==UVM_ACTIVE)driver.seq_item_port.connect(sequencer.seq_item_export);
        endfunction
    endclass

    class aesgcm_virtual_sequencer extends uvm_sequencer;
        `uvm_component_utils(aesgcm_virtual_sequencer)
        axi_lite_sequencer axi_lite_seqr;
        axis_input_sequencer input_seqr;
        output_ready_sequencer data_seqr, tag_seqr, result_seqr;
        function new(string n,uvm_component p);super.new(n,p);endfunction
    endclass

    `uvm_analysis_imp_decl(_record)
    class aesgcm_scoreboard extends uvm_component;
        `uvm_component_utils(aesgcm_scoreboard)
        uvm_analysis_imp_record #(aesgcm_record_item,aesgcm_scoreboard) record_imp;
        int unsigned checked, failed;
        function new(string n,uvm_component p);super.new(n,p);record_imp=new("record_imp",this);endfunction
        function void write_record(aesgcm_record_item tr);
            byte_queue_t iv_q,aad_q,payload_q,recv_q,expected_data,expected_tag;
            bit auth_ok;
            foreach(tr.iv[i])iv_q.push_back(tr.iv[i]);
            foreach(tr.aad[i])aad_q.push_back(tr.aad[i]);
            foreach(tr.payload[i])payload_q.push_back(tr.payload[i]);
            foreach(tr.received_tag[i])recv_q.push_back(tr.received_tag[i]);
            aesgcm_reference_model::predict(tr.key_mode,tr.key,tr.decrypt,
                tr.tag_bits,tr.iv_bits,tr.aad_bits,tr.data_bits,iv_q,aad_q,
                payload_q,recv_q,expected_data,expected_tag,auth_ok);
            checked++;
            if((!tr.decrypt || auth_ok) && tr.observed_data!=expected_data) begin
                failed++; `uvm_error("DATA",$sformatf(
                    "payload mismatch expected_size=%0d observed_size=%0d expected=%p observed=%p",
                    expected_data.size(),tr.observed_data.size(),
                    expected_data,tr.observed_data))
            end
            if(tr.decrypt && !auth_ok && tr.observed_data.size()!=0) begin
                failed++; `uvm_error("DATA","unauthenticated plaintext was released")
            end
            if(!tr.decrypt && tr.observed_tag!=expected_tag) begin failed++; `uvm_error("TAG","tag mismatch") end
            if(tr.observed_result.size()!=1) begin failed++; `uvm_error("RESULT","missing/multiple result") end
            else if(!tr.decrypt && tr.observed_result[0]!=8'h00) begin
                failed++; `uvm_error("RESULT","encrypt result code mismatch")
            end
            else if(tr.decrypt && ((tr.observed_result[0]==8'h01)!=auth_ok)) begin
                failed++; `uvm_error("AUTH","authentication result mismatch")
            end
        endfunction
        function void report_phase(uvm_phase phase);
            `uvm_info("SCOREBOARD",$sformatf("checked=%0d failed=%0d",checked,failed),UVM_LOW)
            if(failed!=0)`uvm_error("SCOREBOARD","scoreboard failures present")
        endfunction
    endclass

`ifdef MODELSIM_STARTER
    class aesgcm_coverage extends uvm_subscriber #(aesgcm_record_item);
        `uvm_component_utils(aesgcm_coverage)
        int unsigned samples;
        function new(string n,uvm_component p);super.new(n,p);endfunction
        function void write(aesgcm_record_item t);samples++;endfunction
        function real coverage_percent();return 0.0;endfunction
        function bit required_bins_covered();return 0;endfunction
        function void report_phase(uvm_phase phase);
            `uvm_info("COVERAGE",$sformatf("NOT_COLLECTED modelsim_starter samples=%0d",samples),UVM_LOW)
        endfunction
    endclass
`else
    class aesgcm_coverage extends uvm_subscriber #(aesgcm_record_item);
        `uvm_component_utils(aesgcm_coverage)
        int unsigned samples;
        int key_mode_s,mode_s,iv_kind_s,aad_kind_s,data_kind_s,auth_s;
        covergroup cg;
            option.per_instance=1;
            cp_key: coverpoint key_mode_s { bins aes128={0};bins aes192={1};bins aes256={2}; }
            cp_mode: coverpoint mode_s { bins encrypt={0};bins decrypt={1}; }
            cp_iv_kind: coverpoint iv_kind_s {
                bins standard_96={0};bins non_96={1};
            }
            cp_aad_kind: coverpoint aad_kind_s {
                bins empty={0};bins short={1};bins one_block={2};bins multi_block={3};
            }
            cp_data_kind: coverpoint data_kind_s {
                bins empty={0};bins short={1};bins one_block={2};bins multi_block={3};
            }
            cp_auth: coverpoint auth_s iff(mode_s==1) {
                bins fail={0};bins pass={1};
            }
            cx_key_mode: cross cp_key,cp_mode;
            cx_mode_iv: cross cp_mode,cp_iv_kind;
            cx_mode_data: cross cp_mode,cp_data_kind;
        endgroup
        function new(string n,uvm_component p);super.new(n,p);cg=new;endfunction
        function int length_kind(int unsigned bits);
            if(bits==0)return 0;
            if(bits<128)return 1;
            if(bits==128)return 2;
            return 3;
        endfunction
        function void write(aesgcm_record_item t);
            samples++;
            key_mode_s=t.key_mode;mode_s=t.decrypt;
            iv_kind_s=(t.iv_bits==96)?0:1;
            aad_kind_s=length_kind(t.aad_bits);
            data_kind_s=length_kind(t.data_bits);
            auth_s=(t.observed_result.size()&&t.observed_result[0]==8'h01);
            cg.sample();
        endfunction
        function real coverage_percent();return cg.get_inst_coverage();endfunction
        function bit required_bins_covered();return coverage_percent()>=99.99;endfunction
        function void report_phase(uvm_phase phase);
            `uvm_info("COVERAGE",$sformatf("samples=%0d coverage_pct=%0.2f required_bins=%s",
                samples,coverage_percent(),required_bins_covered()?"COVERED":"MISSING"),UVM_LOW)
        endfunction
    endclass
`endif

    // Passive monitor configuration/reconstruction is deliberately separate
    // from the active agents so scoreboard input cannot reuse driver objects.
    class passive_record_reconstruction_monitor extends uvm_monitor;
        `uvm_component_utils(passive_record_reconstruction_monitor)
        uvm_analysis_port #(aesgcm_record_item) ap;
        virtual axi_lite_if control_vif;
        virtual axis_input_if input_vif;
        virtual axis_output_if #(4) data_vif,tag_vif,result_vif;
        bit [255:0] staged_key;
        bit decrypt_cfg;
        int unsigned tag_bits_cfg,iv_bits_cfg,aad_bits_cfg,data_bits_cfg;
        aesgcm_record_item current;
        int unsigned input_byte_index;
        function new(string n,uvm_component p);super.new(n,p);ap=new("ap",this);endfunction
        function void build_phase(uvm_phase phase);
            if(!uvm_config_db#(virtual axi_lite_if)::get(this,"","control_vif",control_vif) ||
               !uvm_config_db#(virtual axis_input_if)::get(this,"","input_vif",input_vif) ||
               !uvm_config_db#(virtual axis_output_if #(4))::get(this,"","data_vif",data_vif) ||
               !uvm_config_db#(virtual axis_output_if #(4))::get(this,"","tag_vif",tag_vif) ||
               !uvm_config_db#(virtual axis_output_if #(4))::get(this,"","result_vif",result_vif))
                `uvm_fatal("NOVIF","record reconstruction vifs not configured")
            tag_bits_cfg=128;
        endfunction
        function void observe_write(bit[6:0] addr,bit[31:0] data);
            case(addr)
                7'h08: begin decrypt_cfg=data[0];tag_bits_cfg=data[15:8];end
                7'h0c: iv_bits_cfg=data[10:0];
                7'h10: aad_bits_cfg=data[10:0];
                7'h14: data_bits_cfg=data[10:0];
                7'h20,7'h24,7'h28,7'h2c,7'h30,7'h34,7'h38,7'h3c:
                    staged_key[255-8*(addr-7'h20)-:32]=data;
                7'h00: if(data[0]) begin
                    current=aesgcm_record_item::type_id::create("reconstructed");
                    current.key_mode=control_vif.monitor_cb.key_mode;
                    current.key=staged_key;current.decrypt=decrypt_cfg;
                    current.tag_bits=tag_bits_cfg;current.iv_bits=iv_bits_cfg;
                    current.aad_bits=aad_bits_cfg;current.data_bits=data_bits_cfg;
                    current.iv=new[(iv_bits_cfg+7)/8];
                    current.aad=new[(aad_bits_cfg+7)/8];
                    current.payload=new[(data_bits_cfg+7)/8];
                    if(decrypt_cfg)current.received_tag=new[(tag_bits_cfg+7)/8];
                    input_byte_index=0;
                end
                default: ;
            endcase
        endfunction
        function void observe_input(byte unsigned data);
            int unsigned iv_n,aad_n,data_n,index;
            if(current==null)return;
            iv_n=current.iv.size();aad_n=current.aad.size();data_n=current.payload.size();
            index=input_byte_index++;
            if(index<iv_n)current.iv[index]=data;
            else if(index<(iv_n+aad_n))current.aad[index-iv_n]=data;
            else if(index<(iv_n+aad_n+data_n))current.payload[index-iv_n-aad_n]=data;
            else if(current.decrypt && index<(iv_n+aad_n+data_n+current.received_tag.size()))
                current.received_tag[index-iv_n-aad_n-data_n]=data;
        endfunction
        function bit current_outputs_complete();
            int unsigned data_bytes,tag_bytes;
            if(current==null||current.observed_result.size()!=1)return 0;
            data_bytes=(current.data_bits+7)/8;
            tag_bytes=(current.tag_bits+7)/8;
            if(current.decrypt)begin
                if(current.observed_result[0]!=8'h01)return 1;
                return current.observed_data.size()==data_bytes;
            end
            return current.observed_data.size()==data_bytes&&
                   current.observed_tag.size()==tag_bytes;
        endfunction
        task run_phase(uvm_phase phase);
            forever begin
                @(control_vif.monitor_cb);
                if(!control_vif.monitor_cb.aresetn) begin current=null;staged_key=0;end
                if(control_vif.monitor_cb.awvalid&&control_vif.monitor_cb.awready&&
                   control_vif.monitor_cb.wvalid&&control_vif.monitor_cb.wready)
                    observe_write(control_vif.monitor_cb.awaddr,control_vif.monitor_cb.wdata);
                if(input_vif.monitor_cb.tvalid&&input_vif.monitor_cb.tready)
                    observe_input(input_vif.monitor_cb.tdata);
                if(data_vif.monitor_cb.tvalid&&data_vif.monitor_cb.tready)begin
                    if(current==null)`uvm_error("ORPHAN_DATA","data beat without active record")
                    else current.observed_data.push_back(data_vif.monitor_cb.tdata);
                end
                if(tag_vif.monitor_cb.tvalid&&tag_vif.monitor_cb.tready)begin
                    if(current==null)`uvm_error("ORPHAN_TAG","tag beat without active record")
                    else current.observed_tag.push_back(tag_vif.monitor_cb.tdata);
                end
                if(result_vif.monitor_cb.tvalid&&result_vif.monitor_cb.tready)begin
                    if(current==null)`uvm_error("ORPHAN_RESULT","result beat without active record")
                    else current.observed_result.push_back(result_vif.monitor_cb.tdata);
                end
                if(current_outputs_complete())begin ap.write(current);current=null;end
            end
        endtask
    endclass

    class aesgcm_env extends uvm_env;
        `uvm_component_utils(aesgcm_env)
        axi_lite_agent axi_lite;
        axis_input_agent input_axis;
        axis_output_agent data_output,tag_output,result_output;
        passive_record_reconstruction_monitor reconstruction;
        aesgcm_virtual_sequencer virtual_sequencer;
        aesgcm_scoreboard scoreboard; aesgcm_coverage coverage;
        function new(string n,uvm_component p);super.new(n,p);endfunction
        function void build_phase(uvm_phase phase);
            axi_lite=axi_lite_agent::type_id::create("axi_lite",this);
            input_axis=axis_input_agent::type_id::create("input_axis",this);
            data_output=axis_output_agent::type_id::create("data_output",this);
            tag_output=axis_output_agent::type_id::create("tag_output",this);
            result_output=axis_output_agent::type_id::create("result_output",this);
            reconstruction=passive_record_reconstruction_monitor::type_id::create("reconstruction",this);
            virtual_sequencer=aesgcm_virtual_sequencer::type_id::create("virtual_sequencer",this);
            scoreboard=aesgcm_scoreboard::type_id::create("scoreboard",this);
            coverage=aesgcm_coverage::type_id::create("coverage",this);
        endfunction
        function void connect_phase(uvm_phase phase);
            virtual_sequencer.axi_lite_seqr=axi_lite.sequencer;
            virtual_sequencer.input_seqr=input_axis.sequencer;
            virtual_sequencer.data_seqr=data_output.sequencer;
            virtual_sequencer.tag_seqr=tag_output.sequencer;
            virtual_sequencer.result_seqr=result_output.sequencer;
            reconstruction.ap.connect(scoreboard.record_imp);
            reconstruction.ap.connect(coverage.analysis_export);
        endfunction
    endclass

    class aesgcm_virtual_sequence_base extends uvm_sequence;
        `uvm_object_utils(aesgcm_virtual_sequence_base)
        `uvm_declare_p_sequencer(aesgcm_virtual_sequencer)
        aesgcm_record_item record;
        function new(string n="aesgcm_virtual_sequence_base");super.new(n);endfunction
        virtual function void configure();
            record=aesgcm_record_item::type_id::create("record");
`ifdef MODELSIM_STARTER
            record.key_mode=0;record.key='0;record.decrypt=0;
            record.tag_bits=128;record.iv_bits=96;record.aad_bits=0;
            record.data_bits=128;record.iv=new[12];record.aad=new[0];
            record.payload=new[16];record.received_tag=new[0];
            foreach(record.iv[i])record.iv[i]=0;
            foreach(record.payload[i])record.payload[i]=0;
`else
            if(!record.randomize() with {key_mode==0;decrypt==0;tag_bits==128;
                iv_bits==96;aad_bits==0;data_bits==128;})
                `uvm_fatal("RAND","default record randomization failed")
`endif
        endfunction
        task write_reg(bit[6:0] addr,bit[31:0] data);
            axi_lite_item tr=axi_lite_item::type_id::create("wr");
            tr.write=1;tr.addr=addr;tr.data=data;tr.strb=4'hf;
            tr.key_mode=record.key_mode;
            start_item(tr,-1,p_sequencer.axi_lite_seqr);
            finish_item(tr);
            if(tr.response!=0)`uvm_error("AXI",$sformatf("write %02h failed",addr))
        endtask
        task read_reg(bit[6:0] addr,output bit[31:0] data);
            axi_lite_item tr=axi_lite_item::type_id::create("rd");
            tr.write=0;tr.addr=addr;tr.key_mode=record.key_mode;
            start_item(tr,-1,p_sequencer.axi_lite_seqr);
            finish_item(tr);data=tr.data;
            if(tr.response!=0)`uvm_error("AXI",$sformatf("read %02h failed",addr))
        endtask
        task body();
            byte_queue_t ingress;
            bit[31:0] status;
            int polls;
            configure();
            for(int i=0;i<8;i++)write_reg(7'h20+4*i,record.key[255-32*i-:32]);
            write_reg(7'h00,32'h2);
            polls=0;
            do begin
                read_reg(7'h04,status);polls++;
                if(polls>1000)`uvm_fatal("TIMEOUT","key expansion did not become ready")
            end while(!status[0]);
            write_reg(7'h08,{16'd0,record.tag_bits[7:0],7'd0,record.decrypt});
            write_reg(7'h0c,record.iv_bits);write_reg(7'h10,record.aad_bits);
            write_reg(7'h14,record.data_bits);write_reg(7'h00,32'h1);
            foreach(record.iv[i])ingress.push_back(record.iv[i]);
            foreach(record.aad[i])ingress.push_back(record.aad[i]);
            foreach(record.payload[i])ingress.push_back(record.payload[i]);
            foreach(record.received_tag[i])ingress.push_back(record.received_tag[i]);
            foreach(ingress[i])send_byte(ingress[i],i==ingress.size()-1);
        endtask
        task send_byte(byte unsigned data,bit last);
            axis_byte_item tr=axis_byte_item::type_id::create("byte");
            tr.data=data;tr.last=last;
            if(record.input_gap_percent!=0&&
               $urandom_range(99,0)<record.input_gap_percent)
                tr.gap_cycles=$urandom_range(3,1);
            else
                tr.gap_cycles=0;
            start_item(tr,-1,p_sequencer.input_seqr);
            finish_item(tr);
        endtask
    endclass

    `define DECLARE_AESGCM_SEQUENCE(CLASS_NAME) \
      class CLASS_NAME extends aesgcm_virtual_sequence_base; \
        `uvm_object_utils(CLASS_NAME) \
        function new(string n=`"CLASS_NAME`");super.new(n);endfunction \
      endclass

    `DECLARE_AESGCM_SEQUENCE(ghash_known_answer)
    `DECLARE_AESGCM_SEQUENCE(ghash_random)
    `DECLARE_AESGCM_SEQUENCE(ghash_single_bit)
    `DECLARE_AESGCM_SEQUENCE(reset_each_digit)
    `DECLARE_AESGCM_SEQUENCE(aes128_sequence)
    `DECLARE_AESGCM_SEQUENCE(aes192_sequence)
    `DECLARE_AESGCM_SEQUENCE(aes256_sequence)
    `DECLARE_AESGCM_SEQUENCE(nist_cavp_sequence)
    `DECLARE_AESGCM_SEQUENCE(boundary_lengths_sequence)
    `DECLARE_AESGCM_SEQUENCE(non_96_bit_iv_sequence)
    `DECLARE_AESGCM_SEQUENCE(partial_final_byte_sequence)
    `DECLARE_AESGCM_SEQUENCE(auth_fail_tag_bit_flip_sequence)
    `DECLARE_AESGCM_SEQUENCE(auth_fail_ciphertext_bit_flip_sequence)
    `DECLARE_AESGCM_SEQUENCE(random_input_gaps_sequence)
    `DECLARE_AESGCM_SEQUENCE(random_output_backpressure_sequence)
    `DECLARE_AESGCM_SEQUENCE(descriptor_queue_full_sequence)
    `DECLARE_AESGCM_SEQUENCE(multi_packet_sequence)
    `DECLARE_AESGCM_SEQUENCE(mixed_key_modes_rekey_sequence)
    `DECLARE_AESGCM_SEQUENCE(zeroize_each_major_phase_sequence)
    `DECLARE_AESGCM_SEQUENCE(early_tlast_sequence)
    `DECLARE_AESGCM_SEQUENCE(late_tlast_sequence)
    `DECLARE_AESGCM_SEQUENCE(short_variable_tag_sequence)
    `DECLARE_AESGCM_SEQUENCE(full_throughput_sequence)
    `undef DECLARE_AESGCM_SEQUENCE

    class aesgcm_constrained_random_sequence extends aesgcm_virtual_sequence_base;
        `uvm_object_utils(aesgcm_constrained_random_sequence)
        int unsigned scenario_index;
        bit auth_fail_goal;
        function new(string n="aesgcm_constrained_random_sequence");super.new(n);endfunction

        function string scenario_name();
            case(scenario_index)
                0:return "aes128_encrypt_empty";
                1:return "aes128_decrypt_short";
                2:return "aes192_encrypt_block";
                3:return "aes192_decrypt_multi";
                4:return "aes256_encrypt_short";
                5:return "aes256_decrypt_block_bad_tag";
                6:return "aes128_encrypt_multi";
                7:return "aes128_decrypt_empty";
                default:return "invalid";
            endcase
        endfunction

        function bit randomize_record(
            int unsigned key_goal,
            bit decrypt_goal,
            int unsigned iv_kind_goal,
            int unsigned aad_kind_goal,
            int unsigned data_kind_goal
        );
            return record.randomize() with {
                key_mode==local::key_goal;
                decrypt==local::decrypt_goal;
                tag_bits==128;
                if(local::iv_kind_goal==0)iv_bits==96;
                else iv_bits inside {64,128};
                if(local::aad_kind_goal==0)aad_bits==0;
                else if(local::aad_kind_goal==1)aad_bits inside {8,64,120};
                else if(local::aad_kind_goal==2)aad_bits==128;
                else aad_bits inside {136,256,512};
                if(local::data_kind_goal==0)data_bits==0;
                else if(local::data_kind_goal==1)data_bits inside {8,64,120};
                else if(local::data_kind_goal==2)data_bits==128;
                else data_bits inside {136,256,512};
                input_gap_percent inside {0,25,50};
                backpressure_channel==BP_NONE;
                backpressure_percent==0;
                zeroize_phase==ZP_NONE;
                injected_fault==FAULT_NONE;
            };
        endfunction

        function void prepare_decrypt_input();
            byte_queue_t iv_q,aad_q,plaintext_q,no_tag_q,ciphertext_q,tag_q;
            bit auth_ok;
            foreach(record.iv[i])iv_q.push_back(record.iv[i]);
            foreach(record.aad[i])aad_q.push_back(record.aad[i]);
            foreach(record.payload[i])plaintext_q.push_back(record.payload[i]);
            aesgcm_reference_model::predict(record.key_mode,record.key,1'b0,
                record.tag_bits,record.iv_bits,record.aad_bits,record.data_bits,
                iv_q,aad_q,plaintext_q,no_tag_q,ciphertext_q,tag_q,auth_ok);
            record.payload=new[ciphertext_q.size()];
            foreach(record.payload[i])record.payload[i]=ciphertext_q[i];
            record.received_tag=new[tag_q.size()];
            foreach(record.received_tag[i])record.received_tag[i]=tag_q[i];
            if(auth_fail_goal&&record.received_tag.size()!=0)
                record.received_tag[0]^=8'h01;
        endfunction

        virtual function void configure();
            bit randomized;
            record=aesgcm_record_item::type_id::create("record");
            auth_fail_goal=0;
            case(scenario_index)
                0:randomized=randomize_record(0,0,0,0,0);
                1:randomized=randomize_record(0,1,1,1,1);
                2:randomized=randomize_record(1,0,0,2,2);
                3:randomized=randomize_record(1,1,1,3,3);
                4:randomized=randomize_record(2,0,1,1,1);
                5:begin randomized=randomize_record(2,1,0,2,2);auth_fail_goal=1;end
                6:randomized=randomize_record(0,0,1,3,3);
                7:randomized=randomize_record(0,1,0,0,0);
                default:`uvm_fatal("SCENARIO",$sformatf("invalid scenario index %0d",scenario_index))
            endcase
            if(!randomized)
                `uvm_fatal("RAND",$sformatf("scenario %0d randomization failed",scenario_index))
            if(record.decrypt)prepare_decrypt_input();
            `uvm_info("SCENARIO",$sformatf(
                "index=%0d name=%s key_mode=%0d decrypt=%0d iv_bits=%0d aad_bits=%0d data_bits=%0d gap_pct=%0d auth_fail=%0d",
                scenario_index,scenario_name(),record.key_mode,record.decrypt,
                record.iv_bits,record.aad_bits,record.data_bits,
                record.input_gap_percent,auth_fail_goal),UVM_LOW)
        endfunction
    endclass

    class aesgcm_uvm_test extends uvm_test;
        `uvm_component_utils(aesgcm_uvm_test)
        aesgcm_env env;
        function new(string n,uvm_component p);super.new(n,p);endfunction
        function void build_phase(uvm_phase phase);env=aesgcm_env::type_id::create("env",this);endfunction
        task run_phase(uvm_phase phase);
            aes128_sequence seq=aes128_sequence::type_id::create("seq");
            bit completed;
            phase.raise_objection(this);
            seq.start(env.virtual_sequencer);
            fork
                begin
                    wait(env.scoreboard.checked!=0);
                    completed=1;
                end
                begin
                    #20us;
                    if(!completed)`uvm_fatal("TIMEOUT","scoreboard did not receive a completed record")
                end
            join_any
            disable fork;
            phase.drop_objection(this);
        endtask
    endclass

    class aesgcm_xsim_random_test extends uvm_test;
        `uvm_component_utils(aesgcm_xsim_random_test)
        aesgcm_env env;
        int unsigned records_expected;
        int unsigned run_seed;
        int unsigned final_error_count;
        int unsigned final_fatal_count;
        real final_coverage;
        bit final_pass;
        function new(string n,uvm_component p);
            super.new(n,p);records_expected=8;
        endfunction
        function void build_phase(uvm_phase phase);
            env=aesgcm_env::type_id::create("env",this);
            if(!$value$plusargs("UVM_SEED_%d",run_seed))run_seed=0;
        endfunction
        task run_phase(uvm_phase phase);
            aesgcm_constrained_random_sequence seq;
            int unsigned checked_before;
            bit completed;
            phase.raise_objection(this);
            for(int unsigned i=0;i<records_expected;i++)begin
                seq=aesgcm_constrained_random_sequence::type_id::create(
                    $sformatf("scenario_%0d",i));
                seq.scenario_index=i;
                checked_before=env.scoreboard.checked;
                completed=0;
                fork
                    begin
                        seq.start(env.virtual_sequencer);
                        wait(env.scoreboard.checked==checked_before+1);
                        completed=1;
                    end
                    begin
                        #100us;
                        if(!completed)
                            `uvm_fatal("TIMEOUT",$sformatf("scenario %0d did not complete",i))
                    end
                join_any
                disable fork;
            end
            phase.drop_objection(this);
        endtask
        function void check_phase(uvm_phase phase);
            final_coverage=env.coverage.coverage_percent();
            if(env.scoreboard.checked!=records_expected)
                `uvm_error("REGRESSION",$sformatf("checked=%0d expected=%0d",
                    env.scoreboard.checked,records_expected))
            if(!env.coverage.required_bins_covered())
                `uvm_error("REGRESSION",$sformatf("required coverage missing: %0.2f%%",
                    final_coverage))
        endfunction
        function void report_phase(uvm_phase phase);
            uvm_report_server report_server;
            report_server=uvm_report_server::get_server();
            final_error_count=report_server.get_severity_count(UVM_ERROR);
            final_fatal_count=report_server.get_severity_count(UVM_FATAL);
            final_pass=(env.scoreboard.checked==records_expected)&&
                       (env.scoreboard.failed==0)&&
                       env.coverage.required_bins_covered()&&
                       (final_error_count==0)&&(final_fatal_count==0);
            $display("UVM_REGRESSION_RESULT status=%s seed=%0d records=%0d scoreboard_failed=%0d uvm_errors=%0d uvm_fatals=%0d coverage_pct=%0.2f",
                final_pass?"PASS":"FAIL",run_seed,env.scoreboard.checked,
                env.scoreboard.failed,final_error_count,final_fatal_count,
                final_coverage);
        endfunction
    endclass
endpackage
