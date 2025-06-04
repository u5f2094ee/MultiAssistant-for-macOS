# MultiAssistant

---
## Screenshot

![MultiAssistant v1 2 Screenshot](https://github.com/user-attachments/assets/7eac2a76-5053-4d5d-a02a-aeba40c5fbe5)


---

## Overview

**MultiAssistant** is a lightweight, dual-chat webapp that embeds both OpenAI ChatGPT and Google Gemini. Designed for seamless access and quick toggling, it integrates with the macOS menu bar and global keyboard shortcuts to provide a distraction-free interface for AI-powered conversations.

**//You can modify the Settings using your preferred AI tools.**

---

## Features

- **Dual Chat Views**: Switch between ChatGPT (`https://chat.openai.com/`) and Gemini (`https://gemini.google.com/app`) with a single keyboard shortcut or the in-app toggle.
- **Global Toggle Shortcut**: Configure a custom global hotkey (e.g., ⌥ + .) to show or hide the assistant from anywhere in macOS.
- **Menu Bar Integration**:
  - Menu bar icon for quick show/hide.
  - Context menu items for Refresh, Zoom In/Out, Actual Size, Settings, and About.
- **Auto-hide**: Automatically hides the window when the application loses focus (optional, configurable in Settings).
- **Customizable URLs**: Change the ChatGPT and Gemini URLs in Settings to point to other AI endpoints or self-hosted instances.
- **Modern Window Chrome**:
  - Rounded corners, and full-size content view for a sleek look.
  - No standard title bar buttons; window is movable by dragging the background.
  - Automatically restores the previous window size and position, and retains cookies.
  - A beautifully styled window with elegant blur and transparency effects with customizable settings.
- **Focus Management**: Ensures the active web view receives keyboard focus and places the cursor in the input area on show, for immediate typing.

---

## Installation & Running

### Prerequisites

- **Xcode 15** or later
- **macOS 13.5** or newer

### From Xcode

1. Clone or download the repository.
2. Open `MultiAssistant.xcodeproj` in Xcode.
3. Build and run the application.
4. Grant Accessibility permissions when prompted (System Settings → Privacy & Security → Accessibility), and add MultiAssistant.app for permissions.
5. Use your configured global shortcut or click the menu bar icon to show/hide MultiAssistant.


### Direct Launch:
1. If you have compiled the `.app` bundle or downloaded a pre-built version.
2. Double-click the `MultiAssistant.app` file.
3. **Accessibility Permissions**: For the global hotkey to function correctly, you **must** grant Accessibility permissions to MultiAssistant:
    - Go to **System Settings → Privacy & Security → Accessibility**.
    - Click the **+** button, navigate to MultiAssistant, and add it to the list.
    - Ensure the toggle next to MultiAssistant is **enabled**.
    - You need to restart MultiAssistant after granting permissions.
4. If macOS blocks the app due to unidentified developer (if not notarized):
    - Go to **System Settings → Privacy & Security**.
    - Scroll down to the "Security" section.
    - You should see a message about "MultiAssistant" being blocked. Click **“Open Anyway”**.


---

## Settings

Open Settings via ⌘ + , or select **Settings...** from the menu bar icon. Customize:

- **Page URLs**: Edit the URLs for ChatGPT and Gemini.
- **Auto-hide Behavior**: Toggle whether the window hides on loss of focus.
- **Global Shortcut**: Choose modifiers and key for show/hide.
- **View Controls**: Review in-app shortcuts for page switching, zoom, and refresh.

---

## Acknowledgements

- **Developed by:** ZhangZheng & Gemini 2.5 Pro


