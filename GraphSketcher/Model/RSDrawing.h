// The export drawing seam. Geometry and layout belong to the renderer, not the backend.
#import <Foundation/Foundation.h>

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <AppKit/AppKit.h>

@protocol RSDrawing <NSObject>
// Path styling (width, dash/phase, cap, join, miter, winding rule) travels with the path.
- (void)strokePath:(NSBezierPath *)path color:(NSColor *)color;
- (void)fillPath:(NSBezierPath *)path color:(NSColor *)color;
- (void)fillRect:(NSRect)rect color:(NSColor *)color;
- (void)drawAttributedString:(NSAttributedString *)string atPoint:(NSPoint)point rotation:(CGFloat)degrees;
@end

// Synchronous, thread-local, nestable and exception-safe. nil uses normal AppKit drawing.
void RSWithDrawingBackend(id<RSDrawing> backend, void (^draw)(void));
void RSStrokeDrawingPath(NSBezierPath *path, NSColor *color);
void RSFillDrawingPath(NSBezierPath *path, NSColor *color);
void RSFillDrawingRect(NSRect rect, NSColor *color);
void RSDrawAttributedString(NSAttributedString *string, NSPoint point, CGFloat degrees);
#else
// Keep the archived iPad renderer's native path operations.
#define RSStrokeDrawingPath(path, color) do { [(color) set]; [(path) stroke]; } while (0)
#define RSFillDrawingPath(path, color) do { [(color) set]; [(path) fill]; } while (0)
#endif
