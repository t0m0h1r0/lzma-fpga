/*
 * LZMA2 FPGA Implementation
 * Compression Engine Package
 *
 * Optimized for 32KB input size
 */

package lzma2_compression_pkg;
    // Compression parameters
    parameter MAX_MATCH_LENGTH   = 273;    // Maximum match length
    parameter MIN_MATCH_LENGTH   = 3;      // Minimum match length
    parameter HASH_BITS         = 15;     // Hash table size bits (optimized for 32KB)
    parameter HASH_SIZE         = 1 << HASH_BITS;
    parameter HASH_MASK         = HASH_SIZE - 1;

    // Position and length encoding parameters
    parameter NUM_LIT_CONTEXTS   = 256;    // Number of literal contexts
    parameter NUM_POS_STATES    = 4;      // Number of position states
    parameter NUM_LEN_STATES    = 4;      // Number of length states
    parameter MAX_DISTANCE      = 32768;  // Maximum match distance (32KB)
    parameter NUM_DIST_STATES   = 16;     // Number of distance states
    
    // Probability model parameters
    parameter PROB_INIT         = 8'h80;  // Initial probability (0.5)
    parameter PROB_MAX          = 8'hFF;  // Maximum probability
    parameter PROB_MIN         = 8'h01;   // Minimum probability
    parameter PROB_ADJUST_SHIFT = 4;      // Probability adjustment shift (faster adaptation)

    // Match finder parameters
    parameter HASH_MULTIPLIER    = 32'h01000193;  // FNV hash prime
    parameter HASH_INIT         = 32'h811C9DC5;  // FNV hash offset basis
    parameter CYCLIC_BUFFER_SIZE = 32768;  // Size of cyclic buffer (32KB)
    parameter NICE_LENGTH       = 32;     // Optimization threshold for match length

    // Range encoder parameters
    parameter RANGE_BITS        = 32;     // Range coder precision
    parameter TOP_MASK         = 32'hFF000000;  // Top bits mask
    parameter BIT_MODEL_TOTAL   = 2048;   // Total range for bit models
    parameter MOVE_BITS        = 5;       // Bits to move for probability updates

    // Buffer sizes
    parameter INPUT_BUFFER_SIZE = 256;    // 256-bit input buffer
    parameter OUTPUT_BUFFER_SIZE = 32;     // Output buffer size in bytes
    parameter MATCH_BUFFER_SIZE = 16;     // Match buffer size

    // Performance optimization
    parameter PARALLEL_HASH_UNITS = 8;    // Number of parallel hash units
    parameter PREFETCH_DISTANCE  = 16;    // Distance to prefetch in match finding
    
    // Debug levels
    parameter DEBUG_NONE        = 0;
    parameter DEBUG_BASIC       = 1;
    parameter DEBUG_VERBOSE     = 2;
    parameter DEBUG_FULL        = 3;

    // Type definitions for compression
    typedef struct packed {
        logic [15:0]            length;
        logic [14:0]            distance;  // 15 bits for 32KB
        logic                   literal_flag;
        logic [7:0]             literal;
        logic                   valid;
    } match_result_t;

    typedef struct packed {
        logic [31:0]            state;
        logic [31:0]            range;
        logic [31:0]            low;
        logic [7:0]             cache;
        logic [2:0]             cache_size;
    } range_coder_t;

    typedef struct packed {
        logic [7:0]             literal_probs [NUM_LIT_CONTEXTS-1:0];
        logic [7:0]             match_probs [NUM_POS_STATES-1:0];
        logic [7:0]             len_probs [NUM_LEN_STATES-1:0];
        logic [7:0]             dist_probs [NUM_DIST_STATES-1:0];
    } probability_model_t;

    // Match finder types
    typedef struct packed {
        logic [31:0]            hash;
        logic [14:0]            position;
        logic [7:0]             length;
        logic                   valid;
    } hash_entry_t;

    typedef struct packed {
        logic [7:0]             data [NICE_LENGTH-1:0];
        logic [14:0]            position;
        logic                   valid;
    } match_buffer_t;

    // Range encoder types
    typedef struct packed {
        logic [7:0]             data;
        logic                   valid;
        logic                   last;
    } encoded_byte_t;

    typedef struct packed {
        encoded_byte_t          bytes [OUTPUT_BUFFER_SIZE-1:0];
        logic [5:0]             count;
        logic                   full;
    } output_buffer_t;

    // Performance monitoring types
    typedef struct packed {
        logic [31:0]            matches_found;
        logic [31:0]            literals_encoded;
        logic [31:0]            bytes_processed;
        logic [31:0]            output_bytes;
        logic [31:0]            hash_collisions;
        logic [31:0]            avg_match_length;
        logic [31:0]            max_match_length;
        logic [31:0]            compression_cycles;
    } compression_stats_t;

    // Utility functions
    function automatic logic [HASH_BITS-1:0] calc_hash;
        input logic [23:0] data;  // 3 bytes for hash calculation
        logic [31:0] hash;
        
        hash = HASH_INIT;
        for (int i = 0; i < 3; i++) begin
            hash = (hash ^ data[i*8 +: 8]) * HASH_MULTIPLIER;
        end
        
        return hash[HASH_BITS-1:0];
    endfunction

    function automatic logic [7:0] update_probability;
        input logic [7:0] prob;
        input logic bit_value;
        
        if (bit_value)
            return prob + ((PROB_MAX - prob) >> PROB_ADJUST_SHIFT);
        else
            return prob - ((prob - PROB_MIN) >> PROB_ADJUST_SHIFT);
    endfunction

    function automatic logic [7:0] get_literal_context;
        input logic [7:0] prev_byte;
        input logic [7:0] current_byte;
        return {prev_byte[7:5], current_byte[7:5]};
    endfunction

    function automatic logic [1:0] get_position_state;
        input logic [14:0] position;
        return position[1:0];  // Use 2 LSBs for position state
    endfunction

    // Debug helper functions
    function automatic string match_to_string;
        input match_result_t match;
        string result;
        
        if (match.literal_flag)
            $sformat(result, "LIT: 0x%02x", match.literal);
        else
            $sformat(result, "MATCH: len=%0d dist=%0d", match.length, match.distance);
            
        return result;
    endfunction

    function automatic string prob_to_string;
        input logic [7:0] prob;
        real probability;
        string result;
        
        probability = real'(prob) / 256.0;
        $sformat(result, "%f", probability);
        return result;
    endfunction

endpackage