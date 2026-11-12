#!/usr/bin/env bash
# Установка панели nodepanel одной командой (Ubuntu/Debian, systemd, root).
#
#   bash install.sh [--domain sub.example.com] [--binary ./nodepanel | --url https://…/nodepanel-linux-amd64 --sha256 …]
#                   [--email you@example.com] [--port 31234] [--sni www.microsoft.com] [--no-upgrade]
#
# Без --domain используется бесплатное имя <IP-через-дефисы>.sslip.io — оно указывает на этот сервер,
# и Let's Encrypt выдаёт на него настоящий сертификат (браузер не ругается).
# Сначала обновляется система (apt update && apt upgrade, без вопросов); --no-upgrade — пропустить этот шаг.
# В конце печатаются адрес панели, логин и пароль (они же — в /root/nodepanel-admin.txt).
set -euo pipefail

DOMAIN=""; BINARY=""; URL=""; SHA=""; EMAIL=""; PORT=""; SNI="www.microsoft.com"; NO_UPGRADE=""
# Репозиторий выпусков подставляется при сборке выпуска (.github/workflows/release.yml).
REPO="${NODEPANEL_REPO:-richdodcom-pixel/nodepanel-releases}"
# Метку заменяет только присваивание выше; проверяем по её части, чтобы sed при сборке не задел и эту строку.
case "$REPO" in *_NODEPANEL_REPO_*) REPO="" ;; esac
AGENT_PORT=8444; SUB_PORT=2096
while [ $# -gt 0 ]; do
  case "$1" in
    --domain) DOMAIN="$2"; shift 2 ;;
    --binary) BINARY="$2"; shift 2 ;;
    --url)    URL="$2"; shift 2 ;;
    --sha256) SHA="$2"; shift 2 ;;
    --email)  EMAIL="$2"; shift 2 ;;
    --port)   PORT="$2"; shift 2 ;;
    --sni)    SNI="$2"; shift 2 ;;
    --no-upgrade) NO_UPGRADE=1; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "неизвестный параметр: $1" >&2; exit 2 ;;
  esac
done
say() { printf '\033[1;32m▶ %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m✖ %s\033[0m\n' "$*" >&2; exit 1; }
info() { printf '  %s\n' "$*"; }
busy() { ss -tlnH "( sport = :$1 )" 2>/dev/null | grep -q .; }

[ "$(id -u)" = 0 ] || die "запустите под root (или через sudo)"
command -v systemctl >/dev/null || die "нужен systemd"
command -v curl >/dev/null || die "нужен curl: apt install -y curl"
case "$(uname -m)" in
  x86_64|amd64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) die "архитектура $(uname -m) не поддерживается" ;;
esac
[ ! -f /etc/nodepanel/panel.yaml ] || die "панель уже установлена (/etc/nodepanel/panel.yaml). Удалить: nodepanel uninstall"

# --- обновление системы
# Без вопросов: needrestart сам перезапускает службы, изменённые файлы настроек остаются как были.
# Если apt занят (на свежем сервере часто работают автообновления) — ждём до 10 минут.
if [ -z "$NO_UPGRADE" ] && command -v apt-get >/dev/null; then
  say "Обновление системы: apt update && apt upgrade (пропустить: --no-upgrade)"
  APT_LOG=/var/log/nodepanel-install-apt.log
  export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
  APT=(apt-get -y -o DPkg::Lock::Timeout=600 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
  info "вывод apt — ниже и в $APT_LOG; если apt занят автообновлениями, жду до 10 минут"
  "${APT[@]}" update 2>&1 | tee "$APT_LOG" || die "apt update не удался — подробности: $APT_LOG"
  "${APT[@]}" upgrade 2>&1 | tee -a "$APT_LOG" || die "apt upgrade не удался — подробности: $APT_LOG (можно повторить с --no-upgrade)"
  info "система обновлена"
else
  info "обновление системы пропущено"
fi

# --- программа
say "Программа nodepanel ($ARCH)"
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
if [ -n "$BINARY" ]; then
  cp "$BINARY" "$TMP"
elif [ -n "$URL" ]; then
  info "скачиваю $URL"
  curl -fL --progress-bar -o "$TMP" "$URL" || die "не удалось скачать $URL"
elif [ -n "$REPO" ]; then
  # последний выпуск на GitHub + проверка суммы из SHA256SUMS
  REL="https://github.com/$REPO/releases/latest/download"
  info "скачиваю $REL/nodepanel-linux-$ARCH"
  curl -fL --progress-bar -o "$TMP" "$REL/nodepanel-linux-$ARCH" || die "не удалось скачать $REL/nodepanel-linux-$ARCH"
  SHA="$(curl -fsSL "$REL/SHA256SUMS" | awk -v f="nodepanel-linux-$ARCH" '$2==f {print $1}')"
  [ -n "$SHA" ] || die "в выпуске нет SHA256SUMS для $ARCH"
else
  die "укажите --binary <файл> или --url <адрес>"
fi
if [ -n "$SHA" ]; then
  [ "$(sha256sum "$TMP" | cut -d' ' -f1)" = "$SHA" ] || die "контрольная сумма не совпала"
  info "контрольная сумма совпала (sha256 ${SHA:0:16}…)"
fi
chmod 755 "$TMP"; VER="$("$TMP" version 2>/dev/null)" || die "файл не запускается — не та архитектура?"
install -m 0755 "$TMP" /usr/local/bin/nodepanel
info "установлено: /usr/local/bin/nodepanel — $VER"

# --- адрес и домен
say "Адрес сервера и домен"
IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}')"
case "$IP" in
  ""|10.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*|192.168.*|100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*)
    say "Внешний IP: спрашиваю у api.ipify.org (сервер за NAT)"
    IP="$(curl -4 -fsS --max-time 10 https://api.ipify.org || true)" ;;
esac
[ -n "$IP" ] || die "не удалось определить внешний IP — укажите --domain"
[ -n "$DOMAIN" ] || DOMAIN="${IP//./-}.sslip.io"
RESOLVED="$(getent ahostsv4 "$DOMAIN" | awk 'NR==1{print $1}' || true)"
[ "$RESOLVED" = "$IP" ] || die "домен $DOMAIN указывает на '${RESOLVED:-ничего}', а IP сервера $IP — проверьте DNS"
info "IP сервера: $IP"
info "домен: $DOMAIN (указывает на $RESOLVED — верно)"

# --- порты
say "Порты"
[ -n "$PORT" ] || PORT=$(( 20000 + RANDOM % 40000 ))
for p in 80 "$PORT" "$AGENT_PORT" "$SUB_PORT"; do
  busy "$p" && die "порт $p занят — освободите его или укажите другой (--port)"
done
info "панель: $PORT, проверка Let's Encrypt: 80, ноды: $AGENT_PORT, подписки: $SUB_PORT — свободны"
for p in 443 8443; do busy "$p" && echo "  внимание: порт $p занят — точки подключения на нём (если нода тоже здесь) не заработают" >&2; done

# --- настройки
say "Настройки (/etc/nodepanel/panel.yaml)"
BASE="/$(head -c 18 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 12)"
mkdir -p /etc/nodepanel /var/lib/nodepanel
chmod 700 /var/lib/nodepanel
umask 077
cat > /etc/nodepanel/panel.yaml <<CFG
data_dir: /var/lib/nodepanel
listen: 0.0.0.0:$PORT
base_path: $BASE
agent_listen: :$AGENT_PORT
sub_listen: :$SUB_PORT
tls_domain: $DOMAIN
acme_email: "$EMAIL"
CFG
[ -n "$REPO" ] && echo "update_repo: $REPO" >> /etc/nodepanel/panel.yaml

info "создан /etc/nodepanel/panel.yaml"
/usr/local/bin/nodepanel admin -data /var/lib/nodepanel templates defaults "$SNI" >/dev/null
info "шаблоны точек подключения: VLESS Reality RAW (443) и XHTTP (8443), маскировка под $SNI"
PASS_LINE="$(/usr/local/bin/nodepanel admin -data /var/lib/nodepanel admin add admin | sed -n 's/^Пароль.*: //p')"
[ -n "$PASS_LINE" ] || die "не удалось создать администратора"
info "создан администратор admin"

# --- служба
say "Служба nodepanel-panel"
cat > /etc/systemd/system/nodepanel-panel.service <<UNIT
[Unit]
Description=nodepanel panel
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/nodepanel panel -config /etc/nodepanel/panel.yaml
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now nodepanel-panel >/dev/null 2>&1 || die "служба не запустилась — смотрите: journalctl -u nodepanel-panel -n 50"
info "служба включена и запущена ($(systemctl is-active nodepanel-panel))"

say "Жду сертификат Let's Encrypt и запуск панели (до 3 минут)"
info "журнал панели — ниже:"
URL_PANEL="https://$DOMAIN:$PORT$BASE/"
( journalctl -u nodepanel-panel -f -n 20 --no-pager -o cat 2>/dev/null | sed -u 's/^/    │ /' ) &
JPID=$!
stop_log() { pkill -P "$JPID" 2>/dev/null || true; kill "$JPID" 2>/dev/null || true; wait "$JPID" 2>/dev/null || true; }
trap 'rm -f "$TMP"; stop_log' EXIT
OK=""
for i in $(seq 1 90); do
  if curl -fsS --max-time 3 -o /dev/null "https://$DOMAIN:$PORT$BASE/healthz" 2>/dev/null; then OK=1; break; fi
  [ $((i % 8)) -eq 0 ] && info "…ещё жду ($((i * 2)) с)"
  sleep 2
done
stop_log
if [ -z "$OK" ]; then
  printf '\n\033[1;31m✖ панель не ответила по HTTPS за 3 минуты\033[0m\n\n'
  echo "  Служба: $(systemctl is-active nodepanel-panel)"
  echo "  Слушают порты:"; { ss -tlnp 2>/dev/null | grep nodepanel | awk '{print "    " $4}'; } || echo "    (ни одного)"
  echo "  Последние строки журнала:"
  journalctl -u nodepanel-panel -n 25 --no-pager -o cat 2>/dev/null | sed 's/^/    │ /' || true
  echo
  echo "  Частые причины:"
  echo "    • у хостера закрыт порт 80 (внешний файрвол в личном кабинете) — Let's Encrypt не может проверить домен;"
  echo "    • лимит Let's Encrypt на частые сертификаты для одного имени (в журнале: rateLimited / too many certificates) —"
  echo "      подождать или указать свой домен: --domain panel.example.com;"
  echo "    • сертификат ещё выдаётся — подождите пару минут и откройте: $URL_PANEL"
  echo "  Полный журнал: journalctl -u nodepanel-panel -n 100 --no-pager"
  exit 1
fi
info "панель отвечает по HTTPS, сертификат получен"

cat > /root/nodepanel-admin.txt <<TXT
Панель:  $URL_PANEL
Логин:   admin
Пароль:  $PASS_LINE
TXT
chmod 600 /root/nodepanel-admin.txt

printf '\n\033[1;32m✔ Панель установлена\033[0m\n\n'
printf '  Адрес:   %s\n  Логин:   admin\n  Пароль:  %s\n\n' "$URL_PANEL" "$PASS_LINE"
echo "  Это же записано в /root/nodepanel-admin.txt (только для root)."
echo "  Дальше: в панели «Ноды» → «Добавить ноду» → выполнить готовую команду на сервере ноды."
if [ -f /var/run/reboot-required ]; then
  echo
  echo "  ⚠ После обновления системы сервер просит перезагрузку (новое ядро). Когда удобно: reboot —"
  echo "    панель и ноды после перезагрузки запустятся сами."
fi
