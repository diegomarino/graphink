// Offscreen key view loop checks: Tab and Shift-Tab through a nib-loaded production document
// window (toolbar, canvas, status bar zoom popup, sidebar) for every sidebar section.
// No application delegate, launch loop or visible window.
#import "GraphDocument.h"
#import "GraphWindowController.h"
#import "RSGraphView.h"
#import "RSInspectorSidebar.h"
#import <OmniFoundation/OFController.h>
#import <objc/runtime.h>

@interface GraphWindowController (KeyLoopChecks)
- (RSInspectorSidebar *)inspectorSidebar;
@end

@interface FixtureDocumentController : NSDocumentController
@end
@implementation FixtureDocumentController
- (id)makeUntitledDocumentOfType:(NSString *)typeName error:(NSError **)outError {
    return [[[GraphDocument alloc] initWithType:RSGraphFileType error:outError] autorelease];
}
@end
static void Check(BOOL condition, NSString *message) {
    if (!condition) [NSException raise:@"KeyLoopCheckFailure" format:@"%@", message];
}
static void Drain(void) {
    __block BOOL finished = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ finished = YES; });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (!finished && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:deadline];
    Check(finished, @"Main queue did not drain");
}
static const NSRect Screen = {{0, 0}, {1440, 875}};
static NSArray *SectionNames(void) { return @[@"Style", @"Axes", @"Canvas", @"Data"]; }
static BOOL FullKeyboardAccess;
// System Settings ▸ Keyboard ▸ Keyboard navigation. AppKit reads it from the user's global
// preferences, which a check must not change, so "on" adds what that setting adds: any visible
// control (buttons, popups, sliders, color wells; not scrollers) that accepts first responder becomes a key view. AppKit's own -canBecomeKeyView still
// decides first, and the loop itself (order, recalculation, Tab handling) is entirely AppKit's.
static void EmulateKeyboardNavigation(void) {
    Method method = class_getInstanceMethod(NSView.class, @selector(canBecomeKeyView));
    BOOL (*original)(id, SEL) = (void *)method_getImplementation(method);
    method_setImplementation(method, imp_implementationWithBlock(^BOOL(NSView *view) {
        return original(view, @selector(canBecomeKeyView)) || ([view isKindOfClass:NSControl.class] && ![view isKindOfClass:NSScroller.class] && view.window != nil && !view.isHiddenOrHasHiddenAncestor && view.acceptsFirstResponder);
    }));
}

static GraphWindowController *OpenWindow(GraphDocument *document) {
    [(NSDocumentController *)NSDocumentController.sharedDocumentController addDocument:document];
    [document makeWindowControllers];
    GraphWindowController *owner = document.windowControllers.firstObject;
    Check(owner.window != nil && !owner.window.visible, @"Nib window loaded and not shown");
    [owner chooseInitialWindowFrameInVisibleFrame:Screen];
    // The app inspects the main window's graph; this window is never main, so inspect it directly.
    [owner refreshInspectors];
    Drain(); [document.undoManager removeAllActions]; [document updateChangeCount:NSChangeCleared];
    return owner;
}
static void ClearFrameKeys(void) {
    for (NSString *key in @[@"LastFrameString", @"LastCanvasSize"]) [[OFPreferenceWrapper sharedPreferenceWrapper] removeObjectForKey:key];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"NSWindow Frame RSGraphDocumentWindow"];
}

// The control that owns keyboard focus: a text field while its field editor is first responder.
static NSView *Focused(NSWindow *window) {
    NSResponder *responder = window.firstResponder;
    if ([responder isKindOfClass:NSTextView.class] && ((NSTextView *)responder).isFieldEditor && [(id)((NSTextView *)responder).delegate isKindOfClass:NSView.class])
        return (NSView *)((NSTextView *)responder).delegate;
    return [responder isKindOfClass:NSView.class] ? (NSView *)responder : nil;
}
static NSString *Describe(NSView *view) {
    if (!view) return @"(no focus)";
    NSString *label = view.accessibilityLabel ?: ([view respondsToSelector:@selector(title)] ? [(id)view title] : nil);
    if ([view isKindOfClass:NSPopUpButton.class]) label = label.length ? label : ((NSPopUpButton *)view).titleOfSelectedItem;
    if (!label.length && [view respondsToSelector:@selector(toolTip)]) label = view.toolTip;
    return [NSString stringWithFormat:@"%@ '%@' %@", view.className, label ?: @"", NSStringFromRect([view convertRect:view.bounds toView:nil])];
}
// One Tab or Shift-Tab. A field editor and the canvas handle Tab themselves (end editing; walk a
// selection's labels), so they get the real key event. Every other control leaves Tab to NSWindow's
// keyboard UI, which only runs for the key window; this window is never shown, so the fixture asks
// NSWindow for that same move directly.
static void Press(NSWindow *window, BOOL shift) {
    NSResponder *responder = window.firstResponder;
    if (([responder isKindOfClass:NSTextView.class] && ((NSTextView *)responder).isFieldEditor) || [responder isKindOfClass:RSGraphView.class]) {
        NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:shift ? NSEventModifierFlagShift : 0 timestamp:0 windowNumber:window.windowNumber context:nil characters:shift ? @"\x19" : @"\t" charactersIgnoringModifiers:shift ? @"\x19" : @"\t" isARepeat:NO keyCode:48];
        [window sendEvent:event];
    } else if (shift) {
        [window selectPreviousKeyView:nil];
    } else {
        [window selectNextKeyView:nil];
    }
    Drain();
}
// Presses Tab (or Shift-Tab) until focus returns to the start; returns the focus after each press.
static NSArray<NSView *> *Walk(NSWindow *window, NSView *start, BOOL shift, NSUInteger limit, NSString *what) {
    Check([window makeFirstResponder:start] && Focused(window) == start, [NSString stringWithFormat:@"%@: %@ takes focus", what, Describe(start)]);
    NSMutableArray *sequence = [NSMutableArray array];
    for (NSUInteger press = 0; press < limit; press++) {
        Press(window, shift);
        NSView *focused = Focused(window);
        Check(focused != nil, [NSString stringWithFormat:@"%@: press %lu leaves no focused control (first responder %@) after %@", what, (unsigned long)press + 1, window.firstResponder.className, sequence.count ? Describe(sequence.lastObject) : Describe(start)]);
        if (focused == start) return sequence;
        if ([sequence containsObject:focused]) {
            NSMutableArray *names = [NSMutableArray array];
            for (NSView *view in sequence) [names addObject:Describe(view)];
            Check(NO, [NSString stringWithFormat:@"%@: press %lu returns to %@ before the start; the loop is trapped after %@", what, (unsigned long)press + 1, Describe(focused), [names componentsJoinedByString:@" -> "]]);
        }
        [sequence addObject:focused];
    }
    NSMutableArray *names = [NSMutableArray array];
    for (NSView *view in sequence) [names addObject:Describe(view)];
    Check(NO, [NSString stringWithFormat:@"%@: focus did not come back to the start within %lu presses: %@", what, (unsigned long)limit, [names componentsJoinedByString:@" -> "]]);
    return nil;
}
static BOOL Inside(NSView *view, NSView *ancestor) { return view == ancestor || [view isDescendantOf:ancestor]; }
// Reading order in window coordinates: top to bottom, then left to right within a row.
static BOOL ReadsBefore(NSView *a, NSView *b) {
    NSRect ra = [a convertRect:a.bounds toView:nil], rb = [b convertRect:b.bounds toView:nil];
    BOOL sameRow = NSMinY(ra) < NSMaxY(rb) && NSMinY(rb) < NSMaxY(ra);
    return sameRow ? NSMinX(ra) <= NSMinX(rb) : NSMaxY(ra) > NSMaxY(rb);
}
// Every control a keyboard user can reach in the visible sidebar.
static void CollectKeyViews(NSView *view, NSMutableArray *into) {
    if (view.hidden) return;
    if (view.canBecomeKeyView) [into addObject:view];
    for (NSView *subview in view.subviews) CollectKeyViews(subview, into);
}

static void CheckSection(GraphWindowController *owner, NSUInteger section, NSString *context) {
    NSWindow *window = owner.window;
    NSString *what = [NSString stringWithFormat:@"%@ %@", SectionNames()[section], context];
    RSInspectorSidebar *sidebar = [owner inspectorSidebar];
    Check([sidebar selectSection:section] && sidebar.selectedSection == section, [what stringByAppendingString:@": section selected"]);
    Drain();
    NSView *sidebarView = sidebar.view;
    NSView *graphView = [owner valueForKey:@"_graphView"];
    NSPopUpButton *zoom = [owner valueForKey:@"_viewportZoom"];
    NSMutableArray<NSView *> *reachable = [NSMutableArray array];
    CollectKeyViews(sidebarView, reachable);
    Check(reachable.count > 0, [what stringByAppendingString:@": the sidebar has keyboard-reachable controls"]);
    // Canvas starts in Width, as the checklist does; the other sections start in their first control.
    NSView *start = section == 2 ? [[sidebar tabWithIdentifier:@"com.graphsketcher.GraphSketcher.inspector.document"].inspector valueForKey:@"canvasWidth"] : graphView;
    Check(Inside(start, window.contentView) && start.canBecomeKeyView, [what stringByAppendingString:@": the start control is in the window"]);
    if (section == 2) Check([start isKindOfClass:NSTextField.class] && ((NSTextField *)start).isEnabled, [what stringByAppendingString:@": the Width field is enabled"]);
    NSUInteger limit = reachable.count + 40;
    NSArray<NSView *> *forward = Walk(window, start, NO, limit, [what stringByAppendingString:@" Tab"]);
    NSArray<NSView *> *backward = Walk(window, start, YES, limit, [what stringByAppendingString:@" Shift-Tab"]);
    NSMutableArray *names = [NSMutableArray arrayWithObject:Describe(start)];
    for (NSView *view in forward) [names addObject:Describe(view)];
    NSLog(@"%@ Tab sequence (%lu presses back to the start):\n  %@", what, (unsigned long)forward.count + 1, [names componentsJoinedByString:@"\n  "]);
    // Shift-Tab is the same loop backwards.
    Check([backward isEqual:forward.reverseObjectEnumerator.allObjects], [NSString stringWithFormat:@"%@: Shift-Tab walks the Tab loop backwards (%lu vs %lu stops)", what, (unsigned long)backward.count, (unsigned long)forward.count]);
    NSMutableArray<NSView *> *loop = [NSMutableArray arrayWithObject:start];
    [loop addObjectsFromArray:forward];
    // The canvas and the status bar zoom popup are stops of the loop, so focus also leaves the canvas.
    Check([loop containsObject:graphView], [what stringByAppendingString:@": the canvas is in the loop"]);
    if (FullKeyboardAccess)
        Check([loop containsObject:zoom], [what stringByAppendingString:@": Tab and Shift-Tab reach the Canvas zoom popup"]);
    // Every reachable sidebar control is a stop, once, and nothing from a hidden section is.
    for (NSView *view in reachable)
        Check([loop containsObject:view], [NSString stringWithFormat:@"%@: Tab never reaches %@", what, Describe(view)]);
    NSMutableArray<NSView *> *sidebarStops = [NSMutableArray array];
    for (NSView *view in loop) {
        Check(Inside(view, window.contentView) || [view isDescendantOf:window.contentView.superview], [NSString stringWithFormat:@"%@: %@ is not in the window", what, Describe(view)]);
        if (Inside(view, sidebarView)) {
            Check([reachable containsObject:view], [NSString stringWithFormat:@"%@: %@ is hidden or belongs to another section", what, Describe(view)]);
            [sidebarStops addObject:view];
        }
    }
    // The sidebar is one run of the loop (no excursions to the canvas or toolbar halfway down), in reading order.
    NSUInteger first = [loop indexOfObject:sidebarStops.firstObject];
    NSArray *rotated = [[loop subarrayWithRange:NSMakeRange(first, loop.count - first)] arrayByAddingObjectsFromArray:[loop subarrayWithRange:NSMakeRange(0, first)]];
    NSUInteger topIndex = 0;
    for (NSUInteger index = 1; index < sidebarStops.count; index++)
        if (ReadsBefore(sidebarStops[index], sidebarStops[topIndex])) topIndex = index;
    NSView *top = sidebarStops[topIndex];
    NSUInteger topAt = [rotated indexOfObject:top];
    rotated = [[rotated subarrayWithRange:NSMakeRange(topAt, rotated.count - topAt)] arrayByAddingObjectsFromArray:[rotated subarrayWithRange:NSMakeRange(0, topAt)]];
    for (NSUInteger index = 0; index < sidebarStops.count; index++)
        Check(Inside(rotated[index], sidebarView), [NSString stringWithFormat:@"%@: the sidebar is interrupted by %@ after %@", what, Describe(rotated[index]), Describe(index ? rotated[index - 1] : top)]);
    for (NSUInteger index = 1; index < sidebarStops.count; index++)
        Check(ReadsBefore(rotated[index - 1], rotated[index]), [NSString stringWithFormat:@"%@: %@ comes before %@, against reading order", what, Describe(rotated[index - 1]), Describe(rotated[index])]);
    if (section == 2)
        Check(Inside(forward.firstObject, sidebarView) && ReadsBefore(start, forward.firstObject), [what stringByAppendingString:@": Tab from Width goes to the next sidebar control below or beside it"]);
    NSLog(@"PASS %@: %lu stops, %lu sidebar controls in reading order, canvas%@ in the loop, Shift-Tab reverses it", what, (unsigned long)loop.count, (unsigned long)sidebarStops.count, FullKeyboardAccess ? @" and zoom popup" : @"");
}

static void CheckKeyLoops(void) {
    ClearFrameKeys();
    NSError *error = nil;
    GraphDocument *document = [[[GraphDocument alloc] initWithType:RSGraphFileType error:&error] autorelease];
    Check(document != nil, error.description);
    GraphWindowController *owner = OpenWindow(document);
    NSPopUpButton *zoom = [owner valueForKey:@"_viewportZoom"];
    Check(zoom.canBecomeKeyView == FullKeyboardAccess, [NSString stringWithFormat:@"Keyboard navigation %@ in this process (zoom popup canBecomeKeyView %d)", FullKeyboardAccess ? @"on" : @"off", zoom.canBecomeKeyView]);
    // The checklist path: a blank document, sidebar Canvas tab first; then every tab, and back after switching.
    CheckSection(owner, 2, @"(blank document)");
    for (NSUInteger section = 0; section < 4; section++) CheckSection(owner, section, @"(after switching)");
    CheckSection(owner, 2, @"(back to Canvas)");
    // Ending editing by Tab must not change the graph (the axis range fields used to fix the range).
    Check(!document.isDocumentEdited && !document.undoManager.canUndo, @"Tabbing through the window left the document unchanged");
    [document close];
    ClearFrameKeys();
    printf("PASS key view loops with keyboard navigation %s\n", FullKeyboardAccess ? "on" : "off");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool { @try {
        [(Class)NSBundle.mainBundle.principalClass sharedApplication];
        [[FixtureDocumentController alloc] init];
        Check([NSBundle.mainBundle.bundleIdentifier hasPrefix:@"com.graphink.keyloopchecks."], @"Unique fixture domain required");
        NSString *domain = NSBundle.mainBundle.bundleIdentifier;
        CFPreferencesSetAppValue(CFSTR("KeyLoopIsolationProbe"), (CFStringRef)domain, kCFPreferencesCurrentApplication);
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
        id probe = [(id)CFPreferencesCopyAppValue(CFSTR("KeyLoopIsolationProbe"), (CFStringRef)domain) autorelease];
        Check([probe isEqual:domain], @"Current-application defaults did not route to the unique fixture domain");
        OFController *lifecycle = OFController.sharedController;
        Check([lifecycle isKindOfClass:NSClassFromString(@"AppController")], @"OFControllerClass is the production AppController");
        [lifecycle didInitialize]; [lifecycle startedRunning];
        // Embedded inspectors ask the application delegate for their window; the production AppController
        // answers, as in the app. NSApplication never finishes launching here, so no launch handler runs.
        Check(NSApp.delegate == nil, @"No application delegate before the fixture sets one");
        NSApp.delegate = (id <NSApplicationDelegate>)lifecycle;
        Check(argc >= 2 && (!strcmp(argv[1], "on") || !strcmp(argv[1], "off")), @"Pass on or off for Keyboard navigation");
        Check(!NSApp.isFullKeyboardAccessEnabled, @"Keyboard navigation is off in this session; the fixture provides on itself");
        FullKeyboardAccess = !strcmp(argv[1], "on");
        if (FullKeyboardAccess) EmulateKeyboardNavigation();
        CheckKeyLoops();
        Check([lifecycle requestTermination] == OFControllerTerminateNow, @"Fixture lifecycle refused termination");
        [lifecycle willTerminate];
        puts("PASS key loop checks; offscreen only");
    } @catch (NSException *exception) {
        NSLog(@"FAIL key loop: %@", exception); return 1;
    } }
    return 0;
}
