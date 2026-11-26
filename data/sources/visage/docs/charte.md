# Visage — charte

> **Direction C4 « Poussière »**, validée le 2026-11-26 parmi huit propositions (quatre directions, puis
> quatre variantes de la direction C).
> Tous les fichiers de `brand/` sortent du kit (`brand/kit/`) : on modifie le kit, jamais les fichiers.

---

## 1. L'idée

Un visage fait de points sur une grille. Les points grossissent vers le bord, comme la lumière d'un
contour. Le côté droit se défait en poussière : c'est l'instant où l'hologramme apparaît ou disparaît.
La lumière est chaude, celle d'un projecteur, loin du cyan qu'utilisent presque tous les hologrammes.

Le signe annonce le rendu de l'app : un visage en points qui se forme, parle, puis se défait.

## 2. Les fichiers

| Fichier | Usage | Fond |
|---|---|---|
| `mark.svg` | Le signe seul. | sombre |
| `mark-light.svg` | Le signe seul. | clair |
| `mark-mono.svg` | Une seule couleur (noir) : impression, gravure, tampon. | clair |
| `wordmark.svg` | Le nom seul, en points. | sombre |
| `lockup.svg` | Le signe et le nom côte à côte. | sombre |
| `lockup-light.svg` | Le signe et le nom côte à côte. | clair |
| `banner.svg` | L'en-tête du README : signe, nom, faisceau, lignes de balayage. | le sien |
| `app-icon.svg` | Le dessin de référence de l'icône d'app (1024). | le sien |
| `menubar.svg` | Le gabarit de l'icône de barre des menus (18 points, noir). | — |
| **Animés** | | |
| `mark-animated.svg` | Le signe se défait puis se reforme, en boucle de 10 s. | sombre |
| `mark-speaking.svg` | Le visage entier qui parle : bouche sur 2,4 s, clignement toutes les 4,6 s. | sombre |
| `banner-animated.svg` | L'en-tête du README, animé : le signe se défait, une bande de balayage descend, la lumière vacille. | le sien |

Les animations sont en SMIL : elles tournent dans tous les navigateurs et dans un README GitHub, sans
script.

**L'icône d'app n'est pas un fichier.** Comme pour Awake et Siphon, la construction de l'app la dessine
avec Core Graphics (`brand/generate.sh --iconset <dossier>`, puis `iconutil -c icns`). En dessous de
64 pixels, elle reprend le dessin de la barre des menus : le signe complet y devient une tache.

**La barre des menus** : l'app dessine l'icône en code, comme image gabarit (macOS la teinte selon le
thème). `menubar.svg` n'en est que la référence.

## 3. Les couleurs

| Nom | Code | Rôle |
|---|---|---|
| Charbon | `#0E0C0A` | fond |
| Braise | `#FFC978` | points, accent, couleur de l'hologramme par défaut |
| Or pâle | `#FFE9C4` | texte sur fond sombre, reflets |
| Cendre | `#6E655B` | texte secondaire |
| Fumée | `#EDE6DC` | surfaces claires |
| Brou | `#3A2612` | points sur fond clair, chaleur des dégradés |

La braise ne se pose jamais sur du blanc : trop peu de contraste. Sur fond clair, les points passent en
brou.

## 4. Le nom et les polices

- **Le nom s'écrit en points**, dessinés par le kit (une matrice de points dans l'esprit de la police
  Doto). Aucune police ne voyage avec les fichiers.
- **Pour le web et les visuels** : Doto (licence OFL) pour le nom quand il s'écrit en texte, jamais en
  texte courant ; IBM Plex Sans pour le texte ; IBM Plex Mono pour les mesures.
- **Dans l'app** : la police du système (SF Pro, SF Mono). L'app reste native et n'embarque aucune
  police : c'est un choix de dépendances minimales, à ne pas confondre avec un écart de charte.

## 5. Les règles

- **Zone de protection** : autour du signe, un vide d'au moins un quart de sa largeur.
- **Tailles minimales** : le signe complet à partir de 48 pixels ; en dessous, le dessin de la barre des
  menus.
- **Les points de poussière font partie du signe** : on ne les remet pas en place dans la version
  fixe, et on ne les retire pas.
- **À ne pas faire** : recolorer en cyan ou en dégradé, ajouter un contour ou une ombre portée au signe
  seul, déformer, réarranger les points à la main, mettre le nom dans une autre police.
- **Le mouvement** : le signe ne fait que trois choses. Il se défait et se reforme, il respire au
  repos, il parle. Rien d'autre (ni rotation, ni rebond).

## 6. Le mouvement

| Animation | Durée | Déroulé |
|---|---|---|
| Se défaire, se reformer | 10 s | entier jusqu'à 1,8 s ; les points de droite partent les premiers et arrivent vers 4,8 s ; tenue ; retour à partir de 6,2 s, les plus à droite reviennent les derniers, vers 9,2 s |
| Parler | 2,4 s (bouche), 4,6 s (yeux) | la bouche s'ouvre sur un rythme irrégulier, le milieu davantage ; les yeux clignent sur leur propre rythme, pour que les deux ne se calent jamais |

L'app reprend ces courbes : apparition à la connexion, veille en poussière (spécification, § 7.2).

## 7. Régénérer

```shell
sh data/sources/visage/brand/generate.sh                          # les fichiers SVG
sh data/sources/visage/brand/generate.sh --iconset /tmp/Visage.iconset   # et l'icône
```

Les tirages au hasard du kit sont graines : le logo reste identique, point par point, à celui qui a été
validé (vérifié le 2026-11-26 contre le générateur de la page de choix : 223 points identiques).
