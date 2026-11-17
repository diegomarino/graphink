// Copyright 2003-2013 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAToolbarWindowController.h>

@class RSMode, RSGraph, RSGraphView, OIInspectorRegistry, RSLabelFinder;

// Initial frame for a window with no saved or restored frame: the canvas at 100% plus the
// window's own chrome (sidebar, toolbar, title and status bars), capped to the visible
// screen area inset by a margin. If 100% cannot fit, the largest capped frame is used and
// fitsAtActualSize is NO, so the window opens in Fit zoom. The top-left corner is kept
// (AppKit cascading), then the frame is moved inside the capped area.
typedef struct {
    NSRect frame;
    BOOL fitsAtActualSize;
} RSInitialWindowLayout;
extern const CGFloat RSInitialWindowScreenMargin;
RSInitialWindowLayout RSInitialWindowLayoutForCanvas(NSSize canvasSize, NSRect currentFrame, NSSize viewportSize, NSSize minimumFrameSize, NSRect visibleFrame);

// Each document window owns its inspector sidebar: a native vertical split holding the graph's
// scroll viewport and the sidebar (280 pt at first, 264 pt minimum), and one RSInspectorRegistry
// that AppController maps to the window. There is no floating inspector. Selection, context,
// status and autoscale notifications carry the document, so two windows never inspect each other.
// Moving the divider or showing and hiding the sidebar change only the viewport inside a stable
// window, never the canvas or the undo history; revealing the sidebar in a narrow window grows
// the window only enough for the inspector and a minimum viewport, within the visible screen.
// Zoom (native NSScrollView magnification), Fit and scroll position belong to the window and are
// never saved, restored or undone. Window restoration keeps the sidebar's width, visibility and
// section, apart from graph data and Omni's process-wide inspector workspace.
@interface GraphWindowController : OAToolbarWindowController <NSSplitViewDelegate, NSMenuItemValidation> {
    
    IBOutlet RSGraphView *_graphView;
    IBOutlet id _statusText;  // text view on bottom bar
    
    RSGraph *_graph;  // The window's document's graph
    RSMode *_m;  // the mode controller
    
    BOOL _updatingWindowSize;
    
    NSTextView *_textLabelFieldEditor;
    NSSplitView *_inspectorSplitView;
    NSView *_canvasContainer;
    NSScrollView *_graphScrollView;
    NSPopUpButton *_viewportZoom;
    BOOL _fitsCanvas;
    OIInspectorRegistry *_inspectorRegistry;
    RSLabelFinder *_labelFinder;
    CGFloat _sidebarWidth;
    BOOL _sidebarVisible;
    BOOL _layingOutSidebar;
    BOOL _inspectorsVisibleBeforeVersions;
    BOOL _initialFrameChosen;
    BOOL _frameStateRecorded;      // saved-frame state taken before the nib loads
    BOOL _autosavedFrameAtLoad;    // AppKit had a frame for the nib's autosave name
    BOOL _lastFrameStringAtLoad;   // a blank document had a persisted LastFrameString
    NSString *_suspendedAutosaveName;  // autosave name held back during the first setup
    BOOL _userChangedFrame;        // the user moved or resized the shown window
    BOOL _frameLogDone;            // TEMPORARY window-frame diagnostics finished
}


// Notifications:
- (void)changeToolbarMessageNotification:(NSNotification *)note;
@property(nonatomic, readonly) OIInspectorRegistry *inspectorRegistry;
@property(nonatomic, readonly) BOOL inspectorSidebarVisible;
- (void)refreshInspectors;
- (IBAction)changeViewportZoom:(id)sender;
// Once per window, at its first -showWindow: (after the nib, toolbar, sidebar and the document's
// final graph are in place): size a window that has no saved or restored frame for its canvas.
// Returns YES if the frame was chosen here; NO if a saved frame stays authoritative.
- (BOOL)chooseInitialWindowFrameInVisibleFrame:(NSRect)visibleFrame;
- (IBAction)toggleInspectorPanel:(id)sender;
- (IBAction)selectInspectorSection:(id)sender;
// Edit ▸ Find. The menu items' tags are NSTextFinderAction values. A custom action (not
// -performTextFinderAction:) so that a focused text field, whose field editor would claim and
// disable the standard action, still finds in the graph's labels.
@property(nonatomic, readonly) RSLabelFinder *labelFinder;
- (IBAction)performGraphFindAction:(id)sender;
- (IBAction)jumpToSelection:(id)sender;


// EXPERIMENTAL
//- (void)showModebar;

@end
