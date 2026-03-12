#!/bin/bash

# ==========================================
# PROJET OTA - SCRIPT MAÎTRE v2.6
# Développé par NoxKirna
# ==========================================

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

C_RESET='\033[0m'
C_BOLD='\033[1m'
C_RED='\033[31m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_BLUE='\033[34m'
C_CYAN='\033[36m'
C_MAGENTA='\033[35m'

LOG_FILE="/var/log/ota_manager.log"

if [ "$EUID" -ne 0 ]; then
    echo -e "${C_RED}${C_BOLD}❌ Erreur : Tu dois lancer ce script avec sudo.${C_RESET}"
    exit 1
fi

# ==========================================
# VÉRIFICATION DE LA COMPATIBILITÉ DE L'OS
# ==========================================
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" != "debian" && "$ID" != "ubuntu" ]]; then
        echo -e "${C_RED}${C_BOLD}❌ Erreur de compatibilité OS.${C_RESET}"
        echo -e "${C_YELLOW}Ce script est conçu exclusivement pour les systèmes Debian et Ubuntu.${C_RESET}"
        echo -e "Système détecté : ${C_CYAN}$PRETTY_NAME${C_RESET}"
        exit 1
    fi
else
    echo -e "${C_RED}${C_BOLD}❌ Impossible de détecter l'OS. Arrêt par sécurité.${C_RESET}"
    exit 1
fi

print_header() {
    clear
    echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "${C_BOLD} $1 ${C_RESET}"
    echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
}

pause()   { echo ""; read -n 1 -s -r -p "👉 Appuyez sur une touche pour continuer..."; }
succes()  { echo -e "\n${C_GREEN}${C_BOLD}✅ $1${C_RESET}"; log "SUCCES" "$1"; }
erreur()  { echo -e "\n${C_RED}${C_BOLD}❌ $1${C_RESET}"; log "ERREUR" "$1"; }
info()    { echo -e "\n${C_BLUE}ℹ️  $1${C_RESET}"; }
warning() { echo -e "\n${C_YELLOW}⚠️  $1${C_RESET}"; }

log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$LOG_FILE"
}

valider_username() {
    local u="$1"
    if [[ ! "$u" =~ ^[a-z][a-z0-9_]{2,31}$ ]]; then erreur "Nom invalide. Minuscules/chiffres/underscore uniquement."; return 1; fi
    return 0
}

valider_quota() {
    local q="$1"
    if [[ ! "$q" =~ ^[0-9]+$ ]] || [ "$q" -lt 1 ]; then erreur "Quota invalide. Entrez un entier positif (Mo)."; return 1; fi
    return 0
}

verifier_service() {
    local service="$1"
    if ! systemctl is-active --quiet "$service"; then
        systemctl start "$service" 2>/dev/null
        if ! systemctl is-active --quiet "$service"; then return 1; fi
    fi
    return 0
}

list_ota_users() {
    local count=0
    for u in /home/*; do
        if [ -d "$u/www" ]; then
            echo -e "  ${C_CYAN}► $(basename "$u")${C_RESET}"
            ((count++))
        fi
    done
    if [ "$count" -eq 0 ]; then echo -e "  ${C_YELLOW}Aucun utilisateur hébergé.${C_RESET}"; fi
}

confirmer() {
    local message="$1"
    read -p "$(echo -e "${C_YELLOW}⚠️  $message [oui/non] : ${C_RESET}")" reponse
    [[ "$reponse" == "oui" ]]
}

# ==========================================
# 0. INSTALLER LES PRÉREQUIS
# ==========================================
installer_preRequis() {
    print_header "Installation de la pile Web & FTP"
    echo -e "${C_YELLOW}Installation des paquets en cours (mode visible)...${C_RESET}\n"
    
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y apache2 apache2-utils mariadb-server pure-ftpd pure-ftpd-common php libapache2-mod-php php-mysql wget unzip curl
    
    echo -e "\n${C_BLUE}Configuration des services...${C_RESET}"
    a2enmod rewrite > /dev/null 2>&1

    if ! command -v wp &> /dev/null; then
        curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
        chmod +x wp-cli.phar
        mv wp-cli.phar /usr/local/bin/wp
    fi

    mkdir -p /etc/pure-ftpd/conf
    mkdir -p /etc/pure-ftpd/auth

    groupadd -g 1001 ftpuser 2>/dev/null
    id -u ftpuser &>/dev/null || useradd -u 1001 -g 1001 -d /dev/null -s /bin/false ftpuser
    
    echo "yes"  > /etc/pure-ftpd/conf/CreateHomeDir
    echo "/etc/pure-ftpd/pureftpd.pdb" > /etc/pure-ftpd/conf/PureDB
    ln -sf /etc/pure-ftpd/conf/PureDB /etc/pure-ftpd/auth/50puredb
    touch /etc/pure-ftpd/pureftpd.passwd
    pure-pw mkdb > /dev/null 2>&1

    touch "$LOG_FILE"; chmod 640 "$LOG_FILE"
    for service in apache2 mariadb pure-ftpd; do systemctl enable "$service" > /dev/null 2>&1; systemctl restart "$service" 2>/dev/null; done

    succes "Pile Web, FTP, WP-CLI et utilitaires installés !"
    pause
}

# ==========================================
# 1. CRÉER UN HÉBERGEMENT
# ==========================================
create_user() {
    while true; do
        print_header "Créer un nouvel hébergement"
        verifier_service apache2 || return
        verifier_service pure-ftpd || return

        read -p "Nom utilisateur (ou 'Entrée' pour quitter) : " username
        if [[ -z "$username" ]]; then return; fi
        valider_username "$username" || continue
        if id "$username" &>/dev/null; then erreur "L'utilisateur existe déjà."; continue; fi

        while true; do
            read -s -p "Mot de passe : " password; echo ""
            read -s -p "Confirmez le mot de passe : " password2; echo ""
            if [ "$password" != "$password2" ]; then erreur "Mots de passe différents."; elif [ ${#password} -lt 6 ]; then erreur "Minimum 6 caractères."; else break; fi
        done

        while true; do read -p "Quota disque (en Mo) : " quota; valider_quota "$quota" && break; done

        read -p "Créer une base de données ? (oui/non) : " create_db
        read -p "Accès SSH ? (oui/non) : " ssh_access

        echo -e "\n${C_BLUE}--- Création en cours... ---${C_RESET}"
        local shell="/usr/sbin/nologin"; [ "$ssh_access" == "oui" ] && shell="/bin/bash"

        useradd -m -d "/home/$username" -s "$shell" "$username"
        echo "$username:$password" | chpasswd
        mkdir -p "/home/$username/www"

        echo -e "<!DOCTYPE html><html lang='fr'><head><meta charset='UTF-8'><title>Site de $username</title></head><body style='text-align:center;padding:50px;font-family:sans-serif;'><h1>🚀 Site de <strong>$username</strong> !</h1><p>Hébergement OTA par NoxKirna.</p></body></html>" > "/home/$username/www/index.html"

        chown -R "$username:$username" "/home/$username"
        chmod 755 "/home/$username"
        chmod 644 "/home/$username/www/index.html"

        (echo "$password"; echo "$password") | pure-pw useradd "$username" -u "$username" -g "$username" -d "/home/$username/www" -m > /dev/null 2>&1
        pure-pw usermod "$username" -N "$quota" -m > /dev/null 2>&1

        local CONF_FILE="/etc/apache2/sites-available/${username}.conf"
        echo "<VirtualHost *:80>" > "$CONF_FILE"
        echo "    ServerName ${username}.local" >> "$CONF_FILE"
        echo "    ServerAlias www.${username}.local" >> "$CONF_FILE"
        echo "    DocumentRoot /home/${username}/www" >> "$CONF_FILE"
        echo "    <Directory \"/home/${username}/www\">" >> "$CONF_FILE"
        echo "        Options FollowSymLinks" >> "$CONF_FILE"
        echo "        AllowOverride All" >> "$CONF_FILE"
        echo "        Require all granted" >> "$CONF_FILE"
        echo "    </Directory>" >> "$CONF_FILE"
        echo "    ErrorLog \${APACHE_LOG_DIR}/${username}_error.log" >> "$CONF_FILE"
        echo "    CustomLog \${APACHE_LOG_DIR}/${username}_access.log combined" >> "$CONF_FILE"
        echo "</VirtualHost>" >> "$CONF_FILE"

        a2ensite "${username}.conf" > /dev/null 2>&1
        systemctl reload apache2 2>/dev/null

        if [ "$create_db" == "oui" ]; then
            mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`${username}_db\` CHARACTER SET utf8mb4;" 2>/dev/null
            mysql -u root -e "CREATE USER IF NOT EXISTS '${username}'@'localhost' IDENTIFIED BY '${password}';" 2>/dev/null
            mysql -u root -e "GRANT ALL PRIVILEGES ON \`${username}_db\`.* TO '${username}'@'localhost';" 2>/dev/null
            mysql -u root -e "FLUSH PRIVILEGES;" 2>/dev/null
        fi

        succes "Hébergement '$username' créé."
        read -p "Créer un autre hébergement ? (oui/non) : " encore
        if [[ "$encore" != "oui" ]]; then return; fi
    done
}

# ==========================================
# 2. SUPPRIMER UN HÉBERGEMENT
# ==========================================
delete_user() {
    while true; do
        print_header "Supprimer un hébergement"
        echo -e "${C_BOLD}Liste des utilisateurs hébergés :${C_RESET}"
        list_ota_users
        echo ""
        
        cd /home/ || exit
        read -e -p "Utilisateur à supprimer (TAB pour compléter) : " username
        cd - > /dev/null || exit
        
        if [[ -z "$username" ]]; then return; fi
        if ! id "$username" &>/dev/null || [ ! -d "/home/$username/www" ]; then erreur "Utilisateur invalide."; pause; continue; fi
        
        confirmer "Supprimer définitivement '$username' ?" || continue
        
        a2dissite "${username}.conf" > /dev/null 2>&1
        rm -f "/etc/apache2/sites-available/${username}.conf"
        systemctl reload apache2 2>/dev/null
        pure-pw userdel "$username" -m > /dev/null 2>&1
        mysql -u root -e "DROP DATABASE IF EXISTS \`${username}_db\`; DROP USER IF EXISTS '${username}'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null
        userdel -r "$username" 2>/dev/null
        
        succes "Hébergement '$username' supprimé."
        pause
    done
}

# ==========================================
# 3. MODIFIER UN HÉBERGEMENT
# ==========================================
modify_user() {
    while true; do
        print_header "Modifier un hébergement"
        echo -e "${C_BOLD}Liste des utilisateurs hébergés :${C_RESET}"
        list_ota_users
        echo ""
        
        cd /home/ || exit
        read -e -p "Utilisateur à modifier (TAB pour compléter) : " username
        cd - > /dev/null || exit
        
        if [[ -z "$username" ]]; then return; fi
        if ! id "$username" &>/dev/null || [ ! -d "/home/$username/www" ]; then continue; fi

        while true; do
            print_header "Modification de '$username'"
            echo "  1. Changer quota FTP    | 2. Changer MDP"
            echo "  3. Activer/Désac SSH    | 4. Gérer la BDD"
            echo "  5. Activer/Désac FTP    | 6. 🔒 Sécuriser le site (htpasswd)"
            echo "  7. Retour"
            read -p "Choix : " mod_choice
            case $mod_choice in
                1) 
                    read -p "Nouveau quota (Mo) : " nq
                    pure-pw usermod "$username" -N "$nq" -m >/dev/null 2>&1
                    succes "Quota modifié." 
                    ;;
                2) 
                    read -s -p "Nouveau MDP : " np; echo ""
                    (echo "$np"; echo "$np") | pure-pw passwd "$username" -m >/dev/null 2>&1
                    echo "$username:$np" | chpasswd
                    succes "MDP modifié." 
                    ;;
                3) 
                    if [ "$(grep "^$username:" /etc/passwd | cut -d: -f7)" == "/bin/bash" ]; then 
                        usermod -s /usr/sbin/nologin "$username"
                        succes "SSH OFF"
                    else 
                        usermod -s /bin/bash "$username"
                        succes "SSH ON"
                    fi 
                    ;;
                4) 
                    read -p "A) Créer B) Supprimer : " dbc
                    if [ "${dbc^^}" == "A" ]; then 
                        mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`${username}_db\`; GRANT ALL ON \`${username}_db\`.* TO '${username}'@'localhost'; FLUSH PRIVILEGES;"
                        succes "BDD Créée"
                    else 
                        mysql -u root -e "DROP DATABASE IF EXISTS \`${username}_db\`; FLUSH PRIVILEGES;"
                        succes "BDD Supprimée"
                    fi 
                    ;;
                5) 
                    if pure-pw show "$username" &>/dev/null; then 
                        pure-pw userdel "$username" -m >/dev/null 2>&1
                        succes "FTP OFF"
                    else 
                        pure-pw useradd "$username" -u "$username" -g "$username" -d "/home/$username/www" -m >/dev/null 2>&1
                        succes "FTP ON"
                    fi 
                    ;;
                6) 
                    print_header "Sécuriser le site (htpasswd) : $username"
                    echo -e "  1. 🔒 Activer la protection (demander un mot de passe)"
                    echo -e "  2. 🔓 Désactiver la protection (rendre le site public)"
                    echo -e "  3. Retour"
                    read -p "  Choix : " ht_choice
                    case $ht_choice in
                        1)
                            read -p "  Nom d'utilisateur web : " ht_user
                            read -s -p "  Mot de passe web : " ht_pass; echo ""
                            htpasswd -bc "/home/$username/.htpasswd" "$ht_user" "$ht_pass" > /dev/null 2>&1
                            chown "$username:$username" "/home/$username/.htpasswd"
                            
                            echo "AuthType Basic" > "/home/$username/www/.htaccess"
                            echo "AuthName \"Acces Securise\"" >> "/home/$username/www/.htaccess"
                            echo "AuthUserFile /home/$username/.htpasswd" >> "/home/$username/www/.htaccess"
                            echo "Require valid-user" >> "/home/$username/www/.htaccess"
                            
                            chown "$username:$username" "/home/$username/www/.htaccess"
                            succes "Protection activée."
                            ;;
                        2)
                            rm -f "/home/$username/www/.htaccess" "/home/$username/.htpasswd"
                            succes "Protection désactivée."
                            ;;
                    esac
                    ;;
                7) break ;;
                *) erreur "Choix invalide." ;;
            esac
            pause
        done
    done
}

# ==========================================
# 4. TABLEAU DE BORD & WORDPRESS
# ==========================================
show_users() {
    while true; do
        print_header "Tableau de Bord & WordPress"
        local found=false
        printf "%-20s %-15s %-15s %-10s %-10s\n" "UTILISATEUR" "ESPACE UTILISÉ" "QUOTA FTP" "SSH" "DB"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        for user_home in /home/*; do
            if [ -d "$user_home/www" ]; then
                found=true
                local uname=$(basename "$user_home")
                local usage=$(du -sh "$user_home" 2>/dev/null | cut -f1)
                local quota_ftp=$(pure-pw show "$uname" 2>/dev/null | grep -i "Disk quota" | awk '{print $NF}' | sed 's/[^0-9]//g')
                [ -z "$quota_ftp" ] && quota_ftp="N/A" || quota_ftp="${quota_ftp} Mo"
                local shell_type=$(grep "^$uname:" /etc/passwd | cut -d: -f7)
                [ "$shell_type" == "/bin/bash" ] && ssh_status="✅" || ssh_status="❌"
                local db_status="❌"
                mysql -u root -e "SHOW DATABASES LIKE '${uname}_db';" 2>/dev/null | grep -q "${uname}_db" && db_status="✅"
                printf "%-20s %-15s %-15s %-10s %-10s\n" "$uname" "$usage" "$quota_ftp" "$ssh_status" "$db_status"
            fi
        done
        if ! $found; then echo -e "  ${C_YELLOW}Aucun utilisateur hébergé.${C_RESET}"; pause; return; fi
        
        echo ""
        cd /home/ || exit
        read -e -p "Utilisateur pour voir détails (TAB) : " user
        cd - > /dev/null || exit
        
        if [[ -z "$user" ]]; then return; fi
        if ! id "$user" &>/dev/null || [ ! -d "/home/$user/www" ]; then continue; fi

        echo -e "\n${C_BOLD}Fichiers actuels dans /home/$user/www :${C_RESET}"
        ls -lh "/home/$user/www" 2>/dev/null | tail -n +2
        echo ""
        
        read -p "Installer WordPress pour '$user' ? (oui/non) : " install_wp
        if [ "$install_wp" == "oui" ]; then install_wordpress "$user"; fi
        pause
    done
}

install_wordpress() {
    local user="$1"
    local wp_dir="/home/$user/www"
    
    local db_exists=$(mysql -u root -e "SHOW DATABASES LIKE '${user}_db';" 2>/dev/null | grep -v "Database")
    if [[ -z "$db_exists" ]]; then
        warning "WordPress nécessite une base de données."
        read -p "Créer la base '${user}_db' ? (oui/non) : " c_db
        if [ "$c_db" == "oui" ]; then
            mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`${user}_db\`;" 2>/dev/null
            succes "Base créée."
        else 
            return
        fi
    fi
    
    read -s -p "Mot de passe de la base '${user}_db' : " wp_db_pwd; echo ""
    
    # Correction : création propre de l'utilisateur DB avant de lui donner les droits
    mysql -u root -e "CREATE USER IF NOT EXISTS '${user}'@'localhost' IDENTIFIED BY '${wp_db_pwd}';" 2>/dev/null
    mysql -u root -e "ALTER USER '${user}'@'localhost' IDENTIFIED BY '${wp_db_pwd}'; GRANT ALL PRIVILEGES ON \`${user}_db\`.* TO '${user}'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null
    
    echo -e "${C_YELLOW}Téléchargement de WordPress...${C_RESET}"
    rm -rf "$wp_dir"/*
    wget -q https://wordpress.org/latest.zip -O /tmp/wp.zip
    unzip -q /tmp/wp.zip -d /tmp/wp/ > /dev/null
    cp -rf /tmp/wp/wordpress/* "$wp_dir/"
    rm -rf /tmp/wp /tmp/wp.zip
    
    cp "$wp_dir/wp-config-sample.php" "$wp_dir/wp-config.php"
    sed -i "s/database_name_here/${user}_db/" "$wp_dir/wp-config.php"
    sed -i "s/username_here/${user}/" "$wp_dir/wp-config.php"
    sed -i "s/password_here/${wp_db_pwd}/" "$wp_dir/wp-config.php"
    
    echo -e "\n${C_BOLD}--- Configuration de l'Administrateur WP ---${C_RESET}"
    read -p "Nom de l'admin WordPress (ex: admin) : " wp_admin
    read -s -p "Mot de passe de l'admin : " wp_pass; echo ""
    
    echo -e "${C_YELLOW}Installation WP-CLI en cours...${C_RESET}"
    wp core install --url="http://${user}.local" --title="Site de ${user}" --admin_user="$wp_admin" --admin_password="$wp_pass" --admin_email="admin@$user.local" --path="$wp_dir" --allow-root > /dev/null 2>&1
    
    chown -R "$user:$user" "$wp_dir"
    succes "WordPress installé avec succès !"
}

# ==========================================
# 5. GESTION BDD & FTP
# ==========================================
manage_db_ftp() {
    while true; do
        print_header "🗄️ Gestion BDD & FTP"
        verifier_service mariadb || { pause; return; }
        
        echo "  1. Créer une base de données"
        echo "  2. Supprimer une base de données"
        echo "  3. Lister les bases existantes"
        echo "  4. Afficher les comptes FTP existants"
        echo "  5. Retour"
        read -p "Choix : " choice
        
        case $choice in
            1) 
                read -p "Nom de la base : " db
                mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`$db\`;" 2>/dev/null
                succes "Base '$db' créée." 
                ;;
            2) 
                echo -e "\n${C_BOLD}Bases disponibles :${C_RESET}"
                mysql -u root -e "SHOW DATABASES;" 2>/dev/null | grep -v -E "schema|mysql|sys"
                read -p "Nom de la base à supprimer : " db
                mysql -u root -e "DROP DATABASE IF EXISTS \`$db\`;" 2>/dev/null
                succes "Base '$db' supprimée." 
                ;;
            3) 
                echo -e "\n${C_BOLD}Bases existantes :${C_RESET}"
                mysql -u root -e "SHOW DATABASES;" 2>/dev/null | grep -v -E "schema|mysql|sys" 
                ;;
            4) 
                echo -e "\n${C_BOLD}Comptes FTP :${C_RESET}"
                pure-pw list 2>/dev/null
                ;;
            5) return ;;
            *) erreur "Choix invalide." ;;
        esac
        pause
    done
}

# ==========================================
# 6. INFOS SERVEUR
# ==========================================
server_info() {
    print_header "Informations Serveur"
    echo -e "${C_BOLD}Espace disque :${C_RESET} $(df -h / | awk 'NR==2 {print $3 " / " $2}')"
    echo -e "${C_BOLD}RAM utilisée  :${C_RESET} $(free -h | awk '/Mem/ {print $3 " / " $2}')"
    
    local user_count=$(ls -ld /home/*/www 2>/dev/null | grep "^d" | wc -l)
    echo -e "\n${C_BOLD}Nombre d'utilisateurs OTA :${C_RESET} $user_count"
    
    if [ -f "$LOG_FILE" ]; then
        echo -e "\n${C_BOLD}Dernières actions (log OTA) :${C_RESET}"
        tail -5 "$LOG_FILE" | while read line; do echo -e "  ${C_MAGENTA}$line${C_RESET}"; done
    fi
    pause
}

# ==========================================
# 7. REMISE À ZÉRO GRANULAIRE
# ==========================================
factory_reset() {
    print_header "☢️ REMISE À ZÉRO DU SERVEUR"
    echo -e "${C_RED}ATTENTION : Action irréversible.${C_RESET}"
    confirmer "Voulez-vous vraiment TOUT effacer (Clients + Services) ?" || return
    
    echo -e "\n${C_YELLOW}Suppression en cours...${C_RESET}"
    for u in /home/*; do 
        if [ -d "$u/www" ]; then 
            uname=$(basename "$u")
            a2dissite "${uname}.conf" > /dev/null 2>&1
            pure-pw userdel "$uname" -m > /dev/null 2>&1
            mysql -u root -e "DROP DATABASE IF EXISTS \`${uname}_db\`;" 2>/dev/null
            userdel -r "$uname" 2>/dev/null
        fi
    done
    
    apt-get purge -y apache2* mariadb* pure-ftpd* php* > /dev/null 2>&1
    apt-get autoremove --purge -y > /dev/null 2>&1
    rm -rf /etc/apache2 /etc/pure-ftpd /etc/php /var/lib/mysql /etc/mysql /home/*
    
    succes "Système entièrement remis à zéro."
    pause
}

# ==========================================
# MENU PRINCIPAL
# ==========================================
main_menu() {
    while true; do
        local IP=$(ip -4 addr show scope global | awk '$1=="inet" {print $2}' | head -n 1)
        local GW=$(ip route | awk '/default/ {print $3}' | head -n 1)
        
        clear
        echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
        echo -e "${C_BOLD}${C_YELLOW}         🚀 GESTION HÉBERGEMENT WEB - PROJET OTA v2.6 🚀            ${C_RESET}"
        echo -e "${C_CYAN}                     Développé par NoxKirna                         ${C_RESET}"
        echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
        echo -e "   🌐 IP : ${C_GREEN}${IP}${C_RESET} | 🌍 Passerelle : ${C_GREEN}${GW}${C_RESET}"
        echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
        echo -e "   ${C_BOLD}0)${C_RESET} ${C_YELLOW}Installer les prérequis${C_RESET}"
        echo -e "   ${C_BOLD}1)${C_RESET} Créer un hébergement"
        echo -e "   ${C_BOLD}2)${C_RESET} Supprimer un hébergement"
        echo -e "   ${C_BOLD}3)${C_RESET} Modifier un hébergement (Mot de passe, Quota...)"
        echo -e "   ${C_BOLD}4)${C_RESET} Tableau de bord / Installer WordPress"
        echo -e "   ${C_BOLD}5)${C_RESET} Bases de données & Comptes FTP"
        echo -e "   ${C_BOLD}6)${C_RESET} Infos serveur et Logs"
        echo -e "   ${C_BOLD}7)${C_RESET} ${C_RED}⚠️ Remise à zéro totale${C_RESET}"
        echo -e "   ${C_BOLD}8)${C_RESET} Quitter"
        echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"

        read -p "$(echo -e "${C_BOLD}👉 Ton choix [0-8] : ${C_RESET}")" OPTION
        case $OPTION in
            0) installer_preRequis ;;
            1) create_user ;;
            2) delete_user ;;
            3) modify_user ;;
            4) show_users ;;
            5) manage_db_ftp ;;
            6) server_info ;;
            7) factory_reset ;;
            8) clear; echo -e "${C_GREEN}Fermeture. À bientôt !${C_RESET}\n"; exit 0 ;;
            *) echo -e "\n${C_RED}Choix invalide.${C_RESET}"; sleep 1 ;;
        esac
    done
}


main_menu
