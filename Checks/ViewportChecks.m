// Offscreen production model/view/tool checks. No application delegate or launch loop.
#import "GraphDocument.h"
#import "GraphWindowController.h"
#import "RSGraphView.h"
#import "RSMode.h"
#import "RSTool.h"
#import "RSSelector.h"
#import <GraphSketcherModel/RSGraphEditor.h>
#import <GraphSketcherModel/RSDataMapper.h>
#import <GraphSketcherModel/RSVertex.h>
#import <GraphSketcherModel/RSFill.h>
#import <GraphSketcherModel/RSGroup.h>
#import <GraphSketcherModel/RSAxis.h>
#import <GraphSketcherModel/RSTextLabel.h>
#import <GraphSketcherModel/RSUndoer.h>
#import <OmniFoundation/OFController.h>

@interface GraphWindowController (ViewportChecks)
- (void)installInspectorSidebar;
- (void)updateWindowSize;
@end
#import "GraphWindowController.h" // RSInitialWindowLayoutForCanvas
#import "RSNewFromCatalog.h"      // -openUntitledCopyOfURL:..., the production New From / Welcome path
@interface GraphWindowController (RealPathChecks)
- (CGFloat)sidebarChromeWidth;
@end
// check-viewport.py drops the document types from the fixture's Info.plist, so the fixture
// controller makes GraphDocuments itself; everything else is NSDocumentController's own code.
@interface FixtureDocumentController : NSDocumentController
@end
@implementation FixtureDocumentController
- (id)makeUntitledDocumentOfType:(NSString *)typeName error:(NSError **)outError {
    return [[[GraphDocument alloc] initWithType:RSGraphFileType error:outError] autorelease];
}
@end
@interface RSTool (ViewportChecks)
- (BOOL)commitEditing;
@end
@interface FixtureGraphView : RSGraphView
- (void)useDocument:(GraphDocument *)document;
@end
@implementation FixtureGraphView
- (void)useDocument:(GraphDocument *)document { _document = document; }
@end
@interface ViewportWindowController : GraphWindowController
- (void)prepare;
@property(readonly) NSScrollView *scroll;
@property(readonly) NSPopUpButton *zoom;
@end
@implementation ViewportWindowController
- (NSScrollView *)scroll { return _graphScrollView; }
- (NSPopUpButton *)zoom { return _viewportZoom; }
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
static void Check(BOOL condition, NSString *message) {
    if (!condition) [NSException raise:@"ViewportCheckFailure" format:@"%@", message];
}
static void Drain(void) {
    __block BOOL finished = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ finished = YES; });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (!finished && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:deadline];
    Check(finished, @"Main queue did not drain");
}
static NSEvent *Event(RSGraphView *view, NSPoint point, NSEventType type) {
    Check(NSPointInRect(point, view.visibleRect), @"Synthetic placement event falls outside the visible viewport");
    return [NSEvent mouseEventWithType:type location:[view convertPoint:point toView:nil] modifierFlags:0 timestamp:0 windowNumber:view.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
}
static void Click(RSGraphView *view, NSPoint point) {
    [view mouseMoved:Event(view, point, NSEventTypeMouseMoved)];
    [view mouseDown:Event(view, point, NSEventTypeLeftMouseDown)];
    [view mouseUp:Event(view, point, NSEventTypeLeftMouseUp)];
}
static void CheckPosition(RSGraphView *view, RSGraphElement *element, NSPoint point) {
    NSPoint actual = [view.editor.mapper convertToViewCoords:element.position];
    Check(hypot(actual.x - point.x, actual.y - point.y) < 0.01, [NSString stringWithFormat:@"Production tool placed an object away from the event's canvas point (%@ for %@)", NSStringFromPoint(actual), NSStringFromPoint(point)]);
}
// A fresh window as the nib makes it (520 x 440 content) around a document, before any frame is chosen.
static ViewportWindowController *FreshWindow(GraphDocument *document) {
    NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(300, 300, 520, 440) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO] autorelease];
    ViewportWindowController *owner = [[[ViewportWindowController alloc] initWithWindow:window] autorelease];
    [document addWindowController:owner];
    [owner prepare];
    // Fixture setup (not the frame choice) may register editor history; measure from a clean state.
    Drain(); [document.undoer endRepetitiveUndo]; [document.undoManager removeAllActions]; [document updateChangeCount:NSChangeCleared];
    return owner;
}
static GraphDocument *WelcomeDocument(void) {
    NSURL *url = [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"NewFrom/Initial/welcome-to-graphink.graphink"];
    NSError *error = nil;
    GraphDocument *document = [[[GraphDocument alloc] initWithType:RSGraphFileType error:&error] autorelease];
    Check(document && [document readFromURL:url ofType:RSGraphFileType error:&error], [@"Read the bundled Welcome document: " stringByAppendingString:error.description ?: @""]);
    [document.undoManager removeAllActions]; [document updateChangeCount:NSChangeCleared];
    Check(NSEqualSizes(document.graph.canvasSize, NSMakeSize(960, 700)), @"Welcome canvas is 960 x 700");
    return document;
}
static GraphDocument *BlankDocument(void) {
    NSError *error = nil;
    GraphDocument *document = [[[GraphDocument alloc] initWithType:RSGraphFileType error:&error] autorelease];
    Check(document != nil, error.description);
    Check(NSEqualSizes(document.graph.canvasSize, NSMakeSize(520, 420)), @"Default canvas is 520 x 420");
    return document;
}
// Representative visible frames: menu bar 25 pt, no Dock.
static const NSRect Screens[] = {{{0, 0}, {1440, 875}}, {{0, 0}, {1280, 775}}, {{0, 0}, {2560, 1415}}};
static void CheckInitialFrames(void) {
    for (NSString *key in @[@"LastFrameString", @"LastCanvasSize"]) [[OFPreferenceWrapper sharedPreferenceWrapper] removeObjectForKey:key];
    Check([[OFPreferenceWrapper sharedPreferenceWrapper] objectForKey:@"LastFrameString"] != nil && ![[OFPreference preferenceForKey:@"LastFrameString"] hasPersistentValue], @"Info.plist registers a LastFrameString default, which is not a saved frame");
    // Pure layout: 100% when it fits, otherwise capped with Fit, always inside the inset visible frame.
    NSSize chrome = NSMakeSize(281, 48), minimum = NSMakeSize(461, 168);
    for (NSUInteger s = 0; s < 3; s++) for (NSUInteger c = 0; c < 2; c++) {
        NSSize canvas = c ? NSMakeSize(520, 420) : NSMakeSize(960, 700);
        NSRect current = NSMakeRect(40, NSMaxY(Screens[s]) - 60 - 488, 801, 488);
        RSInitialWindowLayout layout = RSInitialWindowLayoutForCanvas(canvas, current, NSMakeSize(801 - chrome.width, 488 - chrome.height), minimum, Screens[s]);
        NSRect available = NSInsetRect(Screens[s], RSInitialWindowScreenMargin, RSInitialWindowScreenMargin);
        NSSize needed = NSMakeSize(canvas.width + chrome.width, canvas.height + chrome.height);
        BOOL fits = needed.width <= NSWidth(available) && needed.height <= NSHeight(available);
        Check(layout.fitsAtActualSize == fits && NSContainsRect(available, layout.frame), @"Initial layout must stay inside the inset visible frame");
        Check(NSEqualSizes(layout.frame.size, NSMakeSize(MIN(needed.width, NSWidth(available)), MIN(needed.height, NSHeight(available)))), @"Initial layout must be 100% or the largest capped frame");
        if (NSMaxY(current) - NSHeight(layout.frame) >= NSMinY(available))
            Check(NSMinX(layout.frame) == 40 && NSMaxY(layout.frame) == NSMaxY(current), @"Initial layout keeps the cascaded top-left corner when there is room");
    }
    Check(RSInitialWindowLayoutForCanvas(NSMakeSize(960, 700), NSMakeRect(40, 327, 801, 488), NSMakeSize(520, 440), NSMakeSize(461, 168), Screens[0]).fitsAtActualSize, @"Welcome fits at 100% on 1440 x 900");
    Check(!RSInitialWindowLayoutForCanvas(NSMakeSize(960, 700), NSMakeRect(40, 227, 801, 488), NSMakeSize(520, 440), NSMakeSize(461, 168), Screens[1]).fitsAtActualSize, @"Welcome needs Fit on 1280 x 800");
    Check(RSInitialWindowLayoutForCanvas(NSMakeSize(10, 10), NSMakeRect(40, 327, 801, 488), NSMakeSize(520, 440), NSMakeSize(461, 168), Screens[0]).frame.size.width == 461, @"Tiny canvases keep the window minimum");

    // Production controller on fresh windows: frame, zoom, and no document change.
    for (NSUInteger s = 0; s < 3; s++) for (NSUInteger c = 0; c < 2; c++) {
        GraphDocument *document = c ? BlankDocument() : WelcomeDocument();
        ViewportWindowController *owner = FreshWindow(document);
        NSWindow *window = owner.window;
        NSError *error = nil;
        NSData *before = [document.graph generateXMLOfType:RSGraphFileType frame:CGRectZero error:&error];
        NSSize canvas = document.graph.canvasSize;
        Check([owner chooseInitialWindowFrameInVisibleFrame:Screens[s]], @"A window without a saved frame chooses its initial frame");
        [owner updateWindowSize]; Drain();
        NSRect available = NSInsetRect(Screens[s], RSInitialWindowScreenMargin, RSInitialWindowScreenMargin);
        Check(NSContainsRect(available, window.frame), @"Chosen window frame stays inside the visible frame margin");
        NSSize viewport = owner.scroll.contentSize;
        if (owner.zoom.indexOfSelectedItem == 2) {
            Check(owner.scroll.magnification == 1 && viewport.width >= canvas.width && viewport.height >= canvas.height, @"100% window shows the whole canvas");
        } else {
            Check(owner.zoom.indexOfSelectedItem == 5, @"A canvas that cannot fit at 100% opens in Fit");
            CGFloat m = owner.scroll.magnification;
            Check(m < 1 && canvas.width * m <= viewport.width + 0.5 && canvas.height * m <= viewport.height + 0.5, @"Fit shows the whole canvas");
            Check(NSWidth(window.frame) == NSWidth(available) || NSHeight(window.frame) == NSHeight(available), @"Fit window is the largest that fits");
        }
        NSData *after = [document.graph generateXMLOfType:RSGraphFileType frame:CGRectZero error:&error];
        [document.undoer endRepetitiveUndo];
        Check(NSEqualSizes(canvas, document.graph.canvasSize) && [before isEqual:after], @"Choosing the window frame changed the canvas or document XML");
        Check(!document.isDocumentEdited && !document.undoManager.canUndo, @"Choosing the window frame dirtied the document or added undo");
        NSRect chosen = window.frame;
        Check(![owner chooseInitialWindowFrameInVisibleFrame:Screens[2]] && NSEqualRects(chosen, window.frame), @"The initial frame is chosen once per window (Revert keeps the frame)");
        [window setContentSize:NSMakeSize(500, 300)]; Drain();
        Check(NSEqualSizes(canvas, document.graph.canvasSize) && !document.isDocumentEdited, @"User resizing never changes canvas geometry");
        NSLog(@"PASS initial frame %@ canvas %@ on %@: %@ zoom %@", c ? @"default" : @"Welcome", NSStringFromSize(canvas), NSStringFromSize(Screens[s].size), NSStringFromSize(chosen.size), owner.zoom.titleOfSelectedItem);
        [document close];
        for (NSString *key in @[@"LastFrameString", @"LastCanvasSize"]) [[OFPreferenceWrapper sharedPreferenceWrapper] removeObjectForKey:key];  // windowWillClose saves both
    }
    // Saved frames stay authoritative: LastFrameString for new documents, the autosaved frame for its owner.
    [[OFPreferenceWrapper sharedPreferenceWrapper] setObject:@"100 100 700 500 0 0 1440 875 " forKey:@"LastFrameString"];
    GraphDocument *blank = BlankDocument();
    ViewportWindowController *owner = FreshWindow(blank);
    NSRect frame = owner.window.frame;
    Check(![owner chooseInitialWindowFrameInVisibleFrame:Screens[0]] && NSEqualRects(frame, owner.window.frame), @"LastFrameString stays authoritative");
    [blank close];
    for (NSString *key in @[@"LastFrameString", @"LastCanvasSize"]) [[OFPreferenceWrapper sharedPreferenceWrapper] removeObjectForKey:key];
    NSString *name = [@"ViewportChecks" stringByAppendingString:NSUUID.UUID.UUIDString];
    GraphDocument *welcome = WelcomeDocument();
    owner = FreshWindow(welcome);
    Check([owner.window setFrameAutosaveName:name], @"Fixture autosave name");
    [owner.window saveFrameUsingName:name];
    frame = owner.window.frame;
    Check(![owner chooseInitialWindowFrameInVisibleFrame:Screens[0]] && NSEqualRects(frame, owner.window.frame), @"An autosaved frame stays authoritative");
    [welcome close];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:[@"NSWindow Frame " stringByAppendingString:name]];
    puts("PASS initial window frames: 100% or Fit, inside the screen, once, saved frames authoritative, document unchanged");
}
// The real launch path: a nib-loaded GraphWindowController (toolbar, sidebar, the nib's frame
// autosave name) for the Welcome copy made by the production New From method, and for a blank
// document, on a fresh preference domain. Production -showWindow: chooses the frame with the
// screen's visible frame and then orders the window front; the fixture calls the same choice with
// injected visible frames and never orders a window front.
static NSString * const AutosaveKey = @"NSWindow Frame RSGraphDocumentWindow";
static void ClearFrameKeys(void) {
    for (NSString *key in @[@"LastFrameString", @"LastCanvasSize"]) [[OFPreferenceWrapper sharedPreferenceWrapper] removeObjectForKey:key];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:AutosaveKey];
}
static NSArray *PersistedFrameKeys(void) {
    NSDictionary *domain = [NSUserDefaults.standardUserDefaults persistentDomainForName:NSBundle.mainBundle.bundleIdentifier];
    NSMutableArray *keys = [NSMutableArray array];
    for (NSString *key in @[AutosaveKey, @"LastFrameString"]) if (domain[key]) [keys addObject:key];
    return keys;
}
static void CheckRealLaunchPath(void) {
    FixtureDocumentController *controller = (FixtureDocumentController *)NSDocumentController.sharedDocumentController;
    Check([controller isKindOfClass:FixtureDocumentController.class], @"The fixture document controller is the shared one");
    NSURL *welcome = [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"NewFrom/Initial/welcome-to-graphink.graphink"];
    for (NSUInteger s = 0; s < 3; s++) for (NSUInteger kind = 0; kind < 2; kind++) {
        ClearFrameKeys();
        NSError *error = nil;
        GraphDocument *document;
        if (kind == 0) {
            document = (GraphDocument *)[controller openUntitledCopyOfURL:welcome displayName:@"Welcome to Graphink" ofType:RSGraphFileType display:NO error:&error];
        } else {
            document = [controller makeUntitledDocumentOfType:RSGraphFileType error:&error];
            [controller addDocument:document];
        }
        Check(document != nil, [NSString stringWithFormat:@"Open the document %@: %@", welcome.path, error]);
        [document makeWindowControllers];
        GraphWindowController *owner = document.windowControllers.firstObject;
        NSWindow *window = owner.window;  // nib load: -windowWillLoad, -windowDidLoad (toolbar, sidebar, graph)
        NSSize canvas = document.graph.canvasSize;
        Check(NSEqualSizes(canvas, kind == 0 ? NSMakeSize(960, 700) : NSMakeSize(520, 420)), @"Real path documents have their final canvas");
        Check(!window.visible && window.toolbar != nil && [window.contentView isKindOfClass:NSSplitView.class], @"Nib window with toolbar and sidebar, not shown");
        Check(PersistedFrameKeys().count == 0, [@"Window setup persisted a frame: " stringByAppendingString:[PersistedFrameKeys() componentsJoinedByString:@", "]]);
        Check([owner chooseInitialWindowFrameInVisibleFrame:Screens[s]], @"First show of a window without a saved frame chooses its frame");
        Drain();
        NSScrollView *scroll = [owner valueForKey:@"_graphScrollView"];
        NSPopUpButton *zoom = [owner valueForKey:@"_viewportZoom"];
        NSRect available = NSInsetRect(Screens[s], RSInitialWindowScreenMargin, RSInitialWindowScreenMargin);
        Check(NSContainsRect(available, window.frame), @"Real window stays inside the visible frame margin");
        NSSize viewport = scroll.contentSize;
        if (zoom.indexOfSelectedItem == 2) {
            Check(scroll.magnification == 1 && viewport.width >= canvas.width && viewport.height >= canvas.height,
                  [NSString stringWithFormat:@"Real window shows the whole canvas at 100%% (viewport %@, canvas %@, window %@)", NSStringFromSize(viewport), NSStringFromSize(canvas), NSStringFromRect(window.frame)]);
            Check(NSWidth(window.frame) >= canvas.width + [owner sidebarChromeWidth], @"Real window includes the sidebar width");
        } else {
            CGFloat m = scroll.magnification;
            Check(zoom.indexOfSelectedItem == 5 && m < 1 && canvas.width * m <= viewport.width + 0.5 && canvas.height * m <= viewport.height + 0.5, @"Real window that cannot fit at 100% shows the whole canvas in Fit");
        }
        Check(PersistedFrameKeys().count == 0, @"Choosing the initial frame persisted nothing");
        // Status bar: canvas size / coordinates on the left, the zoom popup at the right end, no overlap.
        NSView *status = [owner valueForKey:@"_statusText"];
        for (NSUInteger pass = 0; pass < 2; pass++) {
            NSRect bar = zoom.superview.bounds, zoomFrame = zoom.frame, statusFrame = [status convertRect:status.bounds toView:zoom.superview];
            Check(NSMaxX(zoomFrame) <= NSMaxX(bar) && NSMaxX(zoomFrame) >= NSMaxX(bar) - 8 && NSMinX(statusFrame) <= 8 && NSMaxX(statusFrame) <= NSMinX(zoomFrame) + 0.5,
                  [NSString stringWithFormat:@"Zoom popup at the right end of the status bar, status text on the left (bar %@, zoom %@, text %@)", NSStringFromRect(bar), NSStringFromRect(zoomFrame), NSStringFromRect(statusFrame)]);
            Check([zoom.accessibilityLabel isEqual:@"Canvas zoom"], @"Zoom popup keeps its accessibility label");
            [window setContentSize:NSMakeSize(900, 500)]; Drain();  // and after a resize
        }
        Check(NSEqualSizes(canvas, document.graph.canvasSize) && !document.isDocumentEdited && !document.undoManager.canUndo, @"Real path left the document unchanged");
        NSLog(@"PASS real launch path %@ canvas %@ on %@: window %@, zoom %@", kind == 0 ? @"Welcome copy" : @"blank document", NSStringFromSize(canvas), NSStringFromSize(Screens[s].size), NSStringFromSize(window.frame.size), zoom.titleOfSelectedItem);
        [document close];
        ClearFrameKeys();
    }
    puts("PASS real launch path: nib window, untitled Welcome copy and blank document sized at first show, nothing persisted during setup");
}
// Untitled copies from File ▸ New From and the Welcome / Getting Started document never seed new
// blank documents (LastCanvasSize, LastFrameString, the autosaved frame), and always open sized
// for their canvas, even over a saved frame. Canvas changes on real documents still persist.
@interface GraphWindowController (CatalogCopyChecks)
- (void)saveGraphFrame;
- (void)resumeFrameAutosave;
@end
static NSDictionary *SeedDefaults(void) {
    NSDictionary *domain = [NSUserDefaults.standardUserDefaults persistentDomainForName:NSBundle.mainBundle.bundleIdentifier];
    NSMutableDictionary *seed = [NSMutableDictionary dictionary];
    for (NSString *key in @[AutosaveKey, @"LastFrameString", @"LastCanvasSize"]) if (domain[key]) seed[key] = domain[key];
    return seed;
}
static GraphWindowController *ShownWindow(GraphDocument *document, NSRect screen, BOOL expectChosen) {
    [document makeWindowControllers];
    GraphWindowController *owner = document.windowControllers.firstObject;
    NSWindow *window = owner.window;
    NSSize canvas = document.graph.canvasSize;
    Check([owner chooseInitialWindowFrameInVisibleFrame:screen] == expectChosen, [NSString stringWithFormat:@"%@: initial frame %@", document.displayName, expectChosen ? @"must be chosen for the canvas" : @"must keep the saved frame"]);
    [owner resumeFrameAutosave];  // as -showWindow: does once the window is shown
    Drain();
    if (!expectChosen) return owner;
    NSScrollView *scroll = [owner valueForKey:@"_graphScrollView"];
    NSPopUpButton *zoom = [owner valueForKey:@"_viewportZoom"];
    NSSize viewport = scroll.contentSize;
    CGFloat m = scroll.magnification;
    Check(NSContainsRect(NSInsetRect(screen, RSInitialWindowScreenMargin, RSInitialWindowScreenMargin), window.frame), [document.displayName stringByAppendingString:@": window stays inside the visible frame margin"]);
    Check((zoom.indexOfSelectedItem == 2 && m == 1) || (zoom.indexOfSelectedItem == 5 && m < 1), [document.displayName stringByAppendingString:@": opens at 100% or Fit"]);
    Check(canvas.width * m <= viewport.width + 0.5 && canvas.height * m <= viewport.height + 0.5,
          [NSString stringWithFormat:@"%@: whole canvas %@ visible (viewport %@ at %.2f, window %@)", document.displayName, NSStringFromSize(canvas), NSStringFromSize(viewport), m, NSStringFromRect(window.frame)]);
    return owner;
}
static void UserMovesAndResizes(GraphWindowController *owner) {
    // A user move/resize on the main window: AppKit autosaves the frame under the window's name,
    // and -windowDidMove:/-windowDidBecomeMain: save LastFrameString and LastCanvasSize.
    NSWindow *window = owner.window;
    [window setFrame:NSOffsetRect(NSInsetRect(window.frame, 10, 10), 15, -15) display:NO]; Drain();
    [owner saveGraphFrame];
}
static void CheckCatalogCopies(void) {
    FixtureDocumentController *controller = (FixtureDocumentController *)NSDocumentController.sharedDocumentController;
    RSNewFromCatalog *catalog = [RSNewFromCatalog mainCatalog];
    NSMutableArray *items = [NSMutableArray arrayWithObject:catalog.initialExample];
    for (RSNewFromGroup *group in catalog.groups) [items addObjectsFromArray:group.items];
    Check(items.count == 31, [NSString stringWithFormat:@"Welcome plus 30 New From items, got %lu", (unsigned long)items.count]);
    // A user's earlier choice on a real document: a 700 x 500 canvas in a small window. The frame
    // string is AppKit's own for this screen, so restoring it at nib load writes it back unchanged.
    NSWindow *probe = [[[NSWindow alloc] initWithContentRect:NSMakeRect(100, 200, 801, 478) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO] autorelease];
    NSString *userFrame = probe.stringWithSavedFrame;
    NSDictionary *userSeed = @{AutosaveKey: userFrame, @"LastFrameString": userFrame, @"LastCanvasSize": NSStringFromSize(NSMakeSize(700, 500))};
    NSUInteger opened = 0;
    for (RSNewFromItem *item in items) for (NSUInteger s = 0; s < 3; s++) for (NSUInteger seeded = 0; seeded < 2; seeded++) {
        ClearFrameKeys();
        if (seeded) for (NSString *key in userSeed) [NSUserDefaults.standardUserDefaults setObject:userSeed[key] forKey:key];
        NSDictionary *before = SeedDefaults();
        NSError *error = nil;
        GraphDocument *document = (GraphDocument *)[controller openUntitledCopyOfURL:item.fileURL displayName:item.title ofType:RSGraphFileType display:NO error:&error];
        Check(document != nil, [NSString stringWithFormat:@"Open %@: %@", item.title, error]);
        GraphWindowController *owner = ShownWindow(document, Screens[s], YES);
        UserMovesAndResizes(owner);
        [document close]; Drain();  // -windowWillClose: saves the frame defaults
        Check([SeedDefaults() isEqual:before], [NSString stringWithFormat:@"%@ changed the defaults that seed new documents: %@ -> %@", item.title, before, SeedDefaults()]);
        GraphDocument *blank = [controller makeUntitledDocumentOfType:RSGraphFileType error:&error];
        NSSize expected = seeded ? NSMakeSize(700, 500) : NSMakeSize(520, 420);
        Check(NSEqualSizes(blank.graph.canvasSize, expected), [NSString stringWithFormat:@"After %@ a blank New is %@, not %@", item.title, NSStringFromSize(blank.graph.canvasSize), NSStringFromSize(expected)]);
        [blank close];
        opened++;
    }
    NSLog(@"PASS catalog copies: %lu opens (21 items x 3 screens, with and without saved user frames) sized for their canvas; blank New stays 520 x 420 or the user's size", (unsigned long)opened);

    // A user canvas change on a normal blank document still becomes the default.
    ClearFrameKeys();
    NSError *error = nil;
    GraphDocument *document = [controller makeUntitledDocumentOfType:RSGraphFileType error:&error];
    [controller addDocument:document];
    GraphWindowController *owner = ShownWindow(document, Screens[0], YES);
    [document.editor setCanvasSize:NSMakeSize(640, 480)]; [document.undoer endRepetitiveUndo]; Drain();
    UserMovesAndResizes(owner);
    [document close]; Drain();
    NSDictionary *saved = SeedDefaults();
    Check([saved[@"LastCanvasSize"] isEqual:NSStringFromSize(NSMakeSize(640, 480))] && saved[@"LastFrameString"] && saved[AutosaveKey], [@"A real document's canvas and frame persist: " stringByAppendingString:saved.description]);
    GraphDocument *blank = [controller makeUntitledDocumentOfType:RSGraphFileType error:&error];
    Check(NSEqualSizes(blank.graph.canvasSize, NSMakeSize(640, 480)), @"The next blank New uses the user's canvas size");
    [blank close];
    // ... and its saved frame stays authoritative for the next window that owns the autosave name.
    document = [controller makeUntitledDocumentOfType:RSGraphFileType error:&error];
    [controller addDocument:document];
    ShownWindow(document, Screens[0], NO);
    [document close]; Drain();
    // A copy the user saved is a real document: its canvas counts like any other.
    ClearFrameKeys();
    RSNewFromItem *lesson = items.lastObject;
    document = (GraphDocument *)[controller openUntitledCopyOfURL:lesson.fileURL displayName:lesson.title ofType:RSGraphFileType display:NO error:&error];
    NSSize copyCanvas = document.graph.canvasSize;
    owner = ShownWindow(document, Screens[2], YES);
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"graphink"]];
    Check([document saveToURL:[NSURL fileURLWithPath:path] ofType:RSGraphFileType forSaveOperation:NSSaveAsOperation error:&error], [@"Save As the copy: " stringByAppendingString:error.description ?: @""]);
    UserMovesAndResizes(owner);
    [document close]; Drain();
    [NSFileManager.defaultManager removeItemAtPath:path error:NULL];
    Check([SeedDefaults()[@"LastCanvasSize"] isEqual:NSStringFromSize(copyCanvas)], @"A saved copy's canvas persists like a real document's");
    ClearFrameKeys();
    puts("PASS catalog copies: New From and Welcome copies never seed blank documents and open sized for their canvas; real documents still persist canvas and frame");
}
// Toolbar Show/Hide Grid: the item targets the first responder. With focus outside the canvas
// (sidebar or window), the action must still reach the document's graph, toggle both axis grids
// with undo, redraw, and flip the item's label and icon.
static id ResponderTarget(NSWindow *window, SEL action) {
    for (NSResponder *responder = window.firstResponder; responder; responder = responder.nextResponder)
        if ([responder respondsToSelector:action]) return responder;
    for (id candidate in @[(id)window.delegate ?: NSNull.null, window.windowController.document ?: NSNull.null])
        if ([candidate respondsToSelector:action]) return candidate;
    return nil;
}
static void CheckToolbarGrid(void) {
    FixtureDocumentController *controller = (FixtureDocumentController *)NSDocumentController.sharedDocumentController;
    NSError *error = nil;
    GraphDocument *document = [controller makeUntitledDocumentOfType:RSGraphFileType error:&error];
    [controller addDocument:document];
    [document makeWindowControllers];
    GraphWindowController *owner = document.windowControllers.firstObject;
    NSWindow *window = owner.window;
    [owner chooseInitialWindowFrameInVisibleFrame:Screens[0]];
    Drain(); [document.undoManager removeAllActions];
    NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:@"ShowHideGrid"] autorelease];
    item.action = @selector(showHideGrid:);
    RSGraph *graph = document.graph;
    RSGraphView *view = document.graphView;
    Check(!graph.xAxis.displayGrid && !graph.yAxis.displayGrid, @"New graph starts without a grid");
    for (NSUInteger focus = 0; focus < 2; focus++) {
        [window makeFirstResponder:focus == 0 ? (NSResponder *)window : (NSResponder *)view];  // sidebar/window focus, then canvas focus
        id target = ResponderTarget(window, item.action);
        Check(target != nil, focus == 0 ? @"Show Grid reaches a target while the canvas does not have focus" : @"Show Grid reaches a target while the canvas has focus");
        Check([target validateToolbarItem:item] && [item.label isEqual:@"Show Grid"], @"Item reads Show Grid while the grid is off");
        view.needsDisplay = NO;
        [target performSelector:item.action withObject:item]; Drain();
        Check(graph.xAxis.displayGrid && graph.yAxis.displayGrid && view.needsDisplay, @"Show Grid turns on both grids and redraws");
        Check([target validateToolbarItem:item] && [item.label isEqual:@"Hide Grid"], @"Item reads Hide Grid while the grid is on");
        Check(document.undoManager.canUndo && [document.undoManager.undoActionName isEqual:@"Show Grid"], [@"Show Grid is one undoable step named Show Grid: " stringByAppendingString:document.undoManager.undoActionName ?: @"(none)"]);
        [document.undoManager undo]; Drain();
        Check(!graph.xAxis.displayGrid && !graph.yAxis.displayGrid, @"Undo turns the grid off again");
        [document.undoManager redo]; Drain();
        Check(graph.displayGrid, @"Redo turns it back on");
        [target performSelector:item.action withObject:item]; Drain();
        Check(!graph.displayGrid && [document.undoManager.undoActionName isEqual:@"Hide Grid"], @"Hide Grid turns it off as its own step");
        [document.undoManager removeAllActions];
    }
    [document close];
    ClearFrameKeys();
    puts("PASS toolbar grid: reaches the document from any focus, toggles both grids with undo, redraws, updates its label");
}
int main(int argc, const char *argv[]) {
    @autoreleasepool { @try {
        Check(argc >= 2, @"Pass an owned output directory");
        [(Class)NSBundle.mainBundle.principalClass sharedApplication];  // OAApplication, as in the app; nib-loaded windows need it
        [[FixtureDocumentController alloc] init];  // the first document controller becomes the shared one, as RSDocumentController does in main.m
        Check([NSBundle.mainBundle.bundleIdentifier hasPrefix:@"com.graphink.viewportchecks."], @"Unique fixture domain required");
        NSString *domain = NSBundle.mainBundle.bundleIdentifier;
        CFPreferencesSetAppValue(CFSTR("ViewportIsolationProbe"), (CFStringRef)domain, kCFPreferencesCurrentApplication);
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
        id probe = [(id)CFPreferencesCopyAppValue(CFSTR("ViewportIsolationProbe"), (CFStringRef)domain) autorelease];
        Check([probe isEqual:domain], @"Current-application defaults did not route to the unique fixture domain");
        NSLog(@"Preference routing verified: %@", domain);
        OFController *lifecycle = OFController.sharedController;
        [lifecycle didInitialize]; [lifecycle startedRunning];
        Check(NSApp.delegate == nil, @"Fixture must not install the application delegate");
        [NSUserDefaults.standardUserDefaults registerDefaults:@{@"SnapToGrid": @NO, @"UseStickyTools": @YES}];
        NSMutableArray *controllers = [NSMutableArray array];
        for (NSUInteger index = 0; index < 2; index++) {
            NSError *error = nil;
            GraphDocument *document = [[[GraphDocument alloc] initWithType:RSGraphFileType error:&error] autorelease];
            Check(document != nil, error.description);
            NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 440) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO] autorelease];
            ViewportWindowController *owner = [[[ViewportWindowController alloc] initWithWindow:window] autorelease];
            [document addWindowController:owner];
            [controllers addObject:owner];
            [owner prepare];
            [document.editor setCanvasSize:NSMakeSize(3200, 2400)];
            RSVertex *seed = [[[RSVertex alloc] initWithGraph:document.graph] autorelease];
            seed.position = RSDataPointMake(8, 9);
            [document.graph addVertex:seed];
            Check(owner.zoom.indexOfSelectedItem == 2 && owner.scroll.magnification == 1, @"New document viewport did not start at 100%");
            Drain();
            [document.undoer endRepetitiveUndo];
            [document.undoManager removeAllActions];
            [document updateChangeCount:NSChangeCleared];
            RSGraph *graph = document.graph;
            NSData *before = [graph generateXMLOfType:RSGraphFileType frame:CGRectZero error:&error];
            Check(before != nil, error.description);
            for (NSUInteger zoom = 0; zoom < 6; zoom++) {
                [owner.zoom selectItemAtIndex:zoom]; [owner changeViewportZoom:owner.zoom];
                [document.graphView scrollPoint:NSMakePoint(90, 70)];
                [window setContentSize:NSMakeSize(800 + zoom * 20, 180 + zoom * 40)];
            }
            Drain();
            NSData *after = [graph generateXMLOfType:RSGraphFileType frame:CGRectZero error:&error];
            Check([before isEqual:after] && !document.isDocumentEdited && !document.undoManager.canUndo, @"Viewport changed production XML, dirty state or undo history");
            Check(!window.visible, @"Offscreen fixture showed a window");
            NSRect frame = window.frame;
            [document.editor setCanvasSize:NSMakeSize(3300, 2500)];
            [document.undoer endRepetitiveUndo]; Drain();
            Check(NSEqualSizes(document.graphView.bounds.size, NSMakeSize(3300, 2500)) && NSEqualRects(frame, window.frame), @"Explicit canvas edit changed viewport window or failed to update the mapper");
            Check(document.undoManager.canUndo && document.isDocumentEdited, @"Explicit canvas edit did not reach document history/dirty state");
            [document.undoManager undo]; Drain();
            Check(NSEqualSizes(graph.canvasSize, NSMakeSize(3200, 2400)) && NSEqualSizes(document.graphView.bounds.size, graph.canvasSize), @"Production canvas undo failed");
            [document.undoManager redo]; Drain();
            Check(NSEqualSizes(graph.canvasSize, NSMakeSize(3300, 2500)), @"Production canvas redo failed");
            [document.undoManager undo]; Drain();
            NSString *path = [@(argv[1]) stringByAppendingPathComponent:[NSString stringWithFormat:@"window-%lu.graphink", (unsigned long)index]];
            Check([document writeToURL:[NSURL fileURLWithPath:path] ofType:RSGraphFileType error:&error], error.description);
            GraphDocument *reopened = [[[GraphDocument alloc] init] autorelease];
            Check([reopened readFromURL:[NSURL fileURLWithPath:path] ofType:RSGraphFileType error:&error], error.description);
            Check(NSEqualSizes(reopened.graph.canvasSize, graph.canvasSize), @"Save/reopen lost independent canvas geometry");
            [document.undoManager removeAllActions]; [document updateChangeCount:NSChangeCleared];
            NSLog(@"PASS production view-only XML/dirty/history, canvas undo/redo, save/reopen window %lu", (unsigned long)index);
        }
        ViewportWindowController *owner = controllers[0];
        GraphDocument *document = owner.document;
        RSGraphView *view = document.graphView;
        for (NSNumber *index in @[@0, @4]) {
            [owner.zoom selectItemAtIndex:index.integerValue]; [owner changeViewportZoom:owner.zoom];
            [view scrollPoint:NSMakePoint(200, 180)];
            Check(view.visibleRect.origin.x > 0 && view.visibleRect.origin.y > 0, @"Placement fixture did not actually scroll at this zoom");
            NSPoint point = NSMakePoint(251.3, 213.7);
            NSUInteger vertexCount = document.graph.Vertices.count;
            [[RSMode sharedModeController] registerClick:RS_draw];
            Click(view, point);
            [(id)view.currentTool commitEditing];
            Check(document.graph.Vertices.count == vertexCount + 1, @"Draw created no production vertex");
            RSVertex *vertex = document.graph.Vertices.lastObject;
            CheckPosition(view, vertex, point);
            [[RSMode sharedModeController] registerClick:RS_modify];
            NSPoint target = NSMakePoint(281.3, 243.7);
            [view mouseMoved:Event(view, point, NSEventTypeMouseMoved)];
            [view mouseDown:Event(view, point, NSEventTypeLeftMouseDown)];
            [view mouseDragged:Event(view, target, NSEventTypeLeftMouseDragged)];
            [view mouseUp:Event(view, target, NSEventTypeLeftMouseUp)];
            CheckPosition(view, vertex, target);
            [view scrollPoint:NSMakePoint(100, 100)];
            NSUInteger fillCount = document.graph.Fills.count;
            [[RSMode sharedModeController] registerClick:RS_fill];
            // Corners more than 6 screen points apart in x and y at 25% (24 canvas units), so none snaps level.
            NSPoint corners[] = {NSMakePoint(145.3, 143.7), NSMakePoint(195.3, 143.7), NSMakePoint(225.3, 183.7)};
            for (NSUInteger corner = 0; corner < 3; corner++) Click(view, corners[corner]);
            [(id)view.currentTool commitEditing];
            RSFill *fill = document.graph.Fills.lastObject;
            Check(document.graph.Fills.count == fillCount + 1 && fill.vertices.elements.count == 3, @"Fill created no production triangle");
            for (NSUInteger corner = 0; corner < 3; corner++) CheckPosition(view, fill.vertices.elements[corner], corners[corner]);
            [view scrollPoint:NSMakePoint(300, 280)];
            [[RSMode sharedModeController] registerClick:RS_text];
            [view setWasEditingText:NO]; // No main-window mode notifications run in this offscreen fixture.
            NSPoint text = NSMakePoint(351.3, 313.7);
            Click(view, text);
            RSTextLabel *label = (id)document.selectorObject.selection;
            Check([label isKindOfClass:RSTextLabel.class], @"Text created no production label");
            CheckPosition(view, label, NSMakePoint(text.x, text.y - 12));
            [view commitEditing];
            NSLog(@"PASS production Modify/Draw/Fill/Text placement at %@ after scroll", owner.zoom.titleOfSelectedItem);
        }
        Check(((ViewportWindowController *)controllers[1]).scroll.magnification != owner.scroll.magnification, @"Zoom leaked across production documents");
        Check(!((GraphDocument *)((ViewportWindowController *)controllers[1]).document).isDocumentEdited, @"Tools dirtied the other document");
        NSSize canvas = document.graph.canvasSize;
        RSVertex *outlier = [[[RSVertex alloc] initWithGraph:document.graph] autorelease];
        outlier.position = RSDataPointMake(100, 100);
        [document.graph addVertex:outlier];
        [view performMenuItem:@selector(scaleToFitData:) withName:@"Scale to Fit"];
        Check(document.graph.xMax >= 100 && document.graph.yMax >= 100 && NSEqualSizes(canvas, document.graph.canvasSize) && owner.scroll.magnification == 4, @"Data Scale to Fit lost its axis-fitting meaning or changed viewport/canvas");
        NSLog(@"PASS production Scale to Fit data remains separate from viewport zoom");
        Check(!owner.window.visible, @"Tool fixture showed a window");
        for (ViewportWindowController *controller in controllers) [(GraphDocument *)controller.document close];
        CheckInitialFrames();
        CheckRealLaunchPath();
        CheckCatalogCopies();
        CheckToolbarGrid();
        Check([lifecycle requestTermination] == OFControllerTerminateNow, @"Fixture lifecycle refused termination");
        [lifecycle willTerminate];
        puts("PASS production viewport and tool placement; offscreen only");
    } @catch (NSException *exception) {
        NSLog(@"FAIL viewport: %@", exception); return 1;
    } }
    return 0;
}
