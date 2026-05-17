/// Characters not allowed in export file names.
final invalidFileNameCharsRegex = RegExp(r'[^\w\s-]');

/// Nominal Bitcoin block interval used for ETA estimates across the UI.
const int kSecondsPerBlock = 600;
