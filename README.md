<div align="center">

# 🚀 Projet OTA — OpenSource Tenant Architecture

**Script Bash interactif d'administration d'hébergement web mutualisé**

![Version](https://img.shields.io/badge/version-2.6-blue?style=for-the-badge)
![Bash](https://img.shields.io/badge/100%25-Bash-green?style=for-the-badge&logo=gnu-bash)
![OS](https://img.shields.io/badge/OS-Debian%20%7C%20Ubuntu-orange?style=for-the-badge&logo=linux)
![License](https://img.shields.io/badge/license-MIT-purple?style=for-the-badge)

*Développé par **NoxKirna et gemini,claude***

</div>

---

## 📖 Présentation

**OTA Manager** est un script **100% Bash** permettant à un administrateur de gérer un serveur d'hébergement web mutualisé depuis un simple terminal.

Chaque client dispose de son propre environnement **complètement isolé** :

- 📁 Répertoire web dédié (`/home/<user>/www`)
- 📡 Accès FTP avec quota disque
- 🗄️ Base de données MariaDB personnelle
- 🔐 Accès SSH optionnel
- 🌐 VirtualHost Apache automatique

---

## 🖥️ Aperçu

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
         🚀 GESTION HÉBERGEMENT WEB - PROJET OTA v2.6 🚀
                     Développé par NoxKirna
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   🌐 IP : 192.168.1.63 (/24) | 🌍 Passerelle : 192.168.1.254
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   0) Installer les prérequis
   1) Créer un hébergement
   2) Supprimer un hébergement
   3) Modifier un hébergement (Mot de passe, Quota...)
   4) Tableau de bord / Installer WordPress
   5) Bases de données & Comptes FTP
   6) Infos serveur et Logs
   7) ⚠️  Remise à zéro totale
   8) Quitter
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## ⚙️ Prérequis

| Élément | Requis |
|---|---|
| Système d'exploitation | Debian ou Ubuntu (détection automatique) |
| Droits | `root` ou `sudo` |
| Connexion internet | Pour l'installation des paquets et WordPress |

> ❌ Le script **refusera de se lancer** sur un OS non compatible (CentOS, Arch, etc.)

---

## ⚡ Installation

```bash
# 1. Cloner le dépôt
git clone https://github.com/NoxKirna/projet-ota.git
cd projet-ota

# 2. Rendre le script exécutable
chmod +x ota.sh

# 3. Lancer en root
sudo ./ota.sh
```

> **Première utilisation :** choisir l'**option 0** pour installer automatiquement toute la pile logicielle.

---

## 🛠️ Stack technique installée automatiquement

| Composant | Rôle |
|---|---|
| **Apache2** + mod_rewrite | Serveur web & VirtualHosts |
| **MariaDB** | Bases de données (utf8mb4) |
| **Pure-FTPd** | Serveur FTP à comptes virtuels |
| **PHP 8.x** + php-mysql | Exécution des scripts web |
| **WP-CLI** | Installation WordPress en ligne de commande |
| **apache2-utils** | Gestion htpasswd pour la protection des sites |

---

## 📋 Fonctionnalités détaillées

### 0️⃣ Installer les prérequis
- Installation complète de la pile Apache / MariaDB / Pure-FTPd / PHP / WP-CLI
- Configuration automatique de Pure-FTPd (base de données virtuelle)
- Activation du module `mod_rewrite`
- Création du fichier de log `/var/log/ota_manager.log`

---

### 1️⃣ Créer un hébergement
- Création d'un **utilisateur Linux** avec shell configurable
- Génération du dossier `/home/<user>/www` avec une **page d'accueil automatique**
- **Validation** du nom (regex), du mot de passe (confirmation + 6 car. min.) et du quota
- Création du **compte FTP** avec quota disque
- Génération automatique du **VirtualHost Apache** (avec logs séparés par client)
- Création optionnelle d'une **base de données MariaDB**
- Activation optionnelle de l'**accès SSH**
- Possibilité de créer **plusieurs hébergements à la suite**

---

### 2️⃣ Supprimer un hébergement
- Autocomplétion avec la touche `TAB`
- Confirmation obligatoire avant suppression
- Suppression complète : utilisateur, dossier home, VirtualHost, compte FTP, base de données

---

### 3️⃣ Modifier un hébergement

| Sous-option | Action |
|---|---|
| **1** | Modifier le quota disque FTP |
| **2** | Changer le mot de passe (système + FTP en même temps) |
| **3** | Activer / désactiver l'accès SSH |
| **4** | Créer ou supprimer la base de données |
| **5** | Activer / désactiver le compte FTP |
| **6** 🔒 | Protéger le site par mot de passe (htpasswd + .htaccess) |

---

### 4️⃣ Tableau de bord / WordPress
- **Tableau récapitulatif** de tous les clients :

```
UTILISATEUR          ESPACE UTILISÉ  QUOTA FTP       SSH        DB
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
client1              12M             500 Mo          ❌         ✅
client2              48M             1000 Mo         ✅         ✅
```

- Détails par utilisateur + **liste des fichiers dans `/www`**
- **Installation WordPress automatisée** :
  - Téléchargement de la dernière version
  - `wp-config.php` pré-rempli (DB, user, password)
  - Installation complète via **WP-CLI** (admin, URL, titre configurés)

---

### 5️⃣ Bases de données & Comptes FTP

| Sous-option | Action |
|---|---|
| **1** | Créer une base de données |
| **2** | Supprimer une base de données |
| **3** | Lister toutes les bases existantes |
| **4** | Afficher tous les comptes FTP actifs |

---

### 6️⃣ Informations serveur
- Espace disque utilisé / total
- Mémoire RAM utilisée / totale
- Nombre d'utilisateurs OTA hébergés
- 5 dernières entrées du log `/var/log/ota_manager.log`

---

### 7️⃣ Remise à zéro
- Double confirmation avant toute action
- Suppression de tous les clients OTA (home, VirtualHost, FTP, DB)
- Désinstallation complète de la pile logicielle
- Nettoyage des paquets orphelins

---

## 🗂️ Arborescence générée

```
/home/
├── client1/
│   ├── .htpasswd              ← si protection htpasswd activée
│   └── www/
│       ├── index.html         ← page générée automatiquement
│       ├── .htaccess          ← si protection activée
│       └── (WordPress si installé)
│
├── client2/
│   └── www/
│       └── ...

/etc/apache2/sites-available/
├── client1.conf               ← VirtualHost dédié
└── client2.conf

/var/log/ota_manager.log       ← journal des opérations OTA
```

---

## 🛡️ Sécurité

- ✅ Vérification de compatibilité OS au démarrage
- ✅ Lancement root obligatoire
- ✅ Validation du nom d'utilisateur par regex (`[a-z][a-z0-9_]{2,31}`)
- ✅ Confirmation du mot de passe + minimum 6 caractères
- ✅ Vérification que les services sont actifs avant chaque opération
- ✅ Confirmation obligatoire avant toute suppression
- ✅ Isolation FTP par chroot dans `/home/<user>/www`
- ✅ Logs Apache séparés par client
- ✅ Protection htpasswd / .htaccess intégrée
- ✅ Traçabilité complète dans `/var/log/ota_manager.log`

---

## 📝 Exemple de log

```
[2025-03-09 14:23:11] [SUCCES] Hébergement 'client1' créé.
[2025-03-09 14:45:02] [SUCCES] WordPress installé avec succès !
[2025-03-09 15:01:33] [SUCCES] Hébergement 'client2' supprimé.
[2025-03-09 15:10:44] [ERREUR] Utilisateur invalide.
```

---

## 📁 Structure du projet

```
projet-ota/
├── ota.sh          ← Script principal
└── README.md       ← Documentation
```

---

## 🗓️ Changelog

| Version | Changements |
|---|---|
| **v2.6** | Vérification de compatibilité OS, correction création utilisateur DB WordPress, autocomplétion TAB dans les menus de suppression/modification |
| **v2.5** | Tableau de bord complet, gestion BDD & FTP refaite, factory reset granulaire, affichage IP + masque + passerelle |
| **v2.4** | Protection htpasswd, WP-CLI, création en boucle, IP dans le menu |
| **v2.3** | Système de logs, validation des entrées, double confirmation suppression |
| **v1.5** | Version initiale — menu, création, suppression, WordPress basique |

---

<div align="center">

*Projet OTA — Développé par **NoxKirna***

</div>
