/*
 * LZMA2 FPGA Implementation
 * CRC Generation and Verification Module
 *
 * Optimized for 32KB input with parallel CRC calculation
 * Features:
 * - Parallel CRC calculation for 32-byte chunks
 * - CRC-32 polynomial: 0x04C11DB7
 * - Hardware-optimized implementation
 */

module lzma2_crc
    import lzma2_pkg::*;
(
    input  logic                clk,
    input  logic                rst_n,
    
    // Data input interface
    input  logic [255:0]        data_in,      // 32-byte input
    input  logic                data_valid,
    input  logic                data_last,     // Last chunk indicator
    input  logic [4:0]          last_bytes,    // Valid bytes in last chunk
    
    // CRC output interface
    output logic [31:0]         crc_out,
    output logic                crc_valid,
    
    // Status and control
    input  logic                clear,         // Clear CRC accumulator
    output logic                ready,
    output logic [14:0]         bytes_processed,
    
    // Error detection
    output logic                error,
    output logic [3:0]          error_code
);

    // CRC calculation parameters
    localparam PARALLEL_UNITS = 32;  // Process 32 bytes in parallel
    localparam CRC_WIDTH = 32;       // CRC-32
    
    // Pre-calculated CRC tables for parallel processing
    logic [31:0] crc_table [256];
    logic [31:0] crc_table_parallel [PARALLEL_UNITS][256];
    
    // Internal registers
    logic [31:0] crc_reg;
    logic [31:0] parallel_crc [PARALLEL_UNITS];
    logic processing;
    logic [4:0] valid_bytes;
    
    // Error codes
    localparam ERR_NONE         = 4'h0;
    localparam ERR_OVERFLOW     = 4'h1;
    localparam ERR_INVALID_SIZE = 4'h2;
    
    // Initialize CRC tables
    function automatic logic [31:0] calculate_crc_table_entry;
        input logic [7:0] index;
        logic [31:0] crc;
        begin
            crc = {index, 24'b0};
            for (int i = 0; i < 8; i++) begin
                if (crc[31])
                    crc = (crc << 1) ^ CRC_POLY;
                else
                    crc = crc << 1;
            end
            return crc;
        end
    endfunction
    
    // Initialize parallel CRC tables
    function automatic logic [31:0] calculate_parallel_table_entry;
        input int unit_index;
        input logic [7:0] byte_value;
        logic [31:0] crc;
        begin
            crc = calculate_crc_table_entry(byte_value);
            for (int i = 0; i < unit_index; i++) begin
                crc = (crc << 8) ^ crc_table[crc[31:24]];
            end
            return crc;
        end
    endfunction
    
    // Initialize tables
    initial begin
        // Generate basic CRC table
        for (int i = 0; i < 256; i++) begin
            crc_table[i] = calculate_crc_table_entry(i);
        end
        
        // Generate parallel CRC tables
        for (int unit = 0; unit < PARALLEL_UNITS; unit++) begin
            for (int value = 0; value < 256; value++) begin
                crc_table_parallel[unit][value] = calculate_parallel_table_entry(unit, value);
            end
        end
    end
    
    // Parallel CRC calculation
    function automatic logic [31:0] parallel_crc_calc;
        input logic [255:0] data;
        input logic [31:0] crc_in;
        input logic [4:0] valid_bytes;
        logic [31:0] result;
        begin
            result = crc_in;
            for (int i = 0; i < PARALLEL_UNITS; i++) begin
                if (i < valid_bytes) begin
                    result = (result << 8) ^ 
                            crc_table_parallel[i][data[i*8 +: 8] ^ result[31:24]];
                end
            end
            return result;
        end
    endfunction
    
    // Main CRC calculation process
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_reg <= 32'hFFFFFFFF;
            crc_valid <= 1'b0;
            processing <= 1'b0;
            ready <= 1'b1;
            bytes_processed <= '0;
            error <= 1'b0;
            error_code <= ERR_NONE;
        end else begin
            if (clear) begin
                crc_reg <= 32'hFFFFFFFF;
                crc_valid <= 1'b0;
                bytes_processed <= '0;
                error <= 1'b0;
                error_code <= ERR_NONE;
                ready <= 1'b1;
            end else if (data_valid && ready) begin
                processing <= 1'b1;
                ready <= 1'b0;
                
                // Determine number of valid bytes
                valid_bytes = data_last ? last_bytes : PARALLEL_UNITS;
                
                // Check for potential errors
                if (bytes_processed + valid_bytes > INPUT_SIZE) begin
                    error <= 1'b1;
                    error_code <= ERR_OVERFLOW;
                end else if (data_last && bytes_processed + valid_bytes != INPUT_SIZE) begin
                    error <= 1'b1;
                    error_code <= ERR_INVALID_SIZE;
                end else begin
                    // Calculate CRC for current chunk
                    crc_reg <= parallel_crc_calc(data_in, crc_reg, valid_bytes);
                    bytes_processed <= bytes_processed + valid_bytes;
                    
                    // Set output valid on last chunk
                    if (data_last) begin
                        crc_valid <= 1'b1;
                        crc_out <= ~parallel_crc_calc(data_in, crc_reg, valid_bytes);
                    end
                end
                
                processing <= 1'b0;
                ready <= 1'b1;
            end else if (!data_valid) begin
                crc_valid <= 1'b0;
                ready <= 1'b1;
            end
        end
    end
    
    // Performance monitoring
    // synthesis translate_off
    real processing_rate;
    always @(posedge clk) begin
        if (bytes_processed > 0) begin
            processing_rate = real'(bytes_processed) / real'($time);
            if (processing_rate < 0.5) begin  // Less than 0.5 bytes per cycle
                $display("Warning: Low CRC processing rate at time %t", $time);
            end
        end
    end
    // synthesis translate_on

endmodule

/*
 * CRC Verification Module
 */
module lzma2_crc_verifier
    import lzma2_pkg::*;
(
    input  logic                clk,
    input  logic                rst_n,
    
    // Data input
    input  logic [255:0]        data_in,
    input  logic                data_valid,
    input  logic                data_last,
    input  logic [4:0]          last_bytes,
    
    // CRC reference input
    input  logic [31:0]         crc_ref,
    input  logic                crc_ref_valid,
    
    // Status output
    output logic                verification_done,
    output logic                crc_match,
    output logic                error,
    output logic [3:0]          error_code
);

    // Internal CRC calculator
    logic [31:0] calculated_crc;
    logic crc_valid;
    logic [14:0] bytes_processed;
    logic calc_ready;
    logic calc_error;
    logic [3:0] calc_error_code;

    // Instantiate CRC calculator
    lzma2_crc crc_calc (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(data_in),
        .data_valid(data_valid),
        .data_last(data_last),
        .last_bytes(last_bytes),
        .crc_out(calculated_crc),
        .crc_valid(crc_valid),
        .clear(1'b0),
        .ready(calc_ready),
        .bytes_processed(bytes_processed),
        .error(calc_error),
        .error_code(calc_error_code)
    );

    // Verification logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            verification_done <= 1'b0;
            crc_match <= 1'b0;
            error <= 1'b0;
            error_code <= 4'h0;
        end else begin
            if (crc_valid && crc_ref_valid) begin
                verification_done <= 1'b1;
                crc_match <= (calculated_crc == crc_ref);
                
                // Forward any calculation errors
                error <= calc_error;
                error_code <= calc_error_code;
            end else begin
                verification_done <= 1'b0;
            end
        end
    end

endmodule