# AttuneParser

Аддон для **WoW Prime (3.3.5a)** — анализ поглощения эссенций, рейтинг подземелий и рейдов («Топ инстов»), Путеводитель, помощник аукциона, интеграция с банком ИБ/ГБ/Кладбошей и авто-улучшение экипировки у Валдриса.

## Установка в клиент WoW 3.3.5a

Скопируйте репозиторий прямо в папку аддонов под именем `AttuneParser`:

```powershell
cd "<ПУТЬ_К_WOW>\Interface\AddOns"
git clone https://github.com/Soodoqie/AttuneParser.git AttuneParser
```

Или распакуйте ZIP-архив так, чтобы внутри `Interface\AddOns\AttuneParser\` лежали `AttuneParser.toc`, `AttuneParser.lua`, `AttuneParser_Data.lua`, `AttuneParser_Data2.lua`, `AttuneParser_UI.lua` и `AttuneParser_Integrations.lua`.

## Основные команды

- `/ap` — открыть главное окно аддона
- `/ap minimap` — показать или скрыть кнопку на миникарте
- `/ap status` — вывести краткую сводку в чат

## Офлайн-автотесты (`tests/`)

Требуется Python 3.10+ и библиотека `lupa` для выполнения Lua-тестов:

```powershell
pip install lupa
python tests/test_static.py
python tests/test_hardmode_tracks.py
```

- `tests/test_static.py` проверяет кодировку (UTF-8 без BOM), совместимость символов с WoW 3.3.5a (`<= 0x04FF`), запрещенные вызовы (`C_Timer`, `:SetShown(`), баланс скобок/строк, `string.format` и лимит локальных переменных Lua 5.1 (`< 200`).
- `tests/test_hardmode_tracks.py` запускает эмуляцию WoW API в Lupa. При наличии соседней папки `../TalorianTP` (или переменной окружения `TALORIAN_TP_DIR`) прогоняет также полную кросс-интеграцию с `TalorianTP`.
