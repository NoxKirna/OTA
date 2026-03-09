#!/bin/bash

# ==========================================
# PROJET OTA - SCRIPT MAÎTRE v2.1
# Script 100% Bash avec menu interactif
# ==========================================
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# Couleurs
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_RED='\033[31m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_BLUE='\033[34m'
C_CYAN='\033[36m'
C_MAGENTA='\033[35m'

# Fichier de log
LOG_FILE="/var/log/ota_manager.log"

# ==========================================
# VÉRIFICATION ROOT
# ==========================================
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
    if [[ ! "$u" =~ ^[a-z][a-z0-9_]{2,31}$ ]]; then
        erreur "Nom invalide. Utilise uniquement des minuscules/chiffres/underscore (3-32 car., commence par une lettre)."
        return 1
    fi
    return 0
}

valider_quota() {
    local q="$1"
    if [[ ! "$q" =~ ^[0-9]+$ ]] || [ "$q" -lt 1 ]; then
        erreur "Quota invalide. Entrez un nombre entier positif (en Mo)."
        return 1
    fi
    return 0
}

verifier_service() {
    local service="$1"
    if ! systemctl is-active --quiet "$service"; then
        warning "Le service '$service' n'est pas actif. Tentative de démarrage..."
        systemctl start "$service" 2>/dev/null
        if ! systemctl is-active --quiet "$service"; then
            erreur "Impossible de démarrer '$service'. Vérifiez votre installation (option 0)."
            return 1
        fi
        succes "Service '$service' démarré."
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
    if [ "$count" -eq 0 ]; then
        echo -e "  ${C_YELLOW}Aucun utilisateur hébergé pour le moment.${C_RESET}"
    fi
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

    local deja_installe=true
    for pkg in apache2 mariadb-server pure-ftpd php php-mysql; do
        if ! dpkg -l "$pkg" &>/dev/null; then
            deja_installe=false
            break
        fi
    done

    if $deja_installe; then
        warning "Les paquets semblent déjà installés."
        confirmer "Voulez-vous réinstaller / reconfigurer quand même ?" || { pause; return; }
    fi

    echo -e "${C_YELLOW}Mise à jour des paquets...${C_RESET}"
    apt update -qq

    echo -e "\n${C_YELLOW}Installation d'Apache, MariaDB, Pure-FTPd, PHP et outils...${C_RESET}"
    apt install -y apache2 mariadb-server pure-ftpd php libapache2-mod-php php-mysql wget unzip curl

    a2enmod rewrite > /dev/null 2>&1

    echo -e "\n${C_YELLOW}Configuration de Pure-FTPd...${C_RESET}"
    groupadd -g 1001 ftpuser 2>/dev/null
    id -u ftpuser &>/dev/null || useradd -u 1001 -g 1001 -d /dev/null -s /bin/false ftpuser
    echo "yes"  > /etc/pure-ftpd/conf/CreateHomeDir
    echo "/etc/pure-ftpd/pureftpd.pdb" > /etc/pure-ftpd/conf/PureDB
    ln -sf /etc/pure-ftpd/conf/PureDB /etc/pure-ftpd/auth/50puredb
    touch /etc/pure-ftpd/pureftpd.passwd
    pure-pw mkdb > /dev/null 2>&1

    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"

    for service in apache2 mariadb pure-ftpd; do
        systemctl enable "$service" > /dev/null 2>&1
        systemctl restart "$service" 2>/dev/null
    done

    if systemctl is-active --quiet apache2 && systemctl is-active --quiet pure-ftpd; then
        succes "Pile Web et FTP installée et configurée avec succès !"
    else
        erreur "Un service n'a pas démarré correctement."
    fi
    pause
}

# ==========================================
# 1. CRÉER UN HÉBERGEMENT
# ==========================================
create_user() {
    print_header "Créer un nouvel hébergement"

    verifier_service apache2   || { pause; return; }
    verifier_service pure-ftpd || { pause; return; }

    while true; do
        read -p "Nom utilisateur (ex: client1) : " username
        valider_username "$username" || continue
        if id "$username" &>/dev/null; then
            erreur "L'utilisateur '$username' existe déjà."
            pause; return
        fi
        break
    done

    while true; do
        read -s -p "Mot de passe : " password; echo ""
        read -s -p "Confirmez le mot de passe : " password2; echo ""
        if [ "$password" != "$password2" ]; then
            erreur "Les mots de passe ne correspondent pas."
        elif [ ${#password} -lt 6 ]; then
            erreur "Le mot de passe doit faire au moins 6 caractères."
        else
            break
        fi
    done

    while true; do
        read -p "Quota disque (en Mo, ex: 500) : " quota
        valider_quota "$quota" && break
    done

    read -p "Créer une base de données ? (oui/non) : " create_db
    read -p "Accès SSH ? (oui/non) : " ssh_access

    echo -e "\n${C_BLUE}--- Création en cours... ---${C_RESET}"

    local shell="/usr/sbin/nologin"
    [ "$ssh_access" == "oui" ] && shell="/bin/bash"

    useradd -m -d "/home/$username" -s "$shell" "$username"
    echo "$username:$password" | chpasswd
    mkdir -p "/home/$username/www"

    cat <<EOF > "/home/$username/www/index.html"
<!DOCTYPE html>
<html lang="fr">
<head><meta charset="UTF-8"><title>Site de $username</title></head>
<body style="font-family:sans-serif;text-align:center;padding:50px;">
  <h1>🚀 Bienvenue sur le site de <strong>$username</strong> !</h1>
  <p>Hébergement OTA opérationnel.</p>
</body>
</html>
EOF

    chown -R "$username:$username" "/home/$username"
    chmod 755 "/home/$username"
    chmod 644 "/home/$username/www/index.html"

    (echo "$password"; echo "$password") | pure-pw useradd "$username" \
        -u "$username" -g "$username" \
        -d "/home/$username/www" -m > /dev/null 2>&1
    pure-pw usermod "$username" -N "$quota" -m > /dev/null 2>&1

    local CONF_FILE="/etc/apache2/sites-available/${username}.conf"
    cat <<EOF > "$CONF_FILE"
<VirtualHost *:80>
    ServerName ${username}.local
    ServerAlias www.${username}.local
    DocumentRoot /home/${username}/www

    <Directory "/home/${username}/www">
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/${username}_error.log
    CustomLog \${APACHE_LOG_DIR}/${username}_access.log combined
</VirtualHost>
EOF
    a2ensite "${username}.conf" > /dev/null 2>&1
    systemctl reload apache2 2>/dev/null

    if [ "$create_db" == "oui" ]; then
        local db_name="${username}_db"
        mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null
        mysql -u root -e "CREATE USER IF NOT EXISTS '${username}'@'localhost' IDENTIFIED BY '${password}';" 2>/dev/null
        mysql -u root -e "GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${username}'@'localhost';" 2>/dev/null
        mysql -u root -e "FLUSH PRIVILEGES;" 2>/dev/null
        echo -e "${C_GREEN}  → Base de données '${db_name}' créée.${C_RESET}"
    fi

    echo -e "\n${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "${C_BOLD}  Récapitulatif de l'hébergement créé${C_RESET}"
    echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "  Utilisateur  : ${C_BOLD}$username${C_RESET}"
    echo -e "  Dossier web  : /home/$username/www"
    echo -e "  URL locale   : http://${username}.local"
    echo -e "  FTP          : ✅ (quota: ${quota} Mo)"
    echo -e "  SSH          : $([ "$ssh_access" == "oui" ] && echo "✅ activé" || echo "❌ désactivé")"
    echo -e "  Base de données : $([ "$create_db" == "oui" ] && echo "✅ ${username}_db" || echo "❌ non")"
    echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"

    succes "Hébergement '$username' créé avec succès !"
    log "INFO" "Hébergement créé : $username"
    pause
}

# ==========================================
# 2. SUPPRIMER UN HÉBERGEMENT
# ==========================================
delete_user() {
    print_header "Supprimer un hébergement"
    list_ota_users

    cd /home/ || exit
    read -e -p "Nom de l'utilisateur à supprimer (TAB pour compléter) : " username
    cd - > /dev/null || exit

    if [[ -z "$username" ]]; then return; fi
    if ! id "$username" &>/dev/null; then erreur "L'utilisateur '$username' n'existe pas."; pause; return; fi
    if [ ! -d "/home/$username/www" ]; then erreur "'$username' n'est pas un utilisateur OTA."; pause; return; fi

    echo -e "\n${C_RED}${C_BOLD}ATTENTION : Cette action est irréversible !${C_RESET}"
    confirmer "Êtes-vous sûr de vouloir supprimer '$username' ?" || { info "Annulé."; pause; return; }
    confirmer "Dernière confirmation : supprimer définitivement '$username' ?" || { info "Annulé."; pause; return; }

    echo -e "\n${C_RED}Suppression en cours...${C_RESET}"

    a2dissite "${username}.conf" > /dev/null 2>&1
    rm -f "/etc/apache2/sites-available/${username}.conf"
    systemctl reload apache2 2>/dev/null

    pure-pw userdel "$username" -m > /dev/null 2>&1

    mysql -u root -e "DROP DATABASE IF EXISTS \`${username}_db\`;" 2>/dev/null
    mysql -u root -e "DROP USER IF EXISTS '${username}'@'localhost';" 2>/dev/null
    mysql -u root -e "FLUSH PRIVILEGES;" 2>/dev/null

    userdel -r "$username" 2>/dev/null

    succes "Hébergement '$username' supprimé totalement."
    log "INFO" "Hébergement supprimé : $username"
    pause
}

# ==========================================
# 3. MODIFIER UN HÉBERGEMENT
# ==========================================
modify_user() {
    print_header "Modifier un hébergement"
    list_ota_users

    cd /home/ || exit
    read -e -p "Utilisateur à modifier (TAB pour compléter) : " username
    cd - > /dev/null || exit

    if [[ -z "$username" ]]; then return; fi
    if ! id "$username" &>/dev/null || [ ! -d "/home/$username/www" ]; then erreur "Utilisateur invalide."; pause; return; fi

    echo -e "\n${C_BOLD}Que voulez-vous modifier pour '$username' ?${C_RESET}"
    echo "  1. Changer le quota disque (FTP)"
    echo "  2. Changer le mot de passe"
    echo "  3. Activer / Désactiver SSH"
    echo "  4. Gérer la base de données"
    echo "  5. Activer / Désactiver FTP"
    echo "  6. Retour"
    read -p "Choix : " mod_choice

    case $mod_choice in
        1)
            while true; do
                read -p "Nouveau quota (Mo) : " new_quota
                valider_quota "$new_quota" && break
            done
            pure-pw usermod "$username" -N "$new_quota" -m > /dev/null 2>&1
            succes "Quota mis à jour à ${new_quota} Mo." ;;
        2)
            while true; do
                read -s -p "Nouveau mot de passe : " new_pwd; echo ""
                read -s -p "Confirmez : " new_pwd2; echo ""
                if [ "$new_pwd" != "$new_pwd2" ]; then erreur "Mots de passe différents."; elif [ ${#new_pwd} -lt 6 ]; then erreur "Minimum 6 caractères."; else break; fi
            done
            echo "$username:$new_pwd" | chpasswd
            (echo "$new_pwd"; echo "$new_pwd") | pure-pw passwd "$username" -m > /dev/null 2>&1
            succes "Mot de passe mis à jour." ;;
        3)
            if [ "$(grep "^$username:" /etc/passwd | cut -d: -f7)" == "/bin/bash" ]; then
                usermod -s /usr/sbin/nologin "$username"
                succes "Accès SSH désactivé."
            else
                usermod -s /bin/bash "$username"
                succes "Accès SSH activé."
            fi ;;
        4)
            echo "  A) Créer la base"
            echo "  B) Supprimer la base"
            read -p "  Choix (A/B) : " db_choice
            if [ "${db_choice^^}" == "A" ]; then
                read -s -p "Mot de passe pour l'utilisateur DB '$username' : " db_pwd; echo ""
                mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`${username}_db\` CHARACTER SET utf8mb4;" 2>/dev/null
                mysql -u root -e "CREATE USER IF NOT EXISTS '${username}'@'localhost' IDENTIFIED BY '${db_pwd}';" 2>/dev/null
                mysql -u root -e "GRANT ALL PRIVILEGES ON \`${username}_db\`.* TO '${username}'@'localhost';" 2>/dev/null
                mysql -u root -e "FLUSH PRIVILEGES;" 2>/dev/null
                succes "Base créée."
            elif [ "${db_choice^^}" == "B" ]; then
                mysql -u root -e "DROP DATABASE IF EXISTS \`${username}_db\`; DROP USER IF EXISTS '${username}'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null
                succes "Base supprimée."
            fi ;;
        5)
            if pure-pw show "$username" &>/dev/null; then
                pure-pw userdel "$username" -m > /dev/null 2>&1; succes "FTP désactivé."
            else
                read -s -p "Mot de passe FTP : " ftp_pwd; echo ""
                (echo "$ftp_pwd"; echo "$ftp_pwd") | pure-pw useradd "$username" -u "$username" -g "$username" -d "/home/$username/www" -m > /dev/null 2>&1
                succes "FTP activé."
            fi ;;
        6) return ;;
        *) erreur "Choix invalide." ;;
    esac
    pause
}

# ==========================================
# 4. AFFICHER & INSTALLER WORDPRESS
# ==========================================
show_users() {
    print_header "Afficher les hébergements"

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
    read -e -p "Utilisateur pour voir ses détails (TAB, ou Entrée pour quitter) : " detail_user
    cd - > /dev/null || exit

    if [[ -z "$detail_user" ]]; then return; fi
    if ! id "$detail_user" &>/dev/null || [ ! -d "/home/$detail_user/www" ]; then erreur "Utilisateur introuvable."; pause; return; fi

    echo -e "\n${C_BOLD}Fichiers dans /home/$detail_user/www :${C_RESET}"
    ls -lh "/home/$detail_user/www" 2>/dev/null

    echo ""
    read -p "Installer WordPress pour '$detail_user' ? (oui/non) : " install_wp
    if [ "$install_wp" == "oui" ]; then
        install_wordpress "$detail_user"
    fi
    pause
}

install_wordpress() {
    local user="$1"
    local wp_dir="/home/$user/www"

    if [ -f "$wp_dir/wp-config.php" ]; then
        confirmer "WordPress est déjà installé. Écraser l'installation ?" || return
    fi

    local db_exists=$(mysql -u root -e "SHOW DATABASES LIKE '${user}_db';" 2>/dev/null | grep -v "Database")
    if [[ -z "$db_exists" ]]; then
        warning "WordPress nécessite une base de données."
        read -p "Créer la base '${user}_db' maintenant ? (oui/non) : " create_wp_db
        if [ "$create_wp_db" == "oui" ]; then
            mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`${user}_db\` CHARACTER SET utf8mb4;" 2>/dev/null
        else
            erreur "Annulation."; return
        fi
    fi

    read -s -p "Mot de passe de la base '${user}_db' : " wp_db_pwd; echo ""
    # FORCAGE DU MOT DE PASSE (Anti-bug Error establishing database connection)
    mysql -u root -e "CREATE USER IF NOT EXISTS '${user}'@'localhost' IDENTIFIED BY '${wp_db_pwd}';" 2>/dev/null
    mysql -u root -e "ALTER USER '${user}'@'localhost' IDENTIFIED BY '${wp_db_pwd}';" 2>/dev/null
    mysql -u root -e "GRANT ALL PRIVILEGES ON \`${user}_db\`.* TO '${user}'@'localhost';" 2>/dev/null
    mysql -u root -e "FLUSH PRIVILEGES;" 2>/dev/null

    echo -e "${C_YELLOW}Téléchargement de WordPress...${C_RESET}"
    wget -q https://wordpress.org/latest.zip -O /tmp/wp_${user}.zip
    unzip -q /tmp/wp_${user}.zip -d /tmp/wp_${user}/ > /dev/null
    cp -rf /tmp/wp_${user}/wordpress/* "$wp_dir/"
    chown -R "$user:$user" "$wp_dir"
    rm -rf /tmp/wp_${user} /tmp/wp_${user}.zip

    local wp_sample="$wp_dir/wp-config-sample.php"
    if [ -f "$wp_sample" ]; then
        cp "$wp_sample" "$wp_dir/wp-config.php"
        sed -i "s/database_name_here/${user}_db/" "$wp_dir/wp-config.php"
        sed -i "s/username_here/${user}/"         "$wp_dir/wp-config.php"
        sed -i "s/password_here/${wp_db_pwd}/"    "$wp_dir/wp-config.php"
        
        local wp_keys=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/ 2>/dev/null)
        if [[ -n "$wp_keys" ]]; then
            local tmp_conf="/tmp/wp_config_tmp_${user}.php"
            grep -v "define( 'AUTH_KEY\|define( 'SECURE_AUTH_KEY\|define( 'LOGGED_IN_KEY\|define( 'NONCE_KEY\|define( 'AUTH_SALT\|define( 'SECURE_AUTH_SALT\|define( 'LOGGED_IN_SALT\|define( 'NONCE_SALT" "$wp_dir/wp-config.php" > "$tmp_conf"
            sed -i "/\$table_prefix/i ${wp_keys}" "$tmp_conf" 2>/dev/null || true
            mv "$tmp_conf" "$wp_dir/wp-config.php"
        fi
        
        # CORRECTION PERMISSIONS APACHE
        chown "$user:$user" "$wp_dir/wp-config.php"
        chmod 644 "$wp_dir/wp-config.php"
    fi

    succes "WordPress installé pour '$user' ! Accès : http://${user}.local/wp-admin"
    log "INFO" "WordPress installé pour : $user"
}

# ==========================================
# 5. BASES DE DONNÉES
# ==========================================
manage_databases() {
    print_header "Gestion des bases de données"
    echo "  1. Lister les bases existantes"
    echo "  2. Retour"
    read -p "Choix : " db_choice
    if [ "$db_choice" == "1" ]; then
        echo -e "\n${C_BOLD}Bases existantes :${C_RESET}"
        mysql -u root -e "SHOW DATABASES;" 2>/dev/null | grep -v -E "^(Database|information_schema|performance_schema|mysql|sys)$" | while read db; do echo -e "  ${C_CYAN}► $db${C_RESET}"; done
    fi
    pause
}

# ==========================================
# 6. INFORMATIONS SERVEUR
# ==========================================
server_info() {
    print_header "Informations Serveur"
    echo -e "${C_BOLD}Espace disque (/) :${C_RESET} $(df -h / | awk 'NR==2 {print $3 " / " $2 " ("$5")"}')"
    echo -e "${C_BOLD}Mémoire RAM :${C_RESET} $(free -h | awk '/^Mem/ {print $3 " / " $2}')"
    echo -e "${C_BOLD}Uptime :${C_RESET} $(uptime -p 2>/dev/null)"
    
    if [ -f "$LOG_FILE" ]; then
        echo -e "\n${C_BOLD}Dernières actions :${C_RESET}"
        tail -5 "$LOG_FILE" | while read line; do echo -e "  ${C_MAGENTA}$line${C_RESET}"; done
    fi
    pause
}

# ==========================================
# MENU PRINCIPAL
# ==========================================
main_menu() {
    while true; do
        # Récupération des infos réseau dynamiques
        local SERVER_IP_CIDR=$(ip -4 addr show scope global | awk '$1=="inet" {print $2}' | head -n 1)
        local IP_ONLY=$(echo "$SERVER_IP_CIDR" | cut -d'/' -f1)
        local CIDR=$(echo "$SERVER_IP_CIDR" | cut -d'/' -f2)
        local GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n 1)

        clear
        echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
        echo -e "${C_BOLD}${C_YELLOW}           🚀 GESTION HÉBERGEMENT WEB - PROJET OTA v2.1 🚀          ${C_RESET}"
        echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
        echo -e "   🌐 IP : ${C_GREEN}${IP_ONLY} (/$CIDR)${C_RESET} | 🌍 Passerelle : ${C_GREEN}${GATEWAY}${C_RESET}"
        echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
        echo -e "   ${C_BOLD}0)${C_RESET} ${C_YELLOW}Installer les prérequis${C_RESET}"
        echo -e "   ${C_BOLD}1)${C_RESET} Créer un hébergement"
        echo -e "   ${C_BOLD}2)${C_RESET} Supprimer un hébergement"
        echo -e "   ${C_BOLD}3)${C_RESET} Modifier un hébergement"
        echo -e "   ${C_BOLD}4)${C_RESET} Afficher / Installer WordPress"
        echo -e "   ${C_BOLD}5)${C_RESET} Bases de données"
        echo -e "   ${C_BOLD}6)${C_RESET} Infos serveur"
        echo -e "   ${C_BOLD}7)${C_RESET} ${C_RED}Quitter${C_RESET}"
        echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"

        read -p "$(echo -e "${C_BOLD}👉 Ton choix [0-7] : ${C_RESET}")" OPTION

        case $OPTION in
            0) installer_preRequis ;;
            1) create_user ;;
            2) delete_user ;;
            3) modify_user ;;
            4) show_users ;;
            5) manage_databases ;;
            6) server_info ;;
            7) clear; echo -e "${C_GREEN}Fermeture du script OTA. À bientôt !${C_RESET}\n"; log "INFO" "Script fermé."; exit 0 ;;
            *) echo -e "\n${C_RED}Choix invalide.${C_RESET}"; sleep 1 ;;
        esac
    done
}

# Lancement
main_menu
