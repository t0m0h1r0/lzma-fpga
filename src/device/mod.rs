//! Device abstraction for LZMA2 FPGA Compression Driver

mod metrics;
mod pcie;

pub use metrics::{PerformanceMetrics, CacheMetrics};
pub use pcie::PcieDevice;

use crate::error::{Lzma2Error, Lzma2Result};

/// Configuration for hardware compression device
#[derive(Debug, Clone)]
pub struct DeviceConfig {
    /// Vendor ID of the PCIe device
    pub vendor_id: u16,
    
    /// Device ID of the PCIe device
    pub device_id: u16,
    
    /// BAR (Base Address Register) index
    pub bar_index: usize,
}

/// Trait defining the interface for hardware compression devices
pub trait HardwareCompressionDevice {
    /// Compress input data
    /// 
    /// # Errors
    /// Returns `Lzma2Error` if compression fails
    fn compress(&self, input: &[u8]) -> Lzma2Result<Vec<u8>>;
    
    /// Decompress input data
    /// 
    /// # Errors
    /// Returns `Lzma2Error` if decompression fails
    fn decompress(&self, input: &[u8]) -> Lzma2Result<Vec<u8>>;
    
    /// Retrieve performance metrics for the device
    /// 
    /// # Errors
    /// Returns `Lzma2Error` if metrics cannot be retrieved
    fn get_performance_metrics(&self) -> Lzma2Result<PerformanceMetrics>;
}

/// Device discovery and management
pub struct DeviceManager;

impl DeviceManager {
    /// Probe for available LZMA2 compression devices
    /// 
    /// # Errors
    /// Returns `Lzma2Error` if device discovery fails
    pub fn probe() -> Lzma2Result<Vec<PcieDevice>> {
        PcieDevice::probe()
    }
    
    /// Select the first available device
    /// 
    /// # Errors
    /// Returns `Lzma2Error` if no devices are found
    pub fn select_first_device() -> Lzma2Result<PcieDevice> {
        let devices = Self::probe()?;
        devices.into_iter().next()
            .ok_or(Lzma2Error::DeviceInitError(
                "No LZMA2 compression devices found".to_string()
            ))
    }
}
