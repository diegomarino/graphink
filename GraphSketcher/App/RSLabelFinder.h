#import <AppKit/AppKit.h>

@class RSGraphView;

// Edit ▸ Find for one document window: the system find bar (NSTextFinder) over the text of the
// graph's visible labels (free labels, point labels, axis titles and user-set tick labels; not
// automatic tick numbers or data values). Labels are searched in reading order, top to bottom and
// then left to right; each label is its own search boundary. A match selects its label and scrolls
// it into view without changing the graph or the undo stack.
//
// While a label is being edited in place, Find Next, Find Previous and Use Selection for Find work
// on that label's text only. Showing the find bar ends the edit first and searches every label.
@interface RSLabelFinder : NSObject <NSTextFinderClient>

- (instancetype)initWithGraphView:(RSGraphView *)graphView findBarContainer:(NSScrollView *)scrollView;
- (void)invalidate;  // before the window closes

@property(nonatomic, readonly) NSTextFinder *textFinder;

// Menu items: the action is -performGraphFindAction: and the tag an NSTextFinderAction.
- (BOOL)validateAction:(NSTextFinderAction)action;
- (void)performAction:(NSTextFinderAction)action;

// Labels, layout or the text being edited may have changed. Cheap; the labels are re-read on the
// next turn of the run loop and NSTextFinder is told only if the searchable text really changed.
- (void)contentDidChange;

// Edit ▸ Find ▸ Jump to Selection: scroll the selection into view.
- (BOOL)canJumpToSelection;
- (void)jumpToSelection;

// RSGraphView draws the incremental-search highlights behind the graph (after the background).
- (void)drawIncrementalMatchHighlights;

@end
