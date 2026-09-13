# Work System Recovery

Відтворюваний пакет для всього робочого портфеля: Obsidian, робочі каталоги, reconstructable chat records, конфігурація без секретів і структура чатів/проєктів. Типовий профіль `Foundation` переносить необхідну основу, а не весь локальний диск.

## Перший запуск резервування

```powershell
.\Initialize-GoogleDriveFoundation.ps1 -BackupMode Plain -RegisterSchedule
```

Типовий режим `Plain` відкриє одноразову авторизацію Google Drive через `rclone`, перенесе Foundation у `Work System/00 Recovery/plain-foundation`, перевірить marker readback і зареєструє щоденне резервування о 02:00. Окремого пароля резервної копії немає. Дані захищає обліковий запис Google, HTTPS під час передачі та стандартне шифрування Google Drive.

Для окремо зашифрованого архіву використовуйте:

```powershell
.\Initialize-GoogleDriveFoundation.ps1 -BackupMode Encrypted -RegisterSchedule
```

`Encrypted` використовує restic і вимагає незалежно збережену парольну фразу. Restic не підтримує незашифрований режим; `Plain` реалізований окремим рушієм `rclone`.

## Ручний backup

```powershell
.\Invoke-WorkSystemBackup.ps1
```

## Відновлення на чистій машині

Після завантаження і перевірки pinned release виконайте одну команду з розпакованого каталогу:

```cmd
Install-WorkSystem.cmd
```

Це one-command launcher. У типовому режимі `Plain` потрібні лише Google OAuth/MFA та вхід у Codex. Підтвердження Syncthing потрібне лише якщо live-репліка ввімкнена додатково. Пароль restic потрібен лише для `Encrypted`.

```powershell
.\bootstrap.ps1 -BackupMode Plain -Apply
```

Перший вхід у Codex/ChatGPT і Google OAuth/MFA виконуються вручну. Скрипти не зберігають access tokens або паролі у репозиторії.

## Профілі

- `Critical`: Vault, recovery package та перевірені маніфести чатів/задач. Це аварійний мінімум для продовження роботи.
- `Foundation` (типовий): повна переносна основа. Містить Obsidian, правила, reconstructable records, маніфест структури чатів/проєктів, власний код і довготривалі артефакти всіх напрямків. Не містить залежностей, кешів, тимчасових робочих просторів, великих імпортованих масивів, відтворюваних результатів, старих міграційних копій і секретів.
- `Full`: усі визначені робочі каталоги та локальні масиви. Це необов'язковий архівний профіль.

`Full` не запускати у сховище без запасу. Поточний локальний корпус перевищує 40 GB. Центральний Google Sheet і Google Drive залишаються онлайн-джерелами; у Foundation зберігаються їх стабільні ID, URL та правила доступу, а не дублікати всіх хмарних файлів.

Поточний вимір `Foundation` зберігається у `foundation-profile-measurement.json`.

## Cloud-first артефакти

- Google Docs, Sheets і Slides створюються та редагуються безпосередньо у Drive.
- PDF, ZIP, DOCX, XLSX, зображення та інші бінарні результати спочатку формуються у `%LOCALAPPDATA%\WorkSystemScratch`, потім публікуються через `Publish-WorkArtifact.ps1`.
- Після завантаження обов'язкові hash readback, Drive file ID/URL, запис у tracker `Files` і короткий опис/лінк в Obsidian.
- `Clear-WorkSystemScratch.ps1 -WhatIf` показує майбутнє очищення. Видалення дозволене лише для файлів у канонічному scratch, старших за retention, із валідним `.published.json`, незмінним локальним MD5 і повторно підтвердженим remote MD5.
- Вихідний код зберігається у Git; Drive містить release artifacts і Foundation backup, а не замінює version control.

## Режими резервування

- `Plain` (типовий): незашифровані ZIP-знімки кожного кореня Foundation у `snapshots/<timestamp>/archives`, маніфест із SHA-256/MD5 і перевірений `latest.json`. Це уникає тисяч повільних Google Drive API-операцій і дає повне відновлення без окремого ключа. Файли читаються після звичайного розпакування ZIP.
- `Encrypted`: історичні snapshots restic із клієнтським шифруванням. Сильніша конфіденційність, але без незалежної парольної фрази відновлення неможливе.
- Обидва режими виключають кеші, залежності, тимчасові файли, OAuth tokens, cookies, локальні credentials і restic password files.

## Перенесення під ключ

1. На джерельній машині виконайте `.\Initialize-GoogleDriveFoundation.ps1 -BackupMode Plain -RegisterSchedule`.
2. Дочекайтеся `PASS` і перевірте `.\Test-WorkSystemBackupHealth.ps1` та `.\Test-DisasterRecovery.ps1`.
3. На новій машині завантажте pinned release, розпакуйте і запустіть `Install-WorkSystem.cmd`.
4. Підтвердьте Google OAuth/MFA. Скрипт відновить Foundation у staging, перевірить контрольні нотатки й лише потім застосує її до `Documents`.
5. Увійдіть у Codex, відкрийте Vault і виконайте `.\Repair-WorkSystem.ps1 -RepairSchedules -RunBackup -RunRestoreTest`.

Для encrypted-варіанта перед `Install-WorkSystem.cmd` виконайте `set WORKSYSTEM_BACKUP_MODE=Encrypted`.

## Перевірка

```powershell
.\Test-WorkSystemRecovery.ps1
```

Done означає тільки успішний health check вибраного рушія, тестове відновлення та перевірку контрольних файлів в іншому каталозі або на чистій машині.

## Repair and reusable deployment

- `Test-WorkSystemBackupHealth.ps1` перевіряє доступність і свіжість останнього snapshot.
- `Test-DisasterRecovery.ps1` виконує доказове відновлення в окремий каталог і перевіряє контрольні нотатки та chat manifest.
- `Repair-WorkSystem.ps1` діагностує інструменти, вільне місце, конфігурацію та заплановані задачі.
- `Invoke-WorkSystemMaintenance.ps1` застосовує retention, prune і `restic check`.
- `DEPLOYMENT-GUIDE.md` є універсальною інструкцією для власного середовища або адаптації під клієнта.

## Підготовка Windows-машини для віддаленого Codex

`Enable-WorkSystemSsh.ps1` встановлює Windows OpenSSH Server, вмикає `sshd`, створює правило TCP 22, додає переданий публічний ключ без видалення наявних ключів, виправляє ACL і перевіряє локальний порт. Скрипт не зберігає пароль або приватний ключ.

З каталогу framework:

```cmd
set "WORKSYSTEM_SSH_PUBLIC_KEY=ssh-ed25519 AAAA..." && Enable-WorkSystemSsh.cmd
```

Лаунчер сам запросить підвищення до Administrator. Після успішного JSON-звіту перевірте вхід з керуючої машини через LAN або Tailscale. Парольну автентифікацію не вимикайте до підтвердженого зовнішнього входу ключем.
