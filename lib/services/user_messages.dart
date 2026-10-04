import 'dart:async';
import 'dart:io';
import 'principal_api.dart';

String userMessage(Object error) {
  if (error is PrincipalApprovalPending) return error.toString();
  final text = error is PrincipalApiException ? error.message : error.toString();
  if (text.contains('SQLite') || text.contains('DatabaseException') || text.contains('PRAGMA')) {
    return 'Les données ne peuvent pas être ouvertes. Ne désinstallez pas l’application. Contactez le responsable.';
  }
  if (error is SocketException || error is TimeoutException || text.contains('SocketException') || text.contains('TimeoutException')) {
    return 'Le Principal ne répond pas. Vérifiez le Wi-Fi et que le logiciel est ouvert sur le PC.';
  }
  if (text.contains('403') || text.contains('non autorisé') || text.contains('désactivé')) {
    return 'Connexion non autorisée. Vérifiez votre code et demandez l’accord du responsable.';
  }
  if (text.contains('protocole') || text.contains('incompatible')) {
    return 'Les versions ne correspondent pas. Demandez la mise à jour au responsable.';
  }
  if (text.contains('FormatException') || text.contains('Réponse') || text.contains('HTTP') || text.contains('refusée (')) {
    return 'L’échange avec le Principal n’a pas abouti. Vos saisies restent conservées. Réessayez.';
  }
  if (error is PrincipalApiException || error is StateError) {
    return text.replaceFirst('Bad state: ', '');
  }
  return 'L’opération n’a pas abouti. Vos données n’ont pas été remises à zéro. Réessayez ou contactez le responsable.';
}
