/*
 * LZMA2 FPGA Implementation
 * Match Finder Module
 *
 * Optimized for 32KB input size with parallel hash calculation
 * and efficient match searching
 */

module lzma2_match_finder
    import lzma2_pkg::*;
    import lzma2_compression_pkg::*;
(
    input  logic                clk,
    input  logic                rst_n,
    
    // Data interface
    input  logic [255:0]        data_in,           // 32-byte input chunk
    input  logic                data_valid,
    input  logic [DICT_SIZE-1:0][7:0] dictionary,  // Dictionary buffer
    output logic                ready,
    
    // Match output
    output match_result_t       result,
    
    // Performance monitoring
    output logic [31:0]         match_count,
    output logic [31:0]         hash_collisions
);

    // Hash table for match finding (optimized for 32KB)
    logic [14:0] hash_table [HASH_SIZE-1:0];  // Position entries
    
    // Internal registers
    logic [14:0] position;          // Current position in the buffer
    logic [23:0] current_data;      // Current 3 bytes for hash calculation
    logic [HASH_BITS-1:0] hash;     // Calculated hash value
    
    // Parallel match search registers
    logic [7:0] match_lengths [PARALLEL_HASH_UNITS-1:0];
    logic [14:0] match_distances [PARALLEL_HASH_UNITS-1:0];
    logic match_found [PARALLEL_HASH_UNITS-1:0];
    
    // Best match selection registers
    logic [7:0] best_length;
    logic [14:0] best_distance;
    logic best_found;
    
    // Control flags
    logic processing;
    logic updating_hash;
    
    // Performance counters
    logic [31:0] total_matches;
    logic [31:0] hash_collision_count;

    // Parallel hash calculation units
    genvar i;
    generate
        for (i = 0; i < PARALLEL_HASH_UNITS; i++) begin : hash_units
            localparam int OFFSET = i * 8;  // 8-bit offset for each unit
            
            // Hash calculation per unit
            always_ff @(posedge clk) begin
                if (data_valid && !processing) begin
                    logic [23:0] unit_data = data_in[OFFSET +: 24];
                    logic [HASH_BITS-1:0] unit_hash = calc_hash(unit_data);
                    logic [14:0] prev_pos = hash_table[unit_hash];
                    
                    // Check for hash collision
                    if (hash_table[unit_hash] != 0) begin
                        hash_collision_count <= hash_collision_count + 1;
                    end
                    
                    // Update hash table
                    hash_table[unit_hash] <= position + i[14:0];
                    
                    // Start match search
                    match_lengths[i] <= 0;
                    match_distances[i] <= 0;
                    match_found[i] <= 1'b0;
                    
                    // Only search if within window
                    if (position + i - prev_pos <= MAX_DISTANCE) begin
                        logic [7:0] len = 0;
                        // Compare bytes
                        for (int j = 0; j < MAX_MATCH_LENGTH; j++) begin
                            if (data_in[OFFSET + j] == dictionary[prev_pos + j]) begin
                                len = len + 1;
                            end else begin
                                break;
                            end
                        end
                        
                        if (len >= MIN_MATCH_LENGTH) begin
                            match_lengths[i] <= len;
                            match_distances[i] <= position + i - prev_pos;
                            match_found[i] <= 1'b1;
                        end
                    end
                end
            end
        end
    endgenerate

    // Best match selection logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            best_length <= 0;
            best_distance <= 0;
            best_found <= 1'b0;
        end else if (data_valid && !processing) begin
            // Reset best match
            best_length <= 0;
            best_distance <= 0;
            best_found <= 1'b0;
            
            // Find best match among parallel units
            for (int i = 0; i < PARALLEL_HASH_UNITS; i++) begin
                if (match_found[i] && match_lengths[i] > best_length) begin
                    best_length <= match_lengths[i];
                    best_distance <= match_distances[i];
                    best_found <= 1'b1;
                end
            end
        end
    end

    // Result output generation
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result <= '0;
            processing <= 1'b0;
            position <= '0;
            match_count <= '0;
            hash_collisions <= '0;
            ready <= 1'b1;
        end else begin
            if (data_valid && ready) begin
                processing <= 1'b1;
                ready <= 1'b0;
                
                // Output match or literal
                if (best_found) begin
                    result.length <= best_length;
                    result.distance <= best_distance;
                    result.literal_flag <= 1'b0;
                    result.valid <= 1'b1;
                    match_count <= match_count + 1;
                end else begin
                    result.literal_flag <= 1'b1;
                    result.literal <= data_in[7:0];
                    result.valid <= 1'b1;
                end
                
                // Update position and counters
                position <= position + PARALLEL_HASH_UNITS;
                hash_collisions <= hash_collision_count;
                
                // Reset processing state
                if (position + PARALLEL_HASH_UNITS >= CYCLIC_BUFFER_SIZE) begin
                    position <= '0;  // Wrap around
                end
            end else if (processing) begin
                processing <= 1'b0;
                ready <= 1'b1;
                result.valid <= 1'b0;
            end
        end
    end

    // Debug monitoring
    // synthesis translate_off
    real compression_ratio;
    always @(posedge clk) begin
        if (match_count > 0) begin
            compression_ratio = real'(position) / 
                              real'((match_count * 3) + (position - match_count));
            
            if (compression_ratio < 1.2) begin
                $display("Warning: Low compression ratio (%f) at position %0d", 
                        compression_ratio, position);
            end
        end
        
        if (hash_collisions > position / 2) begin
            $display("Warning: High hash collision rate at position %0d", position);
        end
    end
    // synthesis translate_on

endmodule