const _units = ['o', 'Ko', 'Mo', 'Go', 'To', 'Po'];

String formatBytes(num bytes) {
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < _units.length - 1) {
    v /= 1024;
    i++;
  }
  final digits = i == 0 || v >= 100 ? 0 : (v >= 10 ? 1 : 2);
  return '${v.toStringAsFixed(digits).replaceAll('.', ',')} ${_units[i]}';
}

String formatSpeed(num bytesPerSecond) => '${formatBytes(bytesPerSecond)}/s';

/// Durée en secondes ; Transmission renvoie -1 (indisponible) ou -2 (inconnue).
String formatDuration(int seconds) {
  if (seconds < 0) return '∞';
  if (seconds < 60) return '$seconds s';
  final m = seconds ~/ 60;
  if (m < 60) return '$m min';
  final h = m ~/ 60;
  if (h < 24) return '$h h ${(m % 60).toString().padLeft(2, '0')}';
  return '${h ~/ 24} j ${h % 24} h';
}

String formatRatio(double ratio) {
  if (ratio == -2) return '∞';
  if (ratio < 0) return '—';
  return ratio.toStringAsFixed(2).replaceAll('.', ',');
}

String formatPercent(double fraction) =>
    '${(fraction * 100).toStringAsFixed(fraction >= 1 ? 0 : 1).replaceAll('.', ',')} %';

String formatDate(DateTime d) {
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}

String formatAgo(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return "à l'instant";
  if (diff.inHours < 1) return 'il y a ${diff.inMinutes} min';
  if (diff.inDays < 1) return 'il y a ${diff.inHours} h';
  if (diff.inDays < 30) return 'il y a ${diff.inDays} j';
  return formatDate(d).substring(0, 10);
}

DateTime fromEpoch(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
