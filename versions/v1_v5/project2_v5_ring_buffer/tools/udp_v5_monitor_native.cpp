#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <icmpapi.h>
#include <windows.h>

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <string>
#include <vector>

#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "iphlpapi.lib")

namespace {
constexpr uint16_t kPcPort = 6666;
constexpr size_t kHeaderBytes = 24;
constexpr size_t kDataBytes = 1024;
constexpr size_t kPacketBytes = kHeaderBytes + kDataBytes;
constexpr uint32_t kRingBytes = 256 * 1024;
constexpr uint16_t kPrbsSeed = 0xACE1;
constexpr size_t kPrbsWords = 65535;
constexpr int kMonitorVersion = 3;

struct Options {
    std::string fpga_ip = "192.168.1.11";
    std::string pc_ip = "192.168.1.100";
    double duration = 60.0;
    double first_timeout = 20.0;
    int rcvbuf_mb = 64;
    std::string output = "evidence\\v5_60s_v3_result.json";
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

bool payload_matches(const uint8_t* payload, uint32_t sequence,
                     const std::vector<uint8_t>& period, uint64_t& bad_bytes) {
    const size_t offset = (uint64_t(sequence) * kDataBytes) % period.size();
    const size_t first = std::min(kDataBytes, period.size() - offset);
    bool equal = std::memcmp(payload, period.data() + offset, first) == 0;
    if (first != kDataBytes)
        equal = equal && std::memcmp(payload + first, period.data(), kDataBytes - first) == 0;
    if (equal) return true;

    for (size_t i = 0; i < kDataBytes; ++i) {
        const uint8_t expected = period[(offset + i) % period.size()];
        if (payload[i] != expected) ++bad_bytes;
    }
    return false;
}

bool ping_fpga(const std::string& ip) {
    IPAddr address = inet_addr(ip.c_str());
    if (address == INADDR_NONE) return false;
    HANDLE handle = IcmpCreateFile();
    if (handle == INVALID_HANDLE_VALUE) return false;
    const char request[] = "P2V5";
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
        std::cerr << "Usage: udp_v5_monitor_native.exe [--fpga-ip IP] [--pc-ip IP] "
                     "[--duration SEC] [--first-timeout SEC] [--rcvbuf-mb MB] "
                     "[--output FILE]\n";
        return 64;
    }

    std::cout << "Project2 v5 native PC monitor v" << kMonitorVersion << "\n";
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

    SOCKET sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (sock == INVALID_SOCKET) { WSACleanup(); return 1; }
    const int requested_buffer = options.rcvbuf_mb * 1024 * 1024;
    setsockopt(sock, SOL_SOCKET, SO_RCVBUF,
               reinterpret_cast<const char*>(&requested_buffer), sizeof(requested_buffer));
    int actual_buffer = 0;
    int option_length = sizeof(actual_buffer);
    getsockopt(sock, SOL_SOCKET, SO_RCVBUF,
               reinterpret_cast<char*>(&actual_buffer), &option_length);
    const DWORD timeout_ms = 100;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO,
               reinterpret_cast<const char*>(&timeout_ms), sizeof(timeout_ms));

    sockaddr_in local{};
    local.sin_family = AF_INET;
    local.sin_port = htons(kPcPort);
    if (inet_pton(AF_INET, options.pc_ip.c_str(), &local.sin_addr) != 1 ||
        bind(sock, reinterpret_cast<sockaddr*>(&local), sizeof(local)) == SOCKET_ERROR) {
        std::cerr << "FAIL: cannot bind " << options.pc_ip << ':' << kPcPort
                  << " WSA=" << WSAGetLastError() << "\n";
        closesocket(sock); WSACleanup(); return 1;
    }
    in_addr fpga_address{};
    inet_pton(AF_INET, options.fpga_ip.c_str(), &fpga_address);
    std::cout << "ARMED: listening on " << options.pc_ip << ':' << kPcPort << "\n";
    std::cout << "Socket receive buffer: requested=" << requested_buffer
              << " bytes actual=" << actual_buffer << " bytes\n";
    std::cout << "Press FPGA KEY0 once to start v5; press RESET after the monitor finishes.\n";

    using clock = std::chrono::steady_clock;
    const auto armed_at = clock::now();
    auto started_at = armed_at;
    auto last_print = armed_at;
    bool started = false;
    uint32_t expected_sequence = 0;
    uint64_t packets = 0, payload_bytes = 0, missing = 0, duplicates = 0;
    uint64_t out_of_order = 0, malformed = 0, metadata_errors = 0;
    uint64_t data_error_packets = 0, data_error_bytes = 0;
    uint32_t max_occupancy = 0, last_committed = 0;
    std::vector<uint8_t> buffer(65536);

    while (true) {
        const auto now = clock::now();
        const double armed_seconds = std::chrono::duration<double>(now - armed_at).count();
        if (!started && armed_seconds >= options.first_timeout) {
            std::cerr << "FAIL: no v5 packet received before first-packet timeout.\n";
            break;
        }
        if (started && std::chrono::duration<double>(now - started_at).count() >= options.duration)
            break;

        sockaddr_in peer{};
        int peer_length = sizeof(peer);
        const int length = recvfrom(sock, reinterpret_cast<char*>(buffer.data()),
            static_cast<int>(buffer.size()), 0,
            reinterpret_cast<sockaddr*>(&peer), &peer_length);
        if (length == SOCKET_ERROR) {
            const int error = WSAGetLastError();
            if (error == WSAETIMEDOUT || error == WSAEWOULDBLOCK) continue;
            std::cerr << "FAIL: recvfrom WSA=" << error << "\n";
            break;
        }
        if (peer.sin_addr.s_addr != fpga_address.s_addr) continue;

        if (length != int(kPacketBytes) || std::memcmp(buffer.data(), "P2V5", 4) != 0 ||
            buffer[4] != 5 || buffer[5] != 0 || be16(&buffer[6]) != kPacketBytes ||
            be16(&buffer[12]) != kDataBytes || be16(&buffer[14]) != kHeaderBytes) {
            ++malformed;
            continue;
        }
        const uint32_t sequence = be32(&buffer[8]);
        const uint32_t committed = be32(&buffer[16]);
        const uint32_t occupancy = be32(&buffer[20]);
        if (!started) {
            started = true;
            started_at = clock::now();
            last_print = started_at;
        }

        const uint32_t delta = sequence - expected_sequence;
        if (delta == 0) {
        } else if (delta < 0x80000000u) {
            missing += delta;
        } else if (sequence == expected_sequence - 1u) {
            ++duplicates;
            continue;
        } else {
            ++out_of_order;
            continue;
        }
        expected_sequence = sequence + 1u;

        uint64_t packet_bad_bytes = 0;
        if (!payload_matches(buffer.data() + kHeaderBytes, sequence, period, packet_bad_bytes)) {
            ++data_error_packets;
            data_error_bytes += packet_bad_bytes;
        }
        if ((committed % kDataBytes) != 0 || (occupancy % kDataBytes) != 0 ||
            occupancy > kRingBytes) ++metadata_errors;
        last_committed = committed;
        max_occupancy = std::max(max_occupancy, occupancy);
        ++packets;
        payload_bytes += kDataBytes;

        const auto after_packet = clock::now();
        if (std::chrono::duration<double>(after_packet - last_print).count() >= 1.0) {
            const double elapsed = std::chrono::duration<double>(after_packet - started_at).count();
            const double rate = double(payload_bytes) * 8.0 / elapsed / 1e6;
            std::cout << std::fixed << std::setprecision(2)
                      << "STAT: time=" << std::setw(7) << elapsed
                      << "s packets=" << packets << std::setprecision(3)
                      << " rate=" << rate << " Mb/s missing=" << missing
                      << " duplicate=" << duplicates << " out_of_order=" << out_of_order
                      << " malformed=" << malformed << " data_error_packets="
                      << data_error_packets << " metadata_errors=" << metadata_errors
                      << " occupancy=" << occupancy << '/' << kRingBytes << "\n";
            last_print = after_packet;
        }
    }

    const double elapsed = started ?
        std::chrono::duration<double>(clock::now() - started_at).count() : 0.0;
    const double rate = elapsed > 0 ? double(payload_bytes) * 8.0 / elapsed / 1e6 : 0.0;
    const bool passed = packets > 0 && missing == 0 && duplicates == 0 &&
        out_of_order == 0 && malformed == 0 && metadata_errors == 0 &&
        data_error_packets == 0 && data_error_bytes == 0;

    std::ofstream json(options.output, std::ios::binary);
    json << std::boolalpha << "{\n"
         << "  \"passed\": " << passed << ",\n"
         << "  \"monitor_version\": " << kMonitorVersion << ",\n"
         << "  \"duration_seconds\": " << std::setprecision(12) << elapsed << ",\n"
         << "  \"packets_received\": " << packets << ",\n"
         << "  \"payload_bytes\": " << payload_bytes << ",\n"
         << "  \"payload_rate_mbps\": " << rate << ",\n"
         << "  \"missing_packets\": " << missing << ",\n"
         << "  \"duplicates\": " << duplicates << ",\n"
         << "  \"out_of_order\": " << out_of_order << ",\n"
         << "  \"malformed\": " << malformed << ",\n"
         << "  \"metadata_errors\": " << metadata_errors << ",\n"
         << "  \"data_error_packets\": " << data_error_packets << ",\n"
         << "  \"data_error_bytes\": " << data_error_bytes << ",\n"
         << "  \"max_reported_occupancy_bytes\": " << max_occupancy << ",\n"
         << "  \"last_committed_bytes_low\": " << last_committed << ",\n"
         << "  \"socket_receive_buffer_requested_bytes\": " << requested_buffer << ",\n"
         << "  \"socket_receive_buffer_actual_bytes\": " << actual_buffer << "\n}\n";
    json.close();

    std::cout << std::fixed << std::setprecision(3)
              << "FINAL: time=" << elapsed << "s packets=" << packets
              << " rate=" << rate << " Mb/s missing=" << missing
              << " duplicate=" << duplicates << " out_of_order=" << out_of_order
              << " malformed=" << malformed << " metadata_errors=" << metadata_errors
              << " data_error_packets=" << data_error_packets
              << " data_error_bytes=" << data_error_bytes
              << " payload_bytes=" << payload_bytes
              << " max_occupancy=" << max_occupancy << "\n";
    std::cout << "JSON result written to " << options.output << "\n";
    std::cout << "Press FPGA RESET now to stop/rearm the continuous source.\n";
    std::cout << (passed ? "V5 DDR3 RING-BUFFER STREAM TEST PASSED\n"
                        : "V5 DDR3 RING-BUFFER STREAM TEST FAILED\n");
    closesocket(sock);
    WSACleanup();
    return passed ? 0 : 2;
}
