// Offscreen checks that snap and hit distances are a constant 6 screen points at every zoom.
// No application delegate, launch loop or visible window. Writes transcript-100.txt (every 100%
// probe result, full precision) so check-snap-distance.py can compare it with another build's.
#import "GraphDocument.h"
#import "GraphWindowController.h"
#import "RSGraphView.h"
#import "RSMode.h"
#import "RSTool.h"
#import <GraphSketcherModel/RSGraphEditor.h>
#import <GraphSketcherModel/RSDataMapper.h>
#import <GraphSketcherModel/RSHitTester.h>
#import <GraphSketcherModel/RSAxis.h>
#import <GraphSketcherModel/RSConnectLine.h>
#import <GraphSketcherModel/RSGroup.h>
#import <GraphSketcherModel/RSVertex.h>
#import <GraphSketcherModel/RSUndoer.h>
#import <OmniFoundation/OFController.h>

// check-snap-distance.py drops the document types from the fixture's Info.plist, so the
// fixture controller makes GraphDocuments itself.
@interface FixtureDocumentController : NSDocumentController
@end
@implementation FixtureDocumentController
- (id)makeUntitledDocumentOfType:(NSString *)typeName error:(NSError **)outError {
    return [[[GraphDocument alloc] initWithType:RSGraphFileType error:outError] autorelease];
}
@end
@interface RSTool (SnapDistanceChecks)
- (BOOL)commitEditing;
@end
@interface GraphWindowController (SnapDistanceChecks)
- (void)installInspectorSidebar;
- (void)updateWindowSize;
@end
static void Check(BOOL condition, NSString *message) {
    if (!condition) [NSException raise:@"SnapDistanceCheckFailure" format:@"%@", message];
}
static void Drain(void) {
    __block BOOL finished = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ finished = YES; });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (!finished && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:deadline];
    Check(finished, @"Main queue did not drain");
}
static const CGFloat ScreenDistance = 6;  // the decision: 6 screen points at every zoom
static NSMutableString *Transcript;
static void Record(NSString *zoom, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);
static void Record(NSString *zoom, NSString *format, ...) {
    if (![zoom isEqualToString:@"100%"]) return;
    va_list arguments; va_start(arguments, format);
    [Transcript appendFormat:@"%@\n", [[[NSString alloc] initWithFormat:format arguments:arguments] autorelease]];
    va_end(arguments);
}

// The production window controller and scroll view around a real RSGraphView, in a non-deferred
// offscreen window (as in check-zoom-accessibility.py) so synthetic events have a window to target.
@interface FixtureGraphView : RSGraphView
- (void)useDocument:(GraphDocument *)document;
@end
@implementation FixtureGraphView
- (void)useDocument:(GraphDocument *)document { _document = document; }
@end
@interface SnapWindowController : GraphWindowController
- (void)prepare;
@end
@implementation SnapWindowController
- (void)prepare {
    GraphDocument *document = self.document;
    _graph = [document.graph retain];
    FixtureGraphView *view = [[[FixtureGraphView alloc] initWithFrame:NSMakeRect(0, 20, 520, 420)] autorelease];
    [view useDocument:document];
    _graphView = view;
    document.graphView = view;
    [view setRSSelector:document.selectorObject];
    [self.window.contentView addSubview:view];
    [self installInspectorSidebar];
    [self updateWindowSize];
    view.editor = document.editor;
    [_graph addObserver:self forKeyPath:@"canvasSize" options:0 context:NULL];
    [_graph addObserver:self forKeyPath:@"whitespace" options:0 context:NULL];
    [document addObserver:self forKeyPath:@"graph" options:0 context:NULL];
    self.window.delegate = (id)self;
}
@end
static NSScrollView *ScrollView(GraphWindowController *owner) { return [owner valueForKey:@"_graphScrollView"]; }
static void SelectZoom(GraphWindowController *owner, NSInteger index) {
    NSPopUpButton *zoom = [owner valueForKey:@"_viewportZoom"];
    [zoom selectItemAtIndex:index]; [owner changeViewportZoom:zoom]; Drain();
}
static NSEvent *MouseEvent(RSGraphView *view, NSPoint point, NSEventType type, NSEventModifierFlags flags) {
    Check(NSPointInRect(point, view.visibleRect), [NSString stringWithFormat:@"Synthetic event %@ falls outside the visible viewport %@", NSStringFromPoint(point), NSStringFromRect(view.visibleRect)]);
    return [NSEvent mouseEventWithType:type location:[view convertPoint:point toView:nil] modifierFlags:flags timestamp:0 windowNumber:view.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
}
static void Click(RSGraphView *view, NSPoint point) {
    [view mouseMoved:MouseEvent(view, point, NSEventTypeMouseMoved, 0)];
    [view mouseDown:MouseEvent(view, point, NSEventTypeLeftMouseDown, 0)];
    [view mouseUp:MouseEvent(view, point, NSEventTypeLeftMouseUp, 0)];
}
static NSPoint ViewPoint(RSGraphView *view, RSVertex *vertex) { return [view.editor.mapper convertToViewCoords:vertex.position]; }
// Two Draw clicks, no modifiers; returns the line's end points in canvas (view) coordinates.
static RSConnectLine *DrawLine(GraphDocument *document, NSPoint start, NSPoint end, NSPoint *outStart, NSPoint *outEnd) {
    RSGraphView *view = document.graphView;
    NSUInteger lines = document.graph.Lines.count;
    [[RSMode sharedModeController] registerClick:RS_draw];
    Click(view, start);
    Click(view, end);
    [(id)view.currentTool commitEditing];
    [[RSMode sharedModeController] registerClick:RS_modify];
    Check(document.graph.Lines.count == lines + 1, @"Draw created no production line");
    RSConnectLine *line = document.graph.Lines.lastObject;
    Check([line isKindOfClass:RSConnectLine.class] && line.vertices.elements.count == 2, @"Two Draw clicks make a two-point line");
    *outStart = ViewPoint(view, line.vertices.elements[0]);
    *outEnd = ViewPoint(view, line.vertices.elements[1]);
    return line;
}
// Each section starts from an empty graph, so earlier lines cannot be snapped to.
static void ClearDrawing(GraphDocument *document) {
    RSGraph *graph = document.graph;
    for (RSGraphElement *element in [[graph.Lines copy] autorelease]) [graph removeElement:element];
    for (RSGraphElement *element in [[graph.Vertices copy] autorelease]) [graph removeElement:element];
    Check(graph.Lines.count == 0 && graph.Vertices.count == 0, @"The fixture graph is empty again");
    [document.undoer endRepetitiveUndo]; Drain();
}
static void Centre(RSGraphView *view, NSPoint point) {
    NSRect visible = view.visibleRect;
    [view scrollPoint:NSMakePoint(point.x - NSWidth(visible) / 2, point.y - NSHeight(visible) / 2)]; Drain();
}
// A probe just inside and just outside 6 screen points beyond an object's own extent.
static const CGFloat Inside = 5.5, Outside = 6.5;

// Every check at one zoom. mag is the scroll view's magnification: 1 canvas unit = mag screen points.
static void CheckZoom(NSString *zoom, NSInteger popupIndex, CGFloat expected) {
    OFPreferenceWrapper *preferences = [OFPreferenceWrapper sharedPreferenceWrapper];
    NSError *error = nil;
    GraphDocument *document = [[[GraphDocument alloc] initWithType:RSGraphFileType error:&error] autorelease];
    Check(document != nil, error.description);
    NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1400, 900) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO] autorelease];
    SnapWindowController *owner = [[[SnapWindowController alloc] initWithWindow:window] autorelease];
    [document addWindowController:owner];
    [owner prepare];
    // Large enough that Fit is clearly not 100%.
    [document.editor setCanvasSize:NSMakeSize(2400, 1600)];
    [document.undoer endRepetitiveUndo]; Drain();
    SelectZoom(owner, popupIndex);
    RSGraphView *view = document.graphView;
    RSGraph *graph = document.graph;
    RSDataMapper *mapper = view.editor.mapper;
    RSHitTester *hitTester = view.editor.hitTester;
    CGFloat mag = ScrollView(owner).magnification;
    if (expected > 0) Check(mag == expected, [NSString stringWithFormat:@"%@ sets magnification %g (got %g)", zoom, expected, mag]);
    else Check(mag < 0.75, [NSString stringWithFormat:@"Fit on a 2400 x 1600 canvas is well below 100%% (got %g)", mag]);
    Check(!window.visible, @"Fixture window stays offscreen");

    // 1. The hit tester follows the magnification; each sensitivity is 6 screen points.
    Check(hitTester.scale == mag, [NSString stringWithFormat:@"%@: hit tester scale %g follows magnification %g", zoom, hitTester.scale, mag]);
    struct { NSString *name, *key; CGFloat value; } sensitivities[] = {
        {@"selection", @"SelectionSensitivity", hitTester.selectionSensitivity},
        {@"snap to object", @"SnapToObjectSensitivity", hitTester.snapToObjectSensitivity},
        {@"snap to grid", @"SnapToGridSensitivity", hitTester.snapToGridSensitivity},
    };
    for (NSUInteger index = 0; index < 3; index++) {
        CGFloat preference = [preferences floatForKey:sensitivities[index].key];
        Check(preference == ScreenDistance, [NSString stringWithFormat:@"%@ default is %g", sensitivities[index].key, ScreenDistance]);
        Check(fabs(sensitivities[index].value * mag - ScreenDistance) < 1e-9, [NSString stringWithFormat:@"%@: %@ sensitivity is %g canvas units = %g screen points", zoom, sensitivities[index].name, sensitivities[index].value, sensitivities[index].value * mag]);
        if (mag == 1) Check(sensitivities[index].value == preference, @"At 100% each sensitivity is exactly its preference value");
        Record(zoom, @"sensitivity %@ %.17g", sensitivities[index].key, sensitivities[index].value);
        NSLog(@"PASS %@: %@ = %.4g canvas units = %.4g screen points", zoom, sensitivities[index].name, sensitivities[index].value, sensitivities[index].value * mag);
    }

    // 2. Selecting a line, an axis, an axis end and a margin guide: hit inside 6 screen points
    // beyond the object's own extent, missed outside.
    [preferences setBool:NO forKey:@"SnapToGrid"];
    CGPoint mins = mapper.viewMins, maxes = mapper.viewMaxes;
    NSPoint middle = NSMakePoint((mins.x + maxes.x) / 2, (mins.y + maxes.y) / 2);
    Centre(view, middle);
    NSPoint a, b;
    RSConnectLine *reference = DrawLine(document, NSMakePoint(middle.x - 120 / mag, middle.y), NSMakePoint(middle.x + 120 / mag, middle.y + 0.4 / mag), &a, &b);
    Check(fabs(b.y - a.y) < 1e-9, @"The reference line is snapped horizontal (0.4 screen points apart)");
    Record(zoom, @"reference line %.17g %.17g -> %.17g %.17g", a.x, a.y, b.x, b.y);
    CGFloat lineExtent = reference.width / 2;
    for (NSNumber *distance in @[@(Inside), @(Outside)]) {
        NSPoint probe = NSMakePoint(middle.x, a.y + lineExtent + distance.doubleValue / mag);
        BOOL hit = [hitTester hitTestPoint:probe onLine:reference].hit && [hitTester elementUnderPoint:probe] == reference;
        Check(hit == (distance.doubleValue < ScreenDistance), [NSString stringWithFormat:@"%@: a point %g screen points beyond the line is %@", zoom, distance.doubleValue, hit ? @"selected" : @"not selected"]);
        Record(zoom, @"line probe %.17g %.17g hit %d", probe.x, probe.y, hit);
    }
    RSAxis *xAxis = graph.xAxis;
    CGFloat axisY = [mapper convertToViewCoords:[mapper originPoint]].y;
    NSPoint axisPoint = NSMakePoint(middle.x, axisY);
    Centre(view, axisPoint);
    for (NSNumber *distance in @[@(Inside), @(Outside)]) {
        NSPoint probe = NSMakePoint(axisPoint.x, axisY - xAxis.width / 2 - distance.doubleValue / mag);
        BOOL hit = [hitTester hitTestPoint:probe onAxis:xAxis].hit;
        Check(hit == (distance.doubleValue < ScreenDistance), [NSString stringWithFormat:@"%@: a point %g screen points below the x axis is %@", zoom, distance.doubleValue, hit ? @"on it" : @"off it"]);
        Record(zoom, @"axis probe %.17g %.17g hit %d", probe.x, probe.y, hit);
        probe = NSMakePoint(maxes.x + xAxis.width / 2 + distance.doubleValue / mag, axisY);
        RSAxisEnd end = [hitTester hitTestPoint:probe onEndsOfAxis:xAxis];
        Check((end == RSAxisXMax) == (distance.doubleValue < ScreenDistance), [NSString stringWithFormat:@"%@: a point %g screen points past the x axis end is %@", zoom, distance.doubleValue, end == RSAxisXMax ? @"on it" : @"off it"]);
        Record(zoom, @"axis end probe %.17g %.17g end %d", probe.x, probe.y, (int)end);
        probe = NSMakePoint(mins.x - distance.doubleValue / mag, middle.y);
        NSUInteger edge = [hitTester marginGuideUnderPoint:probe];
        Check((edge != 0) == (distance.doubleValue < ScreenDistance), [NSString stringWithFormat:@"%@: a point %g screen points left of the plot area is %@ its margin guide", zoom, distance.doubleValue, edge ? @"on" : @"off"]);
        Record(zoom, @"margin probe %.17g %.17g edge %lu", probe.x, probe.y, (unsigned long)edge);
    }
    NSLog(@"PASS %@: line, axis, axis end and margin guide hit within %g and missed at %g screen points", zoom, Inside, Outside);

    ClearDrawing(document);

    // 3. Snap to object (90 degrees to the previous point), Draw tool, Snap to Grid off: the second
    // click snaps level with the first 5 screen points away, and lands under the pointer 7 away.
    NSPoint start = NSMakePoint(middle.x - 100 / mag, middle.y + 60 / mag);
    Centre(view, NSMakePoint(middle.x, middle.y + 60 / mag));
    for (NSNumber *distance in @[@5, @7]) {
        start.y += 30 / mag;
        NSPoint end = NSMakePoint(start.x + 200 / mag, start.y + distance.doubleValue / mag);
        DrawLine(document, start, end, &a, &b);
        Check(NSEqualPoints(a, start) || hypot(a.x - start.x, a.y - start.y) < 1e-9, @"The first Draw click lands under the pointer");
        BOOL snapped = fabs(b.y - a.y) < 1e-9;
        Check(snapped == (distance.doubleValue < ScreenDistance), [NSString stringWithFormat:@"%@: second Draw point %g screen points off level %@ (%@ for %@)", zoom, distance.doubleValue, snapped ? @"snapped level" : @"stayed under the pointer", NSStringFromPoint(b), NSStringFromPoint(end)]);
        if (!snapped) Check(hypot(b.x - end.x, b.y - end.y) < 1e-9, @"An unsnapped Draw point is under the pointer");
        Record(zoom, @"draw level %@ %.17g %.17g -> %.17g %.17g", distance, a.x, a.y, b.x, b.y);
        NSLog(@"PASS %@: Draw point %@ screen points off level with the first %@ (moved %.3g screen points)", zoom, distance, snapped ? @"snaps level" : @"stays under the pointer", hypot(b.x - end.x, b.y - end.y) * mag);
    }

    ClearDrawing(document);

    // 4. Snap to Grid, Draw tool: a point 5 screen points from a tick line snaps onto it, 7 away does not.
    [preferences setBool:YES forKey:@"SnapToGrid"];
    start = NSMakePoint(middle.x - 150 / mag, middle.y - 120 / mag);
    Centre(view, NSMakePoint(middle.x, middle.y - 80 / mag));
    for (NSNumber *distance in @[@5, @7]) {
        start.x += 25 / mag;
        NSPoint end = NSMakePoint(start.x + 220 / mag, 0);
        CGFloat tickY = [mapper convertToViewCoords:RSDataPointMake(0, [mapper closestGridLineTo:start.y + 60 / mag onAxis:graph.yAxis])].y;
        end.y = tickY + distance.doubleValue / mag;
        CGFloat nextTick = [mapper convertToViewCoords:RSDataPointMake(0, [mapper closestGridLineTo:end.y + 8 / mag onAxis:graph.yAxis])].y;
        Check(nextTick == tickY || (nextTick - tickY) * mag > 2 * ScreenDistance + 2, @"Tick lines are far enough apart on screen to probe 7 points away");
        DrawLine(document, start, end, &a, &b);
        Check(fabs(b.y - a.y) * mag > ScreenDistance, @"Grid fixture points are not level with each other");
        BOOL snapped = fabs(b.y - tickY) < 1e-9;
        Check(snapped == (distance.doubleValue < ScreenDistance), [NSString stringWithFormat:@"%@: a Draw point %g screen points above a tick line %@ (%@, tick at y %.6g, plot y %.6g to %.6g)", zoom, distance.doubleValue, snapped ? @"snapped onto it" : @"did not snap", NSStringFromPoint(b), tickY, mins.y, maxes.y]);
        if (!snapped) Check(fabs(b.y - end.y) < 1e-9, [NSString stringWithFormat:@"%@: an unsnapped grid coordinate stays under the pointer (%.6g for %.6g)", zoom, b.y, end.y]);
        CGFloat tickX = [mapper convertToViewCoords:RSDataPointMake([mapper closestGridLineTo:end.x onAxis:graph.xAxis], 0)].x;
        Check(fabs(b.x - end.x) < 1e-9 || (fabs(b.x - tickX) < 1e-9 && fabs(end.x - tickX) * mag < ScreenDistance), [NSString stringWithFormat:@"%@: x snaps only onto a tick within 6 screen points (pointer x %.6g, point x %.6g, nearest tick x %.6g)", zoom, end.x, b.x, tickX]);
        Record(zoom, @"draw grid %@ %.17g %.17g -> %.17g %.17g", distance, a.x, a.y, b.x, b.y);
        NSLog(@"PASS %@: Snap to Grid, Draw point %@ screen points above a tick line %@", zoom, distance, snapped ? @"snaps onto it" : @"stays under the pointer");
    }
    [preferences removeObjectForKey:@"SnapToGrid"];
    [document.undoManager removeAllActions]; [document updateChangeCount:NSChangeCleared];
    [document close];
    NSLog(@"PASS %@ (magnification %g): snapping and selection distances are %g screen points", zoom, mag, ScreenDistance);
}

// Magnification changed other than through the zoom popup (pinch uses the same calls): the hit
// tester follows, and returning to 100% restores exactly the preference values.
static void CheckLiveMagnification(void) {
    NSError *error = nil;
    GraphDocument *document = [[[GraphDocument alloc] initWithType:RSGraphFileType error:&error] autorelease];
    Check(document != nil, error.description);
    NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1400, 900) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO] autorelease];
    SnapWindowController *owner = [[[SnapWindowController alloc] initWithWindow:window] autorelease];
    [document addWindowController:owner];
    [owner prepare];
    [document.editor setCanvasSize:NSMakeSize(2400, 1600)];
    [document.undoer endRepetitiveUndo]; Drain();
    NSScrollView *scroll = ScrollView(owner);
    RSHitTester *hitTester = document.graphView.editor.hitTester;
    Check(hitTester.scale == 1 && scroll.magnification == 1, @"A new window starts at 100% with hit tester scale 1");
    scroll.magnification = 3; Drain();
    Check(hitTester.scale == 3, [NSString stringWithFormat:@"magnification = 3 sets hit tester scale (got %g)", hitTester.scale]);
    [scroll setMagnification:1.5 centeredAtPoint:NSMakePoint(600, 400)]; Drain();
    Check(hitTester.scale == 1.5, [NSString stringWithFormat:@"setMagnification:centeredAtPoint: 1.5 sets hit tester scale (got %g)", hitTester.scale]);
    SelectZoom(owner, 5);
    Check(hitTester.scale == scroll.magnification && scroll.magnification < 0.75, @"Fit sets hit tester scale");
    [document.editor setCanvasSize:NSMakeSize(1200, 800)]; [document.undoer endRepetitiveUndo]; Drain();
    Check(hitTester.scale == scroll.magnification, [NSString stringWithFormat:@"Fit after a canvas change keeps hit tester scale %g = magnification %g", hitTester.scale, scroll.magnification]);
    SelectZoom(owner, 2);
    Check(hitTester.scale == 1 && hitTester.selectionSensitivity == [[OFPreferenceWrapper sharedPreferenceWrapper] floatForKey:@"SelectionSensitivity"], @"Back at 100% the selection sensitivity is exactly the preference");
    [document.undoManager removeAllActions]; [document updateChangeCount:NSChangeCleared];
    [document close];
    puts("PASS live magnification changes (direct, centred, Fit, canvas change, back to 100%) update the hit tester");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool { @try {
        Check(argc >= 2, @"Pass an owned output directory");
        NSString *output = @(argv[1]);
        [(Class)NSBundle.mainBundle.principalClass sharedApplication];
        [[FixtureDocumentController alloc] init];
        Check([NSBundle.mainBundle.bundleIdentifier hasPrefix:@"com.graphink.snapdistancechecks."], @"Unique fixture domain required");
        NSString *domain = NSBundle.mainBundle.bundleIdentifier;
        CFPreferencesSetAppValue(CFSTR("SnapDistanceIsolationProbe"), (CFStringRef)domain, kCFPreferencesCurrentApplication);
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
        id probe = [(id)CFPreferencesCopyAppValue(CFSTR("SnapDistanceIsolationProbe"), (CFStringRef)domain) autorelease];
        Check([probe isEqual:domain], @"Current-application defaults did not route to the unique fixture domain");
        NSLog(@"Preference routing verified: %@", domain);
        OFController *lifecycle = OFController.sharedController;
        Check([lifecycle isKindOfClass:NSClassFromString(@"AppController")], @"OFControllerClass is the production AppController");
        [lifecycle didInitialize]; [lifecycle startedRunning];
        Check(NSApp.delegate == nil, @"Fixture must not install the application delegate");
        Transcript = [NSMutableString string];
        // 100% first, so another build's 100% transcript is written even if its other zooms fail.
        CheckZoom(@"100%", 2, 1);
        NSError *error = nil;
        Check([Transcript writeToFile:[output stringByAppendingPathComponent:@"transcript-100.txt"] atomically:YES encoding:NSUTF8StringEncoding error:&error], error.description);
        puts("PASS 100% transcript written");
        CheckZoom(@"25%", 0, 0.25);
        CheckZoom(@"400%", 4, 4);
        CheckZoom(@"Fit", 5, 0);
        CheckLiveMagnification();
        Check([lifecycle requestTermination] == OFControllerTerminateNow, @"Fixture lifecycle refused termination");
        [lifecycle willTerminate];
        puts("PASS snap distance checks: 6 screen points at 25%, 100%, 400% and Fit; offscreen only");
    } @catch (NSException *exception) {
        NSLog(@"FAIL snap distance: %@", exception); return 1;
    } }
    return 0;
}
