import 'dart:ffi';

import 'package:sqlite3/open.dart';

/// Call this before any drift database usage in tests to ensure
/// `libsqlite3.so.0` is found on Linux systems that don't have
/// the `-dev` package installed (which provides the `libsqlite3.so` symlink).
void ensureSqlite3() {
  open.overrideFor(OperatingSystem.linux, () {
    return DynamicLibrary.open('libsqlite3.so.0');
  });
}
