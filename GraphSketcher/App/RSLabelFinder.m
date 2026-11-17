#import "RSLabelFinder.h"

#import "RSGraphView.h"
#import "RSSelector.h"

#import <GraphSketcherModel/RSAxis.h>
#import <GraphSketcherModel/RSDataMapper.h>
#import <GraphSketcherModel/RSGraph.h>
#import <GraphSketcherModel/RSGraphEditor.h>
#import <GraphSketcherModel/RSGraphElement-Rendering.h>
#import <GraphSketcherModel/RSText.h>
#import <GraphSketcherModel/RSTextLabel.h>

static void *RSLabelFinderMatchesContext = &RSLabelFinderMatchesContext;
static const CGFloat RSLabelFinderScrollMargin = 12;

// One searchable label: its text, its range in the concatenated string and its canvas bounds.
// Immutable; NSTextFinder reads the strings on a background queue during incremental searches.
// The label and the rect are used on the main thread only.
@interface RSLabelFinderEntry : NSObject {
@public
    NSString *_string;
    NSRange _range;
    RSTextLabel *_label;  // not retained; the snapshot is replaced whenever the labels change
    NSRect _rect;
}
@end
@implementation RSLabelFinderEntry
- (void)dealloc {
    [_string release];
    [super dealloc];
}
@end

// The searchable text at one moment: every visible label in reading order, or the text of the
// label being edited.
@interface RSLabelFinderSnapshot : NSObject {
@public
    NSArray *_entries;
    NSUInteger _length;
    BOOL _editing;
}
@end
@implementation RSLabelFinderSnapshot
- (void)dealloc {
    [_entries release];
    [super dealloc];
}
- (BOOL)hasSameTextAs:(RSLabelFinderSnapshot *)other {
    if (!other || other->_editing != _editing || other->_entries.count != _entries.count)
        return NO;
    for (NSUInteger index = 0; index < _entries.count; index++) {
        RSLabelFinderEntry *a = _entries[index], *b = other->_entries[index];
        if (a->_label != b->_label || ![a->_string isEqualToString:b->_string])
            return NO;
    }
    return YES;
}
- (RSLabelFinderEntry *)entryAtIndex:(NSUInteger)index {
    for (RSLabelFinderEntry *entry in _entries)
        if (NSLocationInRange(index, entry->_range))
            return entry;
    return nil;
}
- (RSLabelFinderEntry *)entryForLabel:(RSGraphElement *)label {
    for (RSLabelFinderEntry *entry in _entries)
        if (entry->_label == label)
            return entry;
    return nil;
}
@end

// The canvas bounds of a label, rotated about its position as RSText draws it.
static NSRect RSLabelBounds(RSTextLabel *TL, RSDataMapper *mapper) {
    CGRect rect = [mapper rectFromLabel:TL offset:0];
    CGFloat degrees = [TL rotation];
    if (degrees == 0)
        return NSRectFromCGRect(rect);
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:rect.origin.x yBy:rect.origin.y];
    [transform rotateByDegrees:degrees];
    [transform translateXBy:-rect.origin.x yBy:-rect.origin.y];
    NSBezierPath *path = [NSBezierPath bezierPathWithRect:NSRectFromCGRect(rect)];
    [path transformUsingAffineTransform:transform];
    return path.bounds;
}

// Text on the find indicator's yellow: the label's own color unless it is too light to read there
// (white text on a dark preset such as Chalkboard), then black.
static NSColor *RSFindIndicatorTextColor(NSColor *color) {
    NSColor *rgb = [color ?: NSColor.blackColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!rgb)
        return NSColor.blackColor;
    CGFloat luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent;
    return luminance > 0.45 || rgb.alphaComponent < 0.5 ? NSColor.blackColor : [rgb colorWithAlphaComponent:1];
}

@interface RSLabelFinder ()
@property(atomic, retain) RSLabelFinderSnapshot *snapshot;
@end

@implementation RSLabelFinder {
    RSGraphView *_graphView;  // not retained; owned by the same window
    NSScrollView *_scrollView;
    NSTextFinder *_textFinder;
    RSLabelFinderSnapshot *_snapshot;
    NSRange _lastMatch;  // the label part the last match selected; {NSNotFound, 0} if none
    BOOL _dirty;
    BOOL _refreshQueued;
    BOOL _invalidated;
}

@synthesize snapshot = _snapshot;
@synthesize textFinder = _textFinder;

- (instancetype)initWithGraphView:(RSGraphView *)graphView findBarContainer:(NSScrollView *)scrollView {
    if (!(self = [super init]))
        return nil;
    _graphView = graphView;
    _scrollView = scrollView;
    _lastMatch = NSMakeRange(NSNotFound, 0);
    _dirty = YES;
    _textFinder = [[NSTextFinder alloc] init];
    _textFinder.client = self;
    _textFinder.findBarContainer = scrollView;
    _textFinder.incrementalSearchingEnabled = YES;
    // Matches are highlighted behind the graph instead; dimming would hide the canvas.
    _textFinder.incrementalSearchingShouldDimContentView = NO;
    [_textFinder addObserver:self forKeyPath:@"incrementalMatchRanges" options:0 context:RSLabelFinderMatchesContext];
    return self;
}

- (void)invalidate {
    if (_invalidated)
        return;
    _invalidated = YES;
    [_textFinder removeObserver:self forKeyPath:@"incrementalMatchRanges" context:RSLabelFinderMatchesContext];
    [_textFinder cancelFindIndicator];
    _textFinder.client = nil;
    _textFinder.findBarContainer = nil;
    _graphView = nil;
    _scrollView = nil;
}

- (void)dealloc {
    [self invalidate];
    [_textFinder release];
    [_snapshot release];
    [super dealloc];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != RSLabelFinderMatchesContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    [_graphView setNeedsDisplay:YES];
}

#pragma mark - Searchable text

- (RSTextLabel *)selectedLabel {
    RSGraphElement *selection = [[_graphView RSSelector] selection];
    return [selection isKindOfClass:[RSTextLabel class]] ? (RSTextLabel *)selection : nil;
}

- (RSLabelFinderSnapshot *)buildSnapshot {
    RSLabelFinderSnapshot *snapshot = [[[RSLabelFinderSnapshot alloc] init] autorelease];
    NSMutableArray *entries = [NSMutableArray array];
    NSTextView *labelEditor = [_graphView labelEditor];
    if (labelEditor) {
        RSLabelFinderEntry *entry = [[[RSLabelFinderEntry alloc] init] autorelease];
        entry->_string = [labelEditor.string copy];
        entry->_range = NSMakeRange(0, entry->_string.length);
        entry->_label = [self selectedLabel];
        entry->_rect = labelEditor.bounds;
        [entries addObject:entry];
        snapshot->_editing = YES;
    } else if (_graphView.editor) {
        RSGraphEditor *editor = _graphView.editor;
        RSGraph *graph = editor.graph;
        // Tick label visibility and positions come from the renderer's layout.
        [editor prepareForDisplay];
        NSMutableArray *labels = [NSMutableArray array];
        for (RSTextLabel *TL in [graph Labels]) {
            if (![graph isAxisTickLabel:TL] && [TL isVisible] && [graph shouldDisplayLabel:TL])
                [labels addObject:TL];
        }
        // Tick labels the user typed. The axis also caches a label for every automatic tick
        // number it draws; those still read as the formatted number and are not searched.
        for (RSAxis *axis in @[[graph xAxis], [graph yAxis]]) {
            if (![axis displayTickLabels])
                continue;
            for (RSTextLabel *TL in [[axis userLabelsDictionary] allValues])
                if ([TL isVisible] && ![[TL text] isEqualToString:[axis formattedDataValue:[TL tickValue]]] && ![labels containsObject:TL])
                    [labels addObject:TL];
        }
        for (RSTextLabel *TL in labels) {
            NSString *text = [TL text];
            if (!text.length)
                continue;
            RSLabelFinderEntry *entry = [[[RSLabelFinderEntry alloc] init] autorelease];
            entry->_string = [text copy];
            entry->_label = TL;
            entry->_rect = RSLabelBounds(TL, editor.mapper);
            [entries addObject:entry];
        }
        // Reading order: top to bottom, then left to right (the canvas is not flipped).
        [entries sortUsingComparator:^NSComparisonResult(RSLabelFinderEntry *a, RSLabelFinderEntry *b) {
            CGFloat topA = round(NSMaxY(a->_rect)), topB = round(NSMaxY(b->_rect));
            if (topA != topB)
                return topA > topB ? NSOrderedAscending : NSOrderedDescending;
            if (NSMinX(a->_rect) != NSMinX(b->_rect))
                return NSMinX(a->_rect) < NSMinX(b->_rect) ? NSOrderedAscending : NSOrderedDescending;
            return NSOrderedSame;
        }];
        NSUInteger location = 0;
        for (RSLabelFinderEntry *entry in entries) {
            entry->_range = NSMakeRange(location, entry->_string.length);
            location += entry->_string.length;
        }
    }
    snapshot->_entries = [entries copy];
    RSLabelFinderEntry *last = entries.lastObject;
    snapshot->_length = last ? NSMaxRange(last->_range) : 0;
    return snapshot;
}

// Main thread only. Tells NSTextFinder before the searchable text changes, never during a search.
- (void)refreshIfChanged {
    _dirty = NO;
    if (_invalidated)
        return;
    RSLabelFinderSnapshot *snapshot = [self buildSnapshot];
    if (![snapshot hasSameTextAs:_snapshot]) {
        [_textFinder noteClientStringWillChange];
        _lastMatch = NSMakeRange(NSNotFound, 0);
    }
    self.snapshot = snapshot;
}

- (void)contentDidChange {
    _dirty = YES;
    // With the bar hidden nothing is searching; the next action refreshes first.
    if (_refreshQueued || _invalidated || !_scrollView.findBarVisible)
        return;
    _refreshQueued = YES;
    [self retain];
    dispatch_async(dispatch_get_main_queue(), ^{
        _refreshQueued = NO;
        if (_dirty)
            [self refreshIfChanged];
        [self release];
    });
}

- (RSLabelFinderSnapshot *)currentSnapshot {
    if ([NSThread isMainThread] && (_dirty || !_snapshot) && !_refreshQueued)
        [self refreshIfChanged];
    return self.snapshot;
}

#pragma mark - Actions

- (BOOL)validateAction:(NSTextFinderAction)action {
    if (_invalidated)
        return NO;
    if (action == NSTextFinderActionSetSearchString || action == NSTextFinderActionNextMatch || action == NSTextFinderActionPreviousMatch)
        [self currentSnapshot];
    return [_textFinder validateAction:action];
}

- (void)performAction:(NSTextFinderAction)action {
    if (_invalidated)
        return;
    // The find bar takes keyboard focus, which ends an edit in place: end it first, as a click
    // elsewhere would, so the bar searches every label.
    if (action == NSTextFinderActionShowFindInterface && [_graphView isEditingLabel])
        [_graphView.window makeFirstResponder:_graphView];
    if (_dirty || !_snapshot)
        [self refreshIfChanged];
    [_textFinder performAction:action];
}

- (BOOL)canJumpToSelection {
    return !_invalidated && [[_graphView RSSelector] selected];
}

- (void)jumpToSelection {
    if (![self canJumpToSelection])
        return;
    RSGraphElement *selection = [[_graphView RSSelector] selection];
    RSDataMapper *mapper = _graphView.editor.mapper;
    NSRect rect = [selection isKindOfClass:[RSTextLabel class]] ? RSLabelBounds((RSTextLabel *)selection, mapper) : NSRectFromCGRect([selection viewRectWithMapper:mapper]);
    if (NSIsEmptyRect(rect))
        return;
    [_graphView scrollRectToVisible:NSInsetRect(rect, -RSLabelFinderScrollMargin, -RSLabelFinderScrollMargin)];
}

#pragma mark - Selection

// Selects the label holding a match (or the matched text while editing) and scrolls it into view.
- (void)selectRange:(NSRange)range {
    RSLabelFinderSnapshot *snapshot = self.snapshot;
    NSTextView *labelEditor = [_graphView labelEditor];
    if (snapshot->_editing) {
        if (labelEditor && NSMaxRange(range) <= labelEditor.string.length) {
            labelEditor.selectedRange = range;
            [labelEditor scrollRangeToVisible:range];
        }
        return;
    }
    RSLabelFinderEntry *entry = [snapshot entryAtIndex:range.location];
    if (!entry || labelEditor)
        return;
    _lastMatch = range;
    if ([[_graphView RSSelector] selection] != entry->_label)
        [_graphView setSelection:entry->_label];
    [_graphView scrollRectToVisible:NSInsetRect(entry->_rect, -RSLabelFinderScrollMargin, -RSLabelFinderScrollMargin)];
}

#pragma mark - NSTextFinderClient

- (BOOL)isSelectable { return YES; }
- (BOOL)allowsMultipleSelection { return NO; }
- (BOOL)isEditable { return NO; }  // Find only; no Replace

- (NSUInteger)stringLength {
    return [self currentSnapshot]->_length;
}

- (NSString *)stringAtIndex:(NSUInteger)characterIndex effectiveRange:(NSRangePointer)outRange endsWithSearchBoundary:(BOOL *)outFlag {
    RSLabelFinderSnapshot *snapshot = self.snapshot;  // any thread
    RSLabelFinderEntry *entry = [snapshot entryAtIndex:characterIndex];
    if (outFlag)
        *outFlag = YES;  // a match never spans two labels
    if (!entry) {
        if (outRange)
            *outRange = NSMakeRange(snapshot->_length, 0);
        return @"";
    }
    if (outRange)
        *outRange = entry->_range;
    return entry->_string;
}

// Where Find Next starts: the last match while its label stays selected, else the selected
// label as a whole (so Find Next goes on after it and Use Selection for Find takes its text).
- (NSRange)firstSelectedRange {
    RSLabelFinderSnapshot *snapshot = [self currentSnapshot];
    if (snapshot->_editing) {
        NSTextView *labelEditor = [_graphView labelEditor];
        return labelEditor ? labelEditor.selectedRange : NSMakeRange(0, 0);
    }
    RSTextLabel *selected = [self selectedLabel];
    RSLabelFinderEntry *entry = selected ? [snapshot entryForLabel:selected] : nil;
    if (!entry)
        return NSMakeRange(0, 0);
    if (_lastMatch.location != NSNotFound && NSLocationInRange(_lastMatch.location, entry->_range) && NSMaxRange(_lastMatch) <= NSMaxRange(entry->_range))
        return _lastMatch;
    return entry->_range;
}

- (NSArray *)selectedRanges {
    return @[[NSValue valueWithRange:[self firstSelectedRange]]];
}

- (void)setSelectedRanges:(NSArray *)ranges {
    if (ranges.count)
        [self selectRange:[ranges.firstObject rangeValue]];
}

// NSTextFinder steps through incremental matches by scrolling to them without setting the
// selection, so a scroll to a match also selects it.
- (void)scrollRangeToVisible:(NSRange)range {
    [self selectRange:range];
}

- (NSView *)contentViewAtIndex:(NSUInteger)index effectiveCharacterRange:(NSRangePointer)outRange {
    RSLabelFinderSnapshot *snapshot = self.snapshot;
    if (outRange)
        *outRange = NSMakeRange(0, snapshot->_length);
    if (snapshot->_editing)
        return [_graphView labelEditor] ?: (NSView *)_graphView;
    return _graphView;
}

- (NSArray *)rectsForCharacterRange:(NSRange)range {
    RSLabelFinderSnapshot *snapshot = self.snapshot;
    if (snapshot->_editing) {
        NSTextView *labelEditor = [_graphView labelEditor];
        NSLayoutManager *layoutManager = labelEditor.layoutManager;
        if (!layoutManager || NSMaxRange(range) > labelEditor.string.length)
            return nil;
        NSRange glyphs = [layoutManager glyphRangeForCharacterRange:range actualCharacterRange:NULL];
        NSPoint origin = labelEditor.textContainerOrigin;
        NSMutableArray *rects = [NSMutableArray array];
        [layoutManager enumerateEnclosingRectsForGlyphRange:glyphs withinSelectedGlyphRange:NSMakeRange(NSNotFound, 0) inTextContainer:labelEditor.textContainer usingBlock:^(NSRect rect, BOOL *stop) {
            [rects addObject:[NSValue valueWithRect:NSOffsetRect(rect, origin.x, origin.y)]];
        }];
        return rects;
    }
    RSLabelFinderEntry *entry = [snapshot entryAtIndex:range.location];
    return entry ? @[[NSValue valueWithRect:entry->_rect]] : nil;
}

- (NSArray *)visibleCharacterRanges {
    RSLabelFinderSnapshot *snapshot = self.snapshot;
    if (snapshot->_editing)
        return @[[NSValue valueWithRange:NSMakeRange(0, snapshot->_length)]];
    NSRect visible = _graphView.visibleRect;
    NSMutableArray *ranges = [NSMutableArray array];
    for (RSLabelFinderEntry *entry in snapshot->_entries)
        if (NSIntersectsRect(entry->_rect, visible))
            [ranges addObject:[NSValue valueWithRange:entry->_range]];
    return ranges;
}

#pragma mark - Drawing

// The find indicator's content: only the matched label (or the matched characters of the label
// being edited), at the label's own size. Without this method NSTextFinder redraws the whole canvas
// with -drawRect:, and with the canvas zoomed it scales the context by the magnification but
// translates it by the unzoomed rect (probed on macOS 27.2): the label came out shrunk at Fit and
// outside the indicator at 400%. The clip is the indicator's rect for the match in the context's
// space, so the match is moved onto it; where AppKit gets that right, the offset is zero.
- (void)drawCharactersInRange:(NSRange)range forContentView:(NSView *)view {
    RSLabelFinderSnapshot *snapshot = self.snapshot;
    NSArray *rects = [self rectsForCharacterRange:range];
    if (_invalidated || !snapshot || !rects.count)
        return;
    NSRect match = NSZeroRect;
    for (NSValue *value in rects)
        match = NSUnionRect(match, value.rectValue);
    NSGraphicsContext *context = NSGraphicsContext.currentContext;
    NSRect clip = NSRectFromCGRect(CGContextGetClipBoundingBox(context.CGContext));
    [NSGraphicsContext saveGraphicsState];
    if (fabs(NSWidth(clip) - NSWidth(match)) <= 2 && fabs(NSHeight(clip) - NSHeight(match)) <= 2) {
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform translateXBy:NSMinX(clip) - NSMinX(match) yBy:NSMinY(clip) - NSMinY(match)];
        [transform concat];
    }
    BOOL readable = view.isDrawingFindIndicator;
    if (snapshot->_editing) {
        NSTextView *labelEditor = [_graphView labelEditor];
        NSLayoutManager *layoutManager = labelEditor.layoutManager;
        if (layoutManager && NSMaxRange(range) <= labelEditor.string.length) {
            NSRange glyphs = [layoutManager glyphRangeForCharacterRange:range actualCharacterRange:NULL];
            NSColor *color = [labelEditor.textStorage attribute:NSForegroundColorAttributeName atIndex:range.location effectiveRange:NULL];
            if (readable)
                [layoutManager addTemporaryAttribute:NSForegroundColorAttributeName value:RSFindIndicatorTextColor(color) forCharacterRange:range];
            [layoutManager drawGlyphsForGlyphRange:glyphs atPoint:labelEditor.textContainerOrigin];
            if (readable)
                [layoutManager removeTemporaryAttribute:NSForegroundColorAttributeName forCharacterRange:range];
        }
    } else {
        RSTextLabel *TL = [snapshot entryAtIndex:range.location]->_label;
        NSMutableAttributedString *string = [[[[TL formattedTextObject] attributedString] mutableCopy] autorelease];
        if (readable) {
            [string enumerateAttribute:NSForegroundColorAttributeName inRange:NSMakeRange(0, string.length) options:0 usingBlock:^(NSColor *color, NSRange part, BOOL *stop) {
                [string addAttribute:NSForegroundColorAttributeName value:RSFindIndicatorTextColor(color) range:part];
            }];
        }
        RSText *text = [[[RSText alloc] initWithAttributedString:string] autorelease];
        [text drawAtPoint:[_graphView.editor.mapper convertToViewCoords:[TL position]] baselineRotatedByDegrees:[TL rotation]];
    }
    [NSGraphicsContext restoreGraphicsState];
}

- (void)drawIncrementalMatchHighlights {
    RSLabelFinderSnapshot *snapshot = self.snapshot;
    if (_invalidated || !snapshot || snapshot->_editing || _graphView.isDrawingFindIndicator || !_scrollView.findBarVisible)
        return;
    NSMutableSet *drawn = [NSMutableSet set];
    for (NSValue *value in _textFinder.incrementalMatchRanges) {
        RSLabelFinderEntry *entry = [snapshot entryAtIndex:value.rangeValue.location];
        if (!entry || [drawn containsObject:entry])
            continue;
        [drawn addObject:entry];
        [NSTextFinder drawIncrementalMatchHighlightInRect:NSInsetRect(entry->_rect, -2, -1)];
    }
}

@end
