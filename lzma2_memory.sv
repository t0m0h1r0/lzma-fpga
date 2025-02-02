/*
 * LZMA2 FPGA Implementation
 * Memory Management System
 *
 * Optimized for 32KB input with smart caching and prefetch
 */

`timescale 1ns / 1ps

module lzma2_memory_manager 
    import lzma2_pkg::*;
(
    input  logic                clk,
    input  logic                rst_n,
    
    // Memory request interface
    input  logic [14:0]         addr,        // 32KB address space
    input  logic [255:0]        write_data,
    input  logic                write_en,
    input  logic                request_valid,
    output logic [255:0]        read_data,
    output logic                response_valid,
    output logic                ready,
    
    // Performance monitoring
    output logic [31:0]         cache_hits,
    output logic [31:0]         cache_misses,
    output logic [31:0]         prefetch_hits
);

    // Memory system parameters
    localparam CACHE_LINE_SIZE    = 128;    // Reduced cache line for 32KB
    localparam CACHE_WAYS         = 4;      // 4-way set associative
    localparam CACHE_SETS         = 32;     // Reduced sets for 32KB
    localparam PREFETCH_DEPTH     = 4;      // Prefetch buffer depth
    localparam MEMORY_LATENCY     = 10;     // Memory access cycles
    
    // Type definitions
    typedef struct packed {
        logic                    valid;
        logic                    dirty;
        logic [7:0]             tag;
        logic [CACHE_LINE_SIZE-1:0] data;
        logic [3:0]             lru_count;
    } cache_line_t;

    typedef struct packed {
        logic                    valid;
        logic [14:0]            addr;
        logic [CACHE_LINE_SIZE-1:0] data;
    } prefetch_entry_t;

    // Memory structures
    cache_line_t cache [CACHE_WAYS-1:0][CACHE_SETS-1:0];
    prefetch_entry_t prefetch_buffer [PREFETCH_DEPTH-1:0];
    logic [7:0] main_memory [32768-1:0];  // 32KB main memory

    // Memory access pattern analysis
    logic [14:0] last_addresses [7:0];
    logic [14:0] detected_stride;
    logic        pattern_valid;
    
    // Control state machine
    typedef enum logic [2:0] {
        IDLE,
        CHECK_CACHE,
        FETCH_LINE,
        UPDATE_CACHE,
        WRITEBACK,
        PREFETCH
    } state_t;
    
    state_t current_state, next_state;
    
    // Internal registers
    logic [3:0] latency_counter;
    logic [14:0] current_addr;
    logic [255:0] current_data;
    logic [1:0] selected_way;
    
    // Cache lookup function
    function automatic logic [1:0] find_cache_way;
        input logic [14:0] addr;
        logic [1:0] way = 2'b00;
        logic hit = 1'b0;
        
        for (int i = 0; i < CACHE_WAYS; i++) begin
            if (cache[i][addr[11:7]].valid && 
                cache[i][addr[11:7]].tag == addr[14:12]) begin
                way = i[1:0];
                hit = 1'b1;
                break;
            end
        end
        
        if (!hit) begin
            way = find_lru_way(addr[11:7]);
        end
        
        return way;
    endfunction
    
    // LRU management
    function automatic logic [1:0] find_lru_way;
        input logic [4:0] set_index;
        logic [1:0] lru_way = 2'b00;
        logic [3:0] min_count = 4'hF;
        
        for (int i = 0; i < CACHE_WAYS; i++) begin
            if (cache[i][set_index].lru_count < min_count) begin
                min_count = cache[i][set_index].lru_count;
                lru_way = i[1:0];
            end
        end
        
        return lru_way;
    endfunction
    
    // Update LRU counters
    task automatic update_lru;
        input logic [4:0] set_index;
        input logic [1:0] accessed_way;
        
        for (int i = 0; i < CACHE_WAYS; i++) begin
            if (i == accessed_way) begin
                cache[i][set_index].lru_count <= 4'hF;
            end else if (cache[i][set_index].lru_count > 0) begin
                cache[i][set_index].lru_count <= cache[i][set_index].lru_count - 1;
            end
        end
    endtask
    
    // Pattern detection and prefetch control
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pattern_valid <= 1'b0;
            detected_stride <= '0;
            for (int i = 0; i < 8; i++) begin
                last_addresses[i] <= '0;
            end
        end else if (request_valid) begin
            // Update address history
            for (int i = 7; i > 0; i--) begin
                last_addresses[i] <= last_addresses[i-1];
            end
            last_addresses[0] <= addr;
            
            // Detect access pattern
            logic [14:0] new_stride = addr - last_addresses[0];
            logic stride_match = (new_stride == detected_stride);
            
            if (stride_match && !pattern_valid) begin
                pattern_valid <= 1'b1;
            end else if (!stride_match && pattern_valid) begin
                pattern_valid <= 1'b0;
            end
            
            detected_stride <= new_stride;
        end
    end

    // Prefetch buffer management
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < PREFETCH_DEPTH; i++) begin
                prefetch_buffer[i] <= '0;
            end
        end else if (pattern_valid && current_state == IDLE) begin
            // Issue prefetch requests
            for (int i = 0; i < PREFETCH_DEPTH; i++) begin
                if (!prefetch_buffer[i].valid) begin
                    prefetch_buffer[i].valid <= 1'b1;
                    prefetch_buffer[i].addr <= addr + ((i+1) * detected_stride);
                end
            end
        end
    end

    // Main control state machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            response_valid <= 1'b0;
            ready <= 1'b1;
            cache_hits <= '0;
            cache_misses <= '0;
            prefetch_hits <= '0;
            latency_counter <= '0;
        end else begin
            current_state <= next_state;
            
            case (current_state)
                IDLE: begin
                    ready <= 1'b1;
                    response_valid <= 1'b0;
                    if (request_valid) begin
                        current_addr <= addr;
                        current_data <= write_data;
                        ready <= 1'b0;
                    end
                end
                
                CHECK_CACHE: begin
                    selected_way <= find_cache_way(current_addr);
                    if (cache[selected_way][current_addr[11:7]].valid &&
                        cache[selected_way][current_addr[11:7]].tag == current_addr[14:12]) begin
                        cache_hits <= cache_hits + 1;
                        response_valid <= 1'b1;
                        read_data <= cache[selected_way][current_addr[11:7]].data;
                        update_lru(current_addr[11:7], selected_way);
                    end else begin
                        cache_misses <= cache_misses + 1;
                        latency_counter <= MEMORY_LATENCY;
                    end
                end
                
                FETCH_LINE: begin
                    if (latency_counter > 0) begin
                        latency_counter <= latency_counter - 1;
                    end else begin
                        // Update cache with fetched data
                        cache[selected_way][current_addr[11:7]].valid <= 1'b1;
                        cache[selected_way][current_addr[11:7]].tag <= current_addr[14:12];
                        cache[selected_way][current_addr[11:7]].data <= current_data;
                        cache[selected_way][current_addr[11:7]].dirty <= write_en;
                        update_lru(current_addr[11:7], selected_way);
                        response_valid <= 1'b1;
                        read_data <= current_data;
                    end
                end
                
                UPDATE_CACHE: begin
                    cache[selected_way][current_addr[11:7]].data <= current_data;
                    cache[selected_way][current_addr[11:7]].dirty <= 1'b1;
                    update_lru(current_addr[11:7], selected_way);
                    response_valid <= 1'b1;
                end
                
                WRITEBACK: begin
                    if (latency_counter > 0) begin
                        latency_counter <= latency_counter - 1;
                    end else begin
                        cache[selected_way][current_addr[11:7]].dirty <= 1'b0;
                    end
                end
                
                PREFETCH: begin
                    if (prefetch_buffer[0].valid) begin
                        prefetch_hits <= prefetch_hits + 1;
                        response_valid <= 1'b1;
                        read_data <= prefetch_buffer[0].data;
                        
                        // Shift prefetch buffer
                        for (int i = 0; i < PREFETCH_DEPTH-1; i++) begin
                            prefetch_buffer[i] <= prefetch_buffer[i+1];
                        end
                        prefetch_buffer[PREFETCH_DEPTH-1] <= '0;
                    end
                end
            endcase
        end
    end

    // Next state logic
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            IDLE: begin
                if (request_valid) begin
                    next_state = CHECK_CACHE;
                end
            end
            
            CHECK_CACHE: begin
                if (cache[selected_way][current_addr[11:7]].valid &&
                    cache[selected_way][current_addr[11:7]].tag == current_addr[14:12]) begin
                    if (write_en) begin
                        next_state = UPDATE_CACHE;
                    end else begin
                        next_state = IDLE;
                    end
                end else begin
                    next_state = FETCH_LINE;
                end
            end
            
            FETCH_LINE: begin
                if (latency_counter == 0) begin
                    if (cache[selected_way][current_addr[11:7]].dirty) begin
                        next_state = WRITEBACK;
                    end else begin
                        next_state = IDLE;
                    end
                end
            end
            
            UPDATE_CACHE: begin
                next_state = IDLE;
            end
            
            WRITEBACK: begin
                if (latency_counter == 0) begin
                    next_state = IDLE;
                end
            end
            
            PREFETCH: begin
                next_state = IDLE;
            end
        endcase
    end

    // Debug assertions
    // synthesis translate_off
    always @(posedge clk) begin
        if (cache_hits + cache_misses > 0) begin
            $display("Cache hit rate: %0d%%", 
                    (cache_hits * 100) / (cache_hits + cache_misses));
        end
        
        if (pattern_valid) begin
            $display("Access pattern detected: stride = %0d", detected_stride);
        end
    end
    // synthesis translate_on

endmodule