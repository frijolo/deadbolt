// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get cancel => 'Cancelar';

  @override
  String get save => 'Guardar';

  @override
  String get delete => 'Eliminar';

  @override
  String get clear => 'Limpiar';

  @override
  String get add => 'Agregar';

  @override
  String get edit => 'Editar';

  @override
  String get export => 'Exportar';

  @override
  String get discard => 'Descartar';

  @override
  String get previous => 'Anterior';

  @override
  String get next => 'Siguiente';

  @override
  String get loadingProjects => 'Cargando proyectos...';

  @override
  String get projectsTitle => 'Proyectos';

  @override
  String get menuNew => 'Nuevo';

  @override
  String get menuImport => 'Importar';

  @override
  String get menuAbout => 'Acerca de';

  @override
  String get menuSettings => 'Configuración';

  @override
  String get noProjects => 'No hay proyectos.\nToca + para crear uno.';

  @override
  String get deleteProjectTitle => 'Eliminar proyecto';

  @override
  String deleteProjectConfirm(String name) {
    return '¿Eliminar \"$name\"?';
  }

  @override
  String get deleteProjectTooltip => 'Eliminar proyecto';

  @override
  String get importFromFile => 'Importar desde archivo';

  @override
  String get couldNotReadFile => 'No se pudo leer el archivo';

  @override
  String get projectImportedSuccess => 'Proyecto importado exitosamente';

  @override
  String importFailed(String error) {
    return 'Error al importar: $error';
  }

  @override
  String get newProjectTitle => 'Nuevo proyecto';

  @override
  String get importDescriptorMode => 'Importar descriptor';

  @override
  String get fromScratchMode => 'Empezar desde cero';

  @override
  String get projectNameLabel => 'Nombre del proyecto';

  @override
  String get descriptorLabel => 'Descriptor';

  @override
  String get descriptorHint => 'Pega tu descriptor Bitcoin aquí...';

  @override
  String get networkLabel => 'Red';

  @override
  String get selectNetworkTooltip => 'Seleccionar red';

  @override
  String get walletTypeLabel => 'Tipo de wallet';

  @override
  String get selectWalletTypeTooltip => 'Seleccionar tipo de billetera';

  @override
  String get analyzeAndSave => 'Analizar y Guardar';

  @override
  String get createProject => 'Crear Proyecto';

  @override
  String get projectNameRequired => 'El nombre del proyecto es obligatorio';

  @override
  String get descriptorEmpty => 'El descriptor no puede estar vacío';

  @override
  String get analyzingDescriptor => 'Analizando descriptor...';

  @override
  String get creatingProject => 'Creando proyecto...';

  @override
  String get aboutTitle => 'Acerca de';

  @override
  String get loadingAppInfo => 'Cargando información de la app...';

  @override
  String get bitcoinDescriptorAnalyzer => 'Analizador de Descriptores Bitcoin';

  @override
  String get versionLabel => 'Versión';

  @override
  String get projectSectionTitle => 'Proyecto';

  @override
  String get githubRepository => 'Repositorio GitHub';

  @override
  String get securityGpg => 'Seguridad y GPG';

  @override
  String get licenseLabel => 'Licencia';

  @override
  String get mitLicense => 'Licencia MIT';

  @override
  String get openSourceDescription =>
      'Análisis de código abierto de descriptores Bitcoin';

  @override
  String get settingsTitle => 'Configuración';

  @override
  String get languageLabel => 'Idioma';

  @override
  String get preferredNetworkLabel => 'Red preferida';

  @override
  String get activeNetworkLabel => 'Red activa';

  @override
  String get activeNetworkDescription =>
      'Solo se muestran wallets de esta red. Las wallets de otras redes quedan ocultas, no eliminadas.';

  @override
  String walletsHiddenOnOtherNetworks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'wallets',
      one: 'wallet',
    );
    return '$count $_temp0 en otras redes — cambia en Ajustes';
  }

  @override
  String restoringToNetwork(String network) {
    return 'Restaurando en: $network';
  }

  @override
  String get preferredWalletTypeLabel => 'Tipo de billetera predeterminado';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get settingsLanguageEs => 'Español';

  @override
  String get themeLabel => 'Tema';

  @override
  String get themeSystem => 'Predeterminado del sistema';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeDark => 'Oscuro';

  @override
  String get screenshotProtectionLabel => 'Protección de pantalla';

  @override
  String get screenshotProtectionSubtitle =>
      'Evita capturas y grabación de pantalla';

  @override
  String get settingsSectionSecurity => 'Seguridad';

  @override
  String get biometricLockLabel => 'Bloqueo biométrico';

  @override
  String get biometricLockSubtitle => 'Requiere biometría para abrir la app';

  @override
  String get biometricLockInfoTitle => 'Bloqueo biométrico';

  @override
  String get biometricLockInfoBody =>
      'Al activarlo, Deadbolt requerirá huella dactilar, reconocimiento facial o el PIN/patrón del dispositivo cada vez que abras la app o vuelvas de segundo plano.\n\nAsegúrate de tener biometría o bloqueo de pantalla configurado antes de activarlo.';

  @override
  String get biometricLockInfoEnable => 'Activar';

  @override
  String get biometricTimeoutLabel => 'Bloquear tras';

  @override
  String get biometricTimeoutImmediate => 'Inmediatamente';

  @override
  String get biometricTimeout1Min => '1 minuto';

  @override
  String get biometricTimeout5Min => '5 minutos';

  @override
  String get biometricUnlockReason => 'Autentícate para acceder a Deadbolt';

  @override
  String get biometricUnlockButton => 'Desbloquear';

  @override
  String get biometricSetupFailed =>
      'Autenticación fallida. El bloqueo biométrico no se activó.';

  @override
  String get biometricWalletSectionTitle => 'Desbloqueo biométrico';

  @override
  String get biometricWalletSectionBody =>
      'Usa huella dactilar o Face ID para abrir esta wallet sin escribir tu contraseña.';

  @override
  String get biometricWalletUnlockReason => 'Autentícate para abrir la wallet';

  @override
  String get biometricWalletEnableFailed =>
      'No se pudo activar el desbloqueo biométrico. Inténtalo de nuevo.';

  @override
  String get biometricWalletDisableFailed =>
      'No se pudo desactivar el desbloqueo biométrico.';

  @override
  String get biometricWalletRootedWarning =>
      'Aviso: en dispositivos rooteados o con jailbreak, la clave de desbloqueo almacenada en el almacenamiento seguro podría ser extraída.';

  @override
  String get discardChangesTooltip => 'Descartar cambios';

  @override
  String get moreOptionsTooltip => 'Más opciones';

  @override
  String get buildFabLabel => 'Construir';

  @override
  String get descriptorOutdatedBanner =>
      'Descriptor desactualizado · toca Construir para regenerar';

  @override
  String get keySectionLabel => 'Clave';

  @override
  String keysSection(int count) {
    return 'Claves ($count)';
  }

  @override
  String get addKeyButton => 'Agregar clave';

  @override
  String spendPathsSection(int count) {
    return 'Rutas de gasto ($count)';
  }

  @override
  String get addSpendPath => 'Agregar ruta de gasto';

  @override
  String get addKeyDialogTitle => 'Agregar Clave';

  @override
  String get separateFieldsMode => 'Campos separados';

  @override
  String get fullKeyspecMode => 'Keyspec completo';

  @override
  String get mfpLabel => 'Huella maestra (MFP)';

  @override
  String get mfpHint => 'ej., c449c5c5';

  @override
  String get derivationPathLabel => 'Ruta de derivación';

  @override
  String get derivationPathHint => 'ej., 48h/0h/0h/2h';

  @override
  String get xpubLabel => 'Clave pública extendida (xpub)';

  @override
  String get xpubHint => 'xpub6...';

  @override
  String get fullKeyspecLabel => 'Keyspec completo';

  @override
  String get fullKeyspecHint => '[c449c5c5/48h/0h/0h/2h]xpub6...';

  @override
  String get fullKeyspecHelperText => 'Formato: [mfp/ruta]xpub';

  @override
  String get allFieldsRequired => 'Todos los campos son obligatorios';

  @override
  String get keyspecRequired => 'El keyspec es obligatorio';

  @override
  String get invalidKeyspecFormat =>
      'Formato de keyspec inválido. Se esperaba: [mfp/ruta]xpub';

  @override
  String duplicateMfp(String mfp) {
    return 'Ya existe una clave con MFP $mfp';
  }

  @override
  String get copyDescriptorTooltip => 'Exportar descriptor';

  @override
  String get descriptorCopied => 'Descriptor copiado';

  @override
  String get copyToClipboard => 'Copiar al portapapeles';

  @override
  String get saveToDownloads => 'Guardar en Descargas';

  @override
  String get saveAs => 'Guardar como…';

  @override
  String get shareFile => 'Compartir archivo';

  @override
  String get shareText => 'Compartir';

  @override
  String get showQrCode => 'Mostrar código QR';

  @override
  String get scanQrCode => 'Escanear código QR';

  @override
  String get fromFile => 'Desde archivo';

  @override
  String get showAsText => 'Mostrar como texto';

  @override
  String get pasteFromClipboard => 'Pegar desde portapapeles';

  @override
  String get pasteText => 'Pegar texto';

  @override
  String get pasteTextHint => 'Pega tu contenido aquí…';

  @override
  String get clipboardEmpty => 'El portapapeles está vacío';

  @override
  String get importAction => 'Importar';

  @override
  String get qrNotFoundInImage => 'No se encontró código QR en la imagen';

  @override
  String get cameraError => 'Cámara no disponible en esta plataforma';

  @override
  String get importFromQrImage => 'Importar imagen QR';

  @override
  String get qrDialogTitle => 'Código QR';

  @override
  String get qrAnimatedLabel => 'Animado (BC-UR)';

  @override
  String get qrBytesPerFrame => 'Bytes/cuadro';

  @override
  String get qrEcLevel => 'Corrección de errores';

  @override
  String get qrTooLargeForLevel =>
      'Contenido demasiado grande para este nivel de corrección';

  @override
  String qrPart(int current, int total) {
    return '$current / $total';
  }

  @override
  String get enable => 'Habilitar';

  @override
  String get close => 'Cerrar';

  @override
  String get dismiss => 'Descartar';

  @override
  String get savedToDownloads => 'Archivo guardado';

  @override
  String get copiedToClipboard => 'Copiado al portapapeles';

  @override
  String get projectNameDialogTitle => 'Nombre del proyecto';

  @override
  String get discardChangesDialogTitle => '¿Descartar cambios?';

  @override
  String get discardChangesContent =>
      'Tienes cambios sin guardar. Esta acción no se puede deshacer.';

  @override
  String get changeWalletTypeTooltip => 'Cambiar tipo de billetera';

  @override
  String spendPathMustHaveKey(int index) {
    return 'Ruta de gasto $index: Debe tener al menos una clave';
  }

  @override
  String spendPathKeyNotFound(int index, String mfp) {
    return 'Ruta de gasto $index: Clave $mfp no encontrada';
  }

  @override
  String spendPathThresholdMin(int index) {
    return 'Ruta de gasto $index: El umbral debe ser al menos 1';
  }

  @override
  String spendPathThresholdExceeds(int index) {
    return 'Ruta de gasto $index: El umbral no puede superar el número de claves';
  }

  @override
  String get taprootOneKeyPath =>
      'Solo una ruta de gasto puede marcarse como key-path en descriptores Taproot.';

  @override
  String get buildingDescriptor => 'Construyendo descriptor...';

  @override
  String get buildingDescriptorMultiPath =>
      'Construyendo descriptor con múltiples rutas...';

  @override
  String get buildingComplexDescriptor =>
      'Construyendo descriptor complejo...\nEsto puede tardar unos momentos';

  @override
  String get analyzingDescriptorLoading => 'Analizando descriptor...';

  @override
  String get analyzingComplexDescriptor => 'Analizando descriptor complejo...';

  @override
  String get analyzingAndSaving => 'Analizando y guardando...';

  @override
  String get enterName => 'Ingresa un nombre';

  @override
  String get nameAlreadyUsed => 'Este nombre ya está en uso por otra clave';

  @override
  String get tapToName => 'Toca para nombrar';

  @override
  String get copyKeyspecTooltip => 'Copiar keyspec';

  @override
  String get keyCopied => 'Clave copiada';

  @override
  String get pathPrefix => 'Ruta: ';

  @override
  String get rootPath => '(raíz)';

  @override
  String get xpubPrefix => 'Xpub: ';

  @override
  String get keyNameDialogTitle => 'Nombre de clave';

  @override
  String get keyFingerprintLabel => 'Fingerprint';

  @override
  String get keyDerivPathLabel => 'Ruta de derivación';

  @override
  String get keyXpubLabel => 'Clave pública extendida';

  @override
  String get removeKeyTooltip => 'Eliminar clave';

  @override
  String get keyInUseTooltip => 'Clave en uso - no se puede eliminar';

  @override
  String get hotKeyBadge => 'HOT';

  @override
  String get privateKeySection => 'Clave privada';

  @override
  String get viewPrivateKeyButton => 'Ver semilla';

  @override
  String get deletePrivateKeyButton => 'Eliminar clave firmante';

  @override
  String get viewPrivateKeyDisclaimer =>
      'Asegúrate de que nadie vea tu pantalla. Tu frase semilla da acceso total a tus fondos.';

  @override
  String get deletePrivateKeyDisclaimer =>
      'Esto elimina la clave firmante de este proyecto. Ya no podrás firmar transacciones desde el Diseñador.';

  @override
  String get deleteWalletPrivateKeyDisclaimer =>
      'Esto elimina la clave firmante de esta cartera. Ya no podrás firmar transacciones con ella.';

  @override
  String get viewPrivateKeyConfirm => 'Mostrar semilla';

  @override
  String get deletePrivateKeyConfirm => 'Eliminar';

  @override
  String get seedPhraseDialogTitle => 'Frase semilla';

  @override
  String get seedPhraseCopied => 'Frase semilla copiada';

  @override
  String get seedExportTitle => 'Exportar semilla';

  @override
  String get seedExportTabWords => 'Palabras';

  @override
  String get seedExportTabQr => 'Código QR';

  @override
  String get seedExportTabGuide => 'Guía papel';

  @override
  String get seedQrStandard => 'Standard SeedQR';

  @override
  String get seedQrCompact => 'Compact SeedQR';

  @override
  String get seedPassphraseWarning =>
      'Esta semilla tiene una passphrase que no se muestra aquí.';

  @override
  String get seedPassphraseNotIncluded => 'Passphrase no incluida en el QR';

  @override
  String get seedMfpSeedOnly => 'Solo semilla';

  @override
  String get seedMfpWithPassphrase => 'Semilla + passphrase';

  @override
  String seedGuideSegmentLabel(String label, int total) {
    return 'Segmento $label de $total';
  }

  @override
  String get seedGuideDoneTitle => 'Todos los segmentos transcritos';

  @override
  String get seedGuideDoneBody =>
      'Verifica escaneando el QR en papel con una cámara.';

  @override
  String get seedGuideVerifyQr => 'Verificar QR';

  @override
  String get seedGuideVerifySuccess => 'QR verificado correctamente.';

  @override
  String get seedGuideVerifyMismatch => 'El QR no coincide con la semilla.';

  @override
  String get seedGuideInstructions =>
      'Transcribe cada segmento al papel. Cuadros rellenos = módulos oscuros.';

  @override
  String get seedGuideTapToAdvance => 'Toca el QR para avanzar';

  @override
  String get seedGuideRestart => 'Reiniciar';

  @override
  String seedQrSize(String format, int size) {
    return '$format · $size×$size';
  }

  @override
  String get spendPathNameDialogTitle => 'Nombre de ruta de gasto';

  @override
  String get keyPathBadge => 'KEY PATH';

  @override
  String get setAsKeyPath => 'Establecer como key path';

  @override
  String get removePathTooltip => 'Eliminar ruta';

  @override
  String get keysLabel => 'Claves';

  @override
  String get newKey => 'Nueva clave';

  @override
  String get noTimelock => 'Sin timelock';

  @override
  String priorityBadge(int priority) {
    return 'Prioridad $priority';
  }

  @override
  String get changeThresholdTooltip => 'Cambiar umbral';

  @override
  String ofCount(int count) {
    return 'de $count';
  }

  @override
  String get thresholdLabel => 'Umbral';

  @override
  String get sweepCostLabel => 'Sweep cost';

  @override
  String get trDepthLabel => 'Profundidad TR';

  @override
  String get changePriorityTooltip => 'Cambiar prioridad';

  @override
  String get timelockDialogTitle => 'Timelock';

  @override
  String get relativeTimelock => 'Relativo';

  @override
  String get absoluteTimelock => 'Absoluto';

  @override
  String get blocksTimelock => 'Bloques';

  @override
  String get timeTimelock => 'Tiempo';

  @override
  String get timestampTimelock => 'Marca de tiempo';

  @override
  String get selectDateAndTime => 'Seleccionar fecha y hora';

  @override
  String get blocksRelHint => 'Bloques (0-65.535)';

  @override
  String get timeUnitsHint => 'Unidades × 512s (0-65.535)';

  @override
  String get blocksAbsHint => 'Bloques (0-499.999.999)';

  @override
  String get timelockValueMax => 'El valor debe ser ≤ 65.535';

  @override
  String get blockHeightMax => 'La altura del bloque debe ser < 500.000.000';

  @override
  String get timestampMin => 'La marca de tiempo debe ser ≥ 500.000.000';

  @override
  String get mustHaveAtLeastOneKey => 'Debe tener al menos una clave';

  @override
  String get thresholdMustBeAtLeastOne => 'El umbral debe ser al menos 1';

  @override
  String get thresholdCannotExceed =>
      'El umbral no puede superar el número de claves';

  @override
  String get errorCopiedToClipboard => 'Error copiado al portapapeles';

  @override
  String get projectExportedSuccess => 'Proyecto exportado exitosamente';

  @override
  String exportFailed(String error) {
    return 'Error al exportar: $error';
  }

  @override
  String get networkMainnet => 'Mainnet';

  @override
  String get networkTestnet => 'Testnet';

  @override
  String get networkTestnet4 => 'Testnet4';

  @override
  String get networkSignet => 'Signet';

  @override
  String get networkRegtest => 'Regtest';

  @override
  String get walletTypeP2pkh => 'Legacy (P2PKH)';

  @override
  String get walletTypeP2wpkh => 'Segwit (P2WPKH)';

  @override
  String get walletTypeP2sh => 'Legacy (P2SH)';

  @override
  String get walletTypeP2wsh => 'Segwit (P2WSH)';

  @override
  String get walletTypeP2tr => 'Taproot (P2TR)';

  @override
  String get walletTypeP2shWpkh => 'Nested Segwit (P2SH-WPKH)';

  @override
  String get walletTypeP2shWsh => 'Nested Segwit (P2SH-WSH)';

  @override
  String get walletTypeUnknown => 'Desconocido';

  @override
  String get walletPolicySingleSig => 'SingleSig';

  @override
  String get walletPolicyMiniscript => 'Miniscript';

  @override
  String get walletAddressLegacy => 'Legacy';

  @override
  String get walletAddressSegwit => 'SegWit';

  @override
  String get walletAddressNested => 'Nested';

  @override
  String get walletAddressTaproot => 'Taproot';

  @override
  String get navDesigner => 'Diseñador';

  @override
  String get navWallet => 'Billetera';

  @override
  String get walletsTitle => 'Billeteras';

  @override
  String get noWallets => 'No hay billeteras.\nToca + para crear una.';

  @override
  String get createWalletFromProject => 'Crear billetera';

  @override
  String get generateProjectFromWallet => 'Analizar en Diseñador';

  @override
  String get projectHasNoDescriptor =>
      'Este proyecto aún no tiene descriptor. Constrúyelo primero.';

  @override
  String get loadingWallets => 'Cargando billeteras...';

  @override
  String get openingWallet => 'Abriendo cartera…';

  @override
  String get loadingWalletData => 'Cargando datos de cartera…';

  @override
  String get loadingAddresses => 'Cargando direcciones…';

  @override
  String get loadingCoins => 'Cargando monedas…';

  @override
  String get initializingCamera => 'Iniciando cámara…';

  @override
  String get switchCamera => 'Cambiar cámara';

  @override
  String get deleteWalletTitle => 'Eliminar billetera';

  @override
  String deleteWalletConfirm(String name) {
    return '¿Eliminar \"$name\"?';
  }

  @override
  String get createWalletTitle => 'Nueva Billetera';

  @override
  String get walletNameLabel => 'Nombre del wallet';

  @override
  String get walletNameRequired => 'El nombre es obligatorio';

  @override
  String get deleteProjectAfterCreate =>
      'Eliminar este proyecto al crear la billetera';

  @override
  String get fromProjectAction => 'Desde proyecto';

  @override
  String get createWalletButton => 'Crear wallet';

  @override
  String get creatingWallet => 'Creando billetera...';

  @override
  String get balanceConfirmed => 'Confirmado';

  @override
  String get balancePending => 'Pendiente';

  @override
  String get balanceImmature => 'Inmaduro';

  @override
  String balanceSats(int sats) {
    final intl.NumberFormat satsNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String satsString = satsNumberFormat.format(sats);

    return '$satsString sats';
  }

  @override
  String balanceBtc(String btc) {
    return '$btc BTC';
  }

  @override
  String get walletPasswordProtected => 'Protegida con contraseña';

  @override
  String get lockWallet => 'Bloquear cartera';

  @override
  String get backupSaved => 'Copia de seguridad guardada';

  @override
  String get changeProtectionMenu => 'Cambiar protección';

  @override
  String get encryptionLabel => 'Cifrado';

  @override
  String get walletSecurityLabel => 'Seguridad';

  @override
  String get walletSecurityTitle => 'Seguridad del wallet';

  @override
  String get encryptionSection => 'Cifrado';

  @override
  String get descriptorSigsSection => 'Firmas de descriptor';

  @override
  String get manageSignatures => 'Gestionar firmas';

  @override
  String get goToSecurity => 'Ir a seguridad';

  @override
  String get noParticipatingKeys => 'No se encontraron claves participantes';

  @override
  String get descriptorSigAbsent => 'Sin firmas';

  @override
  String get descriptorSigVerified => 'Firmas verificadas';

  @override
  String get descriptorSigInvalid => 'Firmas inválidas';

  @override
  String get descriptorSigOwnerUnsigned => 'Xpub descubridora sin firma';

  @override
  String get descriptorSigUnknown => 'Estado de firma desconocido';

  @override
  String get walletBalanceUnknown => '–';

  @override
  String get notYetSynced => 'No sincronizado aún';

  @override
  String lastSynced(String time) {
    return 'Última sincronización: $time';
  }

  @override
  String get syncButton => 'Sincronizar';

  @override
  String get syncTooltip => 'Sincronizar billetera';

  @override
  String get syncing => 'Sincronizando...';

  @override
  String syncFailed(String error) {
    return 'Error al sincronizar: $error';
  }

  @override
  String get rescanButton => 'Reescaneo completo';

  @override
  String get rescanConfirmTitle => 'Reescaneo completo';

  @override
  String get rescanConfirmBody =>
      'Se reescanearán todas las direcciones desde cero. Puede tardar más que una sincronización normal.';

  @override
  String get transactionsSection => 'Transacciones';

  @override
  String get noTransactions => 'Sin transacciones aún';

  @override
  String get txReceived => 'Recibido';

  @override
  String get txSent => 'Enviado';

  @override
  String get txSelfTransfer => 'Transferencia propia';

  @override
  String get txConfirmed => 'Confirmado';

  @override
  String get txUnconfirmed => 'No confirmado';

  @override
  String txFee(int fee) {
    final intl.NumberFormat feeNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String feeString = feeNumberFormat.format(fee);

    return 'Comisión: $feeString sats';
  }

  @override
  String txHeight(int height) {
    final intl.NumberFormat heightNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String heightString = heightNumberFormat.format(height);

    return 'Bloque: $heightString';
  }

  @override
  String get txId => 'TXID';

  @override
  String get loadMore => 'Cargar más';

  @override
  String get electrumSectionTitle => 'Servidores Electrum';

  @override
  String get electrumUrlLabel => 'URL de Electrum';

  @override
  String get electrumUrlHint => 'ssl://host:puerto o tcp://host:puerto';

  @override
  String get electrumNetworkMainnet => 'Electrum Mainnet';

  @override
  String get electrumNetworkTestnet => 'Electrum Testnet';

  @override
  String get electrumNetworkTestnet4 => 'Electrum Testnet4';

  @override
  String get electrumNetworkSignet => 'Electrum Signet';

  @override
  String get electrumNetworkRegtest => 'Electrum Regtest';

  @override
  String get settingsMinFeeRate => 'Comisión mínima (sat/vB)';

  @override
  String get fiatSectionTitle => 'Valores fiat';

  @override
  String get fiatEnabledLabel => 'Mostrar valores fiat';

  @override
  String get fiatCurrencyLabel => 'Divisa';

  @override
  String get fiatProviderLabel => 'Proveedor de precios';

  @override
  String get fiatProviderCoinGecko => 'CoinGecko';

  @override
  String get fiatProviderMempoolSpace => 'Mempool.space';

  @override
  String get explorerSectionTitle => 'Explorador de bloques';

  @override
  String get explorerUrlHint => 'https://mempool.space';

  @override
  String get explorerNetworkMainnet => 'Explorador Mainnet';

  @override
  String get explorerNetworkTestnet => 'Explorador Testnet';

  @override
  String get explorerNetworkTestnet4 => 'Explorador Testnet4';

  @override
  String get explorerNetworkSignet => 'Explorador Signet';

  @override
  String get explorerNetworkRegtest => 'Explorador Regtest';

  @override
  String get explorerNoUrl => 'Sin explorador configurado para esta red';

  @override
  String get openInExplorer => 'Abrir en explorador';

  @override
  String get txLabelTitle => 'Etiqueta';

  @override
  String get txDetailsTitle => 'Detalles de la transacción';

  @override
  String get txDetailsNet => 'Importe neto';

  @override
  String get txDetailsGrossReceived => 'Recibido (bruto)';

  @override
  String get txDetailsGrossSent => 'Enviado (bruto)';

  @override
  String get txDetailsBlockHeight => 'Altura de bloque';

  @override
  String get txDetailsConfirmedAt => 'Confirmado el';

  @override
  String get txDetailsFee => 'Comisión';

  @override
  String get addressesSection => 'Direcciones';

  @override
  String get receiveAddresses => 'Recepción';

  @override
  String get changeAddresses => 'Cambio';

  @override
  String get noAddresses =>
      'Sin direcciones aún. Sincroniza para descubrirlas.';

  @override
  String addressIndex(int index) {
    return '#$index';
  }

  @override
  String get addressLabelTitle => 'Etiqueta de dirección';

  @override
  String get addressLabelHint => 'Añadir etiqueta...';

  @override
  String get addressLabelRemove => 'Eliminar etiqueta';

  @override
  String get addressDetailsTitle => 'Detalles de la dirección';

  @override
  String addressBalanceSats(int sats) {
    final intl.NumberFormat satsNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String satsString = satsNumberFormat.format(sats);

    return '$satsString sats';
  }

  @override
  String get revealMoreAddresses => 'Revelar 20 direcciones más';

  @override
  String addressTxCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString transacciones';
  }

  @override
  String get viewInExplorer => 'Ver en explorador';

  @override
  String get coinsSection => 'Monedas';

  @override
  String get noCoins => 'Sin monedas. Sincroniza para descubrir UTXOs.';

  @override
  String get coinDetailsTitle => 'Detalles de la moneda';

  @override
  String get coinLabelTitle => 'Etiqueta';

  @override
  String get coinOutpoint => 'Outpoint';

  @override
  String get coinValue => 'Valor';

  @override
  String get coinAddress => 'Dirección';

  @override
  String get coinKeychain => 'Keychain';

  @override
  String get coinKeychainReceive => 'Recepción';

  @override
  String get coinKeychainChange => 'Cambio';

  @override
  String get coinAgeLabel => 'Antigüedad';

  @override
  String get coinBlockNumber => 'Bloque';

  @override
  String get coinConfirmations => 'Confirmaciones';

  @override
  String coinTotalCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString monedas';
  }

  @override
  String coinTotalValue(int sats) {
    final intl.NumberFormat satsNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String satsString = satsNumberFormat.format(sats);

    return 'Total: $satsString sats';
  }

  @override
  String get spendPathsAvailable => 'Rutas de gasto';

  @override
  String get spendPathsNotSynced =>
      'Sincroniza para ver las rutas de gasto disponibles';

  @override
  String get spendPathUnlocked => 'Desbloqueada';

  @override
  String get spendPathLocked => 'Bloqueada';

  @override
  String spendPathLockedUntilBlock(int block) {
    final intl.NumberFormat blockNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String blockString = blockNumberFormat.format(block);

    return 'Bloqueada hasta bloque $blockString';
  }

  @override
  String spendPathBlocks(int blocks) {
    final intl.NumberFormat blocksNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String blocksString = blocksNumberFormat.format(blocks);

    return '$blocksString bloques';
  }

  @override
  String get spendPathNeedsConfirmation => 'Necesita confirmación';

  @override
  String get spendPathUnconfirmed => 'No confirmado';

  @override
  String get spendPathNeedsSync => 'Sincronización requerida';

  @override
  String get psbtStatusUnsigned => 'SIN FIRMAR';

  @override
  String get psbtStatusPartial => 'PARCIAL';

  @override
  String get psbtStatusSigned => 'FIRMADO';

  @override
  String get psbtStatusMempool => 'MEMPOOL';

  @override
  String get psbtStatusConfirmed => 'CONFIRMADO';

  @override
  String get psbtStatusSpent => 'GASTADO';

  @override
  String get psbtSpentInputsWarning =>
      'Uno o más inputs han sido gastados y confirmados por otra transacción. Esta PSBT ya no puede emitirse.';

  @override
  String get createTxTitle => 'Crear transacción';

  @override
  String get createTxRecipient => 'Dirección destinataria';

  @override
  String get createTxRecipientHint => 'bc1q...';

  @override
  String get createTxAmount => 'Importe (sats)';

  @override
  String get createTxFeeRate => 'Tarifa (sat/vB)';

  @override
  String get createTxFeeRateHint => 'p.ej. 1.5';

  @override
  String createTxFeeRateMin(String min) {
    return 'La tarifa mínima es $min sat/vB';
  }

  @override
  String get createTxSpendPath => 'Ruta de gasto';

  @override
  String get createTxSpendPathHint => 'Selecciona una ruta de gasto';

  @override
  String createTxSelectedCoins(int count, int sats) {
    final intl.NumberFormat satsNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String satsString = satsNumberFormat.format(sats);

    return '$count moneda(s) — $satsString sats';
  }

  @override
  String get createTxAutoSelect => 'Selección automática';

  @override
  String get createTxButton => 'Crear PSBT';

  @override
  String get createTxCreating => 'Creando...';

  @override
  String get createTxRecipientRequired => 'La dirección es obligatoria';

  @override
  String get createTxAmountRequired => 'El importe es obligatorio';

  @override
  String get createTxAmountInvalid => 'Importe inválido';

  @override
  String get createTxMaxButton => 'MÁX';

  @override
  String get createTxSendMax => 'Enviar todo (máximo)';

  @override
  String get createTxSelfPayButton => 'AUTO';

  @override
  String get createTxMyWalletsButton => 'MIS WALLETS';

  @override
  String get createTxSelectDestWallet => 'Seleccionar wallet destino';

  @override
  String get createTxThisWallet => 'Esta wallet (Auto)';

  @override
  String get createTxNoUnusedAddress =>
      'No hay dirección de recepción sin usar';

  @override
  String get createTxFeeRateInvalid => 'Tarifa inválida';

  @override
  String get createTxNoSpendPaths =>
      'No hay rutas de gasto. Sincroniza primero.';

  @override
  String get createTxSuccess => 'PSBT creado';

  @override
  String get psbtDetailTitle => 'Transacción sin firmar';

  @override
  String get psbtRecipient => 'Destinatario';

  @override
  String get psbtAmount => 'Importe';

  @override
  String get psbtFee => 'Comisión';

  @override
  String get psbtCreatedAt => 'Creado';

  @override
  String get psbtTimelockLabel => 'Timelock';

  @override
  String get psbtTimelockSyncRequired => 'Sincroniza para ver el estado';

  @override
  String psbtTimelockBlocksRemaining(int blocks, String duration) {
    final intl.NumberFormat blocksNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String blocksString = blocksNumberFormat.format(blocks);

    return '$blocksString bloques restantes (~$duration)';
  }

  @override
  String psbtTimelockTimeRemaining(String duration) {
    return '~$duration restante';
  }

  @override
  String psbtSignaturesTitle(int done, int threshold, int total) {
    return 'Firmas ($done/$threshold de $total)';
  }

  @override
  String get psbtSignerSigned => 'Firmado';

  @override
  String get psbtSignerMissing => 'Pendiente';

  @override
  String get psbtSignerOptional => 'Opcional';

  @override
  String get psbtSignerUnknown => 'Desconocido';

  @override
  String get psbtExportButton => 'Exportar PSBT';

  @override
  String get psbtImportSignedButton => 'Importar firma';

  @override
  String get psbtImportFromQr => 'Escanear QR';

  @override
  String get psbtImportFromFile => 'Desde archivo (.psbt)';

  @override
  String get psbtBroadcastButton => 'Transmitir';

  @override
  String psbtBroadcastSuccess(String txid) {
    return '¡Transacción enviada! TXID: $txid';
  }

  @override
  String psbtBroadcastFailed(String error) {
    return 'Error al transmitir: $error';
  }

  @override
  String get psbtMergeSuccess => 'Firmas importadas';

  @override
  String psbtMergeFailed(String error) {
    return 'Error al importar: $error';
  }

  @override
  String get psbtDeleteTitle => 'Eliminar PSBT';

  @override
  String get psbtDeleteConfirm => '¿Eliminar esta transacción sin firmar?';

  @override
  String get psbtExportedCopied => 'PSBT copiado';

  @override
  String get coinSelectMode => 'Seleccionar monedas';

  @override
  String get coinSelectDone => 'Hecho';

  @override
  String coinSelected(int count) {
    return '$count seleccionada(s)';
  }

  @override
  String get createTxFeeByRate => 'Tarifa (sat/vB)';

  @override
  String get createTxFeeByTotal => 'Total (sats)';

  @override
  String get createTxTotalFee => 'Comisión (sats)';

  @override
  String get createTxTotalFeeInvalid => 'Introduce un importe válido';

  @override
  String get createTxFeeEstimate => 'Estimación de comisiones';

  @override
  String get createTxEstInputs => 'Entradas';

  @override
  String get createTxEstSend => 'Envío';

  @override
  String get createTxEstFee => 'Comisión';

  @override
  String get createTxEstChange => 'Cambio';

  @override
  String get createTxEstInsufficientFunds => 'Fondos insuficientes';

  @override
  String get createTxAddRecipient => 'Añadir destinatario';

  @override
  String get createTxTotalOut => 'Total enviado';

  @override
  String get createTxSelectCoinsFirst =>
      'Selecciona monedas para crear la transacción';

  @override
  String get walletSendButton => 'Enviar';

  @override
  String get coinSelectorTitle => 'Seleccionar monedas';

  @override
  String get coinSelectorNoCoinsSelected => 'Toca para seleccionar monedas...';

  @override
  String coinSelectorDoneCount(int count) {
    return 'Hecho ($count)';
  }

  @override
  String get relatedCoins => 'Monedas relacionadas';

  @override
  String get relatedAddressLabel => 'Etiqueta de dirección';

  @override
  String get relatedAddresses => 'Direcciones de salida';

  @override
  String get inputAddresses => 'Direcciones de entrada';

  @override
  String get relatedTransactions => 'Transacciones relacionadas';

  @override
  String get creatingTransaction => 'Transacción creadora';

  @override
  String get exportBip329Button => 'Exportar';

  @override
  String get importBip329Button => 'Importar';

  @override
  String get exportBip329Empty => 'No hay etiquetas explícitas para exportar';

  @override
  String get exportBip329Copied => 'Etiquetas copiadas';

  @override
  String get importBip329Success => 'Etiquetas importadas';

  @override
  String get exportDescriptorFormatTitle => 'Formato de exportación';

  @override
  String get exportDescriptorStandard => 'Estándar';

  @override
  String get exportDescriptorStandardDesc =>
      'Compatible con Nunchuk y la mayoría de wallets';

  @override
  String get exportDescriptorLiana => 'Liana';

  @override
  String get exportDescriptorLianaDesc =>
      'Agrega [00000000] a la clave no gastable';

  @override
  String get exportLabelsOption => 'Etiquetas (BIP-329)';

  @override
  String get importPsbtOption => 'PSBT';

  @override
  String get importPsbtMerged => 'Firmas combinadas';

  @override
  String get importPsbtSaved => 'PSBT importado';

  @override
  String get coinPendingSpend => 'PSBT';

  @override
  String get coinMempoolSpend => 'Gastando';

  @override
  String get coinPendingPsbtsSection => 'Transacciones pendientes';

  @override
  String get overviewTab => 'Resumen';

  @override
  String get walletReceiveButton => 'Recibir';

  @override
  String get noUnusedReceiveAddress =>
      'No se encontró dirección de recepción sin usar. Prueba a sincronizar primero.';

  @override
  String get receiveNextAddress => 'Siguiente dirección';

  @override
  String get rbfWarningTitle => 'Reemplazo Full-RBF';

  @override
  String get rbfOriginalFee => 'Comisión original';

  @override
  String get rbfDescendants => 'Sucesores';

  @override
  String get rbfMinFee => 'Comisión mínima';

  @override
  String get rbfMinRate => 'Tasa mínima';

  @override
  String get rbfUnknownFee =>
      'Gastando un UTXO en mempool — usa una tasa de comisión mayor que la transacción original.';

  @override
  String rbfFeeTooLow(double rate) {
    return 'Tasa de comisión demasiado baja para RBF — el mínimo es $rate sat/vB';
  }

  @override
  String rbfAbsFeeTooLow(int fee) {
    return 'Comisión total demasiado baja para RBF — el mínimo es $fee sats';
  }

  @override
  String get cpfpBannerTitle => 'Aceleración CPFP';

  @override
  String get cpfpParentFee => 'Fees de ancestros';

  @override
  String get cpfpAncestorCount => 'Txs en el paquete';

  @override
  String get cpfpEffectiveRate => 'Fee rate del paquete';

  @override
  String get cpfpAccelerate => 'Acelerar';

  @override
  String get settingsSectionAppearance => 'Apariencia';

  @override
  String get settingsSectionDefaults => 'Wallet';

  @override
  String get settingsSectionTransactions => 'Transacciones';

  @override
  String get settingsSectionConnectivity => 'Conectividad';

  @override
  String get torLabel => 'Usar Tor';

  @override
  String get torSubtitle => 'Enrutar todo el tráfico por Tor';

  @override
  String get torStatusConnecting => 'Tor conectando...';

  @override
  String get torStatusConnected => 'Tor activo';

  @override
  String get torErrorNotConnected =>
      'Tor está activado pero aún no está conectado';

  @override
  String get disclaimerTitle =>
      'Software en desarrollo — Úsalo bajo tu responsabilidad';

  @override
  String get disclaimerBody =>
      'Deadbolt está en desarrollo activo y puede contener errores.\n\nTodavía no es apto para fondos reales. El uso es bajo tu propia responsabilidad.';

  @override
  String get disclaimerDontShow7Days => 'No mostrar durante 7 días';

  @override
  String get electrumPrivacyWarning =>
      'Usando un servidor Electrum público. Tu IP e historial de transacciones pueden ser visibles para terceros. Configura un servidor propio en Ajustes.';

  @override
  String get goToSettings => 'Configuración';

  @override
  String get wifExportTitle => 'Exportar clave privada (WIF)';

  @override
  String get wifExportWarning =>
      'Esto exporta la clave privada de una sola dirección, pero si el XPUB de tu wallet es conocido por alguien — un coordinador, exchange, o cualquier servicio con el que lo hayas compartido — pueden usar este WIF para derivar las claves privadas de todas las direcciones de tu wallet.\n\nProcede solo si tu XPUB es privado, o si aceptas completamente este riesgo.';

  @override
  String get wifExportTypeToConfirm => 'Escribe para confirmar:';

  @override
  String get wifExportConfirmPhrase => 'mi wallet completo está en riesgo';

  @override
  String get wifExportShowButton => 'Mostrar WIF';

  @override
  String get wifDisplayWarning =>
      'Nunca compartas esta clave. Si tu XPUB es conocido por otros, este WIF expone todo tu wallet.';

  @override
  String get protectionLabel => 'Protección';

  @override
  String get protectionNone => 'Ninguna';

  @override
  String get protectionPassword => 'Contraseña';

  @override
  String get protectionXpub => 'XPub';

  @override
  String get protectionUnprotected => 'Sin protección';

  @override
  String get protectionXpubInfo =>
      'Cualquier xpub del wallet puede desbloquearlo. No compartas esos xpubs con terceros.';

  @override
  String get securityLevelLabel => 'Nivel anti-fuerza bruta';

  @override
  String get securityLevelStandard => 'Estándar';

  @override
  String get securityLevelHigh => 'Alto';

  @override
  String get securityLevelExtreme => 'Extremo';

  @override
  String get newPasswordLabel => 'Nueva contraseña';

  @override
  String get confirmPasswordLabel => 'Confirmar contraseña';

  @override
  String get backupPasswordLabel => 'Contraseña de la copia';

  @override
  String get validatorPasswordEmpty => 'La contraseña no puede estar vacía';

  @override
  String get validatorPasswordRequired => 'Contraseña requerida';

  @override
  String get validatorPasswordsNoMatch => 'Las contraseñas no coinciden';

  @override
  String get validatorNameRequired => 'El nombre es obligatorio';

  @override
  String get changeButton => 'Cambiar';

  @override
  String get exportButton => 'Exportar';

  @override
  String get backButton => 'Volver';

  @override
  String get feeRateLabel => 'Comisión';

  @override
  String get verifyOnDeviceButton => 'Verificar en dispositivo';

  @override
  String get changeProtectionTitle => 'Cambiar protección del wallet';

  @override
  String changeProtectionCurrent(String protection) {
    return 'Actual: $protection';
  }

  @override
  String protectionChangedToast(String protection) {
    return 'Protección cambiada a $protection';
  }

  @override
  String get exportBackupTitle => 'Exportar copia de seguridad';

  @override
  String get sweepWifTitle => 'Barrer clave WIF';

  @override
  String get sweepWifPrivateKeySection => 'Clave privada (WIF)';

  @override
  String get sweepWifHint => 'Pega o escanea una clave WIF...';

  @override
  String get sweepWifSearching => 'Buscando...';

  @override
  String get sweepWifFindUtxos => 'Buscar UTXOs';

  @override
  String get sweepWifControlledAddresses => 'Direcciones controladas';

  @override
  String sweepWifTotal(int amount) {
    return 'Total: $amount sat';
  }

  @override
  String get sweepWifNoFunds =>
      'No se encontraron fondos para esta clave en la red actual.';

  @override
  String get sweepWifDestination => 'Destino';

  @override
  String get sweepWifAddressHint => 'Dirección Bitcoin...';

  @override
  String get sweepWifSweeping => 'Barriendo...';

  @override
  String sweepWifButton(int amount) {
    return 'Barrer $amount sat';
  }

  @override
  String get sweepWifEnterKeyFirst => 'Introduce primero una clave WIF';

  @override
  String get sweepWifFillFields =>
      'Completa todos los campos con valores válidos';

  @override
  String sweepWifSweptToast(String txid) {
    return 'Barrido: $txid';
  }

  @override
  String get sweepWifEmpty => 'vacía';

  @override
  String get walletCreateGuided => 'Creación guiada';

  @override
  String get walletCreateGuidedSub => 'Wallet estándar desde tus claves';

  @override
  String get walletCreateFromDescriptor => 'Desde descriptor';

  @override
  String get walletCreateFromDescriptorSub =>
      'Introduce un descriptor Bitcoin directamente';

  @override
  String get walletCreateFromProject => 'Desde proyecto';

  @override
  String get walletCreateFromProjectSub => 'Usa un descriptor del diseñador';

  @override
  String get walletCreateFromBackup => 'Desde copia de seguridad';

  @override
  String get walletCreateFromBackupSub =>
      'Restaura un wallet desde un archivo .deadbolt';

  @override
  String get projectCreateFromScratch => 'Desde cero';

  @override
  String get projectCreateFromScratchSub =>
      'Elige red y tipo de wallet, luego añade claves';

  @override
  String get projectCreateFromDescriptorSub =>
      'Pega, escanea o importa un descriptor Bitcoin';

  @override
  String get projectCreateImport => 'Importar proyecto';

  @override
  String get projectCreateImportSub =>
      'Restaura un proyecto desde una exportación .json';

  @override
  String get newWalletTitle => 'Nuevo Wallet';

  @override
  String get walletExportLabel => 'Wallet';

  @override
  String get walletTypeSinglesig => 'Singlesig';

  @override
  String get walletTypeMultisig => 'Multisig';

  @override
  String get walletTypeSinglesigDesc =>
      'Una sola clave controla el wallet. Más simple y rápido de configurar.';

  @override
  String get walletTypeMultisigDesc =>
      'Se requieren varias claves para firmar. Ideal para control compartido o seguridad adicional.';

  @override
  String get walletTypeInheritance => 'Herencia';

  @override
  String get walletTypeInheritanceDesc =>
      'Cartera multipaso: tú controlas los fondos ahora; los herederos pueden acceder tras un retraso de tiempo.';

  @override
  String get ownerKeysSection => 'Tus claves';

  @override
  String get heirsSection => 'Herederos';

  @override
  String get addHeir => 'Añadir heredero';

  @override
  String get editHeir => 'Editar heredero';

  @override
  String get heirName => 'Nombre del heredero';

  @override
  String get heirNameHint => 'p.ej. Alice, Familia, Abogado';

  @override
  String get heirKey => 'Clave del heredero';

  @override
  String get heirTimelockLabel => 'Puede acceder después de';

  @override
  String get inheritanceSixMonths => '6 meses (~26.280 bloques)';

  @override
  String get inheritanceOneYear => '1 año (~52.560 bloques)';

  @override
  String get inheritanceThreeMonthsShort => '3 m';

  @override
  String get inheritanceSixMonthsShort => '6 m';

  @override
  String get inheritanceNineMonthsShort => '9 m';

  @override
  String get inheritanceOneYearShort => '1 a';

  @override
  String get inheritanceThreeMonths => '3 meses (~13.140 bloques)';

  @override
  String get inheritanceNineMonths => '9 meses (~39.420 bloques)';

  @override
  String get inheritanceCustomTimelock => 'Personalizado...';

  @override
  String get inheritanceDuplicateTimelockTitle => 'Timelocks duplicados';

  @override
  String get inheritanceDuplicateTimelockBody =>
      'Dos o más herederos comparten el mismo timelock. Para mayor compatibilidad con otros softwares de coordinación, cada ruta de gasto debería tener un timelock distinto.';

  @override
  String get inheritanceDuplicateTimelockFix => 'Corregir automáticamente';

  @override
  String get inheritanceDuplicateTimelockContinue =>
      'Continuar de todas formas';

  @override
  String get inheritanceHeirsNeedKey =>
      'Establece una clave para cada heredero';

  @override
  String get inheritanceNeedHeir => 'Añade al menos un heredero';

  @override
  String get inheritanceOwnerPathLabel => 'Principal';

  @override
  String get inheritanceMinTimelockLabel => 'Umbral de timelock de herencia';

  @override
  String get inheritanceMinTimelockInfoTitle => 'Detección de herencia';

  @override
  String get inheritanceMinTimelockInfo =>
      'Algunos descriptores Taproot usan spend paths con timelocks cortos (p.ej. 1–2 bloques) para modelar combinaciones de firma del mismo propietario — estos no son paths de herencia. Este umbral define el número mínimo de bloques que debe tener un timelock relativo para que un spend path se considere de herencia y se muestre el panel de estado.\n\nPor defecto: 144 bloques (~1 día).';

  @override
  String get inheritanceStatus => 'Herencia';

  @override
  String get inheritanceSafe => 'Seguro';

  @override
  String get inheritanceApproaching => 'Acceso del heredero próximo';

  @override
  String get inheritanceUnlocked => 'El heredero puede acceder a los fondos';

  @override
  String get inheritanceNeedsSync => 'Sincroniza para comprobar el acceso';

  @override
  String get inheritanceNoFunds => 'Sin fondos confirmados';

  @override
  String get revaultNow => 'Re-vault';

  @override
  String get revaultTitle => 'Reiniciar temporizador de herencia';

  @override
  String get revaultDescription =>
      'Envía todos los fondos de vuelta a esta cartera. Al confirmarse, el temporizador se reinicia — los herederos deben esperar el tiempo completo de nuevo.';

  @override
  String get revaultFeeRateLabel => 'Tasa de comisión (sat/vB)';

  @override
  String get revaultCreateButton => 'Crear transacción re-vault';

  @override
  String get revaultCreating => 'Creando transacción...';

  @override
  String get blocksUnit => 'bloques';

  @override
  String inheritanceHeirN(int n) {
    return 'Heredero $n';
  }

  @override
  String inheritanceEarliestAccess(String duration, int blocks) {
    final intl.NumberFormat blocksNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String blocksString = blocksNumberFormat.format(blocks);

    return 'Acceso del heredero más pronto en ~$duration ($blocksString bloques)';
  }

  @override
  String get scriptTypeLabel => 'Tipo de script';

  @override
  String get scriptTypeLegacy => 'Legacy';

  @override
  String get scriptTypeNested => 'Nested';

  @override
  String get scriptTypeSegwit => 'SegWit';

  @override
  String get scriptTypeTaproot => 'Taproot';

  @override
  String get scriptDescP2pkh =>
      'P2PKH — Estándar más antiguo. Comisiones más altas.';

  @override
  String get scriptDescP2sh =>
      'P2SH — Estándar multifirma más antiguo. Comisiones más altas.';

  @override
  String get scriptDescP2shWpkh =>
      'P2SH-P2WPKH — SegWit envuelto para compatibilidad retroactiva. Rara vez necesario hoy.';

  @override
  String get scriptDescP2shWsh =>
      'P2SH-P2WSH — Multifirma SegWit con compatibilidad retroactiva. Rara vez necesario hoy.';

  @override
  String get scriptDescP2wpkh =>
      'P2WPKH — Estándar moderno más común. Menores comisiones.';

  @override
  String get scriptDescP2wsh =>
      'P2WSH — Multifirma SegWit nativo. Menores comisiones, amplio soporte.';

  @override
  String get scriptDescP2trSinglesig =>
      'P2TR — Taproot. Mejor privacidad y menores comisiones.';

  @override
  String get scriptDescP2trMultisig =>
      'P2TR — Taproot multifirma. Mejor privacidad. Requiere wallets compatibles.';

  @override
  String requiredSignatures(int m, int n) {
    return 'Firmas requeridas: $m de $n';
  }

  @override
  String get decreaseThresholdTooltip => 'Reducir umbral';

  @override
  String get increaseThresholdTooltip => 'Aumentar umbral';

  @override
  String get replaceKeyTooltip => 'Reemplazar clave';

  @override
  String get keyDetailsTooltip => 'Detalles de la clave';

  @override
  String get creatingWalletLabel => 'Creando wallet…';

  @override
  String get addAtLeastOneKey => 'Añade al menos una clave';

  @override
  String get multisigNeedsMinKeys =>
      'Los wallets multifirma necesitan al menos 2 claves';

  @override
  String get hwWalletTitle => 'Hardware wallet';

  @override
  String get hwWalletScanning => 'Buscando dispositivos…';

  @override
  String get hwWalletConnecting => 'Conectando…';

  @override
  String get hwWalletUnlockDevice => 'Desbloquea tu dispositivo…';

  @override
  String get hwWalletNoDevices =>
      'No se detectó ningún hardware wallet.\nAsegúrate de que esté conectado.';

  @override
  String get hwWalletSelectDevice => 'Selecciona un dispositivo';

  @override
  String get hwWalletScanDevices => 'Buscar dispositivos';

  @override
  String get hwWalletPairingCode => 'Código de emparejamiento';

  @override
  String get hwWalletNoConfirmNeeded =>
      'No se requiere confirmación en el dispositivo para exportar claves.';

  @override
  String get hwRegisterWallet => 'Registrar wallet';

  @override
  String get hwRegisterWalletSub => 'Registrar esta política en el dispositivo';

  @override
  String get hwNotRequired => 'No requerido para wallets de clave única';

  @override
  String get hwCheckRegistration => 'Verificar registro';

  @override
  String get hwCheckRegistrationSub =>
      'Verificar si esta política está registrada';

  @override
  String get hwWalletRegistered => 'Wallet registrado en el dispositivo.';

  @override
  String get hwWalletIsRegistered =>
      'El wallet está registrado en este dispositivo.';

  @override
  String get hwWalletNotRegistered =>
      'El wallet NO está registrado en este dispositivo.';

  @override
  String get hwNoDevice => 'Ningún dispositivo conectado';

  @override
  String get hwScanButton => 'Buscar';

  @override
  String get hwDisconnectButton => 'Desconectar';

  @override
  String get hwSelectDevice => 'Selecciona un dispositivo:';

  @override
  String get hwPairingCompare =>
      'Compara con la pantalla del dispositivo y confirma:';

  @override
  String get directSendConfirmTitle => 'Confirmar envío';

  @override
  String get directSendConfirmAction => 'Firmar y retransmitir';

  @override
  String directSendSuccess(String txid) {
    return 'Enviado: $txid';
  }

  @override
  String get accountIndexLabel => 'Account';

  @override
  String get restoreFromSeedMenuLabel => 'Recuperar desde semilla';

  @override
  String get restoreFromSeedTitle => 'Recuperar desde semilla';

  @override
  String get scanAccountsAction => 'Escanear accounts';

  @override
  String get scanAccountsScanning => 'Escaneando accounts…';

  @override
  String scanAccountsScanningHint(int accountGap, int addrGap) {
    return 'Verificando direcciones en Electrum…\n(accounts: $accountGap, dir.: $addrGap)';
  }

  @override
  String get accountGapLimitLabel => 'Límite de accounts vacías';

  @override
  String get addressGapLimitLabel => 'Límite de direcciones';

  @override
  String get scanNonStandardPathsLabel => 'Rutas de derivación no estándar';

  @override
  String get scanNonStandardPathsHint =>
      'Busca también rutas BIP alternativas para cada tipo de script (44/49/84/86)';

  @override
  String get scanAccountsNoActivity =>
      'No se encontraron accounts con actividad previa.';

  @override
  String scanAccountsScannedCount(int count) {
    return 'Se escanearon $count accounts';
  }

  @override
  String scanAccountsFoundBackups(int count) {
    return '$count account(s) encontrado(s)';
  }

  @override
  String scanAccountsNewAccount(int index) {
    return 'Usar nuevo account ($index)';
  }

  @override
  String get scanAccountsNoActivitySubtitle =>
      'Recupera cuentas a partir de una frase semilla';

  @override
  String get restoreFromHwMenuLabel => 'Recuperar desde hardware wallet';

  @override
  String get restoreFromHwMenuSubtitle =>
      'Busca cuentas desde una BitBox02 conectada';

  @override
  String get restoreFromHwTitle => 'Recuperar desde Hardware Wallet';

  @override
  String get hwDiscoveryNoDevice =>
      'No hay hardware wallet conectada. Conecta y empareja tu dispositivo primero.';

  @override
  String get hwDiscoveryStart => 'Buscar cuentas';

  @override
  String hwDiscoveryDeriving(int n, int total) {
    return 'Exportando claves… ($n/$total)';
  }

  @override
  String get hwDiscoveryScanning => 'Escaneando blockchain…';

  @override
  String scanAccountsActivitySummary(int txCount) {
    return '$txCount tx';
  }

  @override
  String get scanAccountsCreateWallet => 'Crear wallet';

  @override
  String get scanAccountsRetry => 'Reintentar';

  @override
  String get searchNostrLabel => 'Buscar backups en Nostr';

  @override
  String get searchNostrHint =>
      'Busca copias de seguridad del descriptor en los relays configurados';

  @override
  String get hwSkipLegacyLabel => 'Omitir derivaciones legacy (P2PKH)';

  @override
  String get hwSkipLegacyHint =>
      'Evita confirmaciones en el dispositivo para rutas m/44’';

  @override
  String get searchNostrScanningHint =>
      'También buscando backups de descriptor en relays Nostr…';

  @override
  String get nostrBackupFoundOnScan => 'Backup Nostr encontrado';

  @override
  String get importFromNostrBackup => 'Restaurar desde Nostr';

  @override
  String get nostrImportTamperTitle => 'Verifica tras importar';

  @override
  String get nostrImportTamperBody =>
      'Cualquier persona que conozca el xpub puede modificar este respaldo. Tras importar, confirma que el descriptor y las direcciones de recepción coincidan con tu billetera esperada antes de enviar fondos.';

  @override
  String get scanTypeAll => 'Todos';

  @override
  String get bip39PassphraseLabel => 'Frase BIP39 (opcional)';

  @override
  String get pressBackAgainToExit => 'Pulsa atrás otra vez para salir';

  @override
  String get feeHistogramTitle => 'Fees próximo bloque';

  @override
  String get feeHistogramNext => 'Siguiente';

  @override
  String get confirm => 'Confirmar';

  @override
  String get ok => 'OK';

  @override
  String get copy => 'Copiar';

  @override
  String get refresh => 'Actualizar';

  @override
  String get tryAgain => 'Intentar de nuevo';

  @override
  String get scanAgain => 'Escanear de nuevo';

  @override
  String get signButton => 'Firmar';

  @override
  String get unlock => 'Desbloquear';

  @override
  String get addPrivateKeyLabel => 'Agregar clave privada';

  @override
  String get addSigningKeyLabel => 'Agregar clave de firma';

  @override
  String get editKeyTitle => 'Editar clave';

  @override
  String get addKeyClipboardSubtitle => 'Portapapeles, archivo o código QR';

  @override
  String get addKeyHwSubtitle => 'Dispositivo USB o Bluetooth';

  @override
  String get addKeyManualTitle => 'Ingresar manualmente';

  @override
  String get addKeyManualSubtitle => 'Watch Only (xpub) o Hot Key (semilla)';

  @override
  String get validating => 'Validando...';

  @override
  String get registeredKeys => 'Claves registradas';

  @override
  String get showRegisteredKeys => 'Mostrar claves registradas';

  @override
  String get enterXpubToUnlock => 'Ingrese xpub para desbloquear';

  @override
  String get xpubUnlockHint =>
      'Pegue cualquier xpub registrado para esta billetera. También se acepta el formato keyspec ([mfp/path]xpub).';

  @override
  String get required => 'Requerido';

  @override
  String get invalidXpubOrKeyspec => 'xpub o keyspec inválido';

  @override
  String get signWithHwWallet => 'Firmar con billetera hardware';

  @override
  String get enterWalletPassword => 'Ingresar contraseña de billetera';

  @override
  String get walletPasswordSubtitle =>
      'Esta billetera está protegida con contraseña.';

  @override
  String get enterBackupPassword => 'Ingresar contraseña de respaldo';

  @override
  String get backupPasswordSubtitle =>
      'Este respaldo está protegido con contraseña.';

  @override
  String get wifPrivateKeyLabel => 'Clave privada WIF';

  @override
  String get verifyButton => 'Verificar';

  @override
  String get derivPathWithoutLeading => 'Sin el prefijo m/';

  @override
  String get nostrRelaysLabel => 'Relays Nostr';

  @override
  String get nostrRelaysSubtitle =>
      'Relays para respaldos cifrados de descriptores';

  @override
  String get nostrRelayAddHint => 'wss://relay.ejemplo.com';

  @override
  String get nostrRelayInvalidUrl => 'La URL debe comenzar con wss:// o ws://';

  @override
  String get nostrRelayDuplicate => 'El relay ya está en la lista';

  @override
  String get nostrRelayAddButton => 'Agregar relay';

  @override
  String get nostrRelayTimeoutLabel => 'Tiempo de espera (segundos)';

  @override
  String get nostrRelayMaxAttemptsLabel => 'Intentos por relay';

  @override
  String get nostrSearchNetworkWarning =>
      'Problemas de conexión con algunos relays Nostr. Es posible que algún backup no se haya encontrado.';

  @override
  String get nostrBackupMenu => 'Respaldo Nostr';

  @override
  String get nostrBackupTitle => 'Respaldo Nostr';

  @override
  String get nostrBackupSubtitle =>
      'Respaldo cifrado del descriptor en relays Nostr';

  @override
  String get nostrBackupPublish => 'Publicar respaldo';

  @override
  String get nostrBackupRefresh => 'Actualizar estado';

  @override
  String get nostrBackupPublished => 'Respaldo publicado';

  @override
  String get nostrBackupSecurityNote =>
      'Cualquier persona con tu xpub puede localizar y descifrar este respaldo. Solo comparte xpubs con co-firmantes de confianza.';

  @override
  String get nostrBackupFound => 'Respaldo encontrado';

  @override
  String get nostrBackupNotFound => 'Sin respaldo';

  @override
  String nostrBackupPartialCosigners(int backedUp, int total) {
    return '$backedUp/$total co-firmantes respaldados';
  }

  @override
  String get nostrBackupError => 'Error en relay';

  @override
  String get nostrBackupNoRelays =>
      'No hay relays configurados. Agregalos en Ajustes → Relays Nostr.';

  @override
  String get nostrBackupChecking => 'Verificando…';

  @override
  String get nostrBackupPublishing => 'Publicando…';

  @override
  String get nostrBackupDelete => 'Eliminar respaldo';

  @override
  String get nostrBackupDeleting => 'Eliminando…';

  @override
  String get nostrBackupDeleted => 'Respaldo eliminado del relay';

  @override
  String get nostrBackupDeleteConfirm =>
      '¿Reemplazar el respaldo en este relay con un evento vacío? El descriptor ya no será recuperable desde este relay.';

  @override
  String get walletCreateFromNostr => 'Restaurar desde Nostr';

  @override
  String get walletCreateFromNostrSub =>
      'Recupera un respaldo de descriptor desde relays Nostr';

  @override
  String get nostrRestoreTitle => 'Restaurar desde Nostr';

  @override
  String get nostrRestoreEnterXpub => 'Ingresa cualquier xpub de la billetera';

  @override
  String get nostrRestoreXpubHint => 'xpub6... o [mfp/ruta]xpub...';

  @override
  String get nostrRestoreSearch => 'Buscar en relays';

  @override
  String get nostrRestoreSearching => 'Buscando en relays…';

  @override
  String get nostrRestoreNotFound =>
      'No se encontró respaldo en los relays configurados';

  @override
  String get nostrRestoreFound => 'Respaldo encontrado';

  @override
  String get nostrRestoreWalletName => 'Nombre de billetera';

  @override
  String get nostrRestoreNetwork => 'Red';

  @override
  String get nostrRestoreDate => 'Respaldado';

  @override
  String get nostrRestoreEnterCredential => 'Ingresa tu xpub para descifrar';

  @override
  String get nostrRestoreImport => 'Importar billetera';

  @override
  String get nostrRestoreImporting => 'Importando billetera…';

  @override
  String get nostrRestoreWatchOnlyNote =>
      'La billetera se importará como solo-lectura. Reconecta tu billetera hardware o agrega tu mnemónico para firmar transacciones.';

  @override
  String get recoverWalletTitle => 'Recuperar Cartera';

  @override
  String get restoreTabXpub => 'xpub';

  @override
  String get restoreTabSeed => 'Semilla';

  @override
  String get restoreTabHardware => 'Hardware';

  @override
  String get restoreXpubEnterXpub =>
      'Ingresa una clave pública extendida para escanear cuentas on-chain y buscar backups en Nostr.';

  @override
  String get restoreXpubScanButton => 'Escanear';

  @override
  String get restoreDefaults => 'Restaurar valores por defecto';

  @override
  String get coinSortLabelSize => 'Monto';

  @override
  String get coinSortLabelAge => 'Edad';

  @override
  String get coinSortSizeDesc => 'Monto: mayor primero';

  @override
  String get coinSortSizeAsc => 'Monto: menor primero';

  @override
  String get coinSortAgeDesc => 'Edad: más antiguo primero';

  @override
  String get coinSortAgeAsc => 'Edad: más reciente primero';

  @override
  String get reorderWallets => 'Reordenar wallets';

  @override
  String get reorderProjects => 'Reordenar proyectos';

  @override
  String get done => 'Listo';

  @override
  String get descriptorSigsTitle => 'Firmas del Descriptor';

  @override
  String get descriptorSigsSubtitle =>
      'Prueba la titularidad de cada clave firmando el hash del descriptor. Protege los backups de manipulaciones.';

  @override
  String descriptorSigsSigned(String date) {
    return 'Firmado · $date';
  }

  @override
  String get descriptorSigsNotSigned => 'Sin firmar';

  @override
  String get descriptorSigsInvalid => 'Firma inválida';

  @override
  String get descriptorSigsSignAction => 'Firmar';

  @override
  String get descriptorSigsDeleteAction => 'Eliminar firma';

  @override
  String get descriptorSigsMethodHotKey => 'HotKey (automático)';

  @override
  String get descriptorSigsMethodBB02 => 'BitBox02';

  @override
  String get descriptorSigsMethodQRMessage => 'QR — Firma de mensaje';

  @override
  String get descriptorSigsMethodQRBip322 => 'QR — BIP322 PSBT';

  @override
  String get descriptorSigsVerifyAll => 'Verificar todas';

  @override
  String get descriptorSigsConnectHw => 'Conectar hardware wallet';

  @override
  String descriptorSigsSummary(int signed, int total) {
    return '$signed/$total claves firmadas';
  }

  @override
  String get descriptorSigsManage => 'Gestionar firmas';

  @override
  String get descriptorSigsMessage => 'Mensaje a firmar';

  @override
  String get descriptorSigsQRMessageHint => 'Firma compacta base64 (65 bytes)';

  @override
  String get descriptorSigsShowPsbtQr =>
      'Mostrar QR del PSBT (escanear con hardware wallet)';

  @override
  String get descriptorSigsQRBip322Hint =>
      'PSBT firmado (base64 o escanear QR)';

  @override
  String get descriptorSigsSignSuccess => 'Firma guardada';

  @override
  String get descriptorSigsDeleteSuccess => 'Firma eliminada';

  @override
  String get descriptorSigsChooseMethod => 'Elige método de firma';

  @override
  String descriptorSigsVerified(String date) {
    return 'Verificado · $date';
  }

  @override
  String descriptorSigsVerifyResult(int valid, int total) {
    return '$valid de $total firmas válidas';
  }

  @override
  String get deriveKeyFirst => 'Deriva la clave primero';

  @override
  String get invalidDerivedKeyspec => 'Keyspec derivado no válido';

  @override
  String get enterValidSeedPhrase =>
      'Introduce primero una frase semilla válida';

  @override
  String get enterXprvKey => 'Introduce una clave xprv';

  @override
  String signingKeyAdded(String mfp) {
    return 'Clave de firma añadida ($mfp)';
  }

  @override
  String mfpMismatch(String mfp, String expected) {
    return 'Discordancia MFP: obtenido $mfp, esperado $expected';
  }

  @override
  String wrongKeyMfp(String mfp, String expected) {
    return 'Clave incorrecta. Obtenida $mfp, esperada $expected';
  }

  @override
  String get derivedKeyspecLabel => 'Keyspec derivado';

  @override
  String mustMatchMfp(String mfp) {
    return 'Debe coincidir con MFP: $mfp';
  }

  @override
  String keyWithMfp(String mfp) {
    return 'Clave: $mfp';
  }

  @override
  String loadWarningCorruptKeys(int count) {
    return 'Se perdieron $count clave(s) de firma por corrupción de la base de datos';
  }
}
