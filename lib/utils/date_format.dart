/// Formats [unixSecs] as `YYYY-MM-DD HH:MM` (local time).
String formatTimestamp(int unixSecs) {
  final dt = DateTime.fromMillisecondsSinceEpoch(unixSecs * 1000, isUtc: true)
      .toLocal();
  final y = dt.year.toString().padLeft(4, '0');
  final mo = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final h = dt.hour.toString().padLeft(2, '0');
  final mi = dt.minute.toString().padLeft(2, '0');
  return '$y-$mo-$d $h:$mi';
}

/// Formats [dt] as `Mon DD, YYYY` (e.g. "Jan 1, 2024").
String shortDate(DateTime dt) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
}

/// Formats [dt] as `Mon DD, YYYY HH:mm` (e.g. "Apr 12, 2026 14:30").
String shortDateWithTime(DateTime dt) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year} $hh:$mm';
}

/// Formats [dt] as `dd/MM/yyyy HH:mm` (local time, zero-padded).
String formatDateTime(DateTime dt) {
  return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

/// Same as [formatDateTime] but takes Unix seconds.
String formatDateTimeFromUnix(int unixSeconds) =>
    formatDateTime(DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000));
