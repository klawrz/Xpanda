# Xpanda 🐼

A powerful text expander for macOS that helps you increase productivity by replacing typed keywords with pre-written responses.

## Features

### Core Functionality
- **Text Expansion**: Type a keyword (e.g., "xintro") and it automatically expands to your pre-written text
- **XP Management**: Create, edit, and delete XPs (expansion entries)
- **Search & Filter**: Quickly find XPs using the search bar
- **Organization**: Tag your XPs and organize them into folders
- **Conflict Detection**: Automatic detection of duplicate keywords with visual indicators (!)
- **Import/Export**: Backup your XPs or share them across machines

### Organization Features
- Tag-based categorization
- Folder organization with manual override
- Search and filter by keyword, expansion, or tags

### Smart Features (Coming Soon)
- Cursor positioning after expansion
- Variables (date, time, clipboard, custom fields)
- Multi-line expansions (already supported)
- Tab stops for quick navigation through fill-in fields
- Rich text formatting

## Building the Project

### Prerequisites
- macOS 13.0 or later
- Xcode 14.0 or later
- Swift 5.7 or later

### Setup Instructions

1. **Open in Xcode**
   ```bash
   cd Xpanda
   open Xpanda.xcodeproj
   ```

   If the `.xcodeproj` file doesn't exist, you can create it in Xcode:
   - Open Xcode
   - Choose "Create a new Xcode project"
   - Select "macOS" → "App"
   - Product Name: Xpanda
   - Team: Your team
   - Organization Identifier: com.yourname.xpanda
   - Interface: SwiftUI
   - Language: Swift
   - Save to the Xpanda directory (replace existing files if prompted)

2. **Add Files to Project**

   Make sure all the Swift files are added to the project:
   - `XpandaApp.swift`
   - `Models/XP.swift`
   - `Managers/XPManager.swift`
   - `Managers/ExpansionEngine.swift`
   - `Views/ContentView.swift`
   - `Views/XPDetailView.swift`
   - `Views/AddEditXPView.swift`
   - `Views/ConflictView.swift`
   - `Views/ImportView.swift`
   - `Views/SettingsView.swift`
   - `Info.plist`

3. **Configure Signing**
   - Select the Xpanda target
   - Go to "Signing & Capabilities"
   - Select your development team
   - Ensure "Automatically manage signing" is checked

4. **Build and Run**
   - Press `Cmd + R` to build and run
   - The app will launch and request Accessibility permissions

## Granting Permissions

Xpanda requires Accessibility permissions to monitor keyboard input and perform text expansions.

1. When you first launch the app, macOS will prompt you to grant Accessibility permissions
2. Click "Open System Settings"
3. Toggle the switch next to Xpanda to enable it
4. Restart Xpanda

Alternatively:
1. Open System Settings
2. Go to Privacy & Security → Accessibility
3. Enable Xpanda

## Using Xpanda

### Creating Your First XP

1. Click the "+" button in the toolbar
2. Enter a keyword (e.g., "xintro")
3. Enter your expansion text (e.g., "Hi, this is Adam!")
4. Optionally add tags and assign to a folder
5. Click "Create"

### Testing the Expansion

1. Open any text editor (Notes, TextEdit, etc.)
2. Type your keyword followed by a space or punctuation
3. The keyword will automatically be replaced with your expansion text!

### Organizing XPs

- **Tags**: Add multiple tags to categorize XPs (e.g., "greeting", "email", "signature")
- **Folders**: Group related XPs together in folders
- **Search**: Use the search bar to filter XPs by keyword, expansion, or tags

### Import/Export

- **Export**: Click the menu (⋯) → "Export XPs..." to save your XPs to a file
- **Import**: Click the menu (⋯) → "Import XPs..." to load XPs from a file
  - Choose "Merge" to add to existing XPs
  - Choose "Replace" to replace all XPs with imported ones

### Handling Conflicts

If you create XPs with duplicate keywords:
- An orange "!" indicator appears next to conflicting XPs
- Click the "View Conflicts" button in the toolbar
- Compare the conflicting XPs and edit or delete as needed

## Distribution

### Building for Distribution

1. **Archive the App**
   - In Xcode, select "Product" → "Archive"
   - Once complete, the Organizer window will open

2. **Export the App**
   - Select your archive and click "Distribute App"
   - Choose "Copy App"
   - Select a destination folder

3. **Share with Co-workers**
   - Zip the exported Xpanda.app
   - Share via file sharing service
   - Recipients should drag Xpanda.app to their Applications folder

### For Team Distribution (Optional)

For easier distribution to co-workers, consider:
- Code signing with a Developer ID certificate
- Notarizing the app through Apple
- This prevents Gatekeeper warnings on other machines

## Data Storage

XPs are stored locally at:
```
~/Library/Application Support/Xpanda/xpanda_data.json
```

You can access this location via:
- Settings → General → "Open in Finder"

## Keyboard Shortcuts

- `Cmd + N` - New XP
- `Cmd + ,` - Settings
- `Cmd + F` - Focus search bar

## Technical Architecture

- **Language**: Swift
- **UI Framework**: SwiftUI
- **Storage**: JSON file in Application Support directory
- **Keyboard Monitoring**: macOS Accessibility API (CGEvent)
- **Text Replacement**: Simulated keyboard events

## Troubleshooting

### Expansions Not Working

1. Check Accessibility permissions (Settings → General)
2. Ensure the keyword is unique (check for conflicts)
3. Try typing the keyword in a different app
4. Restart Xpanda

### App Won't Launch

1. Check macOS version (requires 13.0+)
2. Check Console.app for error messages
3. Delete app data and restart:
   ```bash
   rm -rf ~/Library/Application\ Support/Xpanda
   ```

## Future Enhancements

- [ ] Rich text formatting support
- [ ] Cursor positioning with special markers
- [ ] Variables (date, time, clipboard)
- [ ] Tab stops for fill-in fields
- [ ] AppleScript support
- [ ] Cloud sync
- [ ] Snippet statistics
- [ ] Global hotkey to toggle expansion on/off

## License

Copyright © 2024 Xpanda. All rights reserved.

---

Made with ❤️ for productivity
