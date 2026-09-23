# Project 2 V5–V6 Development Log

V5's diagnostic sequence began with the first board run of the continuous ring buffer, then proceeded through PC receiver optimization, the UDP `ready` handshake, IPv4 checksum repair, PRBS reset behavior, receive-host comparisons, 315/400/MAX rate steps, and four ILA evidence captures. V6 added an ingress FIFO, concurrent DDR reads and writes, and two hysteretic watermark stages. It completed a 60-second board test and seven ILA capture conditions.

The development and verification sequence is in [V5: Continuous Ring Buffer and Performance Characterization](../../DEVELOPMENT_LOG.md#v5) and [V6: Concurrent Ingress, DDR, and Transmission Pipeline](../../DEVELOPMENT_LOG.md#v6). The [V5](../../evidence/V5.md) and [V6](../../evidence/V6.md) image and waveform indexes provide direct access to evidence. Individual run results are determined by their original JSON files.
