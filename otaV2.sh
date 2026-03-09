#!/bin/bash

# ==========================================
# PROJET OTA - SCRIPT MAÎTRE v2.0
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

# --- Système de logs ---
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$LOG_FILE"
}

# --- Validation du nom d'utilisateur ---
# Doit être alphanumérique, entre 3 et 32 caractères, sans espaces
valider_username() {
    local u="$1"
    if [[ ! "$u" =~ ^[a-z][a-z0-9_]{2,31}$ ]]; then
        erreur "Nom invalide. Utilise uniquement des minuscules/chiffres/underscore (3-32 car., commence par une lettre)."
        return 1
    fi
    return 0
}

# --- Validation du quota (doit être un entier positif) ---
valider_quota() {
    local q="$1"
    if [[ ! "$q" =~ ^[0-9]+$ ]] || [ "$q" -lt 1 ]; then
        erreur "Quota invalide. Entrez un nombre entier positif (en Mo)."
        return 1
    fi
    return 0
}

# --- Vérification qu'un service est actif ---
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

# --- Liste uniquement les clients OTA (ayant un dossier www) ---
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

# --- Demande une confirmation oui/non ---
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

    # Vérifier si déjà installé
    local deja_installe=true
    for pkg in apache2 mariadb-server pure-ftpd php; do
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
    apt install -y apache2 mariadb-server pure-ftpd php libapache2-mod-php wget unzip curl

    # Activation du module Apache rewrite (utile pour WordPress)
    a2enmod rewrite > /dev/null 2>&1

    echo -e "\n${C_YELLOW}Configuration de Pure-FTPd...${C_RESET}"
    groupadd -g 1001 ftpuser 2>/dev/null
    id -u ftpuser &>/dev/null || useradd -u 1001 -g 1001 -d /dev/null -s /bin/false ftpuser
    echo "yes"  > /etc/pure-ftpd/conf/CreateHomeDir
    echo "/etc/pure-ftpd/pureftpd.pdb" > /etc/pure-ftpd/conf/PureDB
    ln -sf /etc/pure-ftpd/conf/PureDB /etc/pure-ftpd/auth/50puredb
    touch /etc/pure-ftpd/pureftpd.passwd
    pure-pw mkdb > /dev/null 2>&1

    # Créer le fichier de log OTA
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"

    for service in apache2 mariadb pure-ftpd; do
        systemctl enable "$service" > /dev/null 2>&1
        systemctl restart "$service" 2>/dev/null
    done

    if systemctl is-active --quiet apache2 && systemctl is-active --quiet pure-ftpd; then
        succes "Pile Web et FTP installée et configurée avec succès !"
    else
        erreur "Un service n'a pas démarré correctement. Vérifiez avec 'systemctl status'."
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

    # --- Saisie et validation du nom ---
    while true; do
        read -p "Nom utilisateur (ex: client1) : " username
        valider_username "$username" || continue
        if id "$username" &>/dev/null; then
            erreur "L'utilisateur '$username' existe déjà."
            pause; return
        fi
        break
    done

    # --- Mot de passe avec confirmation ---
    while true; do
        read -s -p "Mot de passe : " password; echo ""
        read -s -p "Confirmez le mot de passe : " password2; echo ""
        if [ "$password" != "$password2" ]; then
            erreur "Les mots de passe ne correspondent pas. Réessayez."
        elif [ ${#password} -lt 6 ]; then
            erreur "Le mot de passe doit faire au moins 6 caractères."
        else
            break
        fi
    done

    # --- Quota avec validation ---
    while true; do
        read -p "Quota disque (en Mo, ex: 500) : " quota
        valider_quota "$quota" && break
    done

    read -p "Créer une base de données ? (oui/non) : " create_db
    read -p "Accès SSH ? (oui/non) : " ssh_access

    echo -e "\n${C_BLUE}--- Création en cours... ---${C_RESET}"

    # --- Utilisateur système ---
    local shell="/usr/sbin/nologin"
    [ "$ssh_access" == "oui" ] && shell="/bin/bash"

    useradd -m -d "/home/$username" -s "$shell" "$username"
    echo "$username:$password" | chpasswd
    mkdir -p "/home/$username/www"

    # Page d'accueil par défaut
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

    # --- Compte FTP ---
    (echo "$password"; echo "$password") | pure-pw useradd "$username" \
        -u "$username" -g "$username" \
        -d "/home/$username/www" -m > /dev/null 2>&1
    pure-pw usermod "$username" -N "$quota" -m > /dev/null 2>&1

    # --- VirtualHost Apache ---
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

    # --- Base de données optionnelle ---
    if [ "$create_db" == "oui" ]; then
        local db_name="${username}_db"
        mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null
        mysql -u root -e "CREATE USER IF NOT EXISTS '${username}'@'localhost' IDENTIFIED BY '${password}';" 2>/dev/null
        mysql -u root -e "GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${username}'@'localhost';" 2>/dev/null
        mysql -u root -e "FLUSH PRIVILEGES;" 2>/dev/null
        echo -e "${C_GREEN}  → Base de données '${db_name}' créée (utf8mb4).${C_RESET}"
    fi

    # --- Résumé ---
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
    log "INFO" "Hébergement créé : $username (quota: ${quota}Mo, SSH: $ssh_access, DB: $create_db)"
    pause
}

# ==========================================
# 2. SUPPRIMER UN HÉBERGEMENT
# ==========================================
delete_user() {
    print_header "Supprimer un hébergement"
    echo -e "Utilisateurs hébergés :"
    list_ota_users
    echo "------------------------------------------------"

    cd /home/ || exit
    read -e -p "Nom de l'utilisateur à supprimer (TAB pour compléter) : " username
    cd - > /dev/null || exit

    if [[ -z "$username" ]]; then return; fi
    if ! id "$username" &>/dev/null; then erreur "L'utilisateur '$username' n'existe pas."; pause; return; fi
    if [ ! -d "/home/$username/www" ]; then erreur "'$username' n'est pas un utilisateur OTA."; pause; return; fi

    # Double confirmation pour une suppression irréversible
    echo -e "\n${C_RED}${C_BOLD}ATTENTION : Cette action est irréversible !${C_RESET}"
    echo -e "Seront supprimés : utilisateur système, dossier /home/$username, compte FTP, base de données, VirtualHost.\n"
    confirmer "Êtes-vous sûr de vouloir supprimer '$username' ?" || { info "Suppression annulée."; pause; return; }
    confirmer "Dernière confirmation : supprimer définitivement '$username' ?" || { info "Suppression annulée."; pause; return; }

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
    echo -e "Utilisateurs hébergés :"
    list_ota_users
    echo "------------------------------------------------"

    cd /home/ || exit
    read -e -p "Nom de l'utilisateur (TAB pour compléter) : " username
    cd - > /dev/null || exit

    if [[ -z "$username" ]]; then return; fi
    if ! id "$username" &>/dev/null; then erreur "Utilisateur introuvable."; pause; return; fi
    if [ ! -d "/home/$username/www" ]; then erreur "'$username' n'est pas un utilisateur OTA."; pause; return; fi

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
                if [ "$new_pwd" != "$new_pwd2" ]; then
                    erreur "Mots de passe différents. Réessayez."
                elif [ ${#new_pwd} -lt 6 ]; then
                    erreur "Minimum 6 caractères."
                else
                    break
                fi
            done
            echo "$username:$new_pwd" | chpasswd
            (echo "$new_pwd"; echo "$new_pwd") | pure-pw passwd "$username" -m > /dev/null 2>&1
            succes "Mot de passe mis à jour (système + FTP)." ;;

        3)
            local current_shell
            current_shell=$(grep "^$username:" /etc/passwd | cut -d: -f7)
            if [ "$current_shell" == "/bin/bash" ]; then
                usermod -s /usr/sbin/nologin "$username"
                succes "Accès SSH désactivé pour '$username'."
            else
                usermod -s /bin/bash "$username"
                succes "Accès SSH activé pour '$username'."
            fi ;;

        4)
            echo "  A) Créer la base de données"
            echo "  B) Supprimer la base de données"
            read -p "  Choix (A/B) : " db_choice
            db_choice="${db_choice^^}" # majuscule
            if [ "$db_choice" == "A" ]; then
                if mysql -u root -e "SHOW DATABASES LIKE '${username}_db';" 2>/dev/null | grep -q "${username}_db"; then
                    erreur "La base '${username}_db' existe déjà."; pause; return
                fi
                read -s -p "Mot de passe pour l'utilisateur DB '$username' : " db_pwd; echo ""
                mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`${username}_db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null
                mysql -u root -e "CREATE USER IF NOT EXISTS '${username}'@'localhost' IDENTIFIED BY '${db_pwd}';" 2>/dev/null
                mysql -u root -e "GRANT ALL PRIVILEGES ON \`${username}_db\`.* TO '${username}'@'localhost';" 2>/dev/null
                mysql -u root -e "FLUSH PRIVILEGES;" 2>/dev/null
                succes "Base de données '${username}_db' créée."
            elif [ "$db_choice" == "B" ]; then
                confirmer "Supprimer définitivement la base '${username}_db' ?" || { info "Annulé."; pause; return; }
                mysql -u root -e "DROP DATABASE IF EXISTS \`${username}_db\`;" 2>/dev/null
                mysql -u root -e "DROP USER IF EXISTS '${username}'@'localhost';" 2>/dev/null
                mysql -u root -e "FLUSH PRIVILEGES;" 2>/dev/null
                succes "Base de données supprimée."
            else
                erreur "Choix invalide."
            fi ;;

        5)
            # Vérifier si l'utilisateur a un compte FTP
            if pure-pw show "$username" &>/dev/null; then
                confirmer "Désactiver le compte FTP de '$username' ?" && {
                    pure-pw userdel "$username" -m > /dev/null 2>&1
                    succes "Compte FTP supprimé pour '$username'."
                }
            else
                warning "Aucun compte FTP pour '$username'. Création..."
                read -s -p "Mot de passe FTP : " ftp_pwd; echo ""
                (echo "$ftp_pwd"; echo "$ftp_pwd") | pure-pw useradd "$username" \
                    -u "$username" -g "$username" \
                    -d "/home/$username/www" -m > /dev/null 2>&1
                succes "Compte FTP créé pour '$username'."
            fi ;;

        6) return ;;
        *) erreur "Choix invalide." ;;
    esac
    pause
}

# ==========================================
# 4. AFFICHER HÉBERGEMENTS & FICHIERS WEB
# ==========================================
show_users() {
    print_header "Afficher les hébergements & Fichiers Web"

    local found=false
    printf "%-20s %-15s %-15s %-10s %-10s\n" "UTILISATEUR" "ESPACE UTILISÉ" "QUOTA FTP" "SSH" "DB"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    for user_home in /home/*; do
        if [ -d "$user_home/www" ]; then
            found=true
            local uname
            uname=$(basename "$user_home")
            local usage
            usage=$(du -sh "$user_home" 2>/dev/null | cut -f1)
            local quota_ftp
            quota_ftp=$(pure-pw show "$uname" 2>/dev/null | grep -i "Disk quota" | awk '{print $NF}' | sed 's/[^0-9]//g')
            [ -z "$quota_ftp" ] && quota_ftp="N/A" || quota_ftp="${quota_ftp} Mo"
            local shell_type
            shell_type=$(grep "^$uname:" /etc/passwd | cut -d: -f7)
            [ "$shell_type" == "/bin/bash" ] && ssh_status="✅" || ssh_status="❌"
            local db_status="❌"
            mysql -u root -e "SHOW DATABASES LIKE '${uname}_db';" 2>/dev/null | grep -q "${uname}_db" && db_status="✅"
            printf "%-20s %-15s %-15s %-10s %-10s\n" "$uname" "$usage" "$quota_ftp" "$ssh_status" "$db_status"
        fi
    done

    if ! $found; then
        echo -e "  ${C_YELLOW}Aucun utilisateur hébergé.${C_RESET}"
        pause; return
    fi

    echo ""
    cd /home/ || exit
    read -e -p "Utilisateur pour voir ses détails (TAB, ou Entrée pour quitter) : " detail_user
    cd - > /dev/null || exit

    if [[ -z "$detail_user" ]]; then pause; return; fi
    if ! id "$detail_user" &>/dev/null || [ ! -d "/home/$detail_user/www" ]; then
        erreur "Utilisateur OTA introuvable."
        pause; return
    fi

    echo -e "\n${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "${C_BOLD}  Détails : $detail_user${C_RESET}"
    echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "  ${C_BOLD}Dossier web  :${C_RESET} /home/$detail_user/www"
    echo -e "  ${C_BOLD}Espace utilisé :${C_RESET} $(du -sh /home/$detail_user 2>/dev/null | cut -f1)"
    echo -e "  ${C_BOLD}Quota FTP    :${C_RESET} $(pure-pw show "$detail_user" 2>/dev/null | grep -i "Disk quota" | awk '{print $NF}') Mo"
    echo -e "  ${C_BOLD}Shell/SSH    :${C_RESET} $(grep "^$detail_user:" /etc/passwd | cut -d: -f7)"

    local ftp_status="❌ Inactif"
    pure-pw show "$detail_user" &>/dev/null && ftp_status="✅ Actif"
    echo -e "  ${C_BOLD}FTP          :${C_RESET} $ftp_status"

    local db_ex
    db_ex=$(mysql -u root -e "SHOW DATABASES LIKE '${detail_user}_db';" 2>/dev/null | grep -v "Database")
    if [[ -n "$db_ex" ]]; then
        echo -e "  ${C_BOLD}Base de données :${C_RESET} ✅ ${detail_user}_db"
    else
        echo -e "  ${C_BOLD}Base de données :${C_RESET} ❌ Aucune"
    fi

    echo -e "\n${C_BOLD}Fichiers dans /home/$detail_user/www :${C_RESET}"
    ls -lh "/home/$detail_user/www" 2>/dev/null

    echo ""
    read -p "Installer WordPress pour '$detail_user' ? (oui/non) : " install_wp
    if [ "$install_wp" == "oui" ]; then
        install_wordpress "$detail_user"
    fi
    pause
}

# ==========================================
# INSTALLATION WORDPRESS (sous-fonction)
# ==========================================
install_wordpress() {
    local user="$1"
    local wp_dir="/home/$user/www"

    # Vérifier si déjà installé
    if [ -f "$wp_dir/wp-config.php" ] || [ -f "$wp_dir/wp-login.php" ]; then
        warning "WordPress semble déjà installé pour '$user'."
        confirmer "Écraser l'installation existante ?" || return
    fi

    # Vérifier si une DB existe
    local db_exists
    db_exists=$(mysql -u root -e "SHOW DATABASES LIKE '${user}_db';" 2>/dev/null | grep -v "Database")
    if [[ -z "$db_exists" ]]; then
        warning "Aucune base de données pour '$user'. WordPress nécessite une DB."
        read -p "Créer la base '${user}_db' maintenant ? (oui/non) : " create_wp_db
        if [ "$create_wp_db" == "oui" ]; then
            read -s -p "Mot de passe DB pour '$user' : " wp_db_pwd; echo ""
            mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`${user}_db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null
            mysql -u root -e "CREATE USER IF NOT EXISTS '${user}'@'localhost' IDENTIFIED BY '${wp_db_pwd}';" 2>/dev/null
            mysql -u root -e "GRANT ALL PRIVILEGES ON \`${user}_db\`.* TO '${user}'@'localhost';" 2>/dev/null
            mysql -u root -e "FLUSH PRIVILEGES;" 2>/dev/null
        else
            erreur "Installation WordPress annulée (pas de base de données)."
            return
        fi
    fi

    read -s -p "Mot de passe de la base '${user}_db' : " wp_db_pwd; echo ""

    echo -e "${C_YELLOW}Téléchargement de WordPress...${C_RESET}"
    if ! wget -q https://wordpress.org/latest.zip -O /tmp/wp_${user}.zip; then
        erreur "Téléchargement échoué. Vérifiez la connexion internet."
        return
    fi

    echo -e "${C_YELLOW}Extraction...${C_RESET}"
    unzip -q /tmp/wp_${user}.zip -d /tmp/wp_${user}/ > /dev/null
    cp -rf /tmp/wp_${user}/wordpress/* "$wp_dir/"
    chown -R "$user:$user" "$wp_dir"
    rm -rf /tmp/wp_${user} /tmp/wp_${user}.zip

    # Générer le wp-config.php pré-rempli
    local wp_sample="$wp_dir/wp-config-sample.php"
    if [ -f "$wp_sample" ]; then
        cp "$wp_sample" "$wp_dir/wp-config.php"
        # Remplacer les placeholders de base de données
        sed -i "s/database_name_here/${user}_db/" "$wp_dir/wp-config.php"
        sed -i "s/username_here/${user}/"         "$wp_dir/wp-config.php"
        sed -i "s/password_here/${wp_db_pwd}/"    "$wp_dir/wp-config.php"
        sed -i "s/localhost/localhost/"            "$wp_dir/wp-config.php"

        # Générer des clés de sécurité uniques
        local wp_keys
        wp_keys=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/ 2>/dev/null)
        if [[ -n "$wp_keys" ]]; then
            # Supprimer les lignes de clés génériques et insérer les vraies
            local tmp_conf="/tmp/wp_config_tmp_${user}.php"
            grep -v "define( 'AUTH_KEY\|define( 'SECURE_AUTH_KEY\|define( 'LOGGED_IN_KEY\|define( 'NONCE_KEY\|define( 'AUTH_SALT\|define( 'SECURE_AUTH_SALT\|define( 'LOGGED_IN_SALT\|define( 'NONCE_SALT" "$wp_dir/wp-config.php" > "$tmp_conf"
            # Insérer les nouvelles clés avant la ligne table_prefix
            sed -i "/\$table_prefix/i ${wp_keys}" "$tmp_conf" 2>/dev/null || true
            mv "$tmp_conf" "$wp_dir/wp-config.php"
        fi
        chown "$user:$user" "$wp_dir/wp-config.php"
        chmod 640 "$wp_dir/wp-config.php"
    fi

    succes "WordPress installé pour '$user' ! Accès : http://${user}.local/wp-admin"
    log "INFO" "WordPress installé pour : $user"
}

# ==========================================
# 5. GESTION GLOBALE DES BASES DE DONNÉES
# ==========================================
manage_databases() {
    print_header "Gestion globale des bases de données"
    verifier_service mariadb || { pause; return; }

    echo "  1. Créer une base de données"
    echo "  2. Supprimer une base de données"
    echo "  3. Lister les bases existantes"
    echo "  4. Retour"
    read -p "Choix : " db_choice

    case $db_choice in
        1)
            read -p "Nom de la base : " new_db
            if [[ -z "$new_db" ]]; then erreur "Nom vide."; pause; return; fi
            read -p "Créer un utilisateur DB pour cette base ? (oui/non) : " create_user_db
            mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`${new_db}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null
            if [ "$create_user_db" == "oui" ]; then
                read -p "Nom de l'utilisateur DB : " db_user
                read -s -p "Mot de passe : " db_pass; echo ""
                mysql -u root -e "CREATE USER IF NOT EXISTS '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';" 2>/dev/null
                mysql -u root -e "GRANT ALL PRIVILEGES ON \`${new_db}\`.* TO '${db_user}'@'localhost';" 2>/dev/null
                mysql -u root -e "FLUSH PRIVILEGES;" 2>/dev/null
                succes "Base '$new_db' et utilisateur '$db_user' créés."
            else
                succes "Base '$new_db' créée."
            fi ;;
        2)
            echo -e "\n${C_BOLD}Bases existantes :${C_RESET}"
            mysql -u root -e "SHOW DATABASES;" 2>/dev/null | grep -v -E "^(Database|information_schema|performance_schema|mysql|sys)$"
            echo ""
            read -p "Nom de la base à supprimer : " db_drop
            if [[ -z "$db_drop" ]]; then erreur "Nom vide."; pause; return; fi
            confirmer "Supprimer définitivement la base '$db_drop' ?" || { info "Annulé."; pause; return; }
            mysql -u root -e "DROP DATABASE IF EXISTS \`${db_drop}\`;" 2>/dev/null
            succes "Base '$db_drop' supprimée." ;;
        3)
            echo -e "\n${C_BOLD}Bases de données (hors système) :${C_RESET}"
            mysql -u root -e "SHOW DATABASES;" 2>/dev/null | grep -v -E "^(Database|information_schema|performance_schema|mysql|sys)$" \
                | while read db; do echo -e "  ${C_CYAN}► $db${C_RESET}"; done ;;
        4) return ;;
        *) erreur "Choix invalide." ;;
    esac
    pause
}

# ==========================================
# 6. INFORMATIONS SERVEUR
# ==========================================
server_info() {
    print_header "Informations Serveur"

    # --- État des services ---
    echo -e "${C_BOLD}État des services :${C_RESET}"
    for service in apache2 mariadb pure-ftpd; do
        if systemctl is-active --quiet "$service"; then
            echo -e "  ${C_GREEN}✅ $service${C_RESET} : actif"
        else
            echo -e "  ${C_RED}❌ $service${C_RESET} : INACTIF"
        fi
    done

    # --- Espace disque ---
    echo -e "\n${C_BOLD}Espace disque (/) :${C_RESET}"
    df -h / | awk 'NR>1 {printf "  Utilisé: %s / Total: %s (%s)\n", $3, $2, $5}'

    # --- Mémoire RAM ---
    echo -e "\n${C_BOLD}Mémoire RAM :${C_RESET}"
    free -h | awk '/^Mem/ {printf "  Utilisée: %s / Total: %s\n", $3, $2}'

    # --- Uptime ---
    echo -e "\n${C_BOLD}Uptime :${C_RESET} $(uptime -p 2>/dev/null || uptime)"

    # --- Utilisateurs OTA ---
    echo -e "\n${C_BOLD}Utilisateurs hébergés :${C_RESET}"
    local count=0
    for u in /home/*; do
        [ -d "$u/www" ] && ((count++))
    done
    echo -e "  Total : ${C_CYAN}$count utilisateur(s)${C_RESET}"

    # --- VirtualHosts ---
    echo -e "\n${C_BOLD}Sites Apache actifs :${C_RESET}"
    local vh_count=0
    for f in /etc/apache2/sites-enabled/*.conf; do
        [ -f "$f" ] && echo -e "  ${C_CYAN}► $(basename "$f" .conf)${C_RESET}" && ((vh_count++))
    done
    [ "$vh_count" -eq 0 ] && echo -e "  ${C_YELLOW}Aucun VirtualHost actif.${C_RESET}"

    # --- Comptes FTP ---
    echo -e "\n${C_BOLD}Comptes FTP :${C_RESET}"
    local ftp_count
    ftp_count=$(pure-pw list 2>/dev/null | wc -l)
    echo -e "  Total : ${C_CYAN}$ftp_count compte(s)${C_RESET}"

    # --- Dernières entrées du log OTA ---
    if [ -f "$LOG_FILE" ]; then
        echo -e "\n${C_BOLD}Dernières actions (log OTA) :${C_RESET}"
        tail -5 "$LOG_FILE" | while read line; do
            echo -e "  ${C_MAGENTA}$line${C_RESET}"
        done
    fi

    pause
}

# ==========================================
# MENU PRINCIPAL
# ==========================================
main_menu() {
    while true; do
        clear
        echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
        echo -e "${C_BOLD}${C_YELLOW}           🚀 GESTION HÉBERGEMENT WEB - PROJET OTA v2.0 🚀          ${C_RESET}"
        echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
        echo -e "   ${C_BOLD}0)${C_RESET} ${C_YELLOW}Installer les prérequis${C_RESET} ${C_YELLOW}(À faire une fois)${C_RESET}"
        echo -e "   ${C_BOLD}1)${C_RESET} Créer un hébergement"
        echo -e "   ${C_BOLD}2)${C_RESET} Supprimer un hébergement"
        echo -e "   ${C_BOLD}3)${C_RESET} Modifier un hébergement"
        echo -e "   ${C_BOLD}4)${C_RESET} Afficher les hébergements (fichiers web, WordPress)"
        echo -e "   ${C_BOLD}5)${C_RESET} Gestion des bases de données"
        echo -e "   ${C_BOLD}6)${C_RESET} Informations serveur"
        echo -e "   ${C_BOLD}7)${C_RESET} ${C_RED}Quitter${C_RESET}"
        echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
        echo -e "  📋 Log : $LOG_FILE"
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
