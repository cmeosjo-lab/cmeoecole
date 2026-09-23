GESTCOURS PROF MOBILE — iOS — V0.5.6
========================================

BASE
----
Cette version iOS utilise exactement le même code Flutter fonctionnel que la version Android V0.5.6+13.

RÉSEAU
------
- connexion au PC Principal par adresse IP locale + code professeur ;
- port Principal : 47831 ;
- fonctionnement applicatif sur le LAN de l’établissement, sans dépendance Internet ;
- autorisation iOS "Réseau local" demandée lors du premier accès au Principal ;
- HTTP local autorisé via NSAppTransportSecurity / NSAllowsLocalNetworking.

CAMÉRA
------
Le QR code reste facultatif.
La caméra n'est demandée que si le professeur utilise le scanner QR.

COMPATIBILITÉ
-------------
- iOS 15 ou version ultérieure ;
- build iPhone ARM64 ;
- même protocole réseau V6 que l'Android V0.5.6.

COMPILATION
-----------
Le workflow GitHub ".github/workflows/build-ios.yml" :
1. installe Flutter sur un runner macOS ;
2. génère le projet Xcode iOS ;
3. applique automatiquement les permissions iOS ;
4. exécute flutter analyze ;
5. compile l'application iPhone en release avec --no-codesign ;
6. publie le .app non signé comme artifact.

INSTALLATION SUR IPHONE
-----------------------
Apple exige une signature Apple et un provisioning profile pour installer l'application
sur un iPhone réel.

Le build non signé sert à valider que le code iOS compile réellement.
Pour générer l'IPA installable, il faut ensuite une identité Apple Developer et le mode
de distribution choisi (App Store/TestFlight, Ad Hoc ou distribution d'organisation).
