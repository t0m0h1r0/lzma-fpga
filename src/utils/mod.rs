//! Utility functions and helpers for LZMA2 FPGA Compression Driver

use crate::error::{Lzma2Error, Lzma2Result};
use std::time::{Duration, Instant};

/// Utility for timing operations
pub struct Stopwatch {
    start: Instant,
}

impl Stopwatch {
    /// Create and start a new stopwatch
    pub fn start() -> Self {
        Self {
            start: Instant::now(),
        }
    }
    
    /// Stop the stopwatch and return elapsed time
    pub fn stop(&self) -> Duration {
        self.start.elapsed()
    }
}

/// Byte slice utilities
pub trait ByteSliceExt {
    /// Check if a byte slice is zero-filled
    fn is_zero(&self) -> bool;
    
    /// Get the first non-zero index
    fn first_non_zero_index(&self) -> Option<usize>;
    
    /// Pad or truncate to a specific length
    fn pad_or_truncate(&self, length: usize) -> Vec<u8>;
}

impl ByteSliceExt for [u8] {
    fn is_zero(&self) -> bool {
        self.iter().all(|&x| x == 0)
    }
    
    fn first_non_zero_index(&self) -> Option<usize> {
        self.iter().position(|&x| x != 0)
    }
    
    fn pad_or_truncate(&self, length: usize) -> Vec<u8> {
        let mut result = Vec::with_capacity(length);
        
        // Copy existing data or pad with zeros
        result.extend(self.iter().take(length).cloned());
        
        // If original slice is shorter, pad with zeros
        if result.len() < length {
            result.resize(length, 0);
        }
        
        result
    }
}

/// CRC32 utility
pub struct Crc32 {
    polynomial: u32,
    initial_value: u32,
}

impl Crc32 {
    /// Create a new CRC32 calculator
    pub fn new(polynomial: u32, initial_value: u32) -> Self {
        Self {
            polynomial,
            initial_value,
        }
    }
    
    /// Calculate CRC32 for a byte slice
    pub fn calculate(&self, data: &[u8]) -> u32 {
        let mut crc = self.initial_value;
        
        for &byte in data {
            crc ^= u32::from(byte);
            for _ in 0..8 {
                crc = if crc & 1 == 1 {
                    (crc >> 1) ^ self.polynomial
                } else {
                    crc >> 1
                }
            }
        }
        
        !crc
    }
    
    /// Verify CRC32 for data and reference CRC
    pub fn verify(&self, data: &[u8], reference_crc: u32) -> bool {
        self.calculate(data) == reference_crc
    }
}

/// Logging and tracing utilities
pub trait LogExt {
    /// Log an error with context
    fn log_error(&self, context: &str);
    
    /// Log a warning
    fn log_warning(&self, message: &str);
}

impl<T: std::fmt::Debug> LogExt for Result<T, Lzma2Error> {
    fn log_error(&self, context: &str) {
        if let Err(e) = self {
            eprintln!("Error in {}: {:?}", context, e);
        }
    }
    
    fn log_warning(&self, message: &str) {
        if let Err(e) = self {
            eprintln!("Warning {}: {:?}", message, e);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_stopwatch() {
        let sw = Stopwatch::start();
        std::thread::sleep(Duration::from_millis(10));
        let elapsed = sw.stop();
        assert!(elapsed >= Duration::from_millis(10));
    }
    
    #[test]
    fn test_byte_slice_ext() {
        let zeros = [0u8; 10];
        let mixed = [0u8, 1, 2, 0, 0];
        
        assert!(zeros.is_zero());
        assert!(!mixed.is_zero());
        
        assert_eq!(zeros.first_non_zero_index(), None);
        assert_eq!(mixed.first_non_zero_index(), Some(1));
        
        let padded = [1u8, 2].pad_or_truncate(5);
        assert_eq!(padded, vec![1, 2, 0, 0, 0]);
        
        let truncated = [1u8, 2, 3, 4, 5].pad_or_truncate(3);
        assert_eq!(truncated, vec![1, 2, 3]);
    }
    
    #[test]
    fn test_crc32() {
        let crc = Crc32::new(0x04C11DB7, 0xFFFFFFFF);
        
        let data = b"Hello, World!";
        let calculated_crc = crc.calculate(data);
        
        assert!(crc.verify(data, calculated_crc));
        assert!(!crc.verify(data, calculated_crc ^ 0xFFFF));
    }
}
