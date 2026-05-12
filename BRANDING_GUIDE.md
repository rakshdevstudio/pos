# ILLUME POS - Branding Implementation Guide

## Logo Assets

The ILLUME POS app now uses a professional luxury logo system across all screens and platforms.

### Logo Files

All logo assets are located in `assets/icons/`:

1. **illume_logo_icon.svg** - Icon-only logo (use for compact/mobile/app icon)
2. **illume_logo_horizontal.svg** - Horizontal logo with text (use for headers/login)
3. **illume_logo_monochrome.svg** - Black monochrome version (use for receipts/thermal printing)

### Widget Components

Logo widgets are available in `lib/presentation/shared/widgets/illume_logo.dart`:

```dart
// Icon-only logo with optional shadow
const LogoIcon(size: 48, shadow: true)

// Horizontal logo with text
const LogoHorizontal(height: 64)

// Monochrome black logo for printing
const LogoMonochrome(size: 48, forPrint: true)
```

## Screen Integration

The ILLUME logo has been integrated across all major screens:

### 1. **Splash Screen** (`lib/presentation/auth/splash_screen.dart`)
- Centered ILLUME icon with luxury glow effect
- Subtle dark gradient background
- Elegant fade and scale animations
- Text: "ILLUME POS - Retail Operating System"
- Shows on app startup before login

### 2. **Login Screen** (`lib/presentation/auth/login_screen.dart`)
- LogoIcon replacing the diamond icon
- Replaced hardcoded diamond with luxury ILLUME branding
- 64px icon with shadow effect

### 3. **School Selection Screen** (`lib/presentation/schools/school_selection_screen.dart`)
- LogoIcon in AppBar header (40px)
- Clean, compact branding in the store selection interface

### 4. **POS Screen** (`lib/presentation/pos/pos_screen.dart`)
- LogoIcon in the main POS header (36px)
- Professional branding next to school name

### 5. **Cart Panel** (`lib/presentation/pos/cart_panel.dart`)
- LogoIcon in cart header (28px)
- Consistent branding in the checkout sidebar

## Print Service

The print service (`lib/services/print_service.dart`) now includes:

- `ReceiptData` class for structured receipt layout
- Monochrome ILLUME logo support for thermal printers
- Receipt formatting with school branding
- QR code support (ready for order tracking)

**Note:** For thermal printing, use the monochrome logo at 72-80px for 80mm thermal printers.

## App Icons

### Android

The Android app icons use adaptive icon support:

- **Foreground:** `android/app/src/main/res/drawable/ic_launcher_foreground.svg`
- **Background:** `android/app/src/main/res/drawable/ic_launcher_background.svg`

To generate PNG icons from SVG:

```bash
# Option 1: Use Android Studio Asset Studio
# 1. Open Android Studio
# 2. Right-click android/app/src/main/res
# 3. New → Image Asset
# 4. Select "Adaptive Icons"
# 5. Use the SVG files as source
# 6. Generate for all densities

# Option 2: Use command-line tools
# Install imagemagick:
brew install imagemagick

# Generate MDPI (1x)
convert -density 72 ic_launcher_foreground.svg -resize 108x108 icon_foreground_mdpi.png
convert -density 72 ic_launcher_background.svg -resize 108x108 icon_background_mdpi.png

# Generate HDPI (1.5x)
convert -density 108 ic_launcher_foreground.svg -resize 162x162 icon_foreground_hdpi.png
convert -density 108 ic_launcher_background.svg -resize 162x162 icon_background_hdpi.png

# Generate XHDPI (2x)
convert -density 144 ic_launcher_foreground.svg -resize 216x216 icon_foreground_xhdpi.png
convert -density 144 ic_launcher_background.svg -resize 216x216 icon_background_xhdpi.png

# Generate XXHDPI (3x)
convert -density 216 ic_launcher_foreground.svg -resize 324x324 icon_foreground_xxhdpi.png
convert -density 216 ic_launcher_background.svg -resize 324x324 icon_background_xxhdpi.png

# Generate XXXHDPI (4x)
convert -density 288 ic_launcher_foreground.svg -resize 432x432 icon_foreground_xxxhdpi.png
convert -density 288 ic_launcher_background.svg -resize 432x432 icon_background_xxxhdpi.png
```

### iOS

iOS icons are configured in `ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json`.

To generate iOS icons:

```bash
# Using Xcode Asset Catalog Editor:
# 1. Open Xcode
# 2. Open ios/Runner.xcworkspace
# 3. Navigate to Assets.xcassets → AppIcon
# 4. Update each required icon size from the illume_logo_icon.svg
# 5. Required sizes:
#    - 20x20@2x (40x40)
#    - 20x20@3x (60x60)
#    - 29x29@2x (58x58)
#    - 29x29@3x (87x87)
#    - 40x40@2x (80x80)
#    - 40x40@3x (120x120)
#    - 60x60@2x (120x120)
#    - 60x60@3x (180x180)
#    - 76x76@1x (76x76)
#    - 76x76@2x (152x152)
#    - 83.5x83.5@2x (167x167)
#    - 1024x1024@1x (1024x1024)
```

## Color Scheme

- **Primary Gold/Accent:** #D4AF37 (Illume Gold)
- **Light Gold:** #E8D5B7
- **Background:** #0A0A0A (Deep Black)
- **Surface:** #141414 (Elevated Surface)
- **Text Primary:** #FFFFFF
- **Text Muted:** #757575

All colors are defined in `lib/core/constants/app_colors.dart`.

## Performance Considerations

1. **Logo Preloading:** SVG logos are loaded once and cached by Flutter
2. **No Oversized Assets:** All logos use vector SVG for optimal file size
3. **Thermal Printer Optimization:** Monochrome logo has no gradients for reliable printing
4. **Responsive Scaling:** Logos automatically scale based on screen size

## Responsive Design

The logos scale appropriately across devices:

- **Desktop:** Large logos (64px-120px)
- **Tablet:** Medium logos (48px-64px)
- **Mobile:** Compact logos (28px-40px)

Sizes are managed in the individual logo widget components with the `size` parameter.

## Design Quality

The implementation follows:

- Apple-level design cleanliness
- Enterprise luxury aesthetic
- Minimal, premium styling
- High-end retail software appearance

## Next Steps

1. Generate platform-specific icon assets (see instructions above)
2. Test splash screen animation across all devices
3. Verify logo rendering on dark mode
4. Test receipt printing with thermal printer
5. Validate responsive scaling on tablet/mobile/desktop

## Notes

- SVG logos will render crisp on any screen size
- For web deployment, SVG assets are optimal
- For native builds, convert SVG to PNG using the provided commands
- All branding is non-intrusive and maintains focus on POS functionality
