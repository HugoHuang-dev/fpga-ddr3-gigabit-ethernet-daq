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
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <sstream>
#include <string>
#include <vector>

#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "iphlpapi.lib")

namespace {

constexpr uint16_t kPcPort = 6666;
constexpr size_t kHeaderBytes = 32;
constexpr uint32_t kRingBytes = 256 * 1024;
constexpr uint16_t kPrbsSeed = 0xACE1;
constexpr size_t kPrbsWords = 65535;
constexpr int kMonitorVersion = 9;
constexpr ULONG kRioSlots = 16384;
constexpr ULONG kRioSlotBytes = 2048;
constexpr ULONG kRioBatch = 256;
constexpr size_t kRecordedGaps = 128;

struct GapRecord {
    uint32_t expected = 0;
    uint32_t received = 0;
    uint32_t missing = 0;
};

struct SampleIndexRecord {
    uint64_t expected = 0;
    uint64_t received = 0;
};

struct FragmentRecord {
    std::string file;
    double elapsed_seconds = 0.0;
    uint32_t sequence = 0;
    uint64_t first_word_index = 0;
    uint64_t datagram_bytes = 0;
    uint64_t captured_bytes = 0;
    uint32_t crc32 = 0;
};

struct Options {
    std::string fpga_ip = "192.168.1.11";
    std::string pc_ip = "192.168.1.100";
    double duration = 60.0;
    double first_timeout = 20.0;
    int rcvbuf_mb = 64;
    std::string output = "evidence\\v9_full_validation_result.json";
    std::string sample_dir = "samples_v9";
    double sample_interval = 60.0;
    size_t sample_bytes = 1056;
    size_t max_fragments = 16;
    bool self_test = false;
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

uint64_t be64(const uint8_t* p) {
    return (uint64_t(be32(p)) << 32) | uint64_t(be32(p + 4));
}

void put_be16(uint8_t* p, uint16_t value) {
    p[0] = static_cast<uint8_t>(value >> 8);
    p[1] = static_cast<uint8_t>(value);
}

void put_be32(uint8_t* p, uint32_t value) {
    p[0] = static_cast<uint8_t>(value >> 24);
    p[1] = static_cast<uint8_t>(value >> 16);
    p[2] = static_cast<uint8_t>(value >> 8);
    p[3] = static_cast<uint8_t>(value);
}

void put_be64(uint8_t* p, uint64_t value) {
    put_be32(p, static_cast<uint32_t>(value >> 32));
    put_be32(p + 4, static_cast<uint32_t>(value));
}

uint32_t crc32_ieee(const uint8_t* data, size_t size) {
    uint32_t crc = 0xffffffffu;
    for (size_t i = 0; i < size; ++i) {
        crc ^= data[i];
        for (int bit = 0; bit < 8; ++bit)
            crc = (crc >> 1) ^ ((crc & 1) ? 0xedb88320u : 0u);
    }
    return ~crc;
}

std::string json_escape(const std::string& text) {
    std::ostringstream out;
    for (const unsigned char ch : text) {
        switch (ch) {
        case '\\': out << "\\\\"; break;
        case '"': out << "\\\""; break;
        case '\n': out << "\\n"; break;
        case '\r': out << "\\r"; break;
        case '\t': out << "\\t"; break;
        default:
            if (ch < 0x20) {
                out << "\\u" << std::hex << std::setw(4) << std::setfill('0')
                    << unsigned(ch) << std::dec << std::setfill(' ');
            } else {
                out << static_cast<char>(ch);
            }
        }
    }
    return out.str();
}

bool payload_matches(const uint8_t* payload, size_t payload_bytes,
                     uint64_t first_word_index, const std::vector<uint8_t>& period,
                     uint64_t& bad_bytes) {
    const size_t offset = static_cast<size_t>(
        (first_word_index % kPrbsWords) * uint64_t(2));
    const size_t first = std::min(payload_bytes, period.size() - offset);
    bool equal = std::memcmp(payload, period.data() + offset, first) == 0;
    if (first != payload_bytes) {
        equal = equal &&
            std::memcmp(payload + first, period.data(), payload_bytes - first) == 0;
    }
    if (equal) return true;

    for (size_t i = 0; i < payload_bytes; ++i) {
        const uint8_t expected = period[(offset + i) % period.size()];
        if (payload[i] != expected) ++bad_bytes;
    }
    return false;
}

struct Metrics {
    uint64_t packets = 0;
    uint64_t payload_bytes = 0;
    uint64_t words_received = 0;
    uint64_t missing = 0;
    uint64_t duplicates = 0;
    uint64_t out_of_order = 0;
    uint64_t sequence_origin_errors = 0;
    uint64_t gap_events = 0;
    uint32_t max_gap = 0;
    uint64_t malformed = 0;
    uint64_t short_header_errors = 0;
    uint64_t magic_errors = 0;
    uint64_t version_errors = 0;
    uint64_t source_id_errors = 0;
    uint64_t total_length_errors = 0;
    uint64_t payload_length_errors = 0;
    uint64_t header_length_errors = 0;
    uint64_t metadata_errors = 0;
    uint64_t source_mismatches = 0;
    uint64_t sample_index_origin_errors = 0;
    uint64_t sample_index_discontinuities = 0;
    uint64_t sample_words_missing = 0;
    uint64_t sample_index_regressions = 0;
    uint64_t data_error_packets = 0;
    uint64_t data_error_bytes = 0;
    uint64_t xadc_records = 0;
    uint64_t xadc_invalid_records = 0;
    uint64_t xadc_channel_order_errors = 0;
    std::array<uint64_t, 4> xadc_channel_records{};
    std::array<uint16_t, 4> xadc_min_raw{{0xffff, 0xffff, 0xffff, 0xffff}};
    std::array<uint16_t, 4> xadc_max_raw{};
    uint32_t max_occupancy = 0;
    uint32_t last_occupancy = 0;
    uint32_t last_committed = 0;
    uint16_t observed_payload_bytes = 0;
    uint8_t observed_source = 0xff;
    uint32_t first_sequence = 0;
    uint32_t expected_sequence = 0;
    bool sequence_initialized = false;
    uint64_t first_word_index = 0;
    uint64_t last_packet_first_word_index = 0;
    uint64_t next_expected_word_index = 0;
    bool word_index_initialized = false;
    std::vector<GapRecord> gap_records;
    std::vector<SampleIndexRecord> sample_index_records;
};

class FragmentSampler {
public:
    explicit FragmentSampler(const Options& options)
        : directory_(options.sample_dir), interval_(options.sample_interval),
          bytes_(options.sample_bytes), maximum_(options.max_fragments) {}

    bool enabled() const {
        return !directory_.empty() && bytes_ != 0 && maximum_ != 0;
    }

    void consider(const uint8_t* packet, size_t packet_bytes, double elapsed,
                  uint32_t sequence, uint64_t first_word_index) {
        if (!enabled() || records_.size() >= maximum_) return;
        if (!records_.empty() && elapsed + 1e-9 < next_capture_) return;

        std::error_code error;
        std::filesystem::create_directories(directory_, error);
        if (error) {
            ++write_errors_;
            next_capture_ = elapsed + interval_;
            return;
        }

        std::ostringstream name;
        name << "fragment_" << std::setw(3) << std::setfill('0') << records_.size()
             << "_seq_" << std::setw(10) << std::setfill('0') << sequence << ".bin";
        const std::filesystem::path path =
            std::filesystem::path(directory_) / name.str();
        const size_t captured = std::min(bytes_, packet_bytes);
        std::ofstream output(path, std::ios::binary);
        output.write(reinterpret_cast<const char*>(packet),
                     static_cast<std::streamsize>(captured));
        if (!output) {
            ++write_errors_;
            next_capture_ = elapsed + interval_;
            return;
        }
        output.close();

        FragmentRecord record;
        record.file = path.generic_string();
        record.elapsed_seconds = elapsed;
        record.sequence = sequence;
        record.first_word_index = first_word_index;
        record.datagram_bytes = packet_bytes;
        record.captured_bytes = captured;
        record.crc32 = crc32_ieee(packet, captured);
        records_.push_back(record);
        next_capture_ = elapsed + interval_;
    }

    uint64_t write_errors() const { return write_errors_; }
    const std::vector<FragmentRecord>& records() const { return records_; }

private:
    std::string directory_;
    double interval_ = 60.0;
    size_t bytes_ = 0;
    size_t maximum_ = 0;
    double next_capture_ = 0.0;
    uint64_t write_errors_ = 0;
    std::vector<FragmentRecord> records_;
};

class Validator {
public:
    Validator(const std::vector<uint8_t>& period, FragmentSampler* sampler = nullptr)
        : period_(period), sampler_(sampler) {
        metrics_.gap_records.reserve(kRecordedGaps);
        metrics_.sample_index_records.reserve(kRecordedGaps);
    }

    void process(const uint8_t* buffer, size_t length, double elapsed_seconds) {
        if (length < kHeaderBytes) {
            ++metrics_.short_header_errors;
            ++metrics_.malformed;
            return;
        }

        const uint8_t source_id = buffer[5];
        const uint16_t total_size = be16(&buffer[6]);
        const uint16_t payload_size = be16(&buffer[12]);
        const uint16_t header_size = be16(&buffer[14]);
        bool malformed = false;
        if (std::memcmp(buffer, "P2V9", 4) != 0) {
            ++metrics_.magic_errors;
            malformed = true;
        }
        if (buffer[4] != kMonitorVersion) {
            ++metrics_.version_errors;
            malformed = true;
        }
        if (source_id > 1) {
            ++metrics_.source_id_errors;
            malformed = true;
        }
        if (total_size != length) {
            ++metrics_.total_length_errors;
            malformed = true;
        }
        const bool payload_size_valid = payload_size == 256 || payload_size == 512 ||
                                        payload_size == 1024;
        if (!payload_size_valid || length != kHeaderBytes + payload_size) {
            ++metrics_.payload_length_errors;
            malformed = true;
        }
        if (header_size != kHeaderBytes) {
            ++metrics_.header_length_errors;
            malformed = true;
        }
        if (malformed) {
            ++metrics_.malformed;
            return;
        }

        if (metrics_.observed_payload_bytes == 0)
            metrics_.observed_payload_bytes = payload_size;
        if (payload_size != metrics_.observed_payload_bytes) {
            ++metrics_.metadata_errors;
            return;
        }
        if (metrics_.observed_source == 0xff) metrics_.observed_source = source_id;
        if (source_id != metrics_.observed_source) {
            ++metrics_.source_mismatches;
            ++metrics_.metadata_errors;
            return;
        }

        const uint32_t sequence = be32(&buffer[8]);
        const uint32_t committed = be32(&buffer[16]);
        const uint32_t occupancy = be32(&buffer[20]);
        const uint64_t first_word_index = be64(&buffer[24]);

        // The board-validation flow is deliberately ARMED -> CLEAR -> START.
        // Therefore the first valid datagram must begin at both origins, and
        // every later packet/sample transition is checked strictly as well.
        if (!metrics_.sequence_initialized) {
            metrics_.first_sequence = sequence;
            metrics_.expected_sequence = sequence;
            metrics_.sequence_initialized = true;
            if (sequence != 0) ++metrics_.sequence_origin_errors;
        }
        const uint32_t sequence_delta = sequence - metrics_.expected_sequence;
        if (sequence_delta == 0) {
        } else if (sequence_delta < 0x80000000u) {
            metrics_.missing += sequence_delta;
            ++metrics_.gap_events;
            metrics_.max_gap = std::max(metrics_.max_gap, sequence_delta);
            if (metrics_.gap_records.size() < kRecordedGaps) {
                metrics_.gap_records.push_back(
                    {metrics_.expected_sequence, sequence, sequence_delta});
            }
        } else if (sequence == metrics_.expected_sequence - 1u) {
            ++metrics_.duplicates;
            return;
        } else {
            ++metrics_.out_of_order;
            return;
        }
        metrics_.expected_sequence = sequence + 1u;

        const uint64_t payload_words = payload_size / 2;
        if (!metrics_.word_index_initialized) {
            metrics_.first_word_index = first_word_index;
            metrics_.next_expected_word_index = first_word_index;
            metrics_.word_index_initialized = true;
            if (first_word_index != 0) ++metrics_.sample_index_origin_errors;
        }
        if (first_word_index != metrics_.next_expected_word_index) {
            ++metrics_.sample_index_discontinuities;
            if (first_word_index > metrics_.next_expected_word_index) {
                metrics_.sample_words_missing +=
                    first_word_index - metrics_.next_expected_word_index;
            } else {
                ++metrics_.sample_index_regressions;
            }
            if (metrics_.sample_index_records.size() < kRecordedGaps) {
                metrics_.sample_index_records.push_back(
                    {metrics_.next_expected_word_index, first_word_index});
            }
        }
        metrics_.last_packet_first_word_index = first_word_index;
        metrics_.next_expected_word_index = first_word_index + payload_words;

        uint64_t packet_bad_bytes = 0;
        if (source_id == 0) {
            if (!payload_matches(buffer + kHeaderBytes, payload_size,
                                 first_word_index, period_, packet_bad_bytes)) {
                ++metrics_.data_error_packets;
                metrics_.data_error_bytes += packet_bad_bytes;
            }
        } else {
            bool packet_has_xadc_error = false;
            for (size_t i = 0; i < payload_size; i += 2) {
                const uint16_t record = static_cast<uint16_t>(
                    buffer[kHeaderBytes + i] |
                    (uint16_t(buffer[kHeaderBytes + i + 1]) << 8));
                const uint8_t channel = static_cast<uint8_t>((record >> 14) & 3);
                const uint16_t raw = record & 0x0fff;
                const uint8_t expected_channel = static_cast<uint8_t>(
                    (first_word_index + (i / 2)) & 3u);
                if ((record & 0x3000) != 0) {
                    ++metrics_.xadc_invalid_records;
                    packet_has_xadc_error = true;
                }
                if (channel != expected_channel) {
                    ++metrics_.xadc_channel_order_errors;
                    packet_has_xadc_error = true;
                }
                ++metrics_.xadc_records;
                ++metrics_.xadc_channel_records[channel];
                metrics_.xadc_min_raw[channel] =
                    std::min(metrics_.xadc_min_raw[channel], raw);
                metrics_.xadc_max_raw[channel] =
                    std::max(metrics_.xadc_max_raw[channel], raw);
            }
            if (packet_has_xadc_error) ++metrics_.data_error_packets;
        }

        if ((committed % 1024) != 0 || (occupancy % 1024) != 0 ||
            occupancy > kRingBytes) {
            ++metrics_.metadata_errors;
        }
        metrics_.last_committed = committed;
        metrics_.last_occupancy = occupancy;
        metrics_.max_occupancy = std::max(metrics_.max_occupancy, occupancy);
        ++metrics_.packets;
        metrics_.payload_bytes += payload_size;
        metrics_.words_received += payload_words;

        if (sampler_ != nullptr) {
            sampler_->consider(buffer, length, elapsed_seconds, sequence,
                               first_word_index);
        }
    }

    bool passed(uint64_t receive_errors = 0, bool receive_failed = false,
                uint64_t sample_write_errors = 0) const {
        const Metrics& m = metrics_;
        return m.packets > 0 && m.missing == 0 && m.duplicates == 0 &&
            m.out_of_order == 0 && m.sequence_origin_errors == 0 &&
            m.malformed == 0 && m.metadata_errors == 0 &&
            m.source_mismatches == 0 && m.sample_index_origin_errors == 0 &&
            m.sample_index_discontinuities == 0 &&
            m.data_error_packets == 0 && m.data_error_bytes == 0 &&
            m.xadc_invalid_records == 0 && m.xadc_channel_order_errors == 0 &&
            receive_errors == 0 && sample_write_errors == 0 && !receive_failed;
    }

    const Metrics& metrics() const { return metrics_; }

private:
    const std::vector<uint8_t>& period_;
    FragmentSampler* sampler_ = nullptr;
    Metrics metrics_;
};

struct ThroughputStats {
    double minimum = std::numeric_limits<double>::infinity();
    double maximum = 0.0;
    uint64_t windows = 0;

    void observe(double mbps) {
        minimum = std::min(minimum, mbps);
        maximum = std::max(maximum, mbps);
        ++windows;
    }

    double minimum_or_zero() const { return windows == 0 ? 0.0 : minimum; }
};

bool ping_fpga(const std::string& ip) {
    in_addr parsed_address{};
    if (inet_pton(AF_INET, ip.c_str(), &parsed_address) != 1) return false;
    const IPAddr address = parsed_address.S_un.S_addr;
    HANDLE handle = IcmpCreateFile();
    if (handle == INVALID_HANDLE_VALUE) return false;
    const char request[] = "P2V9";
    std::vector<uint8_t> reply(sizeof(ICMP_ECHO_REPLY) + sizeof(request) + 32);
    const DWORD count = IcmpSendEcho(
        handle, address, const_cast<char*>(request), static_cast<WORD>(sizeof(request)),
        nullptr, reply.data(), static_cast<DWORD>(reply.size()), 1000);
    IcmpCloseHandle(handle);
    return count != 0;
}

bool parse_size(const std::string& text, size_t& value) {
    try {
        size_t used = 0;
        const unsigned long long parsed = std::stoull(text, &used, 0);
        if (used != text.size() || parsed > std::numeric_limits<size_t>::max())
            return false;
        value = static_cast<size_t>(parsed);
        return true;
    } catch (...) {
        return false;
    }
}

bool parse_args(int argc, char** argv, Options& options) {
    for (int i = 1; i < argc; ++i) {
        const std::string key = argv[i];
        if (key == "--self-test") {
            options.self_test = true;
            continue;
        }
        if (i + 1 >= argc) return false;
        const std::string value = argv[++i];
        try {
            if (key == "--fpga-ip") options.fpga_ip = value;
            else if (key == "--pc-ip") options.pc_ip = value;
            else if (key == "--duration") options.duration = std::stod(value);
            else if (key == "--first-timeout") options.first_timeout = std::stod(value);
            else if (key == "--rcvbuf-mb") options.rcvbuf_mb = std::stoi(value);
            else if (key == "--output") options.output = value;
            else if (key == "--sample-dir") {
                options.sample_dir = (value == "none" || value == "-") ? "" : value;
            } else if (key == "--sample-interval") {
                options.sample_interval = std::stod(value);
            } else if (key == "--sample-bytes") {
                if (!parse_size(value, options.sample_bytes)) return false;
            } else if (key == "--max-fragments") {
                if (!parse_size(value, options.max_fragments)) return false;
            } else {
                return false;
            }
        } catch (...) {
            return false;
        }
    }
    return options.duration > 0 && options.first_timeout > 0 &&
        options.rcvbuf_mb > 0 && options.sample_interval > 0 &&
        options.sample_bytes > 0 && options.sample_bytes <= kRioSlotBytes;
}

std::vector<uint8_t> make_test_packet(
    uint8_t source, uint32_t sequence, uint64_t first_word_index,
    uint16_t payload_bytes, const std::vector<uint8_t>& period) {
    std::vector<uint8_t> packet(kHeaderBytes + payload_bytes, 0);
    std::memcpy(packet.data(), "P2V9", 4);
    packet[4] = 9;
    packet[5] = source;
    put_be16(&packet[6], static_cast<uint16_t>(packet.size()));
    put_be32(&packet[8], sequence);
    put_be16(&packet[12], payload_bytes);
    put_be16(&packet[14], static_cast<uint16_t>(kHeaderBytes));
    put_be32(&packet[16], 1024);
    put_be32(&packet[20], 1024);
    put_be64(&packet[24], first_word_index);

    if (source == 0) {
        const size_t offset = static_cast<size_t>(
            (first_word_index % kPrbsWords) * uint64_t(2));
        for (size_t i = 0; i < payload_bytes; ++i)
            packet[kHeaderBytes + i] = period[(offset + i) % period.size()];
    } else {
        for (size_t i = 0; i < payload_bytes / 2; ++i) {
            const uint8_t channel = static_cast<uint8_t>((first_word_index + i) & 3u);
            const uint16_t raw = static_cast<uint16_t>(0x500 + channel + (i & 0x0f));
            const uint16_t record = static_cast<uint16_t>((uint16_t(channel) << 14) | raw);
            packet[kHeaderBytes + i * 2] = static_cast<uint8_t>(record);
            packet[kHeaderBytes + i * 2 + 1] = static_cast<uint8_t>(record >> 8);
        }
    }
    return packet;
}

bool self_test_case(const std::string& name, bool condition) {
    std::cout << "SELF-TEST " << std::left << std::setw(34) << name
              << (condition ? "PASS" : "FAIL") << "\n";
    return condition;
}

int run_self_test(const std::vector<uint8_t>& period) {
    bool all_passed = true;

    {
        Validator validator(period);
        for (uint32_t i = 0; i < 4; ++i) {
            const auto packet = make_test_packet(0, i, uint64_t(i) * 128,
                                                 256, period);
            validator.process(packet.data(), packet.size(), i * 0.001);
        }
        all_passed &= self_test_case(
            "normal source0 stream",
            validator.passed() && validator.metrics().packets == 4 &&
                validator.metrics().words_received == 512);
    }

    {
        Validator validator(period);
        for (uint32_t i = 0; i < 2; ++i) {
            const auto packet = make_test_packet(1, i, uint64_t(i) * 128,
                                                 256, period);
            validator.process(packet.data(), packet.size(), i * 0.001);
        }
        const Metrics& metrics = validator.metrics();
        all_passed &= self_test_case(
            "normal source1/XADC stream",
            validator.passed() && metrics.xadc_records == 256 &&
                metrics.xadc_channel_order_errors == 0 &&
                metrics.xadc_invalid_records == 0);
    }

    {
        Validator validator(period);
        auto first = make_test_packet(0, 0, 0, 256, period);
        auto second = make_test_packet(0, 2, 128, 256, period);
        validator.process(first.data(), first.size(), 0.0);
        validator.process(second.data(), second.size(), 0.1);
        all_passed &= self_test_case(
            "packet-sequence gap injection",
            !validator.passed() && validator.metrics().missing == 1 &&
                validator.metrics().gap_events == 1);
    }

    {
        Validator validator(period);
        auto first = make_test_packet(0, 0, 0, 256, period);
        auto second = make_test_packet(0, 1, 129, 256, period);
        validator.process(first.data(), first.size(), 0.0);
        validator.process(second.data(), second.size(), 0.1);
        all_passed &= self_test_case(
            "sample-index gap injection",
            !validator.passed() &&
                validator.metrics().sample_index_discontinuities == 1 &&
                validator.metrics().sample_words_missing == 1);
    }

    {
        Validator validator(period);
        auto packet = make_test_packet(0, 0, 0, 256, period);
        packet[kHeaderBytes + 37] ^= 0x80;
        validator.process(packet.data(), packet.size(), 0.0);
        all_passed &= self_test_case(
            "payload-byte corruption injection",
            !validator.passed() && validator.metrics().data_error_packets == 1 &&
                validator.metrics().data_error_bytes == 1);
    }

    {
        Validator validator(period);
        auto packet = make_test_packet(0, 0, 0, 256, period);
        packet[4] = 8;
        validator.process(packet.data(), packet.size(), 0.0);
        all_passed &= self_test_case(
            "header-version injection",
            !validator.passed() && validator.metrics().malformed == 1 &&
                validator.metrics().version_errors == 1);
    }

    {
        Validator validator(period);
        auto packet = make_test_packet(0, 0, 0, 256, period);
        put_be16(&packet[14], 24);
        validator.process(packet.data(), packet.size(), 0.0);
        all_passed &= self_test_case(
            "header-length injection",
            !validator.passed() && validator.metrics().malformed == 1 &&
                validator.metrics().header_length_errors == 1);
    }

    {
        Validator validator(period);
        auto packet = make_test_packet(1, 0, 0, 256, period);
        packet[kHeaderBytes + 1] ^= 0x50; // reserved bit plus wrong channel
        validator.process(packet.data(), packet.size(), 0.0);
        const Metrics& metrics = validator.metrics();
        all_passed &= self_test_case(
            "XADC format/order injection",
            !validator.passed() && metrics.xadc_invalid_records >= 1 &&
                metrics.xadc_channel_order_errors >= 1);
    }

    {
        Validator validator(period);
        auto packet = make_test_packet(0, 7, 0, 256, period);
        validator.process(packet.data(), packet.size(), 0.0);
        all_passed &= self_test_case(
            "nonzero first-sequence origin",
            !validator.passed() && validator.metrics().sequence_origin_errors == 1 &&
                validator.metrics().sample_index_origin_errors == 0);
    }

    {
        Validator validator(period);
        auto packet = make_test_packet(0, 0, 23, 256, period);
        validator.process(packet.data(), packet.size(), 0.0);
        all_passed &= self_test_case(
            "nonzero first-sample origin",
            !validator.passed() && validator.metrics().sequence_origin_errors == 0 &&
                validator.metrics().sample_index_origin_errors == 1);
    }

    std::cout << (all_passed ? "V9 MONITOR SELF-TEST PASSED\n"
                            : "V9 MONITOR SELF-TEST FAILED\n");
    return all_passed ? 0 : 2;
}

bool prepare_output_parent(const std::string& file) {
    const std::filesystem::path path(file);
    if (!path.has_parent_path()) return true;
    std::error_code error;
    std::filesystem::create_directories(path.parent_path(), error);
    return !error;
}

void write_json(const Options& options, const Metrics& metrics,
                const FragmentSampler& sampler, double elapsed,
                const ThroughputStats& throughput, uint64_t receive_errors,
                bool receive_failed, int requested_buffer, int actual_buffer,
                bool process_priority_ok, bool thread_priority_ok,
                bool passed) {
    if (!prepare_output_parent(options.output)) {
        std::cerr << "FAIL: cannot create JSON output directory\n";
        return;
    }
    std::ofstream json(options.output, std::ios::binary);
    if (!json) {
        std::cerr << "FAIL: cannot open JSON output " << options.output << "\n";
        return;
    }
    const double average_rate = elapsed > 0
        ? double(metrics.payload_bytes) * 8.0 / elapsed / 1e6 : 0.0;

    json << std::boolalpha << "{\n"
         << "  \"passed\": " << passed << ",\n"
         << "  \"monitor_version\": " << kMonitorVersion << ",\n"
         << "  \"protocol\": \"P2V9\",\n"
         << "  \"header_bytes\": " << kHeaderBytes << ",\n"
         << "  \"receive_engine\": \"windows_rio\",\n"
         << "  \"duration_seconds\": " << std::setprecision(12) << elapsed << ",\n"
         << "  \"packets_received\": " << metrics.packets << ",\n"
         << "  \"payload_bytes\": " << metrics.payload_bytes << ",\n"
         << "  \"words_received\": " << metrics.words_received << ",\n"
         << "  \"udp_payload_bytes\": " << metrics.observed_payload_bytes << ",\n"
         << "  \"source_id\": " << unsigned(metrics.observed_source) << ",\n"
         << "  \"source_name\": \""
         << (metrics.observed_source == 0 ? "deterministic_prbs16" :
             metrics.observed_source == 1 ? "internal_xadc" : "unknown") << "\",\n"
         << "  \"throughput_mbps\": {\"average\":" << average_rate
         << ",\"minimum_1s\":" << throughput.minimum_or_zero()
         << ",\"maximum_1s\":" << throughput.maximum
         << ",\"windows\":" << throughput.windows
         << ",\"basis\":\"udp_payload_only\"},\n"
         << "  \"first_sequence\": " << metrics.first_sequence << ",\n"
         << "  \"first_word_index\": " << metrics.first_word_index << ",\n"
         << "  \"last_packet_first_word_index\": "
         << metrics.last_packet_first_word_index << ",\n"
         << "  \"next_expected_word_index\": "
         << metrics.next_expected_word_index << ",\n"
         << "  \"errors\": {\n"
         << "    \"missing_packets\": " << metrics.missing << ",\n"
         << "    \"gap_events\": " << metrics.gap_events << ",\n"
         << "    \"max_gap_packets\": " << metrics.max_gap << ",\n"
         << "    \"duplicates\": " << metrics.duplicates << ",\n"
         << "    \"out_of_order\": " << metrics.out_of_order << ",\n"
         << "    \"sequence_origin_errors\": "
         << metrics.sequence_origin_errors << ",\n"
         << "    \"sample_index_origin_errors\": "
         << metrics.sample_index_origin_errors << ",\n"
         << "    \"sample_index_discontinuities\": "
         << metrics.sample_index_discontinuities << ",\n"
         << "    \"sample_words_missing\": " << metrics.sample_words_missing << ",\n"
         << "    \"sample_index_regressions\": "
         << metrics.sample_index_regressions << ",\n"
         << "    \"malformed_packets\": " << metrics.malformed << ",\n"
         << "    \"short_header\": " << metrics.short_header_errors << ",\n"
         << "    \"bad_magic\": " << metrics.magic_errors << ",\n"
         << "    \"bad_version\": " << metrics.version_errors << ",\n"
         << "    \"bad_source_id\": " << metrics.source_id_errors << ",\n"
         << "    \"bad_total_length\": " << metrics.total_length_errors << ",\n"
         << "    \"bad_payload_length\": " << metrics.payload_length_errors << ",\n"
         << "    \"bad_header_length\": " << metrics.header_length_errors << ",\n"
         << "    \"metadata_errors\": " << metrics.metadata_errors << ",\n"
         << "    \"source_mismatches\": " << metrics.source_mismatches << ",\n"
         << "    \"data_error_packets\": " << metrics.data_error_packets << ",\n"
         << "    \"data_error_bytes\": " << metrics.data_error_bytes << ",\n"
         << "    \"xadc_invalid_records\": " << metrics.xadc_invalid_records << ",\n"
         << "    \"xadc_channel_order_errors\": "
         << metrics.xadc_channel_order_errors << ",\n"
         << "    \"receive_completion_errors\": " << receive_errors << ",\n"
         << "    \"sample_write_errors\": " << sampler.write_errors() << ",\n"
         << "    \"receive_failed\": " << receive_failed << "\n"
         << "  },\n"
         << "  \"gap_records_truncated\": "
         << (metrics.gap_events > metrics.gap_records.size()) << ",\n"
         << "  \"gap_records\": [";
    for (size_t i = 0; i < metrics.gap_records.size(); ++i) {
        if (i != 0) json << ',';
        json << "{\"expected\":" << metrics.gap_records[i].expected
             << ",\"received\":" << metrics.gap_records[i].received
             << ",\"missing\":" << metrics.gap_records[i].missing << '}';
    }
    json << "],\n"
         << "  \"sample_index_records_truncated\": "
         << (metrics.sample_index_discontinuities > metrics.sample_index_records.size())
         << ",\n"
         << "  \"sample_index_records\": [";
    for (size_t i = 0; i < metrics.sample_index_records.size(); ++i) {
        if (i != 0) json << ',';
        json << "{\"expected\":" << metrics.sample_index_records[i].expected
             << ",\"received\":" << metrics.sample_index_records[i].received << '}';
    }
    json << "],\n"
         << "  \"xadc\": {\"records\":" << metrics.xadc_records
         << ",\"records_by_channel\":[" << metrics.xadc_channel_records[0] << ','
         << metrics.xadc_channel_records[1] << ',' << metrics.xadc_channel_records[2]
         << ',' << metrics.xadc_channel_records[3] << "],\"raw_min\":["
         << (metrics.xadc_min_raw[0] == 0xffff ? 0 : metrics.xadc_min_raw[0]) << ','
         << (metrics.xadc_min_raw[1] == 0xffff ? 0 : metrics.xadc_min_raw[1]) << ','
         << (metrics.xadc_min_raw[2] == 0xffff ? 0 : metrics.xadc_min_raw[2]) << ','
         << (metrics.xadc_min_raw[3] == 0xffff ? 0 : metrics.xadc_min_raw[3]) << "],"
         << "\"raw_max\":[" << metrics.xadc_max_raw[0] << ','
         << metrics.xadc_max_raw[1] << ',' << metrics.xadc_max_raw[2] << ','
         << metrics.xadc_max_raw[3] << "]},\n"
         << "  \"ring\": {\"max_reported_occupancy_bytes\":"
         << metrics.max_occupancy << ",\"last_reported_occupancy_bytes\":"
         << metrics.last_occupancy << ",\"last_committed_bytes_low\":"
         << metrics.last_committed << "},\n"
         << "  \"sampling\": {\"enabled\":" << sampler.enabled()
         << ",\"interval_seconds\":" << options.sample_interval
         << ",\"bytes_per_fragment_limit\":" << options.sample_bytes
         << ",\"max_fragments\":" << options.max_fragments
         << ",\"fragments_written\":" << sampler.records().size()
         << ",\"manifest\":[";
    for (size_t i = 0; i < sampler.records().size(); ++i) {
        if (i != 0) json << ',';
        const FragmentRecord& fragment = sampler.records()[i];
        std::ostringstream crc;
        crc << std::hex << std::uppercase << std::setw(8) << std::setfill('0')
            << fragment.crc32;
        json << "{\"file\":\"" << json_escape(fragment.file)
             << "\",\"elapsed_seconds\":" << fragment.elapsed_seconds
             << ",\"sequence\":" << fragment.sequence
             << ",\"first_word_index\":" << fragment.first_word_index
             << ",\"datagram_bytes\":" << fragment.datagram_bytes
             << ",\"captured_bytes\":" << fragment.captured_bytes
             << ",\"crc32\":\"" << crc.str() << "\"}";
    }
    json << "]},\n"
         << "  \"receiver\": {\"socket_receive_buffer_requested_bytes\":"
         << requested_buffer << ",\"socket_receive_buffer_actual_bytes\":"
         << actual_buffer << ",\"rio_slots\":" << kRioSlots
         << ",\"rio_completion_batch\":" << kRioBatch
         << ",\"process_priority_high\":" << process_priority_ok
         << ",\"thread_priority_highest\":" << thread_priority_ok << "}\n"
         << "}\n";
}

} // namespace

int main(int argc, char** argv) {
    Options options;
    if (!parse_args(argc, argv, options)) {
        std::cerr
            << "Usage: udp_v9_monitor_rio.exe [--fpga-ip IP] [--pc-ip IP] "
               "[--duration SEC] [--first-timeout SEC] [--rcvbuf-mb MB] "
               "[--output FILE] [--sample-dir DIR|none] "
               "[--sample-interval SEC] [--sample-bytes N] "
               "[--max-fragments N] [--self-test]\n";
        return 64;
    }

    std::cout << "Preparing direct-index PRBS reference table ...\n";
    const auto period = build_prbs_period();
    if (options.self_test) return run_self_test(period);

    const bool process_priority_ok =
        SetPriorityClass(GetCurrentProcess(), HIGH_PRIORITY_CLASS) != 0;
    const bool thread_priority_ok =
        SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_HIGHEST) != 0;
    std::cout << "Project2 v9 Windows RIO PC monitor v" << kMonitorVersion << "\n";
    std::cout << "Receive priority: process="
              << (process_priority_ok ? "high" : "unchanged")
              << " thread=" << (thread_priority_ok ? "highest" : "unchanged") << "\n";

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
    if (sock == INVALID_SOCKET) {
        WSACleanup();
        return 1;
    }
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
        closesocket(sock);
        WSACleanup();
        return 1;
    }
    std::cout << "ARMED: listening on " << options.pc_ip << ':' << kPcPort << "\n";
    std::cout << "Protocol: P2V9 fixed 32-byte header, explicit 64-bit word index\n";
    std::cout << "Socket receive buffer: requested=" << requested_buffer
              << " bytes actual=" << actual_buffer << " bytes\n";
    std::cout << "Receive engine: Windows Registered I/O, slots=" << kRioSlots
              << " batch=" << kRioBatch << "\n";
    std::cout << "Bounded sampling: "
              << (options.sample_dir.empty() || options.max_fragments == 0
                      ? "disabled" : options.sample_dir)
              << " interval=" << options.sample_interval
              << "s bytes=" << options.sample_bytes
              << " max=" << options.max_fragments << "\n";
    std::cout << "Send CLEAR_COUNTERS then START over UART after this monitor is armed.\n";

    GUID rio_table_id = WSAID_MULTIPLE_RIO;
    RIO_EXTENSION_FUNCTION_TABLE rio{};
    DWORD rio_bytes = 0;
    if (WSAIoctl(sock, SIO_GET_MULTIPLE_EXTENSION_FUNCTION_POINTER,
                 &rio_table_id, sizeof(rio_table_id), &rio, sizeof(rio),
                 &rio_bytes, nullptr, nullptr) == SOCKET_ERROR) {
        std::cerr << "FAIL: RIO extension table unavailable, WSA="
                  << WSAGetLastError() << "\n";
        closesocket(sock);
        WSACleanup();
        return 1;
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
        if (completion_queue != RIO_INVALID_CQ)
            rio.RIOCloseCompletionQueue(completion_queue);
        if (rio_event) CloseHandle(rio_event);
        closesocket(sock);
        WSACleanup();
        return 1;
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
            CloseHandle(rio_event);
            closesocket(sock);
            WSACleanup();
            return 1;
        }
    }

    using clock = std::chrono::steady_clock;
    const auto armed_at = clock::now();
    auto started_at = armed_at;
    auto last_print = armed_at;
    uint64_t last_print_bytes = 0;
    bool started = false;
    bool receive_failed = false;
    uint64_t receive_errors = 0;
    ThroughputStats throughput;
    FragmentSampler sampler(options);
    Validator validator(period, &sampler);
    std::vector<RIORESULT> completions(kRioBatch);

    while (true) {
        const auto now = clock::now();
        const double armed_seconds =
            std::chrono::duration<double>(now - armed_at).count();
        if (!started && armed_seconds >= options.first_timeout) {
            std::cerr << "FAIL: no V9 packet received before first-packet timeout.\n";
            break;
        }
        if (started &&
            std::chrono::duration<double>(now - started_at).count() >= options.duration) {
            break;
        }

        if (rio.RIONotify(completion_queue) == SOCKET_ERROR) {
            std::cerr << "FAIL: RIONotify WSA=" << WSAGetLastError() << "\n";
            receive_failed = true;
            break;
        }
        const DWORD wait_result = WaitForSingleObject(rio_event, 100);
        if (wait_result == WAIT_OBJECT_0) {
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
                    const uintptr_t context =
                        static_cast<uintptr_t>(result.RequestContext);
                    if (context == 0 || context > kRioSlots) {
                        ++receive_errors;
                        continue;
                    }
                    const ULONG slot = static_cast<ULONG>(context - 1);
                    if (result.Status == NO_ERROR) {
                        const auto* packet = reinterpret_cast<const uint8_t*>(
                            rio_storage.data() + size_t(slot) * kRioSlotBytes);
                        if (!started) {
                            started = true;
                            started_at = clock::now();
                            last_print = started_at;
                        }
                        const double elapsed =
                            std::chrono::duration<double>(clock::now() - started_at).count();
                        validator.process(packet, result.BytesTransferred, elapsed);
                    } else {
                        ++receive_errors;
                    }
                    if (!post_receive(slot)) {
                        std::cerr << "FAIL: RIOReceive repost WSA="
                                  << WSAGetLastError() << "\n";
                        receive_failed = true;
                        break;
                    }
                }
                if (receive_failed) break;
            }
        } else if (wait_result != WAIT_TIMEOUT) {
            std::cerr << "FAIL: RIO completion wait error=" << GetLastError() << "\n";
            receive_failed = true;
            break;
        }
        if (receive_failed) break;

        const auto after_wait = clock::now();
        if (started &&
            std::chrono::duration<double>(after_wait - last_print).count() >= 1.0) {
            const double elapsed =
                std::chrono::duration<double>(after_wait - started_at).count();
            const double window_seconds =
                std::chrono::duration<double>(after_wait - last_print).count();
            const Metrics& metrics = validator.metrics();
            const uint64_t window_bytes = metrics.payload_bytes - last_print_bytes;
            const double instant_rate =
                double(window_bytes) * 8.0 / window_seconds / 1e6;
            const double average_rate =
                double(metrics.payload_bytes) * 8.0 / elapsed / 1e6;
            throughput.observe(instant_rate);
            std::cout << std::fixed << std::setprecision(2)
                      << "STAT: time=" << std::setw(7) << elapsed
                      << "s packets=" << metrics.packets << std::setprecision(3)
                      << " instant=" << instant_rate << " Mb/s avg=" << average_rate
                      << " Mb/s missing=" << metrics.missing
                      << " sample_index_errors="
                      << metrics.sample_index_discontinuities
                      << " data_error_packets=" << metrics.data_error_packets
                      << " malformed=" << metrics.malformed
                      << " occupancy=" << metrics.last_occupancy << '/'
                      << kRingBytes << "\n";
            last_print = after_wait;
            last_print_bytes = metrics.payload_bytes;
        }
    }

    const double elapsed = started
        ? std::chrono::duration<double>(clock::now() - started_at).count() : 0.0;
    const Metrics& metrics = validator.metrics();
    const double average_rate = elapsed > 0
        ? double(metrics.payload_bytes) * 8.0 / elapsed / 1e6 : 0.0;
    const bool passed = validator.passed(
        receive_errors, receive_failed, sampler.write_errors());
    write_json(options, metrics, sampler, elapsed, throughput, receive_errors,
               receive_failed, requested_buffer, actual_buffer,
               process_priority_ok, thread_priority_ok, passed);

    std::cout << std::fixed << std::setprecision(3)
              << "FINAL: time=" << elapsed << "s packets=" << metrics.packets
              << " avg_rate=" << average_rate << " Mb/s min_1s="
              << throughput.minimum_or_zero() << " max_1s=" << throughput.maximum
              << " missing=" << metrics.missing
              << " duplicate=" << metrics.duplicates
              << " out_of_order=" << metrics.out_of_order
              << " sequence_origin_errors=" << metrics.sequence_origin_errors
              << " sample_origin_errors=" << metrics.sample_index_origin_errors
              << " sample_index_errors=" << metrics.sample_index_discontinuities
              << " sample_words_missing=" << metrics.sample_words_missing
              << " malformed=" << metrics.malformed
              << " metadata_errors=" << metrics.metadata_errors
              << " data_error_packets=" << metrics.data_error_packets
              << " data_error_bytes=" << metrics.data_error_bytes
              << " source=" << unsigned(metrics.observed_source)
              << " xadc_records=" << metrics.xadc_records
              << " xadc_order_errors=" << metrics.xadc_channel_order_errors
              << " receive_completion_errors=" << receive_errors
              << " fragments=" << sampler.records().size()
              << " payload_bytes=" << metrics.payload_bytes
              << " max_occupancy=" << metrics.max_occupancy << "\n";
    std::cout << "JSON summary written to " << options.output << "\n";
    std::cout << "Send STOP over UART to stop production and drain complete bursts.\n";
    std::cout << (passed ? "V9 FULL VALIDATION STREAM TEST PASSED\n"
                        : "V9 FULL VALIDATION STREAM TEST FAILED\n");

    rio.RIODeregisterBuffer(rio_buffer_id);
    rio.RIOCloseCompletionQueue(completion_queue);
    CloseHandle(rio_event);
    closesocket(sock);
    WSACleanup();
    return passed ? 0 : 2;
}
