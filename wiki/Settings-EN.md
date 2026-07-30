# Settings

Click the **settings icon** in the top-right corner of the main interface to access the settings page. All settings here are **saved automatically** after you change them and will take effect the next time you launch the application.

![Settings Page](https://github.com/user-attachments/assets/57223010-f168-4545-911c-223689433434)

## Available Settings

- **Language**
  - Select the application's interface language from the dropdown menu. Currently supports "English" and "中文" (Chinese).
  - The entire UI will update immediately after a change.

- **Caption Extension**
  - Defines the file extension that the tool uses when loading and saving caption files.
  - The default value is `.txt`.
  - For example, if you change this to `.caption`, selecting `image1.png` will make the tool look for and load `image1.caption`.

- **Export / Import Data**
  - Under the **Data** group in the sidebar: packs the settings you built up by hand into one JSON file, so a new machine or a reinstall can pick up where you left off.
  - Three independently selectable parts: **AI backends** (with an option to include API keys — they are written as plain text, so keep the file somewhere private), the **tag library** (groups and their colors, the tags inside and outside them, the tags you added to the dictionary yourself, and the glossaries for *every* language), and **prompt presets**.
  - The bundled tag list and the downloaded full danbooru dictionary are **not** included — the app can fetch both again, and there is no point putting megabytes of it in a backup.
  - Importing asks for the file first, then which parts to restore and whether to **keep what is here** or **use the file's version** where the two disagree. Neither choice ever deletes anything — use the per-panel "clear" actions for that.

- **Reset Settings**
  - This is a dangerous operation, so the button is styled in red.
  - Clicking it will open a confirmation dialog to prevent accidental use.
  - After confirmation, **all** settings (including language, theme, extension, common tag library, last opened directory, etc.) will be cleared and restored to their initial default values.
