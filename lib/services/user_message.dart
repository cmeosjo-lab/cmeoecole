/// Keep implementation details, file paths and request URLs out of everyday screens.
String userMessage(Object error, {String? fallback}) {
  final text = error.toString().toLowerCase();
  if (text.contains('demande envoyée') ||
      text.contains('attend une autorisation')) {
    return 'Demande envoyée. L’administration doit l’accepter sur le tableau de bord du Principal.';
  }
  if (text.contains('refusée par l’administration') ||
      text.contains('appareil désactivé') ||
      text.contains('appareil non autorisé')) {
    return 'Cet appareil n’est pas autorisé. Contactez l’administration.';
  }
  if (text.contains('code professeur incorrect') ||
      text.contains('code professeur refusé') ||
      text.contains('code refusé')) {
    return 'Vérifiez votre code professeur auprès de l’administration.';
  }
  if (text.contains('incompatible') || text.contains('versions')) {
    return 'Les logiciels doivent être mis à jour. Contactez l’administration.';
  }
  if (text.contains('sqlite') ||
      text.contains('databaseexception') ||
      text.contains('stockage') ||
      text.contains('base locale') ||
      text.contains('données locales')) {
    return 'Les données locales ne peuvent pas être ouvertes. Ne désinstallez pas l’application et contactez l’administration.';
  }
  if (text.contains('non transmises') || text.contains('restent à envoyer')) {
    return 'Des saisies restent à envoyer. Synchronisez avant de vous déconnecter.';
  }
  if (text.contains('qr'))
    return 'Ce QR n’est pas un code de connexion GESTCOURS valide.';
  if (text.contains('autre professeur') ||
      text.contains('établissement différent') ||
      text.contains('ne correspond pas')) {
    return 'Cette connexion ne correspond pas à votre établissement ou à votre professeur. Les saisies restent conservées.';
  }
  if (text.contains('socket') ||
      text.contains('timeout') ||
      text.contains('réseau') ||
      text.contains('wifi') ||
      text.contains('wi-fi') ||
      text.contains('connexion impossible') ||
      text.contains('principal ne répond') ||
      text.contains('principal indisponible')) {
    return 'Le Principal est injoignable. Vérifiez qu’il est ouvert et que vous êtes sur le même Wi-Fi.';
  }
  return fallback ??
      'L’opération n’a pas abouti. Réessayez ou contactez l’administration. Les données sont conservées.';
}
