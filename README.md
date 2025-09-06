# Morpion accessible (Tic-Tac-Toe)

Un jeu de morpion simple, jouable au clavier et compatible avec les lecteurs d’écran.

## Démarrage

Ouvrez `index.html` dans votre navigateur. Aucun serveur requis.

## Commandes et accessibilité

- Navigation: Tabulation et flèches pour se déplacer entre les cases
- Action: Entrée ou Espace pour jouer dans la case focalisée
- Annonces: région avec `role="status"` (`aria-live="polite"`)
- Libellés: `aria-label` dynamique indiquant la position (ligne/colonne) et l’état

## Structure

- `index.html`: structure et ARIA
- `styles.css`: styles responsives, focus visibles
- `script.js`: logique du jeu, navigation clavier, annonces

## Licence

MIT
