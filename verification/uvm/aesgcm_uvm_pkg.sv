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
                failed++; `uvm_error("DATA","payload mismatch")
            end
            if(tr.decrypt && !auth_ok && tr.observed_data.size()!=0) begin
                failed++; `uvm_error("DATA","unauthenticated plaintext was released")
            end
            if(!tr.decrypt && tr.observed_tag!=expected_tag) begin failed++; `uvm_error("TAG","tag mismatch") end
            if(tr.observed_result.size()!=1) begin failed++; `uvm_error("RESULT","missing/multiple result") end
            else if(tr.decrypt && ((tr.observed_result[0]==8'h01)!=auth_ok)) begin
                failed++; `uvm_error("AUTH","authentication result mismatch")
            end
        endfunction
        function void report_phase(uvm_phase phase);
            `uvm_info("SCOREBOARD",$sformatf("checked=%0d failed=%0d",checked,failed),UVM_LOW)
            if(failed!=0)`uvm_error("SCOREBOARD","scoreboard failures present")
        endfunction
    endclass

    class aesgcm_coverage extends uvm_subscriber #(aesgcm_record_item);
        `uvm_component_utils(aesgcm_coverage)
        int key_mode_s,enc_dec_s,tag_s,iv_s,aad_s,data_s,partial_s,result_s;
        int bp_s,depth_s,zeroize_s,auth_s,digit_s,fault_s,state_s;
        covergroup cg;
            cp_key: coverpoint key_mode_s { bins aes128={0};bins aes192={1};bins aes256={2}; }
            cp_enc: coverpoint enc_dec_s { bins enc={0};bins dec={1}; }
            cp_tag: coverpoint tag_s { bins legal[]={32,64,96,104,112,120,128}; }
            cp_iv: coverpoint iv_s { bins boundary[]={1,7,8,9,95,96,97,127,128,129,2047}; }
            cp_aad: coverpoint aad_s { bins boundary[]={0,1,7,8,9,127,128,129,255,256,257,2047}; }
            cp_data: coverpoint data_s { bins boundary[]={0,1,7,8,9,127,128,129,255,256,257,2047}; }
            cp_partial: coverpoint partial_s { bins valid_bits[]={[0:7]}; }
            cp_result: coverpoint result_s { bins codes[]={[0:15]}; }
            cp_bp: coverpoint bp_s { bins channels[]={[0:4]}; }
            cp_depth: coverpoint depth_s { bins depth[]={[0:4]}; }
            cp_zeroize: coverpoint zeroize_s { bins phases[]={[0:7]}; }
            cp_auth: coverpoint auth_s { bins fail={0};bins pass={1}; }
            cp_digit: coverpoint digit_s { bins digits[]={[0:7]}; }
            cp_fault: coverpoint fault_s { bins kinds[]={[0:4]}; }
            cp_state: coverpoint state_s { bins states[]={[0:15]}; }
            cx_key_enc_tag: cross cp_key,cp_enc,cp_tag;
            cx_key_iv: cross cp_key,cp_iv;
            cx_enc_data: cross cp_enc,cp_data;
            cx_result_fault: cross cp_result,cp_fault;
            cx_zeroize_state: cross cp_zeroize,cp_state;
            cx_bp_enc: cross cp_bp,cp_enc;
        endgroup
        function new(string n,uvm_component p);super.new(n,p);cg=new;endfunction
        function void write(aesgcm_record_item tr);
            key_mode_s=tr.key_mode;enc_dec_s=tr.decrypt;tag_s=tr.tag_bits;
            iv_s=tr.iv_bits;aad_s=tr.aad_bits;data_s=tr.data_bits;
            partial_s=tr.data_bits%8;bp_s=tr.backpressure_channel;
            depth_s=tr.queue_depth;zeroize_s=tr.zeroize_phase;
            fault_s=tr.injected_fault;digit_s=tr.ghash_digit_index;
            result_s=(tr.observed_result.size()?tr.observed_result[0]:-1);
            auth_s=(result_s==0||result_s==1);state_s=0;cg.sample();
        endfunction
    endclass

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
        task run_phase(uvm_phase phase);
            forever begin
                @(control_vif.monitor_cb);
                if(!control_vif.monitor_cb.aresetn) begin current=null;staged_key=0;end
                if(control_vif.monitor_cb.awvalid&&control_vif.monitor_cb.awready&&
                   control_vif.monitor_cb.wvalid&&control_vif.monitor_cb.wready)
                    observe_write(control_vif.monitor_cb.awaddr,control_vif.monitor_cb.wdata);
                if(input_vif.monitor_cb.tvalid&&input_vif.monitor_cb.tready)
                    observe_input(input_vif.monitor_cb.tdata);
                if(current!=null&&data_vif.monitor_cb.tvalid&&data_vif.monitor_cb.tready)
                    current.observed_data.push_back(data_vif.monitor_cb.tdata);
                if(current!=null&&tag_vif.monitor_cb.tvalid&&tag_vif.monitor_cb.tready)
                    current.observed_tag.push_back(tag_vif.monitor_cb.tdata);
                if(current!=null&&result_vif.monitor_cb.tvalid&&result_vif.monitor_cb.tready) begin
                    current.observed_result.push_back(result_vif.monitor_cb.tdata);
                    ap.write(current);current=null;
                end
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
            if(!record.randomize() with {key_mode==0;decrypt==0;tag_bits==128;
                iv_bits==96;aad_bits==0;data_bits==128;})
                `uvm_fatal("RAND","default record randomization failed")
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
            tr.data=data;tr.last=last;tr.gap_cycles=0;
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

    class aesgcm_uvm_test extends uvm_test;
        `uvm_component_utils(aesgcm_uvm_test)
        aesgcm_env env;
        function new(string n,uvm_component p);super.new(n,p);endfunction
        function void build_phase(uvm_phase phase);env=aesgcm_env::type_id::create("env",this);endfunction
        task run_phase(uvm_phase phase);
            aes128_sequence seq=aes128_sequence::type_id::create("seq");
            phase.raise_objection(this);
            seq.start(env.virtual_sequencer);
            phase.phase_done.set_drain_time(this,100us);
            phase.drop_objection(this);
        endtask
    endclass
endpackage
