#!/bin/bash

# ==========================================
# PROJET OTA - SCRIPT MAÎTRE
# Script 100% Bash avec menu interactif
# ==========================================
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# Couleurs pour un bel affichage
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_RED='\033[31m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_BLUE='\033[34m'
C_CYAN='\033[36m'

# Vérification des droits root
if [ "$EUID" -ne 0 ]; then
  echo -e "${C_RED}${C_BOLD}❌ Erreur : Tu dois lancer ce script avec sudo.${C_RESET}"
  exit 1
fi

# ==========================================
# FONCTIONS UTILITAIRES
# ==========================================
print_header() {
    clear
    echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "${C_BOLD} $1 ${C_RESET}"
    echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
}
pause() { echo ""; read -n 1 -s -r -p "👉 Appuyez sur une touche pour continuer..."; }
succes() { echo -e "\n${C_GREEN}${C_BOLD}✅ $1${C_RESET}"; }
erreur() { echo -e "\n${C_RED}${C_BOLD}❌ $1${C_RESET}"; }

# Nouvelle fonction pour n'afficher que les clients OTA (qui ont un dossier www)
list_ota_users() {
    local count=0
    for u in /home/*; do
        if [ -d "$u/www" ]; then
            echo -e "  ${C_CYAN}► $(basename $u)${C_RESET}"
            ((count++))
        fi
    done
    if [ $count -eq 0 ]; then
        echo -e "  ${C_YELLOW}Aucun utilisateur hébergé pour le moment.${C_RESET}"
    fi
}

# ==========================================
# 0. INSTALLER LES PRÉREQUIS
# ==========================================
installer_preRequis() {
    print_header "Installation de la pile Web & FTP"
    echo -e "${C_YELLOW}Mise à jour des paquets...${C_RESET}"
    apt update

    echo -e "\n${C_YELLOW}Installation d'Apache, MariaDB, Pure-FTPd et PHP...${C_RESET}"
    apt install -y apache2 mariadb-server pure-ftpd php libapache2-mod-php wget unzip

    echo -e "\n${C_YELLOW}Configuration initiale de Pure-FTPd...${C_RESET}"
    groupadd -g 1001 ftpuser 2>/dev/null
    id -u ftpuser &>/dev/null || useradd -u 1001 -g 1001 -d /dev/null -s /bin/false ftpuser
    echo "yes" > /etc/pure-ftpd/conf/CreateHomeDir
    echo "/etc/pure-ftpd/pureftpd.pdb" > /etc/pure-ftpd/conf/PureDB
    ln -sf /etc/pure-ftpd/conf/PureDB /etc/pure-ftpd/auth/50puredb
    touch /etc/pure-ftpd/pureftpd.passwd
    pure-pw mkdb > /dev/null 2>&1
    
    if systemctl restart pure-ftpd; then
        succes "Pile Web et FTP installée et configurée avec succès !"
    else
        erreur "Problème au démarrage de FTP."
    fi
    pause
}

# ==========================================
# 1. CRÉER UN HÉBERGEMENT
# ==========================================
create_user() {
    print_header "Créer un nouvel hébergement"
    read -p "Nom utilisateur (ex: client1) : " username
    
    if id "$username" &>/dev/null; then erreur "L'utilisateur existe déjà."; pause; return; fi

    read -s -p "Mot de passe : " password; echo ""
    read -p "Quota disque (en Mo, ex: 500) : " quota
    read -p "Créer une base de données ? (oui/non) : " create_db
    read -p "Accès SSH ? (oui/non) : " ssh_access

    echo -e "\n${C_BLUE}--- Création du système ---${C_RESET}"
    
    shell="/usr/sbin/nologin"
    [ "$ssh_access" == "oui" ] && shell="/bin/bash"
    
    useradd -m -d /home/$username -s $shell $username
    echo "$username:$password" | chpasswd
    mkdir -p /home/$username/www
    chown -R $username:$username /home/$username
    chmod 755 /home/$username

    (echo "$password"; echo "$password") | pure-pw useradd $username -u $username -g $username -d /home/$username/www -m > /dev/null 2>&1
    pure-pw usermod $username -N $quota -m > /dev/null 2>&1

    CONF_FILE="/etc/apache2/sites-available/${username}.conf"
    cat <<EOF > "$CONF_FILE"
<VirtualHost *:80>
    ServerName $username.local
    DocumentRoot /home/$username/www
    <Directory "/home/$username/www">
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
    a2ensite ${username}.conf > /dev/null 2>&1
    systemctl reload apache2 2>/dev/null

    if [ "$create_db" == "oui" ]; then
        db_name="${username}_db"
        mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`${db_name}\`;" 2>/dev/null
        mysql -u root -e "CREATE USER IF NOT EXISTS '${username}'@'localhost' IDENTIFIED BY '${password}';" 2>/dev/null
        mysql -u root -e "GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${username}'@'localhost';" 2>/dev/null
        mysql -u root -e "FLUSH PRIVILEGES;" 2>/dev/null
        echo -e "${C_GREEN}Base de données '${db_name}' créée.${C_RESET}"
    fi

    succes "Hébergement $username créé avec succès !"
    pause
}

# ==========================================
# 2. SUPPRIMER UN HÉBERGEMENT
# ==========================================
delete_user() {
    print_header "Supprimer un hébergement"
    echo -e "Utilisateurs existants :"
    list_ota_users
    echo "------------------------------------------------"
    
    cd /home/ || exit
    read -e -p "Nom de l'utilisateur à supprimer (utilise TAB) : " username
    cd - > /dev/null || exit
    
    if [[ -z "$username" ]]; then return; fi
    if ! id "$username" &>/dev/null; then erreur "L'utilisateur n'existe pas."; pause; return; fi

    echo -e "\n${C_RED}Suppression en cours...${C_RESET}"
    
    a2dissite ${username}.conf > /dev/null 2>&1
    rm -f /etc/apache2/sites-available/${username}.conf
    systemctl reload apache2 2>/dev/null

    pure-pw userdel $username -m > /dev/null 2>&1
    mysql -u root -e "DROP DATABASE IF EXISTS \`${username}_db\`;" 2>/dev/null
    mysql -u root -e "DROP USER IF EXISTS '${username}'@'localhost';" 2>/dev/null
    userdel -r $username 2>/dev/null
    
    succes "Hébergement $username supprimé totalement."
    pause
}

# ==========================================
# 3. MODIFIER UN HÉBERGEMENT
# ==========================================
modify_user() {
    print_header "Modifier un hébergement"
    echo -e "Utilisateurs existants :"
    list_ota_users
    echo "------------------------------------------------"
    
    cd /home/ || exit
    read -e -p "Nom de l'utilisateur (utilise TAB) : " username
    cd - > /dev/null || exit
    
    if [[ -z "$username" ]]; then return; fi
    if ! id "$username" &>/dev/null; then erreur "Utilisateur introuvable."; pause; return; fi

    echo -e "\n1. Changer le quota disque (FTP)"
    echo "2. Changer le mot de passe"
    echo "3. Activer/Désactiver SSH"
    echo "4. Créer ou supprimer une base de données"
    read -p "Choix : " mod_choice

    case $mod_choice in
        1)
            read -p "Nouveau quota (Mo) : " new_quota
            pure-pw usermod $username -N $new_quota -m > /dev/null 2>&1
            succes "Quota mis à jour." ;;
        2)
            read -s -p "Nouveau mot de passe : " new_pwd; echo ""
            echo "$username:$new_pwd" | chpasswd
            (echo "$new_pwd"; echo "$new_pwd") | pure-pw passwd $username -m > /dev/null 2>&1
            succes "Mot de passe mis à jour." ;;
        3)
            current_shell=$(grep "^$username:" /etc/passwd | cut -d: -f7)
            if [ "$current_shell" == "/bin/bash" ]; then
                usermod -s /usr/sbin/nologin $username
                succes "Accès SSH désactivé."
            else
                usermod -s /bin/bash $username
                succes "Accès SSH activé."
            fi ;;
        4)
            echo "  A) Créer une base de données"
            echo "  B) Supprimer sa base de données"
            read -p "  Choix (A/B) : " db_choice
            if [[ "$db_choice" == "A" || "$db_choice" == "a" ]]; then
                read -s -p "Mot de passe pour l'utilisateur DB $username : " db_pwd; echo ""
                mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`${username}_db\`;" 2>/dev/null
                mysql -u root -e "CREATE USER IF NOT EXISTS '${username}'@'localhost' IDENTIFIED BY '${db_pwd}';" 2>/dev/null
                mysql -u root -e "GRANT ALL PRIVILEGES ON \`${username}_db\`.* TO '${username}'@'localhost';" 2>/dev/null
                mysql -u root -e "FLUSH PRIVILEGES;" 2>/dev/null
                succes "Base de données créée."
            elif [[ "$db_choice" == "B" || "$db_choice" == "b" ]]; then
                mysql -u root -e "DROP DATABASE IF EXISTS \`${username}_db\`;" 2>/dev/null
                mysql -u root -e "DROP USER IF EXISTS '${username}'@'localhost';" 2>/dev/null
                succes "Base de données supprimée."
            fi ;;
    esac
    pause
}

# ==========================================
# 4. AFFICHER HÉBERGEMENT ET FICHIERS WEB
# ==========================================
show_users() {
    print_header "Afficher les hébergements & Fichiers Web"
    
    echo -e "${C_BOLD}Utilisateur\tEspace Utilisé\tDossier Web${C_RESET}"
    echo "---------------------------------------------------------"
    for user_home in /home/*; do
        if [ -d "$user_home/www" ]; then
            username=$(basename $user_home)
            usage=$(du -sh $user_home 2>/dev/null | cut -f1)
            echo -e "$username\t\t$usage\t\t$user_home/www"
        fi
    done
    
    echo ""
    cd /home/ || exit
    read -e -p "Nom d'un utilisateur pour voir ses détails (utilise TAB, ou Entrée pour quitter) : " detail_user
    cd - > /dev/null || exit
    
    if [[ -n "$detail_user" ]] && id "$detail_user" &>/dev/null; then
        echo -e "\n${C_CYAN}--- Détails de l'hébergement : $detail_user ---${C_RESET}"
        echo -e "${C_BOLD}Quota FTP :${C_RESET} $(pure-pw show $detail_user 2>/dev/null | grep 'Disk quota' | awk '{print $4, $5}')"
        echo -e "${C_BOLD}Accès SSH :${C_RESET} $(grep "^$detail_user:" /etc/passwd | cut -d: -f7)"
        
        db_exists=$(mysql -u root -e "SHOW DATABASES LIKE '${detail_user}_db';" 2>/dev/null | grep -v "Database")
        if [[ -n "$db_exists" ]]; then echo -e "${C_BOLD}Base de données :${C_RESET} Oui (${detail_user}_db)"; else echo -e "${C_BOLD}Base de données :${C_RESET} Non"; fi
        
        echo -e "\n${C_BOLD}Fichiers présents dans le dossier www :${C_RESET}"
        ls -lh /home/$detail_user/www
        
        echo ""
        read -p "Voulez-vous installer WordPress pour cet utilisateur ? (oui/non) : " install_wp
        if [ "$install_wp" == "oui" ]; then
            echo -e "${C_YELLOW}Téléchargement et installation de WordPress...${C_RESET}"
            wget -q https://wordpress.org/latest.zip -O /tmp/wp.zip
            unzip -q /tmp/wp.zip -d /tmp/ > /dev/null
            cp -r /tmp/wordpress/* /home/$detail_user/www/
            chown -R $detail_user:$detail_user /home/$detail_user/www
            rm -rf /tmp/wordpress /tmp/wp.zip
            succes "WordPress installé avec succès !"
        fi
    fi
    pause
}

# ==========================================
# 5. GESTION DES BASES DE DONNÉES GLOBALE
# ==========================================
manage_databases() {
    print_header "Gestion globale des bases de données"
    echo "1. Créer une base de données manuellement"
    echo "2. Supprimer une base de données manuellement"
    echo "3. Lister les bases existantes"
    read -p "Choix : " db_choice

    case $db_choice in
        1)
            read -p "Nom de la base : " new_db
            mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`${new_db}\`;" 2>/dev/null
            succes "Base $new_db créée." ;;
        2)
            read -p "Nom de la base à supprimer : " db_drop
            mysql -u root -e "DROP DATABASE \`${db_drop}\`;" 2>/dev/null
            succes "Base $db_drop supprimée." ;;
        3) mysql -u root -e "SHOW DATABASES;" ;;
    esac
    pause
}

# ==========================================
# 6. INFORMATIONS SERVEUR
# ==========================================
server_info() {
    print_header "Informations Serveur"
    echo -e "${C_BOLD}Espace disque total (racine) :${C_RESET}"
    df -h / | grep -v "Filesystem"
    
    echo -e "\n${C_BOLD}Nombre d'utilisateurs hébergés :${C_RESET}"
    ls -l /home | grep "^d" | wc -l
    
    echo -e "\n${C_BOLD}Liste des sites (VirtualHosts actifs) :${C_RESET}"
    ls -1 /etc/apache2/sites-enabled/ 2>/dev/null | grep -v "total"
    
    echo -e "\n${C_BOLD}Comptes FTP actifs :${C_RESET}"
    pure-pw list 2>/dev/null | wc -l
    
    pause
}

# ==========================================
# MENU PRINCIPAL
# ==========================================
main_menu() {
    while true; do
        clear
        echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
        echo -e "${C_BOLD}${C_YELLOW}           🚀 GESTION HÉBERGEMENT WEB - PROJET OTA 🚀           ${C_RESET}"
        echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
        echo -e "   ${C_BOLD}0)${C_RESET} ${C_YELLOW}Installer les prérequis (À faire une fois)${C_RESET}"
        echo -e "   ${C_BOLD}1)${C_RESET} Créer un hébergement"
        echo -e "   ${C_BOLD}2)${C_RESET} Supprimer un hébergement"
        echo -e "   ${C_BOLD}3)${C_RESET} Modifier un hébergement"
        echo -e "   ${C_BOLD}4)${C_RESET} Afficher un hébergement (et Gestion des fichiers web)"
        echo -e "   ${C_BOLD}5)${C_RESET} Gestion des bases de données"
        echo -e "   ${C_BOLD}6)${C_RESET} Informations serveur"
        echo -e "   ${C_BOLD}7)${C_RESET} ${C_RED}Quitter${C_RESET}"
        echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
        
        read -p "$(echo -e ${C_BOLD}👉 Ton choix [0-7] : ${C_RESET})" OPTION

        case $OPTION in
            0) installer_preRequis ;;
            1) create_user ;;
            2) delete_user ;;
            3) modify_user ;;
            4) show_users ;;
            5) manage_databases ;;
            6) server_info ;;
            7) clear; echo -e "${C_GREEN}Fermeture du script OTA. À bientôt !${C_RESET}\n"; exit 0 ;;
            *) echo -e "\n${C_RED}Choix invalide.${C_RESET}"; sleep 1 ;;
        esac
    done
}

# Lancement du menu interactif
main_menu