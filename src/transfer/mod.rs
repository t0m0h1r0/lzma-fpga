//! Data transfer strategies for LZMA2 FPGA Compression Driver

use crate::error::{Lzma2Error, Lzma2Result};

/// Data transfer strategies
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum TransferStrategy {
    /// Memory-mapped I/O transfer
    Mmio,
    
    /// Direct Memory Access transfer
    Dma,
    
    /// Streaming transfer
    Streaming,
}

/// Trait defining data transfer capabilities
pub trait DataTransfer {
    /// Transfer input data to the device
    /// 
    /// # Errors
    /// Returns `Lzma2Error` if data transfer fails
    fn transfer_input(&self, data: &[u8]) -> Lzma2Result<()>;
    
    /// Read output data from the device
    /// 
    /// # Errors
    /// Returns `Lzma2Error` if data reading fails
    fn read_output(&self) -> Lzma2Result<Vec<u8>>;
}

/// Configuration for data transfer
#[derive(Debug, Clone)]
pub struct TransferConfig {
    /// Selected transfer strategy
    pub strategy: TransferStrategy,
    
    /// Maximum transfer chunk size
    pub chunk_size: usize,
    
    /// Buffer size for streaming transfers
    pub buffer_size: usize,
}

impl Default for TransferConfig {
    fn default() -> Self {
        Self {
            strategy: TransferStrategy::Mmio,
            chunk_size: 256,  // 256-bit chunks
            buffer_size: 32 * 1024,  // 32KB buffer
        }
    }
}

/// Transfer performance metrics
#[derive(Debug, Clone, Default)]
pub struct TransferMetrics {
    /// Total bytes transferred
    pub total_bytes: u64,
    
    /// Transfer duration
    pub transfer_time: std::time::Duration,
    
    /// Transfer bandwidth
    pub bandwidth: f64,
    
    /// Number of transfer chunks
    pub chunk_count: u64,
}

/// Transfer statistics collector
pub struct TransferStatistics {
    /// Accumulated metrics
    metrics: TransferMetrics,
}

impl TransferStatistics {
    /// Create a new statistics collector
    pub fn new() -> Self {
        Self {
            metrics: TransferMetrics::default(),
        }
    }
    
    /// Record a transfer operation
    pub fn record_transfer(&mut self, bytes: u64, duration: std::time::Duration) {
        self.metrics.total_bytes += bytes;
        self.metrics.transfer_time += duration;
        self.metrics.chunk_count += 1;
        
        // Calculate bandwidth (MB/s)
        let seconds = duration.as_secs_f64();
        self.metrics.bandwidth = if seconds > 0.0 {
            (bytes as f64 / 1_000_000.0) / seconds
        } else {
            0.0
        };
    }
    
    /// Get current transfer metrics
    pub fn get_metrics(&self) -> &TransferMetrics {
        &self.metrics
    }
}

// Utility functions for transfer strategies
impl TransferStrategy {
    /// Determine optimal chunk size based on strategy
    pub fn optimal_chunk_size(&self) -> usize {
        match self {
            TransferStrategy::Mmio => 256,      // 256-bit chunks
            TransferStrategy::Dma => 4096,      // Large DMA-friendly chunks
            TransferStrategy::Streaming => 1024 // Streaming-optimized chunk size
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Instant;
    
    #[test]
    fn test_transfer_config_default() {
        let config = TransferConfig::default();
        assert_eq!(config.strategy, TransferStrategy::Mmio);
        assert_eq!(config.chunk_size, 256);
        assert_eq!(config.buffer_size, 32 * 1024);
    }
    
    #[test]
    fn test_transfer_statistics() {
        let mut stats = TransferStatistics::new();
        
        let start = Instant::now();
        let duration = std::time::Duration::from_millis(100);
        let bytes = 1_000_000u64;
        
        stats.record_transfer(bytes, duration);
        
        let metrics = stats.get_metrics();
        assert_eq!(metrics.total_bytes, bytes);
        assert!(metrics.bandwidth > 0.0);
    }
    
    #[test]
    fn test_transfer_strategy_chunk_size() {
        assert_eq!(TransferStrategy::Mmio.optimal_chunk_size(), 256);
        assert_eq!(TransferStrategy::Dma.optimal_chunk_size(), 4096);
        assert_eq!(TransferStrategy::Streaming.optimal_chunk_size(), 1024);
    }
}
