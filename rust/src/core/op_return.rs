//! OP_RETURN script helpers shared by the wallet API.

use bdk_wallet::bitcoin::script::Instruction;
use bdk_wallet::bitcoin::Script;

/// Concatenate every push payload that follows a leading OP_RETURN opcode.
/// Non-push opcodes and parsing errors are skipped, returning whatever pushed
/// bytes were successfully decoded (may be empty).
///
/// The caller must have already verified that the script is an OP_RETURN
/// (`Script::is_op_return`).
pub fn extract_op_return_payload(script: &Script) -> Vec<u8> {
    let mut out = Vec::new();
    for instr in script.instructions().flatten() {
        if let Instruction::PushBytes(pb) = instr {
            out.extend_from_slice(pb.as_bytes());
        }
    }
    out
}
