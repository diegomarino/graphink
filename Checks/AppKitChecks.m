// Exercise the production path category against exact cubic equivalents.
#import <AppKit/AppKit.h>
#import <OmniAppKit/NSBezierPath-OAExtensions.h>
#include <assert.h>
#include <math.h>

static void CheckPoint(NSPoint a, NSPoint b)
{
    assert(fabs(a.x - b.x) < 1e-9 && fabs(a.y - b.y) < 1e-9);
}

static NSPoint QuadraticPoint(NSPoint start, NSPoint control, NSPoint end, double t)
{
    double u = 1 - t;
    return NSMakePoint(u*u*start.x + 2*u*t*control.x + t*t*end.x,
                       u*u*start.y + 2*u*t*control.y + t*t*end.y);
}

static void CheckEquivalent(NSBezierPath *quadratic, NSBezierPath *cubic)
{
    assert(quadratic.elementCount == cubic.elementCount);
    assert([quadratic isEqual:cubic] && [cubic isEqual:quadratic]);
    assert(quadratic.hash == cubic.hash);
    assert([quadratic strokesSimilarlyIgnoringEndcapsToPath:cubic]);
    NSDictionary *plist = [quadratic propertyListRepresentation];
    assert([plist isEqual:[cubic propertyListRepresentation]]);
    NSError *error = nil;
    NSData *xml = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    assert(xml && !error);
    NSDictionary *decoded = [NSPropertyListSerialization propertyListWithData:xml options:0 format:NULL error:&error];
    assert(decoded && !error && [decoded isEqual:plist]);
    NSBezierPath *restored = [NSBezierPath bezierPath];
    [restored loadPropertyListRepresentation:decoded];
    assert([restored isEqual:cubic] && restored.hash == cubic.hash);
    for (NSInteger i = 1; i < cubic.elementCount; i++) {
        NSPoint points[3];
        NSBezierPathElement element = [cubic elementAtIndex:i associatedPoints:points];
        if (element != NSBezierPathElementCubicCurveTo && element != NSBezierPathElementLineTo)
            continue;
        CheckPoint([quadratic currentpointForSegment:i], [cubic currentpointForSegment:i]);
        for (int step = 0; step <= 8; step++) {
            double t = step / 8.0;
            CheckPoint([quadratic getPointForPosition:(OABezierPathPosition){i, t}],
                       [cubic getPointForPosition:(OABezierPathPosition){i, t}]);
        }
        double qTotal = 0, cTotal = 0;
        double qLength = [quadratic lengthToSegment:i parameter:0.5 totalLength:&qTotal];
        double cLength = [cubic lengthToSegment:i parameter:0.5 totalLength:&cTotal];
        assert(fabs(qLength - cLength) < 1e-8 && fabs(qTotal - cTotal) < 1e-8);
    }
    for (int step = 1; step < 8; step++) {
        double qp = 0, cp = 0;
        NSInteger qs = [quadratic segmentAndParameter:&qp afterLength:step / 8.0 fractional:YES];
        NSInteger cs = [cubic segmentAndParameter:&cp afterLength:step / 8.0 fractional:YES];
        assert(qs == cs && fabs(qp - cp) < 1e-8);
    }
    NSRect hit = NSMakeRect(3, 2, 3, 2), miss = NSMakeRect(100, 100, 1, 1);
    assert([quadratic intersectsRect:hit] == [cubic intersectsRect:hit]);
    assert(![quadratic intersectsRect:miss] && ![cubic intersectsRect:miss]);
    NSPoint qHit = NSZeroPoint, cHit = NSZeroPoint;
    NSPoint from = NSMakePoint(4, -20), to = NSMakePoint(4, 20);
    BOOL qi = [quadratic intersectionWithLine:&qHit lineStart:from lineEnd:to];
    BOOL ci = [cubic intersectionWithLine:&cHit lineStart:from lineEnd:to];
    assert(qi && ci);
    CheckPoint(qHit, cHit);
    OABezierPathIntersection *qFirst = [OABezierPathIntersection new], *cFirst = [OABezierPathIntersection new];
    assert([quadratic firstIntersectionWithLine:qFirst lineStart:from lineEnd:to]);
    assert([cubic firstIntersectionWithLine:cFirst lineStart:from lineEnd:to]);
    CheckPoint(qFirst.location, cFirst.location);
    assert(qFirst.left.segment == cFirst.left.segment);
    assert(fabs(qFirst.left.parameter - cFirst.left.parameter) < 1e-8);
    NSBezierPath *probe = [NSBezierPath bezierPath];
    [probe moveToPoint:from]; [probe lineToPoint:to];
    NSArray<OABezierPathIntersection *> *qIntersections = [quadratic allIntersectionsWithPath:probe];
    NSArray<OABezierPathIntersection *> *cIntersections = [cubic allIntersectionsWithPath:probe];
    assert(qIntersections.count > 0 && qIntersections.count == cIntersections.count);
    for (NSUInteger i = 0; i < qIntersections.count; i++)
        CheckPoint([qIntersections[i] location], [cIntersections[i] location]);
    NSPoint onCurve = QuadraticPoint(NSZeroPoint, NSMakePoint(3, 6), NSMakePoint(9, 0), 0.5);
    CGFloat qt = 0, ct = 0;
    NSInteger qSegment = [quadratic segmentHitByPoint:onCurve position:&qt padding:0.01];
    NSInteger cSegment = [cubic segmentHitByPoint:onCurve position:&ct padding:0.01];
    assert(qSegment == 1 && qSegment == cSegment && fabs(qt - ct) < 1e-8);
}

int main(void)
{
    @autoreleasepool {
        CGMutablePathRef raw = CGPathCreateMutable();
        CGPathMoveToPoint(raw, NULL, 0, 0);
        CGPathAddQuadCurveToPoint(raw, NULL, 3, 6, 9, 0);
        CGPathAddQuadCurveToPoint(raw, NULL, 12, -6, 18, 0);
        CGPathAddLineToPoint(raw, NULL, 21, 0);
        CGPathAddCurveToPoint(raw, NULL, 22, 2, 25, 2, 27, 0);
        CGPathAddQuadCurveToPoint(raw, NULL, 30, 6, 36, 0);
        NSBezierPath *quadratic = [NSBezierPath bezierPathWithCGPath:raw];
        CGPathRelease(raw);
        NSBezierPath *cubic = [NSBezierPath bezierPath];
        [cubic moveToPoint:NSZeroPoint];
        [cubic curveToPoint:NSMakePoint(9, 0) controlPoint1:NSMakePoint(2, 4) controlPoint2:NSMakePoint(5, 4)];
        [cubic curveToPoint:NSMakePoint(18, 0) controlPoint1:NSMakePoint(11, -4) controlPoint2:NSMakePoint(14, -4)];
        [cubic lineToPoint:NSMakePoint(21, 0)];
        [cubic curveToPoint:NSMakePoint(27, 0) controlPoint1:NSMakePoint(22, 2) controlPoint2:NSMakePoint(25, 2)];
        [cubic curveToPoint:NSMakePoint(36, 0) controlPoint1:NSMakePoint(29, 4) controlPoint2:NSMakePoint(32, 4)];
        CheckEquivalent(quadratic, cubic);
        NSDictionary *first = [quadratic propertyListRepresentation][@"elements"][1];
        assert([first[@"element"] isEqual:@"CURVETO"]);
        CheckPoint(NSPointFromString(first[@"control1"]), NSMakePoint(2, 4));
        CheckPoint(NSPointFromString(first[@"control2"]), NSMakePoint(5, 4));
        CheckPoint(NSPointFromString(first[@"point"]), NSMakePoint(9, 0));
        for (int step = 0; step <= 16; step++) {
            double t = step / 16.0;
            CheckPoint([quadratic getPointForPosition:(OABezierPathPosition){1, t}],
                       QuadraticPoint(NSZeroPoint, NSMakePoint(3, 6), NSMakePoint(9, 0), t));
        }
        assert([quadratic elementAtIndex:1] == NSBezierPathElementQuadraticCurveTo);
        // Closed and multiple subpaths exercise current-point recovery across close/move.
        [quadratic closePath]; [cubic closePath];
        [quadratic moveToPoint:NSMakePoint(40, 10)];
        [quadratic curveToPoint:NSMakePoint(49, 10) controlPoint:NSMakePoint(43, 16)];
        [cubic moveToPoint:NSMakePoint(40, 10)];
        [cubic curveToPoint:NSMakePoint(49, 10) controlPoint1:NSMakePoint(42, 14) controlPoint2:NSMakePoint(45, 14)];
        CheckEquivalent(quadratic, cubic);
        assert([quadratic elementAtIndex:quadratic.elementCount - 1] == NSBezierPathElementQuadraticCurveTo);
        // A close restores the subpath's move point, not the preceding segment endpoint.
        NSBezierPath *afterClose = [NSBezierPath bezierPath];
        [afterClose moveToPoint:NSMakePoint(1, 2)];
        [afterClose lineToPoint:NSMakePoint(7, 2)];
        [afterClose closePath];
        [afterClose curveToPoint:NSMakePoint(10, 2) controlPoint:NSMakePoint(4, 8)];
        NSBezierPath *closedCubic = [NSBezierPath bezierPath];
        [closedCubic moveToPoint:NSMakePoint(1, 2)];
        [closedCubic lineToPoint:NSMakePoint(7, 2)];
        [closedCubic closePath];
        [closedCubic curveToPoint:NSMakePoint(10, 2) controlPoint1:NSMakePoint(3, 6) controlPoint2:NSMakePoint(6, 6)];
        assert([[afterClose propertyListRepresentation] isEqual:[closedCubic propertyListRepresentation]]);
        assert([afterClose isEqual:closedCubic] && afterClose.hash == closedCubic.hash);
        assert([afterClose elementAtIndex:afterClose.elementCount - 1] == NSBezierPathElementQuadraticCurveTo);
        puts("Production quadratic/cubic geometry, intersections, length, hash and XML/plist checks passed");
    }
    return 0;
}
