`timescale 1ns/1ps

package aesgcm_reference_model_pkg;

    typedef byte unsigned byte_queue_t[$];

    class aesgcm_reference_model;
        static function automatic byte unsigned gf8_mul(
            input byte unsigned a,
            input byte unsigned b
        );
            byte unsigned aa, bb, p;
            bit high;
            aa = a;
            bb = b;
            p = 0;
            for (int i = 0; i < 8; i++) begin
                if (bb[0]) p ^= aa;
                high = aa[7];
                aa <<= 1;
                if (high) aa ^= 8'h1b;
                bb >>= 1;
            end
            return p;
        endfunction

        static function automatic byte unsigned rotl8(
            input byte unsigned x,
            input int n
        );
            return byte'((x << n) | (x >> (8-n)));
        endfunction

        // Algorithmic S-box: multiplicative inverse in GF(2^8), followed by
        // the FIPS-197 affine transform. It does not reuse the DUT lookup.
        static function automatic byte unsigned sbox(input byte unsigned a);
            byte unsigned inv, base, result;
            int exponent;
            if (a == 0) begin
                inv = 0;
            end else begin
                inv = 1;
                base = a;
                exponent = 254;
                while (exponent != 0) begin
                    if (exponent & 1) inv = gf8_mul(inv, base);
                    base = gf8_mul(base, base);
                    exponent >>= 1;
                end
            end
            result = inv ^ rotl8(inv, 1) ^ rotl8(inv, 2) ^
                     rotl8(inv, 3) ^ rotl8(inv, 4) ^ 8'h63;
            return result;
        endfunction

        static function automatic bit [31:0] rot_word(input bit [31:0] w);
            return {w[23:0], w[31:24]};
        endfunction

        static function automatic bit [31:0] sub_word(input bit [31:0] w);
            return {sbox(w[31:24]), sbox(w[23:16]),
                    sbox(w[15:8]), sbox(w[7:0])};
        endfunction

        static function automatic byte unsigned rcon(input int index);
            byte unsigned value;
            value = 8'h01;
            for (int i = 1; i < index; i++)
                value = gf8_mul(value, 8'h02);
            return value;
        endfunction

        static function automatic void expand_key(
            input bit [2:0] key_mode,
            input bit [255:0] key,
            output bit [31:0] words [0:59],
            output int nr
        );
            int nk, total;
            bit [31:0] temp;
            nk = (key_mode == 0) ? 4 : (key_mode == 1) ? 6 : 8;
            nr = nk + 6;
            total = 4 * (nr + 1);
            for (int i = 0; i < 60; i++) words[i] = 0;
            for (int i = 0; i < nk; i++)
                words[i] = key[255 - 32*i -: 32];
            for (int i = nk; i < total; i++) begin
                temp = words[i-1];
                if ((i % nk) == 0)
                    temp = sub_word(rot_word(temp)) ^ {rcon(i/nk), 24'd0};
                else if ((nk == 8) && ((i % nk) == 4))
                    temp = sub_word(temp);
                words[i] = words[i-nk] ^ temp;
            end
        endfunction

        static function automatic bit [127:0] sub_bytes(input bit [127:0] s);
            bit [127:0] result;
            for (int i = 0; i < 16; i++)
                result[127 - 8*i -: 8] = sbox(s[127 - 8*i -: 8]);
            return result;
        endfunction

        static function automatic bit [127:0] shift_rows(input bit [127:0] s);
            bit [127:0] result;
            int source_column;
            for (int row = 0; row < 4; row++) begin
                for (int column = 0; column < 4; column++) begin
                    source_column = (column + row) % 4;
                    result[127 - 8*(4*column+row) -: 8] =
                        s[127 - 8*(4*source_column+row) -: 8];
                end
            end
            return result;
        endfunction

        static function automatic bit [127:0] mix_columns(input bit [127:0] s);
            bit [127:0] result;
            byte unsigned a0, a1, a2, a3;
            for (int c = 0; c < 4; c++) begin
                a0 = s[127 - 8*(4*c+0) -: 8];
                a1 = s[127 - 8*(4*c+1) -: 8];
                a2 = s[127 - 8*(4*c+2) -: 8];
                a3 = s[127 - 8*(4*c+3) -: 8];
                result[127 - 8*(4*c+0) -: 8] =
                    gf8_mul(a0,2) ^ gf8_mul(a1,3) ^ a2 ^ a3;
                result[127 - 8*(4*c+1) -: 8] =
                    a0 ^ gf8_mul(a1,2) ^ gf8_mul(a2,3) ^ a3;
                result[127 - 8*(4*c+2) -: 8] =
                    a0 ^ a1 ^ gf8_mul(a2,2) ^ gf8_mul(a3,3);
                result[127 - 8*(4*c+3) -: 8] =
                    gf8_mul(a0,3) ^ a1 ^ a2 ^ gf8_mul(a3,2);
            end
            return result;
        endfunction

        static function automatic bit [127:0] round_key(
            input bit [31:0] words [0:59],
            input int round
        );
            return {words[4*round], words[4*round+1],
                    words[4*round+2], words[4*round+3]};
        endfunction

        static function automatic bit [127:0] aes_encrypt_block(
            input bit [2:0] key_mode,
            input bit [255:0] key,
            input bit [127:0] plaintext
        );
            bit [31:0] words [0:59];
            bit [127:0] state;
            int nr;
            expand_key(key_mode, key, words, nr);
            state = plaintext ^ round_key(words, 0);
            for (int round = 1; round < nr; round++)
                state = mix_columns(shift_rows(sub_bytes(state))) ^
                        round_key(words, round);
            return shift_rows(sub_bytes(state)) ^ round_key(words, nr);
        endfunction

        static function automatic bit [127:0] gf_shift_one(input bit [127:0] v);
            return {1'b0, v[127:1]} ^
                   (v[0] ? 128'he1000000000000000000000000000000 : 128'd0);
        endfunction

        // NIST SP 800-38D Algorithm 1, exactly 128 serial iterations.
        static function automatic bit [127:0] gf128_multiply(
            input bit [127:0] x,
            input bit [127:0] y
        );
            bit [127:0] z, v;
            z = 0;
            v = y;
            for (int i = 127; i >= 0; i--) begin
                if (x[i]) z ^= v;
                v = gf_shift_one(v);
            end
            return z;
        endfunction

        static function automatic bit [127:0] queue_block(
            input byte_queue_t bytes,
            input int unsigned first_bit,
            input int unsigned valid_bits
        );
            bit [127:0] block;
            int unsigned source_bit;
            block = 0;
            for (int unsigned i = 0; i < valid_bits; i++) begin
                source_bit = first_bit + i;
                block[127-i] = bytes[source_bit/8][7-(source_bit%8)];
            end
            return block;
        endfunction

        static function automatic bit [127:0] ghash_bits(
            input bit [127:0] h,
            input byte_queue_t bytes,
            input int unsigned bit_length,
            input bit [127:0] initial_y = 128'd0
        );
            bit [127:0] y, block;
            int unsigned offset, take;
            y = initial_y;
            offset = 0;
            while (offset < bit_length) begin
                take = ((bit_length-offset) > 128) ? 128 : bit_length-offset;
                block = queue_block(bytes, offset, take);
                y = gf128_multiply(y ^ block, h);
                offset += take;
            end
            return y;
        endfunction

        static function automatic bit [127:0] make_j0(
            input bit [127:0] h,
            input byte_queue_t iv,
            input int unsigned iv_bits
        );
            bit [127:0] y, iv_block;
            if (iv_bits == 96) begin
                iv_block = queue_block(iv, 0, 96);
                return {iv_block[127:32], 32'h00000001};
            end
            y = ghash_bits(h, iv, iv_bits);
            y = gf128_multiply(y ^ {64'd0, 64'(iv_bits)}, h);
            return y;
        endfunction

        static function automatic bit [127:0] inc32(input bit [127:0] x);
            return {x[127:32], x[31:0] + 32'd1};
        endfunction

        static function automatic bit [127:0] authentication_hash(
            input bit [127:0] h,
            input byte_queue_t aad,
            input int unsigned aad_bits,
            input byte_queue_t ciphertext,
            input int unsigned data_bits
        );
            bit [127:0] y;
            y = ghash_bits(h, aad, aad_bits);
            y = ghash_bits(h, ciphertext, data_bits, y);
            y = gf128_multiply(y ^ {64'(aad_bits), 64'(data_bits)}, h);
            return y;
        endfunction

        static task automatic crypt_payload(
            input bit [2:0] key_mode,
            input bit [255:0] key,
            input bit [127:0] j0,
            input byte_queue_t input_bytes,
            input int unsigned data_bits,
            output byte_queue_t output_bytes
        );
            bit [127:0] counter, stream;
            int unsigned byte_count, valid_bits;
            byte unsigned mask;
            output_bytes.delete();
            byte_count = (data_bits + 7) / 8;
            counter = j0;
            for (int unsigned i = 0; i < byte_count; i++) begin
                if ((i % 16) == 0) begin
                    counter = inc32(counter);
                    stream = aes_encrypt_block(key_mode, key, counter);
                end
                output_bytes.push_back(input_bytes[i] ^
                    stream[127 - 8*(i%16) -: 8]);
            end
            if ((data_bits % 8) != 0 && byte_count != 0) begin
                valid_bits = data_bits % 8;
                mask = 8'hff << (8-valid_bits);
                output_bytes[byte_count-1] &= mask;
            end
        endtask

        static task automatic predict(
            input bit [2:0] key_mode,
            input bit [255:0] key,
            input bit decrypt,
            input int unsigned tag_bits,
            input int unsigned iv_bits,
            input int unsigned aad_bits,
            input int unsigned data_bits,
            input byte_queue_t iv,
            input byte_queue_t aad,
            input byte_queue_t payload,
            input byte_queue_t received_tag,
            output byte_queue_t result_payload,
            output byte_queue_t result_tag,
            output bit authentication_ok
        );
            bit [127:0] h, j0, s, full_tag;
            byte_queue_t ciphertext;
            h = aes_encrypt_block(key_mode, key, 128'd0);
            j0 = make_j0(h, iv, iv_bits);
            crypt_payload(key_mode, key, j0, payload, data_bits,
                          result_payload);
            if (decrypt) ciphertext = payload;
            else ciphertext = result_payload;
            s = authentication_hash(h, aad, aad_bits, ciphertext, data_bits);
            full_tag = aes_encrypt_block(key_mode, key, j0) ^ s;
            result_tag.delete();
            for (int unsigned i = 0; i < ((tag_bits+7)/8); i++)
                result_tag.push_back(full_tag[127 - 8*i -: 8]);
            authentication_ok = !decrypt;
            if (decrypt) begin
                authentication_ok = (received_tag.size() == result_tag.size());
                foreach (result_tag[i])
                    if (received_tag[i] !== result_tag[i])
                        authentication_ok = 0;
            end
        endtask
    endclass
endpackage
