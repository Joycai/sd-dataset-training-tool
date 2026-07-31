# Getting Started

This guide will walk you through the basic workflow of using the DataSet Training Tool.

## 1. Launch the Application

When you first open the application, you'll see a three-column workbench: an Assets panel on the left, a preview/caption editor in the center, and the tag library and dataset tags on the right. All three columns are draggable and remember their width.

## 2. Open an Image Directory

- Click the **"Open Folder"** button in the top-left corner.
- In the system dialog that appears, select a folder containing the images you want to edit.
- The **Assets panel** on the left will scan and display thumbnails of all images in that folder (and its subfolders, if "include subdirectories" is checked).
- If the scanned images are spread across more than one subfolder, a **Subdirectory** dropdown appears at the top of the panel. Switching to a subfolder narrows tag stats, global batch edits, and the AI assistant to that folder alone.

## 3. Select an Image

- In the Assets panel, **single-click** any thumbnail.
- You'll notice:
  - The selected image gets a highlight border.
  - The **preview and editor** in the center becomes active and tries to load the caption file matching the image (e.g. clicking `image1.png` looks for `image1.txt`).
  - **Double-clicking** a thumbnail instead opens a separate native preview window that supports zoom, pan, and prev/next navigation.

## 4. Edit the Caption

- In the center column, tags are shown as **chips**: each is its own block you can drag to reorder, double-click to rename, or click to delete — all of which stay in sync with the underlying comma-separated text.
- You can also edit the raw comma-separated text directly. The standard convention is a comma `,` between tags or phrases.
- **Example**: `1girl, solo, long hair, looking at viewer, smile, bangs`
- Typing a tag by hand brings up danbooru-dictionary autocomplete suggestions — use `↑`/`↓` to select and `Tab` or `Enter` to complete.

## 5. Use the Tag Library on the Right

- The **tag library** on the right highlights common tags the current image already has in green, and missing ones in orange — double-click an orange one to add it instantly.
- The **Dataset Tags panel** aggregates every tag used across the whole dataset with counts; clicking a tag filters the gallery on the left.

## 6. Save Your Work

- When you're happy with the caption, press `Ctrl+S` or click **Save** to write the content to the caption file.
- **Note**: if the caption file didn't exist yet, it's created automatically on save. Until you save, changes only live in memory and don't touch the file on disk.

## 7. Try AI-Assisted Tagging and the AI Assistant

- The top of the center column lets you pick a tagger model and run recognition on the current image (`Ctrl+E`); results land in compare mode so you can accept or reject each tag before it's written.
- The ✨ icon in the top bar opens the **AI Assistant** — a floating chat panel that can operate on your whole dataset for you (retagging, bulk re-sorting, translating tags, and more). See the **[[Usage Guide|Usage-Guide-EN]]** for details.

## 8. Switch to Settings

- If you need to adjust the tool's behavior (language, theme, caption types, LLM backends), click the **settings icon** in the top-right of the app bar.

You've now mastered the core workflow! To learn about more advanced features, continue to the **[[Usage Guide|Usage-Guide-EN]]**.
