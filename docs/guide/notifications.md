# C411 et Salon

[← Sommaire](../README.md)

Les onglets **C411** et **Salon** suivent **C411 en direct**. Ils demandent le
[cookie de session](configuration.md#cookie-de-session-c411).

## L'onglet C411 : notifications et compte

La connexion au site se fait dès le lancement et se rétablit seule en cas de
coupure (de 2 s à 2 min d'attente).

### Profil et Zen

En haut de l'onglet, lus sur le site avec le cookie de session (relus toutes
les 10 minutes, et en tirant la liste vers le bas) :

- **Profil** : pseudo, rang, classe et emblème, ancienneté ; **niveau** (XP
  avant le suivant) et **série de jours** ; téléchargements gratuits
  restants. Une alerte apparaît en cas d'avertissement, de téléchargement
  bloqué, ou de ratio proche du minimum.
- **Zen** : le solde (gagnés, dépensés), **acquis aujourd'hui** et
  l'estimation de ce soir, **versé cette nuit**, la part de la journée
  partagée et le coefficient de poids ; l'**indicateur de contribution** (en
  % du maximum de la classe) et le **bonus** (sur son plafond).
- **Sur 30 jours** : moyennes par minute, heure, jour et mois, et les
  versements jour par jour (valeur au survol).
- **Le calcul en cours** et le **détail par jour**, avec la formule du
  site : versement = arrondi( T × P × S × I ÷ 7 × (1 + B) ) — torrents
  comptés, part de la journée partagée, coefficient de poids, indicateur de
  contribution, bonus.

### Mon compte, en direct

Un encadré en haut de page affiche, mis à jour en temps réel : volume envoyé,
volume reçu, crédit d'envoi et ratio.

### Compteurs

Messages privés, salons, demandes, staff : un bandeau s'affiche quand l'un
augmente.

### La liste

- les notifications du site, une **icône par type**, les non lues signalées ;
- groupées **par jour** (Aujourd'hui, Hier, …) ;
- **Afficher plus anciennes** charge les pages suivantes ; tirer vers le bas
  rafraîchit ;
- relues toutes les 2 minutes et à chaque événement du site ; un bandeau
  annonce les nouvelles ;
- les 500 dernières restent consultables hors ligne.

Un clic ouvre la bonne chose : le torrent dans l'application s'il est dans
Transmission, le salon pour un lien de discussion, sinon la page du site.

La pastille de l'onglet compte les non lues **pas encore vues dans
l'application** ; l'état « lu » du site n'est pas modifié.

## Salon

L'onglet **Salon** est le chat du site :

- choix du salon (Général par défaut), description et message épinglé ;
- les 50 derniers messages, puis la suite en direct ;
- pseudo, avatar, badge, étiquettes **Modo** / **Admin**, réponses citées,
  images jointes, mention « modifié » ;
- **réactions** mises à jour en direct, les tiennes mises en évidence, les
  membres au survol ;
- qui est en ligne, qui « … écrit » ;
- séparateurs de jour, messages consécutifs d'une même personne regroupés,
  texte sélectionnable.

### Mise en forme

`**gras**`, `*italique*`, `~~barré~~`, `` `code` ``, liens cliquables. Les
mentions `@pseudo` et `{{pseudo}}` sont mises en valeur, et les messages qui te
mentionnent sont surlignés.

### Écrire

**Entrée** envoie, **Maj + Entrée** passe à la ligne. Le message s'affiche
tout de suite, puis est confirmé par le serveur ; en cas de refus, un bouton
**Réessayer** apparaît. Dans les salons en lecture seule (Annonces), la saisie
est remplacée par « Lecture seule » ; le mode lent est rappelé quand il
s'applique.
