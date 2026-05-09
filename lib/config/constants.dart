// Deadbolt — Constants centralizados.
//
// Este archivo agrupa valores mágicos y keys que antes estaban dispersos
// en múltiples archivos. Los imports son explícitos, no hay re-exports.

// ── Page size ───────────────────────────────────────────────────────────────

/// Número de transacciones/coins/addresses por página de paginación.
const kPageSize = 25;

// ── Timelock ────────────────────────────────────────────────────────────────

/// Tiempo de retry después de un error transitorio de Electrum (stale data).
const kRetryDelay = Duration(seconds: 15);

/// Umbral dust en sats para outputs.
const kDustThresholdSats = 330;

/// Timelock mínimo por defecto para paths de herencia (bloques).
const kDefaultInheritanceTimelock = 144;

// ── SharedPreferences keys ──────────────────────────────────────────────────

const kElectrumPrivacyWarningHiddenUntilKey = 'electrumPrivacyWarningHiddenUntil';
const kDisclaimerHiddenUntilKey = 'disclaimerHiddenUntil';

// ── Fonts ───────────────────────────────────────────────────────────────────

const kMonospaceFontFamily = 'monospace';
