# ILLUME POS Branding - Quick Reference Guide

## Logo Usage Quick Reference

### Import the Logo Widget
```dart
import 'package:pos_app/presentation/shared/widgets/illume_logo.dart';
```

### Use Logo Components

#### Icon Only (Compact)
```dart
LogoIcon(size: 48)                    // Default 48px
LogoIcon(size: 36)                    // Smaller version
LogoIcon(size: 64, shadow: true)      // With glow effect
```

#### Horizontal (Header)
```dart
LogoHorizontal(height: 64)            // Default 64px
LogoHorizontal(height: 48)            // Compact version
LogoHorizontal(height: 120)           // Large version
```

#### Monochrome (Print)
```dart
LogoMonochrome(size: 48)              // Standard
LogoMonochrome(size: 48, forPrint: true)  // For receipts
```

---

## Screen Integration Examples

### Login Screen
```dart
const LogoIcon(size: 64, shadow: true)
```

### POS Top Bar
```dart
const LogoIcon(size: 36)
```

### Cart Panel
```dart
const LogoIcon(size: 28)
```

### School Selection Header
```dart
const LogoIcon(size: 40)
```

---

## Navigation Routes

```dart
// Splash screen (initial)
context.go('/splash')

// Login
context.go('/')

// School selection
context.go('/schools')

// POS screen
context.go('/pos')
```

---

## Assets

### Logo Files
- `assets/icons/illume_logo_icon.svg`
- `assets/icons/illume_logo_horizontal.svg`
- `assets/icons/illume_logo_monochrome.svg`

### Asset Path Format
```dart
Image.asset('assets/icons/illume_logo_icon.svg')
```

---

## Colors

### Primary Accent
```dart
Color accent = Color(0xFFD4AF37)  // Illume Gold
```

### Usage
```dart
color: AppColors.accent  // Use constants
```

---

## Splash Screen Timing

- Animation Duration: 1200ms
- Auto-navigate Delay: 2500ms
- Total Time on Screen: ~2.5 seconds

---

## Common Tasks

### Add Logo to New Screen
1. Import the widget
2. Place LogoIcon where needed
3. Adjust size parameter as needed

### Update Logo Size
```dart
// Change size parameter
LogoIcon(size: 40)  // Adjust this number
```

### Customize Logo Styling
- Use LogoIcon() for basic logo
- Use LogoIcon(shadow: true) for depth
- Wrap in Container for additional styling

---

## Testing

### Run Branding Tests
```bash
flutter test test/branding_test.dart
```

### Manual Testing Screens
1. Launch app → Splash screen
2. Wait 2.5s → Login screen
3. Enter credentials → School selection
4. Select school → POS screen

---

## File Locations

### Widget Definition
`lib/presentation/shared/widgets/illume_logo.dart`

### Splash Screen
`lib/presentation/auth/splash_screen.dart`

### Router Configuration
`lib/core/router/app_router.dart`

### Tests
`test/branding_test.dart`

### Documentation
- `BRANDING_GUIDE.md` - Full branding guide
- `IMPLEMENTATION_SUMMARY.md` - Implementation details
- `DEPLOYMENT_CHECKLIST.md` - Deployment verification
- `QUICK_REFERENCE.md` - This file

---

## Troubleshooting

### Logo not displaying?
- Check asset path in pubspec.yaml
- Verify file exists in assets/icons/
- Run `flutter pub get`

### Logo rendering issues?
- Check device orientation
- Verify screen width (responsive sizing)
- Test on different screen sizes

### Splash screen not auto-navigating?
- Check router configuration
- Verify navigation context is mounted
- Check Future.delayed timing

### Size issues?
- Adjust `size` parameter on LogoIcon
- Check screen width (mobile/tablet/desktop)
- Verify responsive breakpoints

---

## Performance Tips

1. Logos are SVG - no rasterization overhead
2. Assets cached by Flutter automatically
3. Minimal file sizes (<5KB each)
4. No performance impact on startup

---

## Future Enhancements

- [ ] Icon generation automation
- [ ] Dynamic splash screen text
- [ ] Additional branding assets
- [ ] Animated logo variants
- [ ] Locale-specific branding

---

## Quick Checklist

- [ ] Splash screen displays
- [ ] Logo renders on all screens
- [ ] Navigation works
- [ ] Performance acceptable
- [ ] Tests passing
- [ ] Dark mode visible
- [ ] Responsive sizing works

---

## Support Resources

| Document | Purpose |
|----------|---------|
| BRANDING_GUIDE.md | Complete branding documentation |
| IMPLEMENTATION_SUMMARY.md | Implementation details |
| DEPLOYMENT_CHECKLIST.md | Pre-deployment verification |
| branding_test.dart | Automated tests |

---

**Last Updated:** May 12, 2026  
**Status:** Ready for Use  
**Version:** 1.0
