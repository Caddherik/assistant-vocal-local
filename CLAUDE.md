# Assistant vocal local — consignes pour Claude

- Le suivi du projet (brief, veille, architecture, journal) vit hors de ce dépôt, dans les notes personnelles du propriétaire. Ici, seulement le code.
- **Dépôt PUBLIC** : jamais de donnée clinique, de nom de patient, de clé, ni d'adresse de serveur personnel.
- **Pas de Mac.** On ne compile qu'à travers GitHub Actions. Boucle : push → `gh run watch` → `gh run view --log-failed` → correctif.
- Le projet Xcode est généré par XcodeGen (`project.yml`). Ne jamais écrire de `.pbxproj` à la main, ni le committer.
- Cible : iOS 27.0, Swift 6, concurrence stricte. Une seule cible d'app, aucune extension : le compte Apple gratuit limite le nombre d'App IDs.
- Aucune dépendance tierce qui fait du réseau. En Phase 1, aucun appel réseau du tout.
- Messages de commit en français.
- Rien de personnel dans le code (prénom, métier, adresses) : la personnalisation de l'assistant vit dans les Réglages de l'app, sur l'iPhone.
