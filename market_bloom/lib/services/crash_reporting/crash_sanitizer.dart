class CrashSanitizer {
  const CrashSanitizer();

  Map<String, Object> sanitize(Map<String, Object?> values) {
    final result = <String, Object>{};
    for (final entry in values.entries) {
      final key = entry.key.trim();
      final lower = key.toLowerCase();
      if (key.isEmpty || _isSensitive(lower)) continue;
      final value = entry.value;
      if (value is bool || value is num) {
        result[key] = value!;
      } else if (value is String) {
        result[key] = _safeText(value);
      }
    }
    return result;
  }

  String safeType(Object error) => _safeText(error.runtimeType.toString());

  String safeLibrary(String? value) => _safeText(value ?? 'unknown');

  String _safeText(String value) {
    final collapsed = value.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
    return collapsed.length <= 80 ? collapsed : collapsed.substring(0, 80);
  }

  bool _isSensitive(String key) =>
      key.contains('secret') ||
      key.contains('token') ||
      key.contains('receipt') ||
      key.contains('verification') ||
      key.contains('payload') ||
      key.contains('save') ||
      key.contains('account') ||
      key.contains('device') ||
      key.contains('transaction') ||
      key.contains('purchase');
}
