// Offscreen zoom popup accessibility, assertion handler and 400% Draw mapping checks.
// No application delegate, launch loop, menu tracking or visible window.
#import "GraphDocument.h"
#import "GraphWindowController.h"
#import "RSGraphView.h"
#import "RSMode.h"
#import "RSTool.h"
#import <GraphSketcherModel/RSGraphEditor.h>
#import <GraphSketcherModel/RSDataMapper.h>
#import <GraphSketcherModel/RSConnectLine.h>
#import <GraphSketcherModel/RSGroup.h>
#import <GraphSketcherModel/RSVertex.h>
#import <GraphSketcherModel/RSUndoer.h>
#import <OmniFoundation/OFController.h>
#import <objc/runtime.h>

// check-zoom-accessibility.py drops the document types from the fixture's Info.plist, so the
// fixture controller makes GraphDocuments itself; everything else is NSDocumentController's own code.
@interface FixtureDocumentController : NSDocumentController
@end
@implementation FixtureDocumentController
- (id)makeUntitledDocumentOfType:(NSString *)typeName error:(NSError **)outError {
    return [[[GraphDocument alloc] initWithType:RSGraphFileType error:outError] autorelease];
}
@end
@interface RSTool (ZoomAccessibilityChecks)
- (BOOL)commitEditing;
@end
static void Check(BOOL condition, NSString *message) {
    if (!condition) [NSException raise:@"ZoomAccessibilityCheckFailure" format:@"%@", message];
}
static void Drain(void) {
    __block BOOL finished = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ finished = YES; });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (!finished && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:deadline];
    Check(finished, @"Main queue did not drain");
}
// Count AppKit's private open-for-inspection pair (fixture-only instrumentation, original
// implementations still run) to prove the walk exercises the path that asserted in step 13.
static NSUInteger SimulatedOpens, SimulatedCloses;
static void CountSimulatedOpenClose(void) {
    Method open = class_getInstanceMethod(NSMenu.class, NSSelectorFromString(@"_simulateOpening:"));
    Method close = class_getInstanceMethod(NSMenu.class, NSSelectorFromString(@"_simulateClosed"));
    Check(open && close, @"AppKit still has -[NSMenu _simulateOpening:] and -[NSMenu _simulateClosed]");
    void (*openIMP)(id, SEL, NSUInteger) = (void *)method_getImplementation(open);
    void (*closeIMP)(id, SEL) = (void *)method_getImplementation(close);
    SEL openSEL = method_getName(open), closeSEL = method_getName(close);
    method_setImplementation(open, imp_implementationWithBlock(^(id menu, NSUInteger flags) { SimulatedOpens++; openIMP(menu, openSEL, flags); }));
    method_setImplementation(close, imp_implementationWithBlock(^(id menu) { SimulatedCloses++; closeIMP(menu, closeSEL); }));
}
static const NSRect Screen = {{0, 0}, {1440, 875}};
static const NSRect SmallScreen = {{0, 0}, {1280, 775}};
static NSArray *ZoomTitles(void) { return @[@"25%", @"50%", @"100%", @"200%", @"400%", @"Fit"]; }

// A nib-loaded production window (toolbar, sidebar, status bar, zoom popup), never shown.
static GraphWindowController *OpenWindow(GraphDocument *document, NSRect visibleFrame) {
    [(NSDocumentController *)NSDocumentController.sharedDocumentController addDocument:document];
    [document makeWindowControllers];
    GraphWindowController *owner = document.windowControllers.firstObject;
    Check(owner.window != nil && !owner.window.visible, @"Nib window loaded and not shown");
    [owner chooseInitialWindowFrameInVisibleFrame:visibleFrame];
    Drain(); [document.undoManager removeAllActions]; [document updateChangeCount:NSChangeCleared];
    return owner;
}
static void ClearFrameKeys(void) {
    for (NSString *key in @[@"LastFrameString", @"LastCanvasSize"]) [[OFPreferenceWrapper sharedPreferenceWrapper] removeObjectForKey:key];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"NSWindow Frame RSGraphDocumentWindow"];
}
// Every legacy attribute of one element; an AppKit exception or assertion fails the run.
static NSUInteger ReadAllAttributes(id element, NSString *what) {
    NSArray *names = [element accessibilityAttributeNames];
    Check(names.count > 0, [what stringByAppendingString:@" exposes no accessibility attributes"]);
    for (NSString *name in names) {
        @try { [element accessibilityAttributeValue:name]; }
        @catch (NSException *exception) { Check(NO, [NSString stringWithFormat:@"%@ %@ raised %@", what, name, exception]); }
    }
    return names.count;
}
// What an accessibility client (VoiceOver, computer use) reads from the zoom popup while its menu is closed.
static void CheckZoomAccessibility(GraphWindowController *owner, NSString *state) {
    NSPopUpButton *zoom = [owner valueForKey:@"_viewportZoom"];
    NSMenu *menu = zoom.menu;
    NSString *selected = zoom.titleOfSelectedItem;
    Check([zoom.itemTitles isEqual:ZoomTitles()], [NSString stringWithFormat:@"%@: the zoom items are exactly %@ (%@)", state, ZoomTitles(), zoom.itemTitles]);
    Check(zoom.selectedItem != nil && zoom.selectedItem.menu == menu && [menu indexOfItem:zoom.selectedItem] == zoom.indexOfSelectedItem, [state stringByAppendingString:@": the selected item belongs to the popup's menu"]);
    for (NSMenuItem *item in menu.itemArray) {
        Check(item.menu == menu && !item.hasSubmenu && !item.isSeparatorItem && !item.isHidden && item.view == nil, [state stringByAppendingString:@": plain items owned by the popup's menu"]);
        Check(item.state == (item == zoom.selectedItem ? NSControlStateValueOn : NSControlStateValueOff), [state stringByAppendingString:@": only the selected item is checked"]);
    }
    // Offscreen, the popup's cell answers the legacy AX attributes (the control view is ignored). Its value is the
    // crashing path: NSPopUpButtonCell asks the selected NSMenuItem, which opens the menu for
    // inspection and closes it again (-[NSMenu _simulateClosed]).
    // AppKit skips the inspection open for a menu populated during the last second.
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.1]];
    NSUInteger opens = SimulatedOpens, closes = SimulatedCloses;
    id element = zoom.cell;
    Check([[element accessibilityAttributeValue:NSAccessibilityRoleAttribute] isEqual:NSAccessibilityPopUpButtonRole], [state stringByAppendingString:@": AX role is pop-up button"]);
    Check([zoom.accessibilityLabel isEqual:@"Canvas zoom"], [state stringByAppendingString:@": the popup keeps its accessibility label"]);
    Check([[element accessibilityAttributeValue:NSAccessibilityValueAttribute] isEqual:selected], [NSString stringWithFormat:@"%@: AX value %@ is the selected title %@", state, [element accessibilityAttributeValue:NSAccessibilityValueAttribute], selected]);
    Check(SimulatedOpens > opens && SimulatedCloses - closes == SimulatedOpens - opens, [state stringByAppendingString:@": reading the AX value opened the menu for inspection and closed it again"]);
    NSUInteger attributes = ReadAllAttributes(element, [state stringByAppendingString:@" popup"]);
    NSArray *children = [element accessibilityAttributeValue:NSAccessibilityChildrenAttribute] ?: @[];
    for (id child in children) attributes += ReadAllAttributes(child, [state stringByAppendingString:@" popup child"]);
    for (NSMenuItem *item in menu.itemArray) {
        Check([[item accessibilityAttributeValue:NSAccessibilityTitleAttribute] isEqual:item.title], [NSString stringWithFormat:@"%@: AX title of %@", state, item.title]);
        Check([[item accessibilityAttributeValue:NSAccessibilityEnabledAttribute] boolValue], [NSString stringWithFormat:@"%@: %@ is enabled", state, item.title]);
        Check([item accessibilityAttributeValue:NSAccessibilityParentAttribute] != nil, [NSString stringWithFormat:@"%@: %@ has an AX parent", state, item.title]);
        attributes += ReadAllAttributes(item, [NSString stringWithFormat:@"%@ item %@", state, item.title]);
    }
    Check([zoom.titleOfSelectedItem isEqual:selected] && [zoom.itemTitles isEqual:ZoomTitles()], [state stringByAppendingString:@": reading accessibility changed the popup"]);
    Check(SimulatedCloses - closes == SimulatedOpens - opens, [state stringByAppendingString:@": every inspection open was closed"]);
    NSLog(@"PASS zoom accessibility %@: value %@, %lu children, %lu attributes read, %lu inspection opens/closes", state, selected, (unsigned long)children.count, (unsigned long)attributes, (unsigned long)(SimulatedOpens - opens));
}
static void SelectZoom(GraphWindowController *owner, NSInteger index) {
    NSPopUpButton *zoom = [owner valueForKey:@"_viewportZoom"];
    [zoom selectItemAtIndex:index]; [owner changeViewportZoom:zoom]; Drain();
    NSScrollView *scroll = [owner valueForKey:@"_graphScrollView"];
    CGFloat zooms[] = {0.25, 0.5, 1, 2, 4};
    if (index < 5) Check(fabs(scroll.magnification - zooms[index]) < 1e-9, [NSString stringWithFormat:@"%@ sets magnification %g", zoom.titleOfSelectedItem, zooms[index]]);
}
static void CheckZoomStates(void) {
    ClearFrameKeys();
    NSError *error = nil;
    GraphDocument *document = [[[GraphDocument alloc] initWithType:RSGraphFileType error:&error] autorelease];
    Check(document != nil, error.description);
    GraphWindowController *owner = OpenWindow(document, Screen);
    CheckZoomAccessibility(owner, @"new window");
    // Every state, then the checklist's Fit -> 400% transition and back.
    NSInteger sequence[] = {0, 1, 2, 3, 4, 5, 4, 5, 0, 5, 2};
    for (NSUInteger step = 0; step < sizeof(sequence) / sizeof(*sequence); step++) {
        NSString *from = [[owner valueForKey:@"_viewportZoom"] titleOfSelectedItem];
        SelectZoom(owner, sequence[step]);
        CheckZoomAccessibility(owner, [NSString stringWithFormat:@"%@ -> %@", from, ZoomTitles()[sequence[step]]]);
    }
    Check(!document.isDocumentEdited && !document.undoManager.canUndo, @"Zoom and accessibility reads left the document unchanged");
    [document close];
    // A window that opens in Fit (the production -chooseInitialWindowFrameInVisibleFrame: path).
    ClearFrameKeys();
    NSURL *welcome = [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"NewFrom/Initial/welcome-to-graphink.graphink"];
    document = [[[GraphDocument alloc] initWithType:RSGraphFileType error:&error] autorelease];
    Check(document && [document readFromURL:welcome ofType:RSGraphFileType error:&error], [@"Read the Welcome document: " stringByAppendingString:error.description ?: @""]);
    owner = OpenWindow(document, SmallScreen);
    Check([[[owner valueForKey:@"_viewportZoom"] titleOfSelectedItem] isEqual:@"Fit"], @"Welcome opens in Fit on a 1280 x 800 screen");
    CheckZoomAccessibility(owner, @"opened in Fit");
    SelectZoom(owner, 4);
    CheckZoomAccessibility(owner, @"opened in Fit -> 400%");
    [document close];
    ClearFrameKeys();
    puts("PASS zoom popup accessibility in every zoom state, Fit -> 400% included");
}

// The exact assertion AppKit's -[NSMenu _simulateClosed] fails (macOS 27, NSMenu.m line 1492).
static void SimulateAppKitAssertion(id object, NSString *selector, NSString *file) {
    NSAssertionHandler *handler = NSAssertionHandler.currentHandler;
    Check((id)handler == OFController.sharedController, @"The production OFController subclass is the main thread's assertion handler");
    [handler handleFailureInMethod:NSSelectorFromString(selector) object:object file:file lineNumber:1492 description:@"Shouldn't suppress Close notifications if the menu has been opened"];
}
static void CheckAssertionRule(void) {
    NSMenu *menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    SimulateAppKitAssertion(menu, @"_simulateClosed", @"NSMenu.m");
    SimulateAppKitAssertion(menu, @"_simulateClosed", @"/Library/Caches/com.apple.xbs/Sources/AppKit/AppKit.subproj/NSMenu.m");
    puts("PASS AppKit -[NSMenu _simulateClosed] assertion is logged and execution continues");
}
// Near misses: each must still reach OFController and crash (the runner sets OFCrashShouldExitWithCode).
static void TriggerNearMiss(NSString *mode) {
    NSMenu *menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    NSLog(@"Near miss %@: expecting OFController to crash", mode);
    if ([mode isEqual:@"other-object"]) SimulateAppKitAssertion([[[NSView alloc] init] autorelease], @"_simulateClosed", @"NSMenu.m");
    else if ([mode isEqual:@"other-file"]) SimulateAppKitAssertion(menu, @"_simulateClosed", @"NSMenuItem.m");
    else if ([mode isEqual:@"other-selector"]) SimulateAppKitAssertion(menu, @"_simulateOpening:", @"NSMenu.m");
    else if ([mode isEqual:@"graphink-assert"]) NSCAssert(NO, @"A Graphink NSCAssert still crashes");
    else Check(NO, [@"Unknown near miss " stringByAppendingString:mode]);
    puts("NEAR MISS DID NOT CRASH");
}

// Step 13: Draw at 400%, two clicks 400 x 150 window points apart, as the checklist did. A
// non-deferred window, as in check-viewport.py, so synthetic events have a window to target.
@interface GraphWindowController (ZoomAccessibilityChecks)
- (void)installInspectorSidebar;
- (void)updateWindowSize;
@end
@interface FixtureGraphView : RSGraphView
- (void)useDocument:(GraphDocument *)document;
@end
@implementation FixtureGraphView
- (void)useDocument:(GraphDocument *)document { _document = document; }
@end
@interface DrawWindowController : GraphWindowController
- (void)prepare;
@end
@implementation DrawWindowController
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
static NSEvent *MouseEvent(RSGraphView *view, NSPoint point, NSEventType type, NSEventModifierFlags flags) {
    Check(NSPointInRect(point, view.visibleRect), @"Synthetic Draw event falls outside the visible viewport");
    return [NSEvent mouseEventWithType:type location:[view convertPoint:point toView:nil] modifierFlags:flags timestamp:0 windowNumber:view.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
}
static void DrawClick(RSGraphView *view, NSPoint point, NSEventModifierFlags flags) {
    [view mouseMoved:MouseEvent(view, point, NSEventTypeMouseMoved, flags)];
    [view mouseDown:MouseEvent(view, point, NSEventTypeLeftMouseDown, flags)];
    [view mouseUp:MouseEvent(view, point, NSEventTypeLeftMouseUp, flags)];
}
static NSPoint ViewPoint(RSGraphView *view, RSVertex *vertex) { return [view.editor.mapper convertToViewCoords:vertex.position]; }
// Draws a two-click line and returns its end points in canvas (view) coordinates.
static void DrawLine(GraphDocument *document, NSPoint start, NSPoint end, NSEventModifierFlags secondClickFlags, NSPoint *outStart, NSPoint *outEnd) {
    RSGraphView *view = document.graphView;
    NSUInteger lines = document.graph.Lines.count;
    [[RSMode sharedModeController] registerClick:RS_draw];
    DrawClick(view, start, 0);
    DrawClick(view, end, secondClickFlags);
    [(id)view.currentTool commitEditing];
    Check(document.graph.Lines.count == lines + 1, @"Draw created no production line");
    RSConnectLine *line = document.graph.Lines.lastObject;
    Check([line isKindOfClass:RSConnectLine.class] && line.vertices.elements.count == 2, @"Two Draw clicks make a two-point line");
    *outStart = ViewPoint(view, line.vertices.elements[0]);
    *outEnd = ViewPoint(view, line.vertices.elements[1]);
    [[RSMode sharedModeController] registerClick:RS_modify];
}
static void CheckDrawAt400(void) {
    ClearFrameKeys();
    OFPreferenceWrapper *preferences = [OFPreferenceWrapper sharedPreferenceWrapper];
    Check([preferences boolForKey:@"SnapToGrid"], @"Snap to Grid is on by default");
    NSError *error = nil;
    GraphDocument *document = [[[GraphDocument alloc] initWithType:RSGraphFileType error:&error] autorelease];
    Check(document != nil, error.description);
    NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1400, 900) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO] autorelease];
    DrawWindowController *owner = [[[DrawWindowController alloc] initWithWindow:window] autorelease];
    [document addWindowController:owner];
    [owner prepare];
    [document.editor setCanvasSize:NSMakeSize(1080, 800)];  // the checklist document's canvas
    [document.undoer endRepetitiveUndo]; Drain();
    SelectZoom(owner, 5); SelectZoom(owner, 4);  // Fit -> 400%, as in step 13
    RSGraphView *view = document.graphView;
    RSGraph *graph = document.graph;
    Check(!graph.displayGrid && !graph.noGridComponentsAreDisplayed, @"A new graph shows ticks but no grid: snap to grid still applies to tick positions");
    [view scrollPoint:NSMakePoint(300, 250)]; Drain();
    NSRect visible = view.visibleRect;
    Check(NSMinX(visible) > 0 && NSMinY(visible) > 0 && !window.visible, @"Draw fixture actually scrolled at 400%, offscreen");
    NSPoint start = NSMakePoint(NSMinX(visible) + 40.3, NSMinY(visible) + 30.7);
    NSPoint end = NSMakePoint(start.x + 100, start.y + 37.5);
    NSPoint windowStart = [view convertPoint:start toView:nil], windowEnd = [view convertPoint:end toView:nil];
    Check(fabs(windowEnd.x - windowStart.x - 400) < 1e-6 && fabs(windowEnd.y - windowStart.y - 150) < 1e-6,
          [NSString stringWithFormat:@"At 400%% a 100 x 37.5 canvas step is 400 x 150 window points (got %@)", NSStringFromSize(NSMakeSize(windowEnd.x - windowStart.x, windowEnd.y - windowStart.y))]);
    // 1. Mapping alone: Snap to Grid off, no modifiers -> both points exactly under the pointer.
    [preferences setBool:NO forKey:@"SnapToGrid"];
    NSPoint a, b;
    DrawLine(document, start, end, 0, &a, &b);
    Check(hypot(a.x - start.x, a.y - start.y) < 0.01 && hypot(b.x - end.x, b.y - end.y) < 0.01,
          [NSString stringWithFormat:@"400%% Draw line lands under the pointer: %@ -> %@ for %@ -> %@", NSStringFromPoint(a), NSStringFromPoint(b), NSStringFromPoint(start), NSStringFromPoint(end)]);
    NSLog(@"PASS 400%% Draw line, Snap to Grid off, no modifiers: ends under the pointer (%@ -> %@ canvas, 400 x 150 window points)", NSStringFromPoint(a), NSStringFromPoint(b));
    // 2. Shift or Command straightens: the second point keeps the pointer's x and the first point's y.
    for (NSNumber *flags in @[@(NSEventModifierFlagShift), @(NSEventModifierFlagCommand)]) {
        NSPoint s = NSMakePoint(start.x, start.y + 40), e = NSMakePoint(end.x, end.y + 40);
        DrawLine(document, s, e, flags.unsignedIntegerValue, &a, &b);
        Check(fabs(b.x - e.x) < 0.01 && fabs(b.y - s.y) < 0.01, [NSString stringWithFormat:@"Straightened Draw line is horizontal at the first point's y (%@)", NSStringFromPoint(b)]);
        NSLog(@"PASS 400%% Draw line with %@ held on the second click is horizontal: second point %@ instead of %@ (%.1f window points above the pointer)",
              flags.unsignedIntegerValue == NSEventModifierFlagShift ? @"Shift" : @"Command", NSStringFromPoint(b), NSStringFromPoint(e), (e.y - b.y) * 4);
        start = s; end = e;
    }
    // 3. Default Snap to Grid: a coordinate within 6 screen points (1.5 canvas units at 400%) of a
    // tick moves onto it; it never produces the 37.5-unit step-13 offset.
    [preferences setBool:YES forKey:@"SnapToGrid"];
    RSDataMapper *mapper = view.editor.mapper;
    NSPoint s = NSMakePoint(start.x, start.y + 40), e = NSMakePoint(end.x, end.y + 40);
    // Put the second point 1 unit (4 window points) above the nearest horizontal tick line, so it must snap.
    e.y = [mapper convertToViewCoords:RSDataPointMake(0, [mapper closestGridLineTo:e.y onAxis:graph.yAxis])].y + 1;
    Check(fabs(e.y - s.y) > 6, @"Grid-snap fixture points are not within 90-degree snapping distance");
    DrawLine(document, s, e, 0, &a, &b);
    Check(fabs(b.x - e.x) < 0.01 && fabs(b.y - (e.y - 1)) < 0.01, [NSString stringWithFormat:@"Snap to Grid pulls a point 1 unit from a tick onto it (%@ for %@)", NSStringFromPoint(b), NSStringFromPoint(e)]);
    NSPoint points[] = {s, e}, results[] = {a, b};
    for (NSUInteger index = 0; index < 2; index++) {
        RSDataPoint tick = RSDataPointMake([mapper closestGridLineTo:points[index].x onAxis:graph.xAxis], [mapper closestGridLineTo:points[index].y onAxis:graph.yAxis]);
        NSPoint tickView = [mapper convertToViewCoords:tick];
        CGFloat dx = fabs(results[index].x - points[index].x), dy = fabs(results[index].y - points[index].y);
        Check(dx < 1.5 && dy < 1.5, @"Snap to Grid moves a coordinate by less than its 6-screen-point (1.5-unit) sensitivity");
        Check((dx < 0.01 || fabs(results[index].x - tickView.x) < 0.01) && (dy < 0.01 || fabs(results[index].y - tickView.y) < 0.01), @"A snapped coordinate lands on the nearest tick");
        NSLog(@"PASS 400%% Draw, Snap to Grid on: %@ -> %@ (moved %.2f, %.2f canvas units; nearest ticks %@)", NSStringFromPoint(points[index]), NSStringFromPoint(results[index]), dx, dy, NSStringFromPoint(tickView));
    }
    [preferences removeObjectForKey:@"SnapToGrid"];
    [document.undoManager removeAllActions]; [document updateChangeCount:NSChangeCleared];
    [document close];
    ClearFrameKeys();
    puts("PASS 400% Draw mapping: unmodified clicks land under the pointer; grid snaps stay within 6 screen points; only Shift/Command make the step-13 horizontal line");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool { @try {
        Check(argc >= 2, @"Pass an owned output directory");
        [(Class)NSBundle.mainBundle.principalClass sharedApplication];  // OAApplication, as in the app; nib-loaded windows need it
        [[FixtureDocumentController alloc] init];  // the first document controller becomes the shared one, as RSDocumentController does in main.m
        Check([NSBundle.mainBundle.bundleIdentifier hasPrefix:@"com.graphink.zoomaccessibilitychecks."], @"Unique fixture domain required");
        NSString *domain = NSBundle.mainBundle.bundleIdentifier;
        CFPreferencesSetAppValue(CFSTR("ZoomAccessibilityIsolationProbe"), (CFStringRef)domain, kCFPreferencesCurrentApplication);
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
        id probe = [(id)CFPreferencesCopyAppValue(CFSTR("ZoomAccessibilityIsolationProbe"), (CFStringRef)domain) autorelease];
        Check([probe isEqual:domain], @"Current-application defaults did not route to the unique fixture domain");
        NSLog(@"Preference routing verified: %@", domain);
        OFController *lifecycle = OFController.sharedController;
        Check([lifecycle isKindOfClass:NSClassFromString(@"AppController")], @"OFControllerClass is the production AppController");
        [lifecycle didInitialize]; [lifecycle startedRunning];
        Check(NSApp.delegate == nil, @"Fixture must not install the application delegate");
        Check([[OFPreference preferenceForKey:@"OFCrashOnAssertionOrUnhandledException"] boolValue], @"Fixture keeps OmniFoundation's crash-on-assertion default");
        if (argc >= 4 && !strcmp(argv[2], "--near-miss")) {
            TriggerNearMiss(@(argv[3]));
            return 2;
        }
        CountSimulatedOpenClose();
        CheckZoomStates();
        CheckAssertionRule();
        CheckDrawAt400();
        Check([lifecycle requestTermination] == OFControllerTerminateNow, @"Fixture lifecycle refused termination");
        [lifecycle willTerminate];
        puts("PASS zoom accessibility checks; offscreen only");
    } @catch (NSException *exception) {
        NSLog(@"FAIL zoom accessibility: %@", exception); return 1;
    } }
    return 0;
}
