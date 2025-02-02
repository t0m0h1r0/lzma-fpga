//-----------------------------------------------------------------------------
// Module: System Controller
//-----------------------------------------------------------------------------
module lzma2_system_controller
    import lzma2_pkg::*;
(
    input  logic                clk,
    input  logic                rst_n,
    
    // Control interface
    input  logic                start,
    output logic                busy,
    output logic [3:0]          error,
    
    // Data flow control
    output logic                input_ready,
    input  logic                input_valid,
    output logic                output_ready,
    input  logic                output_valid,
    
    // Status monitoring
    input  performance_counters_t perf_counters,
    output logic [31:0]         status
);
    // State machine definition
    typedef enum logic [3:0] {
        IDLE,
        INIT,
        COMPRESS,
        VERIFY,
        COMPLETE,
        ERROR
    } state_t;

    state_t current_state, next_state;

    // Timeout counter
    logic [31:0] timeout_counter;
    parameter TIMEOUT_LIMIT = 32'd1000000;  // 1M cycles timeout

    // State machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            timeout_counter <= '0;
            busy <= 1'b0;
            error <= ERR_NONE;
        end else begin
            current_state <= next_state;
            
            case (current_state)
                IDLE: begin
                    timeout_counter <= '0;
                    if (start) begin
                        busy <= 1'b1;
                    end
                end
                
                COMPRESS: begin
                    if (timeout_counter < TIMEOUT_LIMIT) begin
                        timeout_counter <= timeout_counter + 1;
                    end else begin
                        error <= ERR_TIMEOUT;
                        next_state <= ERROR;
                    end
                end
                
                COMPLETE: begin
                    busy <= 1'b0;
                end
                
                ERROR: begin
                    busy <= 1'b0;
                end
            endcase
        end
    end

    // Next state logic
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            IDLE: begin
                if (start) next_state = INIT;
            end
            
            INIT: begin
                if (input_valid) next_state = COMPRESS;
            end
            
            COMPRESS: begin
                if (output_valid) next_state = VERIFY;
                else if (error != ERR_NONE) next_state = ERROR;
            end
            
            VERIFY: begin
                if (error != ERR_NONE) next_state = ERROR;
                else next_state = COMPLETE;
            end
            
            COMPLETE, ERROR: begin
                if (!start) next_state = IDLE;
            end
        endcase
    end

    // Status register update
    always_ff @(posedge clk) begin
        status <= {
            16'h0,                  // Reserved
            error,                  // Error flags
            current_state,          // Current state
            8'h0                    // Reserved
        };
    end

endmodule

//-----------------------------------------------------------------------------
// Top Module
//-----------------------------------------------------------------------------
module lzma2_top
    import lzma2_pkg::*;
    import lzma2_memory_pkg::*;
    import lzma2_compression_pkg::*;
(
    input  logic                clk,
    input  logic                rst_n,
    
    // External interface
    input  logic [255:0]        data_in,
    input  logic                data_valid,
    output logic                ready,
    
    output logic [255:0]        data_out,
    output logic                data_valid_out,
    input  logic                output_ready,
    
    // Control interface
    input  logic                start,
    output logic                busy,
    output logic [31:0]         status,
    
    // Performance monitoring
    output performance_counters_t perf_counters
);
    // Internal connections
    mem_request_t  mem_request;
    mem_response_t mem_response;
    logic [31:0]   input_crc, output_crc;
    logic          crc_match, check_valid;
    logic [3:0]    error;

    // Memory manager instantiation
    lzma2_memory_manager memory_manager (
        .clk(clk),
        .rst_n(rst_n),
        .request(mem_request),
        .response(mem_response),
        .cache_hits(perf_counters.cache_hits),
        .cache_misses(perf_counters.cache_misses),
        .prefetch_hits()
    );

    // Compression engine instantiation
    lzma2_compression_engine compression_engine (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(data_in),
        .data_valid(data_valid),
        .ready(ready),
        .data_out(data_out),
        .data_valid_out(data_valid_out),
        .output_ready(output_ready),
        .mem_request(mem_request),
        .mem_response(mem_response),
        .match_count(perf_counters.match_hits),
        .literal_count(perf_counters.literal_count),
        .compressed_size(perf_counters.compressed_bytes)
    );

    // CRC generation for input data
    lzma2_crc_generator input_crc_gen (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(data_in[7:0]),
        .data_valid(data_valid),
        .crc_out(input_crc),
        .crc_valid()
    );

    // CRC checking for output data
    lzma2_crc_checker output_crc_check (
        .clk(clk),
        .rst_n(rst_n),
        .crc_in(input_crc),
        .data_in(data_out[7:0]),
        .data_valid(data_valid_out),
        .crc_match(crc_match),
        .check_valid(check_valid)
    );

    // System controller instantiation
    lzma2_system_controller system_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .busy(busy),
        .error(error),
        .input_ready(ready),
        .input_valid(data_valid),
        .output_ready(output_ready),
        .output_valid(data_valid_out),
        .perf_counters(perf_counters),
        .status(status)
    );

    // Performance monitoring instantiation
    lzma2_performance_monitor perf_monitor (
        .clk(clk),
        .rst_n(rst_n),
        .match_count(perf_counters.match_hits),
        .literal_count(perf_counters.literal_count),
        .compressed_size(perf_counters.compressed_bytes),
        .cache_hits(perf_counters.cache_hits),
        .cache_misses(perf_counters.cache_misses),
        .perf_counters(perf_counters)
    );

endmodule