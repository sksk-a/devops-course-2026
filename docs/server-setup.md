# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины

Oracle VirtualBox 7.2.20; Ubuntu Server 24.04.5 LTS AMD64 (обычная редакция Server, без графического рабочего стола).
ОЗУ — 2048 МБ, процессоры — 2, диск — динамический VDI 25 ГБ.
Имя ВМ и узла — `devops-vm`. Ядро после установки — `6.8.0-147-generic`.

При загрузке установочной среды с двумя ядрами наблюдались зависания и сообщение `watchdog: BUG: soft lockup`.
VirtualBox работает через NEM при активном гипервизоре Windows. Установка выполнена с одним ядром.
В гостевой системе задан `GRUB_CMDLINE_LINUX_DEFAULT="clocksource=acpi_pm"` в `/etc/default/grub` и выполнен `sudo update-grub`.
Фактический источник времени после загрузки: `acpi_pm`.
Параметры Windows для устранения проблемы не менялись.

## 2. Сетевые интерфейсы

| Интерфейс | Режим | Адрес | Назначение |
|---|---|---|---|
| enp0s3 | NAT | 10.0.2.15/24, DHCP | Репозитории пакетов и исходящие соединения |
| enp0s8 | Host-only | 192.168.56.104/24, DHCP | Прямой доступ с Windows к серверу |

Хостовой адаптер Windows: `VirtualBox Host-Only Ethernet Adapter`, адрес `192.168.56.1/24`.
DHCP-сервер VirtualBox: `192.168.56.100`, диапазон `192.168.56.101–192.168.56.254`.
Маршруты DHCP для Host-only отключены (`dhcp4-overrides: {use-routes: false}`); маршрут в Интернет проходит через NAT.
При смене DHCP-адреса обновить запись `devops.local` в Windows hosts.

Проверка:

```bash
ip -brief address
ip route
```

## 3. Правило проброса портов

Название `ssh`, протокол TCP, адрес хоста `127.0.0.1`, порт хоста `2222`.
На чистой установке гостевой порт равен `22`; после усиления защиты — `2222`.
Адрес гостя в правиле не задан.

Изменение правила работающей ВМ из PowerShell, если VirtualBox установлен в `D:\VirtualBox`:

```powershell
& 'D:/VirtualBox/VBoxManage.exe' controlvm devops-vm natpf1 delete ssh
& 'D:/VirtualBox/VBoxManage.exe' controlvm devops-vm natpf1 'ssh,tcp,127.0.0.1,2222,,2222'
```

## 4. Учётные записи

`student` — исходная учётная запись установщика, UID 1000, участник группы sudo, парольный вход в консоли.
`devops` — отдельная административная учётная запись, UID 1001, группы devops, sudo и users.
Доступ `devops` по SSH выполняется с отдельным ключом Ed25519 `~/.ssh/devops_vm` на хосте.
Закрытый ключ не хранится на сервере и не добавляется в репозиторий.
Пароли учётных записей переданы отдельно и в этот документ не включены.

На сервере: `/home/devops/.ssh` — 700; `/home/devops/.ssh/authorized_keys` — 600; владелец обоих — devops.
Вход root и student по SSH запрещён `AllowUsers devops` и `PermitRootLogin no`.

В Windows `C:\Users\Redmi\.ssh\config` сохранена ранее существовавшая конфигурация GitVerse и добавлены блоки:

```sshconfig
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes

Host devops.local
    HostName devops.local
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

Перед первым доверием ключу сервера сверить отпечаток с консолью ВМ:

```bash
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

Известный отпечаток сервера после установки: `SHA256:ubdXAE0PSr3oDnjKZl1/TT1Ni9et6t77JSbmF5YYu6U`.
Запись клиента хранится в `~/.ssh/known_hosts`; смену ключа при переустановке сначала проверить по доверенной консоли.

## 5. Служба SSH

Основной файл `/etc/ssh/sshd_config` не изменён; копия — `/etc/ssh/sshd_config.backup`.
Изменения заданы в `/etc/ssh/sshd_config.d/99-hardening.conf`:

```text
Port 2222
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

Конфликтующее раннее `PasswordAuthentication yes` в drop-in-файлах закомментировано.
OpenSSH использует первое найденное значение параметра; префикс 99 сам по себе не гарантирует переопределения.
`KbdInteractiveAuthentication no` явно отключает альтернативный интерактивный способ ввода пароля.

Активация по сокету отключена, используется служба:

```bash
sudo sshd -t
sudo sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers) '
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh.service
sudo ss -tlnp | grep sshd
```

При изменении конфигурации держать действующую SSH-сессию открытой до успешного входа во второй сессии.
Ожидаемый слушающий порт — `2222`, парольный вход и вход root должны отклоняться.

## 6. Правила межсетевого экрана

UFW активен. Политики: deny incoming, allow outgoing; маршрутизация отключена (disabled routed).
Правила IPv4 и IPv6: LIMIT 2222/tcp, ALLOW 80/tcp, ALLOW 443/tcp.
Журналирование medium; журнал `/var/log/ufw.log`.

Начальная безопасная активация:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 2222/tcp comment 'SSH'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw enable
# Проверить новое SSH-соединение, не закрывая старое.
sudo ufw delete allow 2222/tcp
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw logging medium
sudo ufw status verbose
```

`ufw allow ssh` использовать нельзя: имя ssh соответствует порту 22 из `/etc/services`.
Много новых SSH-соединений подряд может вызвать временную блокировку источника правилом LIMIT.
Проверка блокировки закрытого порта из Windows: `curl.exe -m 3 http://192.168.56.104:8080`.
На сервере: `sudo grep 'UFW BLOCK' /var/log/ufw.log | tail -5`.

## 7. Снимки состояния

- `01-clean-install` — установленная и обновлённая ОС с исходной учётной записью student и SSH на порту 22, до создания devops.
- `02-keys-configured` — создан devops, настроен вход по ключу и проверены права 700/600, до усиления защиты SSH.
- `03-ssh-hardened` — подтверждены новый порт, запрет root и паролей; UFW на этом этапе ещё не активирован.

Снимок фиксирует также параметры ВМ. После отката на `01-clean-install` проверить, что правило NAT снова указывает на гостевой порт 22.
Конфигурация Windows, ключи клиента и запись hosts откатом ВМ не восстанавливаются.

## 8. Веб-сервер

Пакеты: `sudo apt install nginx rsync`. Сайт: `https://devops.local/`.
Конфигурация: `/etc/nginx/sites-available/devops-site`, символическая ссылка
в `sites-enabled`; ссылка `sites-enabled/default` удалена. Корень сайта:
`/var/www/devops-site`, владелец `devops:devops`, каталоги 755, файлы 644.
Рабочие процессы `www-data` читают файлы, но не изменяют их.

Самоподписанный сертификат создан на 365 дней:

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key -out /etc/ssl/certs/devops.crt \
  -subj '/CN=devops.local' -addext 'subjectAltName=DNS:devops.local'
sudo chmod 600 /etc/ssl/private/devops.key
sudo chmod 644 /etc/ssl/certs/devops.crt
```

Владелец обоих файлов root. Закрытый ключ читает главный процесс Nginx.
Срок сертификата: 29.10.2026–29.10.2027. Публичная копия сертификата
в `certs/devops.crt` получена через SCP с проверенным SSH-ключом сервера.
Закрытый ключ хранится только на ВМ.

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name devops.local;
    access_log /var/log/nginx/devops-site.access.log;
    return 301 https://$host$request_uri;
}
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name devops.local;
    root /var/www/devops-site;
    index index.html;
    ssl_certificate /etc/ssl/certs/devops.crt;
    ssl_certificate_key /etc/ssl/private/devops.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    location / { try_files $uri $uri/ =404; }
    error_page 404 /404.html;
    access_log /var/log/nginx/devops-site.access.log;
    error_log /var/log/nginx/devops-site.error.log;
}
```

После изменений: `sudo nginx -t && sudo systemctl reload nginx`.
Снимок `04-nginx-https` сохраняет HTTPS перед доставкой сайта.

На клиенте нужны Bash, Git, rsync, OpenSSH и curl. Для Windows использованы
Bash, rsync и OpenSSH из MSYS2, Git и curl из Git for Windows, без WSL.
Для переносимого комплекта MSYS2 заданы HOME и `db_home: windows`
в `etc/nsswitch.conf`. Алиас `devops` использует ключ,
порт 2222 и проверенный known_hosts. Запуск из любого каталога репозитория:

```bash
scripts/deploy.sh --dry-run
scripts/deploy.sh
curl --cacert certs/devops.crt https://devops.local/
```

Скрипт требует чистое рабочее дерево и `site/index.html`, использует одно
SSH-соединение rsync, зеркалирует `site/` через `--delete --chmod=D755,F644`.
После доставки проверяет HTTPS без `-k`; при ошибках возвращает 1.
Перед доставкой изменённые файлы нужно закоммитить. `--dry-run` ничего
не меняет на сервере и не выполняет HTTP-проверку.

Проверены пять сценариев: dry-run (0, хеши файлов не изменились),
закоммиченная версия (0), грязное дерево (1), остановленный Nginx (1),
переименованный и закоммиченный index.html в отдельной тестовой копии (1).
После тестов Nginx запущен, штатный деплой восстановил сайт.
Права каталога 755/750/744/711 дали HTTP 200/403/403/200;
файл 600 дал 403. Небезопасная доставка 666 без `--chmod` воспроизведена
из временного Linux-каталога на ВМ: Windows не изменила исходный режим 644.
Запись от www-data удалась только при 666; после штатного деплоя запрещена.
Аудит обнаружил world-writable файл и искусственно увеличенный срок
проверки сертификата (оба раза код 1); итоговый аудит: 10/10, код 0.

Для подготовки к ПР7 установлен Docker Engine Community из официального
APT-репозитория https://docs.docker.com/engine/install/ubuntu/.
Установлены docker-ce, docker-ce-cli, containerd.io, docker-buildx-plugin,
docker-compose-plugin. Пользователь devops добавлен в docker;
`docker run --rm hello-world` выполнен без sudo. Контейнерные порты не публиковались.

## 9. Контейнеризация

Docker Engine Community 29.9.2 и Compose v5.6.1 установлены из официального
APT-репозитория Docker; пакет docker.io не используется. В группе docker
состоит devops (также имеет sudo); членство фактически предоставляет root.

Если Docker ещё не установлен, на Ubuntu 24.04 выполнить:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable' | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker devops
```

Начать новую SSH-сессию. Проект хранится в `/home/devops/app`.
Исходники из `app/` доставляются с хоста (сначала добавить `--dry-run`):

```bash
rsync -avz --delete --exclude=.env app/ devops:app/
```

На сервере, от devops, сформировать секрет только при первом развёртывании:

```bash
cd ~/app
umask 077
{ printf 'POSTGRES_DB=app\nPOSTGRES_USER=app\nPOSTGRES_PASSWORD='; openssl rand -hex 16; printf 'DB_HOST=db\n'; } > .env
chmod 600 .env
docker compose up -d --build --wait
```

`/home/devops/app/.env`: devops:devops, 600. При повторном деплое не
перезаписывать .env: смена пароля не меняет пароль уже созданной БД.
Файл отсутствует в Git и исключён из Docker-контекста и rsync; в репозитории
хранится только .env.example с заглушкой. Не выводить секрет в отчёт.

Dockerfile и docker-compose.yml находятся в `app/` репозитория.
Образ devops-app:1.0 основан на python:3.12-slim; Gunicorn работает
от app (UID 999), код принадлежит root и имеет 644. PostgreSQL:
postgres:16-alpine, контейнер app-db-1, healthcheck pg_isready.
Приложение app-app-1 ждёт service_healthy. Сеть app_backend, DNS-имя БД db.
Именованный том app_db_data подключён к /var/lib/postgresql/data.
Публикация приложения: только 127.0.0.1:5000:5000; 5432 не опубликован.
Обычный compose down сохраняет том. Флаг -v удаляет данные; для штатной
остановки и восстановления не применять. Снимок: 05-docker-compose.

В HTTPS-блок /etc/nginx/sites-available/devops-site добавлено:

```nginx
location /app/ {
    proxy_pass http://127.0.0.1:5000/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

Статический root и location / сохранены. Применение:
`sudo nginx -t && sudo systemctl reload nginx`.
Проверки: `curl --cacert certs/devops.crt https://devops.local/app/health`
с хоста, `docker compose ps`, `docker compose exec -T app id`,
`ss -tln`, `scripts/audit.sh` (14 проверок, код 0).
Отказ приложения даёт 502 и connect() failed в журнале Nginx.
Тест публикации на всех адресах даёт ошибку аудита; штатный адрес восстановлен.

## 10. Восстановление и проверка

После отката на `01-clean-install` войти через консоль или с хоста:

```bash
ssh -i ~/.ssh/devops_vm -p 2222 student@127.0.0.1
sudo adduser devops
sudo usermod -aG sudo devops
sudo install -d -m 700 -o devops -g devops /home/devops/.ssh
sudo install -m 600 -o devops -g devops /home/student/.ssh/authorized_keys /home/devops/.ssh/authorized_keys
groups devops
```

В исходном снимке ключ клиента присутствует у student как ключ первоначального доступа.
Создав devops, проверить отдельный вход `ssh devops` и права файлов.
Затем повторить раздел 5, обновить NAT и подтвердить новый вход, после чего применить раздел 6.

Имя на хосте Windows (редактировать hosts с правами администратора):

```text
192.168.56.104 devops.local
```

Полное имя гостя:

```bash
sudo hostnamectl set-hostname devops-vm
sudo sed -i 's/^127.0.1.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts
hostname -f
```

Восстановить `scripts/audit.sh` из этого репозитория и выполнить на сервере:

```bash
chmod +x scripts/audit.sh
sudo -v
./scripts/audit.sh
echo $?
```

До установки веб-сервера в версии ПР5 ожидается 6 успешных проверок.
После настройки веб-сервера версия ПР6 выполняет 10 проверок.
После контейнеризации текущий аудит выполняет 14 проверок: код 0 при отсутствии ошибок.
Для отрицательного теста временно установить MaxAuthTries 10 в drop-in-файле и снова запустить аудит: код 1.
После теста вернуть 3 и проверить `sudo sshd -t`, затем выполнить перезапуск SSH и аудит с кодом 0.
Для проверки самого аудита перезапуск службы при значении 10 не нужен: `sshd -T` читает конфигурацию с диска.
