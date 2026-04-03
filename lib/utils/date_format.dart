/// Formats [dt] as `dd/MM/yyyy HH:mm` (local time, zero-padded).
String formatDateTime(DateTime dt) {
  return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

/// Same as [formatDateTime] but takes Unix seconds.
String formatDateTimeFromUnix(int unixSeconds) =>
    formatDateTime(DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000));
