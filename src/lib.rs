//! LZMA2 FPGA Compression Driver
//! 
//! A high-performance driver for LZMA2 compression on FPGA hardware

// Expose public modules
pub mod error;
pub mod device;
pub mod transfer;
pub mod utils;

// Prelude for convenient imports
pub mod prelude {
    pub use crate::error::Lzma2Error;
    pub use crate::device::{
        HardwareCompressionDevice,
        PerformanceMetrics,
    };
}

// Version information
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

// Ensure proper feature configuration
#[cfg(not(feature = "pcie"))]
compile_error!("At least one hardware interface feature must be enabled");
