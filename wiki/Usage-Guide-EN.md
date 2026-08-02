# Usage Guide

This page provides a detailed look at the advanced features of the tool to help you maximize your efficiency.

## Left: Assets Panel

- **Columns Adjustment**: Drag the slider at the top to change the number of thumbnail columns in real-time, adapting to different screen sizes and your personal preference.
- **Include Subdirectories**: Enabling this switch will make the tool recursively scan and load images from all subfolders. Disabling it shows only images from the currently selected directory.
- **Subdirectory switcher**: When the scanned images are spread across more than one subfolder, a dropdown lists every directory that directly holds images (with each folder's image count). Selecting one narrows tag stats, global batch edits, and the AI assistant to that folder alone — it's an **exact match** on the image's own directory, not a recursive subtree match (a deeper nested folder shows up as its own separate entry).
- **Refresh**: If you have added or removed images from the directory externally, click the refresh button to reload the content.
- **Image Preview**: **Double-click** any thumbnail to open a separate preview window.

### Preview Window

- **Zoom & Pan**: Use the **mouse scroll wheel** to zoom in and out, and **press and hold the left mouse button** to pan the image.
- **Image Navigation**: Click the `<` and `>` buttons on the sides of the window to quickly navigate back and forth through the entire image list without closing the window.
- **Reset View**: If the image is zoomed or moved out of view, click the "Fit to Screen" button at the bottom to reset its state.
- **Save Image**: Click the "Download" button to save the currently previewed image to any other location on your machine.

### Tag Filter Expressions

Tag filtering on the left is not a single has/lacks toggle — it's a nestable boolean expression:

- Each filter group can hold several **has tag / lacks tag** conditions, and all conditions in a group combine with a single **AND** or **OR** (think of a group as one pair of parentheses).
- Groups can nest inside other groups, letting you build arbitrarily complex parenthesized expressions like "(has A and has B) or (lacks C)".
- You can flip a group's AND/OR at any time, "dissolve" a sub-group back into its parent, or delete any condition or group.
- An empty group imposes no restriction; the filter result applies live to the gallery and thumbnail grid on the left.

## Center: Preview & Caption Editor

The heart of the center column is the **tag view**, which powers the whole tag management system.

### Multiple Caption Types & Sentence Mode

An image can carry several caption files side by side with different extensions (e.g. a tag-style `.txt` next to a natural-language `.ntxt`), configured under **Caption Type Management** in Settings — where you enable, name, and set the extension for each. The rest of the app (gallery, editor, batch tools) always works against whichever type is currently **active**.

Every type also declares a **content format**, which is what decides how the whole app parses and rewrites its files — the format, never the file extension:

- **Tags**: comma-separated danbooru-style tags. The default.
- **Prose (sentence mode)**: the tag view segments the text by comma/period (including full-width punctuation) into phrases instead of treating it as tags — a better fit for natural-language descriptions.
- **JSON**: one JSON document per caption. The tag views give way to a read-only highlighted JSON view and tag-level rewrites are refused — a flat list of tags cannot be assembled back into a document. These captions are edited as text, or through the assistant's JSON tools (below).

### Tag Comparison System

Three tag areas appear below the tag view:

1. **Image Tags**
    - This area displays all the tags that the current image possesses.
    - **Drag & Drop Sorting**: Long-press and drag a tag to change its order in the list. This order is synced to the top text box in real-time.
    - **Double-Click to Edit**: Double-click a tag to rename it.
    - **Delete**: Click the `x` icon on a tag to remove it from the image.
    - **Insert anchor**: Tap the small handle beside any tag to make it the "anchor". Every tag added afterward — typed by hand, clicked from the tag library, or accepted from an AI suggestion — is inserted right after it, and the anchor then jumps onto the tag just inserted, so a whole sequence lands in click order. The anchor is remembered *by tag name* across images: switching images reactivates it if that image has a tag of the same name, and otherwise falls back to appending at the end without forgetting the remembered name; deleting the anchored tag also falls back to append-at-end for that image.

2. **Common Tags**
    - This is your "master tag library" for storing the most frequently used tags across all your datasets, organized into custom-colored groups.
    - **Smart Coloring**:
      - **Green**: Indicates that the current image **already includes** this common tag.
      - **Orange**: Indicates that the current image is **missing** this common tag.
    - **Quick Add**: **Double-click** an orange tag to quickly add it to the "Image Tags" list above.
    - **Management**:
      - **Add (+)**: Opens a dialog for you to paste comma-separated text to **incrementally add** new common tags.
      - **Delete (Trash Can)**: First, **single-click** to select one or more common tags (selected tags get a highlighted border), then click this button to remove them from the common library.
      - **Import/Replace (Arrow)**: Opens a dialog for you to paste text to **completely replace** the current list of common tags.
      - **Organize mode**: In organize mode, up/down arrows next to each group's header step it one position at a time through the global group order (with a slide animation); tapping a group's color dot opens either a preset-swatch palette or a full color picker. See "Living with a large library" below.

3. **New Tags**
    - This area appears automatically if the current image's tags contain any that are **not** in your "Common Tags" library.
    - **Quick Add to Library**: **Single-click** a gray "New Tag" to instantly add it to your "Common Tags" library, helping you expand and maintain your master list.

### Living with a large library

Once the library passes a few dozen tags, one flat wall of chips stops being useful. The right column answers that in three layers: narrow it while browsing, move things in bulk while organizing, and — when there is no time to file anything — let the model propose a first pass.

#### Browsing: fold, cap, filter

- **Fold a group**: click its header. The folded state is **remembered across restarts**. The toolbar's fold icon collapses or expands every section at once.
- **Two rows per group**: each group lays out at most two rows of tags; the rest go behind `+N more`. Open it to see the whole group, "Show less" to go back. This is **temporary** state, unlike folding — "let me see the rest" and "I never look at this group" are different statements.
- **Per-group usage**: `6/9 used` in the header means 6 of that group's 9 tags are already on the **current image**. It describes the group, so a filter never makes it lie.
- **Status filter**: four pills below the search box, all relative to the current image:
  - **All** — no filtering.
  - **Used** — only library tags the image already carries.
  - **Unused** — only the ones it is missing.
  - **New** — only tags the image has that the library does not (the same set as the "New Tags" block, in the same amber).
- **Current dataset only**: hides library tags this dataset has never used and says how many it hid. A library shared across several datasets does not need to be spread out in full every time. The switch only appears once a dataset is open.
- **Chinese / pinyin search**: besides the tag itself (`long hair` and `long_hair` are interchangeable), the filter matches its **translation**, the translation's **full pinyin**, and its **initials**. With "长发" stored for `long_hair`, any of `长发`, `changfa`, `chang fa` or `cf` finds it.

#### Organize mode: moving things in bulk

The checklist icon in the toolbar enters organize mode. Clicking a tag no longer applies it to the image — it selects it (a faint wash over the panel says the mode changed).

- **Selecting**: click to toggle; hold `Shift` and click to take everything **from the last tag you clicked to this one**, across groups.
- **The bottom bar**:
  - **Move to group** — send the selection to a group in one step, or to a new group, or back out to ungrouped.
  - **Merge into…** — collapse several near-duplicate or inconsistently spelled tags into one. The dialog lets you name the survivor (prefilled with the first selected tag) and offers **rewrite dataset captions too**: with it on, every caption in the current scope has those tags replaced by the merged one, as a **single** undoable operation. With it off, only the library changes.
  - **Delete** — remove the selection from the library (the dataset is untouched).
- **Drag to file**: drag a selection straight onto any group header and drop. Empty groups show a dashed drop zone.
- **Right-click** still works on a single tag without disturbing the selection.

#### AI grouping

When ungrouped tags pile up, a star button (and a "needs filing" note) appears on the Ungrouped header. It hands those tags and your existing group names to the configured AI backend, which proposes one "tag → group" pairing per tag:

- It **reuses your existing groups** wherever it can, and only invents a category when a batch really needs one (those are marked "new").
- Every row is **confirmed separately** — a check accepts, a cross ignores — or use "Accept all" / "Ignore all".
- **Nothing changes until you accept it.** The model never rewrites the library and leaves you to roll it back.
- An AI backend has to be configured in Settings first; otherwise the button says so.

### Tag Autocomplete & Your Own Tags

Typing a tag by hand brings up danbooru-dictionary suggestions in real time, ranked by post count and coloured by category:

- `↑`/`↓` moves through the candidate list, `Tab` or `Enter` completes the selected one, `F1` opens that tag's wiki page directly (only while the list is open).
- Completions are inserted using the style settings you've set for the AI tagger (underscore-to-space, escaped parentheses, etc.), so hand-typed and AI-suggested tags never end up spelled two different ways.
- **Your own tags**: tags used in the current dataset, or held in the common tag library, that danbooru's dictionary has never heard of (custom trigger words, your own character names) are suggested too, marked with a hollow dot and "your tag · N images in this dataset". They're guaranteed a slice of the candidate list rather than being crowded out by a run of danbooru tags sharing a prefix, and are inserted exactly as you spelled them, with no style conversion. A dataset tag needs to appear on at least **5 images** before it's suggested, so typos don't get fed back to you; tag-library entries are exempt from that threshold since adding one there was already a deliberate choice.

### Tag Lookup & Translations

- **Right-click** any tag (in the editor or the library) to see its danbooru post count and jump straight to its wiki page or a post search. Tags the dictionary has never heard of report how many images in this dataset use them — forty means it's yours, one usually means a typo.
- **Tag translations**: give a tag a translation in the app's current language, shown beside it (or on hover only, or off entirely). Translations are **display-only and never written into a caption file**; each language keeps its own glossary, stored separately from the tag dictionary itself, and can be imported/exported independently. The completion list and the right-click menu also search *by* translation — searching "长发" finds `long_hair`.
- **Update from danbooru**: with a tag selected in the dictionary manager, "Update from danbooru" fetches its `other_names` and wiki excerpt and writes them into the entry — other names join a custom entry's aliases, and the wiki excerpt fills an empty note. **Nothing you typed is ever overwritten.** Fetched records persist across sessions and travel with the settings' data export.
- **Danbooru batch update**: the button at the bottom of the dictionary manager runs the same fetch over every tag the list on the left is currently showing (the search box, the filter segments and the dataset toggle double as the batch's scope controls), skipping tags that already have a record. A tag danbooru does not have gets marked and later batches skip it automatically — a manual "Update from danbooru" on that tag re-checks. Requests go out one at a time with a pause, so a long list takes a while; you can stop anytime and the next run picks up where it left off.

### AI Compare Mode

Running AI recognition on the current image (`Ctrl+E`) shows the result side by side with the current caption in compare mode — accept or reject tags one by one, or apply everything at once; a global exit-compare control lives in the top bar. Batch "recognize only" puts results into each image's own compare mode the same way, for per-image review.

## AI Assistant

The ✨ icon in the top bar opens the **AI Assistant** — a chat panel that can operate on your whole dataset for you.

### The Panel Itself

- It's a **floating** panel, not a fourth column — freely draggable and resizable, docked bottom-right by default, and collapsible to just its title bar with one click. Its position, size, and open/closed state are all remembered, and it never squeezes the width of the center column.
- A button under the panel title shows the current model's name and opens a dropdown of every configured backend/model.

### Multiple Backends & Switching

- Supports **OpenAI**, **Gemini** (via its OpenAI-compatible endpoint), native **Anthropic**, and locally-run **Ollama**. These are all set up under **LLM Backends** in Settings: add a provider first (endpoint + API key), then add specific models under it (context window, max output, temperature, vision support, optional pricing).
- Switching backends from the panel **always starts a brand-new session** with no carried-over context — the tool set and context window are tied to the specific model, so continuing old history across a model switch isn't reliable.

### What It Can Do

Read-only/query tools: dataset overview (image counts, caption coverage, tag vocabulary, active subdirectory scope), tag search with paginated image browsing, and reading multiple images' captions.

Write tools (confirmed one at a time by default, or you can allow all writes for the rest of the conversation; everything is undoable):
- Delete a tag dataset-wide, replace a tag, or insert a new tag beside an existing one.
- Add tags at a given position (start/end/specific index) across a set of images, creating caption files for previously uncaptioned ones.
- **Re-sort every caption's tag order in one pass** against a priority list — much faster than adjusting images one at a time.
- Overwrite a single image's caption.

With more than one caption type enabled (or a single type that isn't tag-format), a few extra tools appear: auditing which type each image has (and which are missing it), and reading/writing a specific type's raw text (e.g. "write a natural-language sentence from this image's WD14 tags").

When a JSON-format type is configured, two more tools show up:

- **Inspect the structure**: sweeps that type's JSON across the dataset and reports which keys the documents carry, how many images have each, whether it holds a string or an array, how many tags live under it with a few examples, which top-level key orders occur, and which files don't parse at all. A restructure is planned from this rather than guessed at from batches of raw reads.
- **Restructure in bulk**: rewrites the whole dataset's (or a filtered subset's) JSON captions into a new shape — **renaming fields, changing their order, moving tags between them**. You describe the target shape once (the ordered fields, where each one's tags come from, and a catch-all for the rest) and the tool assembles every document itself, so the output is always valid JSON, always in the field order you declared, and carries exactly the tags the file already had — nothing reworded, dropped or invented. If a rebuilt document wouldn't come out with the same tags, that image is skipped and reported instead of written. Content that isn't tags (a natural-language description) goes into a "preserve" field, whose old value is carried over untouched. The whole batch undoes as one operation.

For a single-image touch-up there's a guarded write: the new text is rejected unless it carries exactly the tags the file currently holds.

With a vision-capable model configured, the assistant can look at a handful of images directly for a spot check — this is fairly token-expensive, so it's meant for spot checks rather than sweeping the whole dataset.

### Tag Library Tools

The assistant can also tidy the **tag library** itself — the curated set in the right panel, not the dataset. Ask it to categorize the library and it reads the current groups, then files the tags in a single pass: existing groups are reused, new ones are created (with an automatic color) only when a batch really needs them, and membership stays exclusive. It can also add tags to the library (optionally straight into a group), remove tags, and delete a group (whose tags fall back to Ungrouped).

The groups' own appearance is its business too:

- **Rename and recolor**: one call changes a group's name, its color, or both. Colors can be named (blue, purple, pink, orange, mint, gold, slate, brown — the same swatches the color dot offers in organize mode) or given as `#RRGGBB`. The assistant sees each group's current color when it reads the library, so "make these groups easier to tell apart" is a request it can actually act on.
- **Reorder groups**: one call sets the whole top-to-bottom order of the sections (the same order the up/down arrows step through in organize mode). Groups left out of the list keep their relative order behind the ones named, so lifting one group to the top only takes its name.

Removing tags and deleting groups ask for confirmation, because neither is covered by undo. Nothing here touches a caption file: the images keep every tag they have, whatever the library says.

The difference from **AI grouping** on the Ungrouped header: that button is a one-shot pass over ungrouped tags with a row-by-row review. The assistant is the conversational version — you can tell it what the groups should be, have it reorganize existing groups, or fix one thing at a time.

### Tag Translation Tools

The assistant can bulk-fill translations for the dataset's untranslated tags: it lists them busiest-first, looks characters/copyrights/artists up on danbooru's `other_names` rather than inventing a name, doesn't overwrite existing translations by default, and writes at most 200 entries per call, with a per-conversation cap on how many times it can query danbooru. None of this touches a caption file.

### Prompt Presets & Built-in Skills

The bookmark-icon menu next to the input field has three sections:
- A **skills** section at the top (currently just the Character Sheet skill, below).
- **Built-in prompts** in the middle: ready-made starting points shipped with the app, currently two aimed at the Anima model's JSON captions — "WD14 tags to Anima JSON" (converts the tag captions produced by WD14 tagging into Anima's simplified JSON caption format in one pass; requires a JSON-format caption type configured in the caption type settings) and "Reorder Anima JSON fields" (restructures existing JSON captions into the standard quality → count → character → series → artist → appearance → tags → environment → nl field order). Like any preset they only fill the input, so you can add fixed values (quality, artist, character name) before sending.
- Your saved **prompt presets** below it — clicking one just fills the text into the input (appended after whatever you've already typed), it never auto-sends, so you can add a detail before running it.
- The same menu has a "manage prompt presets" entry, which you can open and edit any time, even while the assistant is mid-run.

### Character Sheet Skill (built in)

A two-stage workflow for the common problem of "a character's fixed traits should be written on every image, but whether a garment gets written depends on whether the tagger actually spotted it":

1. **Plan the rules (inside the assistant panel)**: open the skill and fill a one-shot form — rule-set name, trigger word, fixed "identity" traits (hair color/style, eye color, etc. — written regardless of what the tagger sees), each garment's tags and evidence rule, any tags to strip as conflicts, free-form notes, and a sample size (4–30 images, default 12). Clicking Start has the assistant sample the dataset with the tagger to learn its actual vocabulary, work out whether each garment's evidence really showed up in the sample and which tags conflict with the fixed identity traits, then produce a set of "merge rules" for you to review — **no caption is written at this stage**. The review card marks each garment with whether its evidence fired in the sample (garments that never showed evidence are flagged "never written").
2. **Apply the rules (in the Batch Tagging dialog)**: once you're happy with the rules, open Batch Tagging, choose **Sheet mode**, pick that rule set, and set an evidence-confidence threshold. This re-runs the tagger across the (optionally filtered) dataset and writes captions per the rules: trigger word first → identity tags always → each garment only when evidence was found this time (replacing the evidence tags) → everything else left as-is, while conflict tags are stripped unconditionally.

If no rule sets exist yet, the Batch Tagging dialog will tell you to run this skill in the assistant first.

### Session Token Budget

Settings let you cap how many tokens a single conversation can spend (500K / 1M / 2M / 5M, or 0 for unlimited — default 1M). Since every turn resends the full history, batch work burns through the budget fast; once it's hit, start a new conversation. The input footer shows current usage and turns amber near the limit. Changing this setting only affects the *next* session you start, not one already running.

### Long Runs and the Turn Limit

One request runs for at most 24 model turns. Working through a dataset one image at a time costs a turn per image, so long jobs reach that ceiling legitimately — instead of stopping there, the assistant asks whether to keep going. Choose **Continue** for another 24 turns, **Stop here** to end the request, or type a reply to continue with extra instructions (e.g. "skip the ones already done"), which the assistant reads before its next turn. It asks again at every ceiling, so an unattended loop can never run away; the token budget above still applies throughout.

### Follows the Subdirectory Scope

Switch to a subdirectory on the left and the assistant's visibility and edits narrow to that folder too, so it can't accidentally touch the rest of the dataset — it also reports in its results whether it ran against "the whole dataset" or just a subdirectory.

## Right: Dataset Tags Panel

- **Global aggregation**: all tags across the dataset with occurrence counts, with a toggle to sort by count or alphabetically.
- **Click to filter**: clicking a tag filters the gallery on the left (the same mechanism as the boolean expression filter above).
- **Add tags globally**: a toolbar button opens a dialog where you type one or more comma-separated tags and choose where to insert them — start, end, or a specific 1-based position — with an option to scope the sweep to just the currently filtered images if the gallery is filtered. Images without a caption file yet get one created.
- **Global batch edits**: rename or delete a tag across the whole dataset, with **undo** (`Ctrl+Z` / `Ctrl+Shift+Z` or `Ctrl+Y`).

## Recommended Workflow

1. Set up your tag dictionary, theme, and caption extension in Settings, plus the AiApiServer address and/or LLM backends if you want AI features.
2. Use "Import/Replace" to pre-populate your "Common Tags" library with your frequently used tags, organized and colored into groups as needed.
3. Open an image directory; if images are spread across subfolders, switch to a specific subdirectory if that's what you want to work on.
4. Single-click an image and observe the colors in the "Common Tags" area:
    - Quickly **double-click** all orange tags to add the missing ones to the image.
5. Check the "New Tags" area. If you think a new tag is generally useful, **single-click** it to add it to your common library.
6. In the "Image Tags" area, **drag and drop** tags to adjust their order, or set an **insert anchor** to drop a whole sequence of tags in place.
7. For overwrite-style tagging or the Character Sheet workflow, use AI-Assisted Tagging's batch features; for dataset-wide renames, tag translation, or anything more involved, just tell the **AI Assistant** what you need.
8. Click **"Save"** (or `Ctrl+S`), then use `←`/`→` to move to the next image and repeat.
