// Standalone seam checks: exact native pixels, forwarding, nesting and exception cleanup.
#import "RSDrawing.h"

@interface DrawingRecorder : NSObject <RSDrawing>
@property(nonatomic) NSUInteger count;
@property(nonatomic, retain) NSBezierPath *path;
@property(nonatomic, retain) NSColor *color;
@end
@implementation DrawingRecorder
- (void)strokePath:(NSBezierPath *)path color:(NSColor *)color { self.count++; self.path = path; self.color = color; }
- (void)fillPath:(NSBezierPath *)path color:(NSColor *)color { self.count++; self.path = path; self.color = color; }
- (void)fillRect:(NSRect)rect color:(NSColor *)color { self.count++; self.color = color; }
- (void)drawAttributedString:(NSAttributedString *)string atPoint:(NSPoint)point rotation:(CGFloat)degrees { self.count++; }
- (void)dealloc { [_path release]; [_color release]; [super dealloc]; }
@end

static NSBitmapImageRep *Draw(BOOL seam)
{
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:240 pixelsHigh:180 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0] autorelease];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    NSRect rect = NSMakeRect(0, 0, 240, 180);
    NSColor *white = [NSColor whiteColor], *ink = [NSColor colorWithCalibratedRed:0.2 green:0.4 blue:0.7 alpha:0.6];
    NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(25, 35, 160, 90)];
    [path setLineWidth:3.25];
    CGFloat dash[] = {4, 2};
    [path setLineDash:dash count:2 phase:0.75];
    [path setLineCapStyle:NSLineCapStyleRound];
    [path setLineJoinStyle:NSLineJoinStyleBevel];
    NSAttributedString *string = [[[NSAttributedString alloc] initWithString:@"First & line\nSecond" attributes:@{NSFontAttributeName:[NSFont fontWithName:@"HelveticaNeue" size:15], NSForegroundColorAttributeName:ink}] autorelease];
    if (seam) {
        RSFillDrawingRect(rect, white);
        RSFillDrawingPath(path, ink);
        RSStrokeDrawingPath(path, ink);
        RSDrawAttributedString(string, NSMakePoint(40, 30), 0);
        RSDrawAttributedString(string, NSMakePoint(60, 90), 35);
    } else {
        [white set]; [NSBezierPath fillRect:rect];
        [ink set]; [path fill]; [path stroke];
        [string drawWithRect:NSMakeRect(40, 30, 0, 0) options:NSStringDrawingUsesLineFragmentOrigin];
        [NSGraphicsContext saveGraphicsState];
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform translateXBy:60 yBy:90]; [transform rotateByDegrees:35]; [transform concat];
        [string drawWithRect:NSZeroRect options:NSStringDrawingUsesLineFragmentOrigin];
        [NSGraphicsContext restoreGraphicsState];
    }
    [NSGraphicsContext restoreGraphicsState];
    return rep;
}

int main(void)
{
    @autoreleasepool {
        NSBitmapImageRep *before = Draw(NO), *after = Draw(YES);
        if (before.bytesPerRow != after.bytesPerRow || memcmp(before.bitmapData, after.bitmapData, (size_t)before.bytesPerRow * (size_t)before.pixelsHigh)) return 1;
        DrawingRecorder *outer = [[[DrawingRecorder alloc] init] autorelease];
        DrawingRecorder *inner = [[[DrawingRecorder alloc] init] autorelease];
        NSBezierPath *path = [NSBezierPath bezierPath];
        NSColor *color = [NSColor redColor];
        RSWithDrawingBackend(outer, ^{
            RSStrokeDrawingPath(path, color);
            @try {
                RSWithDrawingBackend(inner, ^{
                    RSFillDrawingPath(path, color);
                    [NSException raise:@"DrawingCheck" format:@"test cleanup"];
                });
            } @catch (NSException *exception) {
                if (![exception.name isEqual:@"DrawingCheck"]) @throw;
            }
            RSFillDrawingRect(NSZeroRect, color);
            RSDrawAttributedString([[[NSAttributedString alloc] initWithString:@"text"] autorelease], NSZeroPoint, 90);
        });
        if (outer.count != 3 || inner.count != 1 || outer.path != path || outer.color != color) return 1;
        // The recorder must have been removed before the next ordinary export.
        after = Draw(YES);
        if (outer.count != 3 || memcmp(before.bitmapData, after.bitmapData, (size_t)before.bytesPerRow * (size_t)before.pixelsHigh)) return 1;
        puts("PASS drawing seam: identical AppKit pixels, forwarding, nested scopes, exception cleanup");
    }
    return 0;
}
