# Visage — spécification

> **Statut** : proposition du 2026-11-26. Les cinq questions de départ sont tranchées (§ 0) ; restent les
> risques à lever au pilote (§ 12).
> **En une phrase** : une app Mac gratuite qui donne un visage hologramme, animé au rythme de sa voix,
> à l'IA avec laquelle on parle déjà (Claude ou ChatGPT), sans rien payer de plus que son abonnement.
> L'app est offerte en open source, dans `macos-utils`.

---

## 0. Décisions du 2026-11-26

| # | Question | Décision |
|---|---|---|
| Q1 | D'où viennent les têtes ? | **MakeHuman**, par son extension Blender **MPFB2** et le pack **faceunits01** (52 formes ARKit) : licence CC0, communauté active, même maillage pour toutes les têtes (§ 8.1). |
| Q2 | Combien de visages ? | **10** : 5 hommes et 5 femmes, inventés, d'âges et d'origines variés. |
| Q3 | Quelle fenêtre ? | **Trois modes** : transparente (par défaut), flottante, classique (§ 9). |
| Q4 | Quel dépôt ? | **Public, sous licence MIT** : un cadeau. Visage rejoint **`macos-utils`** (public, MIT), dans `data/sources/visage/` (§ 10.1). |
| Q5 | Un mode navigateur ? | **Non** : l'app officielle seulement. |
| Q6 | Quelle identité ? | **C4 « Poussière »** : un visage en points qui se défait en poussière, en lumière de braise. Charte dans `docs/charte.md`, fichiers dans `brand/`. |

## 1. Le but

Quand on parle à Claude (ou ChatGPT) en mode vocal sur le Mac, un visage hologramme flotte sur le bureau
et parle avec sa voix. Il est assez juste pour qu'**on croie que c'est lui qui parle**. On le choisit parmi
10 visages, 5 hommes et 5 femmes.

## 2. Principes

| Principe | Ce qu'il impose |
|---|---|
| **Gratuit à faire tourner** | Aucune API payante, aucun serveur. On se sert du mode vocal de l'app officielle, inclus dans l'abonnement. |
| **Le moins de dépendances possible** | Aucun paquet tiers : Swift et les frameworks d'Apple uniquement. Les outils de la porte sont fournis avec Swift. Blender ne sert qu'à régénérer les visages, jamais à construire l'app. |
| **Rien ne sort du Mac** | Visage n'ouvre aucune connexion réseau. Il ne voit ni identifiants, ni jetons, ni texte : seulement le son de l'app choisie. |
| **On y croit** | La synchro, l'anticipation des lèvres et la vie du visage passent avant tout le reste (§ 7). |
| **Un vrai hologramme** | Un effet travaillé en couches, pas un simple filtre bleu (§ 8.2). |
| **Un cadeau** | Code sous MIT dans `macos-utils`, visages issus d'éléments CC0. Tout ce que Visage ajoute au dépôt peut être redistribué librement. |
| **Claude ou ChatGPT** | Une même mécanique pour les deux : Visage suit le son d'une app, pas son interface. |

## 3. Comment ça marche

```
 App officielle (Claude Desktop ou ChatGPT), mode vocal
        │ son de cette app seule, coupé à la sortie pendant la capture (« tap » Core Audio)
        ▼
 ┌──────────────────────── Visage ─────────────────────────┐
 │  tampon circulaire, retard fixe D ≈ 150 ms              │
 │      │                                    │             │
 │      ▼ analyse « en avance »              ▼             │
 │  énergie, intonation, formants,     relecture du son    │
 │  fricatives, occlusions             avec le retard D    │
 │      │                                    │             │
 │      ▼                                    │             │
 │  animation : 52 formes ARKit,             │ haut-parleur│
 │  tête, regard, états                      │ ou casque   │
 │      │                                    │             │
 │      ▼                                    │             │
 │  rendu Metal hologramme ◀── même horloge ─┘             │
 └──────────────────────────────────────────────────────────┘
```

**La clé** : Visage coupe le son de l'app IA et le rejoue lui-même avec environ 150 ms de retard. Pendant
ce temps, l'analyse voit déjà la suite. La bouche peut donc **anticiper** le son, comme chez un humain, au
lieu d'être toujours en retard, ce que le cerveau repère tout de suite. Dans une conversation, 150 ms de plus
avant la réponse ne s'entendent pas.

## 4. « Se connecter à mon IA »

### 4.1 Pourquoi pas une vraie connexion au compte

- Une clé API serait **payante**, à la minute de conversation.
- Anthropic n'autorise pas une app tierce à proposer la connexion claude.ai ni à utiliser les limites d'un
  abonnement (conditions rappelées dans la documentation du Claude Agent SDK).
- Le mode vocal de chaque app est déjà bien fait (voix, interruption, choix du modèle) : on ne le refait pas.

« Se connecter à mon IA » (*Connect my AI* dans l'interface anglaise), c'est donc **se brancher sur l'app
officielle**, déjà connectée à ton compte.

### 4.2 Le parcours

1. Au premier lancement, l'écran **« Se connecter à mon IA »** affiche deux cartes : **Claude** et
   **ChatGPT**. Chaque carte dit si l'app est installée et ouverte. Un lien « Autre application… » liste les
   apps qui jouent du son.
2. Clic sur **Claude** : si l'app n'est pas installée, la carte mène à sa page de téléchargement officielle.
   Sinon, Visage l'ouvre.
3. macOS demande, une seule fois, l'autorisation d'enregistrer l'audio du système.
4. Visage se branche. Son état devient **« Connecté à Claude — lance le mode vocal »**, et la tête se
   matérialise (§ 8.2), puis s'anime au repos (respiration, clignements).
5. On lance le mode vocal dans Claude. Dès la première phrase, le visage parle.

Le choix est mémorisé : aux lancements suivants, Visage se rebranche seul, et il se rebranche aussi quand
l'app IA redémarre.

### 4.3 Les sources

| Source | Mode vocal sur Mac | À savoir |
|---|---|---|
| **Claude Desktop** (source principale) | Oui, en bêta, sur toutes les offres | Les langues autres que l'anglais sont en bêta. La voix compte dans les limites d'usage de l'abonnement. Fable n'est pas disponible en mode vocal. |
| **ChatGPT** (app Mac) | Oui | L'ancienne app s'appelle désormais « ChatGPT Classic » : les deux sont à reconnaître. |
| **Autre application** | Selon l'app | Toute app qui joue du son : même mécanique, sans garantie. |

Seules les apps sont prises en charge : pas de mode navigateur (Q5).

## 5. Capture et relecture du son

- **API** : les « taps » Core Audio par processus (macOS 14.2 et plus). On crée un `CATapDescription` sur
  les processus audio de l'app IA, avec `muteBehavior` à `.mutedWhenTapped`, puis un périphérique agrégé
  qui porte ce tap, et une fonction de rappel (`IOProc`) qui lit des trames en float 32 bits. Le tap est
  **privé** : un tap public survit au processus qui l'a créé (pilote, § 2.2).
- **Trouver le bon processus** : la liste `kAudioHardwarePropertyProcessObjectList`, filtrée par
  identifiant de bundle (`kAudioProcessPropertyBundleID`). Claude Desktop est une app Electron, dont le son
  sort d'un processus auxiliaire : on filtre donc par préfixe d'identifiant et par PID responsable. Les
  identifiants exacts des deux apps sont relevés au pilote (lot 0), pas devinés.
- **Couper sans perdre** : tant que le tap est actif, le son de l'app IA n'atteint plus le haut-parleur, et
  c'est Visage qui le rejoue.
- **Tampon** : un tampon circulaire sans verrou (un producteur : l'`IOProc` ; un consommateur : la
  relecture). Le retard **D vaut 150 ms par défaut, réglable de 80 à 300 ms**. Aucune allocation ni aucun
  verrou sur le fil temps réel.
- **Relecture** : dans la même `IOProc`, sur la sortie de l'agrégat, dont le périphérique principal est la
  sortie par défaut : capture et relecture partagent une horloge, sans dérive (validé au pilote). Quand la
  sortie par défaut change (casque branché, AirPods), Visage reconstruit l'agrégat.
- **Démarrage hors du fil principal** : tant que l'autorisation n'est pas donnée, `AudioDeviceStart` reste
  bloqué (90 s au pilote). L'interface dit « en attente de ton autorisation ».
- **Autorisation manquante** : aucun cycle audio dans les 3 s qui suivent le démarrage. Visage ouvre alors
  le panneau *Enregistrement de l'écran et de l'audio du système* de Réglages Système.
- **Une seule horloge** : tout est daté en temps hôte (`mHostTime`) — capture, relecture, image affichée.
- **Sûreté** : si Visage quitte ou plante, le son de l'IA doit revenir seul : la coupure ne dure que
  pendant la lecture du tap, et l'agrégat meurt avec le processus. **Bloquant** (critère 6, § 11.3) :
  mesuré au micro par le pilote (tests 2 et 3). Au lancement, Visage détruit tout tap public nommé
  « Visage » laissé par une version qui aurait planté.
- **Micro (option)** : Visage lit seulement le niveau du micro, pour l'état « écoute ». Il n'enregistre
  rien.

## 6. Analyse de la voix

### 6.1 V1 : sans modèle, en traitement du signal

Fenêtres de 25 ms, pas de 10 ms (100 trames par seconde), tout en Accelerate (`vDSP`) :

| Mesure | Méthode | Sert à |
|---|---|---|
| Énergie, voisement | RMS en dB, taux de passage par zéro | parle ou se tait, ouverture de la mâchoire |
| Intonation (F0) | YIN | sourcils, hochements, questions |
| Voyelles en continu | formants F1, F2, F3 par LPC (Levinson-Durbin), pics de l'enveloppe | F1 donne l'ouverture ; F2 l'avant ou l'arrière (lèvres étirées ou arrondies) ; un F3 abaissé l'arrondi (le « u » et le « eu » du français) |
| Fricatives | centre de gravité du spectre, énergie au-dessus de 4 kHz | « s/z » lèvres étirées et dents ; « ch/j » lèvres avancées ; « f/v » lèvre inférieure sous les dents |
| Occlusions | chute d'énergie suivie d'une explosion ; murmure nasal (basses fortes, aigus faibles) | « b/p » : lèvres fermées avant le son ; « m » : lèvres fermées |

**Normalisation automatique** : Visage apprend la plage de F0, F1 et F2 de la voix pendant la première
minute (percentiles glissants), puis la mémorise par source et par voix. Aucun étalonnage manuel.

**Pourquoi sans modèle d'abord** : aucune dépendance, aucun fichier lourd, indépendant de la langue (le
français marche comme l'anglais), et quelques pour cent d'un cœur suffisent.

### 6.2 V2, seulement si la V1 manque les critères du § 11.3

Un modèle multilingue de reconnaissance de phonèmes (famille wav2vec2), converti une fois en Core ML hors
de l'app et exécuté sur le Neural Engine. C'est un fichier de modèle, pas une dépendance de code. Sa licence
doit permettre la redistribution dans un dépôt MIT. La sortie reste la même (§ 7) : le reste de l'app ne
change pas.

## 7. Animation : ce qui fait qu'on y croit

À chaque image, l'animation produit **les 52 poids ARKit**, la **pose de la tête** (trois rotations) et le
**regard** (rotation des yeux).

### 7.1 Quand il parle

1. **Anticipation** : la forme de la bouche à l'instant *t* vient de l'analyse de *t* + 60 ms (réglable).
   Les lèvres se forment avant le son, jamais après.
2. **Mâchoire et lèvres séparées** : la mâchoire suit l'énergie et F1 ; les lèvres suivent F2, F3, les
   fricatives et les occlusions.
3. **Transitions douces** : un ressort amorti par canal, attaque rapide et relâchement plus lent. Aucun saut
   d'une forme à l'autre.
4. **Fermetures prioritaires** : sur « b », « p » et « m », la fermeture des lèvres l'emporte sur la
   mâchoire pendant 40 à 80 ms. C'est ce que l'œil contrôle.
5. **La voix anime tout le visage** : une intonation qui monte lève les sourcils ; une syllabe accentuée
   (pic d'énergie et de F0) donne un petit hochement ; en fin de phrase, la tête se pose et un clignement
   devient probable.
6. **Quatre états** : *parole* (ce § 7.1), *écoute*, *réflexion* et *attente*, détaillés au § 7.2.
7. **Regard** : vers la caméra par défaut. En option, Vision détecte ton visage dans l'image de la caméra,
   et le regard puis la tête te suivent. Rien n'est enregistré.
8. **Jamais mécanique** : du bruit cohérent (simplex) tiré au hasard à chaque lancement. Deux clignements
   ne tombent jamais au même intervalle.
9. **Synchro à l'affichage** : chaque image est calculée pour l'échantillon qui sera **entendu** au moment
   où l'image sera **affichée**. Ce moment est l'heure d'affichage (le `CADisplayLink` de macOS 14), plus
   la latence de sortie du périphérique (Core Audio), plus un réglage **« décalage lèvres »** de ±200 ms,
   utile pour des écouteurs Bluetooth.

### 7.2 Au repos : vivant, même quand il ne parle pas

Un visage figé trahit la machine tout de suite. Au repos, Visage reste vivant, sur trois plans qui se
superposent : le visage, le moment de la conversation, et l'hologramme. Tout est tiré au hasard (bruit
cohérent, intervalles aléatoires), pour que rien ne se répète.

**Le visage**

| Mouvement | Rythme | Détail |
|---|---|---|
| Respiration | 12 à 16 par minute | la tête monte et descend à peine, les narines s'ouvrent un peu |
| Clignements | toutes les 2 à 6 s | 100 à 150 ms ; parfois doubles ; plus fréquents juste après une phrase |
| Micro-saccades | toutes les 0,5 à 2 s | de très petits sauts du regard, qui empêchent l'œil d'avoir l'air peint |
| Regard qui s'en va | toutes les 5 à 15 s | il se pose ailleurs une ou deux secondes, puis revient vers toi (ou vers la caméra) |
| Dérive de la tête | en continu | lente, de quelques degrés, jamais périodique |
| Micro-expressions | toutes les 20 à 60 s | un début de sourire, un sourcil qui bouge, des lèvres pincées ; jamais deux à la fois |

**Le moment de la conversation**

- *écoute* (ton micro est actif) : le regard reste posé sur toi, la tête hoche aux pauses de ta phrase,
  les sourcils suivent ton intonation ;
- *réflexion* (entre ta fin de phrase et sa réponse) : le regard monte ou s'écarte, la tête s'incline
  légèrement, les lèvres se pincent ;
- *attente* (personne ne parle) : les mouvements du tableau, seuls.

**L'hologramme**

- une lueur plus basse qu'en parole (environ −30 %), un scintillement lent ;
- les lignes de balayage défilent toujours, mais la bande de balayage ne passe plus que toutes les 6 à
  12 s ;
- des poussières flottent dans le faisceau du projecteur ;
- un glitch très rare, au plus une fois par minute ;
- en rendu en demi-teintes, la lumière qui tombe sur le visage tourne très lentement : la trame respire.

**Les passages**

- *repos → parole* : la bouche s'entrouvre avant le premier son (anticipation, § 7.1), la lueur monte en
  150 ms ;
- *parole → repos* : retour en 300 à 500 ms, la bouche se ferme, un clignement devient probable ;
- *veille* : après 5 minutes sans voix (réglable), les paupières s'alourdissent, la lumière baisse, et le
  visage se défait en poussière jusqu'à un nuage de points qui respire. Il se reforme dès que la voix
  revient, ou quand la souris le survole ;
- *signal perdu* (l'app IA est fermée, ou la capture est tombée) : le visage se fige en un nuage de points
  éteint, et l'icône de la barre des menus le signale.

**Économie** : 30 images par seconde au repos, 15 en veille, aucun rendu quand la fenêtre est cachée.

## 8. Visages et rendu hologramme

### 8.1 Les visages : MakeHuman (MPFB2)

**Le choix.** On a comparé trois sources :

| | **MakeHuman (MPFB2)** | MetaHuman (Epic) | Rocketbox (Microsoft) |
|---|---|---|---|
| Licence | **CC0** : redistribution libre, sans attribution | Licence d'Unreal Engine. Utilisable hors d'Unreal depuis 2025, mais les fichiers restent sous licence Epic : impossible de les placer sous MIT, et leur redistribution brute dans un dépôt public n'est pas clairement permise. Licence mouvante : une clause sur l'IA ajoutée en juin 2025, levée en octobre 2026. | MIT |
| Communauté | active : extension Blender officielle, MPFB 2.0.16 en juin 2026 | immense | dépôt archivé le 2026-10-02 |
| Réalisme | bon pour les formes, moyen pour la peau | le meilleur | faible (années 2010, peu de polygones) |
| 52 formes ARKit | **natives** (pack faceunits01) | à cuire depuis la pose de correspondance ARKit, dans Unreal | oui (ajoutées en 2022) |
| Même maillage pour toutes les têtes | oui | oui | oui |
| Outil | Blender (gratuit) | Unreal Engine (lourd) | Maya ou Unity |

**Verdict : MakeHuman.** C'est la seule source à la fois assez réaliste et qu'on peut offrir. MetaHuman
ferait de plus beaux visages, mais on ne peut pas les donner. Et dans un hologramme, la peau disparaît
presque : le réalisme vient des **formes**, des **yeux** et du **mouvement**. MakeHuman tient les formes,
l'animation (§ 7) fait le reste.

**Les 10 visages** : 5 hommes et 5 femmes, de 20 à 65 ans, d'origines variées, tous **inventés** (des
personnes de synthèse, à l'image d'aucune personne réelle). On les choisit dans une grille, et on peut
changer de visage à chaud, avec un fondu, même pendant qu'il parle.

**Ce qui pousse le réalisme** :
- une subdivision à l'export, pour une silhouette lisse sous le contour lumineux ;
- une carte de normales tirée d'une peau CC0, quand elle en a une : pores et rides accrochent la lumière
  du contour ;
- des yeux à part, avec cornée et reflet humide, qui tournent vers leur cible ; des cils et des sourcils ;
- des cheveux (éléments CC0), rendus en mèches d'hologramme ;
- des dents et une langue qui suivent la mâchoire (elles se voient sur « t » et « l »). Si elles ne
  suivent pas les formes faceunits01, le script d'export les accroche à la mâchoire.

**La chaîne de fabrication** :

```
tools/faces/
  presets/*.json       les 10 visages : réglages MakeHuman (genre, âge, origines, proportions),
                       cheveux, sourcils, cils, peau
  build_faces.py       Blender sans interface (blender -b -P) : crée chaque visage avec MPFB2,
                       applique les 52 formes, cuit chaque forme sur tous les objets
                       (tête, yeux, dents, langue, cheveux) et exporte un .glb
Resources/Faces/*.glb  les fichiers générés, commités : construire l'app ne demande pas Blender
```

**Ce que doit contenir chaque `.glb`** (glTF 2.0) : les 52 formes ARKit nommées selon la norme
(`jawOpen`, `mouthClose`, `mouthFunnel`…) dans `extras.targetNames`, la même nomenclature pour tous (donc
une animation commune), au plus 40 000 triangles et **moins de 3 Mo** (cibles creuses, quantifiées),
parce que chaque clone de `macos-utils` les télécharge. Un test le vérifie (§ 11.2).

**Chargeur glTF maison** (positions, normales, coordonnées de texture, index, cibles de morphing) :
quelques centaines de lignes, sans bibliothèque.

### 8.2 Le rendu : un vrai hologramme

Un rendu **Metal maison** : une seule tête à dessiner, un effet sur mesure, et aucun lien avec SceneKit
(déprécié en 2025) ni avec RealityKit. Les **shaders sont compilés au lancement** depuis leur source
(`makeLibrary(source:)`) : pas besoin de la chaîne Metal d'Xcode. Le morphing se fait sur le GPU :
position = base + Σ (poids × écart).

L'effet se construit en couches, chacune réglable :

1. **Le projecteur** : un socle discret sous la tête, un faisceau de lumière en cône (dégradé additif) et
   des poussières qui flottent dans le faisceau. On peut le masquer.
2. **La lumière de la tête** :
   - une transparence additive, avec une pré-passe de profondeur pour ne pas voir l'intérieur de la tête ;
   - un contour lumineux (Fresnel) ;
   - une luminance tirée de la peau, pour que les yeux, les sourcils et les lèvres restent lisibles ;
   - les arêtes du maillage, à peine visibles.
3. **Le signal** :
   - des lignes de balayage qui défilent, un entrelacement (une ligne sur deux un peu plus sombre,
     alternée à chaque image) et du grain ;
   - un léger scintillement ;
   - un rare glitch : tranches horizontales décalées et aberration chromatique.
4. **La voix dans la lumière** : la lueur et le scintillement suivent l'énergie de la voix. Le visage
   s'allume quand il parle.
5. **L'apparition** : à la connexion, une bande de balayage descend et construit la tête ligne par ligne.
   À la déconnexion, elle se dissout.
6. **Le halo** : un bloom en deux passes.
7. **La parallaxe** (option caméra) : Vision suit la position de ta tête, et la caméra de rendu se déplace
   avec elle (projection décentrée). La tête paraît avoir un vrai volume derrière l'écran : c'est ce qui
   fait passer l'écran plat pour un hologramme.
8. **La couleur** : la braise de la charte (`#FFC978`) par défaut, palette réglable ; un mode nuage de
   points en option, celui du signe.

Le style reste celui d'un hologramme de science-fiction générique : il n'imite aucune œuvre en particulier.
On vise 60 images par seconde (120 sur un écran ProMotion) quand il parle, 30 au repos.

## 9. Fenêtre et réglages

### 9.1 Trois modes de fenêtre

| Mode | La fenêtre | Pour quoi faire |
|---|---|---|
| **Transparente** (par défaut) | Sans cadre, fond et ombre invisibles : seule la tête flotte sur le bureau. On la déplace en tirant la tête, on la redimensionne par une poignée ou au trackpad. | L'effet hologramme. |
| **Flottante** | Transparente, toujours au premier plan, sur tous les bureaux et au-dessus des apps en plein écran. Option : les clics la traversent (on la pilote alors par la barre des menus). | L'avoir toujours sous les yeux en travaillant. |
| **Classique** | Une fenêtre normale avec barre de titre et fond sombre, plein écran possible. | Partage d'écran, enregistrement vidéo, un « caisson ». |

On change de mode à chaud, depuis la barre des menus.

### 9.2 Barre des menus et réglages

- **L'icône de la barre des menus** donne l'état (connecté à Claude, en attente, parle), le choix du
  visage, le mode de fenêtre, les réglages, et Quitter.
- **Les réglages** :
  - la source (Claude, ChatGPT, autre) et le visage ;
  - les couches de l'hologramme (intensité de chacune), la couleur, la taille ;
  - le décalage lèvres et l'avance d'analyse ;
  - la caméra (regard et parallaxe) et le micro (écoute).

## 10. Architecture technique

### 10.1 Dans `macos-utils`

Visage est un outil de plus de `macos-utils` (public, MIT), rangé comme les autres :

```
macos-utils/
  README.md               une ligne de plus dans le tableau des outils, et ses prérequis
  data/doc/VISAGE.md      la doc utilisateur, en anglais : prérequis, sources, installation, usage
  data/sources/visage/    le paquet SwiftPM de Visage (§ 10.2), dont docs/specs.md, cette spécification
```

Visage reprend les conventions du dépôt :

- un `build.sh` qui construit sans Xcode (les Command Line Tools suffisent), avec `--install` et
  `--universal` ;
- l'identifiant `com.devinthehood.visage` et une signature ad hoc (`codesign --sign -`) : pas de DMG
  notarisé, une source qu'on assemble soi-même ;
- une interface en anglais, comme Awake et Siphon, traduite en français (`Localizable.strings` en et fr,
  selon la langue du système), dans la police du système : l'app n'embarque aucune police (charte, § 4) ;
- une icône d'app dessinée par le code au moment de la construction (`brand/generate.sh --iconset`) : pas
  de bitmap dans le dépôt ;
- des messages de commit en français, comme le reste du dépôt ; le code et les commentaires en anglais.

Deux adaptations du dépôt, au lot 1 :

- **`CONTRIBUTING.md`** décrit une collection « délibérément petite », qu'on peut lire de bout en bout
  avant de la lancer. Visage est bien plus gros qu'Awake ou Siphon. La règle évolue : chaque outil reste
  lisible et sans paquet tiers, et Visage documente ses modules pour qu'on puisse le relire morceau par
  morceau.
- **Le poids** : `macos-utils` pèse environ 1,7 Mo au 2026-11-26, et chaque clone emporte tous les outils.
  Les 10 visages sont donc limités à 3 Mo chacun (moins de 30 Mo en tout). On ne les régénère qu'en cas
  de besoin, parce que chaque régénération s'ajoute à l'historique. Le `.gitignore` écarte `.build/` et
  `build/` de Visage.

### 10.2 Le code

**Swift 6 et SwiftPM, macOS 14.2 au minimum** (imposé par les taps), **macOS 26 si le pilote confirme**
la capture par identifiant de bundle (`bundleIDs`, `processRestoreEnabled` : pilote, § 2.6). L'app est
développée sur macOS 27.
SwiftPM remplace le simple `swiftc *.swift` des autres outils de `macos-utils`, parce que Visage a des
modules et des tests. Contenu de `data/sources/visage/` :

```
Package.swift
Sources/
  VisageApp/       SwiftUI + AppKit : fenêtre (3 modes), barre des menus, réglages, « Se connecter à mon IA »
  AudioSource/     découverte des processus, tap Core Audio, tampon circulaire, relecture retardée
  VoiceAnalysis/   trames, énergie, F0, LPC et formants, fricatives, occlusions, normalisation
  FaceAnimation/   mapping vers ARKit, anticipation, ressorts, prosodie, états, regard
  HoloRenderer/    chargeur glTF, morphing GPU, couches de l'hologramme, halo, parallaxe
  Shared/          horloge hôte, types communs
Resources/
  Faces/*.glb      les 10 visages, générés par tools/faces
  Shaders/*.metal
  en.lproj/, fr.lproj/
Tests/             un dossier par module
tools/faces/       la chaîne Blender (§ 8.1)
brand/             le kit de marque (kit/) et les fichiers qu'il écrit : logos, animations, icône
docs/specs.md      cette spécification
docs/charte.md     la charte
build.sh           construit Visage.app : Info.plist, ressources, signature
```

- **Dépendances : aucun paquet tiers.** Seulement des frameworks d'Apple : SwiftUI, AppKit, CoreAudio,
  AudioToolbox, AVFAudio, Accelerate, Metal, QuartzCore ; Vision et AVFoundation pour l'option caméra ;
  Core ML pour la V2 seulement. Les compteurs atomiques viennent du module `Synchronization` de la
  bibliothèque standard.
- **Fils d'exécution** : l'`IOProc` sur le fil temps réel (sans allocation ni verrou), l'analyse sur un fil
  dédié, le rendu sur le display link. Ils échangent par des tampons circulaires sans verrou.
- **Construire** : `build.sh` lance `swift build -c release`, puis assemble le `.app` avec `Info.plist`
  (dont `NSAudioCaptureUsageDescription` et, pour l'option caméra, `NSCameraUsageDescription`).
- **Pas de macros SwiftUI qui exigent Xcode** : `@State` et `#Preview` sont, dans ce SDK, des macros dont le
  greffon n'existe que dans Xcode ; la construction par les Command Line Tools échoue (pilote, § 2.5). Le
  modèle est `@Observable` (la macro Observation compile) et tenu par référence.
- **Signature en développement** : la signature ad hoc change à chaque build, et macOS redemande alors
  l'autorisation audio. Pour le développement, `VISAGE_SIGN_IDENTITY` permet à `build.sh` de signer avec un
  certificat local auto-signé (gratuit, Trousseau).
- **Réseau** : aucun. App Sandbox sans droit réseau, si la sandbox est compatible avec les taps (à vérifier
  au pilote).

## 11. Qualité

### 11.1 La porte (avant chaque commit)

`swift build -c release`, `swift test` et `swift format lint --strict`. Tous ces outils sont fournis avec
Swift : rien à installer.

**Pas de CI au départ** : `macos-utils` n'en a pas. Un workflow GitHub (runner macOS, gratuit pour un
dépôt public) pourra jouer la même porte. Il rejoindrait alors le passage mensuel, et resterait coupé le
reste du temps, comme sur les autres dépôts.

### 11.2 Les tests

- **Analyse** : sur des signaux synthétiques (voyelles synthétisées aux formants connus, bruits de
  fricatives, silences et explosions). On vérifie F1, F2, F0 et la détection des occlusions.
- **Animation** : mapping et ressorts, de façon déterministe, avec une graine fixe.
- **Visages** : chaque `.glb` de `Resources/Faces` porte les 52 noms ARKit, le même maillage que les
  autres, au plus 40 000 triangles et moins de 3 Mo.
- **Chargeur glTF** : sur un fichier de test.
- **Tampon circulaire** : en concurrence, producteur contre consommateur.
- **Mode fichier** : Visage lit un `.wav` au lieu d'une app. Il sert à la mise au point sans IA, aux
  démos, et au **rendu vidéo hors ligne** (`.mov` via AVAssetWriter), pour comparer deux versions image
  par image. C'est aussi lui qui produit les vidéos du README.
- **Enregistrements de référence** : 5 extraits de la voix de Claude en français et 2 de ChatGPT, annotés à
  la main (instants des « b », « p » et « m »). Ils restent **hors du dépôt**, qui est public.

### 11.3 Critères d'acceptation : « on y croit »

1. **Synchro** : la bouche devance le son de 0 à 60 ms et n'est jamais en retard de plus de 20 ms. On le
   mesure en filmant l'écran au ralenti (240 images par seconde) avec le téléphone.
2. **Fermetures** : les lèvres se ferment sur au moins 90 % des « b », « p » et « m » des extraits de
   référence.
3. **Jamais figé** : aucun intervalle de plus d'une seconde sans mouvement du visage, attente comprise ; et
   sur deux minutes de repos filmées, on ne repère aucune répétition.
4. **Test à l'aveugle** : sur 10 extraits, on juge « on y croit » sur au moins 8.
5. **Budgets** (MacBook Apple Silicon) : capture et analyse sous 10 % d'un cœur, une image sous 4 ms de
   GPU, moins de 250 Mo de mémoire, aucun craquement audio en une heure.
6. **Sûreté** : Visage quitté ou planté, le son de l'IA revient en moins d'une seconde.

## 12. Risques, levés au pilote ou au lot concerné

| # | Risque | Parade |
|---|---|---|
| R1 | **Écho** : rejoué 150 ms plus tard, le son peut tromper l'annulation d'écho de l'app IA, qui s'entendrait elle-même et se couperait. | Au casque, aucun souci. En haut-parleurs, on mesure, puis on réduit D ou on conseille le casque. |
| R2 | **Processus audio** : il faut trouver celui qui joue la voix (Claude Desktop est une app Electron) et le suivre quand l'app redémarre. | macOS 26 tape une app par son identifiant et la retrouve quand elle redémarre (pilote, tests 4 et 5) ; sinon, filtrer par préfixe et par PID responsable. |
| R3 | **Sûreté de la coupure** : le son de l'IA doit revenir si Visage s'arrête. | Critère 6, bloquant. Tap privé ; mesure au micro par le pilote (tests 2 et 3). |
| R4 | **Analyse sans modèle** insuffisante en français. | V2 Core ML (§ 6.2). |
| R5 | **Mode vocal en bêta** chez Claude (le français aussi) : la voix peut changer. | Visage ne suit que le son : la normalisation automatique réapprend la voix. |
| R6 | **Réalisme de MakeHuman** trop juste en gros plan. | Subdivision, cartes de normales, yeux soignés ; l'hologramme et la parallaxe portent le reste. Jugé au lot 5 sur le test à l'aveugle. |
| R7 | **Poids des visages** : chaque clone de `macos-utils` les emporte. | Moins de 3 Mo par visage (cibles creuses, quantifiées), vérifié par un test ; régénération seulement en cas de besoin. |

## 13. Découpage en lots

| Lot | Contenu | Sortie |
|---|---|---|
| **0 — Pilote** (bloquant) | Tap sur Claude Desktop en mode vocal, coupure et relecture retardée ; mesure de R1, R2 et R3 ; une bouche 2D sommaire (la mâchoire suit l'énergie) pour juger la synchro. | Un go ou no-go écrit, les identifiants relevés. |
| **1 — Socle** | `data/sources/visage/` dans `macos-utils` : paquet SwiftPM, `build.sh`, porte, `.gitignore` ; `CONTRIBUTING.md` adapté ; écran « Se connecter à mon IA », barre des menus, rebranchement automatique. | L'app se branche et se rebranche seule. |
| **2 — Analyse** | § 6.1, mode fichier, tests sur signaux synthétiques. | Les courbes d'analyse sont justes sur les extraits. |
| **3 — Rendu** | Chargeur glTF, morphing, les huit couches de l'hologramme, trois modes de fenêtre, synchro à l'affichage. | Une tête hologramme à 60 images par seconde. |
| **4 — Animation** | § 7 en entier. | Critères 1 à 3. |
| **5 — Visages** | Chaîne Blender, 10 réglages, 10 `.glb`, grille de choix, changement à chaud. | Les 10 visages, tests verts, R6 jugé. |
| **6 — Finitions** | Caméra (regard et parallaxe), réglages complets, traduction ; robustesse (veille, changement de sortie audio, app IA relancée). | Les six critères du § 11.3 passés. |
| **7 — Publication** | `data/doc/VISAGE.md` en anglais, avec les vidéos du mode fichier ; une ligne dans le tableau du README de `macos-utils`, et ses prérequis. | Le cadeau est en ligne. |
| Option | Phonèmes en Core ML (V2) ; téléphone comme écran déporté (pyramide hologramme) ; autres apps. | — |

## 14. Hors périmètre

- **iPhone et iPad en autonome** : aucune app ne peut capter et couper le son d'une autre. Windows et Linux
  non plus.
- **Le mode navigateur** (Q5).
- **Une voix ou une IA à nous** : on ne remplace pas le mode vocal officiel.
- **Lire le texte de la conversation, toute connexion réseau.**
- **Un DMG notarisé** : comme pour le reste de `macos-utils`, on assemble l'app soi-même.

## Sources

- [Claude — Use voice mode](https://support.claude.com/en/articles/11101966-use-voice-mode) : offres,
  plateformes (Desktop, web, mobile), bêta, langues, limites.
- [MacRumors — le mode vocal de Claude passe à Opus et Sonnet](https://www.macrumors.com/2026/07/24/claude-voice-mode-opus-sonnet-model-support/)
- [OpenAI — ChatGPT for desktop, notes de version](https://help.openai.com/en/articles/9703738-desktop-app-release-notes)
- [Neowin — ChatGPT Voice sur les apps desktop](https://www.neowin.net/news/chatgpt-voice-experience-gets-a-massive-upgrade-on-desktop/)
- [MakeHuman — licence](https://static.makehumancommunity.org/about/license.html) : éléments CC0, code de
  MPFB sous GPL.
- [MPFB 2.0.16 — notes de version](https://static.makehumancommunity.org/mpfb/releases/release_2016.html) :
  formes ARKit du pack faceunits01.
- [MPFB sur la plateforme d'extensions de Blender](https://extensions.blender.org/add-ons/mpfb/)
- [CG Channel — MetaHuman utilisable dans Unity ou Godot (2025)](https://www.cgchannel.com/2025/06/you-can-now-sell-metahumans-or-use-them-in-unity-or-godot/)
- [Unreal Engine — journal des changements de l'EULA](https://www.unrealengine.com/eula-change-log/unreal)
- [Microsoft Rocketbox](https://github.com/microsoft/Microsoft-Rocketbox) : licence MIT, formes ARKit,
  dépôt archivé.
