# nodepanel — выпуски

Здесь лежат только готовые файлы выпусков nodepanel (панель управления серверами Xray):
программа для Linux (amd64, arm64), установщик `install.sh` и контрольные суммы `SHA256SUMS`.

## Установка панели

Сервер с Ubuntu 22.04+ / Debian 12+, systemd, вход под root:

```bash
bash <(curl -fsSL https://github.com/richdodcom-pixel/nodepanel-releases/releases/latest/download/install.sh)
```

В конце установщик покажет адрес панели, логин и пароль (они же — в `/root/nodepanel-admin.txt`).
Свой домен: добавьте `--domain panel.example.com` после `install.sh)`.

Ноды ставятся командой, которую панель показывает при добавлении ноды.
Обновление панели — кнопкой «Обновить» в настройках (берёт последний выпуск отсюда).
