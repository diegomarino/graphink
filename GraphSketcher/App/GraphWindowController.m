// Copyright 2003-2013 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "GraphWindowController.h"

#import "AppController.h"
#import "GraphDocument.h"
#import "RSGraphView.h"
#import "RSMode.h"
#import "RSInspectorSidebar.h"
#import "RSLabelFinder.h"

#import <GraphSketcherModel/RSGraph.h>
#import <GraphSketcherModel/RSGraphEditor.h>
#import <GraphSketcherModel/RSUndoer.h>
#import <GraphSketcherModel/RSDataMapper.h>
#import <GraphSketcherModel/RSTextLabel.h>

#import <OmniInspector/OIInspectorRegistry.h>
#import <os/log.h>
#import <OmniInspector/OIInspectorController.h>

// Since macOS 10.15 NSSplitView no longer asks its delegate about divider double-clicks.
@interface RSInspectorSplitView : NSSplitView
@end

@implementation RSInspectorSplitView
- (void)mouseDown:(NSEvent *)event {
    // Unhandled clicks in the canvas or the sidebar are forwarded here too. Only the divider hit-tests
    // to the split view itself, including the area AppKit adds around a thin divider.
    NSPoint point = [self.superview convertPoint:event.locationInWindow fromView:nil];
    if (event.clickCount == 2 && [self hitTest:point] == self) {
        [(GraphWindowController *)self.delegate toggleInspectorPanel:self];
        return;
    }
    [super mouseDown:event];
}
@end


@implementation GraphWindowController

- (OIInspectorRegistry *)inspectorRegistry { return _inspectorRegistry; }
- (BOOL)inspectorSidebarVisible { return _sidebarVisible; }
- (RSLabelFinder *)labelFinder { return _labelFinder; }
- (RSInspectorSidebar *)inspectorSidebar { return (RSInspectorSidebar *)_inspectorRegistry.controllers.firstObject.inspector; }

- (NSResponder *)responderForInspectionSet {
    // A sidebar field editor must not remove its document from inspection.
    return _graphView;
}

- (void)installInspectorSidebar {
    _sidebarWidth = 280;
    _sidebarVisible = YES;
    NSWindow *window = self.window;
    _canvasContainer = window.contentView;
    NSRect viewport = _canvasContainer.bounds;
    viewport.origin.y += WINDOW_BOTTOM_BAR_HEIGHT;
    viewport.size.height = MAX(0, NSHeight(viewport) - WINDOW_BOTTOM_BAR_HEIGHT);
    _graphScrollView = [[[NSScrollView alloc] initWithFrame:viewport] autorelease];
    _graphScrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _graphScrollView.hasVerticalScroller = YES;
    _graphScrollView.hasHorizontalScroller = YES;
    _graphScrollView.autohidesScrollers = YES;
    _graphScrollView.drawsBackground = NO;
    _graphScrollView.minMagnification = 0.25;
    _graphScrollView.maxMagnification = 4;
    [_canvasContainer addSubview:_graphScrollView];
    _graphScrollView.documentView = _graphView;
    _graphView.autoresizingMask = NSViewNotSizable;
    // The system find bar sits at the top of the canvas scroll view.
    _labelFinder = [[RSLabelFinder alloc] initWithGraphView:_graphView findBarContainer:_graphScrollView];
    _graphView.labelFinder = _labelFinder;
    // Status bar: canvas size / coordinates on the left, the zoom popup at the right end next to the sidebar.
    _viewportZoom = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(MAX(0, NSWidth(_canvasContainer.bounds) - 92), 0, 88, WINDOW_BOTTOM_BAR_HEIGHT) pullsDown:NO] autorelease];
    _viewportZoom.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    [_viewportZoom addItemsWithTitles:@[@"25%", @"50%", @"100%", @"200%", @"400%", NSLocalizedString(@"Fit", @"Viewport zoom")]];
    [_viewportZoom selectItemAtIndex:2];
    _viewportZoom.controlSize = NSControlSizeSmall;
    _viewportZoom.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    _viewportZoom.target = self;
    _viewportZoom.action = @selector(changeViewportZoom:);
    _viewportZoom.accessibilityLabel = NSLocalizedString(@"Canvas zoom", @"Viewport zoom accessibility label");
    [_canvasContainer addSubview:_viewportZoom];
    NSRect statusFrame = [_statusText frame];
    statusFrame.origin.x = 4;
    statusFrame.size.width = MAX(0, NSWidth(_canvasContainer.bounds) - 96 - 4);
    [_statusText setFrame:statusFrame];
    [(NSView *)_statusText setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    _inspectorSplitView = [[[RSInspectorSplitView alloc] initWithFrame:_canvasContainer.frame] autorelease];
    _inspectorSplitView.vertical = YES;
    _inspectorSplitView.dividerStyle = NSSplitViewDividerStyleThin;
    _inspectorSplitView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _inspectorSplitView.delegate = self;
    [_inspectorSplitView addSubview:_canvasContainer];
    window.contentView = _inspectorSplitView;
    _inspectorRegistry = [[RSInspectorRegistry alloc] init];
    OIInspectorController *controller = _inspectorRegistry.controllers.firstObject;
    [_inspectorSplitView addSubview:controller.containerView];
    [controller loadInterface];
    [controller setExpanded:YES withNewTopLeftPoint:NSZeroPoint];
    [self layoutInspectorSidebar];
    // The nib's loop predates the sidebar and the status bar popup, and inspector views are swapped
    // per section: let AppKit rebuild the loop from the current view geometry.
    window.autorecalculatesKeyViewLoop = YES;
}

- (void)refreshInspectors {
    if (!_graph || !_inspectorRegistry) return;
    [_inspectorRegistry updateInspectionSetImmediatelyAndUnconditionallyForWindow:self.window];
    [_inspectorRegistry.controllers.firstObject updateInspector];
}

- (CGFloat)sidebarChromeWidth {
    return _sidebarVisible ? _sidebarWidth + _inspectorSplitView.dividerThickness : 0;
}

- (void)layoutInspectorSidebar {
    if (!_inspectorSplitView) return;
    _layingOutSidebar = YES;
    NSRect bounds = _inspectorSplitView.bounds;
    CGFloat chrome = [self sidebarChromeWidth];
    _canvasContainer.frame = NSMakeRect(0, 0, MAX(0, NSWidth(bounds) - chrome), NSHeight(bounds));
    NSView *sidebar = _inspectorRegistry.controllers.firstObject.containerView;
    sidebar.hidden = !_sidebarVisible;
    sidebar.frame = NSMakeRect(NSMaxX(_canvasContainer.frame) + (_sidebarVisible ? _inspectorSplitView.dividerThickness : 0), 0, _sidebarWidth, NSHeight(bounds));
    // Omni's noncollapsible path adds the root without sizing it to its host.
    [self inspectorSidebar].view.frame = sidebar.bounds;
    _layingOutSidebar = NO;
    [self updateViewportZoom];
}

const CGFloat RSInitialWindowScreenMargin = 20;

RSInitialWindowLayout RSInitialWindowLayoutForCanvas(NSSize canvasSize, NSRect currentFrame, NSSize viewportSize, NSSize minimumFrameSize, NSRect visibleFrame)
{
    NSRect available = NSInsetRect(visibleFrame, RSInitialWindowScreenMargin, RSInitialWindowScreenMargin);
    NSSize chrome = NSMakeSize(NSWidth(currentFrame) - viewportSize.width, NSHeight(currentFrame) - viewportSize.height);
    NSSize needed = NSMakeSize(ceil(canvasSize.width + chrome.width), ceil(canvasSize.height + chrome.height));
    RSInitialWindowLayout layout;
    layout.fitsAtActualSize = needed.width <= NSWidth(available) && needed.height <= NSHeight(available);
    NSSize size = NSMakeSize(MIN(needed.width, NSWidth(available)), MIN(needed.height, NSHeight(available)));
    size = NSMakeSize(MAX(size.width, minimumFrameSize.width), MAX(size.height, minimumFrameSize.height));
    NSRect frame = NSMakeRect(NSMinX(currentFrame), NSMaxY(currentFrame) - size.height, size.width, size.height);
    frame.origin.x = MAX(NSMinX(available), MIN(NSMinX(frame), NSMaxX(available) - NSWidth(frame)));
    frame.origin.y = MAX(NSMinY(available), MIN(NSMinY(frame), NSMaxY(available) - NSHeight(frame)));
    layout.frame = frame;
    return layout;
}

// Debug-level diagnostics for the first window setup (initial frame choice and frame changes until
// the window first becomes main). Not shown by default; to see them:
//   log stream --level debug --predicate 'subsystem == "com.diegomarino.Graphink" && category == "window-frame"'
static os_log_t RSWindowFrameLog(void) {
    static os_log_t log; static dispatch_once_t once;
    dispatch_once(&once, ^{ log = os_log_create("com.diegomarino.Graphink", "window-frame"); });
    return log;
}
- (void)logFrame:(NSString *)source {
    if (_frameLogDone) return;
    NSWindow *window = self.isWindowLoaded ? self.window : nil;
    RSGraph *graph = [[self document] graph];
    os_log_debug(RSWindowFrameLog(), "%{public}@ | %{public}@ | frame=%{public}@ content=%{public}@ canvas=%{public}@ sidebar=%.0f autosave='%{public}@' visible=%d chosen=%d savedAtLoad=%d/%d",
           source, [[self document] displayName], NSStringFromRect(window ? window.frame : NSZeroRect), NSStringFromSize(window ? window.contentView.frame.size : NSZeroSize),
           NSStringFromSize(graph ? graph.canvasSize : NSZeroSize), [self sidebarChromeWidth], window.frameAutosaveName ?: @"", window.isVisible, _initialFrameChosen,
           _autosavedFrameAtLoad, _lastFrameStringAtLoad);
}

// The nib's window autosave name (GraphDocument.xib). AppKit writes its frame on every frame change,
// including the window's own setup, so whether a frame was *saved* is recorded before the nib loads.
static NSString * const RSGraphWindowAutosaveName = @"RSGraphDocumentWindow";
- (void)recordSavedFrameStateWithAutosaveName:(NSString *)autosaveName {
    if (_frameStateRecorded) return;
    _frameStateRecorded = YES;
    _autosavedFrameAtLoad = autosaveName.length && [NSUserDefaults.standardUserDefaults objectForKey:[@"NSWindow Frame " stringByAppendingString:autosaveName]] != nil;
    // Info.plist registers a LastFrameString default (600 x 500); only a persisted one is a saved frame.
    _lastFrameStringAtLoad = ![[self document] isFromFile] && [[OFPreference preferenceForKey:@"LastFrameString"] hasPersistentValue];
}
- (void)windowWillLoad {
    [super windowWillLoad];
    [self recordSavedFrameStateWithAutosaveName:RSGraphWindowAutosaveName];
    [self logFrame:@"windowWillLoad"];
}

// A frame is saved when this window owns the autosave name and AppKit had a frame for it before
// the window loaded, or a new blank document had a persisted LastFrameString. State restoration
// marks the frame as chosen (-window:didDecodeRestorableState:). An unsaved New From or Welcome
// copy always opens sized for its canvas: a saved frame belongs to the user's own documents.
- (BOOL)hasSavedWindowFrame {
    if ([[self document] isUnsavedCatalogCopy]) return NO;
    [self recordSavedFrameStateWithAutosaveName:self.window.frameAutosaveName];  // windows not loaded from the nib
    NSString *autosaveName = _suspendedAutosaveName ?: self.window.frameAutosaveName;
    return (_autosavedFrameAtLoad && autosaveName.length) || _lastFrameStringAtLoad;
}

// While the first frame is unsettled the window must not persist it: hold the autosave name back.
// An unsaved catalog copy holds it back for good, so its frame never seeds other windows.
- (void)suspendFrameAutosave {
    NSWindow *window = self.window;
    if (_suspendedAutosaveName || !window.frameAutosaveName.length || (_autosavedFrameAtLoad && ![[self document] isUnsavedCatalogCopy])) return;
    _suspendedAutosaveName = [window.frameAutosaveName copy];
    [window setFrameAutosaveName:@""];
}
- (void)resumeFrameAutosave {
    if (!_suspendedAutosaveName || [[self document] isUnsavedCatalogCopy]) return;
    [self.window setFrameAutosaveName:_suspendedAutosaveName];
    [_suspendedAutosaveName release]; _suspendedAutosaveName = nil;
}

- (BOOL)chooseInitialWindowFrameInVisibleFrame:(NSRect)visibleFrame {
    RSGraph *graph = [[self document] graph];
    if (_initialFrameChosen || !graph || !self.isWindowLoaded || !_inspectorSplitView) return NO;
    _initialFrameChosen = YES;
    if ([self hasSavedWindowFrame] || NSIsEmptyRect(visibleFrame)) {
        [self logFrame:@"initial frame: saved frame kept"];
        return NO;
    }
    NSWindow *window = self.window;
    [self updateContentMinimumSize];
    NSSize minimum = [window frameRectForContentRect:NSMakeRect(0, 0, window.contentMinSize.width, window.contentMinSize.height)].size;
    // The window's own chrome: title bar and toolbar (frame minus content view), plus the sidebar
    // and the status bar inside the content view. Measured from geometry that is final here.
    NSSize content = window.contentView.frame.size;
    NSSize viewport = NSMakeSize(content.width - [self sidebarChromeWidth], content.height - WINDOW_BOTTOM_BAR_HEIGHT);
    RSInitialWindowLayout layout = RSInitialWindowLayoutForCanvas(graph.canvasSize, window.frame, viewport, minimum, visibleFrame);
    [self logFrame:[NSString stringWithFormat:@"initial frame: choosing %@ in visible %@ (fits at 100%%: %d)", NSStringFromRect(layout.frame), NSStringFromRect(visibleFrame), layout.fitsAtActualSize]];
    [self suspendFrameAutosave];
    _updatingWindowSize = YES;
    @try {
        [window setFrame:layout.frame display:NO];
        [self layoutInspectorSidebar];
    } @finally {
        _updatingWindowSize = NO;
    }
    if (!layout.fitsAtActualSize) {
        [_viewportZoom selectItemAtIndex:5];
        [self changeViewportZoom:_viewportZoom];
    }
    [self logFrame:@"initial frame: chosen"];
    return YES;
}

- (IBAction)showWindow:(id)sender {
    [self chooseInitialWindowFrameInVisibleFrame:(self.window.screen ?: [NSScreen mainScreen]).visibleFrame];
    [self logFrame:@"showWindow: before AppKit"];
    [super showWindow:sender];
    [self resumeFrameAutosave];
    [self logFrame:@"showWindow: shown"];
}


// Window minima protect controls; document whitespace must never constrain the viewport.
- (void)updateContentMinimumSize {
    [self.window setContentMinSize:NSMakeSize(180 + [self sidebarChromeWidth], 140)];
}

- (void)updateViewportZoom {
    if (!_graph || !_fitsCanvas) return;
    NSSize size = _graph.canvasSize;
    NSSize available = _graphScrollView.contentSize;
    if (size.width <= 0 || size.height <= 0 || available.width <= 0 || available.height <= 0) return;
    CGFloat zoom = MIN(available.width / size.width, available.height / size.height);
    if (!isfinite(zoom) || zoom <= 0) return;
    _graphScrollView.minMagnification = MIN(zoom, 0.25);
    _graphScrollView.maxMagnification = MAX(zoom, 4);
    _graphScrollView.magnification = zoom;
}

- (IBAction)changeViewportZoom:(id)sender {
    NSInteger index = [sender indexOfSelectedItem];
    if (index < 0 || index > 5) return;
    _fitsCanvas = index == 5;
    // Fit has no scroll gutters, so switching from a large zoom fits exactly once.
    _graphScrollView.hasHorizontalScroller = !_fitsCanvas;
    _graphScrollView.hasVerticalScroller = !_fitsCanvas;
    if (_fitsCanvas) {
        [self updateViewportZoom];
    } else {
        CGFloat zooms[] = {0.25, 0.5, 1, 2, 4};
        NSRect visible = _graphView.visibleRect;
        [_graphScrollView setMagnification:zooms[index] centeredAtPoint:NSMakePoint(NSMidX(visible), NSMidY(visible))];
    }
    [_graphView mouseEntered:nil];
}

- (BOOL)setInspectorSidebarVisible:(BOOL)visible {
    if (_sidebarVisible == visible) return YES;
    if (![[self inspectorSidebar] commitEditing]) return NO;
    NSWindow *window = self.window;
    NSRect frame = window.frame;
    if (visible) {
        NSRect available = (window.screen ?: [NSScreen mainScreen]).visibleFrame;
        CGFloat windowChrome = NSWidth(frame) - NSWidth(window.contentView.bounds);
        CGFloat minimumCanvas = 180;
        CGFloat maximumSidebar = NSWidth(available) - windowChrome - minimumCanvas - _inspectorSplitView.dividerThickness;
        if (maximumSidebar < 264) return NO;
        _sidebarWidth = MIN(_sidebarWidth, maximumSidebar);
        frame.size.width = MAX(NSWidth(frame), minimumCanvas + _sidebarWidth + _inspectorSplitView.dividerThickness + windowChrome);
        frame.size.width = MIN(NSWidth(frame), NSWidth(available));
        frame.origin.x = MAX(NSMinX(available), MIN(NSMinX(frame), NSMaxX(available) - NSWidth(frame)));
    }
    _updatingWindowSize = YES;
    @try {
        _sidebarVisible = visible;
        [self updateContentMinimumSize];
        // Enlarge only when needed to reveal; never resize the document canvas.
        if (!NSEqualRects(frame, window.frame)) [window setFrame:frame display:YES];
        [self layoutInspectorSidebar];
    } @finally {
        _updatingWindowSize = NO;
    }
    if (visible) [self refreshInspectors];
    [self.window invalidateRestorableState];
    return YES;
}

- (IBAction)toggleInspectorPanel:(id)sender {
    [self setInspectorSidebarVisible:!_sidebarVisible];
}

- (IBAction)selectInspectorSection:(id)sender {
    NSUInteger section = [sender tag];
    if (section >= 4) return;
    if (![[self inspectorSidebar] selectSection:section]) return;
    [self setInspectorSidebarVisible:YES];
}

- (IBAction)performGraphFindAction:(id)sender {
    [_labelFinder performAction:[sender tag]];
}

- (IBAction)jumpToSelection:(id)sender {
    [_labelFinder jumpToSelection];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(toggleInspectorPanel:)) {
        item.title = _sidebarVisible ? NSLocalizedString(@"Hide Inspector", @"Inspector menu") : NSLocalizedString(@"Show Inspector", @"Inspector menu");
        return YES;
    }
    if (item.action == @selector(selectInspectorSection:)) {
        item.state = _sidebarVisible && item.tag == (NSInteger)[self inspectorSidebar].selectedSection ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    if (item.action == @selector(performGraphFindAction:))
        return [_labelFinder validateAction:item.tag];
    if (item.action == @selector(jumpToSelection:))
        return [_labelFinder canJumpToSelection];
    return [super validateMenuItem:item];
}

- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize {
    [self layoutInspectorSidebar];
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)minimum ofSubviewAt:(NSInteger)index {
    return 180;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)maximum ofSubviewAt:(NSInteger)index {
    return NSWidth(splitView.bounds) - 264 - splitView.dividerThickness;
}

- (BOOL)splitView:(NSSplitView *)splitView shouldHideDividerAtIndex:(NSInteger)index { return !_sidebarVisible; }

- (void)splitViewDidResizeSubviews:(NSNotification *)notification {
    if (_layingOutSidebar || !_sidebarVisible || _updatingWindowSize || !_graph) return;
    CGFloat width = NSWidth(_inspectorRegistry.controllers.firstObject.containerView.frame);
    if (width < 264 || fabs(width - _sidebarWidth) < 0.5) return;
    _sidebarWidth = width;
    [self updateViewportZoom];
    // The native divider tracks the pointer; only the graph viewport changes.
    [self updateContentMinimumSize];
    [self.window invalidateRestorableState];
}

- (void)window:(NSWindow *)window willEncodeRestorableState:(NSCoder *)coder {
    [coder encodeDouble:_sidebarWidth forKey:@"RSInspectorSidebarWidth"];
    [coder encodeBool:_sidebarVisible forKey:@"RSInspectorSidebarVisible"];
    [coder encodeInteger:[self inspectorSidebar].selectedSection forKey:@"RSInspectorSidebarSection"];
}

- (void)window:(NSWindow *)window didDecodeRestorableState:(NSCoder *)coder {
    // A restored window keeps the frame AppKit restored.
    _initialFrameChosen = YES;
    [self resumeFrameAutosave];
    [self logFrame:@"restored window state"];
    if (![coder containsValueForKey:@"RSInspectorSidebarWidth"]) return;
    _updatingWindowSize = YES;
    CGFloat width = [coder decodeDoubleForKey:@"RSInspectorSidebarWidth"];
    CGFloat maximumWidth = MAX(264, NSWidth(window.contentView.bounds) - 180 - _inspectorSplitView.dividerThickness);
    if (isfinite(width)) _sidebarWidth = MAX(264, MIN(width, maximumWidth));
    _sidebarVisible = [coder decodeBoolForKey:@"RSInspectorSidebarVisible"];
    NSInteger section = [coder decodeIntegerForKey:@"RSInspectorSidebarSection"];
    if (section >= 0 && section < 4) [[self inspectorSidebar] selectSection:section];
    [self updateContentMinimumSize];
    [self layoutInspectorSidebar];
    _updatingWindowSize = NO;
}

////////////////////////////////////////////
#pragma mark -
#pragma mark Class methods
//////

- (void)saveGraphFrame {
    
    // Don't let the "Getting Started" graph or untitled New From / Welcome copies affect the defaults
    if ([[self document] isInAppBundle] || [[self document] isUnsavedCatalogCopy])
	return;
    // A full-screen window fills the screen; new windows keep the frame it had before.
    if ([[self window] styleMask] & NSWindowStyleMaskFullScreen)
	return;

    NSString *frameString = [[self window] stringWithSavedFrame];
    [self logFrame:[@"saveGraphFrame: LastFrameString = " stringByAppendingString:frameString]];
    //DEBUG_RS(@"%@", frameString);
    
    // make this the new default
    [[OFPreferenceWrapper sharedPreferenceWrapper] setObject:frameString forKey:@"LastFrameString"];
    [[OFPreferenceWrapper sharedPreferenceWrapper] setObject:NSStringFromSize([[[self document] graph] canvasSize])
						      forKey:@"LastCanvasSize"];
}

- (void)setStatusMessage:(NSString *)message;
{
    if (!message)
        return;
    
    if (![[self window] isMainWindow])
	return;
    
    [_statusText setStringValue:message];
    
    //if( [message isEqualToString:@""] ) {
    //	[_statusText setBackgroundColor:[NSColor windowBackgroundColor]];
    //} else {
    //	[_statusText setBackgroundColor:
    //		[NSColor colorWithCalibratedHue:0.167 saturation:0.2 brightness:1.0 alpha:1.0] ];
    //}
}

- (void)updateWindowSize;
{
    // Only an explicit document canvas edit reaches the mapper; viewport zoom
    // uses AppKit's clip-view transform and preserves model coordinates.
    [_graphView setFrameSize:_graph.canvasSize];
    [self updateViewportZoom];
    [_graphView windowDidResize];
    [self setStatusMessage:messageForCanvasSize(_graph.canvasSize)];
}

- (void)updateToolbarWithMode:(NSUInteger)newMode;
{
    if ( newMode == RS_none ) {
	[[self toolbar] setSelectedItemIdentifier:nil];
    }
    else if ( newMode == RS_modify ) {
	[[self toolbar] setSelectedItemIdentifier:@"ModifyTool"];
    }
    else if ( newMode == RS_draw ) {
	[[self toolbar] setSelectedItemIdentifier:@"DrawTool"];
    }
    else if ( newMode == RS_fill ) {
	[[self toolbar] setSelectedItemIdentifier:@"FillTool"];
    }
    else if ( newMode == RS_text ) {
	[[self toolbar] setSelectedItemIdentifier:@"TextTool"];
    }
}

- (void)documentGraphDidChange:(RSGraph *)newGraph;
{
    OBASSERT(newGraph != _graph);
    if (newGraph == _graph)
        return;
    
    // Clean up old graph, if it exists
    if (_graph) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        
        // Clear out KVO in the inspector panels
        [_inspectorRegistry clearInspectionSet];
        
        // KVO
        [_graph removeObserver:self forKeyPath:@"canvasSize"];
        [_graph removeObserver:self forKeyPath:@"whitespace"];
        
        [pool release];
        
        //[_graphView setGraph:nil];
        [_graph release];
    }
    
    _graph = [newGraph retain];
    
    if (_graph) {
        GraphDocument *document = [self document];
        NSUndoManager *undoManager = [document undoManager];
        [[document undoer] endRepetitiveUndo];
        BOOL couldUndo __attribute__((unused)) = [undoManager canUndo];
        BOOL couldRedo __attribute__((unused)) = [undoManager canRedo];
        [undoManager disableUndoRegistration];
        @try {
            NSWindow *window = [self window];
        
            // KVO
            [_graph addObserver:self forKeyPath:@"canvasSize" options:NSKeyValueObservingOptionNew context:NULL];
            [_graph addObserver:self forKeyPath:@"whitespace" options:NSKeyValueObservingOptionNew context:NULL];
        
            // Set window position
            // default "shouldCascadeWindows" is YES
            [self logFrame:@"graph adopted: before position"];
            if ([document isFromFile]) {
                // Assume that if there is a non-zero point set, the graph wants it.
                if (!NSEqualPoints(_graph.frameOrigin, NSZeroPoint))
                    [self setShouldCascadeWindows:NO];

                [window setFrameOrigin:_graph.frameOrigin];
            }
            else  // new, blank document
            {
                [window setFrameFromString:[[OFPreferenceWrapper sharedPreferenceWrapper] objectForKey:@"LastFrameString"]];
            }
        
            // The initial size (no saved frame) is chosen at the first -showWindow:, once the toolbar,
            // sidebar and final graph are in place; see -chooseInitialWindowFrameInVisibleFrame:.
            [self logFrame:@"graph adopted: after position"];

            // Set document view geometry independently of the window size
            [self updateWindowSize];
            [self updateContentMinimumSize];
        
            // Notify the RSGraphView
            _graphView.editor = document.editor; // this also updates the display etc.
            [_graphView mouseEntered:nil];
            [self refreshInspectors];
        
        } @finally {
            [undoManager enableUndoRegistration];
        }

        // Window setup must preserve history, including edits in an existing document.
        [[document undoer] endRepetitiveUndo];
        OBASSERT([undoManager canUndo] == couldUndo);
        OBASSERT([undoManager canRedo] == couldRedo);
    }
    
}


////////////////////////////////////////////////
#pragma mark -
#pragma mark init/dealloc
////////////////////////////////////////////////

- (id)init;
{
    self = [super initWithWindowNibName:@"GraphDocument"];
    if (self) {
        _graphView = nil;
        _statusText = nil;
        _graph = nil;
        _m = nil;
        
        _updatingWindowSize = NO;
        
        _textLabelFieldEditor = nil;
        
        DEBUG_RS(@"GraphWindowController init");
    }
    return self;
}

- (void)dealloc;
{
    // _graph should have been released in -windowDidClose:
    OBASSERT(!_graph);
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _inspectorSplitView.delegate = nil;
    [_inspectorRegistry invalidate];
    [_inspectorRegistry release];
    _graphView.labelFinder = nil;
    [_labelFinder invalidate];
    [_labelFinder release];
    [_textLabelFieldEditor release];
    [_suspendedAutosaveName release];
    
    [super dealloc];
}


////////////////////////////////////////////////
#pragma mark -
#pragma mark WindowController subclass
////////////////////////////////////////////////

- (void)awakeFromNib
// Anything that initializes nib elements needs to go here
// rather than in initWithFrame: above, because nib elements get
// initialized after initWithFrame: gets called.
{
    DEBUG_RS(@"awaking from nib");
    
    [[self document] setGraphView:_graphView];
    
    // save position to user defaults
    //now in IB//[[self window] setFrameAutosaveName:@"RSGraphDocumentFrame"];
    
    // Register for notifications
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self 
	   selector:@selector(changeToolbarMessageNotification:)
	       name:@"RSChangeToolbarMessage"
	     object:nil];
    // Register to receive notifications of an external change in mode
    [nc addObserver:self 
           selector:@selector(modeWillChangeNotification:)
               name:@"RSModeWillChange"
             object:nil];
    
    _m = [RSMode sharedModeController];
    [_m resetFlags];
}

- (void)windowDidLoad;
{
    // No persisted frame yet: keep AppKit from saving the setup frames (toolbar, origin, defaults).
    [self suspendFrameAutosave];
    [self logFrame:@"windowDidLoad: nib loaded"];
    [super windowDidLoad];
    
    DEBUG_RS(@"windowDidLoad");
    //[[[self document] undoer] setEnabled:NO];
    
    [self updateToolbarWithMode:[_m mode]];
    
    // setup graphView
    [_graphView setRSSelector:[[self document] selectorObject]];
    [self installInspectorSidebar];
    
    [self logFrame:@"windowDidLoad: toolbar and sidebar installed"];
    [self documentGraphDidChange:[[self document] graph]];
    
    // Register to receive future updates if the graph is changed, most likely because of Revert to Saved.
    [[self document] addObserver:self forKeyPath:@"graph" options:NSKeyValueObservingOptionNew context:NULL];
}



////////////////////////////////////////////////
#pragma mark -
#pragma mark OAToolbarWindowController subclass
////////////////////////////////////////////////

- (NSString *)toolbarConfigurationName; // file name to lookup .toolbar plist
{
    return @"Graph";
}
- (BOOL)shouldAllowUserToolbarCustomization;
{
    return YES;
}
- (BOOL)shouldAutosaveToolbarConfiguration;
{
    return YES;
}



////////////////////////////////////////////////
#pragma mark -
#pragma mark NSToolbar delegate
////////////////////////////////////////////////

- (NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar;
{
    NSMutableArray *identifiers = [NSMutableArray array];
    
    [identifiers addObject:@"ModifyTool"];
    [identifiers addObject:@"DrawTool"];
    [identifiers addObject:@"FillTool"];
    [identifiers addObject:@"TextTool"];
    
    return identifiers;
}

// These are called when the corresponding toolbar items are clicked.
- (void)selectModifyTool:(id)sender;
{
    [_m registerClick:RS_modify];
}
- (void)selectDrawTool:(id)sender;
{
    [_m registerClick:RS_draw];
}
- (void)selectFillTool:(id)sender;
{
    [_m registerClick:RS_fill];
}
- (void)selectTextTool:(id)sender;
{
    [_m registerClick:RS_text];
}


////////////////////////////////////////////////
#pragma mark -
#pragma mark Window delegate methods
////////////////////////////////////////////////
- (void)windowDidBecomeKey:(NSNotification *)note
{
    //DEBUG_RS(@"windowDidBecomeKey");
    
    // Tell graphView to wake up.  This has to be called both here and in -windowDidBecomeMain:, because it's not consistent which method gets called first.
    [_graphView mouseEntered:nil];
    
    // The graphView also needs to redisplay because the selection color will stop being gray.
    [_graphView setNeedsDisplay:YES];
}
- (void)windowDidResignKey:(NSNotification *)note;
{
    // The selection color should change to gray, so the graphView needs to redisplay.
    [_graphView setNeedsDisplay:YES];
}
- (void)windowDidBecomeMain:(NSNotification *)note
{
    //DEBUG_RS(@"windowDidBecomeMain");
    
    [self updateToolbarWithMode:[_m mode]];
    
    // The first setup does not persist its frame; only one the user moved or resized (or closed).
    if (_userChangedFrame) [self saveGraphFrame];
    [self logFrame:@"became main (diagnostics end)"];
    _frameLogDone = YES;
    
    [_m resetFlags];
    
    // tell graphView to wake up
    [_graphView mouseEntered:nil];
}
- (void)windowDidResignMain:(NSNotification *)note;
{
    [self updateToolbarWithMode:RS_none];
}

- (void)windowDidMove:(NSNotification *)note
// sent whenever document window is moved
{
    DEBUG_RS(@"windowDidMove");
    [self logFrame:@"windowDidMove"];
    if (_initialFrameChosen && !_updatingWindowSize && self.window.isVisible) _userChangedFrame = YES;
    
    // if the window has awoken from nib...
    if( [[self window] isMainWindow] ) {
	[self saveGraphFrame];
    }
}
- (void)windowDidResize:(NSNotification *)note
{
    [self logFrame:_updatingWindowSize ? @"windowDidResize (setup)" : @"windowDidResize"];
    if (_updatingWindowSize) return;
    if (_initialFrameChosen && self.window.isVisible) _userChangedFrame = YES;
    [self layoutInspectorSidebar];
    if (self.window.isMainWindow) [self saveGraphFrame];
}

- (void)windowWillClose:(NSNotification *)note
// sent right before the window closes
{
    DEBUG_RS(@"windowWillClose");
    
    [self saveGraphFrame];
    
    [[self document] closeLinkBackConnection];
    [_inspectorRegistry clearInspectionSet];
    [_inspectorRegistry invalidate];
    _graphView.labelFinder = nil;
    [_labelFinder invalidate];
    
    // Unregister KVO, etc.
    [self documentGraphDidChange:nil];
    
    [[self document] removeObserver:self forKeyPath:@"graph"];
}


- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)sender;
{
    return [[self document] undoManager];
}


- (id)windowWillReturnFieldEditor:(NSWindow *)window toObject:(id)anObject;
// Return a dependable field editor specifically for RSTextLabels.
{
    if (![anObject isKindOfClass:[RSTextLabel class]]) {
        return nil;  // use window's default field editor instead
    }
    
    if (!_textLabelFieldEditor) {
        NSTextView *fieldEditor = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 10000, 10000)];
        [fieldEditor setRichText:YES];
        [fieldEditor setEditable:YES];
        [fieldEditor setFieldEditor:YES];  // controls behavior of return and tab keys
        [fieldEditor setAllowsUndo:YES];
        
        [fieldEditor setHorizontallyResizable:NO];  // this just didn't work
        [fieldEditor setVerticallyResizable:NO];
        [fieldEditor setMaxSize:NSMakeSize(10000, 10000)];
        
        // reflect user's continuous spell checking preference
        BOOL useSpell = [[OFPreferenceWrapper sharedPreferenceWrapper] boolForKey:@"UseContinuousSpellChecking"];
        [fieldEditor setContinuousSpellCheckingEnabled:useSpell];
        
        _textLabelFieldEditor = fieldEditor;
    }
    
    return _textLabelFieldEditor;
}


- (void)windowWillEnterVersionBrowser:(NSNotification *)notification;
{
    _inspectorsVisibleBeforeVersions = _sidebarVisible;
    if (_sidebarVisible) [self setInspectorSidebarVisible:NO];
    
}

- (void)windowDidExitVersionBrowser:(NSNotification *)notification;
{
    if (_inspectorsVisibleBeforeVersions) [self setInspectorSidebarVisible:YES];
}


//////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Notifications
//////////////////////////////////////////////////////////

- (void)changeToolbarMessageNotification:(NSNotification *)note;
{
    if (note.userInfo[@"document"] && note.userInfo[@"document"] != self.document) return;
    if (![[self window] isMainWindow])
	return;

    NSString *message = [note object];
    [self setStatusMessage:message];
}

- (void)modeWillChangeNotification:(NSNotification *)note;
{
    if (![[self window] isMainWindow])
	return;
    
    NSUInteger newMode = [[[note userInfo] objectForKey:@"mode"] unsignedIntegerValue];
    
    [self updateToolbarWithMode:newMode];
}


////////////////////////////////////////////////
#pragma mark -
#pragma mark KVO
////////////////////////////////////////////////

- (void)observeValueForKeyPath:(NSString *)keyPath
		      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context;
{
    if (object == [self document]) {
        if ( [keyPath isEqual:@"graph"] ) {
            [self documentGraphDidChange:[[self document] graph]];
        }
    }
    
    if (object == _graph) {
	if ( [keyPath isEqual:@"canvasSize"] ) {
            if (!_updatingWindowSize) [self updateWindowSize];
	}
	else if ( [keyPath isEqual:@"whitespace"] ) {
	    // Update the window's setting for its minimum size
            [self updateContentMinimumSize];
	}
    }
}



//////////////////////////////////////////////////////////
#pragma mark -
#pragma mark EXPERIMENTAL
//////////////////////////////////////////////////////////

//- (void)showModebar {
//    NSLog(@"showModeBar");
//    
//    float MODEBAR_HEIGHT = 26;
//    
//    // set the new frame and animate the change
//    NSRect windowFrame = [[self window] frame];
//    windowFrame.size.height = [_graphView frame].size.height + [_statusText frame].size.height 
//    + MODEBAR_HEIGHT + WINDOW_TITLE_HEIGHT;
//    windowFrame.size.width = [_graphView frame].size.width;
//    windowFrame.origin.y = NSMaxY([_theWindow frame]) - windowFrame.size.height;
//    
//    NSRect graphViewFrame = [_graphView frame];
//    //graphViewFrame.origin.y += MODEBAR_HEIGHT;
//    
//    //if ([[activeContentView subviews] count] != 0)
//    //	[[[activeContentView subviews] objectAtIndex:0] removeFromSuperview];
//    [_theWindow setFrame:windowFrame display:YES animate:YES];
//    
//    [_graphView setFrame:graphViewFrame];
//    
//    [[_theWindow contentView] addSubview:_modebar];
//    NSRect modebarFrame = [_graphView frame];
//    modebarFrame.origin.y = windowFrame.size.height - MODEBAR_HEIGHT - WINDOW_TITLE_HEIGHT;
//    //modebarFrame.size.height = 
//    [_modebar setFrame:modebarFrame];
//    
//    
//    // this seems to fix an IB problem with resizing during the animation...
//    //[activeContentView setFrame:NSMakeRect(0, 0, NSWidth([self frame]), NSMinY([self frame]))];
//    //[activeContentView addSubview:view];
//}

@end
