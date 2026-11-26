# Visage — pilote (lot 0)

> **Statut au 2026-11-26** : la capture et la relecture retardée marchent ; trois découvertes changent la
> conception (§ 3). Restent cinq mesures, qui demandent le son du Mac allumé, deux autorisations, et Claude
> Desktop installé (§ 4). Le verdict final s'écrira après elles.

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
3. **Une autorisation manquante se détecte** : aucun cycle audio dans les 3 s qui suivent le démarrage.
   Visage ouvre alors le bon panneau de Réglages Système.
4. **Signature stable pendant le développement** (`VISAGE_SIGN_IDENTITY`, spécification § 10.2), sinon
   chaque build redemande l'autorisation.
5. **Pas de macros SwiftUI** qui exigent Xcode (`@State`, `#Preview`) : un modèle `@Observable` tenu par
   référence.
6. **macOS 26 minimum**, si le test 4 confirme `bundleIDs` et `processRestoreEnabled`, au lieu de 14.2.

## 4. Ce qui reste : cinq mesures, dix minutes

Il faut : **le son du Mac allumé** (il était coupé), répondre **Autoriser** aux deux demandes (audio du
système, micro), et **Claude Desktop** installé et connecté pour le test 5.

```shell
sh data/sources/visage/pilot/build.sh        # si le pilote n'est pas construit
sh data/sources/visage/pilot/run-tests.sh --claude
```

| Test | Mesure | Réussi si |
|---|---|---|
| 1 · capture par processus | niveau capté, avance réelle, écarts de trames, surcharges, CPU | niveau > −60 dBFS, avance ≈ D − latence, 0 surcharge |
| 2 · plantage, tap privé | micro après `kill -9` | même niveau que la voix directe |
| 3 · plantage, tap public | micro après `kill -9`, taps restants | même niveau que la voix directe |
| 4 · par identifiant, puis redémarrage | capture, puis capture retrouvée sans reconnexion | les deux |
| 5 · Claude Desktop | processus qui jouent la voix, capture de Claude | capture > −60 dBFS |

Puis, à l'oreille et à l'œil, en parlant à Claude en haut-parleurs pendant une minute :

- **R1, l'écho** : Claude s'interrompt-il tout seul ?
- **La synchro** : avec D = 150 ms et 40 ms d'anticipation, la bouche part-elle avec le son, ou un peu
  avant ? Comparer avec D = 0 (la bouche doit paraître en retard).
