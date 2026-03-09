🚀 Projet OTA - OpenSource Tenant Architecture
📝 Présentation du projet
Le projet OTA a pour but de concevoir une solution d'hébergement mutualisée automatisée via un script Bash. Ce script permet à un administrateur de gérer des comptes utilisateurs incluant un répertoire web, un accès FTP, un quota disque, une base de données et un accès SSH.

🛠️ Fonctionnalités implémentées
1. Gestion des comptes utilisateurs
Création complète : Création de l'utilisateur Linux, de son répertoire /home/utilisateur/www, définition du mot de passe, du quota disque et de l'accès FTP .
Automatisation Web : Création automatique d'un VirtualHost Apache pour chaque client.
Modification : Possibilité de changer le quota, le mot de passe, l'accès SSH ou la base de données .
Suppression : Nettoyage complet (fichiers, utilisateur, BDD et accès FTP) .
2. Gestion des fichiers web
Affichage de la liste des utilisateurs et de leur espace disque utilisé.
Listing des fichiers présents dans le dossier www.
Installation automatique de WordPress en un clic.
3. Gestion des bases de données
Création et suppression de bases de données MariaDB.
Affichage des bases existantes.
📸 Démonstration technique
Menu principal du script
Le script utilise un menu interactif structuré avec des fonctions pour une navigation simplifiée.
<img width="976" height="372" alt="image" src="https://github.com/user-attachments/assets/c3bf12f2-45be-4158-af32-226e51cddacd" />
Création d'un hébergement
Lors de la création, le script demande les informations nécessaires (Nom, Quota, BDD, SSH) .
<img width="975" height="471" alt="image" src="https://github.com/user-attachments/assets/32ed1cea-350b-42b6-9118-a179dc919047" />
🚀 Installation et Utilisation
Clonage du dépôt :
git clone https://github.com/NoxKirna/OTA.git
cd OTA
Exécution :
Le script doit être exécuté en tant que root :
chmod +x ota_master.sh
./ota_master.sh
Initialisation :
Utilisez l'option 0 du menu pour installer automatiquement Apache, MariaDB, Pure-FTPd et PHP.
🔧 Contraintes techniques respectées
Script 100% Bash.
Utilisation de fonctions pour chaque action.
Vérification des erreurs (ex: test d'existence de l'utilisateur).
Commentaires détaillés dans le code
