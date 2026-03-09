# 🚀 Projet OTA — OpenSource Tenant Architecture

> Script Bash interactif d'administration d'un hébergement web mutualisé.

---

## 📋 Table des matières

- [Présentation](#présentation)
- [Prérequis](#prérequis)
- [Installation](#installation)
- [Utilisation](#utilisation)
- [Fonctionnalités](#fonctionnalités)
  - [0 — Installer les prérequis](#0--installer-les-prérequis)
  - [1 — Créer un hébergement](#1--créer-un-hébergement)
  - [2 — Supprimer un hébergement](#2--supprimer-un-hébergement)
  - [3 — Modifier un hébergement](#3--modifier-un-hébergement)
  - [4 — Afficher un hébergement](#4--afficher-un-hébergement)
  - [5 — Gestion des bases de données](#5--gestion-des-bases-de-données)
  - [6 — Informations serveur](#6--informations-serveur)
- [Arborescence du serveur](#arborescence-du-serveur)
- [Technologies utilisées](#technologies-utilisées)

---

## Présentation

**OTA (OpenSource Tenant Architecture)** est un script Bash 100% interactif permettant à un administrateur système de gérer un serveur d'hébergement web mutualisé.

Chaque utilisateur hébergé dispose de :

| Ressource | Détail |
|---|---|
| 📁 Répertoire web | `/home/utilisateur/www` |
| 🔒 Accès FTP | Via Pure-FTPd avec quota |
| 💾 Espace de stockage limité | Quota configurable en Mo |
| 🗄️ Base de données | MariaDB (optionnelle) |
| 🖥️ Accès SSH | Activable/désactivable |

---

## Prérequis

- Système d'exploitation : **Debian / Ubuntu**
- Droits **root** (sudo)
- Connexion internet (pour l'installation des paquets)

---

## Installation

**1. Cloner le dépôt**

```bash
git clone https://github.com/votre-utilisateur/projet-ota.git
cd projet-ota
```

**2. Rendre le script exécutable**

```bash
chmod +x otaV1_5.sh
```

**3. Lancer le script**

```bash
sudo ./otaV1_5.sh
```

> ⚠️ Le script **doit être exécuté avec sudo**. Sans droits root, il s'arrête immédiatement.

---

## Utilisation

Au lancement, un menu interactif s'affiche :

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    🚀 GESTION HÉBERGEMENT WEB - PROJET OTA 🚀
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   0) Installer les prérequis (À faire une fois)
   1) Créer un hébergement
   2) Supprimer un hébergement
   3) Modifier un hébergement
   4) Afficher un hébergement (et Gestion des fichiers web)
   5) Gestion des bases de données
   6) Informations serveur
   7) Quitter
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
👉 Ton choix [0-7] :
```

Naviguez en tapant le **numéro** correspondant puis en appuyant sur `Entrée`.

---

## Fonctionnalités

### 0 — Installer les prérequis

> **À exécuter une seule fois** lors de la première utilisation.

Cette option installe et configure automatiquement :

- **Apache2** — Serveur web
- **MariaDB** — Serveur de bases de données
- **Pure-FTPd** — Serveur FTP
- **PHP** — Langage de script côté serveur

```
👉 Ton choix [0-7] : 0
```

---

### 1 — Créer un hébergement

Permet de créer un compte complet pour un nouvel utilisateur.

**Informations demandées :**

```
Nom utilisateur (ex: client1) : client1
Mot de passe : ****
Quota disque (en Mo, ex: 500) : 500
Créer une base de données ? (oui/non) : oui
Accès SSH ? (oui/non) : non
```

**Ce qui est créé automatiquement :**

- Utilisateur Linux avec son home `/home/client1/`
- Dossier web `/home/client1/www/`
- Compte FTP (Pure-FTPd) avec le quota défini
- VirtualHost Apache (`client1.local`)
- Base de données MariaDB `client1_db` *(si demandée)*

---

### 2 — Supprimer un hébergement

Supprime **intégralement** un utilisateur et toutes ses ressources.

```
👉 Ton choix [0-7] : 2

Utilisateurs existants :
  ► client1
  ► client2

Nom de l'utilisateur à supprimer (utilise TAB) : client1
```

> 💡 **Astuce :** utilisez la touche `TAB` pour l'autocomplétion du nom d'utilisateur.

**Ce qui est supprimé :**

- L'utilisateur Linux et son dossier `/home/client1/`
- Le VirtualHost Apache
- Le compte FTP
- La base de données et l'utilisateur MariaDB associé

---

### 3 — Modifier un hébergement

Permet de modifier les paramètres d'un hébergement existant.

```
1. Changer le quota disque (FTP)
2. Changer le mot de passe
3. Activer/Désactiver SSH
4. Créer ou supprimer une base de données
Choix :
```

| Option | Description |
|---|---|
| **1** | Nouveau quota en Mo pour l'accès FTP |
| **2** | Nouveau mot de passe Linux + FTP |
| **3** | Bascule le shell entre `/bin/bash` (SSH actif) et `/usr/sbin/nologin` |
| **4** | Crée ou supprime la base de données MariaDB de l'utilisateur |

---

### 4 — Afficher un hébergement

Affiche la liste des utilisateurs hébergés avec leur espace utilisé, puis permet de consulter le détail d'un utilisateur spécifique.

**Liste globale :**

```
Utilisateur    Espace Utilisé    Dossier Web
---------------------------------------------------------
client1        120K              /home/client1/www
client2        4.5M              /home/client2/www
```

**Détails d'un utilisateur :**

```
--- Détails de l'hébergement : client1 ---
Quota FTP     : 500 MB
Accès SSH     : /usr/sbin/nologin
Base de données : Oui (client1_db)

Fichiers présents dans le dossier www :
total 8
-rw-r--r-- 1 client1 client1 312 jan 01 12:00 index.html
```

**Installation WordPress en un clic :**

Depuis cette section, vous pouvez installer WordPress automatiquement pour l'utilisateur sélectionné :

```
Voulez-vous installer WordPress pour cet utilisateur ? (oui/non) : oui
```

Le script télécharge la dernière version de WordPress et la déploie dans `/home/client1/www/`.

---

### 5 — Gestion des bases de données

Gestion manuelle des bases de données MariaDB, indépendamment des comptes utilisateurs.

```
1. Créer une base de données manuellement
2. Supprimer une base de données manuellement
3. Lister les bases existantes
Choix :
```

---

### 6 — Informations serveur

Affiche un tableau de bord général du serveur :

```
Espace disque total (racine) :
Filesystem   Size  Used Avail Use% Mounted on
/dev/sda1     20G  4.2G   15G  22% /

Nombre d'utilisateurs hébergés : 3

Liste des sites (VirtualHosts actifs) :
  client1.conf
  client2.conf

Comptes FTP actifs : 3
```

---

## Arborescence du serveur

```
/home/
├── client1/
│   └── www/
│       └── index.html
├── client2/
│   └── www/
│       └── index.html
└── client3/
    └── www/
```

Les VirtualHosts Apache sont stockés dans :
```
/etc/apache2/sites-available/
├── client1.conf
├── client2.conf
└── client3.conf
```

---

## Technologies utilisées

| Technologie | Rôle |
|---|---|
| **Bash** | Langage du script |
| **Apache2** | Serveur web & VirtualHosts |
| **MariaDB** | Gestion des bases de données |
| **Pure-FTPd** | Accès FTP avec quotas |
| **PHP** | Interpréteur PHP pour les sites |

---

> Projet réalisé dans le cadre du cours d'administration système — [pedagogeek.fr](https://www.pedagogeek.fr)
