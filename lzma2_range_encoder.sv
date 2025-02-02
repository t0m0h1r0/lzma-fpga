/*
 * LZMA2 FPGA Implementation
 * Range Encoder Module
 *
 * Optimized for 32KB input size with efficient probability model updates
 * and parallel encoding capabilities
 */

module lzma2_range_encoder
    import lzma2_pkg::*;
    import lzma2_compression_pkg::*;
(
    input  logic                clk,
    input  logic                rst_n,
    
    // Input interface
    input  match_result_t       match_result,
    input  logic                input_valid,
    input  probability_model_t  prob_model,
    
    // Output interface
    output logic [7:0]          encoded_data,
    output logic                encoded_valid,
    output range_coder_t        range_state,
    output logic                ready,
    
    // Performance monitoring
    output logic [31:0]         total_bits_encoded,
    output logic [31:0]         compression_ratio      // Fixed point: 16.16
);

    // Internal state
    range_coder_t state;
    
    // Output buffer
    output_buffer_t output_buffer;
    
    // Control flags
    logic processing;
    logic normalizing;
    logic flushing;
    
    // Performance monitoring
    logic [31:0] input_bytes;
    logic [31:0] output_bytes;
    
    // Normalization control
    task automatic normalize_range;
        output logic should_output;
        begin
            should_output = 1'b0;
            if (state.range < 16'h4000) begin
                encoded_data = state.low[31:24];
                should_output = 1'b1;
                state.range = state.range << 8;
                state.low = state.low << 8;
            end
        end
    endtask
    
    // Encode single bit with probability
    task automatic encode_bit;
        input logic bit_value;
        input logic [7:0] probability;
        logic [31:0] bound;
        begin
            bound = (state.range >> 8) * probability;
            
            if (bit_value) begin
                state.low = state.low + bound;
                state.range = state.range - bound;
            end else begin
                state.range = bound;
            end
            
            // Check if normalization needed
            logic should_output;
            normalize_range(should_output);
            encoded_valid = should_output;
        end
    endtask

    // Main encoding process
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= '{
                range: 32'hFFFFFFFF,
                low: 0,
                cache: 0,
                cache_size: 0,
                default: '0
            };
            output_buffer <= '{default: '0};
            processing <= 1'b0;
            normalizing <= 1'b0;
            flushing <= 1'b0;
            ready <= 1'b1;
            encoded_valid <= 1'b0;
            total_bits_encoded <= '0;
            input_bytes <= '0;
            output_bytes <= '0;
        end else begin
            if (input_valid && ready) begin
                processing <= 1'b1;
                ready <= 1'b0;
                
                if (match_result.literal_flag) begin
                    // Encode literal
                    logic [7:0] context = get_literal_context(state.cache, match_result.literal);
                    logic [7:0] prob = prob_model.literal_probs[context];
                    
                    for (int i = 7; i >= 0; i--) begin
                        logic bit = (match_result.literal >> i) & 1;
                        encode_bit(bit, prob);
                        prob = update_probability(prob, bit);
                        total_bits_encoded <= total_bits_encoded + 1;
                    end
                    
                    state.cache <= match_result.literal;
                    input_bytes <= input_bytes + 1;
                    
                end else begin
                    // Encode match
                    logic [1:0] pos_state = get_position_state(state.low[14:0]);
                    
                    // Encode match flag
                    encode_bit(1'b1, prob_model.match_probs[pos_state]);
                    total_bits_encoded <= total_bits_encoded + 1;
                    
                    // Encode match length
                    logic [7:0] len_state;
                    if (match_result.length < 8)
                        len_state = match_result.length - MIN_MATCH_LENGTH;
                    else if (match_result.length < 16)
                        len_state = 7;
                    else if (match_result.length < 32)
                        len_state = 8;
                    else
                        len_state = 9;
                    
                    logic [7:0] len_prob = prob_model.len_probs[len_state[1:0]];
                    encode_bit(1'b1, len_prob);
                    total_bits_encoded <= total_bits_encoded + 1;
                    
                    // Encode distance
                    for (int i = 14; i >= 0; i--) begin
                        logic bit = (match_result.distance >> i) & 1;
                        logic [7:0] dist_prob = prob_model.dist_probs[i[3:0]];
                        encode_bit(bit, dist_prob);
                        total_bits_encoded <= total_bits_encoded + 1;
                    end
                    
                    input_bytes <= input_bytes + match_result.length;
                end
                
                // Update compression ratio (fixed point 16.16)
                if (output_bytes > 0) begin
                    compression_ratio <= (input_bytes << 16) / output_bytes;
                end
                
                if (encoded_valid) begin
                    output_bytes <= output_bytes + 1;
                end
                
                // Check if ready for next input
                if (!normalizing && !flushing) begin
                    ready <= 1'b1;
                    processing <= 1'b0;
                end
                
            end else if (normalizing) begin
                // Continue normalization if needed
                logic should_output;
                normalize_range(should_output);
                encoded_valid <= should_output;
                
                if (!should_output) begin
                    normalizing <= 1'b0;
                    ready <= 1'b1;
                end
                
            end else if (flushing) begin
                // Flush remaining bits
                encoded_data <= state.low[31:24];
                state.low <= state.low << 8;
                encoded_valid <= 1'b1;
                output_bytes <= output_bytes + 1;
                
                if (state.low == 0) begin
                    flushing <= 1'b0;
                    ready <= 1'b1;
                end
            end
        end
    end

    // Output range state
    always_ff @(posedge clk) begin
        range_state <= state;
    end

    // Debug monitoring
    // synthesis translate_off
    real effective_compression_ratio;
    always @(posedge clk) begin
        if (output_bytes > 0) begin
            effective_compression_ratio = real'(input_bytes) / real'(output_bytes);
            
            if (effective_compression_ratio < 1.2) begin
                $display("Warning: Low compression ratio (%f) at time %t", 
                        effective_compression_ratio, $time);
            end
        end
        
        if (total_bits_encoded % 1000 == 0) begin
            $display("Encoded %0d bits, compression ratio: %f", 
                    total_bits_encoded, effective_compression_ratio);
        end
    end
    // synthesis translate_on

endmodule