# AttuneParser

Аддон для **WoW Prime (3.3.5a)** — анализ поглощения эссенций, рейтинг подземелий и рейдов («Топ инстов»), Путеводитель, помощник аукциона, интеграция с банком ИБ/ГБ/Кладбошей и авто-улучшение экипировки у Валдриса.

## Скачать и установить (Releases)

Самый простой способ установки для игры:

1. Откройте страницу последнего релиза: https://github.com/Soodoqie/AttuneParser/releases/latest
2. Скачайте готовый архив **`AttuneParser-v*.zip`** (не `Source code` — в готовом архиве уже удалены `tests/` и служебные файлы).
3. Распакуйте его в `<ПУТЬ_К_WOW>\Interface\AddOns\` — внутри уже есть папка `AttuneParser/`.
4. Перезапустите клиент или выполните `/reload` в игре.

Либо клонируйте напрямую через Git:

```powershell
cd "<ПУТЬ_К_WOW>\Interface\AddOns"
git clone https://github.com/Soodoqie/AttuneParser.git AttuneParser
```

## Основные команды

- `/ap` — открыть главное окно аддона
- `/ap minimap` — показать или скрыть кнопку на миникарте
- `/ap status` — вывести краткую сводку в чат

## Как выпускать новые релизы

1. Обновите `## Version` в `AttuneParser.toc` и добавьте описание изменений в [CHANGELOG.md](./CHANGELOG.md).
2. Закоммитьте и отправьте изменения в `main`.
3. Создайте тег (например, `git tag v1.1.1 && git push origin v1.1.1`) или опубликуйте релиз через GitHub UI / `gh release create` — workflow [release.yml](./.github/workflows/release.yml) автоматически прогонит тесты и прикрепит чистый игровой архив `AttuneParser-<tag>.zip` к релизу.

## Офлайн-автотесты (`tests/`)

Требуется Python 3.10+ и библиотека `lupa` для выполнения Lua-тестов:

```powershell
pip install lupa
python tests/test_static.py
python tests/test_hardmode_tracks.py
```

- `tests/test_static.py` проверяет кодировку (UTF-8 без BOM), совместимость символов с WoW 3.3.5a (`<= 0x04FF`), запрещенные вызовы (`C_Timer`, `:SetShown(`), баланс скобок/строк, `string.format` и лимит локальных переменных Lua 5.1 (`< 200`).
- `tests/test_hardmode_tracks.py` запускает эмуляцию WoW API в Lupa. При наличии соседней папки `../TalorianTP` (или переменной окружения `TALORIAN_TP_DIR`) прогоняет также полную кросс-интеграцию с `TalorianTP`.
