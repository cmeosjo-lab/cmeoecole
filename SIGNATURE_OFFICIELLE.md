# Signature Android officielle GESTCOURS

À partir de **GESTCOURS Prof Mobile V0.5.6+13**, les versions officielles doivent être signées avec la même clé de diffusion permanente.

- Alias public : `gestcours-release`
- Certificat : `CN=GESTCOURS Release, O=GESTCOURS, C=MA`
- SHA-256 du certificat :
  `8C:7E:E6:A6:0B:86:87:A5:FF:F7:3F:CC:C6:D4:9B:06:BF:BB:F8:43:DF:44:81:88:67:BF:5E:B2:E7:14:C1:73`

La clé privée et ses mots de passe ne doivent jamais être placés dans ce dépôt.

Le workflow peut publier une APK **VALIDATION** sans secrets. Il ne publie une APK **OFFICIELLE** que lorsque les quatre secrets privés `GESTCOURS_RELEASE_*` sont configurés.
