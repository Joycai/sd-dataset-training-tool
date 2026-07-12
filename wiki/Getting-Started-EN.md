# Getting Started

This guide will walk you through the basic workflow of using the DataSet Training Tool.

## 1. Launch the Application

When you first open the application, you will see a clean interface. The default view is the **Editor**.

![Main Interface](https://github.com/user-attachments/assets/7e600572-8356-424a-9e1e-289528f89025)

## 2. Open an Image Directory

- Click the **"Open"** button in the top-left corner.
- In the system dialog that appears, select a folder containing the images you want to edit.
- After selection, the **Image Browser** on the left will automatically load and display thumbnails of all images in that folder.

## 3. Select an Image

- In the Image Browser on the left, **single-click** on any image thumbnail.
- You will notice:
  - The selected image gets a **blue** highlight border.
  - The **Workspace** on the right becomes active and attempts to load the caption file with the same name as the image (e.g., if you clicked `image1.png`, it will look for `image1.txt`).

## 4. Edit the Caption

- At the top of the Workspace on the right, there is a multi-line text box. This displays the content of the caption file (if it exists).
- You can directly type or modify the text in this box. The standard practice is to use a comma `,` to separate different tags or phrases.
- **Example**: `1girl, solo, long hair, looking at viewer, smile, bangs`

## 5. Use the Tag View

- To manage tags more conveniently, you can enable the **"Tag View"** switch below the text box.
- Once enabled, you will see:
  - The content of the text box is parsed into a series of individual tags, displayed in the "Image Tags" area below.
  - You can drag and drop these tags to reorder them, double-click to edit, or click the `x` to delete them.
  - All operations on the tags are **synced back to the main text box in real-time**.

## 6. Save Your Work

- When you are satisfied with the caption, click the **"Save"** button in the bottom-right corner.
- This will write the final content from the text box into the corresponding caption file.
- **Note**: If the caption file did not exist, it will be created automatically upon saving. If you do not click "Save", all your changes will only exist in memory and will not affect the physical file.

## 7. Switch to Settings

- If you need to adjust the tool's behavior (like changing the language or theme), you can click the **settings icon** in the top-right of the application bar to go to the settings page.

You have now mastered the core workflow of this tool! To learn about more advanced features, please continue to the **[[Usage Guide|Usage-Guide-EN]]**.
