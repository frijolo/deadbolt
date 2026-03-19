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
  String get walletTypeLabel => 'Tipo de billetera';

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
  String get discardChangesTooltip => 'Descartar cambios';

  @override
  String get moreOptionsTooltip => 'Más opciones';

  @override
  String get buildFabLabel => 'Construir';

  @override
  String get descriptorOutdatedBanner =>
      'Descriptor desactualizado · toca Construir para regenerar';

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
  String get descriptorSectionTitle => 'Descriptor';

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
  String get close => 'Cerrar';

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
  String get spendPathNameDialogTitle => 'Nombre de ruta de gasto';

  @override
  String get keyPathBadge => 'RUTA CLAVE';

  @override
  String get setAsKeyPath => 'Establecer como ruta clave';

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
  String get sweepCostLabel => 'Coste de barrido';

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
  String get walletTypeP2shWpkh => 'Segwit Anidado (P2SH-WPKH)';

  @override
  String get walletTypeP2shWsh => 'Segwit Anidado (P2SH-WSH)';

  @override
  String get walletTypeUnknown => 'Desconocido';

  @override
  String get navDesigner => 'Diseñador';

  @override
  String get navWallet => 'Billetera';

  @override
  String get walletsTitle => 'Billeteras';

  @override
  String get noWallets => 'No hay billeteras.\nToca + para crear una.';

  @override
  String get noWalletsGuidedTitle => 'Aún no hay billeteras';

  @override
  String get noWalletsGuidedBody =>
      'Paso 1: Ve al Diseñador para analizar tu descriptor.\nPaso 2: Vuelve aquí para crear una billetera.';

  @override
  String get goToDesigner => 'Ir al Diseñador';

  @override
  String get enterDescriptorManually => 'Ya tengo un descriptor';

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
  String get deleteWalletTitle => 'Eliminar billetera';

  @override
  String deleteWalletConfirm(String name) {
    return '¿Eliminar \"$name\"?';
  }

  @override
  String get createWalletTitle => 'Nueva Billetera';

  @override
  String get walletNameLabel => 'Nombre de billetera';

  @override
  String get walletNameRequired => 'El nombre es obligatorio';

  @override
  String get sourceProjectLabel => 'Origen';

  @override
  String get sourceProjectFromProject => 'Desde proyecto';

  @override
  String get sourceProjectManual => 'Descriptor manual';

  @override
  String get selectProjectLabel => 'Seleccionar proyecto';

  @override
  String get newProjectEntry => 'Nuevo proyecto…';

  @override
  String get createWalletButton => 'Crear Billetera';

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
  String get notYetSynced => 'No sincronizado aún';

  @override
  String lastSynced(String time) {
    return 'Última sincronización: $time';
  }

  @override
  String get syncButton => 'Sincronizar';

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
  String get txLabelHint => 'Añadir etiqueta...';

  @override
  String get txLabelRemove => 'Eliminar etiqueta';

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
  String get coinLabelHint => 'Añadir etiqueta...';

  @override
  String get coinLabelRemove => 'Eliminar etiqueta';

  @override
  String get coinOutpoint => 'Punto de salida';

  @override
  String get coinValue => 'Valor';

  @override
  String get coinAddress => 'Dirección';

  @override
  String get coinKeychain => 'Llavero';

  @override
  String get coinKeychainReceive => 'Recepción';

  @override
  String get coinKeychainChange => 'Cambio';

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
  String get descriptorTabLabel => 'Descriptor';

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
  String spendPathLockedBlocks(int blocks) {
    final intl.NumberFormat blocksNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String blocksString = blocksNumberFormat.format(blocks);

    return '$blocksString bloques restantes';
  }

  @override
  String get spendPathNeedsConfirmation => 'Necesita confirmación';

  @override
  String get spendPathUnconfirmed => 'Sin confirmar';

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
  String get psbtLabelHint => 'Añadir etiqueta...';

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
}
