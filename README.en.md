# DataSet Training Tool

This is a desktop application built with Flutter, designed to help users efficiently manage and edit image dataset captions, especially for the preprocessing stage of AI model training.

## ✨ Features

### Editor Interface
Features a side-by-side layout, providing a smooth "select-edit" workflow.

#### Left Panel: Image Browser
- **Open Directory**: Quickly select and load a folder containing images.
- **Thumbnail Grid**: Clearly displays all images in the directory in a grid format.
- **Filename Display**: The corresponding filename is shown below each thumbnail.
- **Fit & Contain Scaling**: Thumbnails are displayed completely using `contain` mode, preventing any cropping.
- **Dynamic Column Adjustment**: Adjust the number of columns in real-time with a slider, and the grid adapts automatically.
- **Include Subdirectories**: Scan and load images from all subdirectories with a single switch.
- **Refresh**: Rescan the current directory at any time to update the image list.
- **Image Preview**: **Double-click** any image to open a separate, feature-rich preview window.
- **Selection Highlight**: **Single-click** an image to select it, highlighting it with a blue border and loading its data into the workspace on the right.

#### Right Panel: Workspace
- **Caption Editing**: Automatically loads the `.txt` file with the same name as the selected image (extension is configurable in settings) and displays its content in a multi-line text box.
- **Tag View**:
  - A switch to convert comma-separated caption text into a series of individual chips (tags).
  - **Double-click** a tag to edit it independently.
  - Delete individual tags.
  - All modifications to tags are **bidirectionally synced** back to the main text box.
- **Intelligent Common Tag Management**:
  - **Import/Add**: Bulk import or incrementally add a list of "Common Tags" to serve as your master tag library.
  - **Smart Comparison**:
    - Common tags that are **included** in the image's caption are highlighted in **green**.
    - Common tags that are **missing** from the image's caption are highlighted in **orange**.
  - **Delete**: Select multiple common tags and remove them from the library with one click.
- **New Tag Discovery**:
  - Automatically identifies and displays "New Tags" that exist in the current image's caption but not in the common tag library.
  - New tags are displayed in **gray**.
  - **Single-click** a gray tag to quickly add it to your common tag library.
- **Save**: Click the "Save" button to write all content from the text box into the corresponding caption file, creating it if it doesn't exist.

### Image Preview Window
- **Separate Native Window**: The preview window is a true OS window that can be freely resized and moved.
- **Interactive Viewing**:
  - Use the **mouse scroll wheel** to zoom in and out.
  - **Press and hold the left mouse button** to pan the image.
- **Image Navigation**: Quickly switch to the previous or next image using the buttons on the left and right sides of the window.
- **One-Click Reset**: The "Fit to Screen" button instantly resets the image's zoom and pan state.
- **Image Download**: Save the currently previewed image to another location on your local machine.

### Settings
- **Multi-Language Support**: Built-in support for English and Chinese, easily extendable.
- **Theme Switching**: Supports Light, Dark, and System-default theme modes.
- **Persistence**: All settings (including language, theme, window size, directories, tag library, etc.) are automatically saved on exit and loaded on the next launch.
- **Custom Extension**: Customize the file extension for caption files (defaults to `.txt`).
- **One-Click Reset**: Reset all settings to their initial default values.

## 🚀 System Requirements

Before you begin, ensure your development environment meets the following requirements:

1.  **Flutter SDK**: Version `>=3.4.1`.
2.  **Desktop Development Environment**:
    -   **Windows**: Visual Studio 2022 (or later) with the "Desktop development with C++" workload installed.
    -   **macOS**: The latest version of Xcode.
    -   **Linux**: Necessary build tools such as `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`, and `liblzma-dev`.

## 🏃‍♂️ Running the Project

1.  **Clone the Repository**
    ```sh
    git clone <your-repository-url>
    cd DataSetTrainingTool
    ```

2.  **Get Dependencies**
    ```sh
    flutter pub get
    ```

3.  **Run the Application**
    Choose one of the following commands based on your target platform:
    ```sh
    # Run on Windows
    flutter run -d windows

    # Run on macOS
    flutter run -d macos

    # Run on Linux
    flutter run -d linux
    ```

## 📦 Building for Release

To create a distributable desktop application, use the `flutter build` command.

1.  **Execute the Build Command**
    ```sh
    # Build for Windows
    flutter build windows

    # Build for macOS
    flutter build macos

    # Build for Linux
    flutter build linux
    ```

2.  **Locate the Executable**
    After the build is complete, you can find the final application in the `build` directory of your project:
    -   **Windows**: `build\windows\runner\Release\`
    -   **macOS**: `build\macos\Build\Products\Release\`
    -   **Linux**: `build\linux\<architecture>\runner\Release\`

## 📄 License

This project is licensed under the **GNU General Public License v3.0**. See the [LICENSE](LICENSE) file for details.

## 👥 Authors

- **[Joycai](https://github.com/Joycai)** - Initial idea and contributions
- **Gemini (Google)** - Primary coding and implementation
