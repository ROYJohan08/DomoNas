#!/bin/sh
#VERSION 202610171704
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
    echo "$1 - $(date +'%Y-%m-%d %H:%M:%S') - $2" >> "${LOG_DIR}/$(date +'%Y%m%d')-INSTALL.log"
    if [ "$DEBUG" = "1" ]; then
		case "$1" in
			"[+]") printf " \033[32m[PASS]\033[0m $2 \n" ;;
			"[~]") printf " \033[38;5;208m[WAIT]\033[0m $2 \n" ;;
			"[-]") printf " \033[31m[FAIL]\033[0m $2 \n" ;;
			"[S]") printf " \033[34m[START]\033[0m $2 \n" ;;
			"[F]") printf " \033[34m[END]\033[0m $2 \n" ;;
		esac
    fi
}
log "[S]" "Démarrage du programme"
# ┌────────────────────────────────────────────────────────────────────────────┐
# │ SECTION : Installation de services                                         │
# └────────────────────────────────────────────────────────────────────────────┘

log "[*]" "Mise a jours du systeme"
DEBIAN_FRONTEND=noninteractive apt-get update -qq > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get autoremove -y --purge -qq > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get autoclean -y -qq > /dev/null 2>&1
log "[+]" "Mise a jours du systeme"

log "[*]" "Création de l'arboressance"
mkdir -p "$BASE_DIR" "$LOG_DIR" "$TEM_DIR" "$SOF_DIR" "$CRE_DIR"
log "[+]" "Création de l'arboressance"

log "[*]" "Mise a jour de l'installateur"
wget -q -O "$TEM_DIR/install.sh" https://raw.githubusercontent.com/ROYJohan08/DomoNas/refs/heads/main/install.sh > /dev/null
if [ ! -f "$SOF_DIR/install.sh" ] || [ "$TEM_DIR/install.sh" -nt "$SOF_DIR/install.sh" ]; then
    cp "$TEM_DIR/install.sh" "$SOF_DIR/install.sh"
    log "[+]" "Mise a jour de l'installateur"
else
    log "[+]" "Mise a jour de l'installateur"
fi
rm -f "$TEM_DIR/install.sh"

log "[*]" "Vérification de docker"
if ! command -v docker &> /dev/null; then
    log "[~]" "Vérification de docker"
    log "[*]" "Installation de docker"
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
        log "[+]" "Installation de docker"
    else
        log "[-]" "Installation de docker"
        exit 1
    fi
fi

PACKAGES="cron watchdog glances smartmontools ddclient rsync cockpit git wget fail2ban iotop docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin webp imagemagick ffmpeg unzip p7zip-full unrar net-tools iperf samba python3 python3-pip python3-dev python3-psutil lm-sensors"
for pkg in $PACKAGES; do
	log "[*]" "Vérification de '$pkg'"
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        log "[+]" "Vérification de '$pkg'"
    else
        log "[~]" "Vérification de '$pkg'"
		log "[*]" "Installation de '$pkg'"
        if apt-get install -y "$pkg" > /dev/null 2>&1; then
            log "[+]" "Installation de '$pkg'"
        else
            log "[-]" "Installation de '$pkg'"
            exit 1
        fi
    fi
done

# ┌────────────────────────────────────────────────────────────────────────────┐
# │ SECTION : credentials                                                      │
# └────────────────────────────────────────────────────────────────────────────┘

mkdir -p "$CRE_DIR"
TARGET_CRED="$CRE_DIR/credentials.env"
log "[*]" "Vérification de 'credentials.env'"
if [ ! -f "$TARGET_CRED" ]; then
	log "[~]" "Vérification de 'credentials.env'"
    log "[*]" "Recherche d'un fichier 'credentials.env' sur le système"
    FOUND_CRED=""
    FOUND_CRED=$(find / -name "credentials.env" ! -path "$TARGET_CRED" ! -path "/proc/*" ! -path "/sys/*" ! -path "/dev/*" 2>/dev/null | head -n 1)
    if [ -n "$FOUND_CRED" ]; then
        if [ "$FOUND_CRED" -nt "$TARGET_CRED" ]; then
            cp "$FOUND_CRED" "$TARGET_CRED"
            log "[+]" "Recherche d'un fichier 'credentials.env' sur le système"
        fi
    else
        log "[~]" "Recherche d'un fichier 'credentials.env' sur le système"
        log "[*]" "Téléchargement du modèle depuis GitHub"
        if curl -fsSL "https://raw.githubusercontent.com/ROYJohan08/DomoNas/refs/heads/main/credentials.env" -o "$TARGET_CRED"; then
            log "[+]" "Téléchargement du modèle depuis GitHub"
            if [ -f "$TARGET_CRED" ]; then
                log "[*]" "Configuration interactive"
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
                log "[+]" "Configuration interactive"
            fi
        else
            log "[-]" "Téléchargement du modèle depuis GitHub"
            exit 1
        fi
    fi
else
    log "[+]" "Vérification de 'credentials.env'"
fi
log "[*]" "import de 'credentials.env'"
set -a
. "$TARGET_CRED"
set +a
log "[+]" "import de 'credentials.env'"

# ┌────────────────────────────────────────────────────────────────────────────┐
# │ SECTION : Configurations                                                   │
# └────────────────────────────────────────────────────────────────────────────┘

log "[*]" "Configuration de Samba"
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
systemctl restart smbd nmbd > /dev/null 2>&1
systemctl enable smbd nmbd > /dev/null 2>&1
log "[+]" "Configuration de Samba"

log "[*]" "Configuration de Cockpit"
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
log "[+]" "Configuration de Cockpit"

log "[*]" "Configuration de DDClient"
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
systemctl enable ddclient >/dev/null 2>&1
systemctl restart ddclient >/dev/null 2>&1
log "[+]" "Configuration de DDClient"

log "[*]" "Configuration de Fail2ban"
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
systemctl restart fail2ban >/dev/null 2>&1
systemctl enable fail2ban >/dev/null 2>&1
log "[+]" "Configuration de Fail2ban"

log "[*]" "Configuration de Smartmontools"
sed -i 's/#start_due_daemon=yes/start_due_daemon=yes/' /etc/default/smartmontools
cat << 'EOF' > /etc/smartd.conf
DEVICESCAN -H -m root -M exec /usr/share/smartmontools/smartd-runner
EOF
systemctl enable smartmontools >/dev/null 2>&1
systemctl restart smartmontools >/dev/null 2>&1
log "[+]" "Configuration de Smartmontools"

log "[*]" "Configuration des capteurs de température"
sensors-detect --auto > /dev/null 2>&1 || true
log "[+]" "Configuration des capteurs de température"

log "[*]" "Création du script de réparation réseau pour Watchdog"
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
log "[+]" "Création du script de réparation réseau pour Watchdog"

log "[*]" "Configuration de Watchdog"
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
log "[+]" "Configuration de Watchdog"

log "[*]" "Configuration de Glances"
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
systemctl enable glances.service >/dev/null 2>&1
systemctl restart glances.service >/dev/null 2>&1
log "[+]" "Configuration de Glances"

lsblk -rno NAME,MOUNTPOINT,LABEL,TYPE,UUID | while read -r name mountpoint label type uuid; do
    if [ "$type" = "part" ] && [ -z "$mountpoint" ]; then
        if [ -n "$label" ] && [ "$label" != "null" ]; then
            disk_name="$label"
        else
            disk_name="$name"
        fi
        target_dir="/media/$disk_name"
        log "[*]" "Montage du disque /dev/$name ${label:-Aucun}"
        mkdir -p "$target_dir"
        if mount "/dev/$name" "$target_dir"; then
            log "[+]" "Montage du disque /dev/$name ${label:-Aucun}"
            if [ -n "$uuid" ] && ! grep -q "$uuid" /etc/fstab; then
                fstype=$(blkid -s TYPE -o value "/dev/$name")
                if [ -n "$fstype" ]; then
                    echo "UUID=$uuid $target_dir $fstype defaults,nofail 0 2" >> /etc/fstab
                    log "[+]" "Entrée fstab ajoutée pour le disque $disk_name (UUID: $uuid)."
                fi
            fi
        else
            log "[-]" "Montage du disque /dev/$name ${label:-Aucun}"
        fi
    fi
done
chown -R royjohan:royjohan /media 2>/dev/null || true

CRON_TMP="/tmp/root_crontab_doponas"
crontab -l 2>/dev/null > "$CRON_TMP" || true
add_cron_job() {
    cron_line="$1"
	log "[*]" "Vérification de la tâches cron : $cron_line"
    if ! grep -Fqx "$cron_line" "$CRON_TMP"; then
		log "[~]" "Vérification de la tâches cron : $cron_line"
		log "[*]" "Installation de la tâches cron : $cron_line"
        echo "$cron_line" >> "$CRON_TMP"
        log "[+]" "Installation de la tâches cron : $cron_line"
    else
        log "[+]" "Vérification de la tâches cron : $cron_line"
    fi
}
add_cron_job "@reboot glances -w &"
add_cron_job "@reboot iperf -s"
add_cron_job "@reboot mount -a --onlyonce"
add_cron_job "50 6 * * * $SOF_DIR/archive.sh &"
crontab "$CRON_TMP"
rm -f "$CRON_TMP"

# ┌────────────────────────────────────────────────────────────────────────────┐
# │ SECTION : Commandes docker                                                 │
# └────────────────────────────────────────────────────────────────────────────┘

log "[*]" "Création de 'lamp'"
cat << 'EOF' > /usr/local/bin/lamp
#!/bin/sh
set -eu
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a

PATH_LAMP="${PATH_LAMP:-/media/Runable/Docker/Lamp}"
PATH_MAPS="${PATH_MAPS:-/media/Docs01/Maps/20260726_Europa.pmtiles}"
PATH_CREDS="${PATH_CREDS:-/etc/DomoNas/Credentials}"
PORT_LAMP="${PORT_LAMP:-81}"

NAME="lamp"
IMAGE="php:8.2-apache"
mkdir -p "$PATH_LAMP"
run_container() {
    docker rm -f "$NAME" 2>/dev/null || true
    docker run -d \
        --name "$NAME" \
        --restart=unless-stopped \
        -e TZ=CET \
        -v "$PATH_LAMP:/var/www/html" \
        -v "$PATH_MAPS:/var/www/html/europe.pmtiles:ro" \
        -v "$PATH_CREDS:/etc/DomoNas/Credentials" \
        -v /media:/media \
        -p "$PORT_LAMP:80" \
        -p 3306:3306 \
        "$IMAGE"
}
case "$1" in
    create)
        docker pull "$IMAGE"
        run_container
        echo "Conteneur $NAME créé avec succès."
        ;;
    update)
        OLD_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        if ! docker pull "$IMAGE"; then
            exit 1
        fi
        NEW_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        CONTAINER_EXISTS=$(docker ps -a -q -f name=^"$NAME"$ 2>/dev/null || echo "")
        
        if [ "$OLD_IMAGE_ID" = "$NEW_IMAGE_ID" ] && [ -n "$CONTAINER_EXISTS" ]; then
            echo "L'image est déjà à jour et le conteneur existe. Aucune action requise."
        else
            run_container
            echo "Conteneur $NAME mis à jour et créé avec succès."
        fi
        ;;
    start)
        docker start "$NAME"
        ;;
    stop)
        docker stop "$NAME"
        ;;
    restart)
        docker restart "$NAME"
        ;;
    *)
        echo "Usage: $0 {create|update|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/lamp
log "[+]" "Création de 'lamp'"

log "[*]" "Création de 'homeassistant'"
cat << 'EOF' > /usr/local/bin/homeassistant
#!/bin/sh
set -eu
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a

PATH_HOMEASSISTANT="${PATH_HOMEASSISTANT:-/media/Runable/Docker/HomeAssistant}"
PORT_HOMEASSISTANT="${PORT_HOMEASSISTANT:-1000}"

NAME="homeassistant"
IMAGE="homeassistant/home-assistant:latest"
mkdir -p "$PATH_HOMEASSISTANT"
run_container() {
    docker rm -f "$NAME" 2>/dev/null || true
    docker run -d \
        --name "$NAME" \
        --privileged \
        --restart=unless-stopped \
        --network=host \
        -e TZ=CET \
        -v "$PATH_HOMEASSISTANT:/config" \
        --device /dev/dri:/dev/dri \
        -v /etc/localtime:/etc/localtime:ro \
        -p "$PORT_HOMEASSISTANT:8123" \
        "$IMAGE"
}

case "$1" in
    create)
        docker pull "$IMAGE"
        run_container
        echo "Conteneur $NAME créé avec succès."
        ;;
    update)
        OLD_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        if ! docker pull "$IMAGE"; then
            echo "Erreur lors du téléchargement de l'image." >&2
            exit 1
        fi
        NEW_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        CONTAINER_EXISTS=$(docker ps -a -q -f name=^"$NAME"$ 2>/dev/null || echo "")
        
        if [ "$OLD_IMAGE_ID" = "$NEW_IMAGE_ID" ] && [ -n "$CONTAINER_EXISTS" ]; then
            echo "L'image est déjà à jour et le conteneur existe. Aucune action requise."
        else
            run_container
            echo "Conteneur $NAME mis à jour et créé avec succès."
        fi
        ;;
    start)
        docker start "$NAME"
        ;;
    stop)
        docker stop "$NAME"
        ;;
    restart)
        docker restart "$NAME"
        ;;
    *)
        echo "Usage: $0 {create|update|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/homeassistant
log "[+]" "Création de 'homeassistant'"
log "[*]" "Création de 'jellyfin'"
cat << 'EOF' > /usr/local/bin/jellyfin
#!/bin/sh
set -eu
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a

PATH_JELLYFIN="${PATH_JELLYFIN:-/media/Runable/Docker/Jellyfin}"
PORT_JELLYFIN="${PORT_JELLYFIN:-1001}"

NAME="jellyfin"
IMAGE="jellyfin/jellyfin:latest"
mkdir -p "$PATH_JELLYFIN/config" "$PATH_JELLYFIN/cache"
run_container() {
    docker rm -f "$NAME" 2>/dev/null || true
    docker run -d \
        --name "$NAME" \
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
        "$IMAGE"
}
case "$1" in
    create)
        docker pull "$IMAGE"
        run_container
        echo "Conteneur $NAME créé avec succès."
        ;;
    update)
        OLD_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        if ! docker pull "$IMAGE"; then
            echo "Erreur lors du téléchargement de l'image." >&2
            exit 1
        fi
        NEW_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        CONTAINER_EXISTS=$(docker ps -a -q -f name=^"$NAME"$ 2>/dev/null || echo "")
        
        if [ "$OLD_IMAGE_ID" = "$NEW_IMAGE_ID" ] && [ -n "$CONTAINER_EXISTS" ]; then
            echo "L'image est déjà à jour et le conteneur existe. Aucune action requise."
        else
            run_container
            echo "Conteneur $NAME mis à jour et créé avec succès."
        fi
        ;;
    start)
        docker start "$NAME"
        ;;
    stop)
        docker stop "$NAME"
        ;;
    restart)
        docker restart "$NAME"
        ;;
    *)
        echo "Usage: $0 {create|update|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/jellyfin
log "[+]" "Création de 'jellyfin'"
log "[*]" "Création de 'downbox'"
cat << 'EOF' > /usr/local/bin/downbox
#!/bin/sh
set -eu
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

IMAGE_TR="haugene/transmission-openvpn:latest"
IMAGE_PROXY="haugene/transmission-openvpn-proxy:latest"

mkdir -p "$PATH_DOWNBOX/custom" "$PATH_DOWNBOX/config"
run_transmission() {
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
        "$IMAGE_TR"
}
run_proxy() {
    docker run -d \
        --name downboxproxy \
        --privileged \
        --restart=unless-stopped \
        --link transmission \
        -p "$PORT_DOWNBOX:8080" \
        "$IMAGE_PROXY"
}

case "$1" in
    create)
        docker pull "$IMAGE_TR"
        docker pull "$IMAGE_PROXY"
        docker rm -f transmission downboxproxy 2>/dev/null || true
        run_transmission
        run_proxy
        echo "Stack DownBox (Transmission + Proxy) créée avec succès."
        ;;
    update)
        # Gestion Transmission
        OLD_TR_ID=$(docker images -q "$IMAGE_TR" 2>/dev/null || echo "")
        if ! docker pull "$IMAGE_TR"; then
            echo "Erreur lors du pull de l'image transmission." >&2
            exit 1
        fi
        NEW_TR_ID=$(docker images -q "$IMAGE_TR" 2>/dev/null || echo "")
        TR_EXISTS=$(docker ps -a -q -f name=^transmission$ 2>/dev/null || echo "")

        # Gestion Proxy
        OLD_PROXY_ID=$(docker images -q "$IMAGE_PROXY" 2>/dev/null || echo "")
        if ! docker pull "$IMAGE_PROXY"; then
            echo "Erreur lors du pull de l'image proxy." >&2
            exit 1
        fi
        NEW_PROXY_ID=$(docker images -q "$IMAGE_PROXY" 2>/dev/null || echo "")
        PROXY_EXISTS=$(docker ps -a -q -f name=^downboxproxy$ 2>/dev/null || echo "")

        # Vérification si une mise à jour est nécessaire
        if [ "$OLD_TR_ID" = "$NEW_TR_ID" ] && [ "$OLD_PROXY_ID" = "$NEW_PROXY_ID" ] && [ -n "$TR_EXISTS" ] && [ -n "$PROXY_EXISTS" ]; then
            echo "Les images de la stack DownBox sont déjà à jour. Aucune action requise."
        else
            echo "Mise à jour des conteneurs DownBox..."
            docker rm -f transmission downboxproxy 2>/dev/null || true
            run_transmission
            run_proxy
            echo "Stack DownBox mise à jour avec succès."
        fi
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
        echo "Usage: $0 {create|update|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/downbox
ln -sf /usr/local/bin/downbox /usr/local/bin/db
log "[+]" "Création de 'downbox'"
log "[*]" "Création de 'seedbox'"
cat << 'EOF' > /usr/local/bin/seedbox
#!/bin/sh
set -eu
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a

PATH_SEEDBOX="${PATH_SEEDBOX:-/media/Runable/Docker/Seedbox}"
PATH_TRANSMISSION="${PATH_TRANSMISSION:-/media/Runable/DownBox}"
PORT_SEEDBOX="${PORT_SEEDBOX:-1003}"
USERNAME_GENERAL="${USERNAME_GENERAL:-admin}"
PASSWORD_GENERAL_LOW="${PASSWORD_GENERAL_LOW:-admin}"

NAME="seedbox"
IMAGE="lscr.io/linuxserver/transmission:latest"

mkdir -p "$PATH_SEEDBOX"
run_container() {
    docker rm -f "$NAME" 2>/dev/null || true
    docker run -d \
        --name "$NAME" \
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
        "$IMAGE"
}
install_web_control() {
    TMP_DIR="/tmp/twc_$(date +%s)"
    mkdir -p "$TMP_DIR"
    if git clone https://github.com/ronggang/transmission-web-control.git "$TMP_DIR/twc" >/dev/null 2>&1; then
        mkdir -p "$PATH_SEEDBOX/GUI"
        cp -r "$TMP_DIR/twc/src/"* "$PATH_SEEDBOX/GUI/"
    fi
    rm -rf "$TMP_DIR"

    sleep 10
    docker exec "$NAME" cp -r -f /config/GUI/* /usr/share/transmission/public_html/ 2>/dev/null || true
}

case "$1" in
    create)
        docker pull "$IMAGE"
        run_container
        install_web_control
        echo "Conteneur $NAME créé et configuré avec succès."
        ;;
    update)
        OLD_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        if ! docker pull "$IMAGE"; then
            echo "Erreur lors du téléchargement de l'image." >&2
            exit 1
        fi
        NEW_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        CONTAINER_EXISTS=$(docker ps -a -q -f name=^"$NAME"$ 2>/dev/null || echo "")
        
        if [ "$OLD_IMAGE_ID" = "$NEW_IMAGE_ID" ] && [ -n "$CONTAINER_EXISTS" ]; then
            echo "L'image est déjà à jour et le conteneur existe. Aucune action requise."
        else
            run_container
            install_web_control
            echo "Conteneur $NAME mis à jour avec succès."
        fi
        ;;
    start)
        docker start "$NAME"
        ;;
    stop)
        docker stop "$NAME"
        ;;
    restart)
        docker restart "$NAME"
        ;;
    *)
        echo "Usage: $0 {create|update|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/seedbox
ln -sf /usr/local/bin/seedbox /usr/local/bin/sb
log "[+]" "Création de 'seedbox'"

log "[*]" "Création de 'grocy'"
cat << 'EOF' > /usr/local/bin/grocy
#!/bin/sh
set -eu
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a

PATH_GROCY="${PATH_GROCY:-/media/Runable/Docker/Grocy}"
PORT_GROCY="${PORT_GROCY:-1004}"

NAME="grocy"
IMAGE="lscr.io/linuxserver/grocy:latest"

mkdir -p "$PATH_GROCY"

run_container() {
    docker rm -f "$NAME" 2>/dev/null || true
    docker run -d \
        --name "$NAME" \
        --restart=unless-stopped \
        -e TZ=CET \
        -v "$PATH_GROCY:/config" \
        -p "$PORT_GROCY:80" \
        "$IMAGE"
}

case "$1" in
    create)
        docker pull "$IMAGE"
        run_container
        echo "Conteneur $NAME créé avec succès."
        ;;
    update)
        OLD_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        if ! docker pull "$IMAGE"; then
            echo "Erreur lors du téléchargement de l'image." >&2
            exit 1
        fi
        NEW_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        CONTAINER_EXISTS=$(docker ps -a -q -f name=^"$NAME"$ 2>/dev/null || echo "")
        
        if [ "$OLD_IMAGE_ID" = "$NEW_IMAGE_ID" ] && [ -n "$CONTAINER_EXISTS" ]; then
            echo "L'image est déjà à jour et le conteneur existe. Aucune action requise."
        else
            run_container
            echo "Conteneur $NAME mis à jour et créé avec succès."
        fi
        ;;
    start)
        docker start "$NAME"
        ;;
    stop)
        docker stop "$NAME"
        ;;
    restart)
        docker restart "$NAME"
        ;;
    *)
        echo "Usage: $0 {create|update|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/grocy
log "[+]" "Création de 'grocy'"
log "[*]" "Création de 'portainer'"
cat << 'EOF' > /usr/local/bin/portainer
#!/bin/sh
set -eu
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a

PATH_PORTAINER="${PATH_PORTAINER:-/media/Runable/Docker/Portainer}"
PORT_PORTAINER="${PORT_PORTAINER:-1005}"

NAME="portainer"
IMAGE="portainer/portainer-ce:latest"

mkdir -p "$PATH_PORTAINER"
run_container() {
    docker rm -f "$NAME" 2>/dev/null || true
    docker run -d \
        --name "$NAME" \
        --privileged \
        --restart=unless-stopped \
        -e TZ=CET \
        -p 8000:8000 \
        -p 9443:9443 \
        -p "$PORT_PORTAINER:9000" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v "$PATH_PORTAINER:/data" \
        "$IMAGE"
}

case "$1" in
    create)
        docker pull "$IMAGE"
        run_container
        echo "Conteneur $NAME créé avec succès."
        ;;
    update)
        OLD_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        if ! docker pull "$IMAGE"; then
            echo "Erreur lors du téléchargement de l'image." >&2
            exit 1
        fi
        NEW_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        CONTAINER_EXISTS=$(docker ps -a -q -f name=^"$NAME"$ 2>/dev/null || echo "")
        
        if [ "$OLD_IMAGE_ID" = "$NEW_IMAGE_ID" ] && [ -n "$CONTAINER_EXISTS" ]; then
            echo "L'image est déjà à jour et le conteneur existe. Aucune action requise."
        else
            run_container
            echo "Conteneur $NAME mis à jour et créé avec succès."
        fi
        ;;
    start)
        docker start "$NAME"
        ;;
    stop)
        docker stop "$NAME"
        ;;
    restart)
        docker restart "$NAME"
        ;;
    *)
        echo "Usage: $0 {create|update|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/portainer
ln -sf /usr/local/bin/portainer /usr/local/bin/po
log "[+]" "Création de 'portainer'"

log "[*]" "Création de 'filebrowser'"
cat << 'EOF' > /usr/local/bin/filebrowser
#!/bin/sh
set -eu
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a

PATH_FILEBROWSER="${PATH_FILEBROWSER:-/media/Runable/Docker/Filebrowser}"
PORT_FILEBROWSER="${PORT_FILEBROWSER:-1006}"

NAME="filebrowser"
IMAGE="gtstef/filebrowser:latest"

mkdir -p "$PATH_FILEBROWSER/database" "$PATH_FILEBROWSER/config"

# Fonction mutualisée pour lancer le conteneur
run_container() {
    docker rm -f "$NAME" 2>/dev/null || true
    docker run -d \
        --name "$NAME" \
        --restart=unless-stopped \
        -e TZ=CET \
        -v "/media:/srv" \
        -v "$PATH_FILEBROWSER/database:/database" \
        -v "$PATH_FILEBROWSER/config:/config" \
        -p "$PORT_FILEBROWSER:80" \
        "$IMAGE"
}

case "$1" in
    create)
        docker pull "$IMAGE"
        run_container
        echo "Conteneur $NAME créé avec succès."
        ;;
    update)
        OLD_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        if ! docker pull "$IMAGE"; then
            echo "Erreur lors du téléchargement de l'image." >&2
            exit 1
        fi
        NEW_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        CONTAINER_EXISTS=$(docker ps -a -q -f name=^"$NAME"$ 2>/dev/null || echo "")
        
        if [ "$OLD_IMAGE_ID" = "$NEW_IMAGE_ID" ] && [ -n "$CONTAINER_EXISTS" ]; then
            echo "L'image est déjà à jour et le conteneur existe. Aucune action requise."
        else
            run_container
            echo "Conteneur $NAME mis à jour et créé avec succès."
        fi
        ;;
    start)
        docker start "$NAME"
        ;;
    stop)
        docker stop "$NAME"
        ;;
    restart)
        docker restart "$NAME"
        ;;
    *)
        echo "Usage: $0 {create|update|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/filebrowser
ln -sf /usr/local/bin/filebrowser /usr/local/bin/fb
log "[+]" "Création de 'filebrowser'"

log "[*]" "Création de 'freshrss'"
cat << 'EOF' > /usr/local/bin/freshrss
#!/bin/sh
set -eu
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a

PATH_FRESHRSS="${PATH_FRESHRSS:-/media/Runable/Docker/FreshRSS}"
PORT_FRESHRSS="${PORT_FRESHRSS:-1007}"

NAME="freshrss"
IMAGE="freshrss/freshrss:latest"

mkdir -p "$PATH_FRESHRSS/data" "$PATH_FRESHRSS/extensions"

# Fonction mutualisée pour lancer le conteneur
run_container() {
    docker rm -f "$NAME" 2>/dev/null || true
    docker run -d \
        --name "$NAME" \
        --restart=unless-stopped \
        -e TZ="Europe/Paris" \
        -e CRON_MIN="1,31" \
        -p "$PORT_FRESHRSS:80" \
        -v "$PATH_FRESHRSS/data:/var/www/FreshRSS/data" \
        -v "$PATH_FRESHRSS/extensions:/var/www/FreshRSS/extensions" \
        "$IMAGE"
}

case "$1" in
    create)
        docker pull "$IMAGE"
        run_container
        echo "Conteneur $NAME créé avec succès."
        ;;
    update)
        OLD_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        if ! docker pull "$IMAGE"; then
            echo "Erreur lors du téléchargement de l'image." >&2
            exit 1
        fi
        NEW_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        CONTAINER_EXISTS=$(docker ps -a -q -f name=^"$NAME"$ 2>/dev/null || echo "")
        
        if [ "$OLD_IMAGE_ID" = "$NEW_IMAGE_ID" ] && [ -n "$CONTAINER_EXISTS" ]; then
            echo "L'image est déjà à jour et le conteneur existe. Aucune action requise."
        else
            run_container
            echo "Conteneur $NAME mis à jour et créé avec succès."
        fi
        ;;
    start)
        docker start "$NAME"
        ;;
    stop)
        docker stop "$NAME"
        ;;
    restart)
        docker restart "$NAME"
        ;;
    *)
        echo "Usage: $0 {create|update|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/freshrss
ln -sf /usr/local/bin/freshrss /usr/local/bin/fr
log "[+]" "Création de 'freshrss'"

log "[*]" "Création de 'mqtt'"
cat << 'EOF' > /usr/local/bin/mqtt
#!/bin/sh
set -eu
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a

PATH_MQTT="${PATH_MQTT:-/media/Runable/Docker/MQTT}"
PORT_MQTT="${PORT_MQTT:-1015}"
USERNAME_GENERAL="${USERNAME_GENERAL:-admin}"
PASSWORD_GENERAL_HIGH="${PASSWORD_GENERAL_HIGH:-administrateur}"

NAME="mqtt"
IMAGE="eclipse-mosquitto:latest"

mkdir -p "$PATH_MQTT/config" "$PATH_MQTT/data"

# Fonction mutualisée pour lancer le conteneur
run_container() {
    docker rm -f "$NAME" mstt 2>/dev/null || true
    docker run -d \
        --name "$NAME" \
        --restart=unless-stopped \
        -e TZ=CET \
        -v "$PATH_MQTT/config:/mosquitto/config" \
        -v "$PATH_MQTT/data:/mosquitto/data" \
        -p "$PORT_MQTT:1883" \
        -p 9001:9001 \
        "$IMAGE"
}

# Fonction mutualisée pour configurer le mot de passe utilisateur MQTT
setup_password() {
    sleep 2 # Laisse le temps au conteneur de s'initialiser
    docker exec "$NAME" sh -c "mosquitto_passwd -b /mosquitto/config/password.txt $USERNAME_GENERAL $PASSWORD_GENERAL_HIGH" 2>/dev/null || true
}

case "$1" in
    create)
        docker pull "$IMAGE"
        run_container
        setup_password
        echo "Conteneur $NAME créé et configuré avec succès."
        ;;
    update)
        OLD_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        if ! docker pull "$IMAGE"; then
            echo "Erreur lors du téléchargement de l'image." >&2
            exit 1
        fi
        NEW_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        CONTAINER_EXISTS=$(docker ps -a -q -f name=^"$NAME"$ 2>/dev/null || echo "")
        
        if [ "$OLD_IMAGE_ID" = "$NEW_IMAGE_ID" ] && [ -n "$CONTAINER_EXISTS" ]; then
            echo "L'image est déjà à jour et le conteneur existe. Aucune action requise."
        else
            run_container
            setup_password
            echo "Conteneur $NAME mis à jour et configuré avec succès."
        fi
        ;;
    start)
        docker start "$NAME"
        ;;
    stop)
        docker stop "$NAME"
        ;;
    restart)
        docker restart "$NAME"
        ;;
    *)
        echo "Usage: $0 {create|update|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/mqtt
ln -sf /usr/local/bin/mqtt /usr/local/bin/mq
log "[+]" "Création de 'mqtt'"

log "[*]" "Création de 'gitea'"
cat << 'EOF' > /usr/local/bin/gitea
#!/bin/sh
set -eu
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a

PATH_GITEA="${PATH_GITEA:-/media/Runable/Docker/Gitea}"
PORT_GITEA="${PORT_GITEA:-1010}"

NAME="gitea"
IMAGE="gitea/gitea:latest"

mkdir -p "$PATH_GITEA"

# Fonction mutualisée pour lancer le conteneur
run_container() {
    docker rm -f "$NAME" 2>/dev/null || true
    docker run -d \
        --name "$NAME" \
        --restart=unless-stopped \
        -p "$PORT_GITEA:3000" \
        -p 2222:22 \
        -v "$PATH_GITEA:/data" \
        -v /etc/timezone:/etc/timezone:ro \
        -v /etc/localtime:/etc/localtime:ro \
        "$IMAGE"
}

case "$1" in
    create)
        docker pull "$IMAGE"
        run_container
        echo "Conteneur $NAME créé avec succès."
        ;;
    update)
        OLD_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        if ! docker pull "$IMAGE"; then
            echo "Erreur lors du téléchargement de l'image." >&2
            exit 1
        fi
        NEW_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        CONTAINER_EXISTS=$(docker ps -a -q -f name=^"$NAME"$ 2>/dev/null || echo "")
        
        if [ "$OLD_IMAGE_ID" = "$NEW_IMAGE_ID" ] && [ -n "$CONTAINER_EXISTS" ]; then
            echo "L'image est déjà à jour et le conteneur existe. Aucune action requise."
        else
            run_container
            echo "Conteneur $NAME mis à jour et créé avec succès."
        fi
        ;;
    start)
        docker start "$NAME"
        ;;
    stop)
        docker stop "$NAME"
        ;;
    restart)
        docker restart "$NAME"
        ;;
    *)
        echo "Usage: $0 {create|update|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/gitea
ln -sf /usr/local/bin/gitea /usr/local/bin/gt
log "[+]" "Création de 'gitea'"

log "[*]" "Création de 'siyuan'"
cat << 'EOF' > /usr/local/bin/siyuan
#!/bin/sh
set -eu
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a

PATH_SIYUAN="${PATH_SIYUAN:-/media/Runable/Docker/SiYuan}"
PORT_SIYUAN="${PORT_SIYUAN:-6806}"
PASSWORD_GENERAL_HIGH="${PASSWORD_GENERAL_HIGH:-password}"

NAME="siyuan"
IMAGE="b3log/siyuan:latest"

mkdir -p "$PATH_SIYUAN"

# Fonction mutualisée pour lancer le conteneur
run_container() {
    docker rm -f "$NAME" 2>/dev/null || true
    docker run -d \
        --name "$NAME" \
        --restart=unless-stopped \
        -v "$PATH_SIYUAN:/siyuan/workspace" \
        -p "$PORT_SIYUAN:6806" \
        -e PUID=1000 \
        -e PGID=1000 \
        "$IMAGE" \
        serve \
        --workspace=/siyuan/workspace \
        --accessAuthCode="$PASSWORD_GENERAL_HIGH"
}

case "$1" in
    create)
        docker pull "$IMAGE"
        run_container
        echo "Conteneur $NAME créé avec succès."
        ;;
    update)
        OLD_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        if ! docker pull "$IMAGE"; then
            echo "Erreur lors du téléchargement de l'image." >&2
            exit 1
        fi
        NEW_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        CONTAINER_EXISTS=$(docker ps -a -q -f name=^"$NAME"$ 2>/dev/null || echo "")
        
        if [ "$OLD_IMAGE_ID" = "$NEW_IMAGE_ID" ] && [ -n "$CONTAINER_EXISTS" ]; then
            echo "L'image est déjà à jour et le conteneur existe. Aucune action requise."
        else
            run_container
            echo "Conteneur $NAME mis à jour et créé avec succès."
        fi
        ;;
    start)
        docker start "$NAME"
        ;;
    stop)
        docker stop "$NAME"
        ;;
    restart)
        docker restart "$NAME"
        ;;
    *)
        echo "Usage: $0 {create|update|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/siyuan
ln -sf /usr/local/bin/siyuan /usr/local/bin/sy
log "[+]" "Création de 'siyuan'"

log "[*]" "Création de 'myelectricaldata'"
cat << 'EOF' > /usr/local/bin/myelectricaldata
#!/bin/sh
set -eu
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a

PATH_MED="${PATH_MED:-/media/Runable/Docker/MyElectricalData/config.yaml}"
PORT_MED="${PORT_MED:-5000}"

NAME="myelectricaldata"
IMAGE="m4dm4rtig4n/myelectricaldata:latest"

mkdir -p "$(dirname "$PATH_MED")"

# Fonction mutualisée pour lancer le conteneur
run_container() {
    docker rm -f med "$NAME" 2>/dev/null || true
    docker run -d \
        --name "$NAME" \
        --restart=unless-stopped \
        -p "$PORT_MED:5000" \
        -v "$PATH_MED:/data/config.yaml" \
        "$IMAGE"
}

case "$1" in
    create)
        docker pull "$IMAGE"
        run_container
        echo "Conteneur $NAME créé avec succès."
        ;;
    update)
        OLD_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        if ! docker pull "$IMAGE"; then
            echo "Erreur lors du téléchargement de l'image." >&2
            exit 1
        fi
        NEW_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        CONTAINER_EXISTS=$(docker ps -a -q -f name=^"$NAME"$ 2>/dev/null || echo "")
        
        if [ "$OLD_IMAGE_ID" = "$NEW_IMAGE_ID" ] && [ -n "$CONTAINER_EXISTS" ]; then
            echo "L'image est déjà à jour et le conteneur existe. Aucune action requise."
        else
            run_container
            echo "Conteneur $NAME mis à jour et créé avec succès."
        fi
        ;;
    start)
        docker start "$NAME"
        ;;
    stop)
        docker stop "$NAME"
        ;;
    restart)
        docker restart "$NAME"
        ;;
    *)
        echo "Usage: $0 {create|update|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/myelectricaldata
ln -sf /usr/local/bin/myelectricaldata /usr/local/bin/med
log "[+]" "Création de 'myelectricaldata'"

log "[*]" "Création de 'kiwix'"
cat << 'EOF' > /usr/local/bin/kiwix
#!/bin/sh
set -eu
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a

PATH_KIWIX="${PATH_KIWIX:-/media/Docs01/Kiwix}"
PORT_KIWIX="${PORT_KIWIX:-1011}"

NAME="kiwix"
IMAGE="ghcr.io/kiwix/kiwix-serve:latest"

mkdir -p "$PATH_KIWIX"

# Fonction mutualisée pour lancer le conteneur
run_container() {
    docker rm -f "$NAME" 2>/dev/null || true
    docker run -d \
        --name "$NAME" \
        --restart=unless-stopped \
        -p "$PORT_KIWIX:8080" \
        -v "$PATH_KIWIX:/data" \
        "$IMAGE" \
        /data/*.zim
}

case "$1" in
    create)
        docker pull "$IMAGE"
        run_container
        echo "Conteneur $NAME créé avec succès."
        ;;
    update)
        OLD_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        if ! docker pull "$IMAGE"; then
            echo "Erreur lors du téléchargement de l'image." >&2
            exit 1
        fi
        NEW_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        CONTAINER_EXISTS=$(docker ps -a -q -f name=^"$NAME"$ 2>/dev/null || echo "")
        
        if [ "$OLD_IMAGE_ID" = "$NEW_IMAGE_ID" ] && [ -n "$CONTAINER_EXISTS" ]; then
            echo "L'image est déjà à jour et le conteneur existe. Aucune action requise."
        else
            run_container
            echo "Conteneur $NAME mis à jour et créé avec succès."
        fi
        ;;
    start)
        docker start "$NAME"
        ;;
    stop)
        docker stop "$NAME"
        ;;
    restart)
        docker restart "$NAME"
        ;;
    *)
        echo "Usage: $0 {create|update|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/kiwix
ln -sf /usr/local/bin/kiwix /usr/local/bin/kw
log "[+]" "Création de 'kiwix'"

log "[*]" "Création de 'kolibri'"
cat << 'EOF' > /usr/local/bin/kolibri
#!/bin/sh
set -eu
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a

PATH_KOLIBRI="${PATH_KOLIBRI:-/media/Runable/Docker/Kolibri}"
PORT_KOLIBRI="${PORT_KOLIBRI:-1012}"

NAME="kolibri"
IMAGE="learningequality/kolibri:latest"

mkdir -p "$PATH_KOLIBRI"

# Fonction mutualisée pour lancer le conteneur
run_container() {
    docker rm -f "$NAME" 2>/dev/null || true
    docker run -d \
        --name "$NAME" \
        --restart=unless-stopped \
        -p "$PORT_KOLIBRI:8080" \
        -v "$PATH_KOLIBRI:/kolibri" \
        "$IMAGE"
}

case "$1" in
    create)
        docker pull "$IMAGE"
        run_container
        echo "Conteneur $NAME créé avec succès."
        ;;
    update)
        OLD_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        if ! docker pull "$IMAGE"; then
            echo "Erreur lors du téléchargement de l'image." >&2
            exit 1
        fi
        NEW_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        CONTAINER_EXISTS=$(docker ps -a -q -f name=^"$NAME"$ 2>/dev/null || echo "")
        
        if [ "$OLD_IMAGE_ID" = "$NEW_IMAGE_ID" ] && [ -n "$CONTAINER_EXISTS" ]; then
            echo "L'image est déjà à jour et le conteneur existe. Aucune action requise."
        else
            run_container
            echo "Conteneur $NAME mis à jour et créé avec succès."
        fi
        ;;
    start)
        docker start "$NAME"
        ;;
    stop)
        docker stop "$NAME"
        ;;
    restart)
        docker restart "$NAME"
        ;;
    *)
        echo "Usage: $0 {create|update|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/kolibri
ln -sf /usr/local/bin/kolibri /usr/local/bin/kb
log "[+]" "Création de 'kolibri'"

log "[*]" "Création de 'cyberchef'"
cat << 'EOF' > /usr/local/bin/cyberchef
#!/bin/sh
set -eu
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a

PORT_CYBERCHEF="${PORT_CYBERCHEF:-8000}"

NAME="cyberchef"
IMAGE="mpepping/cyberchef:latest"

# Fonction mutualisée pour lancer le conteneur
run_container() {
    docker rm -f "$NAME" 2>/dev/null || true
    docker run -d \
        --name "$NAME" \
        --restart=unless-stopped \
        -p "$PORT_CYBERCHEF:8000" \
        "$IMAGE"
}

case "$1" in
    create)
        docker pull "$IMAGE"
        run_container
        echo "Conteneur $NAME créé avec succès."
        ;;
    update)
        OLD_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        if ! docker pull "$IMAGE"; then
            echo "Erreur lors du téléchargement de l'image." >&2
            exit 1
        fi
        NEW_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        CONTAINER_EXISTS=$(docker ps -a -q -f name=^"$NAME"$ 2>/dev/null || echo "")
        
        if [ "$OLD_IMAGE_ID" = "$NEW_IMAGE_ID" ] && [ -n "$CONTAINER_EXISTS" ]; then
            echo "L'image est déjà à jour et le conteneur existe. Aucune action requise."
        else
            run_container
            echo "Conteneur $NAME mis à jour et créé avec succès."
        fi
        ;;
    start)
        docker start "$NAME"
        ;;
    stop)
        docker stop "$NAME"
        ;;
    restart)
        docker restart "$NAME"
        ;;
    *)
        echo "Usage: $0 {create|update|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/cyberchef
ln -sf /usr/local/bin/cyberchef /usr/local/bin/cc
log "[+]" "Création de 'cyberchef'"

log "[*]" "Création de 'vaultwarden'"
cat << 'EOF' > /usr/local/bin/vaultwarden
#!/bin/sh
set -eu
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a

PATH_VAULTWARDEN="${PATH_VAULTWARDEN:-/media/Runable/Docker/Vaultwarden}"
PORT_VAULTWARDEN="${PORT_VAULTWARDEN:-1013}"

NAME="vaultwarden"
IMAGE="vaultwarden/server:latest"

mkdir -p "$PATH_VAULTWARDEN/ssl"

# Fonction mutualisée pour générer le certificat SSL si nécessaire
setup_ssl() {
    if [ ! -f "$PATH_VAULTWARDEN/ssl/vaultwarden.crt" ] || [ ! -f "$PATH_VAULTWARDEN/ssl/vaultwarden.key" ]; then
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout "$PATH_VAULTWARDEN/ssl/vaultwarden.key" \
            -out "$PATH_VAULTWARDEN/ssl/vaultwarden.crt" \
            -subj "/CN=domonas.local/O=DomoNas/C=FR" 2>/dev/null
    fi
}

# Fonction mutualisée pour lancer le conteneur
run_container() {
    setup_ssl
    docker rm -f "$NAME" 2>/dev/null || true
    docker run -d \
        --name "$NAME" \
        -e WEBSOCKET_ENABLED=true \
        -e ROCKET_TLS='{certs="/data/ssl/vaultwarden.crt",key="/data/ssl/vaultwarden.key"}' \
        -v "$PATH_VAULTWARDEN:/data" \
        -p "$PORT_VAULTWARDEN:80" \
        -p 3012:3012 \
        --restart unless-stopped \
        "$IMAGE"
}

case "$1" in
    create)
        docker pull "$IMAGE"
        run_container
        echo "Conteneur $NAME créé avec succès."
        ;;
    update)
        OLD_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        if ! docker pull "$IMAGE"; then
            echo "Erreur lors du téléchargement de l'image." >&2
            exit 1
        fi
        NEW_IMAGE_ID=$(docker images -q "$IMAGE" 2>/dev/null || echo "")
        CONTAINER_EXISTS=$(docker ps -a -q -f name=^"$NAME"$ 2>/dev/null || echo "")
        
        if [ "$OLD_IMAGE_ID" = "$NEW_IMAGE_ID" ] && [ -n "$CONTAINER_EXISTS" ]; then
            echo "L'image est déjà à jour et le conteneur existe. Aucune action requise."
        else
            run_container
            echo "Conteneur $NAME mis à jour et créé avec succès."
        fi
        ;;
    start)
        docker start "$NAME"
        ;;
    stop)
        docker stop "$NAME"
        ;;
    restart)
        docker restart "$NAME"
        ;;
    *)
        echo "Usage: $0 {create|update|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/vaultwarden
ln -sf /usr/local/bin/vaultwarden /usr/local/bin/vw
log "[+]" "Création de 'vaultwarden'"

log "[*]" "Création de 'immich'"
cat << 'EOF' > /usr/local/bin/immich
#!/bin/sh
set -eu
set -a
. "/etc/DomoNas/Credentials/credentials.env"
set +a

PATH_IMMICH="${PATH_IMMICH:-/media/Runable/Docker/Immich}"
PORT_IMMICH="${PORT_IMMICH:-1016}"
USERNAME_GENERAL="${USERNAME_GENERAL:-admin}"
PASSWORD_GENERAL_LOW="${PASSWORD_GENERAL_LOW:-administrateur}"

IMAGE_PG="ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0"
IMAGE_REDIS="docker.io/valkey/valkey:8"
IMAGE_SERVER="ghcr.io/immich-app/immich-server:release"

mkdir -p "$PATH_IMMICH/postgres" "$PATH_IMMICH/data"

# Fonction pour créer le réseau si absent
create_network() {
    docker network create immich_net 2>/dev/null || true
}

# Fonction mutualisée pour lancer la stack Immich
run_containers() {
    create_network
    docker rm -f immich_server immich_redis immich_postgres 2>/dev/null || true

    # 1. Postgres
    docker run -d \
        --name immich_postgres \
        --restart unless-stopped \
        --network immich_net \
        -e POSTGRES_USER="$USERNAME_GENERAL" \
        -e POSTGRES_PASSWORD="$PASSWORD_GENERAL_LOW" \
        -e POSTGRES_DB=immich \
        -e POSTGRES_INITDB_ARGS="--data-checksums" \
        -v "$PATH_IMMICH/postgres:/var/lib/postgresql/data" \
        "$IMAGE_PG"

    # 2. Redis (Valkey)
    docker run -d \
        --name immich_redis \
        --restart unless-stopped \
        --network immich_net \
        "$IMAGE_REDIS"

    # 3. Server
    docker run -d \
        --name immich_server \
        --restart unless-stopped \
        -p "$PORT_IMMICH:2283" \
        --network immich_net \
        -v "$PATH_IMMICH/data:/usr/src/app/upload" \
        -e DB_HOSTNAME=immich_postgres \
        -e DB_USERNAME="$USERNAME_GENERAL" \
        -e DB_PASSWORD="$PASSWORD_GENERAL_LOW" \
        -e DB_DATABASE_NAME=immich \
        -e REDIS_HOSTNAME=immich_redis \
        -e IMMICH_MACHINE_LEARNING_ENABLED=false \
        -v /etc/localtime:/etc/localtime:ro \
        "$IMAGE_SERVER"
}

case "$1" in
    create)
        echo "Téléchargement des images de la stack Immich..."
        docker pull "$IMAGE_PG"
        docker pull "$IMAGE_REDIS"
        docker pull "$IMAGE_SERVER"
        run_containers
        echo "Stack Immich créée avec succès."
        ;;
    update)
        OLD_PG_ID=$(docker images -q "$IMAGE_PG" 2>/dev/null || echo "")
        OLD_REDIS_ID=$(docker images -q "$IMAGE_REDIS" 2>/dev/null || echo "")
        OLD_SERVER_ID=$(docker images -q "$IMAGE_SERVER" 2>/dev/null || echo "")

        if ! docker pull "$IMAGE_PG" || ! docker pull "$IMAGE_REDIS" || ! docker pull "$IMAGE_SERVER"; then
            echo "Erreur lors du téléchargement des images Immich." >&2
            exit 1
        fi

        NEW_PG_ID=$(docker images -q "$IMAGE_PG" 2>/dev/null || echo "")
        NEW_REDIS_ID=$(docker images -q "$IMAGE_REDIS" 2>/dev/null || echo "")
        NEW_SERVER_ID=$(docker images -q "$IMAGE_SERVER" 2>/dev/null || echo "")

        SERVER_EXISTS=$(docker ps -a -q -f name=^immich_server$ 2>/dev/null || echo "")

        if [ "$OLD_PG_ID" = "$NEW_PG_ID" ] && [ "$OLD_REDIS_ID" = "$NEW_REDIS_ID" ] && [ "$OLD_SERVER_ID" = "$NEW_SERVER_ID" ] && [ -n "$SERVER_EXISTS" ]; then
            echo "Les images d'Immich sont déjà à jour et les conteneurs existent. Aucune action requise."
        else
            echo "Mise à jour des conteneurs Immich..."
            run_containers
            echo "Stack Immich mise à jour avec succès."
        fi
        ;;
    start)
        docker start immich_postgres immich_redis immich_server
        ;;
    stop)
        docker stop immich_server immich_redis immich_postgres
        ;;
    restart)
        docker restart immich_postgres immich_redis immich_server
        ;;
    *)
        echo "Usage: $0 {create|update|start|stop|restart}"
        exit 1
        ;;
esac
EOF
chmod +x /usr/local/bin/immich
ln -sf /usr/local/bin/immich /usr/local/bin/im
log "[+]" "Création de 'immich'"

log "[*]" "Vérification de l'état des conteneurs Docker..."
SERVICES="lamp homeassistant jellyfin downbox seedbox grocy portainer filebrowser freshrss mqtt gitea siyuan myelectricaldata kiwix kolibri cyberchef vaultwarden"
for srv in $SERVICES; do
    if [ -x "/usr/local/bin/$srv" ]; then
        container_name="$srv"
        [ "$srv" = "downbox" ] && container_name="downbox"
        [ "$srv" = "myelectricaldata" ] && container_name="myelectricaldata"
        [ "$srv" = "mqtt" ] && container_name="mqtt"
        [ "$srv" = "immich" ] && container_name="immich"
        if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
            log "[*]" "Le conteneur '$container_name' est déjà actif."
        else
            log "[!]" "Le conteneur '$container_name' est arrêté ou absent. Lancement via '$srv create'..."
            if "/usr/local/bin/$srv" update > /dev/null 2>&1; then
                log "[+]" "Service '$srv' initialisé et lancé avec succès."
            else
                log "[-]" "Échec lors de l'initialisation du service '$srv'."
            fi
        fi
    fi
done
log "[+]" "Tous les services Docker ont été vérifiés et lancés."
log "[*]" "Nettoyage des images Docker inutilisées"
if docker image prune -f >/dev/null 2>&1; then
    log "[+]" "Nettoyage des images Docker inutilisées"
else
    log "[-]" "Nettoyage des images Docker inutilisées"
fi
log "[E]" "Fin du programme"
