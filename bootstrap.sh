
#!/usr/bin/env bash
set -Eeuo pipefail


PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

if [[ ! -f Dockerfile || ! -f script.sh ]]; then
echo "Ошибка: в каталоге проекта должны быть Dockerfile и script.sh."
exit 1
fi

echo "-- Установка необходимых пакетов"
sudo apt-get update
sudo apt-get install -y docker.io nginx mdadm lvm2 openssl curl

sudo systemctl enable --now docker
sudo systemctl enable --now nginx

echo "-- Сборка Docker-образа"
sudo docker build -t my-script .

echo "-- Настройка RAID1"
sudo mkdir -p /mnt/raid-lab /mnt/raid

if ! sudo mdadm --detail /dev/md0 >/dev/null 2>&1; then
for disk in disk1.img disk2.img; do
if [[ ! -f "/mnt/raid-lab/$disk" ]]; then
sudo fallocate -l 512M "/mnt/raid-lab/$disk"
fi
done

LOOP1="$(sudo losetup --find --show /mnt/raid-lab/disk1.img)"
LOOP2="$(sudo losetup --find --show /mnt/raid-lab/disk2.img)"

if sudo wipefs -n "$LOOP1" | grep -q . || sudo wipefs -n "$LOOP2" | grep -q .; then
echo "Обнаружены сигнатуры на loop-дисках"
exit 1
fi

sudo mdadm --create /dev/md0 --metadata=1.2 \
--level=1 --raid-devices=2 "$LOOP1" "$LOOP2" --run
sudo mkfs.ext4 -F /dev/md0
fi

if ! mountpoint -q /mnt/raid; then
sudo mount /dev/md0 /mnt/raid
fi

echo "-- Настройка LVM"
sudo mkdir -p /mnt/logs /mnt/raid-lab

if ! sudo vgs vg_data >/dev/null 2>&1; then
if [[ ! -f /mnt/raid-lab/disk3.img ]]; then
sudo fallocate -l 512M /mnt/raid-lab/disk3.img
fi

LOOP3="$(sudo losetup --find --show /mnt/raid-lab/disk3.img)"

if sudo wipefs -n "$LOOP3" | grep -q .; then
echo "Обнаружены сигнатуры на диске LVM"
exit 1
fi

sudo pvcreate "$LOOP3"
sudo vgcreate vg_data "$LOOP3"
sudo lvcreate -L 300M -n lv_logs vg_data
sudo mkfs.ext4 /dev/vg_data/lv_logs
fi

if ! mountpoint -q /mnt/logs; then
sudo mount /dev/vg_data/lv_logs /mnt/logs
fi

echo "-- Запуск контейнера"
if sudo docker container inspect my-app >/dev/null 2>&1; then
    sudo docker rm -f my-app
fi

sudo docker run -d --name my-app \
    --restart unless-stopped \
    -p 127.0.0.1:8080:8080 \
    my-script

echo "-- Настройка TLS-сертификата"
if [[ ! -f /etc/ssl/certs/my-app.crt || ! -f /etc/ssl/private/my-app.key ]]; then
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
-keyout /etc/ssl/private/my-app.key \
-out /etc/ssl/certs/my-app.crt \
-subj "/CN=my-app.local"
sudo chmod 600 /etc/ssl/private/my-app.key
fi

echo "-- Настройка Nginx"
sudo tee /etc/nginx/sites-available/my-app >/dev/null <<'NGINX'
server {
listen 80;
server_name _;
return 301 https://$host$request_uri;
}

server {
listen 443 ssl;
server_name _;

ssl_certificate /etc/ssl/certs/my-app.crt;
ssl_certificate_key /etc/ssl/private/my-app.key;

location / {
proxy_pass http://127.0.0.1:8080;
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
}
}
NGINX

sudo ln -sfn /etc/nginx/sites-available/my-app /etc/nginx/sites-enabled/my-app
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx

echo "-- Настройка systemd"
sudo tee /etc/systemd/system/my-app.service >/dev/null <<'UNIT'
[Unit]
Description=My Docker monitoring application
Requires=docker.service
After=docker.service

[Service]
Type=simple
ExecStart=/usr/bin/docker start -a my-app
ExecStop=/usr/bin/docker stop -t 10 my-app
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable my-app

sudo docker stop my-app >/dev/null 2>&1 || true
sudo systemctl restart my-app
sleep 3

echo "-- Проверка"
sudo systemctl --no-pager --full status my-app
sudo nginx -t
curl -kI https://127.0.0.1/monitor.log

echo
echo "Развёртывание завершено успешно"
echo "Проверка RAID: cat /proc/mdstat"
echo "Проверка LVM: sudo lvs && df -h /mnt/logs"
echo "Логи службы: sudo journalctl -u my-app -n 30 --no-pager"

