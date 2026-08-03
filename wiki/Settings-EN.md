# Settings

Click the **settings icon** in the top-right corner of the main interface to access the settings page. All settings here are **saved automatically** after you change them and will take effect the next time you launch the application.

![Settings Page](https://github.com/user-attachments/assets/57223010-f168-4545-911c-223689433434)

## Available Settings

- **Language**
  - Select the application's interface language from the dropdown menu. Currently supports "English" and "中文" (Chinese).
  - The entire UI will update immediately after a change.

- **Theme**
  - Light / dark / follow-system for brightness.
  - Plus **6 selectable accent colors**: Teal (default), Blue, Indigo, Violet, Rose, Green. The chosen color doesn't just tint buttons and highlights — it derives the whole UI's neutral tones (background, panels, hairlines) too, so switching accents effectively re-skins the app.

- **UI Font**
  - System default / HarmonyOS Sans / MiSans.
  - Choosing a non-system font downloads it on demand.

- **Caption Extension**
  - Defines the file extension the tool uses when loading and saving the currently **active** caption type.
  - The default value is `.txt`.
  - For example, if you change this to `.caption`, selecting `image1.png` will make the tool look for and load `image1.caption`.

- **Caption Type Management**
  - An image can carry several caption files side by side with different extensions (e.g. a tag-style `.txt` next to a natural-language `.ntxt`).
  - Add, name, and set the extension for each caption type here, and enable or disable it. Edits stay in the dialog until you press **Done** (cancelling or closing it discards everything); the default type cannot be disabled or deleted, and extensions must be unique.
  - Every type picks a **format**, which decides how the whole app parses that type's caption files:
    - **WD14 tags**: comma-separated, editable tag by tag in the tag view.
    - **Anima Tag**: the WD14 grammar plus a trailing natural-language description — `tag, tag, tag. A sentence about the image.` Everything after the period that closes the tag list is one segment: it is never split on its own commas, never counts as a tag, and always stays last, so batch edits (sort, replace, add) and the AI assistant's tag tools cannot disturb it.
    - **Anima JSON**: a structured document; the tag view is read-only, edit it from the text tab or with the assistant's JSON tools.
    - **Natural language**: full text; the tag view segments it by comma/period into phrases instead of treating it as comma-separated danbooru tags.
  - Enabling more than one type unlocks a few extra AI Assistant tools for auditing coverage and reading/writing a specific type's files.

- **Tag Dictionary**
  - ~11k danbooru tags ship with the app, fully offline, matching the same vocabulary the WD tagger emits.
  - The full top-100k dictionary — with aliases, artists and copyrights — can be downloaded with one click.
  - **Edit the dictionary**: edit any tag's translation and note, add tags danbooru doesn't have (with a category, ranked first in completions), import/export glossaries, and clear AI-produced translations in one action while keeping hand-written ones.
  - **Fetch from danbooru**: paste a danbooru URL (wiki page / post search / tag listing) or just a tag name to read its public API for category, post count, `other_names` (mostly Japanese alternate names), and a wiki excerpt. These are all candidates — one click adopts one into the translation or note, nothing is written for you automatically.

- **LLM Backends**
  - The conversation-model configuration used by the **AI Assistant**. Two levels: add a **provider** first (endpoint + API key), then add specific **models** under it (model ID, display name, a context-window stop from 8K up to 1M, max output tokens, temperature, vision support, and optional per-million-token pricing).
  - Built-in quick-start presets for common providers: OpenAI, Gemini (OpenAI-compatible endpoint), Ollama (local, default `http://127.0.0.1:11434/v1`), Anthropic.
  - You can also switch between configured models on the fly from the button under the AI Assistant panel's title; switching starts a brand-new session.

- **AI Assistant Settings**
  - **Session token budget**: how many tokens a single conversation can spend — 500K / 1M / 2M / 5M, or 0 for unlimited (default 1M). Every turn resends the full history, so batch work burns through it fast; once hit, start a new conversation. Changing this only affects the *next* session you start.
  - **Whether write tools require confirmation**: on by default (each write is confirmed individually), can be switched to auto-approve everything.
  - **Prompt preset management**: add, edit, or remove the saved prompts available from the panel's bookmark-icon menu.
  - **Assistant tools**: switches for three optional tool groups — **tag library tools** (on by default), **tag translation tools** (off), and **character sheet rules** (off). Every tool the assistant is given has its definition resent on *every* turn, so a group you never use is a standing cost: these three come to roughly 2,400 tokens, which is significant on an 8K/32K-window model. Switching a group off means the assistant no longer has those tools and is not told they exist (it will simply say it cannot do that); the corresponding panels keep working by hand. Applies to the next session you start.

- **Export / Import Data**
  - Under the **Data** group in the sidebar: packs the settings you built up by hand into one JSON file, so a new machine or a reinstall can pick up where you left off.
  - Three independently selectable parts: **AI backends** (with an option to include API keys — they are written as plain text, so keep the file somewhere private), the **tag library** (groups and their colors, the tags inside and outside them, the tags you added to the dictionary yourself, and the glossaries for *every* language), and **prompt presets**.
  - The bundled tag list and the downloaded full danbooru dictionary are **not** included — the app can fetch both again, and there is no point putting megabytes of it in a backup.
  - Importing asks for the file first, then which parts to restore and whether to **keep what is here** or **use the file's version** where the two disagree. Neither choice ever deletes anything — use the per-panel "clear" actions for that.

- **Reset Settings**
  - This is a dangerous operation, so the button is styled in red.
  - Clicking it will open a confirmation dialog to prevent accidental use.
  - After confirmation, **all** settings (including language, theme, extension, common tag library, LLM backends, last opened directory, etc.) will be cleared and restored to their initial default values.
