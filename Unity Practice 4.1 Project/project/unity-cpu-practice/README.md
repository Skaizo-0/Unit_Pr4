# Unity CPU Lab: практика 4.1

Откройте эту папку через Unity Hub в Unity 6000.3.16f1. Здесь находятся Assets, Packages и ProjectSettings. Нужна сборка Windows Player на Mono; отдельный Memory Profiler не требуется.

Выберите `Lesson 4 > Create Scene and Build Development Player`, дождитесь успешной сборки и запустите `Build/UnityCpuLab.exe`.

Player автоматически выполняет 300 кадров прогрева и следующие 300 измерений. Дождитесь `Measurement: 300/300`, checksum 6168064 и valid: True. CSV сохраняется как `lookup.csv` в папке, указанной на экране. В Windows стандартный путь: `%USERPROFILE%\AppData\LocalLow\Mire Education\Unity CPU Lab`. Копируйте результат каждого запуска до следующего: файл перезаписывается.

Полный порядок работы находится в `Лекция_4_CPU_Unity.md` из архива лекции, раздел «Практика 4.1. Оптимизация критического участка кода». Сначала получите три исходных CSV и исходную запись Profiler; только затем изменяйте тело `ExecuteBatch` в `Assets/Scripts/LookupExercise.cs`. Остальные файлы и измеритель не меняйте. Все запросы, порядок ответов и checksum должны сохраниться.

Для повторного измерения пересоберите Player. Маркер: `Lesson4.LookupBatch`. В CPU Usage / Hierarchy выбирайте Main Thread, Calls=1 и сравнивайте Time ms. Здесь цель — меньше времени на ту же работу, не нулевые выделения памяти.

Студенческий архив содержит исходный линейный поиск, а не готовую оптимизацию.
