# FPGA3 — AES-GCM FPGA 專題

以 Verilog/SystemVerilog 實作的 AES-GCM IP，支援 AES-128／192／256 加解密，
包含 AXI4-Lite 控制介面、AXI4-Stream 資料介面，以及 Arty A7-100T 的 UART 實板驗證。
目標元件為 `xc7a100tcsg324-1`，保留的實作與驗證基準為 175 MHz。

## 報告與簡報

| 內容 | 連結 |
| --- | --- |
| 完整設計與驗證報告 PDF | [AESGCM_175MHz_rpt.pdf](output/pdf/AESGCM_175MHz_rpt.pdf) |
| 報告 LaTeX 原稿與圖表 | [docs/report](docs/report) |
| RTL 工程簡報 PDF | [AES-GCM_175MHz_RTL_Engineering_Report.pdf](docs/presentation/slidev-rtl-report/AES-GCM_175MHz_RTL_Engineering_Report.pdf) |
| 互動式 RTL 簡報原始碼與執行方式 | [Slidev README](docs/presentation/slidev-rtl-report/README.md) |
| 資源與功耗說明 PowerPoint | [FPGA3_Resource_Power_Explanation_175MHz.pptx](docs/presentation/resource_power/FPGA3_Resource_Power_Explanation_175MHz.pptx) |
| 專題報告講解指南 | [口語報告指南](docs/presentation/AESGCM_175MHz_rpt_口語報告指南.md) |
| 架構、時序及驗證簡報圖 | [vivado_executive_report](docs/presentation/vivado_executive_report) |
| Vivado 原生報告與畫面 | [vivado_native](docs/report/figures/vivado_native) |
| 實板實作與 signoff 報表 | [board/output](engrenring/synth_1g/board/output) |
| 驗證結果總覽 | [verification_summary.md](verification/results/verification_summary.md) |

## 原始碼與重現入口

- [engrenring/rtl/source](engrenring/rtl/source)：AES、GHASH、AXI wrapper、stream core 與板端 UART RTL。
- [engrenring/rtl/functional test](engrenring/rtl/functional%20test)：NIST 測試向量與 directed testbenches。
- [engrenring/synth_1g](engrenring/synth_1g)：Vivado Tcl 建置腳本與 XDC constraints。
- [verification](verification)：UVM、SVA、formal、板端驗證及結果摘要。
- [tcl](tcl)：Vivado 報表、電路圖與時序證據匯出工具。

既有工具環境使用 Vivado 2021.1，部分驗證另需 ModelSim 或 Yosys。
各驗證目錄的 README 說明適用範圍；整合驗證入口為
[`verification/scripts/run_all.sh`](verification/scripts/run_all.sh)，Windows 模擬器流程由 Git Bash 啟動。

## 已保留的驗證結果

依據[驗證總覽](verification/results/verification_summary.md)，175 MHz 實板實作的
setup WNS 為 +0.029 ns、hold WHS 為 +0.044 ns；完整硬體 NIST 向量測試為
47,250／47,250 通過。這是測試向量一致性驗證，不代表取得 NIST 認證。

1.052–1.065 Gbit/s 為 RTL 模擬量測的 payload throughput，並非 UART 實板吞吐率。
Formal 結果只涵蓋部分組合邏輯；功耗為 Vivado vectorless estimate。
完整限制、版本身分與證據雜湊請見報告及
[`exact_current_manifest.json`](verification/results/exact_current_manifest.json)。

## 版本控制範圍

本 repository 收錄專題原始碼、建置與驗證腳本、正式報告、簡報及報表證據。
個人履歷與面試資料、帳密、第三方參考文件、工具安裝、相依套件、暫存檔、
模擬資料庫及 Vivado DCP／bitstream 留在本機，不納入上傳。
