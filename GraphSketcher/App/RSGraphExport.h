#import <AppKit/AppKit.h>

// File ▸ Export and `graphink render` both export through these functions, so the app and the
// command-line tool cannot draw a document differently (#18 was such a drift: the app's raster
// export scaled twice while the tool's copy of it did not). RSGraphView -drawRect: also uses
// RSDrawGraphForExport whenever it is not drawing to the screen (saved preview, copy, EPS, print).
//
// `editor` must already be laid out for `bounds` (-updateBounds: and -prepareForDisplay), as a
// graph view's editor is before it draws.

@class RSGraphEditor;

// What an export shows: the background and every graph element. Never the selection, tool
// feedback or the window's transparency.
void RSDrawGraphForExport(RSGraphEditor *editor);

// One vector PDF page of bounds.size points, drawn by an offscreen view.
NSData *RSGraphPDFData(RSGraphEditor *editor, NSRect bounds);

// The whole canvas offscreen at `dpi`: 8-bit RGBA, calibrated RGB, RSRasterPixelSize pixels. The
// rep's point size is the canvas size, so the image records the resolution.
NSBitmapImageRep *RSGraphBitmapImageRep(RSGraphEditor *editor, NSRect bounds, CGFloat dpi);

// PNG, JPEG (quality 1) or TIFF via ImageIO, with `dpi` recorded even at 72. `typeIdentifier` is
// public.png, public.jpeg or public.tiff; nil for any other type.
NSData *RSGraphRasterData(RSGraphEditor *editor, NSRect bounds, NSString *typeIdentifier, CGFloat dpi);
