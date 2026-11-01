# Практика 4.2: CPU-регрессия в Unity C# через Git bisect

Это подготовленная история того же Unity CPU-проекта, что в 4.1, а не Python-приложение. Используйте отдельный клон, не изменяя свою работу 4.1. Полная инструкция и восемь обязательных файлов сдачи находятся в разделе «Практика 4.2» канонической `Лекция_4_CPU_Unity.md`.

Нужны Git, Windows PowerShell и лицензированный совместимый Unity Editor. Python нужен только внешним вспомогательным инструментам сводки CSV и проверки сдачи; алгоритм и тест здесь написаны на C#.

## Подготовка

Откройте PowerShell в этой папке, родительской для `unity_fixture`. Один раз выберите совместимый Editor через Unity Hub → Installs → меню версии → Show in Explorer. Если найдена одна стандартная установка, скрипт возьмёт её; при нескольких укажите `-Unity`, потому что скрипт не выбирает молча самый новый. Например, нестандартная установка может находиться в `D:\Unity\6000.3.16f1\Editor\Unity.exe`.

```powershell
$unity = 'C:\Program Files\Unity\Hub\Editor\6000.3.16f1\Editor\Unity.exe'
$check = (Resolve-Path .\Проверить.ps1).Path
git clone unity_fixture/history.bundle work
New-Item -ItemType Directory submission
Set-Location work
git status --short
git switch --detach known-good
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $check -Repo (Get-Location).Path -Unity $unity -Output ..\submission\known_good.json
$LASTEXITCODE
git switch --detach reported-bad
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $check -Repo (Get-Location).Path -Unity $unity -Output ..\submission\reported_bad.json
$LASTEXITCODE
git switch main
```

Ожидаются коды 0 и 1 соответственно. Editor запускается во внешней служебной копии, а не в вашем клоне: история не меняется. Скрипт сохраняет только `Library`-кэш, а остальные файлы для каждого коммита заново получает из Git. Проверка запускает `HistoryRegressionCheck.Run` в batch Editor без сборки Player. Первый импорт может занять несколько минут и потребовать пакеты; лимит по умолчанию 600 секунд, это не обещание времени запуска на другом компьютере. Несовместимый пакет или API, лицензия и неполный запуск дают `128`, а не bad.

По умолчанию служебная копия находится в `.unity-bisect-runs` рядом с клоном. Если это место неудобно, передайте существующую внешнюю папку параметром `-ExecutionRoot 'D:\UnityBisectRuns'`. Не помещайте её внутрь клона и не очищайте её вручную: скрипт проверяет свой `owner.json`, блокирует одновременный запуск и удаляет только свои проверенные файлы, сохраняя `Library`.

## Что проверяет тест

Настоящий `LookupExercise.ExecuteBatch` выполняет 1024 запроса `(i * 37) % 4096` по 4096 записям `(id, id * 3 + 7)`. Тест независимо проверяет каждый ответ и checksum `6168064`. В `LookupInstrumentation.cs` успешное чтение `CountedRecords<T>` добавляет одно обращение; запись не добавляет. Каждый `CountedLookup.TryGetValue` добавляет одно обращение, включая отсутствующий ключ; `Add` отдельно не считается. Однократная инициализация читает все 4096 записей для индекса. Индексный поиск даёт 5120 обращений, линейный для этих входов — 2059776, включая ту же подготовку. `inspections <= 8192` означает good. Это учебный бюджет работы, не миллисекунды и не модель полной стоимости словаря. `seconds_informational` не включает импорт и не определяет verdict.

Ничего не редактируйте во время поиска. Защищены `Assets/Editor/HistoryRegressionCheck.cs`, `Assets/Scripts/LookupInstrumentation.cs`, `LookupBenchmark.cs`, инициализация `LookupExercise.cs`, остальные исходники, настройки и метаданные. Проверка отклоняет изменённые/неотслеживаемые файлы и сверяет защищённые байты с `known-good`. Это учебная защита от случайных изменений, не песочница против намеренной подмены Git-тегов.

Коды: `0` good, `1` только превышение бюджета при правильных ответах, `125` ошибка компиляции версии с сохранёнными исходниками, `128` остановка из-за неверных ответов, изменённых файлов или инфраструктуры. Отсутствие Editor/лицензии, несовместимый API/пакет, блокировка, тайм-аут, неполный JSON и существующий выходной файл не означают bad.

## Ручной поиск

```powershell
git bisect start reported-bad known-good
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $check -Repo (Get-Location).Path -Unity $unity
$testCode = $LASTEXITCODE
$testCode
if ($testCode -eq 0) { git bisect good }
elseif ($testCode -eq 1) { git bisect bad }
elseif ($testCode -eq 125) { git bisect skip }
else { throw "Проверка остановлена с кодом $testCode" }
```

Повторяйте проверку и разметку до `is the first bad commit`. Сохраните собственный снимок терминала в `..\submission\bisect.png`, затем SHA из специальной ссылки **до** reset:

```powershell
$bad = git rev-parse refs/bisect/bad
git bisect log | Out-File -Encoding utf8 ..\submission\bisect.log
git bisect reset
Set-Content -Encoding utf8 ..\submission\first_bad.txt $bad
git show $bad
git switch --detach "$bad"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $check -Repo (Get-Location).Path -Unity $unity -Output ..\submission\culprit.json
$LASTEXITCODE
git switch --detach "$bad^"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $check -Repo (Get-Location).Path -Unity $unity -Output ..\submission\parent.json
$LASTEXITCODE
git switch main
git status --short
```

Ожидаются коды 1 и 0. PowerShell 5.1: журнал сохраняйте именно через `Out-File -Encoding utf8`, не `>`.

## Отчёты и сдача

Если проверка остановилась с `ERROR (128, not BAD)`, не выполняйте `git bisect bad`: исправьте указанную причину и повторите с новым `-Output` (или без него для уникального имени). Существующие отчёты и логи сохраняются, но не переиспользуются. Закройте Editor именно проверяемого клона; Unity Hub закрывать не нужно. Остаточный `Temp/UnityLockfile` без открытого дескриптора скрипт оставляет Unity, а занятую блокировку или невозможность проверить доступ отклоняет без удаления. Для диагностики сохраните соседние логи. Единственное разрешённое неотслеживаемое исключение — созданный Unity `ProjectSettings/PackageManagerSettings.asset`; изменения отслеживаемых настроек и любые другие новые файлы по-прежнему запрещены.

Каждый `-Output` должен указывать новый файл вне клона. Скрипт отказывается перезаписывать JSON и логи с кодом 128; для повтора выбирайте новый путь. Без `-Output` создаётся уникальный JSON во временной папке. Рядом с JSON появляются `.unity.log`, `.stdout.log`, `.stderr.log`; сохраняйте их для диагностики, но они не входят в обязательные восемь файлов сдачи.

Передайте только `known_good.json`, `reported_bad.json`, `parent.json`, `culprit.json`, `bisect.log`, `first_bad.txt`, `bisect.png` и `Вывод.txt`. Можно скопировать их в отдельную папку `handoff`. В выводе объясните изменение поиска и границу бюджета, а не только назовите SHA. Итоговый PNG не меньше 640 × 360 должен показывать собственный поиск и `is the first bad commit`.

Альтернативный запуск того же скрипта: `..\Проверить.bat -Repo (Get-Location).Path -Unity $unity` из клона. BAT сохраняет код завершения. Студенческий архив содержит только этот README, `Проверить.ps1`, `Проверить.bat` и `unity_fixture/history.bundle`; преподавательские исходники генератора и ответы не выдаются.
