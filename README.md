# MultiAssistant

---
## Screenshot

![MultiAssistant v1 2 Screenshot copy](https://github.com/user-attachments/assets/3cdd1c31-679d-4fc6-bd9c-be472b8bebc5)


---

## Overview

**MultiAssistant** is a lightweight, multi-tab web app that embeds ChatGPT, Gemini and any other AI you modified. Designed for seamless access and quick toggling, it integrates with the macOS menu bar and global keyboard shortcuts to provide a distraction-free interface for AI-powered conversations.

**//You can modify the Settings using your preferred AI tools.**

---

## Features

- **Multi Chat Views**: Switch between Multi AI with a single keyboard shortcut or the in-app toggle.（Max to 10 tabs）
- **Global Toggle Shortcut**: Configure a custom global hotkey (e.g., ⌥ + .) to show or hide the assistant from anywhere in macOS.
- **Menu Bar Integration**:
  - Menu bar icon for quick show/hide.
  - Context menu items for Refresh, Zoom In/Out, Actual Size, Settings, and About.
- **Auto-hide**: Automatically hides the window when the application loses focus (optional, configurable in Settings).
- **Customizable URLs**: Change the AI URLs in Settings to point to any AI endpoints or self-hosted instances.
- **Modern Window Chrome**:
  - Rounded corners, and full-size content view for a sleek look.
  - No standard title bar buttons; window is movable by dragging the background.
  - A beautifully styled window with blur and transparency effects with customizable settings.
- **Focus Management**:
  - Ensures the active web view receives keyboard focus and places the cursor in the input area on show, for immediate typing.



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

## Acknowledgements

- **Developed by:** ZhangZheng & Gemini 2.5 Pro


