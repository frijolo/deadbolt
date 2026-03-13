use thiserror::Error;

#[derive(Error, Debug)]
pub enum WalletError {
    #[error("MissingPolicy")]
    MissingPolicy,
    #[error("MissingSpendPath")]
    MissingSpendPath,
    #[error("MissingThreshold")]
    MissingThreshold,
    #[error("MissingSpendWeight")]
    MissingSpendWeight,
    #[error("MissingFingerprint")]
    MissingFingerprint,
    #[error("UnsupportedDescriptor")]
    UnsupportedDescriptor,
    #[error("UnsupportedKey")]
    UnsupportedKey,
    #[error("UnexpectedError")]
    UnexpectedError,
    #[error("InvalidDescriptorSyntax")]
    InvalidDescriptorSyntax,
    #[error("NetworkDetectionFailed")]
    NetworkDetectionFailed,
    #[error("Single-path descriptor (e.g. /0/*) is not supported. Use <0;1>/* format instead.")]
    SinglePathDescriptor,
    #[error("BuilderError: {0}")]
    BuilderError(String),

    #[error("InvalidAddress: {0}")]
    InvalidAddress(String),

    // Capture direct errors from BDK
    #[error("MiniscriptError: {0}")]
    MiniscriptError(#[from] bdk_wallet::miniscript::Error),
    #[error("DescriptorError: {0}")]
    DescriptorError(#[from] bdk_wallet::descriptor::DescriptorError),
}
