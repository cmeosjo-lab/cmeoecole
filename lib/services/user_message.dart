String userMessage(Object error, {String fallback = 'Cette opération n’a pas abouti. Réessayez.'}) {
  final text = error.toString();
  final lower = text.toLowerCase();
  if (lower.contains('databaseexception') || lower.contains('sqlite') || lower.contains('json') || lower.contains('formatexception')) {
    return 'Les données ne peuvent pas être ouvertes. Elles n’ont pas été effacées. Ne désinstallez pas l’application.';
  }
  if (lower.contains('socketexception') || lower.contains('clientexception') || lower.contains('timeoutexception')) {
    return 'Le Principal n’est pas joignable. Vérifiez le Wi-Fi et que le logiciel est ouvert sur le PC.';
  }
  if (lower.contains('http') || lower.contains('stacktrace') || lower.contains('pragma')) return fallback;
  return text.replaceFirst(RegExp(r'^(Bad state: |Exception: )'), '');
}
