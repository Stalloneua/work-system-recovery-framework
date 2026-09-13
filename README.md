# Work System Recovery

Відтворюваний пакет для всього робочого портфеля: Obsidian, робочі каталоги, reconstructable chat records, конфігурація без секретів і структура чатів/проєктів. Типовий профіль `Foundation` переносить необхідну основу, а не весь локальний диск.

## Перший запуск резервування

```powershell
.\Initialize-GoogleDriveFoundation.ps1 -RegisterSchedule
```

Перший запуск відкриє одноразову авторизацію Google Drive через `rclone`, а потім попросить пароль restic у захищеному prompt. Збережіть пароль у зовнішньому password manager: DPAPI-копія на поточній машині не є recovery copy. З параметром `-RegisterSchedule` команда також реєструє щоденний backup о 02:00 і щоденне очищення verified scratch о 03:00 після 7 днів retention.

## Ручний backup

```powershell
.\Invoke-WorkSystemBackup.ps1
```

## Відновлення на чистій машині

Після завантаження і перевірки pinned release виконайте одну команду з розпакованого каталогу:

```cmd
Install-WorkSystem.cmd
```

Це one-command launcher. Google OAuth/MFA, вхід у Codex, підтвердження Syncthing device і незалежно збережений restic passphrase залишаються обов'язковими безпечними prompt.

```powershell
.\bootstrap.ps1 -Repository "rclone:work-drive:Work System/00 Recovery/restic-foundation" -Apply
```

Перший вхід у Codex/ChatGPT, Google OAuth/MFA, ключ restic і підтвердження Syncthing device виконуються вручну. Скрипти не зберігають access tokens або паролі у репозиторії.

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
- Вихідний код зберігається у Git; Drive містить release artifacts і зашифровані snapshots, а не замінює version control.

## Перевірка

```powershell
.\Test-WorkSystemRecovery.ps1
```

Done означає тільки успішний `restic check`, тестове відновлення та перевірку контрольних файлів на іншому каталозі або чистій машині.

## Repair and reusable deployment

- `Test-WorkSystemBackupHealth.ps1` перевіряє доступність і свіжість останнього snapshot.
- `Test-DisasterRecovery.ps1` виконує доказове відновлення в окремий каталог і перевіряє контрольні нотатки та chat manifest.
- `Repair-WorkSystem.ps1` діагностує інструменти, вільне місце, конфігурацію та заплановані задачі.
- `Invoke-WorkSystemMaintenance.ps1` застосовує retention, prune і `restic check`.
- `DEPLOYMENT-GUIDE.md` є універсальною інструкцією для власного середовища або адаптації під клієнта.
