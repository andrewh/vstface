# EditorHost Modifications

This project includes a modified version of the VST3 SDK's EditorHost sample
application, located in `src/editorhost/`. The code was copied from the VST3 SDK
rather than referenced as a submodule to allow for custom modifications.

## Why We Forked EditorHost

The original EditorHost sample has several issues when used with real-world plugins:

1. **Oversized windows**: When plugins don't report their size upfront, EditorHost
   defaults to creating a 2048x1536 window
2. **No screen bounds checking**: Large plugin windows can extend off-screen
3. **Size mismatch**: The window size doesn't update after plugin attachment even
   when the plugin reports its actual size

## Modifications Made

### 1. Screen Bounds Constraining (`src/editorhost/source/platform/mac/window.mm:79-92`)

Added logic to constrain window creation to 95% of screen dimensions:

```cpp
// Constrain to screen if necessary
NSScreen* screen = [NSScreen mainScreen];
NSRect visibleFrame = [screen visibleFrame];
CGFloat maxWidth = visibleFrame.size.width * 0.95;
CGFloat maxHeight = visibleFrame.size.height * 0.95;

if (finalWidth > maxWidth || finalHeight > maxHeight) {
    CGFloat scale = std::min(maxWidth / finalWidth, maxHeight / finalHeight);
    finalWidth = std::floor(finalWidth * scale);
    finalHeight = std::floor(finalHeight * scale);
}
```

This ensures that even if a plugin requests a massive window, it will be scaled
down proportionally to fit on screen.

### 2. Reduced Fallback Size (`src/editorhost/source/editorhost.cpp:217-221`)

Changed the fallback size from 2048x1536 to 800x600 when plugins don't initially
report their size:

```cpp
if (result != kResultTrue)
{
    // Use reasonable fallback size; window will be resized after attachment
    plugViewSize.right = 800;
    plugViewSize.bottom = 600;
}
```

### 3. Post-Attachment Window Resize (`src/editorhost/source/editorhost.cpp:326-339`)

Added logic to resize the window to match the plugin's actual size after the
plugin view is attached:

```cpp
// After attachment, resize window to match plugin's actual size
ViewRect plugRect {};
if (plugView->getSize (&plugRect) == kResultTrue)
{
    int32 plugWidth = plugRect.right - plugRect.left;
    int32 plugHeight = plugRect.bottom - plugRect.top;
    auto windowSize = window->getContentSize ();

    if (plugWidth > 0 && plugHeight > 0 &&
        (plugWidth != windowSize.width || plugHeight != windowSize.height))
    {
        window->resize ({plugWidth, plugHeight});
    }
}
```

Many plugins (like Raum.vst3) don't know their size until after they're attached
to a window. This change queries the plugin's size after attachment and resizes
the window to match exactly.

### 4. Removed Manual Resize in vstface (`src/ScreenshotHost.mm:367-368`)

Removed the manual `runner.resizeContent()` call that was forcing windows to
the default 1024x768 size, allowing EditorHost's automatic sizing to work:

```cpp
// Before:
runner.resizeContent(opts.width, opts.height);  // Forced 1024x768

// After:
// EditorHost automatically resizes window to match plugin size after attachment
// No need to manually resize
```

This ensures that screenshots capture the plugin's actual size rather than forcing
a fixed window size.

## Testing

The modifications were tested with:
- **Raum.vst3** (reports size as 616x382 only after attachment)
  - EditorHost window: exactly 616x382
  - vstface screenshot: 616x414 (includes titlebar)
- **vstface_test_fixture** (our built-in test plugin)

Both plugins now display with windows that exactly match their UI size, and
screenshots capture the actual plugin dimensions.

## License

EditorHost is part of the VST3 SDK and is licensed under the same terms as the
SDK itself. See `third_party/vst3sdk/LICENSE.txt` for details.

## Updating

If you need to update EditorHost to a newer SDK version:

1. Copy the latest EditorHost source from the SDK:
   ```bash
   cp -r third_party/vst3sdk/public.sdk/samples/vst-hosting/editorhost/source/ src/editorhost/
   ```

2. Reapply the modifications listed above

3. Update include paths by running:
   ```bash
   find src/editorhost/source -type f \( -name "*.cpp" -o -name "*.mm" -o -name "*.h" \) -exec sed -i '' 's|public.sdk/samples/vst-hosting/editorhost/source/||g' {} \;
   ```

4. Test thoroughly with both the test fixture and real plugins
