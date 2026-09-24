---
theme: default
title: AES-GCM 175 MHz RTL Engineering Report
info: |
  FPGA3 AES-GCM RTL architecture, security control, implementation,
  and verification evidence for a professional FPGA/IC review.
author: FPGA3 AES-GCM Project
transition: fade-out
mdc: true
lineNumbers: true
drawings:
  persist: false
---

<div class="cover-grid">
  <section>
    <p class="kicker">FPGA / RTL / DV / PHYSICAL SIGNOFF</p>
    <h1>AES-GCM<br><span>RTL Engineering Report</span></h1>
    <p class="lead">從SystemVerilog架構、握手與安全控制，一路追溯到175 MHz routed DCP與FPGA板級NIST驗證。</p>
    <div class="chip-row">
      <span class="chip">Artix-7 XC7A100T</span>
      <span class="chip">Vivado 2021.1</span>
      <span class="chip chip-accent">175 MHz</span>
    </div>
  </section>
  <aside class="cover-rail">
    <div><b>RTL baseline</b><code>4246ebc7…578c11</code></div>
    <div><b>Production top</b><code>arty_a7_100t_aes_gcm_uart_rsp_top</code></div>
    <div><b>Scope</b><span>RTL → Simulation → Implementation → Board</span></div>
    <div class="pass"><b>Current full-board status</b><span>IMPLEMENTED · ROUTED · VERIFIED</span></div>
  </aside>
</div>

<!--
本報告不逐行念RTL；主線是設計意圖、硬體機制與可重現證據。
175 MHz是目前正式範圍，200 MHz不在此deck內。
-->

---

# 主管先看什麼：RTL不是檔案清單，而是三層證據

<div class="three-col">
  <article class="panel numbered" data-n="01">
    <h3>Structure</h3>
    <p>模組邊界、資料流、clock/reset與可替換介面。</p>
    <ul>
      <li>Board wrapper與crypto core分離</li>
      <li>AXI-style ready/valid contract</li>
      <li>AES、GHASH、Key Context、FIFO分工</li>
    </ul>
  </article>
  <article class="panel numbered" data-n="02">
    <h3>Mechanism</h3>
    <p>RTL如何達成吞吐率、時序與安全不變條件。</p>
    <ul>
      <li>三個AES service instances</li>
      <li>16-bit digit-serial GHASH</li>
      <li>authenticated plaintext release</li>
    </ul>
  </article>
  <article class="panel numbered" data-n="03">
    <h3>Evidence</h3>
    <p>每個主張都連到simulation、DCP、RPT或board log。</p>
    <ul>
      <li>WNS <b>+0.029 ns</b> · TNS 0</li>
      <li>NIST <b>47,250 / 47,250</b></li>
      <li>DRC與route errors 0</li>
    </ul>
  </article>
</div>

<div class="metric-grid four compact top-gap">
  <div class="metric"><small>Encrypt core throughput</small><strong>1.065</strong><span>Gbit/s · simulation</span></div>
  <div class="metric"><small>Decrypt core throughput</small><strong>1.052</strong><span>Gbit/s · simulation</span></div>
  <div class="metric"><small>Final routed clock</small><strong>175</strong><span>MHz · 5.714 ns</span></div>
  <div class="metric"><small>Hardware NIST</small><strong>0</strong><span>failures / 47,250</span></div>
</div>

<!--
主管需要的是結構、關鍵機制、證據。吞吐率是simulation test-level核心數字，不是UART板級傳輸率。
-->

---

# Production RTL地圖：14個檔案，6個責任域

<div class="source-map">
  <div class="tree panel">
    <code>engrenring/rtl/source/</code>
    <div class="branch"><b>board/</b><span>board top · UART/RSP bridge · uart_rx/tx</span></div>
    <div class="branch"><b>stream_axi/</b><span>AXI-Lite registers · output skid</span></div>
    <div class="branch"><b>stream_core/</b><span>transaction controller · stream FIFO</span></div>
    <div class="branch"><b>stream_aes/</b><span>AES engines · key context</span></div>
    <div class="branch"><b>stream_ghash/</b><span>production ghash16</span></div>
    <div class="branch"><b>aes_core/</b><span>S-box primitive</span></div>
  </div>
  <div class="panel callout-stack">
    <h3>主報告只追三條線</h3>
    <div class="callout"><b>Protocol boundary</b><span>UART/RSP → AXI-Lite / AXI-Stream</span></div>
    <div class="callout"><b>Crypto datapath</b><span>AES-CTR ↔ GHASH ↔ tag compare</span></div>
    <div class="callout"><b>Security lifecycle</b><span>accept → authenticate → release / abort / zeroize</span></div>
    <p class="note">`tb_ghash16.sv`是testbench，不列入production RTL。</p>
  </div>
</div>

<div class="evidence-line"><span>RTL最後修改commit</span><code>4246ebc7a72ce8eb1a49d56969aae6e151578c11</code></div>

<!--
14個production Verilog檔不逐一介紹，而是依責任域分組。之後每一頁只引用可解釋一個設計決策的片段。
-->

---

# 分層架構：板級協定不污染crypto core

<div class="architecture-stack">
  <div class="arch-lane">
    <b>BOARD / PROTOCOL BOUNDARY</b>
    <div class="arch-row four">
      <span class="host">PC / NIST RSP host</span><i>UART</i>
      <span class="edge">Arty A7 board top</span><i>→</i>
      <span class="edge">UART / RSP bridge</span><i>→</i>
      <span class="edge">aes_gcm_axi_top</span>
    </div>
  </div>
  <div class="arch-down">↓ AXI-Lite control · AXI-Stream data</div>
  <div class="arch-lane">
    <b>CRYPTO TRANSACTION LAYER</b>
    <div class="arch-row three">
      <span>AXI-Lite registers</span><i>↔</i>
      <span>boundary queues / skid</span><i>↔</i>
      <span class="core">aes_gcm_stream_core</span>
    </div>
  </div>
  <div class="arch-down">↓ internal ready / valid services</div>
  <div class="arch-lane">
    <b>CRYPTO SERVICES</b>
    <div class="arch-row five">
      <span>Key Context</span><span>3 × AES engines</span><span>GHASH16</span><span>request / result FIFOs</span><span>data · tag · status</span>
    </div>
  </div>
</div>

<div class="strip three">
  <div><b>板級替換</b><span>UART wrapper可換成DMA／PCIe，crypto core介面不變</span></div>
  <div><b>控制面</b><span>AXI-Lite設定key、IV、mode與descriptor</span></div>
  <div><b>資料面</b><span>AXI-Stream用ready/valid維持backpressure</span></div>
</div>

<!--
專業價值在於邊界清楚：板級驗證速度不等於核心吞吐率，也不把UART狀態機塞進密碼運算核心。
-->

---

# Interface contract：registered READY切斷wide feedback cone

<div class="split code-split">
  <div>

```verilog {1-3|5-10|12-21|all}
// aes_gcm_axi_top.v:156-201
assign s_axis_tready = s_axis_tready_r && !zeroize_pulse;
wire public_input_fire = s_axis_tvalid && s_axis_tready;

wire [2:0] inputq_count_next = {1'b0, inputq_count} +
                               (public_input_fire ? 3'd1 : 3'd0) -
                               (inputq_pop ? 3'd1 : 3'd0);

always @(posedge aclk) begin
  if(!aresetn || zeroize_pulse) begin
    input_frame_credits <= 2'd0;
    s_axis_tready_r     <= 1'b0;
  end else begin
    input_frame_credits <= input_frame_credits_next;
    if(core_zeroize_busy)
      s_axis_tready_r <= 1'b0;
    else
      s_axis_tready_r <= (input_frame_credits_next != 0) &&
                         (inputq_count_next < 2);
  end
end
```

  </div>
  <div class="mechanism-list">
    <article><span>01</span><div><b>Same-edge admission</b><p>`valid && ready`是唯一accept事件。</p></div></article>
    <article><span>02</span><div><b>Predictive occupancy</b><p>用next count決定下一cycle READY，避免overflow。</p></div></article>
    <article><span>03</span><div><b>Timing locality</b><p>READY註冊化，不把core-wide狀態組合回public port。</p></div></article>
    <article class="danger"><span>04</span><div><b>ZEROIZE priority</b><p>command pulse同cycle直接gate READY。</p></div></article>
  </div>
</div>

<div class="code-caption">來源：<code>engrenring/rtl/source/aes_gcm_axi_top.v</code> · production RTL</div>

<!--
這段不是一般FIFO教學，而是最關鍵的介面時序決策：registered-ready與credit tracking同時守住吞吐率與無overflow。
-->

---

# AES service：一組共享round-key context，三個engine instances

<div class="split diagram-code">
  <div>
    <div class="microarch">
      <div class="node wide">Key Context<br><small>round keys · key size</small></div>
      <div class="fanout"></div>
      <div class="engine-row">
        <div class="node">AES block engine<br><small>shared service</small></div>
        <div class="node accent">First engine A<br><small>first-block fast lane</small></div>
        <div class="node accent">First engine B<br><small>overlapped service</small></div>
      </div>
      <div class="node wide fifo">Request / metadata / result FIFOs</div>
    </div>
    <div class="metric-grid three compact">
      <div class="metric"><small>AES-128 II</small><strong>10</strong><span>cycles</span></div>
      <div class="metric"><small>AES-192 II</small><strong>12</strong><span>cycles</span></div>
      <div class="metric"><small>AES-256 II</small><strong>14</strong><span>cycles</span></div>
    </div>
  </div>
  <div>

```verilog {1-6|8-13|15-20|all}
// aes_gcm_stream_core.v:314-335
aes_block_engine u_aes_engine (
  .clk(clk), .rst_n(rst_n && !zeroize),
  .key_size(expanded_key_size),
  .round_keys(round_keys),
  .block_in(aes_engine_in),
  .block_out(aes_engine_out)
);

aes_first_block_engine u_aes_first_engine (
  .clk(clk), .rst_n(rst_n && !zeroize),
  .round_keys(round_keys),
  .block_in(aes_prod_data[267:140]),
  .block_out(aes_first_out)
);

aes_first_block_engine u_aes_second_engine (
  .clk(clk), .rst_n(rst_n && !zeroize),
  .round_keys(round_keys),
  .block_in(aes_prod_data[267:140]),
  .block_out(aes_second_out)
);
```

  </div>
</div>

<div class="conclusion">設計重點：複製的是服務能力，不是key schedule；round keys由單一context供應。</div>

<!--
三個engine instance不是三倍峰值的簡單宣稱；它們用來重疊不同first-block與一般block服務，真實效能以量測II與吞吐率報告。
-->

---

# GHASH16：16-bit digit-serial，組合邏輯刻意做成balanced XOR

<div class="ghash-flow">
  <div class="node">X = Y ⊕ block</div>
  <div class="arrow">→</div>
  <div class="node accent">16 field terms<br><small>T⁰(V)…T¹⁵(V)</small></div>
  <div class="arrow">→</div>
  <div class="xor">⊕</div>
  <div class="arrow">→</div>
  <div class="node">Z ← Z ⊕ product<br><small>V ← T¹⁶(V)</small></div>
</div>

<div class="split code-split ghash-code">
  <div>

```verilog {1-4|6-9|11-12|all}
// ghash16.v:152-169
wire [127:0] xor_level1_0 = selected_0 ^ selected_1;
wire [127:0] xor_level1_1 = selected_2 ^ selected_3;
// ... 8 parallel pairs

wire [127:0] xor_level2_0 = xor_level1_0 ^ xor_level1_1;
wire [127:0] xor_level2_1 = xor_level1_2 ^ xor_level1_3;
// ... 4 groups

wire [127:0] xor_level3_0 = xor_level2_0 ^ xor_level2_1;
wire [127:0] xor_level3_1 = xor_level2_2 ^ xor_level2_3;

wire [127:0] digit_product_w = xor_level3_0 ^ xor_level3_1;
```

  </div>
  <div class="metric-grid two vertical">
    <div class="metric"><small>Digit width</small><strong>16</strong><span>bits / iteration</span></div>
    <div class="metric"><small>Multiply latency</small><strong>8</strong><span>digit clocks</span></div>
    <div class="metric"><small>External II</small><strong>9</strong><span>load + 8 iterations</span></div>
    <div class="metric"><small>SVA smoke</small><strong>66</strong><span>GHASH tests · 0 failures</span></div>
  </div>
</div>

<!--
Balanced reduction把16項縮成8、4、2、1，不形成16級串接XOR。T^POWER也是從原始V直接展開，不是runtime shift chain。
-->

---

# Decrypt fail-closed：先驗證tag，再授權plaintext release

<div class="split code-split">
  <div>

```verilog {1-9|11-18|all}
// aes_gcm_stream_core.v:2536-2576
if(descriptor_crypto_active_w && final_tag_ready &&
   all_cipher_blocks_ready && !result_valid_r) begin
  if(rec_decrypt && tag_compare_ready_r &&
     !plain_write_pending_valid_r) begin
    result_data_r <= tag_mismatch_w ?
                     RESULT_DEC_AUTH_FAIL :
                     RESULT_DEC_AUTH_OK;
    result_valid_r <= 1'b1;
    state <= ST_DEC_RESULT;
  end
end

if((state == ST_DEC_RESULT) && result_valid_r &&
   m_axis_result_tready) begin
  result_valid_r <= 1'b0;
  if(result_data_r == RESULT_DEC_AUTH_OK) begin
    plain_release_valid <= 1'b1;
    plain_release_data  <= {rec_bank, rec_data_bits};
  end
end
```

  </div>
  <div class="security-flow">
    <div class="node">Ciphertext → private plaintext banks</div>
    <div class="down">↓</div>
    <div class="node">完整tag operands + fixed XOR/OR compare</div>
    <div class="fork">
      <div class="pass">AUTH_OK<br><small>release token</small></div>
      <div class="fail">AUTH_FAIL<br><small>no plaintext release</small></div>
    </div>
    <p class="note">Board reconciliation：unauthorized plaintext = <b>0</b></p>
  </div>
</div>

<div class="conclusion lime">安全不變條件：plaintext的存在不等於對外可見；只有AUTH_OK result被接受後才產生release permission。</div>

<!--
這是最值得給安全主管看的RTL片段。它把compare完成、result握手與plaintext release三個事件明確分離。
-->

---

# ZEROIZE與FIFO：同edge阻擋新交易，再同步清除有效狀態

<div class="three-col zeroize-cols">
  <article class="panel">
    <p class="kicker">BOUNDARY GATE</p>
    <pre class="inline-code"><code>assign s_axis_tready =
  s_axis_tready_r &amp;&amp;
  !zeroize_pulse;</code></pre>
    <div class="mini-note">raw command pulse同cycle阻止新的public accept。</div>
  </article>
  <article class="panel">
    <p class="kicker">QUEUE INVALIDATION</p>
    <pre class="inline-code"><code>stream_fifo u_input_queue (
  .clear(zeroize_pulse),
  // ready / valid queue
);</code></pre>
    <div class="mini-note">count、pointer與registered head同步歸零，stale head不能fire。</div>
  </article>
  <article class="panel">
    <p class="kicker">SCRUB LIFECYCLE</p>
    <pre class="inline-code"><code>if(first_zeroize_event_w) begin
  zeroize_busy_r &lt;= 1'b1;
  zeroize_index  &lt;= 5'd0;
end</code></pre>
    <div class="mini-note">重複ZEROIZE保持idempotent，scrub完成前不重新開放context。</div>
  </article>
</div>

<div class="timeline">
  <div><b>T0</b><span>raw ZEROIZE</span></div>
  <div><b>same edge</b><span>READY/VALID gated</span></div>
  <div><b>T1</b><span>FIFO/control invalidated</span></div>
  <div><b>scrub</b><span>16 addresses</span></div>
  <div><b>done</b><span>abort result / clean recovery</span></div>
</div>

<div class="code-caption">Production sources：<code>aes_gcm_axi_top.v</code> · <code>aes_gcm_stream_core.v</code> · <code>stream_fifo.v</code></div>

<!--
ZEROIZE不是單一reset線，而是一個可觀察、可阻擋新交易、可清queue並完成memory scrub的lifecycle。
-->

---

# Timing-aware RTL：局部ready與registered head降低control cone

<div class="split code-split">
  <div>

```verilog {1-4|6-9|all}
// stream_fifo.v:27-37
wire push = in_valid && in_ready;
wire pop  = out_valid && out_ready;

// Full只看count MSB，localize RAM write enable
assign in_ready  = !count_r[ADDR_W];
assign out_valid = (count_r != 0);

// Head註冊化，pointer select不直達consumer mux
assign out_data = out_data_q;
```

  </div>
  <div class="delta-card">
    <div class="phase bad"><small>Post-synthesis estimate</small><strong>−0.298 ns</strong><span>292 setup endpoints</span></div>
    <div class="delta">+0.327 ns</div>
    <div class="phase good"><small>Final post-route</small><strong>+0.029 ns</strong><span>TNS 0 · FEP 0</span></div>
    <div class="breakdown"><b>Final worst path</b><span>5.544 ns data path</span><span>1.214 ns logic</span><span class="accent-text">4.330 ns net · 78.1%</span></div>
  </div>
</div>

<div class="conclusion">來源：<code>stream_core/stream_fifo.v</code>。Synthesis成功但初估setup未closure；placement、physical optimization與routing後，175 MHz final timing通過。</div>

<!--
不是routing單獨修好，而是implementation整體收斂。Final path以net delay為主，說明control locality與physical optimization是必要手段。
-->

---

# Code → hardware：最終routed DCP是release基準

<div class="implementation-grid">
  <div class="panel image-panel">
    <img src="/evidence/implementation_device_placement.png" alt="Vivado final routed device placement" />
    <p>Vivado Device View · final routed DCP</p>
  </div>
  <div>
    <div class="metric-grid two compact">
      <div class="metric"><small>Setup</small><strong>+0.029</strong><span>WNS ns · TNS 0</span></div>
      <div class="metric"><small>Hold</small><strong>+0.044</strong><span>WHS ns · THS 0</span></div>
      <div class="metric"><small>Routing</small><strong>17,758</strong><span>/ 17,758 · errors 0</span></div>
      <div class="metric"><small>DRC</small><strong>0</strong><span>violations</span></div>
    </div>
    <div class="resource-bar">
      <div><b>12,411</b><span>LUT · 19.58%</span></div>
      <div><b>9,029</b><span>FF · 7.12%</span></div>
      <div><b>10</b><span>RAMB18</span></div>
      <div><b>0</b><span>DSP</span></div>
    </div>
    <div class="evidence-card">
      <span>Routed DCP SHA-256</span>
      <code>A91758ED…9C016B</code>
      <small>Power 0.461 W是Vivado vectorless estimate（Medium），不是實板量測。</small>
    </div>
  </div>
</div>

<!--
這頁只報正式post-route數字。DCP hash讓placement、timing、DRC與後續bitstream evidence綁到同一設計身分。
-->

---

# Verification pyramid：不同方法覆蓋不同失效模式

<div class="verification-pyramid">
  <div class="tier board"><b>FPGA BOARD</b><span>47,250 / 47,250 NIST · 6 / 6 smoke</span></div>
  <div class="tier nist"><b>XSim NIST RSP</b><span>47,250 / 47,250 · 17,740,527 cycles</span></div>
  <div class="tier uvm"><b>UVM 1.2</b><span>3 seeds · 24 checked · 0 failed · maintained bins 100%</span></div>
  <div class="tier sva"><b>SVA</b><span>37 properties · AXI/GHASH smoke · 0 assertion failures</span></div>
  <div class="tier static"><b>STATIC / FORMAL SUBSET</b><span>DRC · methodology · CDC gates · 19 combinational assertions</span></div>
</div>

<div class="limits-grid">
  <div class="pass-box"><b>What is closed</b><span>Full-board timing、routing、DRC、hardware NIST與security reconciliation。</span></div>
  <div class="limit-box"><b>What is not claimed</b><span>Whole-design sequential formal、code/assertion coverage、measured board power、OOC PartPin。</span></div>
</div>

<!--
UVM 100%是maintained functional scenario bins，不是code或assertion coverage。Formal是19個assumption-free combinational assertions的partial pass。
-->

---

# Release narrative：程式碼主張與證據一一對應

<div class="trace-table">
  <div class="head"><span>RTL claim</span><span>Mechanism</span><span>Evidence</span><span>Status</span></div>
  <div><span>無overflow的stream accept</span><span>registered READY + credits</span><span>UVM / SVA / directed</span><b class="ok">PASS</b></div>
  <div><span>高吞吐AES-GCM</span><span>3 AES services + FIFO decoupling</span><span>1.052–1.065 Gbit/s simulation</span><b class="ok">PASS</b></div>
  <div><span>Decrypt fail-closed</span><span>AUTH_OK-gated plaintext release</span><span>11,908 expected auth fails · leakage 0</span><b class="ok">PASS</b></div>
  <div><span>ZEROIZE無stale output</span><span>same-edge gate + clear + scrub</span><span>SVA / directed / board reconciliation</span><b class="ok">PASS</b></div>
  <div><span>175 MHz implementation</span><span>timing-aware RTL + physical optimization</span><span>WNS +0.029 · TNS 0</span><b class="ok">PASS</b></div>
  <div><span>Standalone OOC reuse</span><span>approved PartPin map</span><span>identity-matched map unavailable</span><b class="open">OPEN</b></div>
</div>

<div class="final-statement">
  <b>主管結論</b>
  <span>RTL架構、security control、implementation與板級功能形成可追溯閉環；目前release限制被明確隔離，沒有用一種測試替代另一種signoff。</span>
</div>

<!--
最終結論不是「全部都完美」，而是full-board candidate已閉合，且未完成的formal/PartPin/power量測沒有被隱藏。
-->

---
layout: center
class: appendix-cover
---

# Appendix

<p class="lead center">原始RTL、Vivado native evidence與verification summaries</p>

---

# Appendix A · Source與evidence索引

<div class="appendix-grid">
  <div class="panel">
    <h3>Production RTL</h3>
    <code>engrenring/rtl/source/</code>
    <ul>
      <li><code>board/arty_a7_100t_aes_gcm_uart_rsp_top.v</code></li>
      <li><code>aes_gcm_axi_top.v</code></li>
      <li><code>stream_core/aes_gcm_stream_core.v</code></li>
      <li><code>stream_aes/*.v</code></li>
      <li><code>stream_ghash/ghash16.v</code></li>
    </ul>
  </div>
  <div class="panel">
    <h3>Verification</h3>
    <code>verification/</code>
    <ul>
      <li><code>sva/</code> · 37 properties</li>
      <li><code>uvm/</code> · UVM 1.2</li>
      <li><code>results/nist/</code></li>
      <li><code>results/board/</code></li>
      <li><code>results/exact_current_manifest.json</code></li>
    </ul>
  </div>
  <div class="panel">
    <h3>Vivado native evidence</h3>
    <code>docs/report/figures/vivado_native/</code>
    <ul>
      <li><code>04_routed_timing_summary.rpt</code></li>
      <li><code>09_utilization_hierarchical.rpt</code></li>
      <li><code>14_drc.rpt</code></li>
      <li><code>16_route_status.rpt</code></li>
      <li><code>vivado_native_manifest.txt</code></li>
    </ul>
  </div>
</div>

<div class="evidence-line"><span>Current repository HEAD</span><code>a0e8531e4e886d103b2a51d6b9fae682d50bf451</code></div>
