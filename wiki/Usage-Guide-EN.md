# Usage Guide

This page provides a detailed look at the advanced features of the tool to help you maximize your efficiency.

## Image Browser (Left Panel)

- **Columns Adjustment**: Drag the slider at the top to change the number of thumbnail columns in real-time, adapting to different screen sizes and your personal preference.
- **Include Subdirectories**: Enabling this switch will make the tool recursively scan and load images from all subfolders. Disabling it shows only images from the currently selected directory.
- **Refresh**: If you have added or removed images from the directory externally, click the refresh button to reload the content.
- **Image Preview**: **Double-click** any thumbnail to open a separate preview window.

### Preview Window

- **Zoom & Pan**: Use the **mouse scroll wheel** to zoom in and out, and **press and hold the left mouse button** to pan the image.
- **Image Navigation**: Click the `<` and `>` buttons on the sides of the window to quickly navigate back and forth through the entire image list without closing the window.
- **Reset View**: If the image is zoomed or moved out of view, click the "Fit to Screen" button at the bottom to reset its state.
- **Save Image**: Click the "Download" button to save the currently previewed image to any other location on your machine.

## Workspace (Right Panel)

The core of the workspace is the **Tag View**, which provides a powerful tag management system.

### Tag Comparison System

When you enable "Tag View", three tag areas appear below:

1.  **Image Tags**
    - This area displays all the tags that the current image possesses.
    - **Drag & Drop Sorting**: Long-press and drag a tag to change its order in the list. This order is synced to the top text box in real-time.
    - **Double-Click to Edit**: Double-click a tag to rename it.
    - **Delete**: Click the `x` icon on a tag to remove it from the image.

2.  **Common Tags**
    - This is your "master tag library" for storing the most frequently used tags across all your datasets.
    - **Smart Coloring**:
      - **Green**: Indicates that the current image **already includes** this common tag.
      - **Orange**: Indicates that the current image is **missing** this common tag.
    - **Quick Add**: **Double-click** an orange tag to quickly add it to the "Image Tags" list above.
    - **Management**:
      - **Add (+)**: Opens a dialog for you to paste comma-separated text to **incrementally add** new common tags.
      - **Delete (Trash Can)**: First, **single-click** to select one or more common tags (selected tags will have a blue border), then click this button to remove them from the common library.
      - **Import/Replace (Arrow)**: Opens a dialog for you to paste text to **completely replace** the current list of common tags.

3.  **New Tags**
    - This area appears automatically if the current image's tags contain any that are **not** in your "Common Tags" library.
    - **Quick Add to Library**: **Single-click** a gray "New Tag" to instantly add it to your "Common Tags" library, helping you expand and maintain your master list.

### Recommended Workflow

1.  Use the "Import/Replace" feature to pre-populate your "Common Tags" library with your frequently used tags.
2.  Open an image directory and enable "Tag View".
3.  Single-click an image and observe the colors in the "Common Tags" area:
    - Quickly **double-click** all orange tags to add the missing ones to the image.
4.  Check the "New Tags" area. If you think a new tag is generally useful, **single-click** it to add it to your common library.
5.  In the "Image Tags" area, **drag and drop** tags to adjust their weight and order (e.g., place subject or important features at the beginning).
6.  Finally, click **"Save"**.
7.  Select the next image and repeat the process.
