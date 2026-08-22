`timescale 1ns/1ps

module tb_reference_model;
    import aesgcm_reference_model_pkg::*;
    bit [255:0] key;
    bit [127:0] value;
    byte_queue_t iv, aad, payload, received_tag, output_bytes, tag_bytes;
    bit auth_ok;

    initial begin
        key = {128'h000102030405060708090a0b0c0d0e0f, 128'd0};
        value = aesgcm_reference_model::aes_encrypt_block(
            3'd0, key, 128'h00112233445566778899aabbccddeeff);
        if (value !== 128'h69c4e0d86a7b0430d8cdb78070b4c55a)
            $fatal(1, "REFERENCE_AES_FAIL got=%032h", value);

        key = 256'd0;
        repeat (12) iv.push_back(8'h00);
        repeat (16) payload.push_back(8'h00);
        aesgcm_reference_model::predict(3'd0, key, 1'b0, 128,
            96, 0, 128, iv, aad, payload, received_tag,
            output_bytes, tag_bytes, auth_ok);
        for (int i = 0; i < 16; i++)
            value[127 - 8*i -: 8] = output_bytes[i];
        if (value !== 128'h0388dace60b6a392f328c2b971b2fe78)
            $fatal(1, "REFERENCE_GCM_CT_FAIL got=%032h", value);
        for (int i = 0; i < 16; i++)
            value[127 - 8*i -: 8] = tag_bytes[i];
        if (value !== 128'hab6e47d42cec13bdf53a67b21257bddf)
            $fatal(1, "REFERENCE_GCM_TAG_FAIL got=%032h", value);
        $display("REFERENCE_MODEL_PASS aes_fips197=1 gcm_sp800_38d=1");
        $finish;
    end
endmodule
