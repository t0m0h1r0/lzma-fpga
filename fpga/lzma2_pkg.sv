/*
 * LZMA2 FPGA Implementation
 * Main Package Definitions
 *
 * Parameters and types optimized for 32KB input size
 */

package lzma2_pkg;
    // System parameters
    parameter INPUT_SIZE      = 32768;  // 32KB fixed input size
    parameter DICT_SIZE      = 16384;   // 16KB dictionary (optimized for 32KB input)
    parameter PIPE_STAGES    = 8;       // Pipeline stages
    parameter PARALLEL_UNITS = 8;       // Parallel processing units
    parameter CRC_POLY      = 32'h04C11DB7;  // CRC-32 polynomial
    
    // Timing parameters
    parameter TIMEOUT_CYCLES = 100000;  // Timeout counter limit
    parameter STALL_LIMIT   = 1000;     // Maximum allowable stall cycles
    
    // Performance monitoring parameters
    parameter PERF_COUNTER_WIDTH = 32;
    parameter PERF_UPDATE_INTERVAL = 1000;  // Cycles between performance updates
    
    // Error and status flags
    parameter ERR_NONE          = 4'h0;  // No error
    parameter ERR_CRC_MISMATCH  = 4'h1;  // CRC verification failed
    parameter ERR_MEMORY_ACCESS = 4'h2;  // Memory access error
    parameter ERR_OVERFLOW      = 4'h3;  // Buffer overflow
    parameter ERR_TIMEOUT       = 4'h4;  // Operation timeout
    parameter ERR_INVALID_STATE = 4'h5;  // Invalid state transition
    parameter ERR_STALL        = 4'h6;  // Pipeline stall exceeded limit

    // Status register bit definitions
    typedef struct packed {
        logic [15:0] reserved;      // Reserved for future use
        logic [3:0]  error_flags;   // Active error flags
        logic [3:0]  warning_flags; // Warning flags
        logic [3:0]  state;         // Current state
        logic [3:0]  status;        // Status flags
    } status_reg_t;

    // Data structures
    typedef struct packed {
        logic [255:0] data;         // 256-bit data chunk
        logic [31:0]  crc;          // CRC value
        logic         valid;         // Data valid flag
        logic         last;          // Last chunk indicator
        logic [3:0]   byte_count;   // Valid bytes in last chunk
    } input_data_t;

    typedef struct packed {
        logic [31:0] total_bytes;      // Total bytes processed
        logic [31:0] compressed_bytes;  // Output bytes generated
        logic [31:0] cycles;           // Processing cycles
        logic [31:0] cache_hits;       // Cache hit counter
        logic [31:0] cache_misses;     // Cache miss counter
        logic [31:0] match_hits;       // Successful matches found
        logic [31:0] literal_count;    // Literal bytes encoded
        logic [31:0] stall_cycles;     // Pipeline stall cycles
        logic [31:0] compression_ratio; // Current compression ratio (fixed point 16.16)
        logic [31:0] pipeline_util;     // Pipeline utilization percentage
    } performance_counters_t;

    // Common interface definition
    interface lzma2_if;
        logic        clk;
        logic        rst_n;
        input_data_t in_data;
        logic        in_valid;
        logic        in_ready;
        logic [255:0] out_data;
        logic         out_valid;
        logic         out_ready;
        
        // Control signals
        logic         start;
        logic         busy;
        status_reg_t  status;
        
        // Performance monitoring
        performance_counters_t perf_counters;
        
        // Debug interface
        logic         debug_enable;
        logic [31:0]  debug_addr;
        logic [31:0]  debug_data;
        logic         debug_valid;
        
        // Modport definitions
        modport master (
            output in_data,
            output in_valid,
            input  in_ready,
            input  out_data,
            input  out_valid,
            output out_ready,
            output start,
            input  busy,
            input  status,
            input  perf_counters,
            output debug_enable,
            output debug_addr,
            input  debug_data,
            input  debug_valid
        );
        
        modport slave (
            input  in_data,
            input  in_valid,
            output in_ready,
            output out_data,
            output out_valid,
            input  out_ready,
            input  start,
            output busy,
            output status,
            output perf_counters,
            input  debug_enable,
            input  debug_addr,
            output debug_data,
            output debug_valid
        );

        // Clocking block for testbench
        clocking cb @(posedge clk);
            default input #1step output #1step;
            output in_data, in_valid, out_ready, start, debug_enable, debug_addr;
            input  in_ready, out_data, out_valid, busy, status, 
                   perf_counters, debug_data, debug_valid;
        endclocking
        
        // Monitor path for verification
        clocking monitor_cb @(posedge clk);
            default input #1step;
            input in_data, in_valid, in_ready, out_data, out_valid, out_ready,
                  start, busy, status, perf_counters;
        endclocking
    endinterface

    // Type definitions for verification
    typedef struct packed {
        logic [31:0] start_time;
        logic [31:0] end_time;
        logic [31:0] input_size;
        logic [31:0] output_size;
        logic [31:0] compression_ratio;
        logic [31:0] throughput;
        logic [3:0]  error_code;
    } compression_stats_t;

endpackage