import 'package:deadbolt/src/rust/api/model.dart';

List<APIHotKeyInfo> upsertHotKey(
        List<APIHotKeyInfo> keys, APIHotKeyInfo info) =>
    [...keys.where((k) => k.mfp != info.mfp), info];

List<APIHotKeyInfo> removeHotKey(List<APIHotKeyInfo> keys, String mfp) =>
    keys.where((k) => k.mfp != mfp).toList();
