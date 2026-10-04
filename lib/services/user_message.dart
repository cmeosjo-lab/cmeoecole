/// Internal exceptions remain in the diagnostic log, not in the teacher's screen.
String userMessage(Object error) {
  final raw = error.toString();
  final s = raw.toLowerCase();
  if (s.contains('reste') && (s.contains('envoyer') || s.contains('transmi'))) {
    return 'Des saisies restent à envoyer. Synchronisez avant de vous déconnecter.';
  }
  if (s.contains('refus') && s.contains('appareil')) {
    return 'Cet appareil n’est pas autorisé. Contactez le responsable de l’établissement.';
  }
  if (s.contains('code professeur') && (s.contains('incorrect') || s.contains('refus'))) {
    return 'Le code professeur n’est pas accepté. Vérifiez-le avec le responsable.';
  }
  if (s.contains('désactiv') || s.contains('non autorisé')) {
    return 'L’accès est désactivé. Demandez au responsable de le vérifier sur le Principal.';
  }
  if (s.contains('autoris') && s.contains('attend')) {
    return 'Votre demande attend l’accord du responsable sur le tableau de bord du Principal.';
  }
  if (s.contains('socket') || s.contains('timeout') || s.contains('ne répond') || s.contains('inaccessible')) {
    return 'Le Principal est inaccessible. Vérifiez qu’il est ouvert et que vous êtes sur le même Wi-Fi.';
  }
  if (s.contains('sqlite') || s.contains('database') || s.contains('stockage') || s.contains('endommag')) {
    return 'Les données locales ne peuvent pas être ouvertes. Ne désinstallez pas l’application et contactez le responsable.';
  }
  if (s.contains('incompatib') || s.contains('protocole')) {
    return 'Le Principal et l’application doivent être mis à jour ensemble.';
  }
  if (s.contains('autre professeur') || s.contains('autre établissement') || s.contains('correspond pas')) {
    return 'La connexion ne correspond pas à votre établissement ou à votre professeur. Aucune donnée n’a été remplacée.';
  }
  if (s.contains('sauvegarde')) {
    return 'Cette sauvegarde ne peut pas être utilisée. Vos données actuelles sont conservées.';
  }
  return 'L’opération n’a pas abouti. Vos données sont conservées. Réessayez ou contactez le responsable.';
}
