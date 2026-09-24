# 《AESGCM_175MHz_rpt》口語報告指南

來源：`C:\project\FPGA3\output\pdf\AESGCM_175MHz_rpt.pdf`（79 個 PDF 頁面）  
建議用途：數位 IC／FPGA／Design Verification 面試或專題答辯  
建議主講時間：約 15 分鐘；其餘頁面作為追問證據

## 先理解：這份 PDF 不是投影片

這是 signoff 工程報告，不應從第 1 頁一路念到第 79 頁。報告的故事只有五句：

1. 我完成一個支援 AES-128／192／256、Encrypt／Decrypt 的 AES-GCM RTL IP。
2. Core 外面有正式的 `aes_gcm_axi_top` Production AXI Wrapper；UART 只是 Arty A7 實板驗證通道。
3. 我用平行化與 buffering，在 175 MHz、8-bit stream 下達到大於 1 Gbit/s 的 RTL payload throughput。
4. 我用 UVM、SVA、NIST、Vivado static signoff 與 exact-bitstream 實板測試建立分層證據。
5. Final route timing、DRC 與實板 NIST 均通過，但 formal、power 與 PartPin 仍有清楚限制。

報告時不是證明「每一頁都有看過」，而是讓主管聽懂：

> 我做了什麼 → 為什麼這樣設計 → 遇到什麼問題 → 如何驗證 → 結果與限制是什麼。

---

# 15 分鐘主講路線

## 第 1 段｜開場與成果總覽

**使用 PDF 頁：1、9–11｜建議時間：1 分 30 秒**

### 可直接照念

> 各位主管好，這個專案是一個在 Arty A7-100T 上完成實作與驗證的 AES-GCM IP。它支援 AES-128、AES-192、AES-256，以及 Encrypt 和 Decrypt。設計分成三個層級：最內層是負責 AES-CTR、GHASH 與 authentication 的 Core；中間是正式系統整合使用的 `aes_gcm_axi_top` Production AXI Wrapper；最外層才是 Arty A7 的 UART Board Validation Top，用來把 NIST 測試向量送進 FPGA。
>
> Final target 是 175 MHz，週期 5.714 ns。Post-route setup WNS 是正 0.029 ns，hold WHS 是正 0.044 ns，TNS、THS 與 failing endpoints 都是 0。RTL payload throughput 為 Encrypt 1.065 Gbit/s、Decrypt 1.052 Gbit/s；實板六模式 smoke 全部通過，NIST RSP 是 47,250 筆全部通過。
>
> 這份報告的重點不是只說功能模擬 PASS，而是把 RTL、verification、physical implementation 與實板結果分層，建立可以追溯的證據鏈。

### 轉場

> 接下來先看核心架構，說明為什麼在只有 175 MHz、8-bit stream 的條件下，仍能超過 1 Gbit/s。

---

## 第 2 段｜核心架構與平行化

**使用 PDF 頁：19–20｜建議時間：2 分鐘**

### 可直接照念

> 核心的主要資料流是：輸入 descriptor 與 byte stream 進入 queue，再由 AES engines 產生 CTR keystream，payload 與 keystream XOR，同時由 GHASH 計算 authentication tag。Decrypt 的 plaintext 不會立刻公開，而是先保存在 protected banks，只有 tag compare 成功後才釋放，避免 unauthenticated plaintext leakage。
>
> AES 主引擎不是複製三條完整 datapath，而是使用三個 context 交錯共用一條 registered round datapath。單一 block 的 nominal latency 仍可能是 30、36、42 clocks，但 steady-state initiation interval 降到 10、12、14 clocks。
>
> 原始瓶頸出現在每筆 record 前兩個 CTR blocks：第一個 keystream 回來太慢，造成 byte stream 在 block boundary 等待。我的改善方式是加入兩個專門處理 block index 0 和 1 的 first-block engines，以及兩筆 sensitive data queue。這不是提高 clock frequency，而是讓 byte admission、AES 計算與 GHASH 更有效地重疊，減少 startup bubble。

### 一句話重點

> 我的平行化不是把整個 AES-GCM 複製多份，而是針對 first-block latency 做局部平行化，再用三 context shared engine 處理 steady state。

### 轉場

> 架構改善完成後，我用 accepted payload 與實際 cycle count 計算吞吐率，而不是只用理論頻寬推估。

---

## 第 3 段｜175 MHz、Cycle 與吞吐率

**使用 PDF 頁：22–24、45｜建議時間：1 分 30 秒**

### 可直接照念

> 板上 100 MHz clock 經 MMCM 乘 7 除 4，產生 175 MHz core clock，週期是 5.714 ns。吞吐率使用 accepted payload bits 乘上 clock frequency，再除以實際執行 cycles。
>
> 測試條件是每個模式 100 筆 record、每筆 1024-bit payload。Encrypt 使用 16,820 cycles，得到 1.065398 Gbit/s；Decrypt 使用 17,039 cycles，得到 1.051705 Gbit/s。AES-128、192、256 都通過大於 1 Gbit/s。
>
> 8-bit stream 在 175 MHz 的理論 raw ceiling 是 1.4 Gbit/s。實際結果較低，是因為還包含 GCM、FIFO 與 record overhead。這組數字屬於 RTL／AXI testbench 的 crypto payload throughput，不是 UART 的傳輸速度，也不是直接在板上量到的 1 Gbit/s。

### 若主管追問為什麼三種 key size 結果相同

> 前兩個 blocks 由 dedicated engines 隱藏 startup latency，後續 AES-256 最差 14-clock block interval 仍快於 8-bit stream 傳完一個 128-bit block所需的 16 clocks，所以系統瓶頸轉到 byte stream，而不是 key size。

### 轉場

> 接下來看這個架構是否真的能在 FPGA 資源內實現，以及 175 MHz 是否完成實體 timing closure。

---

## 第 4 段｜資源、Timing Closure 與 DRC

**使用 PDF 頁：26–27、34–36｜建議時間：2 分鐘**

### 可直接照念

> Final full-board 使用 12,411 LUT、9,029 FF、10 個 RAMB18，DSP 使用量是 0。LUT 使用率約 19.58%，FF 約 7.12%，資源仍在 XC7A100T 的合理範圍內。
>
> Timing 並不是 synthesis 完成就算通過。v8 synthesis 的 WNS 仍是負 0.298 ns；placement 加 physical optimization 後 setup 轉正，但 hold 還有 9 個 failing endpoints。經過 routing 與 post-route hold repair，final strict audit 的 setup WNS 為正 0.029 ns、hold WHS 為正 0.044 ns，TNS、THS 與 setup／hold failing endpoints 全部為 0。
>
> Route 方面，17,758 個 routable nets 全部完成，routing error 為 0；DRC Error、DRC Critical Warning、methodology Error／Critical Warning 都是 0，pulse width 也通過。因此我把 final routed DCP 的 STA 與 DRC 當成 175 MHz signoff，而不是拿 synthesis timing 當最後結論。

### 必須主動說明

> Setup margin 只有 29 ps，雖然為正但很窄，所以結論只對目前 exact RTL、XDC、Vivado 2021.1 build 與 implementation directives 有效；任何一項改變都必須重跑 signoff。

### 轉場

> Core 能算、timing 也收斂之後，還需要一層 Wrapper 把它安全地接進真正的 AXI 系統。

---

## 第 5 段｜Production AXI Wrapper

**使用 PDF 頁：46–51｜建議時間：2 分鐘**

### 可直接照念

> 這裡的 `aes_gcm_axi_top` 是 Production AXI Wrapper，不是外層 Arty A7 UART Board Top。Core 專心做 AES-CTR、GHASH 與 record lifecycle；Wrapper 則負責 command admission、byte-stream buffering、public-frame ownership 與 ZEROIZE security boundary。
>
> 第一個責任是 command admission。AXI4-Lite 的 AW 和 W 可以分開握手，兩者收齊且 response channel 可用時，才把 CONTROL write 轉成一拍的 CMD_PUSH、KEY_COMMIT 或 ZEROIZE。CMD_PUSH 檢查 key ready、descriptor FIFO 空間、IV 與 tag length；KEY_COMMIT 檢查 key mode、key engine 與公開邊界狀態。兩者不能混成同一份 checklist。Standalone legal ZEROIZE 則不等待 output drain，而是 emergency flush。
>
> 第二個責任是 buffering。S_AXIS 先進 2-entry、9-bit input queue；input-frame credit 代表 CMD_PUSH 已被接受、但 public TLAST 尚未 handshake 的 frame。沒有 credit 時 READY 不會開啟。Data 使用 one-entry elastic skid，Tag 使用 two-entry FIFO，Result 沒有 FIFO，只使用 ordering gate。不能說三條 output 都有完整 registered READY；Data skid occupied 時，downstream TREADY 仍可能組合影響 Core，Tag 才是依 registered FIFO count 隔離 READY。
>
> 第三個責任是 mode-dependent ordering 與 ZEROIZE。Encrypt 是 Ciphertext Data、Generated Tag、ENC_OK；Decrypt success 是 DEC_AUTH_OK 先被接受，才釋放 authenticated plaintext；Decrypt failure 只回 AUTH_FAIL。ZEROIZE 會立即 mask public READY／VALID，並同步清 queue、credits、frame trackers、key staging及觸發 Core scrub。它與單一 record 的 TLAST protocol abort 不同，不能混為一談。

### 一句話收尾

> Wrapper 不做 AES-GCM 演算法；它把 Core 封裝成可整合、可 timing、可驗證的同步 protocol／security boundary。

### 轉場

> 有了這個邊界後，下一個問題就是：如何證明演算法、transaction、逐拍協定與實體硬體都正確。

---

## 第 6 段｜UVM、SVA、NIST 與 Vivado 各自證明什麼

**使用 PDF 頁：54–60、63–65｜建議時間：2 分鐘**

### 可直接照念

> 我的驗證不是只靠一個 PASS。UVM、SVA、NIST、Vivado 與實板各自負責不同層級。
>
> UVM 負責 transaction-level end-to-end verification。Driver 透過 AXI-Lite 與 AXI-Stream 送 stimulus；passive reconstruction monitor 只依實際 ready／valid handshake 重建 record，不直接重用 sequence item；independent reference model 產生 expected data、tag 與 authentication 結果，再由 scoreboard 比對。三個 seeds、每個 8 個 scenarios，共 24 checked、0 failed，UVM error／fatal 為 0／0。
>
> SVA 則逐 clock 檢查 GHASH recurrence、key lifecycle、queue、tag serializer、AXI stall stability 與 ZEROIZE。共有 37 個 source-level properties，elaboration 後為 39 個 active instances；retained traces 中 assertion failure 是 0。但沒有 assertion activation、vacuity 或 assertion coverage，所以不能說成 100% assertion coverage。
>
> NIST RSP 檢查標準向量的 plaintext、ciphertext、tag 與 expected authentication failure；Vivado static signoff 檢查 simulation 看不到的 routing delay、setup、hold、pulse width、DRC 與 CDC。這些 checker 互補，但不能互相取代。

### 轉場

> 最後再把同一個設計燒到 Arty A7，用 exact bitstream 重播完整 NIST vectors。

---

## 第 7 段｜實板 NIST 結果

**使用 PDF 頁：67–68｜建議時間：1 分鐘**

### 可直接照念

> 實板先完成 AES-128、192、256 的 Encrypt／Decrypt 六模式 smoke，結果是 6/6 PASS。Full hardware NIST 使用 COM4、115200 baud，共執行 47,250 筆，結果 47,250/47,250 PASS，fail 0，first failure 為 null。
>
> 其中 Encrypt 23,625 筆、Decrypt 23,625 筆；Decrypt 包含 11,908 筆預期的 authentication failures。這些 case 必須回 AUTH_FAIL，而且不能釋放 plaintext。最終 status、data、tag mismatch 全部為 0，47,250 行 JSONL 的 indices、來源數量與分類也經第二次獨立 reconciliation 通過。
>
> 平均 39.098 cases/s 是 host 加 UART validation harness 的速度，不是 AES-GCM Core throughput。

### 轉場

> 除了展示 PASS，我也整理了失敗過的版本、真正根因與最後如何關閉問題。

---

## 第 8 段｜最值得講的問題與解法

**使用 PDF 頁：69–70｜建議時間：1 分 30 秒**

### 可直接照念

> 我挑三個最能代表工程能力的問題。
>
> 第一，原架構在 175 MHz 下 throughput 不到 1 Gbit/s。根因不是 clock 太低，而是 first-block keystream startup bubble；加入兩個 first-block engines、16-entry keystream FIFO 與兩筆 sensitive queue 後，Encrypt／Decrypt 提升到 1.065／1.052 Gbit/s。
>
> 第二，早期 Board v3 的 synthesis WNS 是負 1.192 ns，TNS 是負 1506 ns。根因是 UART 使用 1024-bit wide FF arrays，形成 wide mux 與 high fanout。改成 8-bit byte memories 後，LUT 減少 10,048、FF 減少 6,434，final route WNS 收斂到正 0.029 ns。
>
> 第三，Decrypt 存在 authentication failure 時 plaintext leakage 的風險。我的設計讓 plaintext 先留在 protected banks，只有驗證成功才釋放；UVM bad-tag、ZEROIZE／FIFO directed tests 與 11,908 個 NIST expected-fail cases 都確認 unauthorized data 為 0。

### 轉場

> 最後用成果與限制收尾，避免把已完成的部分說得太少，也避免過度宣稱。

---

## 第 9 段｜結論與誠實邊界

**使用 PDF 頁：76｜建議時間：1 分鐘**

### 可直接照念

> 總結來說，我完成了可燒錄到 Arty A7-100T 的 AES-GCM RTL IP。設計在 175 MHz 下完成 routed setup、hold、pulse width、route、DRC、CDC 與 check_timing hard gates；RTL payload throughput 為 Encrypt 1.065 Gbit/s、Decrypt 1.052 Gbit/s；實板六模式 smoke 與 47,250 筆 NIST RSP 全部通過。
>
> 驗證結論必須分層：static implementation、dynamic simulation／UVM／NIST 與實板驗證都是 PASS；整體仍寫成 PARTIAL PASS，是因為 formal 目前只完成 19 個 combinational assertions，不代表 full formal closure，也不是 simulation 或 hardware failure。
>
> 後續最重要的是加入代表性 SAIF 或實板 rail 量測提高 power 可信度、擴充 sequential formal、加入 on-chip cycle counter 驗證板上 datapath throughput，以及在需要 Block Design 交付時完成 IP-XACT packaging。

### 最後一句

> 這個專案展現的不只是 AES-GCM 演算法，而是我如何把規格轉成 RTL，經過 verification、timing closure 與實板驗證，最後留下可重現、可稽核的工程證據。

---

# 5 分鐘救急版本

如果現場只給 5 分鐘，只開 PDF 頁 1、19、35、46、56、67、76。

> 這個專案是支援 AES-128／192／256 Encrypt 和 Decrypt 的 AES-GCM RTL IP，分成 AES-GCM Core、正式的 Production AXI Wrapper，以及只供 Arty A7 實板驗證的 UART Board Top。
>
> 核心以三 context shared AES pipeline 搭配兩個 first-block engines、16-entry keystream FIFO 與兩筆 sensitive data queue，解決每筆 record 的 startup bubble。在 175 MHz、8-bit AXI stream 下，100 筆 1024-bit records 的 Encrypt throughput 為 1.065 Gbit/s，Decrypt 為 1.052 Gbit/s。
>
> Production Wrapper 不做密碼運算，而是處理 CMD_PUSH／KEY_COMMIT 的不同 admission、input-frame credits、Data skid／Tag FIFO／Result gate、mode-dependent public ordering，以及 ZEROIZE immediate emergency flush。
>
> Final routed timing 的 WNS 是正 0.029 ns、WHS 是正 0.044 ns，TNS、THS、failing endpoints 與 DRC violations 都是 0。UVM 三個 seeds 共 24 checked、0 failed；SVA 37 個 source properties、39 個 active instances，在 retained traces 中 failure 0；實板六模式 smoke 6/6 PASS，NIST 47,250/47,250 PASS。
>
> 我同時保留限制：1 Gbit/s 是 RTL／AXI payload throughput，不是 UART 板測速度；0.461 W 是 Medium-confidence vectorless estimate；formal 只有 19 個 combinational proofs，所以 overall 是 PARTIAL PASS，不宣稱 full formal closure。

---

# 必背數字

| 項目 | 正確說法 |
|---|---|
| Clock | 175 MHz；5.714 ns |
| RTL payload throughput | Encrypt 1.065398 Gbit/s；Decrypt 1.051705 Gbit/s |
| Throughput 測試 | 每模式 100 筆 × 1024-bit；16,820／17,039 cycles |
| Final timing | WNS +0.029 ns；TNS 0；WHS +0.044 ns；THS 0；FEP 0 |
| Route／DRC | 17,758/17,758 routable nets；routing error 0；DRC E/CW 0/0 |
| Resources | 12,411 LUT；9,029 FF；10 RAMB18；DSP 0 |
| Power | 0.461 W vectorless estimate；Medium confidence；不是 rail measurement |
| UVM | 3 seeds × 8 scenarios；24 checked、0 failed；E/F 0/0 |
| SVA | 37 source properties；39 active instances；retained traces failure 0 |
| Formal | 19/0 combinational subset；PARTIAL PASS；不是 full closure |
| FPGA smoke | AES-128／192／256 Encrypt／Decrypt；6/6 PASS |
| Hardware NIST | 47,250/47,250 PASS；fail 0；expected AUTH_FAIL 11,908 |
| UART harness | COM4、115200 baud；39.098 cases/s；不是 Core throughput |

---

# 最容易講錯的地方

| 不要這樣說 | 應該這樣說 |
|---|---|
| 「板上量到 1 Gbit/s」 | 「RTL／AXI testbench payload throughput 超過 1 Gbit/s；UART 實板驗證是另一個觀測邊界。」 |
| 「三條 output 都是 registered READY」 | 「Data 是 one-entry skid、Tag 是 registered-count FIFO、Result 只有 ordering gate；三者 timing 特性不同。」 |
| 「所有模式都是 Data→Tag→Result」 | 「Encrypt 是 Data→Tag→Result；Decrypt success 是 Result→authenticated plaintext；auth fail 只有 Result。」 |
| 「ZEROIZE 會等資料送完再清」 | 「ZEROIZE 是 immediate emergency flush，允許截斷尚未 handshake 的 partial frame。」 |
| 「TLAST abort 就是 ZEROIZE」 | 「TLAST abort 只終止目前 record；ZEROIZE 清整個公開邊界並觸發 Core scrub。」 |
| 「UVM coverage 100%，所以全部覆蓋」 | 「維護中的 functional scenario bins 為 100%；沒有 code、assertion 或 exhaustive security coverage。」 |
| 「37/37 SVA 全部證明」 | 「37 個 source statements、39 個 active instances；retained traces 中 failure 0，沒有 activation/vacuity coverage。」 |
| 「Formal PASS」 | 「19 個 combinational assertions PASS，但 whole-design formal 尚未完成，因此是 PARTIAL PASS。」 |
| 「功耗是 0.461 W」 | 「Vivado vectorless estimate 是 0.461 W、Medium confidence，不是實板 rail 量測。」 |
| 「Synthesis WNS 負數，所以設計失敗」 | 「Synthesis timing 是 early estimate；final closure 由 routed STA 判定。」 |

---

# 主管常見追問

## Q1：為什麼選 175 MHz？

> 175 MHz 是本版 production target，來自 Arty A7 100 MHz 經 MMCM 乘 7 除 4。我的目標不是追求最高 clock，而是在可 signoff 的 clock 下，利用平行化與 buffering 讓 payload throughput 超過 1 Gbit/s。

## Q2：為什麼不直接把 AXI 接到 Core？

> Core 應專注於 AES-CTR、GHASH 與 authentication。Wrapper 集中處理 AXI4-Lite channel pairing、command admission、未配對 payload、backpressure、public-frame ownership 與 ZEROIZE policy，讓 Core 與外部 protocol 解耦，也形成清楚的 verification boundary。

## Q3：為什麼 UVM、SVA、NIST 都需要？

> UVM 比對完整 transaction，SVA 檢查逐 clock temporal invariant，NIST 驗證標準向量，Vivado 檢查 physical timing／route／DRC，實板測試再驗證 exact configuration image 與 board I/O。它們回答不同問題，不能互相替代。

## Q4：為什麼 Synthesis timing 失敗，最後還能通過？

> Synthesis 使用估計 interconnect，還沒有真實 placement。Placement 與 route 後才有實際 wire delay，並可執行 physical optimization 與 hold repair。最終以 routed WNS、WHS、TNS、THS 與 FEP 作 signoff。

## Q5：這個設計最大的取捨是什麼？

> 為了把 throughput 提升到大於 1 Gbit/s，我增加兩個 first-block engines 與 sensitive queues，代價約為增加 3,230 LUT、1,046 FF。這是以面積換取 startup latency overlap；security 規則則沒有放寬，sensitive queues 仍受 abort、ZEROIZE 與 authentication-before-release 控制。

## Q6：你最誠實的未完成項目是什麼？

> Sequential／whole-design formal 尚未完成，power 缺少 SAIF 或 rail measurement，standalone PartPin 沒有 approved identity-matched map，板上 1 Gbit/s datapath throughput 也尚未用 on-chip counter 或高速介面直接量測。

---

# 不需要主講的頁面

- PDF 頁 3–8：目錄、插圖、表格索引。
- PDF 頁 12–15：完整 stage-gated 流程；主管追問流程再開。
- PDF 頁 16–18：AES／GCM 數學原理；只需知道 AES-CTR 提供 confidentiality、GHASH 提供 authentication。
- PDF 頁 28–32：Vivado 圖與 power 細節；資源或功耗追問再開。
- PDF 頁 37–44：critical path 與 timing 深入分析；主管追問 timing root cause 再開。
- PDF 頁 47–51：Wrapper register map 與 exact semantics；正常主講挑重點，細節用於追問。
- PDF 頁 58–66：UVM class hierarchy、SVA ledger、formal 範圍；不要逐表念。
- PDF 頁 71–75：工具、Tcl 與檔案位置；只作 reproducibility 證據。
- PDF 頁 77–79：SHA-256 與參考資料；不要口頭報告。

## 最後提醒

如果你緊張，只要記住這個順序：

> 三層設計 → 平行化解 throughput → Wrapper 解 protocol/security → UVM/SVA/NIST 分層驗證 → Routed timing 與實板 PASS → 誠實說明 formal/power/PartPin 限制。
