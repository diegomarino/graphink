#import "RSDrawing.h"

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
static __thread id<RSDrawing> currentBackend;

void RSWithDrawingBackend(id<RSDrawing> backend, void (^draw)(void))
{
    id<RSDrawing> previous = currentBackend;
    currentBackend = [backend retain];
    @try {
        draw();
    } @finally {
        currentBackend = previous;
        [backend release];
    }
}

void RSStrokeDrawingPath(NSBezierPath *path, NSColor *color)
{
    if (currentBackend) [currentBackend strokePath:path color:color];
    else { [color set]; [path stroke]; }
}

void RSFillDrawingPath(NSBezierPath *path, NSColor *color)
{
    if (currentBackend) [currentBackend fillPath:path color:color];
    else { [color set]; [path fill]; }
}

void RSFillDrawingRect(NSRect rect, NSColor *color)
{
    if (currentBackend) [currentBackend fillRect:rect color:color];
    else { [color set]; [NSBezierPath fillRect:rect]; }
}

void RSDrawAttributedString(NSAttributedString *string, NSPoint point, CGFloat degrees)
{
    if (currentBackend) {
        [currentBackend drawAttributedString:string atPoint:point rotation:degrees];
    } else if (degrees) {
        [NSGraphicsContext saveGraphicsState];
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform translateXBy:point.x yBy:point.y];
        [transform rotateByDegrees:degrees];
        [transform concat];
        [string drawWithRect:NSMakeRect(0, 0, 0, 0) options:NSStringDrawingUsesLineFragmentOrigin];
        [NSGraphicsContext restoreGraphicsState];
    } else {
        [string drawWithRect:NSMakeRect(point.x, point.y, 0, 0) options:NSStringDrawingUsesLineFragmentOrigin];
    }
}
#endif
