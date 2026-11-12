# nodepanel — выпуски

Здесь лежат только готовые файлы выпусков nodepanel (панель управления серверами Xray):
программа для Linux (amd64, arm64), установщик `install.sh` и контрольные суммы `SHA256SUMS`.

## Установка панели

Сервер с Ubuntu 22.04+ / Debian 12+, systemd, вход под root:

```bash
wget -qO nodepanel.sh https://raw.githubusercontent.com/richdodcom-pixel/nodepanel-releases/main/install.sh && bash nodepanel.sh
```

В конце установщик покажет адрес панели, логин и пароль (они же — в `/root/nodepanel-admin.txt`).
Свой домен: `bash nodepanel.sh --domain panel.example.com`.
Сначала установщик обновляет систему (`apt update && apt upgrade`); пропустить: `bash nodepanel.sh --no-upgrade`.

Ноды ставятся командой, которую панель показывает при добавлении ноды.
Обновление панели — кнопкой «Обновить» в настройках (берёт последний выпуск отсюда).
