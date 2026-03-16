/// BitBox02 hardware wallet implementation for Android.
///
/// Provides the USB I/O transport layer for Android via tokio channels driven
/// by the Dart dispatch loop. The BTC operations themselves are in `hw/mod.rs`
/// and are shared with the desktop platform.
///
/// ```text
///   Dart side                          Rust side (this module)
///   ─────────────────────────────      ─────────────────────────────────
///   androidHwPollWritePacket()  ◄───── write_tx: Rust→Dart USB packets
///   USB.write(packet)
///   USB.read() → packet
///   androidHwDeliverReadPacket() ────► read_tx: Dart→Rust USB packets
/// ```
use std::sync::OnceLock;

use anyhow::{anyhow, Result};
use async_trait::async_trait;
use tokio::sync::{mpsc, Mutex as TokioMutex};

use bitbox_api::communication::{Error as CommError, ReadWrite, U2fHidCommunication, FIRMWARE_CMD};
use bitbox_api::runtime::TokioRuntime;

// ── Channel infrastructure (shared with Dart dispatch loop) ───────────────────

const CHANNEL_CAP: usize = 32;

struct IoChannels {
    /// Rust → Dart: USB HID packets Rust wants to send to the device.
    /// Unbounded so that ChannelTransport::write() (a sync fn) never blocks or
    /// fails with Full regardless of how many 64-byte U2F chunks a single
    /// protocol message requires.
    write_tx: mpsc::UnboundedSender<Vec<u8>>,
    write_rx: TokioMutex<mpsc::UnboundedReceiver<Vec<u8>>>,
    /// Dart → Rust: USB HID packets received from the device.
    read_tx: mpsc::Sender<Vec<u8>>,
    read_rx: TokioMutex<mpsc::Receiver<Vec<u8>>>,
}

static IO_CHANNELS: OnceLock<IoChannels> = OnceLock::new();

fn io_channels() -> &'static IoChannels {
    IO_CHANNELS.get_or_init(|| {
        let (write_tx, write_rx) = mpsc::unbounded_channel();
        let (read_tx, read_rx) = mpsc::channel(CHANNEL_CAP);
        IoChannels {
            write_tx,
            write_rx: TokioMutex::new(write_rx),
            read_tx,
            read_rx: TokioMutex::new(read_rx),
        }
    })
}

// ── Dart-facing I/O functions ─────────────────────────────────────────────────

/// Called by Dart to deliver a USB HID packet received from the device.
pub async fn deliver_read_packet(data: Vec<u8>) -> Result<()> {
    io_channels()
        .read_tx
        .send(data)
        .await
        .map_err(|_| anyhow!("Read channel closed — no active Android HW session"))
}

/// Called by Dart to retrieve the next USB HID packet Rust wants to write.
///
/// Returns `Some(packet)` when Rust has a packet ready, `None` otherwise.
pub async fn poll_write_packet() -> Option<Vec<u8>> {
    io_channels().write_rx.try_lock().ok()?.try_recv().ok()
}

// ── ChannelTransport: bridges tokio channels to bitbox-api ReadWrite ──────────

/// Adapts the global tokio channels to the synchronous/async `ReadWrite`
/// interface expected by `bitbox-api`.
struct ChannelTransport;

impl bitbox_api::Threading for ChannelTransport {}

#[async_trait]
impl ReadWrite for ChannelTransport {
    /// Enqueue a 64-byte U2F packet for Dart to write to USB (sync, non-blocking).
    ///
    /// Uses an unbounded channel so this never fails with `Full`, regardless of
    /// how many packets a single U2F-framed message requires.
    fn write(&self, msg: &[u8]) -> Result<usize, CommError> {
        io_channels()
            .write_tx
            .send(msg.to_vec())
            .map_err(|_| CommError::Write)?;
        Ok(msg.len())
    }

    /// Signal Dart that a USB read is needed, then wait for the packet.
    ///
    /// An empty `Vec` is enqueued in `write_tx` as a sentinel so the Dart
    /// dispatch loop knows to read USB even though there is no outgoing packet.
    /// The loop distinguishes writes (non-empty) from read-needed (empty).
    async fn read(&self) -> Result<Vec<u8>, CommError> {
        // Unbounded send is sync and infallible (only fails if receiver dropped).
        io_channels()
            .write_tx
            .send(vec![])
            .map_err(|_| CommError::Write)?;
        io_channels()
            .read_rx
            .lock()
            .await
            .recv()
            .await
            .ok_or(CommError::Read)
    }
}

// ── Pending pairing state ─────────────────────────────────────────────────────

struct PendingAndroidPairing {
    session_id: String,
    device_name: String,
    product_string: String,
    pairing: bitbox_api::PairingBitBox<TokioRuntime>,
}

static PENDING_ANDROID_PAIRING: OnceLock<TokioMutex<Option<PendingAndroidPairing>>> =
    OnceLock::new();

fn pending_lock() -> &'static TokioMutex<Option<PendingAndroidPairing>> {
    PENDING_ANDROID_PAIRING.get_or_init(|| TokioMutex::new(None))
}

// ── Pairing flow ──────────────────────────────────────────────────────────────

/// Connect to a BitBox02 and run the Noise XX pairing handshake.
///
/// Returns `(session_id, pairing_code?)`:
/// - `pairing_code = None`    → already trusted, session ready immediately.
/// - `pairing_code = Some(c)` → show `c` to the user, call `wait_confirm`.
pub async fn connect(
    device_name: String,
    noise_dir: String,
    product_string: String,
) -> Result<(String, Option<String>)> {
    // Drain any stale data left in the channels from a previous (failed) session.
    {
        let mut rx = io_channels().write_rx.lock().await;
        while rx.try_recv().is_ok() {}
    }
    {
        let mut rx = io_channels().read_rx.lock().await;
        while rx.try_recv().is_ok() {}
    }

    let safe_key = hex::encode(device_name.as_bytes());
    let device_noise_dir = format!("{noise_dir}/{safe_key}");
    std::fs::create_dir_all(&device_noise_dir)?;

    let noise_config = Box::new(bitbox_api::PersistedNoiseConfig::new(&device_noise_dir));

    let raw: Box<dyn ReadWrite> = Box::new(ChannelTransport);
    let u2f: Box<dyn ReadWrite> = Box::new(U2fHidCommunication::from(raw, FIRMWARE_CMD));

    let bitbox = bitbox_api::BitBox::<TokioRuntime>::from_transport(u2f, noise_config)
        .await
        .map_err(|e| anyhow!("BitBox02 handshake failed: {e}"))?;

    let pairing = bitbox
        .unlock_and_pair()
        .await
        .map_err(|e| anyhow!("BitBox02 unlock failed: {e}"))?;

    let pairing_code = pairing.get_pairing_code();
    let session_id = crate::core::hw::new_session_id();

    if pairing_code.is_none() {
        let paired = pairing
            .wait_confirm()
            .await
            .map_err(|e| anyhow!("BitBox02 confirm failed: {e}"))?;
        crate::core::hw::finish_connection(session_id.clone(), device_name, product_string, paired)
            .await?;
    } else {
        let mut lock = pending_lock().lock().await;
        *lock = Some(PendingAndroidPairing {
            session_id: session_id.clone(),
            device_name,
            product_string,
            pairing,
        });
    }

    Ok((session_id, pairing_code))
}

/// Wait for the user to confirm the pairing code on the device.
pub async fn wait_confirm(session_id: &str) -> Result<()> {
    let pending = {
        let mut lock = pending_lock().lock().await;
        match lock.take() {
            Some(p) if p.session_id == session_id => p,
            other => {
                *lock = other;
                return Err(anyhow!("No pending pairing for session {session_id}"));
            }
        }
    };

    let paired = pending
        .pairing
        .wait_confirm()
        .await
        .map_err(|e| anyhow!("BitBox02 pairing rejected: {e}"))?;

    crate::core::hw::finish_connection(
        session_id.to_string(),
        pending.device_name,
        pending.product_string,
        paired,
    )
    .await
}
