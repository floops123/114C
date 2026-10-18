# Notifications et Salon

[← Sommaire](../README.md)

Ces deux onglets suivent **C411 en direct**. Ils demandent le
[cookie de session](configuration.md#cookie-de-session-c411).

## Notifications

La connexion au site se fait dès le lancement et se rétablit seule en cas de
coupure (de 2 s à 2 min d'attente).

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
