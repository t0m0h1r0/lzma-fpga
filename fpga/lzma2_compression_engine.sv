/*
 * LZMA2 FPGA Implementation
 * Compression Engine Main Module
 *
 * Optimized for 32KB input size with parallel processing
 * and pipelined architecture
 */

module lzma2_compression_engine
    import lzma2_pkg::*;
    import lzma2_compression_pkg::*;
(
    input  logic                clk,
    input  logic                rst_n,
    
    // Data interface
    input  logic [255:0]        data_in,
    input  logic                data_valid,
    output logic                ready,
    output logic [255:0]        data_out,
    output logic                data_valid_out,
    input  logic                output_ready,
    
    // Memory interface
    output mem_request_t        mem_request,
    input  mem_response_t       mem_response,
    
    // Performance monitoring
    output logic [31:0]         match_count,
    output logic [31:0]         literal_count,
    output logic [31:0]         compressed_size,
    output performance_counters_t perf_counters
);

    // Pipeline stages definition
    typedef struct packed {
        logic [255:0]           data;
        logic                   valid;
        match_result_t          matches [PARALLEL_UNITS-1:0];
        range_coder_t           range_state;
        logic [14:0]            position;
        logic                   last_chunk;
    } pipeline_stage_t;

    // Internal registers and signals
    pipeline_stage_t pipeline [PIPE_STAGES-1:0];
    logic [PARALLEL_UNITS-1:0] match_ready;
    logic [PARALLEL_UNITS-1:0] encode_ready;
    logic [14:0] current_position;
    logic processing_complete;
    logic flush_pipeline;
    
    // Progress tracking
    logic [14:0] bytes_processed;
    logic [14:0] bytes_remaining;
    
    // Match finder instances
    match_result_t match_results [PARALLEL_UNITS-1:0];
    logic [PARALLEL_UNITS-1:0][31:0] unit_match_count;
    logic [PARALLEL_UNITS-1:0][31:0] unit_hash_collisions;
    
    // Range encoder instances
    range_coder_t range_states [PARALLEL_UNITS-1:0];
    logic [PARALLEL_UNITS-1:0][31:0] unit_bits_encoded;
    logic [PARALLEL_UNITS-1:0][31:0] unit_compression_ratio;
    
    // Probability model (shared among encoders)
    probability_model_t prob_model;
    
    // Performance monitoring
    logic [31:0] stall_cycles;
    logic [31:0] active_cycles;
    logic [31:0] total_cycles;
    
    // Generate parallel match finders
    genvar i;
    generate
        for (i = 0; i < PARALLEL_UNITS; i++) begin : gen_match_finders
            lzma2_match_finder match_finder_inst (
                .clk(clk),
                .rst_n(rst_n),
                .data_in(data_in[i*32 +: 256]),
                .data_valid(data_valid && !processing_complete),
                .dictionary(mem_response.data),
                .ready(match_ready[i]),
                .result(match_results[i]),
                .match_count(unit_match_count[i]),
                .hash_collisions(unit_hash_collisions[i])
            );

            lzma2_range_encoder range_encoder_inst (
                .clk(clk),
                .rst_n(rst_n),
                .match_result(match_results[i]),
                .input_valid(pipeline[i].valid),
                .prob_model(prob_model),
                .encoded_data(data_out[i*8 +: 8]),
                .encoded_valid(data_valid_out),
                .range_state(range_states[i]),
                .ready(encode_ready[i]),
                .total_bits_encoded(unit_bits_encoded[i]),
                .compression_ratio(unit_compression_ratio[i])
            );
        end
    endgenerate

    // Pipeline control logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all pipeline stages
            for (int i = 0; i < PIPE_STAGES; i++) begin
                pipeline[i] <= '0;
            end
            
            // Reset control signals
            ready <= 1'b1;
            current_position <= '0;
            bytes_processed <= '0;
            bytes_remaining <= INPUT_SIZE[14:0];
            processing_complete <= 1'b0;
            flush_pipeline <= 1'b0;
            
            // Reset performance counters
            match_count <= '0;
            literal_count <= '0;
            compressed_size <= '0;
            stall_cycles <= '0;
            active_cycles <= '0;
            total_cycles <= '0;
            
        end else begin
            total_cycles <= total_cycles + 1;
            
            if (data_valid && ready && !processing_complete) begin
                // Input stage - load new data
                pipeline[0].data <= data_in;
                pipeline[0].valid <= 1'b1;
                pipeline[0].position <= current_position;
                
                // Store match results
                for (int i = 0; i < PARALLEL_UNITS; i++) begin
                    pipeline[0].matches[i] <= match_results[i];
                    
                    // Update statistics
                    if (match_results[i].valid) begin
                        if (!match_results[i].literal_flag) begin
                            match_count <= match_count + 1;
                        end else begin
                            literal_count <= literal_count + 1;
                        end
                    end
                end
                
                // Update position and byte counters
                current_position <= current_position + PARALLEL_UNITS;
                bytes_processed <= bytes_processed + PARALLEL_UNITS;
                bytes_remaining <= bytes_remaining - PARALLEL_UNITS;
                
                // Check for completion
                if (bytes_remaining <= PARALLEL_UNITS) begin
                    processing_complete <= 1'b1;
                    flush_pipeline <= 1'b1;
                end
                
                active_cycles <= active_cycles + 1;
            end

            // Pipeline shift
            if (output_ready || !pipeline[PIPE_STAGES-1].valid) begin
                for (int i = PIPE_STAGES-1; i > 0; i--) begin
                    pipeline[i] <= pipeline[i-1];
                end
            end else begin
                stall_cycles <= stall_cycles + 1;
            end
            
            // Update ready signal
            ready <= &{match_ready, encode_ready} && 
                    (!pipeline[0].valid || output_ready) &&
                    !processing_complete;
                    
            // Update compressed size counter
            if (data_valid_out) begin
                compressed_size <= compressed_size + 1;
            end
            
            // Update performance counters
            perf_counters.total_bytes <= bytes_processed;
            perf_counters.compressed_bytes <= compressed_size;
            perf_counters.cycles <= total_cycles;
            perf_counters.cache_hits <= mem_response.hit_count;
            perf_counters.cache_misses <= mem_response.miss_count;
            perf_counters.match_hits <= match_count;
            perf_counters.literal_count <= literal_count;
        end
    end

    // Memory request generation
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_request <= '0;
        end else begin
            // Generate memory requests for match finding
            mem_request.valid <= data_valid && ready && !processing_complete;
            mem_request.address <= current_position;
            mem_request.write_en <= 1'b0;
            mem_request.urgent <= 1'b1;
        end
    end

    // Probability model initialization and updates
    initial begin
        for (int i = 0; i < NUM_LIT_CONTEXTS; i++) begin
            prob_model.literal_probs[i] = PROB_INIT;
        end
        for (int i = 0; i < NUM_POS_STATES; i++) begin
            prob_model.match_probs[i] = PROB_INIT;
            prob_model.dist_probs[i] = PROB_INIT;
        end
        for (int i = 0; i < NUM_LEN_STATES; i++) begin
            prob_model.len_probs[i] = PROB_INIT;
        end
    end

    // Probability model updates
    always_ff @(posedge clk) begin
        if (data_valid_out) begin
            for (int i = 0; i < PARALLEL_UNITS; i++) begin
                if (pipeline[i].valid) begin
                    if (pipeline[i].matches[i].literal_flag) begin
                        // Update literal probabilities
                        logic [7:0] context = get_literal_context(
                            pipeline[i].range_state.cache,
                            pipeline[i].matches[i].literal
                        );
                        prob_model.literal_probs[context] <= update_probability(
                            prob_model.literal_probs[context],
                            pipeline[i].matches[i].literal[7]
                        );
                    end else begin
                        // Update match probabilities
                        logic [1:0] pos_state = get_position_state(pipeline[i].position);
                        prob_model.match_probs[pos_state] <= update_probability(
                            prob_model.match_probs[pos_state],
                            1'b1
                        );
                    end
                end
            end
        end
    end

    // Debug and verification logic
    // synthesis translate_off
    always @(posedge clk) begin
        // Monitor progress
        if (bytes_processed % 1024 == 0 && bytes_processed > 0) begin
            $display("Compression progress: %0d%%", 
                    (bytes_processed * 100) / INPUT_SIZE);
        end
        
        // Monitor pipeline efficiency
        if (stall_cycles > total_cycles / 4) begin
            $display("Warning: High stall rate detected at time %t", $time);
        end
        
        // Monitor compression ratio
        if (compressed_size > 0) begin
            real current_ratio = real'(bytes_processed) / real'(compressed_size);
            if (current_ratio < 1.2) begin
                $display("Warning: Low compression ratio (%f) at time %t", 
                        current_ratio, $time);
            end
        end
    end
    // synthesis translate_on

endmodule