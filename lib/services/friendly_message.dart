import 'dart:async';
import 'dart:io';
import 'principal_api.dart';

String friendlyMessage(Object error) {
  final text = error.toString();
  if (error is PrincipalApiException &&
      !RegExp(
        r'HTTP|https?://|SocketException|DatabaseException|PRAGMA',
        caseSensitive: false,
      ).hasMatch(text)) {
    return text;
  }
  if (error is TimeoutException ||
      error is SocketException ||
      RegExp(
        r'SocketException|TimeoutException|ClientException|Connection refused|Failed host lookup',
        caseSensitive: false,
      ).hasMatch(text)) {
    return 'Le Principal ne répond pas. Vérifiez que le PC est ouvert et que vous êtes sur le même Wi-Fi. Vos saisies restent conservées.';
  }
  if (RegExp(
    r'DatabaseException|PRAGMA|SQLite|SQLITE_|database is|Bad state:.*base',
    caseSensitive: false,
  ).hasMatch(text)) {
    return 'Les données ne peuvent pas être ouvertes. Ne désinstallez pas l’application et contactez le responsable.';
  }
  if (error is FormatException ||
      RegExp(
        r'FormatException|Unexpected character',
        caseSensitive: false,
      ).hasMatch(text)) {
    return 'Les informations reçues sont illisibles. Réessayez ou contactez le responsable.';
  }
  if (error is StateError) {
    final clean = error.message.toString();
    if (!RegExp(
      r'JSON|sqlite|Exception|\bSELECT\b|\bINSERT\b',
      caseSensitive: false,
    ).hasMatch(clean)) {
      return clean;
    }
  }
  if (RegExp(
        r'code professeur|appareil|désactivé|autorisation|Versions incompatibles|établissement|Réseau local|Wi-Fi',
        caseSensitive: false,
      ).hasMatch(text) &&
      !text.contains('://')) {
    return text;
  }
  return 'L’opération n’a pas abouti. Vos saisies sont conservées. Réessayez ou contactez le responsable.';
}
