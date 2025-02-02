//! Performance metrics for LZMA2 FPGA Compression Device

use std::fmt;

/// Cache performance metrics
#[derive(Debug, Clone, Default)]
pub struct CacheMetrics {
    /// Total cache hits
    pub hits: u64,
    
    /// Total cache misses
    pub misses: u64,
    
    /// Cache hit ratio
    pub hit_ratio: f32,
}

impl CacheMetrics {
    /// Calculate hit ratio
    pub fn calculate_hit_ratio(&mut self) {
        let total = self.hits + self.misses;
        self.hit_ratio = if total > 0 {
            self.hits as f32 / total as f32
        } else {
            0.0
        };
    }
}

/// Comprehensive performance metrics for compression device
#[derive(Debug, Clone, Default)]
pub struct PerformanceMetrics {
    /// Total bytes processed
    pub total_bytes_processed: u64,
    
    /// Compressed bytes generated
    pub compressed_bytes: u64,
    
    /// Compression ratio
    pub compression_ratio: f32,
    
    /// Total clock cycles used
    pub cycles: u64,
    
    /// Cache performance metrics
    pub cache_metrics: CacheMetrics,
    
    /// Number of literal bytes encoded
    pub literal_count: u64,
    
    /// Number of match hits during compression
    pub match_hits: u64,
}

impl PerformanceMetrics {
    /// Calculate compression ratio
    pub fn calculate_compression_ratio(&mut self) {
        self.compression_ratio = if self.total_bytes_processed > 0 {
            self.compressed_bytes as f32 / self.total_bytes_processed as f32
        } else {
            1.0
        };
    }
}

impl fmt::Display for PerformanceMetrics {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Performance Metrics:\n\
            Total Processed: {} bytes\n\
            Compressed Size: {} bytes\n\
            Compression Ratio: {:.2}\n\
            Cycles: {}\n\
            Cache Hits: {} ({:.2}%)\n\
            Literals: {}\n\
            Match Hits: {}",
            self.total_bytes_processed,
            self.compressed_bytes,
            self.compression_ratio,
            self.cycles,
            self.cache_metrics.hits,
            self.cache_metrics.hit_ratio * 100.0,
            self.literal_count,
            self.match_hits
        )
    }
}
