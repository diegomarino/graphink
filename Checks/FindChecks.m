// Offscreen Edit ▸ Find checks: the system find bar over a nib-loaded production
// document window. Matches across label kinds in reading order, wraparound both ways, start after
// the selection, scrolling at 400%, no match, Use Selection for Find, incremental search in the
// bar, Find inside a label being edited, routing past focused text fields, undo neutrality, and
// the find indicator's content (the label's text at its size at 50%, 400% and in Chalkboard).
// The shared find pasteboard is saved first and restored at the end.
// No application delegate, launch loop or visible window.
#import "GraphDocument.h"
#import "GraphWindowController.h"
#import "RSGraphView.h"
#import "RSInspectorSidebar.h"
#import "RSLabelFinder.h"
#import "RSSelector.h"
#import "RSStylePresets.h"
#import <GraphSketcherModel/RSAxis.h>
#import <GraphSketcherModel/RSDataMapper.h>
#import <GraphSketcherModel/RSGraph.h>
#import <GraphSketcherModel/RSGraphEditor.h>
#import <GraphSketcherModel/RSTextLabel.h>
#import <GraphSketcherModel/RSVertex.h>
#import <OmniFoundation/OFController.h>
#import <objc/runtime.h>

@interface FixtureDocumentController : NSDocumentController
@end
@implementation FixtureDocumentController
- (id)makeUntitledDocumentOfType:(NSString *)typeName error:(NSError **)outError {
    return [[[GraphDocument alloc] initWithType:RSGraphFileType error:outError] autorelease];
}
@end
static void Check(BOOL condition, NSString *message) {
    if (!condition) [NSException raise:@"FindCheckFailure" format:@"%@", message];
}
static void Drain(void) {
    for (int turn = 0; turn < 3; turn++) {
        __block BOOL finished = NO;
        dispatch_async(dispatch_get_main_queue(), ^{ finished = YES; });
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
        while (!finished && deadline.timeIntervalSinceNow > 0)
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:deadline];
        Check(finished, @"Main queue did not drain");
    }
}
// Incremental searches run on a background queue; wait until the matches settle.
static void Settle(void) {
    for (int turn = 0; turn < 10; turn++) {
        Drain();
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
}
static const NSRect Screen = {{0, 0}, {1440, 875}};

#pragma mark - Find pasteboard

static NSArray *SavedFindPasteboard;
static NSArray *FindPasteboardContents(void) {
    NSMutableArray *items = [NSMutableArray array];
    for (NSPasteboardItem *item in [NSPasteboard pasteboardWithName:NSPasteboardNameFind].pasteboardItems) {
        NSMutableDictionary *types = [NSMutableDictionary dictionary];
        for (NSString *type in item.types) {
            NSData *data = [item dataForType:type];
            if (data) types[type] = data;
        }
        [items addObject:types];
    }
    return items;
}
static void RestoreFindPasteboard(void) {
    if (!SavedFindPasteboard) return;
    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithName:NSPasteboardNameFind];
    [pasteboard clearContents];
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *types in SavedFindPasteboard) {
        NSPasteboardItem *item = [[[NSPasteboardItem alloc] init] autorelease];
        for (NSString *type in types) [item setData:types[type] forType:type];
        [items addObject:item];
    }
    if (items.count) [pasteboard writeObjects:items];
}
// What another app (or this one, before) leaves on the find pasteboard: the search string and
// default options (Contains, case-insensitive). NSTextFinder reads it when the app becomes active.
static void SetFindString(NSString *string) {
    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithName:NSPasteboardNameFind];
    [pasteboard clearContents];
    [pasteboard setString:string forType:NSPasteboardTypeString];
    [pasteboard setPropertyList:@{NSTextFinderCaseInsensitiveKey: @YES, NSTextFinderMatchingTypeKey: @(NSTextFinderMatchingTypeContains)} forType:NSPasteboardTypeTextFinderOptions];
    [NSNotificationCenter.defaultCenter postNotificationName:NSApplicationDidBecomeActiveNotification object:NSApp];
    Drain();
}
static NSString *FindString(void) {
    return [[NSPasteboard pasteboardWithName:NSPasteboardNameFind] stringForType:NSPasteboardTypeString];
}

#pragma mark - Fixture

static GraphWindowController *Owner;
static GraphDocument *Document;
static RSGraphView *GraphView;
static NSScrollView *ScrollView;
static RSTextLabel *SupplyCurve, *Demand, *SupplyNote, *PointLabel, *TickLabel, *XTitle, *YTitle;

static RSGraph *Graph(void) { return Document.editor.graph; }
static RSGraphElement *Selection(void) { return [[GraphView RSSelector] selection]; }
static NSString *Name(RSGraphElement *element) {
    if (!element) return @"(nothing)";
    return [element isKindOfClass:RSTextLabel.class] ? [NSString stringWithFormat:@"'%@'", [(RSTextLabel *)element text]] : element.className;
}
static RSTextLabel *AddLabel(NSString *text, double fx, double fy) {
    RSGraph *graph = Graph();
    RSTextLabel *label = [[[RSTextLabel alloc] initWithGraph:graph] autorelease];
    [label setText:text];
    [label setPosition:RSDataPointMake([graph xMin] + fx * ([graph xMax] - [graph xMin]), [graph yMin] + fy * ([graph yMax] - [graph yMin]))];
    [graph addLabel:label];
    return label;
}
// Every label text and position, to prove Find changed nothing. Tick labels are positioned by the
// renderer's layout, so lay out first.
static NSArray *LabelState(void) {
    [Document.editor prepareForDisplay];
    NSMutableArray *state = [NSMutableArray array];
    for (RSTextLabel *label in [Graph() allLabels])
        [state addObject:[NSString stringWithFormat:@"%p %@ %@ %g", label, label.text, NSStringFromPoint(NSPointFromCGPoint(CGPointMake(label.position.x, label.position.y))), [label rotation]]];
    return state;
}

static void OpenFixtureDocument(void) {
    for (NSString *key in @[@"LastFrameString", @"LastCanvasSize"]) [[OFPreferenceWrapper sharedPreferenceWrapper] removeObjectForKey:key];
    NSError *error = nil;
    Document = [[GraphDocument alloc] initWithType:RSGraphFileType error:&error];
    Check(Document != nil, error.description);
    RSGraph *graph = Graph();
    [Document.undoManager disableUndoRegistration];
    // Two labels on the top row (left one first), one in the middle, a point with a label lower
    // down, the x-axis title, and a y-axis title that is hidden and must never match.
    SupplyCurve = AddLabel(@"Supply curve", 0.1, 0.9);
    Demand = AddLabel(@"Demand", 0.6, 0.9);
    SupplyNote = AddLabel(@"supply NOTE", 0.3, 0.6);
    RSVertex *vertex = [[[RSVertex alloc] initWithGraph:graph identifier:nil point:RSDataPointMake([graph xMin] + 0.5 * ([graph xMax] - [graph xMin]), [graph yMin] + 0.3 * ([graph yMax] - [graph yMin])) width:4 color:[NSColor blackColor] shape:1] autorelease];
    [graph addVertex:vertex];
    PointLabel = [graph makeLabelForOwner:vertex];
    [PointLabel setText:@"Equilibrium SUPPLY"];
    XTitle = [[graph xAxis] title];
    [XTitle setText:@"Quantity of supply"];
    [[graph xAxis] setDisplayTitle:YES];
    YTitle = [[graph yAxis] title];
    [YTitle setText:@"Hidden supply"];
    [[graph yAxis] setDisplayTitle:NO];
    // Wide x ticks (0, 5, 10) leave room for a typed tick label.
    [Document.editor setTickSpacing:5 forAxis:[graph xAxis]];
    [Document.undoManager enableUndoRegistration];

    [(NSDocumentController *)NSDocumentController.sharedDocumentController addDocument:Document];
    [Document makeWindowControllers];
    Owner = Document.windowControllers.firstObject;
    Check(Owner.window != nil && !Owner.window.visible, @"Nib window loaded and not shown");
    [Owner chooseInitialWindowFrameInVisibleFrame:Screen];
    [Owner refreshInspectors];
    GraphView = [Owner valueForKey:@"_graphView"];
    ScrollView = [Owner valueForKey:@"_graphScrollView"];
    Check(GraphView.labelFinder == Owner.labelFinder && Owner.labelFinder != nil, @"The window has a label finder wired to its canvas");
    Check(Owner.labelFinder.textFinder.findBarContainer == ScrollView && Owner.labelFinder.textFinder.client == (id)Owner.labelFinder, @"The find bar belongs to the canvas scroll view");
    Drain();

    // A tick label the user typed: an interior x tick drawn on the canvas, renamed as the editor would.
    [Document.editor prepareForDisplay];
    RSAxis *axis = [graph xAxis];
    NSArray *ticks = [[[axis userLabelsDictionary] allValues] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RSTextLabel *label, NSDictionary *bindings) {
        return [label isVisible] && [label tickValue] > [graph xMin] && [label tickValue] < [graph xMax];
    }]];
    Check(ticks.count >= 1, [NSString stringWithFormat:@"The x axis draws an interior tick label (%lu)", (unsigned long)ticks.count]);
    TickLabel = ticks[ticks.count / 2];
    [Document.undoManager disableUndoRegistration];
    [TickLabel setText:@"Supply peak"];
    [Document.undoManager enableUndoRegistration];
    [Document.editor setNeedsDisplay];
    [GraphView setSelection:nil];
    Drain();
    [Document.undoManager removeAllActions];
    [Document updateChangeCount:NSChangeCleared];
    Check(!Document.isDocumentEdited && !Document.undoManager.canUndo, @"Fixture starts clean");
}

static NSMenuItem *Item(SEL action, NSInteger tag) {
    NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:@"" action:action keyEquivalent:@""] autorelease];
    item.tag = tag;
    return item;
}
// The object a menu item reaches from the window's first responder, as AppKit would find it.
static id TargetFor(SEL action) {
    NSWindow *window = Owner.window;
    for (NSResponder *responder = window.firstResponder; responder; responder = responder.nextResponder)
        if ([responder respondsToSelector:action]) return responder;
    if ([window.delegate respondsToSelector:action]) return window.delegate;
    return nil;
}
static BOOL Validate(NSInteger tag) {
    id target = TargetFor(@selector(performGraphFindAction:));
    Check(target == Owner, [NSString stringWithFormat:@"Find reaches the window controller from %@ (got %@)", Owner.window.firstResponder.className, [target className]]);
    return [target validateMenuItem:Item(@selector(performGraphFindAction:), tag)];
}
static void Send(NSInteger tag) {
    Check(Validate(tag), [NSString stringWithFormat:@"Find action %ld is enabled", (long)tag]);
    [TargetFor(@selector(performGraphFindAction:)) performGraphFindAction:Item(@selector(performGraphFindAction:), tag)];
    Drain();
}
static NSRect VisibleRect(void) { return GraphView.visibleRect; }
static NSRect LabelRect(RSTextLabel *label) {
    NSRect rect = NSRectFromCGRect([Document.editor.mapper rectFromLabel:label offset:0]);
    return label.rotation ? NSMakeRect(NSMinX(rect) - NSHeight(rect), NSMinY(rect), NSHeight(rect), NSWidth(rect)) : rect;
}

#pragma mark - Checks

static void CheckMatchesInReadingOrder(void) {
    SetFindString(@"supply");
    NSArray *expected = @[SupplyCurve, SupplyNote, PointLabel, TickLabel, XTitle];
    NSMutableArray *seen = [NSMutableArray array];
    for (NSUInteger press = 0; press < expected.count + 1; press++) {
        Send(NSTextFinderActionNextMatch);
        [seen addObject:Name(Selection())];
        RSGraphElement *want = expected[press % expected.count];
        Check(Selection() == want, [NSString stringWithFormat:@"Find Next %lu selects %@ (got %@; so far %@)", (unsigned long)press + 1, Name(want), Name(Selection()), seen]);
        Check(!GraphView.isEditingLabel, @"A match is selected, not edited");
    }
    NSLog(@"PASS Find Next 'supply': %@ (free labels, point label, typed tick label, axis title; wraps to the first)", [seen componentsJoinedByString:@" -> "]);
    // Previous from the first match wraps to the last.
    Send(NSTextFinderActionPreviousMatch);
    Check(Selection() == XTitle, [NSString stringWithFormat:@"Find Previous from the first match wraps to the x-axis title (got %@)", Name(Selection())]);
    Send(NSTextFinderActionPreviousMatch);
    Check(Selection() == TickLabel, [NSString stringWithFormat:@"Find Previous walks backwards (got %@)", Name(Selection())]);
    NSLog(@"PASS Find Previous wraps from the first match to the last and walks backwards");
    // Hidden and non-matching labels are never selected; neither are automatic tick numbers.
    Check(![seen containsObject:Name(YTitle)] && ![seen containsObject:Name(Demand)], @"The hidden y-axis title and 'Demand' never match");
    // The search starts after the selected label.
    [GraphView setSelection:SupplyNote]; Drain();
    Send(NSTextFinderActionNextMatch);
    Check(Selection() == PointLabel, [NSString stringWithFormat:@"Find Next starts after the selected label (got %@)", Name(Selection())]);
    [GraphView setSelection:Demand]; Drain();
    Send(NSTextFinderActionNextMatch);
    Check(Selection() == SupplyNote, [NSString stringWithFormat:@"Find Next after a non-matching selected label goes to the next match below it (got %@)", Name(Selection())]);
    NSLog(@"PASS Find Next starts after the selection");
    // Case: 'SUPPLY' finds the same labels case-insensitively.
    SetFindString(@"SUPPLY");
    [GraphView setSelection:nil]; Drain();
    Send(NSTextFinderActionNextMatch);
    Check(Selection() == SupplyCurve, @"Matching is case-insensitive by default");
}

static void CheckScrollAt400(void) {
    NSPopUpButton *zoom = [Owner valueForKey:@"_viewportZoom"];
    [zoom selectItemAtIndex:4]; [Owner changeViewportZoom:zoom]; Drain();
    Check(fabs(ScrollView.magnification - 4) < 0.01, @"Canvas at 400%");
    SetFindString(@"supply");
    [GraphView setSelection:nil]; Drain();
    [ScrollView.contentView scrollToPoint:NSZeroPoint]; [ScrollView reflectScrolledClipView:ScrollView.contentView]; Drain();
    NSArray *expected = @[SupplyCurve, SupplyNote, PointLabel, TickLabel, XTitle];
    BOOL scrolled = NO;
    for (RSTextLabel *label in expected) {
        NSRect before = VisibleRect();
        Send(NSTextFinderActionNextMatch);
        Check(Selection() == label, [NSString stringWithFormat:@"400%%: Find Next selects %@ (got %@)", Name(label), Name(Selection())]);
        NSRect rect = LabelRect(label);
        Check(NSContainsRect(VisibleRect(), NSIntersectionRect(rect, GraphView.bounds)), [NSString stringWithFormat:@"400%%: %@ %@ is scrolled into view %@", Name(label), NSStringFromRect(rect), NSStringFromRect(VisibleRect())]);
        scrolled = scrolled || !NSEqualRects(before, VisibleRect());
    }
    Check(scrolled, @"400%: at least one match needed scrolling");
    Check(fabs(ScrollView.magnification - 4) < 0.01, @"Find kept the zoom");
    // Jump to Selection brings the selection back after scrolling away.
    [ScrollView.contentView scrollToPoint:NSZeroPoint]; [ScrollView reflectScrolledClipView:ScrollView.contentView]; Drain();
    [GraphView setSelection:SupplyCurve]; Drain();
    Check(!NSContainsRect(VisibleRect(), LabelRect(SupplyCurve)), @"400%: the top label is out of view at the bottom-left");
    id target = TargetFor(@selector(jumpToSelection:));
    Check(target == Owner && [target validateMenuItem:Item(@selector(jumpToSelection:), 0)], @"Jump to Selection is enabled with a selection");
    [target jumpToSelection:nil]; Drain();
    Check(NSContainsRect(VisibleRect(), LabelRect(SupplyCurve)), @"Jump to Selection scrolls the selected label into view");
    [zoom selectItemAtIndex:2]; [Owner changeViewportZoom:zoom]; Drain();
    NSLog(@"PASS 400%%: every match scrolled into view without changing the zoom; Jump to Selection");
}

static void CheckNoMatchAndUseSelection(void) {
    SetFindString(@"zzzz");
    [GraphView setSelection:SupplyNote]; Drain();
    Send(NSTextFinderActionNextMatch);
    Check(Selection() == SupplyNote, @"No match leaves the selection unchanged (Next)");
    Send(NSTextFinderActionPreviousMatch);
    Check(Selection() == SupplyNote, @"No match leaves the selection unchanged (Previous)");
    // Use Selection for Find takes the selected label's text.
    [GraphView setSelection:Demand]; Drain();
    Send(NSTextFinderActionSetSearchString);
    Check([FindString() isEqualToString:@"Demand"], [NSString stringWithFormat:@"Use Selection for Find takes the label text (find string '%@')", FindString()]);
    [GraphView setSelection:nil]; Drain();
    Send(NSTextFinderActionNextMatch);
    Check(Selection() == Demand, @"Find Next finds the text taken from the selection");
    [GraphView setSelection:nil]; Drain();
    Check(!Validate(NSTextFinderActionSetSearchString), @"Use Selection for Find is disabled with nothing selected");
    NSLog(@"PASS no match leaves the selection; Use Selection for Find");
}

static NSView *FindSubview(NSView *view, Class cls) {
    if ([view isKindOfClass:cls]) return view;
    for (NSView *subview in view.subviews) { NSView *found = FindSubview(subview, cls); if (found) return found; }
    return nil;
}
static void CollectButtons(NSView *view, NSMutableArray *into) {
    if ([view isKindOfClass:NSButton.class] && !view.isHiddenOrHasHiddenAncestor) [into addObject:view];
    for (NSView *subview in view.subviews) CollectButtons(subview, into);
}
static void TypeInFindBar(NSString *text) {
    NSSearchField *field = (NSSearchField *)FindSubview(ScrollView.findBarView, NSSearchField.class);
    Check(field != nil, @"The find bar has a search field");
    if (![Owner.window.firstResponder isKindOfClass:NSTextView.class] || ((NSTextView *)Owner.window.firstResponder).delegate != (id)field)
        [Owner.window makeFirstResponder:field];
    NSTextView *editor = (NSTextView *)Owner.window.firstResponder;
    Check([editor isKindOfClass:NSTextView.class], @"Typing goes to the find bar field");
    [editor selectAll:nil];
    [editor insertText:text replacementRange:editor.selectedRange];
    Settle();
}

static void CheckFindBar(void) {
    [GraphView setSelection:nil];
    [Owner.window makeFirstResponder:GraphView]; Drain();
    Send(NSTextFinderActionShowFindInterface);
    Check(ScrollView.isFindBarVisible && ScrollView.findBarView != nil, @"Find… shows the find bar at the top of the canvas");
    NSSearchField *field = (NSSearchField *)FindSubview(ScrollView.findBarView, NSSearchField.class);
    Check(field && field.canBecomeKeyView && [Owner.window.firstResponder isKindOfClass:NSTextView.class] && ((NSTextView *)Owner.window.firstResponder).delegate == (id)field, @"The find bar's search field has keyboard focus and is a key view");
    // AppKit exposes the search field through its cell (the control itself is ignored).
    id fieldElement = field.accessibilityChildren.firstObject ?: field.cell;
    Check([[fieldElement accessibilityRole] isEqualToString:NSAccessibilityTextFieldRole] && [fieldElement isAccessibilityElement], [NSString stringWithFormat:@"VoiceOver reads the find field as a text field (%@ %@)", fieldElement, [fieldElement accessibilityRole]]);
    NSMutableArray *buttons = [NSMutableArray array];
    CollectButtons(ScrollView.findBarView, buttons);
    Check(buttons.count > 0, @"The find bar shows its buttons");
    for (NSButton *button in buttons)
        Check(button.accessibilityLabel.length || button.title.length || button.accessibilityTitle.length, [NSString stringWithFormat:@"Find bar button %@ has a VoiceOver label", button]);
    // Incremental search: typing highlights every match and selects the first.
    TypeInFindBar(@"supply");
    NSArray *matches = Owner.labelFinder.textFinder.incrementalMatchRanges;
    Check(matches.count == 5, [NSString stringWithFormat:@"Incremental search finds the five visible matches (got %lu)", (unsigned long)matches.count]);
    Check(Selection() == SupplyCurve, [NSString stringWithFormat:@"Typing selects the first match (got %@)", Name(Selection())]);
    // The highlights draw behind the graph; drawing must work while they show.
    NSBitmapImageRep *bitmap = [GraphView bitmapImageRepForCachingDisplayInRect:GraphView.bounds];
    [GraphView cacheDisplayInRect:GraphView.bounds toBitmapImageRep:bitmap];
    Check(bitmap != nil, @"The canvas draws with match highlights");
    // Return in the bar and Find Next step through the matches from there.
    Send(NSTextFinderActionNextMatch);
    Check(Selection() == SupplyNote, [NSString stringWithFormat:@"Find Next from the bar goes to the second match (got %@)", Name(Selection())]);
    Send(NSTextFinderActionPreviousMatch);
    Check(Selection() == SupplyCurve, [NSString stringWithFormat:@"Find Previous from the bar goes back (got %@)", Name(Selection())]);
    // No match: nothing highlighted and the selection stays.
    TypeInFindBar(@"zzzz");
    Check(Owner.labelFinder.textFinder.incrementalMatchRanges.count == 0, @"No incremental matches for 'zzzz'");
    Check(Selection() == SupplyCurve, [NSString stringWithFormat:@"A search with no match leaves the selection unchanged (got %@)", Name(Selection())]);
    Send(NSTextFinderActionNextMatch);
    Check(Selection() == SupplyCurve, @"Find Next with no match leaves the selection unchanged");
    // Editing the graph while the bar is open updates the searchable text.
    TypeInFindBar(@"demand");
    Check(Owner.labelFinder.textFinder.incrementalMatchRanges.count == 1 && Selection() == Demand, @"'demand' matches the one label");
    [Document.undoManager disableUndoRegistration];
    RSTextLabel *added = AddLabel(@"Demand curve", 0.1, 0.45);
    [Document.undoManager enableUndoRegistration];
    [Document.editor setNeedsDisplay]; Settle();
    TypeInFindBar(@"demand c");
    Check(Owner.labelFinder.textFinder.incrementalMatchRanges.count == 1 && Selection() == added, [NSString stringWithFormat:@"A label added while the bar is open is found (got %@)", Name(Selection())]);
    [Document.undoManager disableUndoRegistration];
    [Graph() removeLabel:added];
    [Document.undoManager enableUndoRegistration];
    [GraphView setSelection:nil];
    [Document.editor setNeedsDisplay]; Settle();
    Send(NSTextFinderActionHideFindInterface);
    Check(!ScrollView.isFindBarVisible, @"Done hides the find bar");
    NSLog(@"PASS find bar: focus, VoiceOver labels, incremental matches, no match, live updates");
}

static void CheckFindWhileEditing(void) {
    [Owner.window makeFirstResponder:GraphView];
    [GraphView setSelection:SupplyNote]; Drain();
    [GraphView startEditingLabel]; Drain();
    Check(GraphView.isEditingLabel && GraphView.labelEditor && Owner.window.firstResponder == GraphView.labelEditor, @"Editing 'supply NOTE' in place");
    SetFindString(@"p");
    NSTextView *editor = GraphView.labelEditor;
    // "supply NOTE": 'p' at 2 and 3; Find works on this text only and wraps inside it.
    NSArray *expected = @[@2, @3, @2];
    for (NSNumber *location in expected) {
        Send(NSTextFinderActionNextMatch);
        Check(GraphView.isEditingLabel && Selection() == SupplyNote, @"Find while editing keeps editing the same label");
        Check(NSEqualRanges(editor.selectedRange, NSMakeRange(location.unsignedIntegerValue, 1)), [NSString stringWithFormat:@"Find Next inside the label selects 'p' at %@ (got %@)", location, NSStringFromRange(editor.selectedRange)]);
    }
    Send(NSTextFinderActionPreviousMatch);
    Check(NSEqualRanges(editor.selectedRange, NSMakeRange(3, 1)), [NSString stringWithFormat:@"Find Previous inside the label wraps (got %@)", NSStringFromRange(editor.selectedRange)]);
    // 'curve' is in another label only: no match inside this one.
    SetFindString(@"curve");
    NSRange before = editor.selectedRange;
    Send(NSTextFinderActionNextMatch);
    Check(GraphView.isEditingLabel && Selection() == SupplyNote && NSEqualRanges(editor.selectedRange, before), @"Text in other labels is not searched while editing");
    // Use Selection for Find takes the selected characters.
    editor.selectedRange = NSMakeRange(7, 4);
    Send(NSTextFinderActionSetSearchString);
    Check([FindString() isEqualToString:@"NOTE"], [NSString stringWithFormat:@"Use Selection for Find while editing takes the selected text (got '%@')", FindString()]);
    Check([editor.string isEqualToString:@"supply NOTE"], @"Find while editing does not change the text");
    // Find… ends the edit and searches every label.
    Send(NSTextFinderActionShowFindInterface);
    Check(!GraphView.isEditingLabel && ScrollView.isFindBarVisible, @"Find… ends the edit and shows the find bar");
    Check([SupplyNote.text isEqualToString:@"supply NOTE"], @"Ending the edit kept the text");
    TypeInFindBar(@"supply");
    Check(Owner.labelFinder.textFinder.incrementalMatchRanges.count == 5, @"After the edit the bar searches every label again");
    Send(NSTextFinderActionHideFindInterface);
    NSLog(@"PASS Find inside a label being edited works on its text only; Find… ends the edit");
}

static void CheckRoutingFromTextFields(void) {
    [GraphView setSelection:nil];
    RSInspectorSidebar *sidebar = [Owner valueForKey:@"inspectorSidebar"];
    Check([sidebar selectSection:2], @"Canvas section"); Drain();
    NSTextField *width = [[sidebar tabWithIdentifier:@"com.graphsketcher.GraphSketcher.inspector.document"].inspector valueForKey:@"canvasWidth"];
    Check([Owner.window makeFirstResponder:width], @"The Width field takes focus");
    Check([Owner.window.firstResponder isKindOfClass:NSTextView.class], @"A field editor is first responder");
    Check(Validate(NSTextFinderActionShowFindInterface) && Validate(NSTextFinderActionNextMatch), @"Find stays enabled while a sidebar field is focused");
    SetFindString(@"supply");
    Send(NSTextFinderActionNextMatch);
    Check(Selection() == SupplyCurve, [NSString stringWithFormat:@"Find Next from a focused sidebar field searches the canvas (got %@)", Name(Selection())]);
    [Owner.window makeFirstResponder:GraphView]; Drain();
    NSLog(@"PASS Find reaches the window from the canvas, a label editor, the find bar and sidebar fields");
}

#pragma mark - Find indicator

// What NSTextFinder drew into its find indicator: the bitmap, the context's scale and the dark
// (text) pixels. Recorded after every drawing made for the indicator, by the client's
// -drawCharactersInRange:forContentView: or, without it, the canvas's -drawRect:.
typedef struct { size_t width, height; CGFloat scale; NSInteger ink; NSRect inkBounds; BOOL readable; } IndicatorDrawing;
static NSMutableArray *IndicatorDrawings;
static void RecordIndicatorDrawing(void) {
    CGContextRef context = NSGraphicsContext.currentContext.CGContext;
    IndicatorDrawing drawing = {0};
    drawing.scale = CGContextGetCTM(context).a;
    // Whatever the indicator bitmap's format, read it back as 32-bit premultiplied BGRA.
    CGImageRef image = CGBitmapContextGetData(context) ? CGBitmapContextCreateImage(context) : NULL;
    if (image) {
        drawing.width = CGImageGetWidth(image); drawing.height = CGImageGetHeight(image);
        CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGContextRef copy = CGBitmapContextCreate(NULL, drawing.width, drawing.height, 8, 0, space, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
        CGColorSpaceRelease(space);
        if (copy) {
            CGContextDrawImage(copy, CGRectMake(0, 0, drawing.width, drawing.height), image);
            unsigned char *data = CGBitmapContextGetData(copy);
            size_t bytesPerRow = CGBitmapContextGetBytesPerRow(copy);
            NSInteger minX = drawing.width, minY = drawing.height, maxX = -1, maxY = -1;
            for (size_t y = 0; y < drawing.height; y++)
                for (size_t x = 0; x < drawing.width; x++) {
                    unsigned char *pixel = data + y * bytesPerRow + x * 4;
                    if (pixel[3] < 128 || pixel[0] + pixel[1] + pixel[2] >= 3 * 0.4 * pixel[3]) continue;
                    drawing.ink++;
                    minX = MIN(minX, (NSInteger)x); maxX = MAX(maxX, (NSInteger)x); minY = MIN(minY, (NSInteger)y); maxY = MAX(maxY, (NSInteger)y);
                }
            if (drawing.ink) drawing.inkBounds = NSMakeRect(minX, minY, maxX - minX + 1, maxY - minY + 1);
            drawing.readable = YES;
            CGContextRelease(copy);
        }
        CGImageRelease(image);
    }
    [IndicatorDrawings addObject:[NSValue valueWithBytes:&drawing objCType:@encode(IndicatorDrawing)]];
}
static void InstallIndicatorRecorder(void) {
    IndicatorDrawings = [[NSMutableArray alloc] init];
    Method drawRect = class_getInstanceMethod(RSGraphView.class, @selector(drawRect:));
    void (*originalDrawRect)(id, SEL, NSRect) = (void *)method_getImplementation(drawRect);
    method_setImplementation(drawRect, imp_implementationWithBlock(^(RSGraphView *view, NSRect rect) {
        originalDrawRect(view, @selector(drawRect:), rect);
        if (view.isDrawingFindIndicator) RecordIndicatorDrawing();
    }));
    SEL drawCharacters = @selector(drawCharactersInRange:forContentView:);
    Method client = class_getInstanceMethod(RSLabelFinder.class, drawCharacters);
    if (!client) return;  // AppKit then draws the indicator with the canvas's -drawRect:
    void (*originalDrawCharacters)(id, SEL, NSRange, NSView *) = (void *)method_getImplementation(client);
    method_setImplementation(client, imp_implementationWithBlock(^(RSLabelFinder *finder, NSRange range, NSView *view) {
        originalDrawCharacters(finder, drawCharacters, range, view);
        RecordIndicatorDrawing();
    }));
}

// Find Next to a label at the current zoom and preset: the indicator shows that label's text at the
// label's size in a color readable on its yellow (dark), filling the indicator's bitmap.
static void CheckIndicatorFor(RSTextLabel *label, NSString *search, NSString *what) {
    SetFindString(search);
    [GraphView setSelection:nil]; Drain();
    [IndicatorDrawings removeAllObjects];
    NSColor *color = [[label.color retain] autorelease];
    Send(NSTextFinderActionNextMatch);
    Settle();
    Check(Selection() == label, [NSString stringWithFormat:@"%@: Find Next selects %@ (got %@)", what, Name(label), Name(Selection())]);
    Check(IndicatorDrawings.count > 0, [what stringByAppendingString:@": the find indicator was drawn"]);
    // The last drawing into a bitmap AppKit gave for the indicator is its content.
    IndicatorDrawing drawing = {0};
    NSMutableArray *drawn = [NSMutableArray array];
    for (NSValue *value in IndicatorDrawings) {
        IndicatorDrawing each;
        [value getValue:&each];
        [drawn addObject:[NSString stringWithFormat:@"%zux%zu%@ scale %.2f", each.width, each.height, each.readable ? @"" : @" (no bitmap)", each.scale]];
        if (each.readable) drawing = each;
    }
    Check(drawing.readable, [NSString stringWithFormat:@"%@: the indicator draws into a bitmap (%@)", what, drawn]);
    NSRect rect = LabelRect(label);
    CGFloat magnification = ScrollView.magnification;
    // The bitmap is the label at this zoom (times the backing scale the context carries).
    Check(fabs(drawing.scale / magnification - round(drawing.scale / magnification)) < 0.01 && drawing.scale >= magnification - 0.01, [NSString stringWithFormat:@"%@: the indicator context is scaled by the zoom (%.3f at %.0f%%)", what, drawing.scale, magnification * 100]);
    Check(fabs(drawing.width - NSWidth(rect) * drawing.scale) <= 2 + 0.05 * NSWidth(rect) * drawing.scale, [NSString stringWithFormat:@"%@: the indicator is the label's width at this zoom (%zu px for %.1f pt × %.2f)", what, drawing.width, NSWidth(rect), drawing.scale]);
    // The text spans the label: dark ink across most of its width and a good part of its height.
    NSString *ink = [NSString stringWithFormat:@"ink %ld px in %@ of %zux%zu", (long)drawing.ink, NSStringFromRect(drawing.inkBounds), drawing.width, drawing.height];
    Check(drawing.ink > 0, [NSString stringWithFormat:@"%@: the label's text is drawn in the indicator, dark on its yellow (%@)", what, ink]);
    Check(NSWidth(drawing.inkBounds) >= 0.6 * drawing.width && NSHeight(drawing.inkBounds) >= 0.35 * drawing.height, [NSString stringWithFormat:@"%@: the text is drawn at the label's size (%@)", what, ink]);
    Check(drawing.ink <= 0.6 * drawing.width * drawing.height, [NSString stringWithFormat:@"%@: only the text is dark, no canvas background (%@)", what, ink]);
    Check([label.color isEqual:color], [what stringByAppendingString:@": drawing the indicator left the label's color unchanged"]);
    NSLog(@"PASS find indicator %@: %@ at %.0f%%, %@", what, Name(label), magnification * 100, ink);
}

static void CheckFindIndicator(void) {
    NSPopUpButton *zoom = [Owner valueForKey:@"_viewportZoom"];
    // 50% stands for Fit on a canvas larger than the window (the MacBook report); here Fit is 100%.
    NSArray *zooms = @[@[@1, @"50%"], @[@4, @"400%"]];
    for (NSArray *item in zooms) {
        [zoom selectItemAtIndex:[item[0] integerValue]]; [Owner changeViewportZoom:zoom]; Drain();
        CheckIndicatorFor(Demand, @"demand", item[1]);
        CheckIndicatorFor(XTitle, @"quantity", [item[1] stringByAppendingString:@" axis title"]);
    }
    // Chalkboard: light text on a dark canvas; the indicator still shows dark text and no canvas.
    Check([Document.editor applyStylePreset:2], @"Chalkboard applies");
    Drain();
    NSColor *chalk = [Demand.color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    Check(0.2126 * chalk.redComponent + 0.7152 * chalk.greenComponent + 0.0722 * chalk.blueComponent > 0.45, [NSString stringWithFormat:@"Chalkboard draws labels in a light color (%@)", chalk]);
    for (NSArray *item in zooms) {
        [zoom selectItemAtIndex:[item[0] integerValue]]; [Owner changeViewportZoom:zoom]; Drain();
        CheckIndicatorFor(Demand, @"demand", [item[1] stringByAppendingString:@" Chalkboard"]);
    }
    [Document.undoManager undo]; Drain();
    Check(!Document.isDocumentEdited, @"Undoing Chalkboard returns the fixture to clean");
    [zoom selectItemAtIndex:2]; [Owner changeViewportZoom:zoom]; Drain();
}

static void CheckFind(void) {
    OpenFixtureDocument();
    NSArray *state = LabelState();
    CheckMatchesInReadingOrder();
    CheckScrollAt400();
    CheckNoMatchAndUseSelection();
    CheckFindBar();
    CheckFindWhileEditing();
    CheckRoutingFromTextFields();
    NSMutableArray *changed = [NSMutableArray array];
    NSArray *after = LabelState();
    for (NSString *line in after) if (![state containsObject:line]) [changed addObject:line];
    for (NSString *line in state) if (![after containsObject:line]) [changed addObject:[@"was " stringByAppendingString:line]];
    Check(changed.count == 0, [NSString stringWithFormat:@"Find moved or changed no label: %@", changed]);
    // Ending the in-place edit with unchanged text may close an empty undo group; nothing to undo.
    Check(!Document.undoManager.canUndo, [NSString stringWithFormat:@"Find added no undo step (undo: '%@')", Document.undoManager.undoActionName]);
    Check(!Document.isDocumentEdited, @"Find left the document unedited");
    NSLog(@"PASS undo neutrality: no undo step, document unedited, labels unchanged");
    CheckFindIndicator();
    [Document close];
    for (NSString *key in @[@"LastFrameString", @"LastCanvasSize"]) [[OFPreferenceWrapper sharedPreferenceWrapper] removeObjectForKey:key];
    puts("PASS find checks");
}

int main(int argc, const char *argv[]) {
    int status = 0;
    @autoreleasepool { @try {
        [(Class)NSBundle.mainBundle.principalClass sharedApplication];
        [[FixtureDocumentController alloc] init];
        Check([NSBundle.mainBundle.bundleIdentifier hasPrefix:@"com.graphink.findchecks."], @"Unique fixture domain required");
        NSString *domain = NSBundle.mainBundle.bundleIdentifier;
        CFPreferencesSetAppValue(CFSTR("FindIsolationProbe"), (CFStringRef)domain, kCFPreferencesCurrentApplication);
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
        id probe = [(id)CFPreferencesCopyAppValue(CFSTR("FindIsolationProbe"), (CFStringRef)domain) autorelease];
        Check([probe isEqual:domain], @"Current-application defaults did not route to the unique fixture domain");
        SavedFindPasteboard = [FindPasteboardContents() retain];
        OFController *lifecycle = OFController.sharedController;
        Check([lifecycle isKindOfClass:NSClassFromString(@"AppController")], @"OFControllerClass is the production AppController");
        [lifecycle didInitialize]; [lifecycle startedRunning];
        Check(NSApp.delegate == nil, @"No application delegate before the fixture sets one");
        NSApp.delegate = (id <NSApplicationDelegate>)lifecycle;
        InstallIndicatorRecorder();
        CheckFind();
        Check([lifecycle requestTermination] == OFControllerTerminateNow, @"Fixture lifecycle refused termination");
        [lifecycle willTerminate];
    } @catch (NSException *exception) {
        NSLog(@"FAIL find: %@", exception); status = 1;
    } @finally {
        RestoreFindPasteboard();
        if (SavedFindPasteboard && ![FindPasteboardContents() isEqualToArray:SavedFindPasteboard]) {
            NSLog(@"FAIL find: the find pasteboard was not restored"); status = 1;
        } else if (SavedFindPasteboard) {
            puts("PASS find pasteboard restored");
        }
    } }
    if (!status) puts("PASS find checks; offscreen only");
    return status;
}
