# App Icon Assets

## Required Files

This directory needs two icon files for the app icon generation:

1. **app_icon.png** - 1024x1024px main app icon
2. **app_icon_foreground.png** - 1024x1024px foreground for adaptive icon (Android)

## How to Create the Icons

### Option 1: Using icon.kitchen (Recommended)

1. Visit https://icon.kitchen
2. Select the "Icon" tab
3. Choose a lock/padlock icon from the library or upload your own
4. Set the color scheme:
   - Primary color: `#FF6D00` (orange to match app theme)
   - Background: `#FF6D00` or dark color
5. Configure options:
   - Style: Material Design
   - Shape: Square or rounded square
   - Padding: Medium (ensure icon fits in safe zone)
6. Download the generated icons:
   - Download "Icon" → save as `app_icon.png` (1024x1024)
   - Download "Adaptive foreground" → save as `app_icon_foreground.png` (1024x1024)
7. Place both files in this directory (`assets/icon/`)

### Option 2: Manual Creation

If creating manually in Inkscape, Figma, or similar:

**app_icon.png requirements:**
- Size: 1024x1024px
- Format: PNG with transparency
- Content: Lock/padlock icon centered
- Color: Orange (#FF6D00) or gradient
- Style: Simple, Material Design style
- Padding: Keep icon in center 80% for safety

**app_icon_foreground.png requirements:**
- Size: 1024x1024px
- Format: PNG with transparency
- Content: Same icon as app_icon.png
- Background: Fully transparent
- Safe zone: Keep icon in center 66% (Android will mask outer 33%)

## After Creating Icons

Once you have both PNG files in this directory, generate platform-specific icons:

```bash
# Install dependencies
flutter pub get

# Generate icons for all platforms
dart run flutter_launcher_icons

# Verify generation
ls android/app/src/main/res/mipmap-*/ic_launcher.png
ls ios/Runner/Assets.xcassets/AppIcon.appiconset/
ls linux/icons/
```

## Icon Design Guidelines

- **Simple shapes**: Avoid complex details that blur at small sizes
- **High contrast**: Icon should be visible on various backgrounds
- **Centered**: Keep important elements in safe zone
- **No text**: Icons work globally without text
- **Distinctive**: Should be recognizable in app drawer
- **Color**: Use orange (#FF6D00) to match app theme

## Current Status

⚠️ **Icons not yet created** - Please create and add the icon files following the instructions above.
