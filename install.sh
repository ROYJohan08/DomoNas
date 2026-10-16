#!/bin/sh
#VERSION 202610161410
set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "Droits insuffisants : exécuter ce script en tant que root." >&2
    exit 1
fi
DEBUG=1
BASE_DIR="/etc/DomoNas"
LOG_DIR="$BASE_DIR/Logs"
TEM_DIR="$BASE_DIR/Temp"
SOF_DIR="$BASE_DIR/Softs"
CRE_DIR="$BASE_DIR/Credentials"

log() {
    mkdir -p "$LOG_DIR"
    if [ "$DEBUG" = "1" ]; then
        echo "[$1] - $(date +'%Y-%m-%d %H:%M:%S') - $2"
    fi
    echo "[$1] - $(date +'%Y-%m-%d %H:%M:%S') - $2" >> "${LOG_DIR}/$(date +'%Y%m%d')-INSTALL.log"
}

log "[*]" "Mise a jours du systeme."
apt-get update -y > /dev/null
apt-get upgrade -y > /dev/null
apt-get autoremove -y --purge > /dev/null
apt-get autoclean -y > /dev/null
log "[+]" "Mise a jours du systeme terminée."

mkdir -p "$SOF_DIR" "$TEM_DIR"
wget -q -O "$TEM_DIR/install.sh" https://raw.githubusercontent.com/ROYJohan08/DomoNas/refs/heads/main/install.sh > /dev/null
if [ ! -f "$SOF_DIR/install.sh" ] || [ "$TEM_DIR/install.sh" -nt "$SOF_DIR/install.sh" ]; then
    cp "$TEM_DIR/install.sh" "$SOF_DIR/install.sh"
    log "[!]" "install.sh a été mis à jour dans $SOF_DIR."
else
    log "[!]" "Le fichier dans $SOF_DIR est déjà à jour ou plus récent."
fi
rm -f "$TEM_DIR/install.sh"

log "[*]" "Vérification de docker."
if ! command -v docker &> /dev/null; then
    log "[!]" "Docker n'est pas installé. Lancement de l'installation..."
    apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sourcesaclist.d/docker.list > /dev/null
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    if [ $? -eq 0 ]; then
        log "[+]" "Docker installé avec succès."
    else
        log "[-]" "Échec lors de l'installation de Docker."
        exit 1
    fi
fi

PACKAGES="cron watchdog glances smartmontools ddclient rsync cockpit git wget fail2ban iotop docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin webp imagemagick ffmpeg unzip p7zip-full unrar net-tools iperf samba python3 python3-pip python3-dev python3-psutil lm-sensors"
for pkg in $PACKAGES; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        log "[*]" "Paquet '$pkg' déjà installé."
    else
        log "[!]" "Paquet '$pkg' absent. Installation en cours..."
        if apt-get install -y "$pkg" > /dev/null; then
            log "[+]" "Paquet '$pkg' installé avec succès."
        else
            log "[-]" "Échec lors de l'installation du paquet '$pkg'."
            exit 1
        fi
    fi
done

mkdir -p "$CRE_DIR"
TARGET_CRED="$CRE_DIR/credentials.env"
if [ ! -f "$TARGET_CRED" ]; then
    log "[*]" "Recherche d'un fichier 'credentials.env' existant sur le système..."
    FOUND_CRED=""
    FOUND_CRED=$(find / -name "credentials.env" ! -path "$TARGET_CRED" ! -path "/proc/*" ! -path "/sys/*" ! -path "/dev/*" 2>/dev/null | head -n 1)
    if [ -n "$FOUND_CRED" ]; then
        log "[*]" "Fichier 'credentials.env' trouvé : $FOUND_CRED"
        if [ "$FOUND_CRED" -nt "$TARGET_CRED" ]; then
            cp "$FOUND_CRED" "$TARGET_CRED"
            log "[+]" "Le fichier trouvé est plus récent. Copie effectuée dans $TARGET_CRED."
        else
            cp "$FOUND_CRED" "$TARGET_CRED"
            log "[+]" "Copie effectuée depuis $FOUND_CRED vers $TARGET_CRED."
        fi
    else
        log "[!]" "Aucun fichier 'credentials.env' trouvé sur le système."
        log "[*]" "Téléchargement du modèle depuis GitHub..."
        if curl -fsSL "https://raw.githubusercontent.com/ROYJohan08/DomoNas/refs/heads/main/credentials.env" -o "$TARGET_CRED"; then
            log "[+]" "Modèle téléchargé avec succès dans $TARGET_CRED."
            if [ -f "$TARGET_CRED" ]; then
                log "[*]" "Vérification et configuration interactive des variables de credentials..."
                echo "------------------------------------------------------------------"
                echo "Veuillez renseigner les valeurs pour chaque variable (Appuyez sur Entrée pour garder la valeur actuelle/par défaut) :"
                echo "------------------------------------------------------------------"
                TEMP_CRED="${TARGET_CRED}.tmp"
                > "$TEMP_CRED"
                while IFS= read -r line || [ -n "$line" ]; do
                    if echo "$line" | grep -qE '^[[:space:]]*(#|$)'; then
                        echo "$line" >> "$TEMP_CRED"
                        continue
                    fi
                    key=$(echo "$line" | cut -d '=' -f 1)
                    current_val=$(echo "$line" | cut -d '=' -f 2-)
                    printf "%s [%s] : " "$key" "$current_val" > /dev/tty
                    read -r new_val < /dev/tty
                    if [ -z "$new_val" ]; then
                        echo "$line" >> "$TEMP_CRED"
                    else
                        echo "$key=$new_val" >> "$TEMP_CRED"
                    fi
                done < "$TARGET_CRED"
                mv "$TEMP_CRED" "$TARGET_CRED"
                chmod 600 "$TARGET_CRED"
                log "[+]" "Configuration des credentials enregistrée et sécurisée dans $TARGET_CRED."
            fi
        else
            log "[-]" "Échec du téléchargement du modèle credentials.env depuis GitHub."
            exit 1
        fi
    fi
else
    log "[*]" "Le fichier '$TARGET_CRED' existe déjà. Étape de recherche/téléchargement ignorée."
fi

set -a
. "$TARGET_CRED"
set +a

log "[*]" "Début de la configuration des servicesac.."
log "[*]" "Configuration de Samba avec vos partagesac.."
[ ! -f /etc/samba/smb.conf.bak ] && cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
cat << 'EOF' > /etc/samba/smb.conf
[global]
    workgroup = WORKGROUP
    server string = %h DomoNas
    server role = standalone server
    hosts allow = 192.168.1. 127.
    hosts deny = ALL
    map to guest = bad user
    usershare allow guests = yes
    obey pam restrictions = yes
    unix password sync = yes
    passwd program = /usr/bin/passwd %u
    passwd chat = *Enter\snew\s*\spassword:* %n\n *Retype\snew\s*\spassword:* %n\n *password\supdated\ssuccessfully* .
    pam password change = yes

[Root]
    path = /
    guest ok = yes
    writable = yes
    browsable = yes
    force user = royjohan

[Media]
    path = /media
    guest ok = yes
    writable = yes
    browsable = yes
    force user = royjohan

[Series01]
    path = /media/Series01
    guest ok = yes
    writable = yes
    browsable = yes
    force user = royjohan

[Series02]
    path = /media/Series02
    guest ok = yes
    writable = yes
    browsable = yes
    force user = royjohan

[Series03]
    path = /media/Series03
    guest ok = yes
    writable = yes
    browsable = yes
    force user = royjohan

[Films01]
    path = /media/Films01
    guest ok = yes
    writable = yes
    browsable = yes
    force user = royjohan

[Films02]
    path = /media/Films02
    guest ok = yes
    writable = yes
    browsable = yes
    force user = royjohan

[DownBox]
    path = /media/Runable/DownBox/
    guest ok = yes
    writable = yes
    browsable = yes
    force user = royjohan

[Docs01]
    path = /media/Docs01
    guest ok = yes 
    writable = yes
    browsable = yes
    force user = royjohan

[octoprint]
    path = /media/Runable/Docker/Octoprint
    guest ok = yes
    writable = yes
    browsable = yes
    force user = royjohan
EOF
chown -R royjohan:royjohan /media 2>/dev/null || true
systemctl restart smbd nmbd >/dev/null
systemctl enable smbd nmbd >/dev/null
log "[+]" "Samba configuré et redémarré."

log "[*]" "Configuration du port Cockpit ($PORT_COCKPIT)..."
PORT_COCKPIT="${PORT_COCKPIT:-9090}"
mkdir -p /etc/systemd/system/cockpit.socket.d
cat << EOF > /etc/systemd/system/cockpit.socket.d/listen.conf
[Socket]
ListenStream=
ListenStream=$PORT_COCKPIT
EOF
systemctl daemon-reload
systemctl restart cockpit.socket
systemctl enable --now cockpit.socket
log "[+]" "Cockpit configuré sur le port $PORT_COCKPIT."

log "[*]" "Configuration de DDClient..."
USERNAME_DYDNS="${USERNAME_DYDNS:-royjohan.fr-dsm}"
PASSWORD_DYDNS="${PASSWORD_DYDNS:-123456789}"
DOMAIL_DYDNS="${DOMAIL_DYDNS:-dsm.royjohan.fr}"
cat << EOF > /etc/ddclient.conf
protocol=ovh
use=web, web=ipify-ipv4
login=$USERNAME_DYDNS
password=$PASSWORD_DYDNS
$DOMAIL_DYDNS
EOF
systemctl enable ddclient >/dev/null
systemctl restart ddclient >/dev/null
log "[+]" "DDClient configuré pour le domaine $DOMAIL_DYDNS."

log "[*]" "Configuration de Fail2ban..."
cat << 'EOF' > /etc/fail2ban/jail.local
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port    = ssh
logpath = %(sshd_log)s
backend = %(sshd_backend)s
EOF
systemctl restart fail2ban >/dev/null
systemctl enable fail2ban >/dev/null
log "[+]" "Fail2ban configuré et activé."

log "[*]" "Configuration de Smartmontools..."
sed -i 's/#start_due_daemon=yes/start_due_daemon=yes/' /etc/default/smartmontools
cat << 'EOF' > /etc/smartd.conf
DEVICESCAN -H -m root -M exec /usr/share/smartmontools/smartd-runner
EOF
systemctl enable smartmontools >/dev/null
systemctl restart smartmontools >/dev/null
log "[+]" "Smartmontools activé."

log "[*]" "Configuration des capteurs de température..."
sensors-detect --auto > /dev/null 2>&1 || true
log "[+]" "Capteurs initialisés."

log "[*]" "Création du script de réparation réseau pour Watchdog..."
mkdir -p "$SOF_DIR"
cat << 'EOF' > "$SOF_DIR/fix-network.sh"
#!/bin/bash
LOG_FILE="/var/log/network-repair.log"
echo "$(date) - [WATCHDOG] Perte de connexion détectée. Redémarrage de systemd-networkd..." >> "$LOG_FILE"
systemctl restart systemd-networkd
sleep 5
if ping -c 1 -W 2 192.168.1.1 > /dev/null 2>&1; then
    echo "$(date) - [WATCHDOG] Connexion réseau rétablie avec succès." >> "$LOG_FILE"
    exit 0
else
    echo "$(date) - [WATCHDOG] Échec du rétablissement. Le serveur va rebooter." >> "$LOG_FILE"
    exit 1
fi
EOF
chmod +x "$SOF_DIR/fix-network.sh"
log "[+]" "Script fix-network.sh créé et rendu exécutable dans $SOF_DIR."

log "[*]" "Mise à jour de la configuration de Watchdog..."
cat << EOF > /etc/watchdog.conf
watchdog-device = /dev/watchdog
max-load-1 = 24
min-memory = 25000
ping = 192.168.1.1
ping-retry = 3
repair-binary = $SOF_DIR/fix-network.sh
repair-timeout = 30
EOF
modprobe softdog 2>/dev/null || true
echo "softdog" > /etc/modules-load.d/softdog.conf
systemctl enable watchdog >/dev/null
systemctl restart watchdog >/dev/null
log "[+]" "Watchdog configuré avec le script pointant vers $SOF_DIR/fix-network.sh."
log "[*]" "Configuration du service systemd pour Glancesac.."

cat << 'EOF' > /etc/systemd/system/glancesacservice
[Unit]
Description=Glances (Web Server Mode)
After=network.target

[Service]
ExecStart=/usr/bin/glances -w
Restart=on-abort
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload >/dev/null
systemctl enable glancesacservice >/dev/null
systemctl restart glancesacservice >/dev/null
log "[+]" "Glances configuré et démarré en mode Web (accessible par défaut sur le port 61208)."
log "[*]" "Recherche et montage automatique des disques branchés..."
lsblk -rno NAME,MOUNTPOINT,LABEL,TYPE,UUID | while read -r name mountpoint label type uuid; do
    if [ "$type" = "part" ] && [ -z "$mountpoint" ]; then
        if [ -n "$label" ] && [ "$label" != "null" ]; then
            disk_name="$label"
        else
            disk_name="$name"
        fi
        target_dir="/media/$disk_name"
        log "[*]" "Détection du disque /dev/$name (Label: ${label:-Aucun}). Montage dans $target_dir..."
        mkdir -p "$target_dir"
        if mount "/dev/$name" "$target_dir"; then
            log "[+]" "Disque /dev/$name monté avec succès sur $target_dir."
            if [ -n "$uuid" ] && ! grep -q "$uuid" /etc/fstab; then
                # Détection automatique du type de système de fichiers (ext4, ntfs, exfat, vfat, etc.)
                fstype=$(blkid -s TYPE -o value "/dev/$name")
                if [ -n "$fstype" ]; then
                    echo "UUID=$uuid $target_dir $fstype defaults,nofail 0 2" >> /etc/fstab
                    log "[+]" "Entrée fstab ajoutée pour le disque $disk_name (UUID: $uuid)."
                fi
            fi
        else
            log "[-]" "Échec du montage du disque /dev/$name sur $target_dir."
        fi
    fi
done
chown -R royjohan:royjohan /media 2>/dev/null || true
log "[+]" "Montage des disques externes terminé."
log "[*]" "Configuration des tâches cron..."
CRON_TMP="/tmp/root_crontab_doponas"
crontab -l 2>/dev/null > "$CRON_TMP" || true
add_cron_job() {
    cron_line="$1"
    if ! grep -Fqx "$cron_line" "$CRON_TMP"; then
        echo "$cron_line" >> "$CRON_TMP"
        log "[+]" "Ajout de la tâche cron : $cron_line"
    else
        log "[*]" "La tâche cron existe déjà : $cron_line"
    fi
}
add_cron_job "@reboot glances -w &"
add_cron_job "@reboot iperf -s"
add_cron_job "@reboot mount -a --onlyonce"
add_cron_job "50 6 * * * $SOF_DIR/archive.sh &"
crontab "$CRON_TMP"
rm -f "$CRON_TMP"
log "[+]" "Gestion des tâches cron configurée avec succès."

log "[*]" "Création de la commande globale 'lamp'..."
cat << 'EOF' > /usr/local/bin/lamp
#!/bin/sh
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a
PATH_LAMP="${PATH_LAMP:-/media/Runable/Docker/Lamp}"
PORT_LAMP="${PORT_LAMP:-81}"
mkdir -p "$PATH_LAMP"
case "$1" in
    create)
        docker rm -f lamp 2>/dev/null || true
        docker pull php:8.2-apache || echo ""
        docker run -d \
            --name lamp \
            --restart=unless-stopped \
            -e TZ=CET \
            -v "$PATH_LAMP:/var/www/html" \
            -v /media/Docs01/Maps/20260726_Europa.pmtiles:/var/www/html/europe.pmtiles:ro \
            -v /media:/media \
            -p "$PORT_LAMP:80" \
            -p 3306:3306 \
            php:8.2-apache
        ;;
    update)
        docker rm -f lamp 2>/dev/null || true
        docker pull php:8.2-apache || echo ""
        docker run -d \
            --name lamp \
            --restart=unless-stopped \
            -e TZ=CET \
            -v "$PATH_LAMP:/var/www/html" \
            -v /media/Docs01/Maps/20260726_Europa.pmtiles:/var/www/html/europe.pmtiles:ro \
            -v /media:/media \
            -p "$PORT_LAMP:80" \
            -p 3306:3306 \
            php:8.2-apache
        ;;
    start)
        docker start lamp
        ;;
    stop)
        docker stop lamp
        ;;
    restart)
        docker restart lamp
        ;;
    *)
        echo "Usage: lamp {create|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/lamp
log "[+]" "Commande 'lamp' créée avec succès. Vous pouvez taper 'lamp create', 'lamp start', etc. de n'importe où."
log "[*]" "Création de la commande globale 'homeassistant'..."
cat << 'EOF' > /usr/local/bin/homeassistant
#!/bin/sh
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a
PATH_HOMEASSISTANT="${PATH_HOMEASSISTANT:-/etc/DomoNas/Docker/HomeAssistant}"
PORT_HOMEASSISTANT="${PORT_HOMEASSISTANT:-1000}"
mkdir -p "$PATH_HOMEASSISTANT"
case "$1" in
    create)
        docker rm -f homeassistant 2>/dev/null || true
        docker pull homeassistant/home-assistant:latest || echo ""
        docker run -d \
            --name homeassistant \
            --privileged \
            --restart=unless-stopped \
            --network=host \
            -e TZ=CET \
            -v "$PATH_HOMEASSISTANT:/config" \
            --device /dev/dri:/dev/dri \
            -v /etc/localtime:/etc/localtime:ro \
            -p "$PORT_HOMEASSISTANT:8123" \
            homeassistant/home-assistant:latest
        ;;
    update)
        docker rm -f homeassistant 2>/dev/null || true
        docker pull homeassistant/home-assistant:latest || echo ""
        docker run -d \
            --name homeassistant \
            --privileged \
            --restart=unless-stopped \
            --network=host \
            -e TZ=CET \
            -v "$PATH_HOMEASSISTANT:/config" \
            --device /dev/dri:/dev/dri \
            -v /etc/localtime:/etc/localtime:ro \
            -p "$PORT_HOMEASSISTANT:8123" \
            homeassistant/home-assistant:latest
        ;;
    start)
        docker start homeassistant
        ;;
    stop)
        docker stop homeassistant
        ;;
    restart)
        docker restart homeassistant
        ;;
    *)
        echo "Usage: homeassistant {create|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/homeassistant
log "[+]" "Commande 'homeassistant' créée avec succès (utilisable via 'homeassistant create', etc.)."
log "[*]" "Création de la commande globale 'jellyfin'..."
cat << 'EOF' > /usr/local/bin/jellyfin
#!/bin/sh
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a
PATH_JELLYFIN="${PATH_JELLYFIN:-/etc/DomoNas/Docker/Jellyfin}"
PORT_JELLYFIN="${PORT_JELLYFIN:-1001}"
mkdir -p "$PATH_JELLYFIN/config" "$PATH_JELLYFIN/cache"
case "$1" in
    create)
        docker rm -f jellyfin 2>/dev/null || true
        docker pull jellyfin/jellyfin:latest || echo " "
        docker run -d \
            --name jellyfin \
            --restart=unless-stopped \
            -e TZ=CET \
            -v "$PATH_JELLYFIN/config:/config" \
            -v "/media/:/media" \
            -v "$PATH_JELLYFIN/cache:/cache" \
            -p "$PORT_JELLYFIN:8096" \
            -p 8920:8920 \
            -e PUID=1000 \
            -e PGID=1000 \
            --device /dev/dri/renderD128:/dev/dri/renderD128 \
            jellyfin/jellyfin:latest
        ;;
        update)
        docker rm -f jellyfin 2>/dev/null || true
        docker pull jellyfin/jellyfin:latest || echo " "
        docker run -d \
            --name jellyfin \
            --restart=unless-stopped \
            -e TZ=CET \
            -v "$PATH_JELLYFIN/config:/config" \
            -v "/media/:/media" \
            -v "$PATH_JELLYFIN/cache:/cache" \
            -p "$PORT_JELLYFIN:8096" \
            -p 8920:8920 \
            -e PUID=1000 \
            -e PGID=1000 \
            --device /dev/dri/renderD128:/dev/dri/renderD128 \
            jellyfin/jellyfin:latest
        ;;
    start)
        docker start jellyfin
        ;;
    stop)
        docker stop jellyfin
        ;;
    restart)
        docker restart jellyfin
        ;;
    *)
        echo "Usage: jellyfin {create|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/jellyfin
log "[+]" "Commande 'jellyfin' créée avec succès (utilisable via 'jellyfin create', etc.)."
log "[*]" "Création de la commande globale 'transmission'..."
cat << 'EOF' > /usr/local/bin/transmission
#!/bin/sh
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a
PATH_DOWNBOX="${PATH_DOWNBOX:-/media/Runable/Docker/DownBox}"
PATH_TRANSMISSION="${PATH_TRANSMISSION:-/media/Runable/DownBox}"
PORT_DOWNBOX="${PORT_DOWNBOX:-1002}"
USERNAME_VPN="${USERNAME_VPN:-mon_user_vpn}"
PASSWORD_VPN="${PASSWORD_VPN:-mon_pass_vpn}"
USERNAME_GENERAL="${USERNAME_GENERAL:-admin}"
PASSWORD_GENERAL_LOW="${PASSWORD_GENERAL_LOW:-admin}"
mkdir -p "$PATH_DOWNBOX/custom" "$PATH_DOWNBOX/config"
case "$1" in
    create)
        docker rm -f transmission downboxproxy 2>/dev/null || true
        docker pull haugene/transmission-openvpn:latest || true
        docker pull haugene/transmission-openvpn-proxy:latest || true
        docker run -d \
            --name transmission \
            --privileged \
            --restart=unless-stopped \
            -e PUID=1000 \
            -e PGID=1000 \
            -p 9091:9091 \
            -p 51415:51414 \
            -p 51415:51414/udp \
            --cap-add=NET_ADMIN \
            -e TRANSMISSION_WEB_UI=transmission-web-control \
            -v "$PATH_DOWNBOX/custom:/etc/openvpn/custom" \
            -v "$PATH_TRANSMISSION:/data" \
            -v "$PATH_DOWNBOX/config:/config" \
            -e OPENVPN_PROVIDER=CUSTOM \
            -e OPENVPN_USERNAME="$USERNAME_VPN" \
            -e OPENVPN_PASSWORD="$PASSWORD_VPN" \
            -e TRANSMISSION_DOWNLOAD_DIR=/data/DownBox \
            -e UFW_ALLOW_GW_NET=true \
            -e UFW_EXTRA_PORTS=9910,23561,443,83,9091 \
            -e DROP_DEFAULT_ROUTE=true \
            -e TRANSMISSION_RPC_USERNAME="$USERNAME_GENERAL" \
            -e TRANSMISSION_RPC_PASSWORD="$PASSWORD_GENERAL_LOW" \
            -e TRANSMISSION_RPC_AUTHENTICATION_REQUIRED=true \
            -e TRANSMISSION_RPC_WHITELIST_ENABLED=false \
            -e LOCAL_NETWORK=192.168.1.0/32 \
            --log-driver json-file \
            --log-opt max-size=10m \
            haugene/transmission-openvpn:latest
        docker run -d \
            --name downboxproxy \
            --privileged \
            --restart=unless-stopped \
            --link transmission \
            -p "$PORT_DOWNBOX:8080" \
            haugene/transmission-openvpn-proxy:latest
        ;;
    update)
        docker rm -f transmission downboxproxy 2>/dev/null || true
        docker pull haugene/transmission-openvpn:latest || true
        docker pull haugene/transmission-openvpn-proxy:latest || true
        docker run -d \
            --name transmission \
            --privileged \
            --restart=unless-stopped \
            -e PUID=1000 \
            -e PGID=1000 \
            -p 9091:9091 \
            -p 51415:51414 \
            -p 51415:51414/udp \
            --cap-add=NET_ADMIN \
            -e TRANSMISSION_WEB_UI=transmission-web-control \
            -v "$PATH_DOWNBOX/custom:/etc/openvpn/custom" \
            -v "$PATH_TRANSMISSION:/data" \
            -v "$PATH_DOWNBOX/config:/config" \
            -e OPENVPN_PROVIDER=CUSTOM \
            -e OPENVPN_USERNAME="$USERNAME_VPN" \
            -e OPENVPN_PASSWORD="$PASSWORD_VPN" \
            -e TRANSMISSION_DOWNLOAD_DIR=/data/DownBox \
            -e UFW_ALLOW_GW_NET=true \
            -e UFW_EXTRA_PORTS=9910,23561,443,83,9091 \
            -e DROP_DEFAULT_ROUTE=true \
            -e TRANSMISSION_RPC_USERNAME="$USERNAME_GENERAL" \
            -e TRANSMISSION_RPC_PASSWORD="$PASSWORD_GENERAL_LOW" \
            -e TRANSMISSION_RPC_AUTHENTICATION_REQUIRED=true \
            -e TRANSMISSION_RPC_WHITELIST_ENABLED=false \
            -e LOCAL_NETWORK=192.168.1.0/32 \
            --log-driver json-file \
            --log-opt max-size=10m \
            haugene/transmission-openvpn:latest
        docker run -d \
            --name downboxproxy \
            --privileged \
            --restart=unless-stopped \
            --link transmission \
            -p "$PORT_DOWNBOX:8080" \
            haugene/transmission-openvpn-proxy:latest
        ;;
    start)
        docker start transmission downboxproxy
        ;;
    stop)
        docker stop downboxproxy transmission
        ;;
    restart)
        docker restart transmission downboxproxy
        ;;
    *)
        echo "Usage: transmission {create|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/transmission
ln -sf /usr/local/bin/transmission /usr/local/bin/tr
log "[+]" "Commande 'transmission' (ou 'tr') créée avec succès."
log "[*]" "Création de la commande globale 'seedbox'..."
cat << 'EOF' > /usr/local/bin/seedbox
#!/bin/sh
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a
PATH_SEEDBOX="${PATH_SEEDBOX:-/etc/DomoNas/Docker/Seedbox}"
PATH_TRANSMISSION="${PATH_TRANSMISSION:-/media/Runable/DownBox}"
PORT_SEEDBOX="${PORT_SEEDBOX:-1003}"
USERNAME_GENERAL="${USERNAME_GENERAL:-admin}"
PASSWORD_GENERAL_LOW="${PASSWORD_GENERAL_LOW:-admin}"
mkdir -p "$PATH_SEEDBOX"
case "$1" in
    create)
        docker rm -f seedbox 2>/dev/null || true
        docker pull lscr.io/linuxserver/transmission:latest || echo ""
        docker run -d \
            --name seedbox \
            --privileged \
            --restart=unless-stopped \
            -e TZ=CET \
            -v "$PATH_SEEDBOX:/config" \
            -v "$PATH_TRANSMISSION:/downloads" \
            -p "$PORT_SEEDBOX:9091" \
            -p 51413:51413 \
            -p 51413:51413/udp \
            -e PUID=1000 \
            -e PGID=1000 \
            -e USER="$USERNAME_GENERAL" \
            -e PASS="$PASSWORD_GENERAL_LOW" \
            -e TRANSMISSION_DOWNLOAD_DIR=/downloads/SeedBox \
            lscr.io/linuxserver/transmission:latest
        TMP_DIR="/tmp/twc_$(date +%s)"
        mkdir -p "$TMP_DIR"
        git clone https://github.com/ronggang/transmission-web-control.git "$TMP_DIR/twc" >/dev/null 2>&1
        mkdir -p "$PATH_SEEDBOX/GUI"
        cp -r "$TMP_DIR/twc/src/"* "$PATH_SEEDBOX/GUI/"
        rm -rf "$TMP_DIR"
        sleep 3 # Laisse le temps au conteneur de s'initialiser
        docker exec seedbox cp -r /config/GUI /usr/share/transmission/public_html/web-control 2>/dev/null || true
        ;;
    update)
        docker rm -f seedbox 2>/dev/null || true
        docker pull lscr.io/linuxserver/transmission:latest || echo ""
        docker run -d \
            --name seedbox \
            --privileged \
            --restart=unless-stopped \
            -e TZ=CET \
            -v "$PATH_SEEDBOX:/config" \
            -v "$PATH_TRANSMISSION:/downloads" \
            -p "$PORT_SEEDBOX:9091" \
            -p 51413:51413 \
            -p 51413:51413/udp \
            -e PUID=1000 \
            -e PGID=1000 \
            -e USER="$USERNAME_GENERAL" \
            -e PASS="$PASSWORD_GENERAL_LOW" \
            -e TRANSMISSION_DOWNLOAD_DIR=/downloads/SeedBox \
            lscr.io/linuxserver/transmission:latest
        TMP_DIR="/tmp/twc_$(date +%s)"
        mkdir -p "$TMP_DIR"
        git clone https://github.com/ronggang/transmission-web-control.git "$TMP_DIR/twc" >/dev/null 2>&1
        mkdir -p "$PATH_SEEDBOX/GUI"
        cp -r "$TMP_DIR/twc/src/"* "$PATH_SEEDBOX/GUI/"
        rm -rf "$TMP_DIR"
        sleep 3 # Laisse le temps au conteneur de s'initialiser
        docker exec seedbox cp -r /config/GUI /usr/share/transmission/public_html/web-control 2>/dev/null || true
        ;;
    start)
        docker start seedbox
        ;;
    stop)
        docker stop seedbox
        ;;
    restart)
        docker restart seedbox
        ;;
    *)
        echo "Usage: seedbox {create|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/seedbox
ln -sf /usr/local/bin/seedbox /usr/local/bin/sb
log "[+]" "Commande 'seedbox' (ou 'sb') créée avec succès."
log "[*]" "Création de la commande globale 'grocy'..."
cat << 'EOF' > /usr/local/bin/grocy
#!/bin/sh
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a
PATH_GROCY="${PATH_GROCY:-/etc/DomoNas/Docker/Grocy}"
PORT_GROCY="${PORT_GROCY:-1004}"
mkdir -p "$PATH_GROCY"
case "$1" in
    create)
        docker rm -f grocy 2>/dev/null || true
        docker pull lscr.io/linuxserver/grocy:latest || echo ""
        docker run -d \
            --name grocy \
            --restart=unless-stopped \
            -e TZ=CET \
            -v "$PATH_GROCY:/config" \
            -p "$PORT_GROCY:80" \
            lscr.io/linuxserver/grocy:latest
        ;;
    update)
        docker rm -f grocy 2>/dev/null || true
        docker pull lscr.io/linuxserver/grocy:latest || echo ""
        docker run -d \
            --name grocy \
            --restart=unless-stopped \
            -e TZ=CET \
            -v "$PATH_GROCY:/config" \
            -p "$PORT_GROCY:80" \
            lscr.io/linuxserver/grocy:latest
        ;;
    start)
        docker start grocy
        ;;
    stop)
        docker stop grocy
        ;;
    restart)
        docker restart grocy
        ;;
    *)
        echo "Usage: grocy {create|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/grocy
log "[+]" "Commande 'grocy' créée avec succès."
log "[*]" "Création de la commande globale 'portainer'..."
cat << 'EOF' > /usr/local/bin/portainer
#!/bin/sh
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a
PATH_PORTAINER="${PATH_PORTAINER:-/etc/DomoNas/Docker/Portainer}"
PORT_PORTAINER="${PORT_PORTAINER:-1005}"
mkdir -p "$PATH_PORTAINER"
case "$1" in
    create)
        docker rm -f portainer 2>/dev/null || true
        docker pull portainer/portainer-ce:latest || echo ""
        docker run -d \
            --name portainer \
            --privileged \
            --restart=unless-stopped \
            -e TZ=CET \
            -p 8000:8000 \
            -p 9443:9443 \
            -p "$PORT_PORTAINER:9000" \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v "$PATH_PORTAINER:/data" \
            portainer/portainer-ce:latest
        ;;
    update)
        docker rm -f portainer 2>/dev/null || true
        docker pull portainer/portainer-ce:latest || echo ""
        docker run -d \
            --name portainer \
            --privileged \
            --restart=unless-stopped \
            -e TZ=CET \
            -p 8000:8000 \
            -p 9443:9443 \
            -p "$PORT_PORTAINER:9000" \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v "$PATH_PORTAINER:/data" \
            portainer/portainer-ce:latest
        ;;
    start)
        docker start portainer
        ;;
    stop)
        docker stop portainer
        ;;
    restart)
        docker restart portainer
        ;;
    *)
        echo "Usage: portainer {create|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/portainer
ln -sf /usr/local/bin/portainer /usr/local/bin/po
log "[+]" "Commande 'portainer' (ou 'po') créée avec succès."
log "[*]" "Création de la commande globale 'filebrowser'..."
cat << 'EOF' > /usr/local/bin/filebrowser
#!/bin/sh
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a
PATH_FILEBROWSER="${PATH_FILEBROWSER:-/etc/DomoNas/Docker/Filebrowser}"
PORT_FILEBROWSER="${PORT_FILEBROWSER:-1006}"
mkdir -p "$PATH_FILEBROWSER/database" "$PATH_FILEBROWSER/config"
case "$1" in
    create)
        docker rm -f filebrowser 2>/dev/null || true
        docker pull gtstef/filebrowser:latest || echo " "
        docker run -d \
            --name filebrowser \
            --restart=unless-stopped \
            -e TZ=CET \
            -v "/media:/srv" \
            -v "$PATH_FILEBROWSER/database:/database" \
            -v "$PATH_FILEBROWSER/config:/config" \
            -p "$PORT_FILEBROWSER:80" \
            gtstef/filebrowser:latest
        ;;
    update)
        docker rm -f filebrowser 2>/dev/null || true
        docker pull gtstef/filebrowser:latest || echo " "
        docker run -d \
            --name filebrowser \
            --restart=unless-stopped \
            -e TZ=CET \
            -v "/media:/srv" \
            -v "$PATH_FILEBROWSER/database:/database" \
            -v "$PATH_FILEBROWSER/config:/config" \
            -p "$PORT_FILEBROWSER:80" \
            gtstef/filebrowser:latest
        ;;
    start)
        docker start filebrowser
        ;;
    stop)
        docker stop filebrowser
        ;;
    restart)
        docker restart filebrowser
        ;;
    *)
        echo "Usage: filebrowser {create|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/filebrowser
ln -sf /usr/local/bin/filebrowser /usr/local/bin/fb
log "[+]" "Commande 'filebrowser' (ou 'fb') créée avec succès."
log "[*]" "Création de la commande globale 'freshrss'..."
cat << 'EOF' > /usr/local/bin/freshrss
#!/bin/sh
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a
PATH_FRESHRSS="${PATH_FRESHRSS:-/etc/DomoNas/Docker/FreshRSS}"
PORT_FRESHRSS="${PORT_FRESHRSS:-1007}"
mkdir -p "$PATH_FRESHRSS"
case "$1" in
    create)
        docker rm -f freshrss 2>/dev/null || true
        docker pull freshrss/freshrss:latest || echo ""
        docker run -d \
            --name freshrss \
            --restart=unless-stopped \
            -e TZ=CET \
            -e CRON_MIN="1,31" \
            -p "$PORT_FRESHRSS:80" \
            -v "$PATH_FRESHRSS:/var/www/FreshRSS" \
            freshrss/freshrss:latest
        ;;
    update)
        docker rm -f freshrss 2>/dev/null || true
        docker pull freshrss/freshrss:latest || echo ""
        docker run -d \
            --name freshrss \
            --restart=unless-stopped \
            -e TZ=CET \
            -e CRON_MIN="1,31" \
            -p "$PORT_FRESHRSS:80" \
            -v "$PATH_FRESHRSS:/var/www/FreshRSS" \
            freshrss/freshrss:latest
        ;;
    start)
        docker start freshrss
        ;;
    stop)
        docker stop freshrss
        ;;
    restart)
        docker restart freshrss
        ;;
    *)
        echo "Usage: freshrss {create|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/freshrss
ln -sf /usr/local/bin/freshrss /usr/local/bin/fr
log "[+]" "Commande 'freshrss' (ou 'fr') créée avec succès."
log "[*]" "Création de la commande globale 'mqtt'..."
cat << 'EOF' > /usr/local/bin/mqtt
#!/bin/sh
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a
PATH_MQTT="${PATH_MQTT:-/etc/DomoNas/Docker/MQTT}"
PORT_MQTT="${PORT_MQTT:-1015}"
USERNAME_GENERAL="${USERNAME_GENERAL:-admin}"
PASSWORD_GENERAL_HIGH="${PASSWORD_GENERAL_HIGH:-administrateur}"
mkdir -p "$PATH_MQTT/config" "$PATH_MQTT/data"
case "$1" in
    create)
        docker rm -f mqtt mstt 2>/dev/null || true
        docker pull eclipse-mosquitto:latest || echo ""
        docker run -d \
            --name mqtt \
            --restart=unless-stopped \
            -e TZ=CET \
            -v "$PATH_MQTT/config:/mosquitto/config" \
            -v "$PATH_MQTT/data:/mosquitto/data" \
            -p "$PORT_MQTT:1883" \
            -p 9001:9001 \
            eclipse-mosquitto:latest
        sleep 2
        docker exec mqtt sh -c "mosquitto_passwd -b /mosquitto/config/password.txt $USERNAME_GENERAL $PASSWORD_GENERAL_HIGH" 2>/dev/null || true
        ;;
     update)
        docker rm -f mqtt mstt 2>/dev/null || true
        docker pull eclipse-mosquitto:latest || echo ""
        docker run -d \
            --name mqtt \
            --restart=unless-stopped \
            -e TZ=CET \
            -v "$PATH_MQTT/config:/mosquitto/config" \
            -v "$PATH_MQTT/data:/mosquitto/data" \
            -p "$PORT_MQTT:1883" \
            -p 9001:9001 \
            eclipse-mosquitto:latest
        sleep 2
        docker exec mqtt sh -c "mosquitto_passwd -b /mosquitto/config/password.txt $USERNAME_GENERAL $PASSWORD_GENERAL_HIGH" 2>/dev/null || true
        ;;
    start)
        docker start mqtt
        ;;
    stop)
        docker stop mqtt
        ;;
    restart)
        docker restart mqtt
        ;;
    *)
        echo "Usage: mqtt {create|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/mqtt
ln -sf /usr/local/bin/mqtt /usr/local/bin/mq
log "[+]" "Commande 'mqtt' (ou 'mq') créée avec succès."
log "[*]" "Création de la commande globale 'gitea'..."
cat << 'EOF' > /usr/local/bin/gitea
#!/bin/sh
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a
PATH_GITEA="${PATH_GITEA:-/etc/DomoNas/Docker/Gitea}"
PORT_GITEA="${PORT_GITEA:-1010}"
mkdir -p "$PATH_GITEA"
case "$1" in
    create)
        docker rm -f gitea 2>/dev/null || true
        docker pull gitea/gitea:latest || echo ""
        docker run -d \
            --name gitea \
            --restart=unless-stopped \
            -p "$PORT_GITEA:3000" \
            -p 2222:22 \
            -v "$PATH_GITEA:/data" \
            -v /etc/timezone:/etc/timezone:ro \
            -v /etc/localtime:/etc/localtime:ro \
            gitea/gitea:latest
        ;;
    update)
        docker rm -f gitea 2>/dev/null || true
        docker pull gitea/gitea:latest || echo ""
        docker run -d \
            --name gitea \
            --restart=unless-stopped \
            -p "$PORT_GITEA:3000" \
            -p 2222:22 \
            -v "$PATH_GITEA:/data" \
            -v /etc/timezone:/etc/timezone:ro \
            -v /etc/localtime:/etc/localtime:ro \
            gitea/gitea:latest
        ;;
    start)
        docker start gitea
        ;;
    stop)
        docker stop gitea
        ;;
    restart)
        docker restart gitea
        ;;
    *)
        echo "Usage: gitea {create|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/gitea
ln -sf /usr/local/bin/gitea /usr/local/bin/gt
log "[+]" "Commande 'gitea' (ou 'gt') créée avec succès."
log "[*]" "Création de la commande globale 'siyuan'..."
cat << 'EOF' > /usr/local/bin/siyuan
#!/bin/sh
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a
PATH_SIYUAN="${PATH_SIYUAN:-/etc/DomoNas/Docker/SiYuan}"
PORT_SIYUAN="${PORT_SIYUAN:-6806}"
PASSWORD_GENERAL_HIGH="${PASSWORD_GENERAL_HIGH:-password}"
mkdir -p "$PATH_SIYUAN"
case "$1" in
    create)
        docker rm -f siyuan 2>/dev/null || true
        docker pull b3log/siyuan:latest || echo ""
        docker run -d \
            --name siyuan \
            --restart=unless-stopped \
            -v "$PATH_SIYUAN:/siyuan/workspace" \
            -p "$PORT_SIYUAN:6806" \
            -e PUID=1000 \
            -e PGID=1000 \
            b3log/siyuan:latest \
            serve \
            --workspace=/siyuan/workspace \
            --accessAuthCode="$PASSWORD_GENERAL_HIGH"
        ;;
    update)
        docker rm -f siyuan 2>/dev/null || true
        docker pull b3log/siyuan:latest || echo ""
        docker run -d \
            --name siyuan \
            --restart=unless-stopped \
            -v "$PATH_SIYUAN:/siyuan/workspace" \
            -p "$PORT_SIYUAN:6806" \
            -e PUID=1000 \
            -e PGID=1000 \
            b3log/siyuan:latest \
            serve \
            --workspace=/siyuan/workspace \
            --accessAuthCode="$PASSWORD_GENERAL_HIGH"
        ;;
    start)
        docker start siyuan
        ;;
    stop)
        docker stop siyuan
        ;;
    restart)
        docker restart siyuan
        ;;
    *)
        echo "Usage: siyuan {create|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/siyuan
ln -sf /usr/local/bin/siyuan /usr/local/bin/sy
log "[+]" "Commande 'siyuan' (ou 'sy') créée avec succès."
log "[*]" "Création de la commande globale 'myelectricaldata'..."
cat << 'EOF' > /usr/local/bin/myelectricaldata
#!/bin/sh
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a
PATH_MED="${PATH_MED:-/etc/DomoNas/Docker/MyElectricalData/config.yaml}"
PORT_MED="${PORT_MED:-5000}"
mkdir -p "$(dirname "$PATH_MED")"
case "$1" in
    create)
        docker rm -f med myelectricaldata 2>/dev/null || true
        docker pull m4dm4rtig4n/myelectricaldata:latest || echo ""
        docker run -d \
            --name myelectricaldata \
            --restart=unless-stopped \
            -p "$PORT_MED:5000" \
            -v "$PATH_MED:/data/config.yaml" \
            m4dm4rtig4n/myelectricaldata:latest
        ;;
    update)
        docker rm -f med myelectricaldata 2>/dev/null || true
        docker pull m4dm4rtig4n/myelectricaldata:latest || echo ""
        docker run -d \
            --name myelectricaldata \
            --restart=unless-stopped \
            -p "$PORT_MED:5000" \
            -v "$PATH_MED:/data/config.yaml" \
            m4dm4rtig4n/myelectricaldata:latest
        ;;
    start)
        docker start myelectricaldata
        ;;
    stop)
        docker stop myelectricaldata
        ;;
    restart)
        docker restart myelectricaldata
        ;;
    *)
        echo "Usage: myelectricaldata {create|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/myelectricaldata
ln -sf /usr/local/bin/myelectricaldata /usr/local/bin/med
log "[+]" "Commande 'myelectricaldata' (ou 'med') créée avec succès."
log "[*]" "Création de la commande globale 'kiwix'..."
cat << 'EOF' > /usr/local/bin/kiwix
#!/bin/sh
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a
PATH_KIWIX="${PATH_KIWIX:-/media/Docs01/Kiwix}"
PORT_KIWIX="${PORT_KIWIX:-1011}"
mkdir -p "$PATH_KIWIX"
case "$1" in
    create)
        docker rm -f kiwix 2>/dev/null || true
        docker pull ghcr.io/kiwix/kiwix-serve:latest || echo ""
        docker run -d \
            --name kiwix \
            --restart=unless-stopped \
            -p "$PORT_KIWIX:8080" \
            -v "$PATH_KIWIX:/data" \
            ghcr.io/kiwix/kiwix-serve:latest \
            /data/*.zim
        ;;
    update)
        docker rm -f kiwix 2>/dev/null || true
        docker pull ghcr.io/kiwix/kiwix-serve:latest || echo ""
        docker run -d \
            --name kiwix \
            --restart=unless-stopped \
            -p "$PORT_KIWIX:8080" \
            -v "$PATH_KIWIX:/data" \
            ghcr.io/kiwix/kiwix-serve:latest \
            /data/*.zim
        ;;
    start)
        docker start kiwix
        ;;
    stop)
        docker stop kiwix
        ;;
    restart)
        docker restart kiwix
        ;;
    *)
        echo "Usage: kiwix {create|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/kiwix
ln -sf /usr/local/bin/kiwix /usr/local/bin/kw
log "[+]" "Commande 'kiwix' (ou 'kw') créée avec succès."
log "[*]" "Création de la commande globale 'kolibri'..."
cat << 'EOF' > /usr/local/bin/kolibri
#!/bin/sh
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a
PATH_KOLIBRI="${PATH_KOLIBRI:-/media/Runable/Docker/Kolibri}"
PORT_KOLIBRI="${PORT_KOLIBRI:-1012}"
mkdir -p "$PATH_KOLIBRI"
case "$1" in
    create)
        docker rm -f kolibri 2>/dev/null || true
        docker pull learningequality/kolibri:latest || echo ""
        docker run -d \
            --name kolibri \
            --restart=unless-stopped \
            -p "$PORT_KOLIBRI:8080" \
            -v "$PATH_KOLIBRI:/kolibri" \
            learningequality/kolibri:latest
        ;;
    update)
        docker rm -f kolibri 2>/dev/null || true
        docker pull learningequality/kolibri:latest || echo ""
        docker run -d \
            --name kolibri \
            --restart=unless-stopped \
            -p "$PORT_KOLIBRI:8080" \
            -v "$PATH_KOLIBRI:/kolibri" \
            learningequality/kolibri:latest
        ;;
    start)
        docker start kolibri
        ;;
    stop)
        docker stop kolibri
        ;;
    restart)
        docker restart kolibri
        ;;
    *)
        echo "Usage: kolibri {create|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/kolibri
ln -sf /usr/local/bin/kolibri /usr/local/bin/kb
log "[+]" "Commande 'kolibri' (ou 'kb') créée avec succès."
log "[*]" "Création de la commande globale 'cyberchef'..."
cat << 'EOF' > /usr/local/bin/cyberchef
#!/bin/sh
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a
PORT_CYBERCHEF="${PORT_CYBERCHEF:-8000}"
case "$1" in
    create)
        docker rm -f cyberchef 2>/dev/null || true
        docker pull mpepping/cyberchef:latest || echo ""
        docker run -d \
            --name cyberchef \
            --restart=unless-stopped \
            -p "$PORT_CYBERCHEF:8000" \
            mpepping/cyberchef:latest
        ;;
    update)
        docker rm -f cyberchef 2>/dev/null || true
        docker pull mpepping/cyberchef:latest || echo ""
        docker run -d \
            --name cyberchef \
            --restart=unless-stopped \
            -p "$PORT_CYBERCHEF:8000" \
            mpepping/cyberchef:latest
        ;;
    start)
        docker start cyberchef
        ;;
    stop)
        docker stop cyberchef
        ;;
    restart)
        docker restart cyberchef
        ;;
    *)
        echo "Usage: cyberchef {create|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/cyberchef
ln -sf /usr/local/bin/cyberchef /usr/local/bin/cc
log "[+]" "Commande 'cyberchef' (ou 'cc') créée avec succès."
log "[*]" "Création de la commande globale 'vaultwarden'..."
cat << 'EOF' > /usr/local/bin/vaultwarden
#!/bin/sh
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a
PATH_VAULTWARDEN="${PATH_VAULTWARDEN:-/media/Runable/Docker/Vaultwarden}"
PORT_VAULTWARDEN="${PORT_VAULTWARDEN:-1013}"
mkdir -p "$PATH_VAULTWARDEN/ssl"
case "$1" in
    create)
        if [ ! -f "$PATH_VAULTWARDEN/ssl/vaultwarden.crt" ] || [ ! -f "$PATH_VAULTWARDEN/ssl/vaultwarden.key" ]; then
            openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
                -keyout "$PATH_VAULTWARDEN/ssl/vaultwarden.key" \
                -out "$PATH_VAULTWARDEN/ssl/vaultwarden.crt" \
                -subj "/CN=domonas.local/O=DomoNas/C=FR" 2>/dev/null
        fi
        docker rm -f vaultwarden 2>/dev/null || true
        docker pull vaultwarden/server:latest || echo ""
        docker run -d \
            --name vaultwarden \
            -e WEBSOCKET_ENABLED=true \
            -e ROCKET_TLS='{certs="/data/ssl/vaultwarden.crt",key="/data/ssl/vaultwarden.key"}' \
            -v "$PATH_VAULTWARDEN:/data" \
            -p "$PORT_VAULTWARDEN:80" \
            -p 3012:3012 \
            --restart unless-stopped \
            vaultwarden/server:latest
        ;;
    update)
        if [ ! -f "$PATH_VAULTWARDEN/ssl/vaultwarden.crt" ] || [ ! -f "$PATH_VAULTWARDEN/ssl/vaultwarden.key" ]; then
            openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
                -keyout "$PATH_VAULTWARDEN/ssl/vaultwarden.key" \
                -out "$PATH_VAULTWARDEN/ssl/vaultwarden.crt" \
                -subj "/CN=domonas.local/O=DomoNas/C=FR" 2>/dev/null
        fi
        docker rm -f vaultwarden 2>/dev/null || true
        docker pull vaultwarden/server:latest || echo ""
        docker run -d \
            --name vaultwarden \
            -e WEBSOCKET_ENABLED=true \
            -e ROCKET_TLS='{certs="/data/ssl/vaultwarden.crt",key="/data/ssl/vaultwarden.key"}' \
            -v "$PATH_VAULTWARDEN:/data" \
            -p "$PORT_VAULTWARDEN:80" \
            -p 3012:3012 \
            --restart unless-stopped \
            vaultwarden/server:latest
        ;;
    start)
        docker start vaultwarden
        ;;
    stop)
        docker stop vaultwarden
        ;;
    restart)
        docker restart vaultwarden
        ;;
    *)
        echo "Usage: vaultwarden {create|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/vaultwarden
ln -sf /usr/local/bin/vaultwarden /usr/local/bin/vw
log "[+]" "Commande 'vaultwarden' (ou 'vw') créée avec succès."
log "[*]" "Création de la commande globale 'immich'..."
cat << 'EOF' > /usr/local/bin/immich
#!/bin/sh
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a
PATH_IMMICH="${PATH_IMMICH:-/media/Docs01/Immich}"
PORT_IMMICH="${PORT_IMMICH:-1016}"
USERNAME_GENERAL="${USERNAME_GENERAL:-admin}"
PASSWORD_GENERAL_LOW="${PASSWORD_GENERAL_LOW:-administrateur}"
mkdir -p "$PATH_IMMICH"
case "$1" in
    create)
        docker rm -f immich_postgres immich_redis immich postgres redis 2>/dev/null || true
        docker network create immich_net 2>/dev/null || true
        docker pull tensorchord/pgvecto-rs:pg16-v0.2.1 || true
        docker pull docker.io/valkey/valkey:8 || true
        docker pull ghcr.io/martabal/immich:latest || echo ""
        docker run -d \
            --name postgres \
            --restart unless-stopped \
            --network immich_net \
            -e POSTGRES_USER="$USERNAME_GENERAL" \
            -e POSTGRES_PASSWORD="$PASSWORD_GENERAL_LOW" \
            -e POSTGRES_DB=immich \
            -e POSTGRES_INITDB_ARGS="--data-checksums" \
            -v immich_postgres_data:/var/lib/postgresql/data \
            tensorchord/pgvecto-rs:pg16-v0.2.1
        docker run -d \
            --name redis \
            --restart unless-stopped \
            --network immich_net \
            docker.io/valkey/valkey:8
        docker run -d \
            --name immich \
            --restart unless-stopped \
            -p "$PORT_IMMICH:8080" \
            --network immich_net \
            -v "$PATH_IMMICH:/usr/src/app/upload" \
            -e DB_HOSTNAME=postgres \
            -e DB_USERNAME="$USERNAME_GENERAL" \
            -e DB_PASSWORD="$PASSWORD_GENERAL_LOW" \
            -e DB_DATABASE_NAME=immich \
            -e REDIS_HOSTNAME=redis \
            ghcr.io/martabal/immich:latest
        ;;
    update)
        docker rm -f immich_postgres immich_redis immich postgres redis 2>/dev/null || true
        docker network create immich_net 2>/dev/null || true
        docker pull tensorchord/pgvecto-rs:pg16-v0.2.1 || true
        docker pull docker.io/valkey/valkey:8 || true
        docker pull ghcr.io/martabal/immich:latest || echo ""
        docker run -d \
            --name postgres \
            --restart unless-stopped \
            --network immich_net \
            -e POSTGRES_USER="$USERNAME_GENERAL" \
            -e POSTGRES_PASSWORD="$PASSWORD_GENERAL_LOW" \
            -e POSTGRES_DB=immich \
            -e POSTGRES_INITDB_ARGS="--data-checksums" \
            -v immich_postgres_data:/var/lib/postgresql/data \
            tensorchord/pgvecto-rs:pg16-v0.2.1
        docker run -d \
            --name redis \
            --restart unless-stopped \
            --network immich_net \
            docker.io/valkey/valkey:8
        docker run -d \
            --name immich \
            --restart unless-stopped \
            -p "$PORT_IMMICH:8080" \
            --network immich_net \
            -v "$PATH_IMMICH:/usr/src/app/upload" \
            -e DB_HOSTNAME=postgres \
            -e DB_USERNAME="$USERNAME_GENERAL" \
            -e DB_PASSWORD="$PASSWORD_GENERAL_LOW" \
            -e DB_DATABASE_NAME=immich \
            -e REDIS_HOSTNAME=redis \
            ghcr.io/martabal/immich:latest
        ;;
    start)
        docker start postgres redis immich
        ;;
    stop)
        docker stop immich redis postgres
        ;;
    restart)
        docker restart postgres redis immich
        ;;
    *)
        echo "Usage: immich {create|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/immich
ln -sf /usr/local/bin/immich /usr/local/bin/im
log "[+]" "Commande 'immich' (ou 'im') créée avec succès."
#log "[*]" "Vérification de l'état des conteneurs Docker..."
#SERVICES="lamp homeassistant jellyfin transmission seedbox grocy portainer filebrowser freshrss mqtt gitea siyuan myelectricaldata kiwix kolibri cyberchef vaultwarden immich"
#for srv in $SERVICES; do
#    if [ -x "/usr/local/bin/$srv" ]; then
#        container_name="$srv"
#        [ "$srv" = "transmission" ] && container_name="transmission"
#        [ "$srv" = "myelectricaldata" ] && container_name="myelectricaldata"
#        [ "$srv" = "mqtt" ] && container_name="mqtt"
#        [ "$srv" = "immich" ] && container_name="immich"
#        if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
#            log "[*]" "Le conteneur '$container_name' est déjà actif."
#        else
#            log "[!]" "Le conteneur '$container_name' est arrêté ou absent. Lancement via '$srv create'..."
#            if "/usr/local/bin/$srv" create; then
#                log "[+]" "Service '$srv' initialisé et lancé avec succès."
#            else
#                log "[-]" "Échec lors de l'initialisation du service '$srv'."
#            fi
#        fi
log "[*]" "Nettoyage des images Docker inutilisées..."
if docker image prune -f >/dev/null 2>&1; then
    log "[+]" "Images Docker inutilisées supprimées avec succès."
else
    log "[-]" "Échec lors du nettoyage des images Docker."
fi
#    fi
#done
#log "[+]" "Tous les services Docker ont été vérifiés et lancés."
