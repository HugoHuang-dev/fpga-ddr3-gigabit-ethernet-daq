# Original 200 Mb/s replay: FAIL

Original archived BIT/LTX/receiver restored by the user. Administrator receiver, NIC PktMon capture, 60-second test.

- Duration: 60.00019 s
- Payload rate: 199.752003185 Mb/s
- Received packets: 1,463,032
- Missing: 7 in one gap, expected 112676, received 112683
- All other receiver error counters: zero
- PktMon reports no lost events; conversion produced 2,945,188 packet records.

The entire PCAPNG was scanned for P2V5 sequence headers. Sequences 112670–112675 and 112683–112689 each occur twice. Every sequence 112676–112682 occurs zero times. Detailed output is in sequence_analysis.txt. Repeated capture observations are not interpreted as duplicate physical Ethernet frames. Capture timestamps reflect software observation and USB delivery batching; they are not wire transmission timestamps.

This same-run agreement places the missing observations upstream of the recorded NIC observation point, subject to capture completeness. It does not distinguish FPGA frame generation, PHY/link, NIC hardware, USB transport or driver behavior before that point. It does not prove that all FPGA logic is correct. No MAC overflow probe observation is available for this archived image.

200 Mb/s is not a qualified loss-free baseline. Previous passes remain valid short observations, but cannot establish reliability or a numerical success probability. No further rate stepping is justified.

Next discriminating experiment: retain the exact FPGA BIT and receiver; substitute an available independent Ethernet receive path, preferably a built-in Ethernet port on a second PC, with the same addressing and capture procedure. This tests the receiver-path hypothesis; one pass alone is insufficient. If an independent receive path is unavailable, an independent wire observation (network TAP or suitable mirrored switch port) is needed to separate the FPGA/link side from the existing NIC path. Merely replacing the capture software on the same NIC does not add an upstream observation point.
