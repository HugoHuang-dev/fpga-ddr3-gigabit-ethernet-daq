#define _WIN32_WINNT 0x0602
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <winsock2.h>
#include <mswsock.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <icmpapi.h>
#include <windows.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <string>
#include <vector>

#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "iphlpapi.lib")

namespace {
constexpr uint16_t kPcPort = 6666;
constexpr size_t kHeaderBytes = 24;
constexpr uint32_t kRingBytes = 256 * 1024;
constexpr uint16_t kPrbsSeed = 0xACE1;
constexpr size_t kPrbsWords = 65535;
constexpr int kMonitorVersion = 8;
constexpr ULONG kRioSlots = 16384;
constexpr ULONG kRioSlotBytes = 2048;
constexpr ULONG kRioBatch = 256;
constexpr size_t kRecordedGaps = 128;

struct GapRecord {
    uint32_t expected;
    uint32_t received;
    uint32_t missing;
};

struct Options {
    std::string fpga_ip = "192.168.1.11";
    std::string pc_ip = "192.168.1.100";
    double duration = 60.0;
    double first_timeout = 20.0;
    int rcvbuf_mb = 64;
    std::string output = "evidence\\v8_acquisition_result.json";
};

uint16_t prbs_next(uint16_t value) {
    const uint16_t feedback = static_cast<uint16_t>(
        ((value >> 15) ^ (value >> 13) ^ (value >> 12) ^ (value >> 10)) & 1);
    return static_cast<uint16_t>((value << 1) | feedback);
}

std::vector<uint8_t> build_prbs_period() {
    std::vector<uint8_t> result(kPrbsWords * 2);
    uint16_t value = kPrbsSeed;
    for (size_t i = 0; i < kPrbsWords; ++i) {
        result[i * 2] = static_cast<uint8_t>(value & 0xff);
        result[i * 2 + 1] = static_cast<uint8_t>(value >> 8);
        value = prbs_next(value);
    }
    if (value != kPrbsSeed) throw std::runtime_error("PRBS period check failed");
    return result;
}

uint16_t be16(const uint8_t* p) {
    return static_cast<uint16_t>((uint16_t(p[0]) << 8) | p[1]);
}

uint32_t be32(const uint8_t* p) {
    return (uint32_t(p[0]) << 24) | (uint32_t(p[1]) << 16) |
           (uint32_t(p[2]) << 8) | uint32_t(p[3]);
}

bool payload_matches(const uint8_t* payload, size_t payload_bytes, uint32_t sequence,
                     const std::vector<uint8_t>& period, uint64_t& bad_bytes) {
    const size_t offset = (uint64_t(sequence) * payload_bytes) % period.size();
    const size_t first = std::min(payload_bytes, period.size() - offset);
    bool equal = std::memcmp(payload, period.data() + offset, first) == 0;
    if (first != payload_bytes)
        equal = equal && std::memcmp(payload + first, period.data(), payload_bytes - first) == 0;
    if (equal) return true;

    for (size_t i = 0; i < payload_bytes; ++i) {
        const uint8_t expected = period[(offset + i) % period.size()];
        if (payload[i] != expected) ++bad_bytes;
    }
    return false;
}

bool ping_fpga(const std::string& ip) {
    in_addr parsed_address{};
    if (inet_pton(AF_INET, ip.c_str(), &parsed_address) != 1) return false;
    const IPAddr address = parsed_address.S_un.S_addr;
    HANDLE handle = IcmpCreateFile();
    if (handle == INVALID_HANDLE_VALUE) return false;
    const char request[] = "P2V8";
    std::vector<uint8_t> reply(sizeof(ICMP_ECHO_REPLY) + sizeof(request) + 32);
    const DWORD count = IcmpSendEcho(handle, address, const_cast<char*>(request),
        static_cast<WORD>(sizeof(request)), nullptr, reply.data(),
        static_cast<DWORD>(reply.size()), 1000);
    IcmpCloseHandle(handle);
    return count != 0;
}

bool parse_args(int argc, char** argv, Options& o) {
    for (int i = 1; i < argc; ++i) {
        const std::string key = argv[i];
        if (i + 1 >= argc) return false;
        const std::string value = argv[++i];
        try {
            if (key == "--fpga-ip") o.fpga_ip = value;
            else if (key == "--pc-ip") o.pc_ip = value;
            else if (key == "--duration") o.duration = std::stod(value);
            else if (key == "--first-timeout") o.first_timeout = std::stod(value);
            else if (key == "--rcvbuf-mb") o.rcvbuf_mb = std::stoi(value);
            else if (key == "--output") o.output = value;
            else return false;
        } catch (...) { return false; }
    }
    return o.duration > 0 && o.first_timeout > 0 && o.rcvbuf_mb > 0;
}
}

int main(int argc, char** argv) {
    Options options;
    if (!parse_args(argc, argv, options)) {
        std::cerr << "Usage: udp_v8_monitor_rio.exe [--fpga-ip IP] [--pc-ip IP] "
                     "[--duration SEC] [--first-timeout SEC] [--rcvbuf-mb MB] "
                     "[--output FILE]\n";
        return 64;
    }

    const bool process_priority_ok =
        SetPriorityClass(GetCurrentProcess(), HIGH_PRIORITY_CLASS) != 0;
    const bool thread_priority_ok =
        SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_HIGHEST) != 0;
    std::cout << "Project2 v8 Windows RIO PC monitor v" << kMonitorVersion << "\n";
    std::cout << "Receive priority: process="
              << (process_priority_ok ? "high" : "unchanged")
              << " thread=" << (thread_priority_ok ? "highest" : "unchanged") << "\n";
    std::cout << "Preparing direct-index PRBS reference table ...\n";
    const auto period = build_prbs_period();

    WSADATA wsa{};
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) return 1;
    std::cout << "Checking FPGA reachability at " << options.fpga_ip << " ...\n";
    if (!ping_fpga(options.fpga_ip)) {
        std::cerr << "FAIL: FPGA ping failed\n";
        WSACleanup();
        return 1;
    }
    std::cout << "PASS: FPGA ping reply received\n";

    SOCKET sock = WSASocketW(AF_INET, SOCK_DGRAM, IPPROTO_UDP, nullptr, 0,
                             WSA_FLAG_REGISTERED_IO);
    if (sock == INVALID_SOCKET) { WSACleanup(); return 1; }
    const int requested_buffer = options.rcvbuf_mb * 1024 * 1024;
    setsockopt(sock, SOL_SOCKET, SO_RCVBUF,
               reinterpret_cast<const char*>(&requested_buffer), sizeof(requested_buffer));
    int actual_buffer = 0;
    int option_length = sizeof(actual_buffer);
    getsockopt(sock, SOL_SOCKET, SO_RCVBUF,
               reinterpret_cast<char*>(&actual_buffer), &option_length);
    sockaddr_in local{};
    local.sin_family = AF_INET;
    local.sin_port = htons(kPcPort);
    if (inet_pton(AF_INET, options.pc_ip.c_str(), &local.sin_addr) != 1 ||
        bind(sock, reinterpret_cast<sockaddr*>(&local), sizeof(local)) == SOCKET_ERROR) {
        std::cerr << "FAIL: cannot bind " << options.pc_ip << ':' << kPcPort
                  << " WSA=" << WSAGetLastError() << "\n";
        closesocket(sock); WSACleanup(); return 1;
    }
    std::cout << "ARMED: listening on " << options.pc_ip << ':' << kPcPort << "\n";
    std::cout << "Socket receive buffer: requested=" << requested_buffer
              << " bytes actual=" << actual_buffer << " bytes\n";
    std::cout << "Receive engine: Windows Registered I/O, slots=" << kRioSlots
              << " batch=" << kRioBatch << "\n";
    std::cout << "Send CLEAR_COUNTERS then START over UART after this monitor is armed.\n";

    GUID rio_table_id = WSAID_MULTIPLE_RIO;
    RIO_EXTENSION_FUNCTION_TABLE rio{};
    DWORD rio_bytes = 0;
    if (WSAIoctl(sock, SIO_GET_MULTIPLE_EXTENSION_FUNCTION_POINTER,
                 &rio_table_id, sizeof(rio_table_id), &rio, sizeof(rio),
                 &rio_bytes, nullptr, nullptr) == SOCKET_ERROR) {
        std::cerr << "FAIL: RIO extension table unavailable, WSA="
                  << WSAGetLastError() << "\n";
        closesocket(sock); WSACleanup(); return 1;
    }

    HANDLE rio_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    RIO_NOTIFICATION_COMPLETION notification{};
    notification.Type = RIO_EVENT_COMPLETION;
    notification.Event.EventHandle = rio_event;
    notification.Event.NotifyReset = TRUE;
    RIO_CQ completion_queue = rio.RIOCreateCompletionQueue(kRioSlots + 1, &notification);
    RIO_RQ request_queue = rio.RIOCreateRequestQueue(
        sock, kRioSlots, 1, 1, 1, completion_queue, completion_queue, nullptr);
    std::vector<char> rio_storage(size_t(kRioSlots) * kRioSlotBytes);
    RIO_BUFFERID rio_buffer_id = rio.RIORegisterBuffer(
        rio_storage.data(), static_cast<DWORD>(rio_storage.size()));
    if (!rio_event || completion_queue == RIO_INVALID_CQ ||
        request_queue == RIO_INVALID_RQ || rio_buffer_id == RIO_INVALID_BUFFERID) {
        std::cerr << "FAIL: RIO initialization failed, WSA=" << WSAGetLastError() << "\n";
        if (rio_buffer_id != RIO_INVALID_BUFFERID) rio.RIODeregisterBuffer(rio_buffer_id);
        if (completion_queue != RIO_INVALID_CQ) rio.RIOCloseCompletionQueue(completion_queue);
        if (rio_event) CloseHandle(rio_event);
        closesocket(sock); WSACleanup(); return 1;
    }

    auto post_receive = [&](ULONG slot) {
        RIO_BUF data_buffer{};
        data_buffer.BufferId = rio_buffer_id;
        data_buffer.Offset = slot * kRioSlotBytes;
        data_buffer.Length = kRioSlotBytes;
        return rio.RIOReceive(request_queue, &data_buffer, 1, 0,
            reinterpret_cast<PVOID>(static_cast<uintptr_t>(slot + 1)));
    };
    for (ULONG slot = 0; slot < kRioSlots; ++slot) {
        if (!post_receive(slot)) {
            std::cerr << "FAIL: initial RIOReceive post failed, WSA="
                      << WSAGetLastError() << "\n";
            rio.RIODeregisterBuffer(rio_buffer_id);
            rio.RIOCloseCompletionQueue(completion_queue);
            CloseHandle(rio_event); closesocket(sock); WSACleanup(); return 1;
        }
    }

    using clock = std::chrono::steady_clock;
    const auto armed_at = clock::now();
    auto started_at = armed_at;
    auto last_print = armed_at;
    bool started = false;
    uint32_t expected_sequence = 0;
    uint32_t first_sequence = 0;
    bool sequence_initialized = false;
    uint64_t packets = 0, payload_bytes = 0, missing = 0, duplicates = 0;
    uint64_t out_of_order = 0, malformed = 0, metadata_errors = 0;
    uint64_t data_error_packets = 0, data_error_bytes = 0;
    uint64_t gap_events = 0, receive_errors = 0;
    uint32_t max_gap = 0, max_occupancy = 0, last_occupancy = 0, last_committed = 0;
    uint16_t observed_payload_bytes = 0;
    uint8_t observed_source = 0xff;
    uint64_t source_mismatches = 0;
    uint64_t xadc_records = 0, xadc_invalid_records = 0;
    uint64_t xadc_channel_order_errors = 0;
    uint8_t expected_xadc_channel = 0;
    std::array<uint64_t,4> xadc_channel_records{};
    std::array<uint16_t,4> xadc_min_raw{{0xffff,0xffff,0xffff,0xffff}};
    std::array<uint16_t,4> xadc_max_raw{};
    std::vector<GapRecord> gap_records;
    gap_records.reserve(kRecordedGaps);
    std::vector<RIORESULT> completions(kRioBatch);

    auto process_packet = [&](const uint8_t* buffer, ULONG length) {
        const uint16_t payload_size = length >= kHeaderBytes ? be16(&buffer[12]) : 0;
        const bool payload_size_valid = payload_size == 256 || payload_size == 512 ||
                                        payload_size == 1024;
        const uint8_t source_id = length >= kHeaderBytes ? buffer[5] : 0xff;
        if (length < kHeaderBytes || std::memcmp(buffer, "P2V8", 4) != 0 ||
            buffer[4] != 8 || source_id > 1 || be16(&buffer[6]) != length ||
            !payload_size_valid || length != kHeaderBytes + payload_size ||
            be16(&buffer[14]) != kHeaderBytes) {
            ++malformed;
            return;
        }
        if (observed_payload_bytes == 0) observed_payload_bytes = payload_size;
        if (payload_size != observed_payload_bytes) {
            ++metadata_errors;
            return;
        }
        if (observed_source == 0xff) observed_source = source_id;
        if (source_id != observed_source) {
            ++source_mismatches;
            ++metadata_errors;
            return;
        }
        const uint32_t sequence = be32(&buffer[8]);
        const uint32_t committed = be32(&buffer[16]);
        const uint32_t occupancy = be32(&buffer[20]);
        if (!started) {
            started = true;
            started_at = clock::now();
            last_print = started_at;
        }

        // Listening and KEY0 are not an atomic operation.  Anchor continuity
        // to the first delivered packet instead of classifying an unknown
        // startup prefix as loss.  Every gap after this packet is still strict.
        if (!sequence_initialized) {
            first_sequence = sequence;
            expected_sequence = sequence;
            sequence_initialized = true;
        }

        const uint32_t delta = sequence - expected_sequence;
        if (delta == 0) {
        } else if (delta < 0x80000000u) {
            missing += delta;
            ++gap_events;
            max_gap = std::max(max_gap, delta);
            if (gap_records.size() < kRecordedGaps) {
                gap_records.push_back({expected_sequence, sequence, delta});
                std::cout << "GAP: expected=" << expected_sequence
                          << " received=" << sequence << " missing=" << delta << "\n";
            }
        } else if (sequence == expected_sequence - 1u) {
            ++duplicates;
            return;
        } else {
            ++out_of_order;
            return;
        }
        expected_sequence = sequence + 1u;

        uint64_t packet_bad_bytes = 0;
        if (source_id == 0) {
            if (!payload_matches(buffer + kHeaderBytes, payload_size, sequence, period,
                                 packet_bad_bytes)) {
                ++data_error_packets;
                data_error_bytes += packet_bad_bytes;
            }
        } else {
            bool packet_has_xadc_error = false;
            for (size_t i = 0; i < payload_size; i += 2) {
                const uint16_t record = static_cast<uint16_t>(
                    buffer[kHeaderBytes+i] | (uint16_t(buffer[kHeaderBytes+i+1]) << 8));
                const uint8_t channel = static_cast<uint8_t>((record >> 14) & 3);
                const uint16_t raw = record & 0x0fff;
                if ((record & 0x3000) != 0) {
                    ++xadc_invalid_records;
                    packet_has_xadc_error = true;
                }
                if (channel != expected_xadc_channel) {
                    ++xadc_channel_order_errors;
                    packet_has_xadc_error = true;
                    expected_xadc_channel = channel;
                }
                expected_xadc_channel = static_cast<uint8_t>((expected_xadc_channel + 1) & 3);
                ++xadc_records;
                ++xadc_channel_records[channel];
                xadc_min_raw[channel] = std::min(xadc_min_raw[channel], raw);
                xadc_max_raw[channel] = std::max(xadc_max_raw[channel], raw);
            }
            if (packet_has_xadc_error) ++data_error_packets;
        }
        if ((committed % 1024) != 0 || (occupancy % 1024) != 0 ||
            occupancy > kRingBytes) ++metadata_errors;
        last_committed = committed;
        last_occupancy = occupancy;
        max_occupancy = std::max(max_occupancy, occupancy);
        ++packets;
        payload_bytes += payload_size;
    };

    bool receive_failed = false;
    while (true) {
        const auto now = clock::now();
        const double armed_seconds = std::chrono::duration<double>(now - armed_at).count();
        if (!started && armed_seconds >= options.first_timeout) {
            std::cerr << "FAIL: no v8 packet received before first-packet timeout.\n";
            break;
        }
        if (started && std::chrono::duration<double>(now - started_at).count() >= options.duration)
            break;

        if (rio.RIONotify(completion_queue) == SOCKET_ERROR) {
            std::cerr << "FAIL: RIONotify WSA=" << WSAGetLastError() << "\n";
            receive_failed = true;
            break;
        }
        const DWORD wait_result = WaitForSingleObject(rio_event, 100);
        if (wait_result == WAIT_TIMEOUT) continue;
        if (wait_result != WAIT_OBJECT_0) {
            std::cerr << "FAIL: RIO completion wait error=" << GetLastError() << "\n";
            receive_failed = true;
            break;
        }

        while (true) {
            const ULONG completed = rio.RIODequeueCompletion(
                completion_queue, completions.data(), kRioBatch);
            if (completed == RIO_CORRUPT_CQ) {
                std::cerr << "FAIL: RIO completion queue corrupt\n";
                receive_failed = true;
                break;
            }
            if (completed == 0) break;
            for (ULONG i = 0; i < completed; ++i) {
                const auto& result = completions[i];
                const uintptr_t context = static_cast<uintptr_t>(result.RequestContext);
                if (context == 0 || context > kRioSlots) {
                    ++receive_errors;
                    continue;
                }
                const ULONG slot = static_cast<ULONG>(context - 1);
                if (result.Status == NO_ERROR) {
                    const auto* packet = reinterpret_cast<const uint8_t*>(
                        rio_storage.data() + size_t(slot) * kRioSlotBytes);
                    process_packet(packet, result.BytesTransferred);
                } else {
                    ++receive_errors;
                }
                if (!post_receive(slot)) {
                    std::cerr << "FAIL: RIOReceive repost WSA=" << WSAGetLastError() << "\n";
                    receive_failed = true;
                    break;
                }
            }
            if (receive_failed) break;
        }
        if (receive_failed) break;

        const auto after_packet = clock::now();
        if (started && std::chrono::duration<double>(after_packet - last_print).count() >= 1.0) {
            const double elapsed = std::chrono::duration<double>(after_packet - started_at).count();
            const double rate = double(payload_bytes) * 8.0 / elapsed / 1e6;
            std::cout << std::fixed << std::setprecision(2)
                      << "STAT: time=" << std::setw(7) << elapsed
                      << "s packets=" << packets << std::setprecision(3)
                      << " rate=" << rate << " Mb/s missing=" << missing
                      << " gap_events=" << gap_events << " max_gap=" << max_gap
                      << " duplicate=" << duplicates << " out_of_order=" << out_of_order
                      << " malformed=" << malformed << " data_error_packets="
                      << data_error_packets << " metadata_errors=" << metadata_errors
                      << " occupancy=" << last_occupancy << '/' << kRingBytes << "\n";
            last_print = after_packet;
        }
    }

    const double elapsed = started ?
        std::chrono::duration<double>(clock::now() - started_at).count() : 0.0;
    const double rate = elapsed > 0 ? double(payload_bytes) * 8.0 / elapsed / 1e6 : 0.0;
    const bool passed = packets > 0 && missing == 0 && duplicates == 0 &&
        out_of_order == 0 && malformed == 0 && metadata_errors == 0 &&
        data_error_packets == 0 && data_error_bytes == 0 && receive_errors == 0 &&
        source_mismatches == 0 && xadc_invalid_records == 0 &&
        xadc_channel_order_errors == 0 && !receive_failed;

    std::ofstream json(options.output, std::ios::binary);
    json << std::boolalpha << "{\n"
         << "  \"passed\": " << passed << ",\n"
         << "  \"monitor_version\": " << kMonitorVersion << ",\n"
         << "  \"receive_engine\": \"windows_rio\",\n"
         << "  \"duration_seconds\": " << std::setprecision(12) << elapsed << ",\n"
         << "  \"packets_received\": " << packets << ",\n"
         << "  \"payload_bytes\": " << payload_bytes << ",\n"
         << "  \"udp_payload_bytes\": " << observed_payload_bytes << ",\n"
         << "  \"source_id\": " << unsigned(observed_source) << ",\n"
         << "  \"source_name\": \""
         << (observed_source == 0 ? "deterministic_prbs16" :
             observed_source == 1 ? "internal_xadc" : "unknown") << "\",\n"
         << "  \"payload_rate_mbps\": " << rate << ",\n"
         << "  \"first_sequence\": " << first_sequence << ",\n"
         << "  \"missing_packets\": " << missing << ",\n"
         << "  \"gap_events\": " << gap_events << ",\n"
         << "  \"max_gap_packets\": " << max_gap << ",\n"
         << "  \"gap_records_truncated\": "
         << (gap_events > gap_records.size()) << ",\n"
         << "  \"gap_records\": [";
    for (size_t i = 0; i < gap_records.size(); ++i) {
        if (i != 0) json << ',';
        json << "{\"expected\":" << gap_records[i].expected
             << ",\"received\":" << gap_records[i].received
             << ",\"missing\":" << gap_records[i].missing << '}';
    }
    json << "],\n"
         << "  \"duplicates\": " << duplicates << ",\n"
         << "  \"out_of_order\": " << out_of_order << ",\n"
         << "  \"malformed\": " << malformed << ",\n"
         << "  \"metadata_errors\": " << metadata_errors << ",\n"
         << "  \"data_error_packets\": " << data_error_packets << ",\n"
         << "  \"data_error_bytes\": " << data_error_bytes << ",\n"
         << "  \"source_mismatches\": " << source_mismatches << ",\n"
         << "  \"xadc_records\": " << xadc_records << ",\n"
         << "  \"xadc_invalid_records\": " << xadc_invalid_records << ",\n"
         << "  \"xadc_channel_order_errors\": " << xadc_channel_order_errors << ",\n"
         << "  \"xadc_records_by_channel\": [" << xadc_channel_records[0] << ','
         << xadc_channel_records[1] << ',' << xadc_channel_records[2] << ','
         << xadc_channel_records[3] << "],\n"
         << "  \"xadc_raw_min\": ["
         << (xadc_min_raw[0] == 0xffff ? 0 : xadc_min_raw[0]) << ','
         << (xadc_min_raw[1] == 0xffff ? 0 : xadc_min_raw[1]) << ','
         << (xadc_min_raw[2] == 0xffff ? 0 : xadc_min_raw[2]) << ','
         << (xadc_min_raw[3] == 0xffff ? 0 : xadc_min_raw[3]) << "],\n"
         << "  \"xadc_raw_max\": [" << xadc_max_raw[0] << ',' << xadc_max_raw[1]
         << ',' << xadc_max_raw[2] << ',' << xadc_max_raw[3] << "],\n"
         << "  \"receive_completion_errors\": " << receive_errors << ",\n"
         << "  \"max_reported_occupancy_bytes\": " << max_occupancy << ",\n"
         << "  \"last_committed_bytes_low\": " << last_committed << ",\n"
         << "  \"socket_receive_buffer_requested_bytes\": " << requested_buffer << ",\n"
         << "  \"socket_receive_buffer_actual_bytes\": " << actual_buffer << ",\n"
         << "  \"rio_slots\": " << kRioSlots << ",\n"
         << "  \"process_priority_high\": " << process_priority_ok << ",\n"
         << "  \"thread_priority_highest\": " << thread_priority_ok << ",\n"
         << "  \"rio_completion_batch\": " << kRioBatch << "\n}\n";
    json.close();

    std::cout << std::fixed << std::setprecision(3)
              << "FINAL: time=" << elapsed << "s packets=" << packets
              << " rate=" << rate << " Mb/s missing=" << missing
              << " gap_events=" << gap_events << " max_gap=" << max_gap
              << " duplicate=" << duplicates << " out_of_order=" << out_of_order
              << " malformed=" << malformed << " metadata_errors=" << metadata_errors
              << " data_error_packets=" << data_error_packets
              << " data_error_bytes=" << data_error_bytes
              << " source=" << unsigned(observed_source)
              << " xadc_records=" << xadc_records
              << " xadc_order_errors=" << xadc_channel_order_errors
              << " receive_completion_errors=" << receive_errors
              << " payload_bytes=" << payload_bytes
              << " max_occupancy=" << max_occupancy << "\n";
    std::cout << "JSON result written to " << options.output << "\n";
    std::cout << "Send STOP over UART to stop production and drain complete bursts.\n";
    std::cout << (passed ? "V8 ACQUISITION STREAM TEST PASSED\n"
                        : "V8 ACQUISITION STREAM TEST FAILED\n");
    rio.RIODeregisterBuffer(rio_buffer_id);
    rio.RIOCloseCompletionQueue(completion_queue);
    CloseHandle(rio_event);
    closesocket(sock);
    WSACleanup();
    return passed ? 0 : 2;
}
