# zapret2-secondlife

Комплексный фикс для полной разблокировки **Second Life** (клиенты BlackDragon, Firestorm, Official Viewer и др.) на роутерах с **OpenWrt** через **zapret2** без использования VPN.

---

## ⚠️ Важное требование (Prerequisites)

> [!IMPORTANT]
> **На роутере уже должен быть установлен и настроен zapret2!**  
> Скрипт не заменяет установку самого zapret2, а добавляет в существующую конфигурацию специализированные правила (TLS desync, UDP Circuit desync, прямой DNS и фикс оффлоадинга).  
> Все ваши существующие настройки для YouTube, Discord и других сервисов полностью сохраняются.

---

## 🚀 Быстрая установка (One-liner)

Подключитесь к роутеру по SSH и выполните **одну команду**:

### Через `curl`:
```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/PinyaGit/zapret2-secondlife/main/install.sh)"
```

### Через `wget` (если нет curl):
```bash
wget -qO- https://raw.githubusercontent.com/PinyaGit/zapret2-secondlife/main/install.sh | sh
```

---

## 🔍 В чём заключалась проблема

В России при попытке зайти в Second Life без VPN пользователи сталкивались со следующими симптомами:
1. **Ошибка логина / отказ связи с сервером авторизации** — DNS poisoning со стороны провайдеров (подмена IP-адресов Akamai CDN на неживые IP вроде `188.234.73.x`) и блокировка TLS SNI (`login.agni.lindenlab.com`).
2. **Зависание на 91–94% при входе в мир** (`STATE_PRECACHE` / `STATE_WEARABLES_WAIT`) — клиент авторизовался, но мир не загружается, аватар не прогружается, тайм-аут через 30–60 секунд:
   - **Блокировка ТСПУ неизвестного UDP-трафика:** ТСПУ в РФ пропускает первые 4–9 пакетов игрового протокола Linden UDP к симуляторам в AWS (порты `13000–13050`), а затем глушит поток, так как не видит разрешённых протоколов (QUIC, STUN). В результате симулятор прекращает передавать данные мира и аватара.
   - **Аппаратный Flow Offloading (MediaTek MT7981 PPE и др.):** Правило `ct original packets >= 30 flow add @ft` передавало UDP-поток в чип аппаратного ускорения, который из-за бага драйвера сбрасывал отслеживание conntrack для игровых портов.
   - **Перехват входящего UDP до DNAT:** Опция `nfqws_udp_pkt_in='3'` по умолчанию в zapret2 ломала трансляцию сокетов входящих пакетов.

---

## 🛠️ Что делает этот фикс

1. **Прямой DNS для доменов Second Life в `dnsmasq`:**
   - Домены `secondlife.com`, `lindenlab.com`, `secondlife.io`, `secondlifegrid.net`, `akamaized.net`, `vivox.com` направляются напрямую на независимые DNS-серверы `1.1.1.1` и `8.8.8.8`, минуя отравленный DNS провайдера.
2. **Стратегия `secondlife_tls`:**
   - Для портов `443, 12043, 12046` (включая порты HTTP capabilities симуляторов) применяется метод desync `hostfakesplit:host=google.com:tcp_ts=-600000`.
   - Исключает домены SL из стратегии `V_circular` для предотвращения конфликтов.
3. **Стратегия `secondlife_udp`:**
   - Для игровых портов Linden UDP Circuit (`12035, 12036, 13000-13050`) на первых трёх пакетах сессии отправляются фейковые пакеты **Google QUIC Initial** с флагами **`badsum`** и **`ip_ttl=3`**.
   - ТСПУ на оборудовании провайдера (1–2 хопа) распознаёт поток как «разрешённый QUIC/Google» и разблокирует весь последующий UDP-канал. Фейки сгорают на 3-м хопе и не долетают до симуляторов, исключая порчу игровых пакетов.
4. **Фикс аппаратного оффлоада:**
   - Отключает `flow_offloading_hw` в `/etc/config/firewall`, предотвращая сброс UDP-сокетов чипом роутера.
5. **Отключение перехвата входящего UDP:**
   - Устанавливает `nfqws_udp_pkt_in='0'`, как в стабильной первой версии zapret.

---

## 🗑️ Удаление / Откат

Если по какой-либо причине потребуется удалить правила:

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/PinyaGit/zapret2-secondlife/main/uninstall.sh)"
```

Или через `wget`:
```bash
wget -qO- https://raw.githubusercontent.com/PinyaGit/zapret2-secondlife/main/uninstall.sh | sh
```

---

## 📋 Проверено на оборудовании и клиентах

- **Роутер:** OpenWrt 24.x / 25.x (MediaTek MT7981 Filogic 820 Wi-Fi 6 и совместимые архитектуры)
- **Пакет:** zapret2
- **Клиенты игры:** BlackDragon 6.6.x (Vulkan/OpenGL), Firestorm Viewer, Official Second Life Viewer
- **Провайдеры:** ЭР-Телеком (Дом.ру), Ростелеком и др. ТСПУ
