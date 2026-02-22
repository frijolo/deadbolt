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
  String get shareFile => 'Compartir';

  @override
  String get showQrCode => 'Mostrar código QR';

  @override
  String get scanQrCode => 'Escanear código QR';

  @override
  String get fromFile => 'Desde archivo';

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
}
