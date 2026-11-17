# TradMaths

Les mathématiques dans toutes les langues de la classe : ce que dit le professeur s’affiche en français et dans jusqu’à quatre autres langues, avec les mots de maths en couleur.

**En ligne :** https://tom-rougeaud.github.io/tradmaths/

## Nouveautés (novembre 2026)
- Langues favorites (★), conservées dans le navigateur ; export / import / effacement des données.
- Ajouts : suédois ; moteur disponible pour le wolof, le peul et le tchétchène.
- Verbes d’action des manuels « Maths Allophones » niveaux 1, 2 et 3 soulignés en vert, onglet dédié dans le glossaire.
- Plus de 300 mots des manuels ajoutés au glossaire (définitions simples reprises des manuels).
- Écoute de chaque traduction quand une voix existe ; message explicite sinon.
- Lexique de départ tamoul et pachto, et correction de n’importe quelle traduction au crayon.
- Installation sur l’écran d’accueil (PWA), fonctionnement hors ligne pour l’interface.

## Fonctionnement
- `index.html` : l’application. Contenus pédagogiques dans les blocs JSON `tm-verbes` et `tm-curated`.
- `manifest.webmanifest`, `sw.js`, icônes : installation et hors ligne.
- Le texte à traduire est envoyé aux relais de traduction indiqués dans la page « Confidentialité ». Aucun compte, aucun traceur.

## Licence
© Tom Rougeaud — [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/deed.fr).

## Voix naturelles (hors ligne)
Réglages → « Voix naturelles » : ajouter les fichiers `tm-voix-xxx.onnx` (≈ 114 Mo par langue, modèles MMS-TTS de Meta, CC BY-NC 4.0). Ils restent sur l’appareil (IndexedDB), rien n’est envoyé. Moteur : ONNX Runtime Web (dossier `vendor/ort`, MIT). Sans ces voix, l’appli utilise celles du navigateur.
