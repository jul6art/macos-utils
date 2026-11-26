# Visage — pilote (lot 0)

> **Statut au 2026-11-26, au soir** : les cinq mesures sont faites, avec l'utilisateur, son allumé et
> Claude Desktop installé (§ 4). **Verdict : go** (§ 5). Visage capte la voix de Claude, la relit
> retardée sans dégât, et la bouche la suit ; l'app elle-même a parlé avec la voix de Claude le soir même.

## 1. Ce que contient le pilote

| Fichier | Rôle |
|---|---|
| `pilot/TapSession.swift` | Le tap Core Audio coupé à la sortie, l'agrégat qui le joint à la sortie par défaut, et une seule `IOProc` : capture dans un tampon circulaire, relecture avec le retard D, niveau toutes les 10 ms. |
| `pilot/PilotModel.swift`, `PilotApp.swift` | La fenêtre : cible, mode (processus ou identifiants), retard, anticipation, une bouche sommaire qui suit le niveau du son qui sera entendu. |
| `pilot/ProcessCatalog.swift` | Les processus audio du système, les taps publics, et leur destruction. |
| `pilot/MicProbe.swift` | L'oreille du pilote : le niveau du micro, pour savoir si une voix sort des haut-parleurs. |
| `pilot/standin/` | Une voix de remplacement avec un vrai identifiant de bundle, qu'on quitte et relance. |
| `pilot/run-tests.sh` | Les mesures, d'un seul coup (§ 4). |

Construction : `sh pilot/build.sh`, Command Line Tools seulement. Journal : `~/Library/Logs/VisagePilot/`
(`pilot.log`, `status.json`, heures en UTC).

## 2. Résultats

### 2.1 Capture et relecture : ça marche

Premier essai, sur `afplay` qui lit une voix française de synthèse :

| Mesure | Valeur |
|---|---|
| Délai avant la première capture | 6 s, autorisation comprise |
| Format du tap | 48 kHz, 2 canaux, float 32 bits entrelacé |
| Agrégat (haut-parleurs du MacBook Pro) | 44,1 kHz, tampon de 512 trames, environ 82 cycles par seconde |
| Latence de sortie annoncée | 743 trames, soit 16,8 ms |
| Niveau capté | −22,8 dBFS pendant la voix |
| Surcharges de l'`IOProc` | 0 |

Le tap à 48 kHz et la sortie à 44,1 kHz cohabitent dans l'agrégat (compensation de dérive). Le décompte
des écarts de taille entre entrée et sortie, ajouté depuis, sera lu par le test 1 du § 4.

### 2.2 Plantage (R3) : un tap public survit à son processus

Tué par `kill -9`, le pilote laisse son tap **public** derrière lui : toujours listé par le système plus
d'une minute après. Un autre processus peut le détruire (`VisagePilot --destroy-tap <UID>`, fait).

Le son de la cible revient-il pour autant ? La documentation de `CATapMutedWhenTapped` ne coupe le son
que pendant qu'un client lit le tap ; or l'agrégat et son `IOProc` meurent avec le processus. Le son
devrait donc revenir, mais ce n'est pas encore mesuré : la sortie du Mac était coupée pendant le pilote.
Les tests 2 et 3 du § 4 le mesurent au micro, pour un tap privé et pour un tap public.

### 2.3 L'autorisation bloque le démarrage

Un nouveau build signé ad hoc est une nouvelle app pour macOS : il redemande l'autorisation d'enregistrer
l'audio du système. Tant qu'elle n'est pas donnée, `AudioDeviceStart` reste bloqué (90 s observées), puis
rend la main sans qu'aucun cycle audio ne tourne jamais : pas de silence, rien.

### 2.4 Le dessin SwiftUI coûte cher

La fenêtre du pilote, avec un `Canvas` redessiné à chaque image, prend 10 à 14 % d'un cœur à elle seule,
l'audio arrêté. Le rendu du lot 3 passe par Metal, avec un nombre d'images par seconde plafonné au repos
(spécification, § 7.2).

### 2.5 Sans Xcode, pas de macros SwiftUI

`@State` est, dans ce SDK, une macro dont le greffon n'existe que dans Xcode : la compilation échoue avec
les seules Command Line Tools. `@Observable` (Observation) compile. Le pilote tient son modèle par une simple
référence.

### 2.6 macOS 26 sait taper une app par son identifiant

Le SDK de macOS 26 ajoute à `CATapDescription` `bundleIDs` (taper une app par son identifiant) et
`processRestoreEnabled` (retrouver l'app quand elle redémarre). Si le test 4 le confirme, Visage n'a plus
à suivre les processus d'une app Electron à la main (R2).

## 3. Ce qui change dans la conception

1. **Tap privé**, toujours. Au lancement, Visage détruit tout tap public nommé « Visage » laissé par une
   version qui aurait planté.
2. **La capture démarre hors du fil principal**, et l'interface dit « en attente de ton autorisation ».
3. **Une autorisation manquante se détecte**, mais pas comme on le croyait : l'app joue depuis six secondes
   et rien de non nul n'en est venu depuis le branchement (§ 4). Trois secondes sans cycle audio ne
   prouvaient rien : sur macOS 26, une capture par identifiant ne tourne pas tant que l'app se tait.
4. **Si l'autorisation devient inerte** (§ 4) : `tccutil reset AudioCapture <identifiant>` puis une
   nouvelle demande, avec l'accord de l'utilisateur. On a d'abord cru qu'il fallait une signature stable
   (`VISAGE_SIGN_IDENTITY`, spécification § 10.2), sinon chaque build perdrait l'autorisation ; Visage,
   signé en ad hoc et recompilé à plusieurs reprises le même soir, l'a gardée.
5. **Pas de macros SwiftUI** qui exigent Xcode (`@State`, `#Preview`) : un modèle `@Observable` tenu par
   référence.
6. **macOS 15 minimum** : le test 4 confirme `bundleIDs` et `processRestoreEnabled` sur macOS 26, que Visage
   prend quand il les trouve ; sur macOS 15, il suit les processus lui-même. Exiger macOS 26 écarterait
   presque tous les Mac Intel (quatre modèles seulement le reçoivent), dont celui de l'utilisateur.

## 4. Les mesures du 2026-11-26, au soir

Avec l'utilisateur, haut-parleurs du MacBook Pro à 56 %, micro intégré comme oreille.

| Test | Mesure | Résultat |
|---|---|---|
| 1 · capture par processus | voix captée −17 dB ; à travers le pilote, la voix sort à −30,7 dB, autant qu'en direct (−29 dB) ; avance 175 ms ; 0 écart de trame, 0 surcharge | **réussi** |
| 2 · plantage, tap privé | après `kill -9`, la voix revient aussitôt (−31,9 dB) | **réussi** |
| 3 · plantage, tap public | la voix revient (−30,7 dB) ; le tap orphelin reste listé, et se détruit | **réussi** |
| 4 · par identifiant, puis redémarrage | captée (−27,5 dB), puis retrouvée seule après le redémarrage de l'app (une seule connexion au journal) | **réussi** |
| 5 · Claude Desktop | la lecture à voix haute sort de « Claude Helper » (`com.anthropic.claudefordesktop.helper`) ; captée de −17 à −24 dB, des creux à −70/−80 dB entre les phrases ; avance 174 à 184 ms ; à l'œil, la bouche part avec le son ; à l'oreille, la voix relue est normale | **réussi** |

Ce que les mesures ont appris :

- **Claude Desktop (6.28899.6) ne tient pas de conversation parlée sur Mac** : on lui dicte (maintenir pour
  parler), il répond en texte, et « Lire à voix haute » lit la réponse, avec la voix et la vitesse choisies.
  Le visage parle donc quand Claude lit. R1, l'écho, ne se pose pas avec lui : il n'écoute pas pendant qu'il
  lit. Il reste à mesurer avec le mode vocal de ChatGPT.
  *Rectificatif du même soir* : selon la documentation d'Anthropic, Claude Desktop a bien un mode vocal
  mains libres, ouvert par le bouton en forme d'onde sonore, en bas à droite de la fenêtre ; ce qu'on a
  pris pour lui est la dictée. Le mode vocal reste à essayer avec Visage, et R1 avec lui.
- **R2, les identifiants** : l'app `com.anthropic.claudefordesktop`, sa voix dans un auxiliaire
  `….helper`. Le branchement par préfixe d'identifiant prend les deux.
- **Une fois, l'autorisation du pilote est devenue inerte, sans un mot** : macOS gardait la coche dans
  Réglages Système, mais le tap ne coupait plus l'app et ne livrait que des zéros. Il a fallu
  `tccutil reset AudioCapture com.devinthehood.visage.pilot` et une nouvelle demande. La cause n'est pas
  établie : on l'a d'abord mise sur la recompilation, mais Visage a gardé son autorisation à chaque
  recompilation du même soir.
- **La fausse alerte d'autorisation** : l'app Visage disait « autorisation manquante » tant que Claude se
  taisait (§ 3, point 3), corrigé le soir même.
- **Les mesures se gênent** : une copie du pilote restée d'une série précédente coupait la voix de test ;
  la voix de test (19 s) finissait parfois avant la dernière mesure, retardée par la demande d'autorisation.
  `run-tests.sh` devra fermer les copies restantes avant de commencer, et jouer la voix en boucle.
- **Une fois, l'état du pilote s'est figé** cinq secondes après son branchement, sans plantage ni rapport ;
  pas reproduit. À surveiller dans Visage.
- **Le pilote prend environ 20 % de processeur**, fenêtre SwiftUI comprise ; Visage se mesurera à part.

## 5. Verdict : go

La capture, la relecture retardée et la synchro tiennent sur la vraie voix de Claude, sans dégât audible ;
un plantage rend la voix. Le pilote n'a plus d'autre rôle que de rejouer ces mesures. La suite se fait
dans l'app (spécification, § 13).
