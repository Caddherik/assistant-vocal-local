# Assistant vocal local

Un assistant vocal personnel qui tourne **entièrement sur l'iPhone** : reconnaissance vocale, modèle de langage et synthèse vocale d'Apple, sans serveur et sans compte tiers. Projet perso et pédagogique.

- **Pas de Mac** : l'app est compilée par GitHub Actions (runner `xcode-27`), puis installée depuis Windows avec Sideloadly.
- **Aucune donnée** dans ce dépôt : uniquement du code.
- **Aucun appel réseau** en Phase 1. Vérifiable dans Réglages › Confidentialité et sécurité › Rapport de confidentialité des apps.

## État

| Étape | Contenu | État |
|---|---|---|
| 1a-1 | Écran Diagnostic : appareil, mémoire, chaleur, modèle Apple, langues, voix, tests chronométrés | fait, validé sur iPhone |
| 1a-2 | Appui long → transcription → réponse en streaming → voix, réglages, latences mesurées | en cours |
| 1b | Mains libres, coupure de la voix quand on reparle, second modèle (MLX) | à venir |

## Compiler

Chaque push sur `main` lance [le workflow](.github/workflows/build.yml) : XcodeGen génère le projet à partir de `project.yml`, `xcodebuild` compile sans signature, et le `.ipa` est publié comme **artefact** du run (gardé 14 jours).

## Installer sur l'iPhone depuis Windows (Sideloadly)

À faire une seule fois :
1. Installer **iTunes** et **iCloud** en version web, depuis le site d'Apple (pas celles du Microsoft Store), puis **Sideloadly** ([sideloadly.io](https://sideloadly.io)).
2. Brancher l'iPhone en USB, le déverrouiller, puis toucher « Se fier à cet ordinateur ».
3. Sur l'iPhone, activer **Réglages › Confidentialité et sécurité › Mode développeur**. L'iPhone redémarre ; confirmer après le redémarrage.

À chaque nouvelle version :
1. Télécharger l'artefact `AssistantVocal-N` du dernier run vert (onglet *Actions* du dépôt) et le dézipper pour récupérer `AssistantVocal.ipa`.
2. Dans Sideloadly, glisser le `.ipa`, choisir l'iPhone, saisir l'identifiant Apple (compte gratuit), puis cliquer sur **Start**.
3. Première installation seulement : sur l'iPhone, ouvrir **Réglages › Général › VPN et gestion de l'appareil**, choisir le profil de l'identifiant Apple, puis toucher **Faire confiance**.

Avec un compte gratuit, l'app expire au bout de **7 jours**. Le *Sideloadly Daemon* la re-signe tout seul quand le PC voit l'iPhone (en Wi-Fi ou en USB).
