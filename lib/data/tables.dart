import 'package:drift/drift.dart';

class Projects extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get descriptor => text()();
  TextColumn get network => text()();
  TextColumn get walletType => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class ProjectKeys extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get projectId => integer().references(Projects, #id)();
  TextColumn get mfp => text()();
  TextColumn get derivationPath => text()();
  TextColumn get xpub => text()();
  TextColumn get customName => text().nullable()();
}

class ProjectSpendPaths extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get projectId => integer().references(Projects, #id)();
  IntColumn get rustId => integer()();
  IntColumn get threshold => integer()();
  TextColumn get mfps => text()(); // JSON array

  // Semantic timelock storage (type + decoded value)
  TextColumn get relTimelockType => text().withDefault(const Constant('blocks'))();
  IntColumn get relTimelockValue => integer().withDefault(const Constant(0))();
  TextColumn get absTimelockType => text().withDefault(const Constant('blocks'))();
  IntColumn get absTimelockValue => integer().withDefault(const Constant(0))();

  IntColumn get wuBase => integer()();

  IntColumn get wuIn => integer()();
  IntColumn get wuOut => integer()();
  IntColumn get trDepth => integer()();
  RealColumn get vbSweep => real()();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  TextColumn get customName => text().nullable()();
}
