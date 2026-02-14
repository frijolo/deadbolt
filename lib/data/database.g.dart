// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ProjectsTable extends Projects with TableInfo<$ProjectsTable, Project> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProjectsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptorMeta = const VerificationMeta(
    'descriptor',
  );
  @override
  late final GeneratedColumn<String> descriptor = GeneratedColumn<String>(
    'descriptor',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _networkMeta = const VerificationMeta(
    'network',
  );
  @override
  late final GeneratedColumn<String> network = GeneratedColumn<String>(
    'network',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _walletTypeMeta = const VerificationMeta(
    'walletType',
  );
  @override
  late final GeneratedColumn<String> walletType = GeneratedColumn<String>(
    'wallet_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    descriptor,
    network,
    walletType,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'projects';
  @override
  VerificationContext validateIntegrity(
    Insertable<Project> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('descriptor')) {
      context.handle(
        _descriptorMeta,
        descriptor.isAcceptableOrUnknown(data['descriptor']!, _descriptorMeta),
      );
    } else if (isInserting) {
      context.missing(_descriptorMeta);
    }
    if (data.containsKey('network')) {
      context.handle(
        _networkMeta,
        network.isAcceptableOrUnknown(data['network']!, _networkMeta),
      );
    } else if (isInserting) {
      context.missing(_networkMeta);
    }
    if (data.containsKey('wallet_type')) {
      context.handle(
        _walletTypeMeta,
        walletType.isAcceptableOrUnknown(data['wallet_type']!, _walletTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_walletTypeMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Project map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Project(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      descriptor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}descriptor'],
      )!,
      network: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}network'],
      )!,
      walletType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}wallet_type'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ProjectsTable createAlias(String alias) {
    return $ProjectsTable(attachedDatabase, alias);
  }
}

class Project extends DataClass implements Insertable<Project> {
  final int id;
  final String name;
  final String descriptor;
  final String network;
  final String walletType;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Project({
    required this.id,
    required this.name,
    required this.descriptor,
    required this.network,
    required this.walletType,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['descriptor'] = Variable<String>(descriptor);
    map['network'] = Variable<String>(network);
    map['wallet_type'] = Variable<String>(walletType);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ProjectsCompanion toCompanion(bool nullToAbsent) {
    return ProjectsCompanion(
      id: Value(id),
      name: Value(name),
      descriptor: Value(descriptor),
      network: Value(network),
      walletType: Value(walletType),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Project.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Project(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      descriptor: serializer.fromJson<String>(json['descriptor']),
      network: serializer.fromJson<String>(json['network']),
      walletType: serializer.fromJson<String>(json['walletType']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'descriptor': serializer.toJson<String>(descriptor),
      'network': serializer.toJson<String>(network),
      'walletType': serializer.toJson<String>(walletType),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Project copyWith({
    int? id,
    String? name,
    String? descriptor,
    String? network,
    String? walletType,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Project(
    id: id ?? this.id,
    name: name ?? this.name,
    descriptor: descriptor ?? this.descriptor,
    network: network ?? this.network,
    walletType: walletType ?? this.walletType,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Project copyWithCompanion(ProjectsCompanion data) {
    return Project(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      descriptor: data.descriptor.present
          ? data.descriptor.value
          : this.descriptor,
      network: data.network.present ? data.network.value : this.network,
      walletType: data.walletType.present
          ? data.walletType.value
          : this.walletType,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Project(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('descriptor: $descriptor, ')
          ..write('network: $network, ')
          ..write('walletType: $walletType, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    descriptor,
    network,
    walletType,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Project &&
          other.id == this.id &&
          other.name == this.name &&
          other.descriptor == this.descriptor &&
          other.network == this.network &&
          other.walletType == this.walletType &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ProjectsCompanion extends UpdateCompanion<Project> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> descriptor;
  final Value<String> network;
  final Value<String> walletType;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const ProjectsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.descriptor = const Value.absent(),
    this.network = const Value.absent(),
    this.walletType = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ProjectsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String descriptor,
    required String network,
    required String walletType,
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : name = Value(name),
       descriptor = Value(descriptor),
       network = Value(network),
       walletType = Value(walletType);
  static Insertable<Project> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? descriptor,
    Expression<String>? network,
    Expression<String>? walletType,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (descriptor != null) 'descriptor': descriptor,
      if (network != null) 'network': network,
      if (walletType != null) 'wallet_type': walletType,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  ProjectsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? descriptor,
    Value<String>? network,
    Value<String>? walletType,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return ProjectsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      descriptor: descriptor ?? this.descriptor,
      network: network ?? this.network,
      walletType: walletType ?? this.walletType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (descriptor.present) {
      map['descriptor'] = Variable<String>(descriptor.value);
    }
    if (network.present) {
      map['network'] = Variable<String>(network.value);
    }
    if (walletType.present) {
      map['wallet_type'] = Variable<String>(walletType.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProjectsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('descriptor: $descriptor, ')
          ..write('network: $network, ')
          ..write('walletType: $walletType, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ProjectKeysTable extends ProjectKeys
    with TableInfo<$ProjectKeysTable, ProjectKey> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProjectKeysTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<int> projectId = GeneratedColumn<int>(
    'project_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES projects (id)',
    ),
  );
  static const VerificationMeta _mfpMeta = const VerificationMeta('mfp');
  @override
  late final GeneratedColumn<String> mfp = GeneratedColumn<String>(
    'mfp',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _derivationPathMeta = const VerificationMeta(
    'derivationPath',
  );
  @override
  late final GeneratedColumn<String> derivationPath = GeneratedColumn<String>(
    'derivation_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _xpubMeta = const VerificationMeta('xpub');
  @override
  late final GeneratedColumn<String> xpub = GeneratedColumn<String>(
    'xpub',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _customNameMeta = const VerificationMeta(
    'customName',
  );
  @override
  late final GeneratedColumn<String> customName = GeneratedColumn<String>(
    'custom_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    projectId,
    mfp,
    derivationPath,
    xpub,
    customName,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'project_keys';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProjectKey> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_projectIdMeta);
    }
    if (data.containsKey('mfp')) {
      context.handle(
        _mfpMeta,
        mfp.isAcceptableOrUnknown(data['mfp']!, _mfpMeta),
      );
    } else if (isInserting) {
      context.missing(_mfpMeta);
    }
    if (data.containsKey('derivation_path')) {
      context.handle(
        _derivationPathMeta,
        derivationPath.isAcceptableOrUnknown(
          data['derivation_path']!,
          _derivationPathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_derivationPathMeta);
    }
    if (data.containsKey('xpub')) {
      context.handle(
        _xpubMeta,
        xpub.isAcceptableOrUnknown(data['xpub']!, _xpubMeta),
      );
    } else if (isInserting) {
      context.missing(_xpubMeta);
    }
    if (data.containsKey('custom_name')) {
      context.handle(
        _customNameMeta,
        customName.isAcceptableOrUnknown(data['custom_name']!, _customNameMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProjectKey map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProjectKey(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}project_id'],
      )!,
      mfp: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mfp'],
      )!,
      derivationPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}derivation_path'],
      )!,
      xpub: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}xpub'],
      )!,
      customName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}custom_name'],
      ),
    );
  }

  @override
  $ProjectKeysTable createAlias(String alias) {
    return $ProjectKeysTable(attachedDatabase, alias);
  }
}

class ProjectKey extends DataClass implements Insertable<ProjectKey> {
  final int id;
  final int projectId;
  final String mfp;
  final String derivationPath;
  final String xpub;
  final String? customName;
  const ProjectKey({
    required this.id,
    required this.projectId,
    required this.mfp,
    required this.derivationPath,
    required this.xpub,
    this.customName,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['project_id'] = Variable<int>(projectId);
    map['mfp'] = Variable<String>(mfp);
    map['derivation_path'] = Variable<String>(derivationPath);
    map['xpub'] = Variable<String>(xpub);
    if (!nullToAbsent || customName != null) {
      map['custom_name'] = Variable<String>(customName);
    }
    return map;
  }

  ProjectKeysCompanion toCompanion(bool nullToAbsent) {
    return ProjectKeysCompanion(
      id: Value(id),
      projectId: Value(projectId),
      mfp: Value(mfp),
      derivationPath: Value(derivationPath),
      xpub: Value(xpub),
      customName: customName == null && nullToAbsent
          ? const Value.absent()
          : Value(customName),
    );
  }

  factory ProjectKey.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProjectKey(
      id: serializer.fromJson<int>(json['id']),
      projectId: serializer.fromJson<int>(json['projectId']),
      mfp: serializer.fromJson<String>(json['mfp']),
      derivationPath: serializer.fromJson<String>(json['derivationPath']),
      xpub: serializer.fromJson<String>(json['xpub']),
      customName: serializer.fromJson<String?>(json['customName']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'projectId': serializer.toJson<int>(projectId),
      'mfp': serializer.toJson<String>(mfp),
      'derivationPath': serializer.toJson<String>(derivationPath),
      'xpub': serializer.toJson<String>(xpub),
      'customName': serializer.toJson<String?>(customName),
    };
  }

  ProjectKey copyWith({
    int? id,
    int? projectId,
    String? mfp,
    String? derivationPath,
    String? xpub,
    Value<String?> customName = const Value.absent(),
  }) => ProjectKey(
    id: id ?? this.id,
    projectId: projectId ?? this.projectId,
    mfp: mfp ?? this.mfp,
    derivationPath: derivationPath ?? this.derivationPath,
    xpub: xpub ?? this.xpub,
    customName: customName.present ? customName.value : this.customName,
  );
  ProjectKey copyWithCompanion(ProjectKeysCompanion data) {
    return ProjectKey(
      id: data.id.present ? data.id.value : this.id,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      mfp: data.mfp.present ? data.mfp.value : this.mfp,
      derivationPath: data.derivationPath.present
          ? data.derivationPath.value
          : this.derivationPath,
      xpub: data.xpub.present ? data.xpub.value : this.xpub,
      customName: data.customName.present
          ? data.customName.value
          : this.customName,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProjectKey(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('mfp: $mfp, ')
          ..write('derivationPath: $derivationPath, ')
          ..write('xpub: $xpub, ')
          ..write('customName: $customName')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, projectId, mfp, derivationPath, xpub, customName);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProjectKey &&
          other.id == this.id &&
          other.projectId == this.projectId &&
          other.mfp == this.mfp &&
          other.derivationPath == this.derivationPath &&
          other.xpub == this.xpub &&
          other.customName == this.customName);
}

class ProjectKeysCompanion extends UpdateCompanion<ProjectKey> {
  final Value<int> id;
  final Value<int> projectId;
  final Value<String> mfp;
  final Value<String> derivationPath;
  final Value<String> xpub;
  final Value<String?> customName;
  const ProjectKeysCompanion({
    this.id = const Value.absent(),
    this.projectId = const Value.absent(),
    this.mfp = const Value.absent(),
    this.derivationPath = const Value.absent(),
    this.xpub = const Value.absent(),
    this.customName = const Value.absent(),
  });
  ProjectKeysCompanion.insert({
    this.id = const Value.absent(),
    required int projectId,
    required String mfp,
    required String derivationPath,
    required String xpub,
    this.customName = const Value.absent(),
  }) : projectId = Value(projectId),
       mfp = Value(mfp),
       derivationPath = Value(derivationPath),
       xpub = Value(xpub);
  static Insertable<ProjectKey> custom({
    Expression<int>? id,
    Expression<int>? projectId,
    Expression<String>? mfp,
    Expression<String>? derivationPath,
    Expression<String>? xpub,
    Expression<String>? customName,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (projectId != null) 'project_id': projectId,
      if (mfp != null) 'mfp': mfp,
      if (derivationPath != null) 'derivation_path': derivationPath,
      if (xpub != null) 'xpub': xpub,
      if (customName != null) 'custom_name': customName,
    });
  }

  ProjectKeysCompanion copyWith({
    Value<int>? id,
    Value<int>? projectId,
    Value<String>? mfp,
    Value<String>? derivationPath,
    Value<String>? xpub,
    Value<String?>? customName,
  }) {
    return ProjectKeysCompanion(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      mfp: mfp ?? this.mfp,
      derivationPath: derivationPath ?? this.derivationPath,
      xpub: xpub ?? this.xpub,
      customName: customName ?? this.customName,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<int>(projectId.value);
    }
    if (mfp.present) {
      map['mfp'] = Variable<String>(mfp.value);
    }
    if (derivationPath.present) {
      map['derivation_path'] = Variable<String>(derivationPath.value);
    }
    if (xpub.present) {
      map['xpub'] = Variable<String>(xpub.value);
    }
    if (customName.present) {
      map['custom_name'] = Variable<String>(customName.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProjectKeysCompanion(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('mfp: $mfp, ')
          ..write('derivationPath: $derivationPath, ')
          ..write('xpub: $xpub, ')
          ..write('customName: $customName')
          ..write(')'))
        .toString();
  }
}

class $ProjectSpendPathsTable extends ProjectSpendPaths
    with TableInfo<$ProjectSpendPathsTable, ProjectSpendPath> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProjectSpendPathsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<int> projectId = GeneratedColumn<int>(
    'project_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES projects (id)',
    ),
  );
  static const VerificationMeta _rustIdMeta = const VerificationMeta('rustId');
  @override
  late final GeneratedColumn<int> rustId = GeneratedColumn<int>(
    'rust_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _thresholdMeta = const VerificationMeta(
    'threshold',
  );
  @override
  late final GeneratedColumn<int> threshold = GeneratedColumn<int>(
    'threshold',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mfpsMeta = const VerificationMeta('mfps');
  @override
  late final GeneratedColumn<String> mfps = GeneratedColumn<String>(
    'mfps',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _relTimelockTypeMeta = const VerificationMeta(
    'relTimelockType',
  );
  @override
  late final GeneratedColumn<String> relTimelockType = GeneratedColumn<String>(
    'rel_timelock_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('blocks'),
  );
  static const VerificationMeta _relTimelockValueMeta = const VerificationMeta(
    'relTimelockValue',
  );
  @override
  late final GeneratedColumn<int> relTimelockValue = GeneratedColumn<int>(
    'rel_timelock_value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _absTimelockTypeMeta = const VerificationMeta(
    'absTimelockType',
  );
  @override
  late final GeneratedColumn<String> absTimelockType = GeneratedColumn<String>(
    'abs_timelock_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('blocks'),
  );
  static const VerificationMeta _absTimelockValueMeta = const VerificationMeta(
    'absTimelockValue',
  );
  @override
  late final GeneratedColumn<int> absTimelockValue = GeneratedColumn<int>(
    'abs_timelock_value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _wuBaseMeta = const VerificationMeta('wuBase');
  @override
  late final GeneratedColumn<int> wuBase = GeneratedColumn<int>(
    'wu_base',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _wuInMeta = const VerificationMeta('wuIn');
  @override
  late final GeneratedColumn<int> wuIn = GeneratedColumn<int>(
    'wu_in',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _wuOutMeta = const VerificationMeta('wuOut');
  @override
  late final GeneratedColumn<int> wuOut = GeneratedColumn<int>(
    'wu_out',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _trDepthMeta = const VerificationMeta(
    'trDepth',
  );
  @override
  late final GeneratedColumn<int> trDepth = GeneratedColumn<int>(
    'tr_depth',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _vbSweepMeta = const VerificationMeta(
    'vbSweep',
  );
  @override
  late final GeneratedColumn<double> vbSweep = GeneratedColumn<double>(
    'vb_sweep',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _customNameMeta = const VerificationMeta(
    'customName',
  );
  @override
  late final GeneratedColumn<String> customName = GeneratedColumn<String>(
    'custom_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    projectId,
    rustId,
    threshold,
    mfps,
    relTimelockType,
    relTimelockValue,
    absTimelockType,
    absTimelockValue,
    wuBase,
    wuIn,
    wuOut,
    trDepth,
    vbSweep,
    customName,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'project_spend_paths';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProjectSpendPath> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_projectIdMeta);
    }
    if (data.containsKey('rust_id')) {
      context.handle(
        _rustIdMeta,
        rustId.isAcceptableOrUnknown(data['rust_id']!, _rustIdMeta),
      );
    } else if (isInserting) {
      context.missing(_rustIdMeta);
    }
    if (data.containsKey('threshold')) {
      context.handle(
        _thresholdMeta,
        threshold.isAcceptableOrUnknown(data['threshold']!, _thresholdMeta),
      );
    } else if (isInserting) {
      context.missing(_thresholdMeta);
    }
    if (data.containsKey('mfps')) {
      context.handle(
        _mfpsMeta,
        mfps.isAcceptableOrUnknown(data['mfps']!, _mfpsMeta),
      );
    } else if (isInserting) {
      context.missing(_mfpsMeta);
    }
    if (data.containsKey('rel_timelock_type')) {
      context.handle(
        _relTimelockTypeMeta,
        relTimelockType.isAcceptableOrUnknown(
          data['rel_timelock_type']!,
          _relTimelockTypeMeta,
        ),
      );
    }
    if (data.containsKey('rel_timelock_value')) {
      context.handle(
        _relTimelockValueMeta,
        relTimelockValue.isAcceptableOrUnknown(
          data['rel_timelock_value']!,
          _relTimelockValueMeta,
        ),
      );
    }
    if (data.containsKey('abs_timelock_type')) {
      context.handle(
        _absTimelockTypeMeta,
        absTimelockType.isAcceptableOrUnknown(
          data['abs_timelock_type']!,
          _absTimelockTypeMeta,
        ),
      );
    }
    if (data.containsKey('abs_timelock_value')) {
      context.handle(
        _absTimelockValueMeta,
        absTimelockValue.isAcceptableOrUnknown(
          data['abs_timelock_value']!,
          _absTimelockValueMeta,
        ),
      );
    }
    if (data.containsKey('wu_base')) {
      context.handle(
        _wuBaseMeta,
        wuBase.isAcceptableOrUnknown(data['wu_base']!, _wuBaseMeta),
      );
    } else if (isInserting) {
      context.missing(_wuBaseMeta);
    }
    if (data.containsKey('wu_in')) {
      context.handle(
        _wuInMeta,
        wuIn.isAcceptableOrUnknown(data['wu_in']!, _wuInMeta),
      );
    } else if (isInserting) {
      context.missing(_wuInMeta);
    }
    if (data.containsKey('wu_out')) {
      context.handle(
        _wuOutMeta,
        wuOut.isAcceptableOrUnknown(data['wu_out']!, _wuOutMeta),
      );
    } else if (isInserting) {
      context.missing(_wuOutMeta);
    }
    if (data.containsKey('tr_depth')) {
      context.handle(
        _trDepthMeta,
        trDepth.isAcceptableOrUnknown(data['tr_depth']!, _trDepthMeta),
      );
    } else if (isInserting) {
      context.missing(_trDepthMeta);
    }
    if (data.containsKey('vb_sweep')) {
      context.handle(
        _vbSweepMeta,
        vbSweep.isAcceptableOrUnknown(data['vb_sweep']!, _vbSweepMeta),
      );
    } else if (isInserting) {
      context.missing(_vbSweepMeta);
    }
    if (data.containsKey('custom_name')) {
      context.handle(
        _customNameMeta,
        customName.isAcceptableOrUnknown(data['custom_name']!, _customNameMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProjectSpendPath map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProjectSpendPath(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}project_id'],
      )!,
      rustId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rust_id'],
      )!,
      threshold: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}threshold'],
      )!,
      mfps: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mfps'],
      )!,
      relTimelockType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rel_timelock_type'],
      )!,
      relTimelockValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rel_timelock_value'],
      )!,
      absTimelockType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}abs_timelock_type'],
      )!,
      absTimelockValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}abs_timelock_value'],
      )!,
      wuBase: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}wu_base'],
      )!,
      wuIn: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}wu_in'],
      )!,
      wuOut: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}wu_out'],
      )!,
      trDepth: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tr_depth'],
      )!,
      vbSweep: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}vb_sweep'],
      )!,
      customName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}custom_name'],
      ),
    );
  }

  @override
  $ProjectSpendPathsTable createAlias(String alias) {
    return $ProjectSpendPathsTable(attachedDatabase, alias);
  }
}

class ProjectSpendPath extends DataClass
    implements Insertable<ProjectSpendPath> {
  final int id;
  final int projectId;
  final int rustId;
  final int threshold;
  final String mfps;
  final String relTimelockType;
  final int relTimelockValue;
  final String absTimelockType;
  final int absTimelockValue;
  final int wuBase;
  final int wuIn;
  final int wuOut;
  final int trDepth;
  final double vbSweep;
  final String? customName;
  const ProjectSpendPath({
    required this.id,
    required this.projectId,
    required this.rustId,
    required this.threshold,
    required this.mfps,
    required this.relTimelockType,
    required this.relTimelockValue,
    required this.absTimelockType,
    required this.absTimelockValue,
    required this.wuBase,
    required this.wuIn,
    required this.wuOut,
    required this.trDepth,
    required this.vbSweep,
    this.customName,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['project_id'] = Variable<int>(projectId);
    map['rust_id'] = Variable<int>(rustId);
    map['threshold'] = Variable<int>(threshold);
    map['mfps'] = Variable<String>(mfps);
    map['rel_timelock_type'] = Variable<String>(relTimelockType);
    map['rel_timelock_value'] = Variable<int>(relTimelockValue);
    map['abs_timelock_type'] = Variable<String>(absTimelockType);
    map['abs_timelock_value'] = Variable<int>(absTimelockValue);
    map['wu_base'] = Variable<int>(wuBase);
    map['wu_in'] = Variable<int>(wuIn);
    map['wu_out'] = Variable<int>(wuOut);
    map['tr_depth'] = Variable<int>(trDepth);
    map['vb_sweep'] = Variable<double>(vbSweep);
    if (!nullToAbsent || customName != null) {
      map['custom_name'] = Variable<String>(customName);
    }
    return map;
  }

  ProjectSpendPathsCompanion toCompanion(bool nullToAbsent) {
    return ProjectSpendPathsCompanion(
      id: Value(id),
      projectId: Value(projectId),
      rustId: Value(rustId),
      threshold: Value(threshold),
      mfps: Value(mfps),
      relTimelockType: Value(relTimelockType),
      relTimelockValue: Value(relTimelockValue),
      absTimelockType: Value(absTimelockType),
      absTimelockValue: Value(absTimelockValue),
      wuBase: Value(wuBase),
      wuIn: Value(wuIn),
      wuOut: Value(wuOut),
      trDepth: Value(trDepth),
      vbSweep: Value(vbSweep),
      customName: customName == null && nullToAbsent
          ? const Value.absent()
          : Value(customName),
    );
  }

  factory ProjectSpendPath.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProjectSpendPath(
      id: serializer.fromJson<int>(json['id']),
      projectId: serializer.fromJson<int>(json['projectId']),
      rustId: serializer.fromJson<int>(json['rustId']),
      threshold: serializer.fromJson<int>(json['threshold']),
      mfps: serializer.fromJson<String>(json['mfps']),
      relTimelockType: serializer.fromJson<String>(json['relTimelockType']),
      relTimelockValue: serializer.fromJson<int>(json['relTimelockValue']),
      absTimelockType: serializer.fromJson<String>(json['absTimelockType']),
      absTimelockValue: serializer.fromJson<int>(json['absTimelockValue']),
      wuBase: serializer.fromJson<int>(json['wuBase']),
      wuIn: serializer.fromJson<int>(json['wuIn']),
      wuOut: serializer.fromJson<int>(json['wuOut']),
      trDepth: serializer.fromJson<int>(json['trDepth']),
      vbSweep: serializer.fromJson<double>(json['vbSweep']),
      customName: serializer.fromJson<String?>(json['customName']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'projectId': serializer.toJson<int>(projectId),
      'rustId': serializer.toJson<int>(rustId),
      'threshold': serializer.toJson<int>(threshold),
      'mfps': serializer.toJson<String>(mfps),
      'relTimelockType': serializer.toJson<String>(relTimelockType),
      'relTimelockValue': serializer.toJson<int>(relTimelockValue),
      'absTimelockType': serializer.toJson<String>(absTimelockType),
      'absTimelockValue': serializer.toJson<int>(absTimelockValue),
      'wuBase': serializer.toJson<int>(wuBase),
      'wuIn': serializer.toJson<int>(wuIn),
      'wuOut': serializer.toJson<int>(wuOut),
      'trDepth': serializer.toJson<int>(trDepth),
      'vbSweep': serializer.toJson<double>(vbSweep),
      'customName': serializer.toJson<String?>(customName),
    };
  }

  ProjectSpendPath copyWith({
    int? id,
    int? projectId,
    int? rustId,
    int? threshold,
    String? mfps,
    String? relTimelockType,
    int? relTimelockValue,
    String? absTimelockType,
    int? absTimelockValue,
    int? wuBase,
    int? wuIn,
    int? wuOut,
    int? trDepth,
    double? vbSweep,
    Value<String?> customName = const Value.absent(),
  }) => ProjectSpendPath(
    id: id ?? this.id,
    projectId: projectId ?? this.projectId,
    rustId: rustId ?? this.rustId,
    threshold: threshold ?? this.threshold,
    mfps: mfps ?? this.mfps,
    relTimelockType: relTimelockType ?? this.relTimelockType,
    relTimelockValue: relTimelockValue ?? this.relTimelockValue,
    absTimelockType: absTimelockType ?? this.absTimelockType,
    absTimelockValue: absTimelockValue ?? this.absTimelockValue,
    wuBase: wuBase ?? this.wuBase,
    wuIn: wuIn ?? this.wuIn,
    wuOut: wuOut ?? this.wuOut,
    trDepth: trDepth ?? this.trDepth,
    vbSweep: vbSweep ?? this.vbSweep,
    customName: customName.present ? customName.value : this.customName,
  );
  ProjectSpendPath copyWithCompanion(ProjectSpendPathsCompanion data) {
    return ProjectSpendPath(
      id: data.id.present ? data.id.value : this.id,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      rustId: data.rustId.present ? data.rustId.value : this.rustId,
      threshold: data.threshold.present ? data.threshold.value : this.threshold,
      mfps: data.mfps.present ? data.mfps.value : this.mfps,
      relTimelockType: data.relTimelockType.present
          ? data.relTimelockType.value
          : this.relTimelockType,
      relTimelockValue: data.relTimelockValue.present
          ? data.relTimelockValue.value
          : this.relTimelockValue,
      absTimelockType: data.absTimelockType.present
          ? data.absTimelockType.value
          : this.absTimelockType,
      absTimelockValue: data.absTimelockValue.present
          ? data.absTimelockValue.value
          : this.absTimelockValue,
      wuBase: data.wuBase.present ? data.wuBase.value : this.wuBase,
      wuIn: data.wuIn.present ? data.wuIn.value : this.wuIn,
      wuOut: data.wuOut.present ? data.wuOut.value : this.wuOut,
      trDepth: data.trDepth.present ? data.trDepth.value : this.trDepth,
      vbSweep: data.vbSweep.present ? data.vbSweep.value : this.vbSweep,
      customName: data.customName.present
          ? data.customName.value
          : this.customName,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProjectSpendPath(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('rustId: $rustId, ')
          ..write('threshold: $threshold, ')
          ..write('mfps: $mfps, ')
          ..write('relTimelockType: $relTimelockType, ')
          ..write('relTimelockValue: $relTimelockValue, ')
          ..write('absTimelockType: $absTimelockType, ')
          ..write('absTimelockValue: $absTimelockValue, ')
          ..write('wuBase: $wuBase, ')
          ..write('wuIn: $wuIn, ')
          ..write('wuOut: $wuOut, ')
          ..write('trDepth: $trDepth, ')
          ..write('vbSweep: $vbSweep, ')
          ..write('customName: $customName')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    projectId,
    rustId,
    threshold,
    mfps,
    relTimelockType,
    relTimelockValue,
    absTimelockType,
    absTimelockValue,
    wuBase,
    wuIn,
    wuOut,
    trDepth,
    vbSweep,
    customName,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProjectSpendPath &&
          other.id == this.id &&
          other.projectId == this.projectId &&
          other.rustId == this.rustId &&
          other.threshold == this.threshold &&
          other.mfps == this.mfps &&
          other.relTimelockType == this.relTimelockType &&
          other.relTimelockValue == this.relTimelockValue &&
          other.absTimelockType == this.absTimelockType &&
          other.absTimelockValue == this.absTimelockValue &&
          other.wuBase == this.wuBase &&
          other.wuIn == this.wuIn &&
          other.wuOut == this.wuOut &&
          other.trDepth == this.trDepth &&
          other.vbSweep == this.vbSweep &&
          other.customName == this.customName);
}

class ProjectSpendPathsCompanion extends UpdateCompanion<ProjectSpendPath> {
  final Value<int> id;
  final Value<int> projectId;
  final Value<int> rustId;
  final Value<int> threshold;
  final Value<String> mfps;
  final Value<String> relTimelockType;
  final Value<int> relTimelockValue;
  final Value<String> absTimelockType;
  final Value<int> absTimelockValue;
  final Value<int> wuBase;
  final Value<int> wuIn;
  final Value<int> wuOut;
  final Value<int> trDepth;
  final Value<double> vbSweep;
  final Value<String?> customName;
  const ProjectSpendPathsCompanion({
    this.id = const Value.absent(),
    this.projectId = const Value.absent(),
    this.rustId = const Value.absent(),
    this.threshold = const Value.absent(),
    this.mfps = const Value.absent(),
    this.relTimelockType = const Value.absent(),
    this.relTimelockValue = const Value.absent(),
    this.absTimelockType = const Value.absent(),
    this.absTimelockValue = const Value.absent(),
    this.wuBase = const Value.absent(),
    this.wuIn = const Value.absent(),
    this.wuOut = const Value.absent(),
    this.trDepth = const Value.absent(),
    this.vbSweep = const Value.absent(),
    this.customName = const Value.absent(),
  });
  ProjectSpendPathsCompanion.insert({
    this.id = const Value.absent(),
    required int projectId,
    required int rustId,
    required int threshold,
    required String mfps,
    this.relTimelockType = const Value.absent(),
    this.relTimelockValue = const Value.absent(),
    this.absTimelockType = const Value.absent(),
    this.absTimelockValue = const Value.absent(),
    required int wuBase,
    required int wuIn,
    required int wuOut,
    required int trDepth,
    required double vbSweep,
    this.customName = const Value.absent(),
  }) : projectId = Value(projectId),
       rustId = Value(rustId),
       threshold = Value(threshold),
       mfps = Value(mfps),
       wuBase = Value(wuBase),
       wuIn = Value(wuIn),
       wuOut = Value(wuOut),
       trDepth = Value(trDepth),
       vbSweep = Value(vbSweep);
  static Insertable<ProjectSpendPath> custom({
    Expression<int>? id,
    Expression<int>? projectId,
    Expression<int>? rustId,
    Expression<int>? threshold,
    Expression<String>? mfps,
    Expression<String>? relTimelockType,
    Expression<int>? relTimelockValue,
    Expression<String>? absTimelockType,
    Expression<int>? absTimelockValue,
    Expression<int>? wuBase,
    Expression<int>? wuIn,
    Expression<int>? wuOut,
    Expression<int>? trDepth,
    Expression<double>? vbSweep,
    Expression<String>? customName,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (projectId != null) 'project_id': projectId,
      if (rustId != null) 'rust_id': rustId,
      if (threshold != null) 'threshold': threshold,
      if (mfps != null) 'mfps': mfps,
      if (relTimelockType != null) 'rel_timelock_type': relTimelockType,
      if (relTimelockValue != null) 'rel_timelock_value': relTimelockValue,
      if (absTimelockType != null) 'abs_timelock_type': absTimelockType,
      if (absTimelockValue != null) 'abs_timelock_value': absTimelockValue,
      if (wuBase != null) 'wu_base': wuBase,
      if (wuIn != null) 'wu_in': wuIn,
      if (wuOut != null) 'wu_out': wuOut,
      if (trDepth != null) 'tr_depth': trDepth,
      if (vbSweep != null) 'vb_sweep': vbSweep,
      if (customName != null) 'custom_name': customName,
    });
  }

  ProjectSpendPathsCompanion copyWith({
    Value<int>? id,
    Value<int>? projectId,
    Value<int>? rustId,
    Value<int>? threshold,
    Value<String>? mfps,
    Value<String>? relTimelockType,
    Value<int>? relTimelockValue,
    Value<String>? absTimelockType,
    Value<int>? absTimelockValue,
    Value<int>? wuBase,
    Value<int>? wuIn,
    Value<int>? wuOut,
    Value<int>? trDepth,
    Value<double>? vbSweep,
    Value<String?>? customName,
  }) {
    return ProjectSpendPathsCompanion(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      rustId: rustId ?? this.rustId,
      threshold: threshold ?? this.threshold,
      mfps: mfps ?? this.mfps,
      relTimelockType: relTimelockType ?? this.relTimelockType,
      relTimelockValue: relTimelockValue ?? this.relTimelockValue,
      absTimelockType: absTimelockType ?? this.absTimelockType,
      absTimelockValue: absTimelockValue ?? this.absTimelockValue,
      wuBase: wuBase ?? this.wuBase,
      wuIn: wuIn ?? this.wuIn,
      wuOut: wuOut ?? this.wuOut,
      trDepth: trDepth ?? this.trDepth,
      vbSweep: vbSweep ?? this.vbSweep,
      customName: customName ?? this.customName,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<int>(projectId.value);
    }
    if (rustId.present) {
      map['rust_id'] = Variable<int>(rustId.value);
    }
    if (threshold.present) {
      map['threshold'] = Variable<int>(threshold.value);
    }
    if (mfps.present) {
      map['mfps'] = Variable<String>(mfps.value);
    }
    if (relTimelockType.present) {
      map['rel_timelock_type'] = Variable<String>(relTimelockType.value);
    }
    if (relTimelockValue.present) {
      map['rel_timelock_value'] = Variable<int>(relTimelockValue.value);
    }
    if (absTimelockType.present) {
      map['abs_timelock_type'] = Variable<String>(absTimelockType.value);
    }
    if (absTimelockValue.present) {
      map['abs_timelock_value'] = Variable<int>(absTimelockValue.value);
    }
    if (wuBase.present) {
      map['wu_base'] = Variable<int>(wuBase.value);
    }
    if (wuIn.present) {
      map['wu_in'] = Variable<int>(wuIn.value);
    }
    if (wuOut.present) {
      map['wu_out'] = Variable<int>(wuOut.value);
    }
    if (trDepth.present) {
      map['tr_depth'] = Variable<int>(trDepth.value);
    }
    if (vbSweep.present) {
      map['vb_sweep'] = Variable<double>(vbSweep.value);
    }
    if (customName.present) {
      map['custom_name'] = Variable<String>(customName.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProjectSpendPathsCompanion(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('rustId: $rustId, ')
          ..write('threshold: $threshold, ')
          ..write('mfps: $mfps, ')
          ..write('relTimelockType: $relTimelockType, ')
          ..write('relTimelockValue: $relTimelockValue, ')
          ..write('absTimelockType: $absTimelockType, ')
          ..write('absTimelockValue: $absTimelockValue, ')
          ..write('wuBase: $wuBase, ')
          ..write('wuIn: $wuIn, ')
          ..write('wuOut: $wuOut, ')
          ..write('trDepth: $trDepth, ')
          ..write('vbSweep: $vbSweep, ')
          ..write('customName: $customName')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ProjectsTable projects = $ProjectsTable(this);
  late final $ProjectKeysTable projectKeys = $ProjectKeysTable(this);
  late final $ProjectSpendPathsTable projectSpendPaths =
      $ProjectSpendPathsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    projects,
    projectKeys,
    projectSpendPaths,
  ];
}

typedef $$ProjectsTableCreateCompanionBuilder =
    ProjectsCompanion Function({
      Value<int> id,
      required String name,
      required String descriptor,
      required String network,
      required String walletType,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$ProjectsTableUpdateCompanionBuilder =
    ProjectsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> descriptor,
      Value<String> network,
      Value<String> walletType,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

final class $$ProjectsTableReferences
    extends BaseReferences<_$AppDatabase, $ProjectsTable, Project> {
  $$ProjectsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ProjectKeysTable, List<ProjectKey>>
  _projectKeysRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.projectKeys,
    aliasName: $_aliasNameGenerator(db.projects.id, db.projectKeys.projectId),
  );

  $$ProjectKeysTableProcessedTableManager get projectKeysRefs {
    final manager = $$ProjectKeysTableTableManager(
      $_db,
      $_db.projectKeys,
    ).filter((f) => f.projectId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_projectKeysRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ProjectSpendPathsTable, List<ProjectSpendPath>>
  _projectSpendPathsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.projectSpendPaths,
        aliasName: $_aliasNameGenerator(
          db.projects.id,
          db.projectSpendPaths.projectId,
        ),
      );

  $$ProjectSpendPathsTableProcessedTableManager get projectSpendPathsRefs {
    final manager = $$ProjectSpendPathsTableTableManager(
      $_db,
      $_db.projectSpendPaths,
    ).filter((f) => f.projectId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _projectSpendPathsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ProjectsTableFilterComposer
    extends Composer<_$AppDatabase, $ProjectsTable> {
  $$ProjectsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get descriptor => $composableBuilder(
    column: $table.descriptor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get network => $composableBuilder(
    column: $table.network,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get walletType => $composableBuilder(
    column: $table.walletType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> projectKeysRefs(
    Expression<bool> Function($$ProjectKeysTableFilterComposer f) f,
  ) {
    final $$ProjectKeysTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.projectKeys,
      getReferencedColumn: (t) => t.projectId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectKeysTableFilterComposer(
            $db: $db,
            $table: $db.projectKeys,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> projectSpendPathsRefs(
    Expression<bool> Function($$ProjectSpendPathsTableFilterComposer f) f,
  ) {
    final $$ProjectSpendPathsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.projectSpendPaths,
      getReferencedColumn: (t) => t.projectId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectSpendPathsTableFilterComposer(
            $db: $db,
            $table: $db.projectSpendPaths,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ProjectsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProjectsTable> {
  $$ProjectsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get descriptor => $composableBuilder(
    column: $table.descriptor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get network => $composableBuilder(
    column: $table.network,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get walletType => $composableBuilder(
    column: $table.walletType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProjectsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProjectsTable> {
  $$ProjectsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get descriptor => $composableBuilder(
    column: $table.descriptor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get network =>
      $composableBuilder(column: $table.network, builder: (column) => column);

  GeneratedColumn<String> get walletType => $composableBuilder(
    column: $table.walletType,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> projectKeysRefs<T extends Object>(
    Expression<T> Function($$ProjectKeysTableAnnotationComposer a) f,
  ) {
    final $$ProjectKeysTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.projectKeys,
      getReferencedColumn: (t) => t.projectId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectKeysTableAnnotationComposer(
            $db: $db,
            $table: $db.projectKeys,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> projectSpendPathsRefs<T extends Object>(
    Expression<T> Function($$ProjectSpendPathsTableAnnotationComposer a) f,
  ) {
    final $$ProjectSpendPathsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.projectSpendPaths,
          getReferencedColumn: (t) => t.projectId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ProjectSpendPathsTableAnnotationComposer(
                $db: $db,
                $table: $db.projectSpendPaths,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ProjectsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProjectsTable,
          Project,
          $$ProjectsTableFilterComposer,
          $$ProjectsTableOrderingComposer,
          $$ProjectsTableAnnotationComposer,
          $$ProjectsTableCreateCompanionBuilder,
          $$ProjectsTableUpdateCompanionBuilder,
          (Project, $$ProjectsTableReferences),
          Project,
          PrefetchHooks Function({
            bool projectKeysRefs,
            bool projectSpendPathsRefs,
          })
        > {
  $$ProjectsTableTableManager(_$AppDatabase db, $ProjectsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProjectsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProjectsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProjectsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> descriptor = const Value.absent(),
                Value<String> network = const Value.absent(),
                Value<String> walletType = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => ProjectsCompanion(
                id: id,
                name: name,
                descriptor: descriptor,
                network: network,
                walletType: walletType,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required String descriptor,
                required String network,
                required String walletType,
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => ProjectsCompanion.insert(
                id: id,
                name: name,
                descriptor: descriptor,
                network: network,
                walletType: walletType,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ProjectsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({projectKeysRefs = false, projectSpendPathsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (projectKeysRefs) db.projectKeys,
                    if (projectSpendPathsRefs) db.projectSpendPaths,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (projectKeysRefs)
                        await $_getPrefetchedData<
                          Project,
                          $ProjectsTable,
                          ProjectKey
                        >(
                          currentTable: table,
                          referencedTable: $$ProjectsTableReferences
                              ._projectKeysRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProjectsTableReferences(
                                db,
                                table,
                                p0,
                              ).projectKeysRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.projectId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (projectSpendPathsRefs)
                        await $_getPrefetchedData<
                          Project,
                          $ProjectsTable,
                          ProjectSpendPath
                        >(
                          currentTable: table,
                          referencedTable: $$ProjectsTableReferences
                              ._projectSpendPathsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProjectsTableReferences(
                                db,
                                table,
                                p0,
                              ).projectSpendPathsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.projectId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ProjectsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProjectsTable,
      Project,
      $$ProjectsTableFilterComposer,
      $$ProjectsTableOrderingComposer,
      $$ProjectsTableAnnotationComposer,
      $$ProjectsTableCreateCompanionBuilder,
      $$ProjectsTableUpdateCompanionBuilder,
      (Project, $$ProjectsTableReferences),
      Project,
      PrefetchHooks Function({bool projectKeysRefs, bool projectSpendPathsRefs})
    >;
typedef $$ProjectKeysTableCreateCompanionBuilder =
    ProjectKeysCompanion Function({
      Value<int> id,
      required int projectId,
      required String mfp,
      required String derivationPath,
      required String xpub,
      Value<String?> customName,
    });
typedef $$ProjectKeysTableUpdateCompanionBuilder =
    ProjectKeysCompanion Function({
      Value<int> id,
      Value<int> projectId,
      Value<String> mfp,
      Value<String> derivationPath,
      Value<String> xpub,
      Value<String?> customName,
    });

final class $$ProjectKeysTableReferences
    extends BaseReferences<_$AppDatabase, $ProjectKeysTable, ProjectKey> {
  $$ProjectKeysTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ProjectsTable _projectIdTable(_$AppDatabase db) =>
      db.projects.createAlias(
        $_aliasNameGenerator(db.projectKeys.projectId, db.projects.id),
      );

  $$ProjectsTableProcessedTableManager get projectId {
    final $_column = $_itemColumn<int>('project_id')!;

    final manager = $$ProjectsTableTableManager(
      $_db,
      $_db.projects,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_projectIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ProjectKeysTableFilterComposer
    extends Composer<_$AppDatabase, $ProjectKeysTable> {
  $$ProjectKeysTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mfp => $composableBuilder(
    column: $table.mfp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get derivationPath => $composableBuilder(
    column: $table.derivationPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get xpub => $composableBuilder(
    column: $table.xpub,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customName => $composableBuilder(
    column: $table.customName,
    builder: (column) => ColumnFilters(column),
  );

  $$ProjectsTableFilterComposer get projectId {
    final $$ProjectsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableFilterComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProjectKeysTableOrderingComposer
    extends Composer<_$AppDatabase, $ProjectKeysTable> {
  $$ProjectKeysTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mfp => $composableBuilder(
    column: $table.mfp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get derivationPath => $composableBuilder(
    column: $table.derivationPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get xpub => $composableBuilder(
    column: $table.xpub,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customName => $composableBuilder(
    column: $table.customName,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProjectsTableOrderingComposer get projectId {
    final $$ProjectsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableOrderingComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProjectKeysTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProjectKeysTable> {
  $$ProjectKeysTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get mfp =>
      $composableBuilder(column: $table.mfp, builder: (column) => column);

  GeneratedColumn<String> get derivationPath => $composableBuilder(
    column: $table.derivationPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get xpub =>
      $composableBuilder(column: $table.xpub, builder: (column) => column);

  GeneratedColumn<String> get customName => $composableBuilder(
    column: $table.customName,
    builder: (column) => column,
  );

  $$ProjectsTableAnnotationComposer get projectId {
    final $$ProjectsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableAnnotationComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProjectKeysTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProjectKeysTable,
          ProjectKey,
          $$ProjectKeysTableFilterComposer,
          $$ProjectKeysTableOrderingComposer,
          $$ProjectKeysTableAnnotationComposer,
          $$ProjectKeysTableCreateCompanionBuilder,
          $$ProjectKeysTableUpdateCompanionBuilder,
          (ProjectKey, $$ProjectKeysTableReferences),
          ProjectKey,
          PrefetchHooks Function({bool projectId})
        > {
  $$ProjectKeysTableTableManager(_$AppDatabase db, $ProjectKeysTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProjectKeysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProjectKeysTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProjectKeysTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> projectId = const Value.absent(),
                Value<String> mfp = const Value.absent(),
                Value<String> derivationPath = const Value.absent(),
                Value<String> xpub = const Value.absent(),
                Value<String?> customName = const Value.absent(),
              }) => ProjectKeysCompanion(
                id: id,
                projectId: projectId,
                mfp: mfp,
                derivationPath: derivationPath,
                xpub: xpub,
                customName: customName,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int projectId,
                required String mfp,
                required String derivationPath,
                required String xpub,
                Value<String?> customName = const Value.absent(),
              }) => ProjectKeysCompanion.insert(
                id: id,
                projectId: projectId,
                mfp: mfp,
                derivationPath: derivationPath,
                xpub: xpub,
                customName: customName,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ProjectKeysTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({projectId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (projectId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.projectId,
                                referencedTable: $$ProjectKeysTableReferences
                                    ._projectIdTable(db),
                                referencedColumn: $$ProjectKeysTableReferences
                                    ._projectIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ProjectKeysTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProjectKeysTable,
      ProjectKey,
      $$ProjectKeysTableFilterComposer,
      $$ProjectKeysTableOrderingComposer,
      $$ProjectKeysTableAnnotationComposer,
      $$ProjectKeysTableCreateCompanionBuilder,
      $$ProjectKeysTableUpdateCompanionBuilder,
      (ProjectKey, $$ProjectKeysTableReferences),
      ProjectKey,
      PrefetchHooks Function({bool projectId})
    >;
typedef $$ProjectSpendPathsTableCreateCompanionBuilder =
    ProjectSpendPathsCompanion Function({
      Value<int> id,
      required int projectId,
      required int rustId,
      required int threshold,
      required String mfps,
      Value<String> relTimelockType,
      Value<int> relTimelockValue,
      Value<String> absTimelockType,
      Value<int> absTimelockValue,
      required int wuBase,
      required int wuIn,
      required int wuOut,
      required int trDepth,
      required double vbSweep,
      Value<String?> customName,
    });
typedef $$ProjectSpendPathsTableUpdateCompanionBuilder =
    ProjectSpendPathsCompanion Function({
      Value<int> id,
      Value<int> projectId,
      Value<int> rustId,
      Value<int> threshold,
      Value<String> mfps,
      Value<String> relTimelockType,
      Value<int> relTimelockValue,
      Value<String> absTimelockType,
      Value<int> absTimelockValue,
      Value<int> wuBase,
      Value<int> wuIn,
      Value<int> wuOut,
      Value<int> trDepth,
      Value<double> vbSweep,
      Value<String?> customName,
    });

final class $$ProjectSpendPathsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ProjectSpendPathsTable,
          ProjectSpendPath
        > {
  $$ProjectSpendPathsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ProjectsTable _projectIdTable(_$AppDatabase db) =>
      db.projects.createAlias(
        $_aliasNameGenerator(db.projectSpendPaths.projectId, db.projects.id),
      );

  $$ProjectsTableProcessedTableManager get projectId {
    final $_column = $_itemColumn<int>('project_id')!;

    final manager = $$ProjectsTableTableManager(
      $_db,
      $_db.projects,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_projectIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ProjectSpendPathsTableFilterComposer
    extends Composer<_$AppDatabase, $ProjectSpendPathsTable> {
  $$ProjectSpendPathsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rustId => $composableBuilder(
    column: $table.rustId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get threshold => $composableBuilder(
    column: $table.threshold,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mfps => $composableBuilder(
    column: $table.mfps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relTimelockType => $composableBuilder(
    column: $table.relTimelockType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get relTimelockValue => $composableBuilder(
    column: $table.relTimelockValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get absTimelockType => $composableBuilder(
    column: $table.absTimelockType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get absTimelockValue => $composableBuilder(
    column: $table.absTimelockValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get wuBase => $composableBuilder(
    column: $table.wuBase,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get wuIn => $composableBuilder(
    column: $table.wuIn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get wuOut => $composableBuilder(
    column: $table.wuOut,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get trDepth => $composableBuilder(
    column: $table.trDepth,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get vbSweep => $composableBuilder(
    column: $table.vbSweep,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customName => $composableBuilder(
    column: $table.customName,
    builder: (column) => ColumnFilters(column),
  );

  $$ProjectsTableFilterComposer get projectId {
    final $$ProjectsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableFilterComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProjectSpendPathsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProjectSpendPathsTable> {
  $$ProjectSpendPathsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rustId => $composableBuilder(
    column: $table.rustId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get threshold => $composableBuilder(
    column: $table.threshold,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mfps => $composableBuilder(
    column: $table.mfps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relTimelockType => $composableBuilder(
    column: $table.relTimelockType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get relTimelockValue => $composableBuilder(
    column: $table.relTimelockValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get absTimelockType => $composableBuilder(
    column: $table.absTimelockType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get absTimelockValue => $composableBuilder(
    column: $table.absTimelockValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get wuBase => $composableBuilder(
    column: $table.wuBase,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get wuIn => $composableBuilder(
    column: $table.wuIn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get wuOut => $composableBuilder(
    column: $table.wuOut,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get trDepth => $composableBuilder(
    column: $table.trDepth,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get vbSweep => $composableBuilder(
    column: $table.vbSweep,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customName => $composableBuilder(
    column: $table.customName,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProjectsTableOrderingComposer get projectId {
    final $$ProjectsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableOrderingComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProjectSpendPathsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProjectSpendPathsTable> {
  $$ProjectSpendPathsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get rustId =>
      $composableBuilder(column: $table.rustId, builder: (column) => column);

  GeneratedColumn<int> get threshold =>
      $composableBuilder(column: $table.threshold, builder: (column) => column);

  GeneratedColumn<String> get mfps =>
      $composableBuilder(column: $table.mfps, builder: (column) => column);

  GeneratedColumn<String> get relTimelockType => $composableBuilder(
    column: $table.relTimelockType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get relTimelockValue => $composableBuilder(
    column: $table.relTimelockValue,
    builder: (column) => column,
  );

  GeneratedColumn<String> get absTimelockType => $composableBuilder(
    column: $table.absTimelockType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get absTimelockValue => $composableBuilder(
    column: $table.absTimelockValue,
    builder: (column) => column,
  );

  GeneratedColumn<int> get wuBase =>
      $composableBuilder(column: $table.wuBase, builder: (column) => column);

  GeneratedColumn<int> get wuIn =>
      $composableBuilder(column: $table.wuIn, builder: (column) => column);

  GeneratedColumn<int> get wuOut =>
      $composableBuilder(column: $table.wuOut, builder: (column) => column);

  GeneratedColumn<int> get trDepth =>
      $composableBuilder(column: $table.trDepth, builder: (column) => column);

  GeneratedColumn<double> get vbSweep =>
      $composableBuilder(column: $table.vbSweep, builder: (column) => column);

  GeneratedColumn<String> get customName => $composableBuilder(
    column: $table.customName,
    builder: (column) => column,
  );

  $$ProjectsTableAnnotationComposer get projectId {
    final $$ProjectsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.projectId,
      referencedTable: $db.projects,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProjectsTableAnnotationComposer(
            $db: $db,
            $table: $db.projects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProjectSpendPathsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProjectSpendPathsTable,
          ProjectSpendPath,
          $$ProjectSpendPathsTableFilterComposer,
          $$ProjectSpendPathsTableOrderingComposer,
          $$ProjectSpendPathsTableAnnotationComposer,
          $$ProjectSpendPathsTableCreateCompanionBuilder,
          $$ProjectSpendPathsTableUpdateCompanionBuilder,
          (ProjectSpendPath, $$ProjectSpendPathsTableReferences),
          ProjectSpendPath,
          PrefetchHooks Function({bool projectId})
        > {
  $$ProjectSpendPathsTableTableManager(
    _$AppDatabase db,
    $ProjectSpendPathsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProjectSpendPathsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProjectSpendPathsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProjectSpendPathsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> projectId = const Value.absent(),
                Value<int> rustId = const Value.absent(),
                Value<int> threshold = const Value.absent(),
                Value<String> mfps = const Value.absent(),
                Value<String> relTimelockType = const Value.absent(),
                Value<int> relTimelockValue = const Value.absent(),
                Value<String> absTimelockType = const Value.absent(),
                Value<int> absTimelockValue = const Value.absent(),
                Value<int> wuBase = const Value.absent(),
                Value<int> wuIn = const Value.absent(),
                Value<int> wuOut = const Value.absent(),
                Value<int> trDepth = const Value.absent(),
                Value<double> vbSweep = const Value.absent(),
                Value<String?> customName = const Value.absent(),
              }) => ProjectSpendPathsCompanion(
                id: id,
                projectId: projectId,
                rustId: rustId,
                threshold: threshold,
                mfps: mfps,
                relTimelockType: relTimelockType,
                relTimelockValue: relTimelockValue,
                absTimelockType: absTimelockType,
                absTimelockValue: absTimelockValue,
                wuBase: wuBase,
                wuIn: wuIn,
                wuOut: wuOut,
                trDepth: trDepth,
                vbSweep: vbSweep,
                customName: customName,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int projectId,
                required int rustId,
                required int threshold,
                required String mfps,
                Value<String> relTimelockType = const Value.absent(),
                Value<int> relTimelockValue = const Value.absent(),
                Value<String> absTimelockType = const Value.absent(),
                Value<int> absTimelockValue = const Value.absent(),
                required int wuBase,
                required int wuIn,
                required int wuOut,
                required int trDepth,
                required double vbSweep,
                Value<String?> customName = const Value.absent(),
              }) => ProjectSpendPathsCompanion.insert(
                id: id,
                projectId: projectId,
                rustId: rustId,
                threshold: threshold,
                mfps: mfps,
                relTimelockType: relTimelockType,
                relTimelockValue: relTimelockValue,
                absTimelockType: absTimelockType,
                absTimelockValue: absTimelockValue,
                wuBase: wuBase,
                wuIn: wuIn,
                wuOut: wuOut,
                trDepth: trDepth,
                vbSweep: vbSweep,
                customName: customName,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ProjectSpendPathsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({projectId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (projectId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.projectId,
                                referencedTable:
                                    $$ProjectSpendPathsTableReferences
                                        ._projectIdTable(db),
                                referencedColumn:
                                    $$ProjectSpendPathsTableReferences
                                        ._projectIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ProjectSpendPathsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProjectSpendPathsTable,
      ProjectSpendPath,
      $$ProjectSpendPathsTableFilterComposer,
      $$ProjectSpendPathsTableOrderingComposer,
      $$ProjectSpendPathsTableAnnotationComposer,
      $$ProjectSpendPathsTableCreateCompanionBuilder,
      $$ProjectSpendPathsTableUpdateCompanionBuilder,
      (ProjectSpendPath, $$ProjectSpendPathsTableReferences),
      ProjectSpendPath,
      PrefetchHooks Function({bool projectId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ProjectsTableTableManager get projects =>
      $$ProjectsTableTableManager(_db, _db.projects);
  $$ProjectKeysTableTableManager get projectKeys =>
      $$ProjectKeysTableTableManager(_db, _db.projectKeys);
  $$ProjectSpendPathsTableTableManager get projectSpendPaths =>
      $$ProjectSpendPathsTableTableManager(_db, _db.projectSpendPaths);
}
