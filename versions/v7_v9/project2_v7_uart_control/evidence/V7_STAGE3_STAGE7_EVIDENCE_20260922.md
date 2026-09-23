# Project 2 V7 Board Evidence: Gates 3–7

## Validation results

Eighteen UART/receiver screenshots and four Windows RIO JSON files for the remaining V7 gates were cross-checked on September 22, 2026. Gates 3–7 all passed, completing V7 board validation.

| Gate | Configuration or function | Key result | Verdict |
| --- | --- | --- | --- |
| 3 | 1024 B, 12.5 Mword/s, 10 s | 244,178 packets; 250,038,272 B; 200.027857 Mb/s; zero data errors | PASS |
| 4 | 256 B, finite 1,048,576 words | Exactly 8,192 packets / 2,097,152 B; automatic stop and exact status counts | PASS |
| 5 | Unsupported source, in-run packet-length change, bad CRC | `UNSUPPORTED`, `BUSY`, silent discard; CRC=1, rejects=2 | PASS |
| 6 | 1024 B, maximum rate, 60 s | 2,925,342 packets; 2,995,550,208 B; 399.405333 Mb/s; zero data errors | PASS |
| 7 | 1024 B, maximum rate, 300 s | 14,626,556 packets; 14,977,593,344 B; 399.402011 Mb/s; zero data errors | PASS |

All four JSON files report `passed=true`, `first_sequence=0`, and zero missing/gap, duplicate, out-of-order, malformed, metadata, PRBS-data, and receive-completion errors.

RTL review explained `tx_underflow=12952` in the deliberately rate-limited Gate 3 and `tx_underflow=1` after Gate 5's slow fault-injection run. When `stream_expected=1` and the packetizer is idle without a complete packet, this counter increments for each starvation interval. Both 12.5 Mword/s (approximately 200 Mb/s) and 1000 words/s are below the roughly 400 Mb/s transmission capacity, so deliberate rate limiting creates idle intervals. The corresponding JSON remains continuous and PRBS-correct. After restoring maximum rate and issuing CLEAR_COUNTERS, the final 60- and 300-second statuses both returned to `tx_underflow=0`; other internal errors stayed at zero.

## Original evidence and SHA-256

| File | SHA-256 |
| --- | --- |
| [`v7_gate3_1024B_12M5_10s_20260922.json`](v7_gate3_1024B_12M5_10s_20260922.json) | `DDE528DDA7D010712CEC44AF43A0E250C40412E096E6B521822A2BA70B290445` |
| [`v7_gate3_receiver_1024B_12M5_pass_20260922.png`](v7_gate3_receiver_1024B_12M5_pass_20260922.png) | `9E3FEA23222FAC2DBCA53035EBF1C0E6FD754F2D39C8F161B2152EC02A0E9AC2` |
| [`v7_gate3_uart_configuration_20260922.png`](v7_gate3_uart_configuration_20260922.png) | `7A284FDF2D0689FC6D65F728072C7A7720DA2655F866164CEFC36C69BF326824` |
| [`v7_gate3_uart_start_20260922.png`](v7_gate3_uart_start_20260922.png) | `B6C33A72F0500BF7310B3D7DF9448CEF499A7562519BED2D073D86F0116AFF3F` |
| [`v7_gate3_uart_stop_status_20260922.png`](v7_gate3_uart_stop_status_20260922.png) | `C24FCA19D3897D6769B76B2DEC58798D7676901EA63889DD558AD28DACF9D300` |
| [`v7_gate4_finite_1Mwords_256B_20260922.json`](v7_gate4_finite_1Mwords_256B_20260922.json) | `9EB3C614522F09B296D787A22D53CF1113A39096952CA1C0D4CC8667561D3647` |
| [`v7_gate4_finite_configuration_20260922.png`](v7_gate4_finite_configuration_20260922.png) | `E51D580F76E6DA0DDCB2DE67A14BA9215844BFD94224A53CF23746C3C7507431` |
| [`v7_gate4_finite_final_status_20260922.png`](v7_gate4_finite_final_status_20260922.png) | `192DE7C9436CFF900F8CF5FCD274412CD4875F135BB92A5FF0A51EAB30D74F04` |
| [`v7_gate4_finite_receiver_pass_20260922.png`](v7_gate4_finite_receiver_pass_20260922.png) | `E6F0446EF1062264106D2AC25BCD97EF331FFB9525D2F74C96CABD8E50B3B302` |
| [`v7_gate4_finite_uart_start_20260922.png`](v7_gate4_finite_uart_start_20260922.png) | `3869E0FA50896C51EF2EA6E65FCCFCEAC0F7A9A8C50C8C4270314AE13737532A` |
| [`v7_gate5_bad_crc_and_status_20260922.png`](v7_gate5_bad_crc_and_status_20260922.png) | `1851D992100AA3A81CC2B38BAD5C8A1CA2156789FBC6C2B2DEEA307373493D70` |
| [`v7_gate5_busy_rejection_20260922.png`](v7_gate5_busy_rejection_20260922.png) | `B1505414146568BEC9A6F745D1950F04BAE9C6CE316038FF1DBF124530577F34` |
| [`v7_gate5_restore_and_clear_20260922.png`](v7_gate5_restore_and_clear_20260922.png) | `791C5C79F1B3F515834176BBF2E67D9AD9F02FE783886D94CCD5A819A0BF60F0` |
| [`v7_gate5_source_unsupported_20260922.png`](v7_gate5_source_unsupported_20260922.png) | `CBBA68E0884BA8499FD7A0D9F528A7F25C27A0406C304B9B1BCC1FC48D3FD045` |
| [`v7_gate6_1024B_max_60s_20260922.json`](v7_gate6_1024B_max_60s_20260922.json) | `EE2CCC359CF3183B11E2B752FC24C4971ACC3033B007906112E848165712B197` |
| [`v7_gate6_receiver_1024B_max_60s_pass_20260922.png`](v7_gate6_receiver_1024B_max_60s_pass_20260922.png) | `3767AE3856C4BA3F137B691DF57FEC70E18AE5C60A73A4501C83595525FDF7B3` |
| [`v7_gate6_uart_start_20260922.png`](v7_gate6_uart_start_20260922.png) | `C1791C2080A971E0CA22BAC96F3BA14DA9DA4AA057AE82BC839740DA20978D8E` |
| [`v7_gate6_uart_stop_status_20260922.png`](v7_gate6_uart_stop_status_20260922.png) | `21A1072C8F1CB166E932723951ECF35E1E0ECE4E2953E6DFF35566A7CA78DAE5` |
| [`v7_gate7_1024B_max_300s_20260922.json`](v7_gate7_1024B_max_300s_20260922.json) | `D4684A31798885387350A771D110C6229C991B9B1BA6823D5DD9D65A3AADEFE2` |
| [`v7_gate7_configuration_and_clear_20260922.png`](v7_gate7_configuration_and_clear_20260922.png) | `5E1D31C0832BD4995A787FB5E112FC80DE4A2E469DE212B07968DC0494F854C6` |
| [`v7_gate7_receiver_1024B_max_300s_pass_20260922.png`](v7_gate7_receiver_1024B_max_300s_pass_20260922.png) | `847318DD0C77C7388E510E71A41E999FB747DDCCC0F600B2D78E57C4717A22A8` |
| [`v7_gate7_uart_stop_status_20260922.png`](v7_gate7_uart_stop_status_20260922.png) | `64050E59449AEE3DA42E140658C9922B68B11DAD917A8634F30ADD0B71CB20D6` |

All listed files are stored in this `evidence` directory.
