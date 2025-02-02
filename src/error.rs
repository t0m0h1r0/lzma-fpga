//! Error handling for LZMA2 FPGA Driver

use std::fmt;
use thiserror::Error;

/// Comprehensive error enum for LZMA2 FPGA Driver
#[derive(Debug, Error)]
pub enum Lzma2Error {
    /// Device initialization errors
    #[error("Device initialization failed: {0}")]
    DeviceInitError(String),
    
    /// Data transfer errors
    #[error("Data transfer error: {0}")]
    TransferError(String),
    
    /// Compression/decompression processing errors
    #[error("Processing error: {0}")]
    ProcessingError(String),
    
    /// Device access errors
    #[error("Device access error")]
    DeviceAccessError,
    
    /// Timeout errors
    #[error("Operation timeout")]
    TimeoutError,
    
    /// CRC verification errors
    #[error("CRC verification failed")]
    CrcError,
    
    /// Input validation errors
    #[error("Invalid input: {0}")]
    InputValidationError(String),
}

/// Error extension trait for additional error handling capabilities
pub trait ErrorExt {
    /// Determines if the error is potentially recoverable
    fn is_recoverable(&self) -> bool;
    
    /// Provides a detailed error context
    fn context(&self) -> Option<&str>;
}

impl ErrorExt for Lzma2Error {
    fn is_recoverable(&self) -> bool {
        match self {
            Lzma2Error::TimeoutError => true,
            Lzma2Error::TransferError(_) => true,
            Lzma2Error::DeviceInitError(_) => false,
            Lzma2Error::ProcessingError(_) => false,
            Lzma2Error::DeviceAccessError => false,
            Lzma2Error::CrcError => false,
            Lzma2Error::InputValidationError(_) => false,
        }
    }
    
    fn context(&self) -> Option<&str> {
        match self {
            Lzma2Error::DeviceInitError(ctx) => Some(ctx),
            Lzma2Error::TransferError(ctx) => Some(ctx),
            Lzma2Error::ProcessingError(ctx) => Some(ctx),
            Lzma2Error::InputValidationError(ctx) => Some(ctx),
            _ => None
        }
    }
}

/// Convenience result type using Lzma2Error
pub type Lzma2Result<T> = Result<T, Lzma2Error>;
