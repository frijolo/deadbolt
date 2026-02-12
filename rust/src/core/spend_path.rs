use std::collections::{BTreeMap, BTreeSet};
use std::sync::Arc;

use anyhow::{Ok, Result};
use bdk_wallet::bitcoin::psbt::Input;
use bdk_wallet::bitcoin::transaction::Version;
use bdk_wallet::bitcoin::{
    ecdsa, taproot, Amount, BlockHash, FeeRate, Network, OutPoint, Psbt, PublicKey, ScriptBuf,
    TapLeafHash, Transaction, TxOut, Txid,
};
use bdk_wallet::chain::{BlockId, CheckPoint, ConfirmationBlockTime};
use bdk_wallet::descriptor::policy::PkOrF;
use bdk_wallet::descriptor::{policy::SatisfiableItem, Policy};
use bdk_wallet::keys::DescriptorPublicKey;
use bdk_wallet::miniscript::descriptor::{Pkh, Sh, Tr, Wpkh, Wsh};
use bdk_wallet::miniscript::Descriptor;
use bdk_wallet::rusqlite::Connection;
#[expect(deprecated)]
use bdk_wallet::SignOptions;
use bdk_wallet::{KeychainKind, PersistedWallet, Update, Wallet};
use secp256k1::hashes::{Hash, sha256, HashEngine};

use crate::core::error::WalletError;

/// Calculate a deterministic ID based on spend path properties
/// This ensures the same spend path always gets the same ID across re-analysis
pub fn calculate_spend_path_id(
    threshold: usize,
    mfps: &[String],
    rel_timelock: u32,
    abs_timelock: u32,
) -> u32 {
    let mut engine = sha256::Hash::engine();

    // Hash threshold
    engine.input(&threshold.to_le_bytes());

    // Hash MFPs in sorted order for consistency
    let mut sorted_mfps: Vec<String> = mfps.iter().cloned().collect();
    sorted_mfps.sort();
    for mfp in sorted_mfps {
        engine.input(mfp.as_bytes());
    }

    // Hash timelocks
    engine.input(&rel_timelock.to_le_bytes());
    engine.input(&abs_timelock.to_le_bytes());

    // Finalize hash and take first 4 bytes as u32
    let hash = sha256::Hash::from_engine(engine);
    let hash_bytes = hash.as_byte_array();
    u32::from_le_bytes([hash_bytes[0], hash_bytes[1], hash_bytes[2], hash_bytes[3]])
}

#[derive(Debug, Clone, Default)]
struct SpendPathBuilder {
    policy_path: BTreeMap<String, Vec<usize>>,

    threshold_setted: bool,
    threshold: Option<usize>,
    mfps: BTreeSet<String>,
    rel_timelock: u32,
    abs_timelock: u32,

    wu_base: Option<u32>,
    wu_in: Option<u32>,
    wu_out: Option<u32>,

    addr_type: Option<String>,
    is_tr_script: bool,
    tr_depth: usize,
}

impl SpendPathBuilder {
    fn new() -> Self {
        let mut new = Self::default();
        new.is_tr_script = false;
        new.threshold_setted = false;
        new
    }

    fn policy_path(&mut self, policy_path: BTreeMap<String, Vec<usize>>) -> &mut Self {
        self.policy_path = policy_path;
        self
    }

    fn add_policy_path(&mut self, root_id: &String, path: &Vec<usize>) -> &mut Self {
        self.policy_path.insert(root_id.clone(), path.clone());
        self
    }

    fn get_threshold(&self) -> Result<usize> {
        self.threshold.ok_or(WalletError::MissingThreshold.into())
    }

    fn threshold(&mut self, threshold: usize) -> Result<&mut Self> {
        if let Some(_) = self.threshold {
            return Err(WalletError::UnsupportedDescriptor.into());
        }

        self.threshold_setted = true;
        self.threshold = Some(threshold);
        Ok(self)
    }

    fn add_threshold(&mut self, threshold: usize) -> Result<&mut Self> {
        if self.threshold_setted {
            return Err(WalletError::UnsupportedDescriptor.into());
        }

        self.threshold = match self.threshold {
            Some(t) => Some(t + threshold),
            None => Some(threshold),
        };
        Ok(self)
    }

    fn add_mfp(&mut self, mfp: String) -> &mut Self {
        self.mfps.insert(mfp);
        self
    }

    fn rel_timelock(&mut self, rel_timelock: u32) -> &mut Self {
        self.rel_timelock = rel_timelock;
        self
    }

    fn abs_timelock(&mut self, abs_timelock: u32) -> &mut Self {
        self.abs_timelock = abs_timelock;
        self
    }

    fn wu_base(&mut self, wu_base: u32) -> &mut Self {
        self.wu_base = Some(wu_base);
        self
    }

    fn wu_in(&mut self, wu_in: u32) -> &mut Self {
        self.wu_in = Some(wu_in);
        self
    }

    fn wu_out(&mut self, wu_out: u32) -> &mut Self {
        self.wu_out = Some(wu_out);
        self
    }

    fn addr_type(&mut self, addr_type: String) -> &mut Self {
        self.addr_type = Some(addr_type);
        self
    }

    /// Calculate a deterministic ID based on spend path properties
    /// This ensures the same spend path always gets the same ID across re-analysis
    fn calculate_id(&self) -> Result<u32> {
        let threshold = self.threshold.ok_or(WalletError::MissingThreshold)?;
        let mfps_vec: Vec<String> = self.mfps.iter().cloned().collect();
        Ok(calculate_spend_path_id(threshold, &mfps_vec, self.rel_timelock, self.abs_timelock))
    }

    fn build(self, id: u32) -> Result<SpendPath> {
        Ok(SpendPath {
            id,
            addr_type: self.addr_type.ok_or(WalletError::UnsupportedDescriptor)?,
            policy_path: self.policy_path,
            threshold: self.threshold.ok_or(WalletError::MissingThreshold)?,
            mfps: (!self.mfps.is_empty())
                .then(|| self.mfps.into_iter().collect())
                .ok_or(WalletError::MissingFingerprint)?,
            rel_timelock: self.rel_timelock,
            abs_timelock: self.abs_timelock,
            wu_base: self.wu_base.ok_or(WalletError::MissingSpendWeight)?,
            wu_in: self.wu_in.ok_or(WalletError::MissingSpendWeight)?,
            wu_out: self.wu_out.ok_or(WalletError::MissingSpendWeight)?,
            tr_depth: self.tr_depth,
        })
    }

    fn build_many(mut spbs: Vec<Self>) -> Result<Vec<SpendPath>> {
        let mut sps = Vec::new();
        while !spbs.is_empty() {
            let spb = spbs.pop().ok_or(WalletError::MissingPolicy)?;
            let id = spb.calculate_id()?;
            sps.push(spb.build(id)?);
        }
        Ok(sps)
    }

    fn from_policies(policy: &Policy) -> Result<Vec<SpendPathBuilder>> {
        Self::_from_policies(policy, false)
    }

    fn from_tr_policies(policy: &Policy) -> Result<Vec<SpendPathBuilder>> {
        Self::_from_policies(policy, true)
    }

    fn _from_policies(policy: &Policy, is_taproot: bool) -> Result<Vec<SpendPathBuilder>> {
        fn policy_finder(
            policy: &Policy,
            policy_path: &mut BTreeMap<String, Vec<usize>>,
            sps: &mut Vec<SpendPathBuilder>,
            force_path: bool,
        ) -> Result<()> {
            if force_path || policy.requires_path() {
                match &policy.item {
                    SatisfiableItem::Thresh {
                        items,
                        threshold: _,
                    } => {
                        for (i, item) in items.iter().enumerate() {
                            policy_path.entry(policy.id.clone()).or_default().push(i);

                            policy_finder(item, policy_path, sps, false)?;

                            if let Some(vec) = policy_path.get_mut(&policy.id) {
                                vec.pop();
                                if vec.is_empty() {
                                    policy_path.remove(&policy.id);
                                }
                            }
                        }
                    }
                    SatisfiableItem::SchnorrSignature(_) | SatisfiableItem::EcdsaSignature(_) => {
                        policy_finder(&policy, policy_path, sps, false)?;
                    }
                    _ => {
                        Err(WalletError::UnsupportedDescriptor)?;
                    }
                };
            } else {
                let mut sp = SpendPathBuilder::from_policy(policy)?;
                sp.policy_path(policy_path.clone());
                sps.push(sp);
            }
            Ok(())
        }

        let mut sps: Vec<SpendPathBuilder> = Vec::new();
        let mut policy_path = BTreeMap::new();
        policy_finder(policy, &mut policy_path, &mut sps, is_taproot)?;
        Ok(sps)
    }

    fn from_policy(policy: &Policy) -> Result<SpendPathBuilder> {
        fn policy_parser(policy: &Policy, sp: &mut SpendPathBuilder) -> Result<()> {
            match &policy.item {
                SatisfiableItem::Thresh { items, threshold } => {
                    if policy.requires_path() {
                        Err(WalletError::UnsupportedDescriptor)?;
                    }
                    if *threshold != items.len() {
                        sp.threshold(*threshold)?;
                    }
                    for item in items {
                        policy_parser(item, sp)?;
                    }
                }
                SatisfiableItem::Multisig { keys, threshold } => {
                    sp.threshold(*threshold)?;
                    for key in keys {
                        sp.add_mfp(fingerprint_of(key)?);
                    }
                }
                SatisfiableItem::SchnorrSignature(key) | SatisfiableItem::EcdsaSignature(key) => {
                    if !sp.threshold_setted {
                        sp.add_threshold(1)?;
                    }
                    sp.add_mfp(fingerprint_of(key)?);
                }
                SatisfiableItem::RelativeTimelock { value } => {
                    sp.rel_timelock(value.to_consensus_u32());
                }
                SatisfiableItem::AbsoluteTimelock { value } => {
                    sp.abs_timelock(value.to_consensus_u32());
                }
                _ => {
                    Err(WalletError::UnsupportedDescriptor)?;
                }
            };
            Ok(())
        }

        let mut spb = Self::new();
        policy_parser(policy, &mut spb)?;
        Ok(spb)
    }
}

#[derive(Debug)]
pub struct SpendPath {
    // For TxBuilder::policy_path
    pub policy_path: BTreeMap<String, Vec<usize>>,

    pub id: u32,

    pub threshold: usize,
    pub mfps: Vec<String>,
    pub rel_timelock: u32,
    pub abs_timelock: u32,

    pub wu_base: u32,
    pub wu_in: u32,
    pub wu_out: u32,

    pub addr_type: String,
    pub tr_depth: usize,
}

impl SpendPath {
    pub fn estimate_tx_vb(&self, inputs: usize, outputs: usize) -> f32 {
        WeightCalc::to_vbytes(Self::estimate_tx_wu(&self, inputs, outputs))
    }

    pub fn estimate_tx_wu(&self, inputs: usize, outputs: usize) -> u32 {
        self.wu_base + (inputs as u32) * self.wu_in + (outputs as u32) * self.wu_out
    }

    /// Extract spend paths from descriptor and network without requiring an existing wallet
    ///
    /// This is the new preferred method that avoids keeping a persistent wallet.
    /// Creates a temporary wallet ONLY for weight calculation, which legitimately
    /// requires transaction building via `build_tx()`.
    ///
    /// This method still creates ONE temporary wallet, but that's significantly
    /// better than the old approach which could create 5-6 wallets for a single analysis.
    pub fn extract_from_descriptor(
        descriptor: &Descriptor<DescriptorPublicKey>,
        network: Network,
    ) -> Result<Vec<SpendPath>> {
        // Create minimal temporary wallet for weight calculation
        // This is unavoidable because WeightCalc uses build_tx()
        let descriptor_str = descriptor.to_string();
        let temp_wallet = Self::create_weight_calc_wallet(&descriptor_str, network)?;

        // Delegate to existing type-specific methods
        // These will use the temporary wallet for both policy extraction and weight calc
        match descriptor {
            Descriptor::Pkh(pkh) => Self::from_pkh_to_spend_paths(pkh, &temp_wallet),
            Descriptor::Sh(sh) => Self::from_sh_to_spend_paths(sh, &temp_wallet),
            Descriptor::Wpkh(wpkh) => Self::from_wpkh_to_spend_paths(wpkh, &temp_wallet),
            Descriptor::Wsh(wsh) => Self::from_wsh_to_spend_paths(wsh, &temp_wallet),
            Descriptor::Tr(tr) => Self::from_tr_to_spend_paths(tr, &temp_wallet),
            _ => Err(WalletError::UnsupportedDescriptor.into()),
        }
    }

    /// Create minimal temporary wallet for weight calculation only
    ///
    /// Weight calculation requires actual transaction building which needs a full wallet.
    /// This is unavoidable but we only create it once and discard it immediately.
    fn create_weight_calc_wallet(descriptor: &str, network: Network) -> Result<Wallet> {
        Wallet::create_from_two_path_descriptor(descriptor.to_string())
            .network(network)
            .create_wallet_no_persist()
            .map_err(Into::into)
    }

    /// Extract spend paths from existing wallet (backward compatibility)
    ///
    /// This method is kept for backward compatibility with existing code
    /// that uses APIWallet. Internally delegates to extract_from_descriptor().
    pub fn extract_spend_paths(wallet: &Wallet) -> Result<Vec<SpendPath>> {
        let descriptor = wallet.public_descriptor(KeychainKind::External);
        let network = wallet.network();
        Self::extract_from_descriptor(&descriptor, network)
    }

    fn from_pkh_to_spend_paths(
        pkh: &Pkh<DescriptorPublicKey>,
        wallet: &Wallet,
    ) -> Result<Vec<SpendPath>> {
        let mut spb = SpendPathBuilder::new();
        spb.add_policy_path(&get_unique_policy_id(wallet)?, &vec![0])
            .threshold(1)?
            .add_mfp(pkh.as_inner().master_fingerprint().to_string())
            .addr_type(String::from("P2PKH"));

        let mut spbs = vec![spb];
        WeightCalc::calc_tx_weight(wallet, &mut spbs)?;

        Ok(SpendPathBuilder::build_many(spbs)?)
    }

    fn from_sh_to_spend_paths(
        _sh: &Sh<DescriptorPublicKey>,
        wallet: &Wallet,
    ) -> Result<Vec<SpendPath>> {
        let policy = get_policy(wallet)?;

        let mut spbs = SpendPathBuilder::from_policies(&policy)?;
        for spb in &mut spbs {
            spb.addr_type(String::from("P2SH"));
        }

        WeightCalc::calc_tx_weight(wallet, &mut spbs)?;
        Ok(SpendPathBuilder::build_many(spbs)?)
    }

    fn from_wpkh_to_spend_paths(
        wpkh: &Wpkh<DescriptorPublicKey>,
        wallet: &Wallet,
    ) -> Result<Vec<SpendPath>> {
        let mut spb = SpendPathBuilder::new();
        spb.add_policy_path(&get_unique_policy_id(wallet)?, &vec![0])
            .threshold(1)?
            .add_mfp(wpkh.as_inner().master_fingerprint().to_string());

        let mut spbs = vec![spb];
        for spb in &mut spbs {
            spb.addr_type(String::from("P2WPKH"));
        }

        WeightCalc::calc_tx_weight(wallet, &mut spbs)?;

        Ok(SpendPathBuilder::build_many(spbs)?)
    }

    fn from_wsh_to_spend_paths(
        _wsh: &Wsh<DescriptorPublicKey>,
        wallet: &Wallet,
    ) -> Result<Vec<SpendPath>> {
        let policy = get_policy(wallet)?;

        let mut spbs = SpendPathBuilder::from_policies(&policy)?;
        for spb in &mut spbs {
            spb.addr_type(String::from("P2WSH"));
        }

        WeightCalc::calc_tx_weight(wallet, &mut spbs)?;
        Ok(SpendPathBuilder::build_many(spbs)?)
    }

    fn from_tr_to_spend_paths(
        tr: &Tr<DescriptorPublicKey>,
        wallet: &Wallet,
    ) -> Result<Vec<SpendPath>> {
        let policy = get_policy(wallet)?;

        let mut spbs: Vec<SpendPathBuilder> = SpendPathBuilder::from_tr_policies(&policy)?;
        for spb in &mut spbs {
            spb.addr_type(String::from("P2TR"));
        }

        // If the internal key is a raw (Single) key (e.g. NUMS unspendable point),
        // remove the key-path spend path — it's not actually spendable.
        let skip_key_path = matches!(tr.internal_key(), DescriptorPublicKey::Single(_));
        if skip_key_path && !spbs.is_empty() {
            spbs.remove(0);
            for spb in spbs.iter_mut() {
                spb.is_tr_script = true;
            }
        } else {
            for (i, spb) in spbs.iter_mut().enumerate() {
                spb.is_tr_script = i != 0;
            }
        }

        WeightCalc::calc_tx_weight(wallet, &mut spbs)?;
        Ok(SpendPathBuilder::build_many(spbs)?)
    }
}

pub struct WeightCalc;

impl WeightCalc {
    fn calc_tx_weight(wallet: &Wallet, spbs: &mut Vec<SpendPathBuilder>) -> Result<()> {
        let (mut fake_wallet, txid) = Self::build_fake_wallet(wallet)?;

        let addr_script_pubkey = fake_wallet
            .next_unused_address(KeychainKind::External)
            .script_pubkey();

        for spb in spbs {
            let tx_1_1 =
                Self::dummy_tx_wu(&mut fake_wallet, spb, &txid, &addr_script_pubkey, 1, 1)?;

            let tx_1_2 =
                Self::dummy_tx_wu(&mut fake_wallet, spb, &txid, &addr_script_pubkey, 1, 2)?;

            let tx_2_1 =
                Self::dummy_tx_wu(&mut fake_wallet, spb, &txid, &addr_script_pubkey, 2, 1)?;

            let input = tx_2_1 - tx_1_1;
            let output = tx_1_2 - tx_1_1;
            let base = tx_1_1 - input - output;

            spb.wu_base(base).wu_in(input).wu_out(output);
        }

        Ok(())
    }

    fn build_fake_wallet(wallet: &Wallet) -> Result<(PersistedWallet<Connection>, Txid)> {
        // New fake wallet to build some TXs
        let mut mem = Connection::open_in_memory()?;
        let mut fake_wallet = Wallet::create(
            wallet.public_descriptor(KeychainKind::External).to_string(),
            wallet.public_descriptor(KeychainKind::Internal).to_string(),
        )
        .network(wallet.network())
        .create_wallet(&mut mem)?;

        // Get the first External address
        let address_info = fake_wallet.reveal_next_address(KeychainKind::External);
        let my_spk = address_info.address.script_pubkey();

        // Build a fake input TX
        let fake_tx = Transaction {
            version: Version::TWO,
            lock_time: bdk_wallet::bitcoin::absolute::LockTime::ZERO,
            input: vec![],
            output: vec![
                TxOut {
                    value: Amount::from_sat(100_000),
                    script_pubkey: my_spk.clone(),
                },
                TxOut {
                    value: Amount::from_sat(100_000),
                    script_pubkey: my_spk.clone(),
                },
                TxOut {
                    value: Amount::from_sat(100_000),
                    script_pubkey: my_spk.clone(),
                },
                TxOut {
                    value: Amount::from_sat(100_000),
                    script_pubkey: my_spk.clone(),
                },
                TxOut {
                    value: Amount::from_sat(100_000),
                    script_pubkey: my_spk.clone(),
                },
            ],
        };
        let txid = fake_tx.compute_txid();

        // Update to insert the TX on wallet
        let mut update = Update::default();

        // Blocks 0 and 1
        let hash0 = bdk_wallet::bitcoin::constants::genesis_block(Network::Signet).block_hash();
        let hash1 = BlockHash::all_zeros();

        let cp0 = CheckPoint::new(BlockId {
            height: 0,
            hash: hash0,
        });
        let cp1 = cp0.insert(BlockId {
            height: 1,
            hash: hash1,
        });
        update.chain = Some(cp1);

        // Insert TX on update
        update.tx_update.txs.push(Arc::new(fake_tx));

        // Tx anchor to block 1
        update.tx_update.anchors.insert((
            ConfirmationBlockTime {
                block_id: BlockId {
                    height: 1,
                    hash: hash1,
                },
                confirmation_time: 1700000000,
            },
            txid,
        ));

        // Apply update to wallet
        fake_wallet.apply_update(update)?;

        Ok((fake_wallet, txid))
    }

    fn dummy_tx_wu(
        wallet: &mut Wallet,
        spb: &mut SpendPathBuilder,
        utxos_txid: &Txid,
        target_address: &ScriptBuf,
        ninputs: usize,
        noutputs: usize,
    ) -> Result<u32> {
        let mut tx_builder = wallet.build_tx();

        tx_builder
            .policy_path(spb.policy_path.clone(), KeychainKind::External)
            .policy_path(spb.policy_path.clone(), KeychainKind::Internal);

        for i in 0..ninputs {
            tx_builder.add_utxo(OutPoint {
                txid: *utxos_txid,
                vout: i as u32,
            })?;
        }

        for _ in 0..(noutputs - 1) {
            tx_builder.add_recipient(target_address.clone(), Amount::from_sat(5_000));
        }

        tx_builder
            .manually_selected_only()
            .drain_to(target_address.clone())
            .fee_rate(FeeRate::from_sat_per_vb(1).ok_or(WalletError::UnsupportedDescriptor)?);

        let mut psbt = tx_builder.finish()?;

        Self::dummy_sig(&mut psbt, spb)?;

        // Calculate resulted WU
        #[expect(deprecated)]
        let sign_options = SignOptions::default();
        let finalized = wallet.finalize_psbt(&mut psbt, sign_options)?;

        if !finalized {
            return Err(WalletError::UnsupportedDescriptor.into());
        }

        let tx = psbt.extract_tx()?;

        //Self::print_witness_forensics(&tx);

        let wu = tx.weight().to_wu();

        if spb.is_tr_script {
            // Analyze first input
            let input = tx.input.first().ok_or(WalletError::UnsupportedDescriptor)?;
            let witness = &input.witness;
            // Last witness is control block
            let control_block_bytes = witness.last().ok_or(WalletError::UnsupportedDescriptor)?;

            let cb_len = control_block_bytes.len();

            // Control block size check
            if cb_len >= 33 && (cb_len - 33) % 32 == 0 {
                spb.tr_depth = ((cb_len - 33) / 32) + 1;
            } else {
                Err(WalletError::UnsupportedDescriptor)?;
            }
        }

        Ok(wu as u32)
    }

    fn dummy_sig(psbt: &mut Psbt, spb: &SpendPathBuilder) -> Result<()> {
        // Dummy signatures
        let dummy_ecdsa: ecdsa::Signature = "3045022100800000000000000000000000000000000000000000000000000000000000000002207fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff01".parse()?;
        // Schnorr signature
        let schnorr_bytes = hex::decode(
            "d45e6105b81093128d2243d6c97a474c106093630f4a475306d649d21469e38f1727725514f9d0c8d5d878783451515202810281200210212002102120021021",
        )?;
        let dummy_schnorr = taproot::Signature::from_slice(&schnorr_bytes)?;

        for input in psbt.inputs.iter_mut() {
            // Add the minimun signatures to satisfy the policy
            let mut available_mfp = spb.mfps.clone();
            let threshold = spb.get_threshold()?;
            while available_mfp.len() > threshold {
                available_mfp.pop_first();
            }

            Self::dummy_sig_input(input, spb, &available_mfp, dummy_ecdsa, dummy_schnorr)?;
        }

        Ok(())
    }

    fn dummy_sig_input(
        input: &mut Input,
        spb: &SpendPathBuilder,
        available_mfp: &BTreeSet<String>,
        dummy_ecdsa: ecdsa::Signature,
        dummy_schnorr: taproot::Signature,
    ) -> Result<()> {
        // Legacy and Segwit
        let keys_to_sign: Vec<PublicKey> = input
            .bip32_derivation
            .iter()
            .filter(|(_, source)| available_mfp.contains(&source.0.to_string()))
            .map(|(&pk, _)| PublicKey::new(pk))
            .collect();

        if !keys_to_sign.is_empty() {
            for pk in keys_to_sign {
                input.partial_sigs.insert(PublicKey::from(pk), dummy_ecdsa);
            }
            return Ok(());
        }

        // Taproot KeyPath
        if !spb.is_tr_script {
            if let Some(internal_key) = input.tap_internal_key {
                let matches = input
                    .tap_key_origins
                    .get(&internal_key)
                    .map(|(_, (mfp, _))| available_mfp.contains(&mfp.to_string()))
                    .ok_or(WalletError::UnsupportedDescriptor)?;

                if matches {
                    input.tap_key_sig = Some(dummy_schnorr);
                    return Ok(());
                }
            }
        }

        // Taproot ScriptPath
        for (_, (leaf_script, leaf_ver)) in &input.tap_scripts {
            let leaf_hash = TapLeafHash::from_script(leaf_script, *leaf_ver);

            let leaf_mfps: BTreeSet<String> = input
                .tap_key_origins
                .iter()
                .filter(|(_, (hashes, _))| hashes.contains(&leaf_hash))
                .map(|(_, (_, (mfp, _)))| mfp.to_string())
                .collect();

            // Only sign leaf that matches 100% with policy mfps
            if spb.mfps == leaf_mfps {
                for (x_only_pk, (hashes, _)) in &input.tap_key_origins {
                    if hashes.contains(&leaf_hash) {
                        input
                            .tap_script_sigs
                            .insert((*x_only_pk, leaf_hash), dummy_schnorr);
                    }
                }
            }
        }

        Ok(())
    }

    pub fn to_vbytes(wu: u32) -> f32 {
        wu as f32 / 4.0
    }
}

fn fingerprint_of(key: &PkOrF) -> Result<String> {
    match key {
        PkOrF::Fingerprint(fp) => Ok(fp.to_string()),
        PkOrF::Pubkey(pk) => {
            let hash = pk.pubkey_hash();
            let bytes: [u8; 4] = hash.to_byte_array()[..4].try_into().unwrap();
            Ok(bdk_wallet::bitcoin::bip32::Fingerprint::from(bytes).to_string())
        }
        PkOrF::XOnlyPubkey(xpk) => {
            let mut compressed = [0u8; 33];
            compressed[0] = 0x02;
            compressed[1..].copy_from_slice(&xpk.serialize());
            let pk = PublicKey::from_slice(&compressed)
                .map_err(|_| WalletError::MissingFingerprint)?;
            let hash = pk.pubkey_hash();
            let bytes: [u8; 4] = hash.to_byte_array()[..4].try_into().unwrap();
            Ok(bdk_wallet::bitcoin::bip32::Fingerprint::from(bytes).to_string())
        }
    }
}

fn get_policy(wallet: &Wallet) -> Result<Policy> {
    wallet
        .policies(KeychainKind::External)?
        .ok_or(WalletError::MissingPolicy.into())
}

fn get_unique_policy_id(wallet: &Wallet) -> Result<String> {
    let policy = get_policy(wallet)?;

    (!policy.requires_path())
        .then(|| policy.id)
        .ok_or(WalletError::MissingPolicy.into())
}
