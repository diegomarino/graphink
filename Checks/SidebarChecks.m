// Focused, offscreen AppKit contract checks; this does not launch GraphSketcher.
#import <Cocoa/Cocoa.h>
#import <OmniInspector/OIInspector.h>
#import <OmniInspector/OIInspectorRegistry.h>
#import <OmniInspector/OIInspectorController.h>
#import <OmniInspector/OIInspectorTabController.h>
#import <OmniInspector/OIInspectionSet.h>
#import <OmniInspector/OIInspectableControllerProtocol.h>
#import "../GraphSketcher/App/GraphWindowController.h"
#import <GraphSketcherModel/RSGraph.h>

static BOOL CommandResize;
static BOOL SquareGridResize;
@interface CheckMapper : NSObject
@end
@implementation CheckMapper
- (void)setBounds:(NSRect)bounds {}
- (CGPoint)deltaToSquareGrid { return CGPointMake(2, 3); }
@end
@interface CheckEditor : NSObject
@end
@implementation CheckEditor
- (id)mapper { return [[[CheckMapper alloc] init] autorelease]; }
- (void)setNeedsUpdateWhitespace {}
@end

@interface GraphWindowController (SidebarChecks)
- (void)installInspectorSidebar;
- (void)updateWindowSize;
- (void)windowDidResize:(NSNotification *)note;
- (void)layoutInspectorSidebar;
- (BOOL)setInspectorSidebarVisible:(BOOL)visible;
- (void)window:(NSWindow *)window willEncodeRestorableState:(NSCoder *)coder;
- (void)window:(NSWindow *)window didDecodeRestorableState:(NSCoder *)coder;
@end

// Only graph storage and the unrelated tool singleton are fixtures. Sizing,
// split handling, state restoration and visibility use GraphWindowController.
@interface CheckGraph : NSObject
@property(nonatomic) NSSize canvasSize;
@property(nonatomic, retain) NSUndoManager *undoManager;
@property(nonatomic) RSBorder whitespace;
@property(nonatomic) BOOL autoMaintainsWhitespace;
@end
@implementation CheckGraph
- (NSSize)minCanvasSize { return NSMakeSize(100, 100); }
- (BOOL)displayBothGrids { return SquareGridResize; }
- (BOOL)bothGridsAreEvenlySpaced { return YES; }
- (void)setCanvasSize:(NSSize)size {
    if (NSEqualSizes(size, _canvasSize)) return;
    [[_undoManager prepareWithInvocationTarget:self] setCanvasSize:_canvasSize];
    _canvasSize = size;
}
@end

@interface RSMode : NSObject
@end
@implementation RSMode
+ (id)sharedModeController { static RSMode *mode; if (!mode) mode = [[self alloc] init]; return mode; }
- (BOOL)commandKeyIsDown { return CommandResize; }
@end

@interface CheckGraphDocument : NSDocument
@property(nonatomic, retain) CheckGraph *graph;
@end
@implementation CheckGraphDocument
- (BOOL)isInAppBundle { return YES; }
@end

@interface CheckGraphView : NSView <OIInspectableController>
@property(nonatomic, assign) id document;
@property(nonatomic) NSUInteger boundsUpdates;
@property(nonatomic, assign) id labelFinder;  // the window controller's Edit ▸ Find client
@end
@implementation CheckGraphView
- (id)editor { return [[[CheckEditor alloc] init] autorelease]; }
- (void)windowDidResize { _boundsUpdates++; }
- (void)mouseEntered:(NSEvent *)event {}
- (void)addInspectedObjects:(OIInspectionSet *)set { [set addObject:_document]; }
@end

@interface CheckGraphWindowController : GraphWindowController
- (void)prepareSidebar;
- (void)enableResizeCallbacks;
- (void)disableResizeCallbacks;
- (void)forceLegacyScrollers;
- (NSScrollView *)graphScrollView;
- (NSPopUpButton *)viewportZoom;
- (CheckGraphView *)graphView;
@end
@implementation CheckGraphWindowController
- (void)enableResizeCallbacks { self.window.delegate = (id)self; [(id)_graph addObserver:self forKeyPath:@"canvasSize" options:0 context:NULL]; }
- (void)disableResizeCallbacks { self.window.delegate = nil; [(id)_graph removeObserver:self forKeyPath:@"canvasSize"]; }
- (NSScrollView *)graphScrollView { return _graphScrollView; }
- (NSPopUpButton *)viewportZoom { return _viewportZoom; }
- (CheckGraphView *)graphView { return (id)_graphView; }
- (void)forceLegacyScrollers { _graphScrollView.scrollerStyle = NSScrollerStyleLegacy; [_graphScrollView tile]; }
- (void)prepareSidebar {
    _graph = (id)[[(CheckGraphDocument *)self.document graph] retain];
    CheckGraphView *view = [[[CheckGraphView alloc] initWithFrame:NSMakeRect(0, 20, 520, 420)] autorelease];
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    view.document = self.document;
    _graphView = (id)view;
    [self.window.contentView addSubview:view];
    [self installInspectorSidebar];
    [self updateWindowSize];
    [self refreshInspectors];
}
- (OIInspectorRegistry *)registry { return self.inspectorRegistry; }
- (void)dealloc { [_graph release]; _graph = nil; [super dealloc]; }
@end

@interface NSObject (SidebarContract)
- (BOOL)selectSection:(NSUInteger)section;
- (NSUInteger)selectedSection;
- (BOOL)commitEditing;
- (void)refreshInspectors;
@end

@interface CheckInspector : OIInspector <OIConcreteInspector>
@property(nonatomic, assign) id inspectedDocument;
@end
@implementation CheckInspector
- (void)loadView { self.view = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 240, 559)] autorelease]; }
- (NSPredicate *)inspectedObjectsPredicate { return [NSPredicate predicateWithValue:YES]; }
- (void)inspectObjects:(NSArray *)objects { self.inspectedDocument = objects.firstObject; }
@end

@interface CheckWindow : NSWindow
@property(nonatomic) BOOL refusesCommit;
@property(nonatomic) BOOL forcedMain;
@end
@implementation CheckWindow
- (BOOL)isMainWindow { return _forcedMain || [super isMainWindow]; }
- (BOOL)makeFirstResponder:(NSResponder *)responder { return !_refusesCommit && [super makeFirstResponder:responder]; }
@end

@interface CheckOwner : NSWindowController <OIInspectableController>
@property(nonatomic, retain) OIInspectorRegistry *registry;
@end
@implementation CheckOwner
- (NSResponder *)responderForInspectionSet { return self; }
- (void)addInspectedObjects:(OIInspectionSet *)set { [set addObject:self.document]; }
@end

@interface CheckDelegate : NSObject
@property(nonatomic, retain) NSArray *owners;
@end
@implementation CheckDelegate
- (OIInspectorRegistry *)inspectorRegistryForWindow:(NSWindow *)window { return [(CheckOwner *)window.windowController registry]; }
- (NSWindow *)windowForInspectorRegistry:(OIInspectorRegistry *)registry {
    for (CheckOwner *owner in _owners) if (owner.registry == registry) return owner.window;
    return nil;
}
@end

static NSEvent *DoubleClick(NSWindow *window, NSPoint windowPoint) {
    return [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:windowPoint modifierFlags:0 timestamp:0 windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:2 pressure:1];
}

// Sends a double-click to the view AppKit hit-tests at a split view point, so unhandled mouse-downs
// travel the real responder chain. A queued mouse-up ends any tracking loop the click starts.
static NSView *DoubleClickHitView(NSSplitView *split, NSPoint point) {
    NSView *hit = [split hitTest:[split convertPoint:point toView:split.superview]];
    NSCAssert(hit && hit != split && ![hit isKindOfClass:[NSControl class]], @"Point is not on a plain, non-divider view");
    NSPoint windowPoint = [split convertPoint:point toView:nil];
    [NSApp postEvent:[NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:windowPoint modifierFlags:0 timestamp:0 windowNumber:split.window.windowNumber context:nil eventNumber:0 clickCount:2 pressure:0] atStart:NO];
    [hit mouseDown:DoubleClick(split.window, windowPoint)];
    while ([NSApp nextEventMatchingMask:NSEventMaskAny untilDate:nil inMode:NSDefaultRunLoopMode dequeue:YES]) {}
    return hit;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *domain = NSBundle.mainBundle.bundleIdentifier;
        NSCAssert([domain hasPrefix:@"com.graphsketcher.SidebarChecks."], @"Fixture requires a unique test preference domain");
        CFPreferencesSetAppValue(CFSTR("SidebarIsolationProbe"), (CFStringRef)domain, kCFPreferencesCurrentApplication);
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
        id probe = [(id)CFPreferencesCopyAppValue(CFSTR("SidebarIsolationProbe"), (CFStringRef)domain) autorelease];
        NSCAssert([probe isEqual:domain], @"Current-application preferences did not route to the unique fixture domain");
        NSLog(@"Preference routing verified: %@", domain);
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"SelectionSensitivity": @5}];
        Class sidebarClass = NSClassFromString(@"RSInspectorSidebar");
        NSCAssert(sidebarClass, @"Missing per-window inspector sidebar implementation");
        CheckDelegate *delegate = [[[CheckDelegate alloc] init] autorelease];
        [NSApplication sharedApplication].delegate = (id)delegate;
        NSMutableArray *owners = [NSMutableArray array];
        for (NSUInteger index = 0; index < 2; index++) {
            CheckWindow *window = [[[CheckWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 450) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES] autorelease];
            CheckOwner *owner = [[[CheckOwner alloc] initWithWindow:window] autorelease];
            owner.document = [[[NSDocument alloc] init] autorelease];
            owner.registry = [[[OIInspectorRegistry alloc] init] autorelease];
            [owners addObject:owner];
        }
        delegate.owners = owners;
        for (CheckOwner *owner in owners) {
            OIInspectorController *controller = owner.registry.controllers.firstObject;
            NSCAssert(controller.interfaceType == OIInspectorInterfaceTypeEmbedded, @"Inspector must never create a floating window");
            controller.containerView.frame = owner.window.contentView.bounds;
            [owner.window.contentView addSubview:controller.containerView];
            [controller loadInterface];
            [controller setExpanded:YES withNewTopLeftPoint:NSZeroPoint];
            [owner.registry updateInspectionSetImmediatelyAndUnconditionallyForWindow:owner.window];
            [controller updateInspector];
            NSCAssert(controller.window == nil, @"Embedded inspector created a panel");
        }
        CheckOwner *a = owners[0], *b = owners[1];
        id sidebarA = a.registry.controllers.firstObject.inspector;
        id sidebarB = b.registry.controllers.firstObject.inspector;
        NSCAssert(sidebarA != sidebarB, @"Windows share inspector instances");
        NSArray *identifiers = @[@"style", @"axis", @"document", @"data"];
        for (NSUInteger index = 0; index < 4; index++) {
            NSCAssert([sidebarA selectSection:index], @"Section switch refused without an edit");
            OIInspectorTabController *tab = [sidebarA tabWithIdentifier:identifiers[index]];
            NSCAssert([(CheckInspector *)tab.inspector inspectedDocument] == a.document, @"Section lost its owning document while the inspector owns focus");
        }
        NSCAssert([sidebarB selectedSection] == 0, @"Section switch leaked into the second window");
        ((CheckWindow *)a.window).refusesCommit = YES;
        NSCAssert(![sidebarA selectSection:0] && [sidebarA selectedSection] == 3, @"Validation refusal switched the inspector");
        NSCAssert(![sidebarA commitEditing], @"Validation refusal was ignored before hiding");
        ((CheckWindow *)a.window).refusesCommit = NO;
        NSCAssert([sidebarA selectSection:0], @"Valid edit did not permit switching");
        id replacement = [[[NSDocument alloc] init] autorelease];
        [a.registry clearInspectionSet];
        NSCAssert([(CheckInspector *)[[sidebarA tabWithIdentifier:@"style"] inspector] inspectedDocument] == nil, @"Old graph/document remained inspected during replacement");
        a.document = replacement;
        [a.registry updateInspectionSetImmediatelyAndUnconditionallyForWindow:a.window];
        [a.registry.controllers.firstObject updateInspector];
        NSCAssert([(CheckInspector *)[[sidebarA tabWithIdentifier:@"style"] inspector] inspectedDocument] == replacement, @"Replaced document was not rebound");
        NSCAssert([(CheckInspector *)[[sidebarB tabWithIdentifier:@"style"] inspector] inspectedDocument] == b.document, @"Replacement cleared the other window");
        [a.registry clearInspectionSet];
        [a.registry invalidate];
        NSCAssert([(CheckInspector *)[[sidebarA tabWithIdentifier:@"style"] inspector] inspectedDocument] == nil, @"Close retained inspection references");

        CheckGraphDocument *document = [[[CheckGraphDocument alloc] init] autorelease];
        document.graph = [[[CheckGraph alloc] init] autorelease];
        document.graph.undoManager = [[[NSUndoManager alloc] init] autorelease];
        [document.graph.undoManager disableUndoRegistration];
        document.graph.canvasSize = NSMakeSize(520, 420);
        [document.graph.undoManager enableUndoRegistration];
        CheckWindow *window = [[[CheckWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 440) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES] autorelease];
        CheckGraphWindowController *controller = [[[CheckGraphWindowController alloc] initWithWindow:window] autorelease];
        controller.document = document;
        [owners addObject:controller];
        [controller prepareSidebar];
        NSCAssert(NSMaxX(controller.graphScrollView.frame) == NSWidth(window.contentView.subviews.firstObject.bounds), @"Viewport inherited a document-sized trailing margin");
        CheckGraphDocument *secondDocument = [[[CheckGraphDocument alloc] init] autorelease];
        secondDocument.graph = [[[CheckGraph alloc] init] autorelease];
        secondDocument.graph.canvasSize = NSMakeSize(360, 280);
        CheckWindow *secondWindow = [[[CheckWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 440) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES] autorelease];
        CheckGraphWindowController *secondController = [[[CheckGraphWindowController alloc] initWithWindow:secondWindow] autorelease];
        secondController.document = secondDocument;
        [owners addObject:secondController];
        [secondController prepareSidebar];
        NSSize originalCanvas = document.graph.canvasSize;
        NSRect originalWindow = window.frame;
        NSSplitView *split = (NSSplitView *)window.contentView;
        NSView *sidebar = split.subviews.lastObject;
        NSCAssert(fabs(NSWidth(sidebar.frame) - 280) < 0.5, @"Initial sidebar width is not 280pt");
        NSTextField *field = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 60, 20)] autorelease];
        [sidebar addSubview:field];
        NSCAssert([window makeFirstResponder:field], @"Could not focus sidebar field");
        NSResponder *fieldEditor = window.firstResponder;
        window.refusesCommit = YES;
        NSCAssert(![controller setInspectorSidebarVisible:NO] && controller.inspectorSidebarVisible, @"Collapse ignored refused field validation");
        [split setPosition:450 ofDividerAtIndex:0];
        NSCAssert(window.firstResponder == fieldEditor, @"Divider stole active field focus");
        NSCAssert(NSEqualSizes(document.graph.canvasSize, originalCanvas) && !document.graph.undoManager.canUndo, @"Divider edited the canvas or undo stack");
        NSCAssert(NSEqualRects(window.frame, originalWindow), @"Divider resized the outer window");
        NSCAssert(fabs(NSMaxX(split.subviews.firstObject.frame) - 450) < 0.5, @"Divider did not track its requested position");
        window.refusesCommit = NO;
        CGFloat expandedWidth = NSWidth(sidebar.frame);
        NSCAssert([controller setInspectorSidebarVisible:NO], @"Valid collapse failed");
        NSCAssert([controller setInspectorSidebarVisible:YES], @"Valid expansion failed");
        NSCAssert(fabs(NSWidth(sidebar.frame) - expandedWidth) < 0.5, @"Collapse lost expanded sidebar width");
        NSCAssert(NSEqualSizes(document.graph.canvasSize, originalCanvas) && !document.graph.undoManager.canUndo && NSEqualRects(window.frame, originalWindow), @"Toggle changed canvas, undo or outer window");
        NSView *blankHit = DoubleClickHitView(split, NSMakePoint(NSMidX(sidebar.frame), NSMinY(sidebar.frame) + 10));
        NSCAssert([blankHit isDescendantOf:sidebar] && controller.inspectorSidebarVisible, @"Double-click on blank sidebar space toggled the sidebar");
        NSView *canvasHit = DoubleClickHitView(split, NSMakePoint(NSMidX(split.subviews.firstObject.frame), NSMidY(split.bounds)));
        NSCAssert([canvasHit isDescendantOf:split.subviews.firstObject] && controller.inspectorSidebarVisible, @"Double-click on the canvas toggled the sidebar");
        NSPoint dividerPoint = NSMakePoint(NSMaxX(split.subviews.firstObject.frame) + split.dividerThickness / 2, NSMidY(split.bounds));
        NSCAssert([split hitTest:[split convertPoint:dividerPoint toView:split.superview]] == split, @"Divider clicks do not reach the split view");
        [split mouseDown:DoubleClick(window, [split convertPoint:dividerPoint toView:nil])];
        NSCAssert(!controller.inspectorSidebarVisible, @"Divider double-click did not hide the sidebar");
        NSCAssert(NSEqualSizes(document.graph.canvasSize, originalCanvas) && !document.graph.undoManager.canUndo && NSEqualRects(window.frame, originalWindow), @"Divider double-click changed canvas, undo or outer window");
        NSCAssert([controller setInspectorSidebarVisible:YES] && fabs(NSWidth(sidebar.frame) - expandedWidth) < 0.5, @"Sidebar hidden by double-click lost its width");
        NSKeyedArchiver *coder = [[[NSKeyedArchiver alloc] initRequiringSecureCoding:YES] autorelease];
        [(id)controller window:window willEncodeRestorableState:coder];
        [coder finishEncoding];
        [split setPosition:500 ofDividerAtIndex:0];
        NSKeyedUnarchiver *decoder = [[[NSKeyedUnarchiver alloc] initForReadingFromData:coder.encodedData error:NULL] autorelease];
        [(id)controller window:window didDecodeRestorableState:decoder];
        [decoder finishDecoding];
        NSCAssert(fabs(NSWidth(sidebar.frame) - expandedWidth) < 0.5 && NSEqualSizes(document.graph.canvasSize, originalCanvas) && !document.graph.undoManager.canUndo && NSEqualRects(window.frame, originalWindow), @"Restoration changed canvas/history/window or lost divider width");
        [window setContentSize:NSMakeSize(1000, 650)];
        NSView *root = controller.inspectorRegistry.controllers.firstObject.inspector.view;
        NSCAssert(NSEqualRects(root.frame, sidebar.bounds), @"Embedded sidebar root does not fill a tall host");
        NSStackView *selector = (id)root.subviews.firstObject;
        NSCAssert(fabs(NSMaxY(root.bounds) - NSMaxY(selector.frame) - 8) < 0.5, @"Selector is not pinned below toolbar");
        [window setContentSize:NSMakeSize(900, 250)];
        NSCAssert(NSEqualRects(root.frame, sidebar.bounds) && NSMinY(selector.frame) >= 0, @"Short host clips selector");
        [controller setInspectorSidebarVisible:NO];
        [window setContentSize:NSMakeSize(160, 440)];
        window.forcedMain = YES;
        [controller enableResizeCallbacks];
        NSCAssert([controller setInspectorSidebarVisible:YES], @"Narrow hidden window could not reveal sidebar");
        NSCAssert(NSWidth(split.subviews.firstObject.frame) >= 100 && NSMinX(sidebar.frame) >= 100 && NSMaxX(sidebar.frame) <= NSWidth(split.bounds) + 0.5, @"Revealed inspector is clipped in a narrow window");
        NSCAssert(NSEqualSizes(document.graph.canvasSize, originalCanvas) && !document.graph.undoManager.canUndo, @"Reveal enlargement changed canvas/history");
        [controller forceLegacyScrollers];
        [window setContentSize:NSMakeSize(700, 400)];
        NSCAssert(NSEqualSizes(window.contentView.bounds.size, NSMakeSize(700, 400)), @"Legacy scrollbar resize fed canvas KVO back into the outer window");
        NSCAssert(NSEqualSizes(document.graph.canvasSize, originalCanvas), @"Window resize changed saved canvas geometry");
        RSBorder border = {.left = 10, .right = 10, .top = 10, .bottom = 10};
        document.graph.whitespace = border;
        document.graph.autoMaintainsWhitespace = YES;
        CommandResize = YES;
        SquareGridResize = YES;
        [window setContentSize:NSMakeSize(740, 300)];
        NSCAssert(document.graph.autoMaintainsWhitespace && document.graph.whitespace.left == 10 && NSEqualSizes(document.graph.canvasSize, originalCanvas), @"Command/square-grid resize edited document geometry");
        CommandResize = NO;
        SquareGridResize = NO;
        CheckGraphView *graphView = controller.graphView;
        NSUInteger updates = graphView.boundsUpdates;
        CGFloat zooms[] = {0.25, 0.5, 1, 2, 4};
        for (NSInteger index = 0; index < 6; index++) {
            [controller.viewportZoom selectItemAtIndex:index];
            [controller changeViewportZoom:controller.viewportZoom];
            NSScrollView *scroll = controller.graphScrollView;
            if (index < 5) NSCAssert(fabs(scroll.magnification - zooms[index]) < 0.001, @"Fixed zoom is incorrect");
            else NSCAssert(NSWidth(graphView.visibleRect) >= originalCanvas.width - 0.5 && NSHeight(graphView.visibleRect) >= originalCanvas.height - 0.5, @"Fit clips the canvas");
            NSCAssert(NSEqualSizes(graphView.bounds.size, originalCanvas) && NSEqualSizes(document.graph.canvasSize, originalCanvas), @"Zoom changed mapper or saved geometry");
            NSPoint modelPoint = NSMakePoint(260, 210);
            [graphView scrollPoint:NSMakePoint(100, 80)];
            NSPoint windowPoint = [graphView convertPoint:modelPoint toView:nil];
            NSPoint converted = [graphView convertPoint:windowPoint fromView:nil];
            NSCAssert(hypot(converted.x - modelPoint.x, converted.y - modelPoint.y) < 0.001, @"Scrolled zoom event conversion moved model point");
            NSPoint origin = [graphView convertPoint:NSZeroPoint toView:nil];
            NSPoint unit = [graphView convertPoint:NSMakePoint(1, 1) toView:nil];
            NSCAssert(fabs((unit.x - origin.x) - scroll.magnification) < 0.001, @"Window events do not use the zoom transform");
        }
        [window setContentSize:NSMakeSize(900, 500)];
        [controller setInspectorSidebarVisible:NO];
        NSCAssert(NSWidth(graphView.visibleRect) >= originalCanvas.width - 0.5 && NSHeight(graphView.visibleRect) >= originalCanvas.height - 0.5, @"Fit did not follow window/sidebar resize");
        NSCAssert(graphView.boundsUpdates == updates && !document.graph.undoManager.canUndo && !document.isDocumentEdited, @"View-only operations reached document/mapper/undo");
        NSRect viewportWindow = window.frame;
        document.graph.canvasSize = NSMakeSize(620, 460);
        [document.graph.undoManager endUndoGrouping];
        NSCAssert(NSEqualSizes(graphView.bounds.size, NSMakeSize(620, 460)) && NSEqualRects(viewportWindow, window.frame), @"Explicit canvas edit did not update geometry independently of window");
        [document.graph.undoManager undo];
        NSCAssert(NSEqualSizes(graphView.bounds.size, originalCanvas), @"Canvas undo did not update view geometry");
        [document.graph.undoManager redo];
        NSCAssert(NSEqualSizes(graphView.bounds.size, NSMakeSize(620, 460)), @"Canvas redo did not update view geometry");
        NSCAssert(secondController.graphScrollView.magnification == 1 && secondController.viewportZoom.indexOfSelectedItem == 2 && NSEqualSizes(secondDocument.graph.canvasSize, NSMakeSize(360, 280)), @"View state or canvas edits leaked into the second document");
        NSCAssert(secondController.inspectorRegistry != controller.inspectorRegistry, @"Documents share inspector ownership");
        [document.graph.undoManager disableUndoRegistration];
        document.graph.canvasSize = NSMakeSize(1000000, 1000000);
        NSCAssert(NSWidth(graphView.visibleRect) >= 999999 && NSHeight(graphView.visibleRect) >= 999999, @"Fit imposes an arbitrary lower magnification bound");
        document.graph.canvasSize = NSMakeSize(1, 1);
        NSCAssert(fabs(controller.graphScrollView.magnification - MIN(controller.graphScrollView.contentSize.width, controller.graphScrollView.contentSize.height)) < 0.01, @"Fit imposes an arbitrary upper magnification bound");
        [document.graph.undoManager enableUndoRegistration];
        [secondController.inspectorRegistry clearInspectionSet];
        [secondController.inspectorRegistry invalidate];
        [controller disableResizeCallbacks];
        [controller.inspectorRegistry clearInspectionSet];
        [controller.inspectorRegistry invalidate];
        puts("PASS window controller: sizing/focus/canvas/undo/restoration, divider double-click, tall/short root fit, narrow reveal, legacy-scroller and Command/square-grid resize invariance, viewport zoom/Fit/event conversion, explicit canvas undo/redo");
        puts("PASS sidebar: separate windows, four sections, field-focus routing, validation refusal, replacement and close isolation");
    }
    return 0;
}
