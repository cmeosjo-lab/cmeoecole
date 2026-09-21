# GESTCOURS PROF MOBILE V0.5.2

Application Prof mobile locale **Android + iOS**, conçue pour fonctionner avec le **PC Principal GESTCOURS** sur le réseau local.

## Fonctions actuelles

- connexion au Principal par IP/port + professeur + code ;
- QR code facultatif ;
- synchronisation protocole V6 et travail hors connexion ;
- classes et élèves autorisés pour le professeur ;
- appel de classe ;
- absences et retards avec date, justification et heure d'arrivée ;
- évaluations individuelles et saisie par classe ;
- progression Coran : sourate, versets, Hizb et Juz ;
- devoirs ;
- signalements Discipline / Matériel / Devoirs avec listes guidées ;
- historique élève ;
- file locale des saisies avec accusé explicite du Principal ;
- interface Material 3 modernisée et défilable jusqu'au dernier bouton.

## Source de vérité

Le **PC Principal GESTCOURS reste la base officielle**. Android, iOS et le logiciel Prof Windows peuvent coexister. Le mobile conserve uniquement le cache et les saisies nécessaires au professeur.

## Construction Android

Le workflow `.github/workflows/build-android-apk.yml` analyse le vrai code de l'application et compile l'APK. Pour publier un APK capable de mettre à jour les installations existantes, enregistrer la clé stable en secret GitHub Actions :

`GESTCOURS_DEBUG_KEYSTORE_B64`

La clé n'est volontairement pas incluse dans ce paquet source.

## Confidentialité

Ne jamais déposer dans un GitHub public de listes d'élèves réelles, téléphones, e-mails, exports CSV/Excel, sauvegardes, bases locales ou clés de signature.
