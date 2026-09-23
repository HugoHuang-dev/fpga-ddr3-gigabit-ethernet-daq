# V9 ModelSim 10.6c regression summary

Generated: 2026-09-23 00:52:49 +08:00

This regression compiles and simulates the V9 project RTL directly; no V8 test is counted as V9 evidence.

| Test | Result | Self-checked coverage | Raw transcript |
|---|---:|---|---|
| ingress_fifo | PASS | FIFO full/empty and watermarks; hysteretic source gate; input/output backpressure; ordering; simultaneous push/pop; flush; overflow/underflow injection; counter clear | [transcript](./ingress_fifo_transcript.log) |
| packetizer | PASS | Exact 32-byte P2V9 header; 1024-byte payload byte comparison; packet sequence; 64-bit first-word index; packet-boundary app_tx_ready backpressure; early/late last; overflow/underflow; clear | [transcript](./packetizer_transcript.log) |
| pipeline_controller | PASS | Ring write/read pointers and wrap; committed/released accounting; high/low-water drain hysteresis; write/read backpressure; overflow/underflow fault injection; FIFO/packetizer fatal inputs; AXI BRESP error | [transcript](./pipeline_controller_transcript.log) |

**Overall: PASS — 3/3 self-checking RTL simulations passed.**

The packetizer backpressure test covers the real packet-boundary contract: a packet is not launched while `app_tx_ready` is low, queued bytes and sequence/index remain unchanged, and ready-low/high is exercised between packets.

