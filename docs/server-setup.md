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

## 8. Восстановление и проверка

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

Ожидается 6 успешных проверок, 0 ошибок, код 0.
Для отрицательного теста временно установить MaxAuthTries 10 в drop-in-файле и снова запустить аудит: код 1.
После теста вернуть 3 и проверить `sudo sshd -t`, затем выполнить перезапуск SSH и аудит с кодом 0.
Для проверки самого аудита перезапуск службы при значении 10 не нужен: `sshd -T` читает конфигурацию с диска.
