// Windowless checks of Debug-only Experimental menu actions on a real RSGraphView and
// GraphDocument (no NSWindow, no application delegate, no launch loop, no pasteboard):
// - Dotted Grid Lines is one undo step that marks the document edited, changes only the grids
//   that are shown, and is disabled (and ignored) while no grid is shown.
#import "GraphDocument.h"
#import "RSGraphView.h"
#import <GraphSketcherModel/RSGraph.h>
#import <GraphSketcherModel/RSGraphEditor.h>
#import <GraphSketcherModel/RSAxis.h>
#import <GraphSketcherModel/RSGrid.h>
#import <GraphSketcherModel/RSUndoer.h>
#import <OmniFoundation/OFController.h>

// check-experimental-actions.py drops the document types from the fixture's Info.plist.
@interface FixtureDocumentController : NSDocumentController
@end
@implementation FixtureDocumentController
- (id)makeUntitledDocumentOfType:(NSString *)typeName error:(NSError **)outError {
    return [[[GraphDocument alloc] initWithType:RSGraphFileType error:outError] autorelease];
}
@end
@interface FixtureGraphView : RSGraphView
- (void)useDocument:(GraphDocument *)document;
@end
@implementation FixtureGraphView
- (void)useDocument:(GraphDocument *)document { _document = document; }
@end

static void Check(BOOL condition, NSString *message) {
    if (!condition) [NSException raise:@"ExperimentalActionCheckFailure" format:@"%@", message];
}
// Lets the undo manager close the event's group, as the app's run loop would.
static void Drain(void) {
    __block BOOL finished = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ finished = YES; });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (!finished && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:deadline];
    Check(finished, @"Main queue did not drain");
}
static void ClearHistory(GraphDocument *document) {
    [document.undoer endRepetitiveUndo];
    Drain();
    [document.undoManager removeAllActions];
    [document updateChangeCount:NSChangeCleared];
    Check(!document.undoManager.canUndo && !document.isDocumentEdited, @"Fixture history cleared");
}
static GraphDocument *NewDocument(FixtureGraphView **outView) {
    NSError *error = nil;
    GraphDocument *document = [[[GraphDocument alloc] initWithType:RSGraphFileType error:&error] autorelease];
    Check(document != nil, error.description);
    Check(document.fileURL == nil, @"Fixture documents are untitled and never saved");
    FixtureGraphView *view = [[[FixtureGraphView alloc] initWithFrame:NSMakeRect(0, 0, 520, 420)] autorelease];
    [view useDocument:document];
    document.graphView = view;
    [view setRSSelector:document.selectorObject];
    view.editor = document.editor;
    Check(view.window == nil, @"The fixture view has no window");
    *outView = view;
    return document;
}
static NSString *GridState(RSGraph *graph) {
    return [NSString stringWithFormat:@"x shown %d dotted %d, y shown %d dotted %d", graph.xAxis.displayGrid, graph.xGrid.dotted, graph.yAxis.displayGrid, graph.yGrid.dotted];
}

static void CheckDottedGrid(void) {
    FixtureGraphView *view = nil;
    GraphDocument *document = NewDocument(&view);
    RSGraph *graph = document.graph;
    NSUndoManager *undo = document.undoManager;
    NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:@"Dotted Grid Lines" action:@selector(toggleDottedGrid:) keyEquivalent:@""] autorelease];

    // No grid shown: disabled, and a direct call changes nothing.
    graph.xAxis.displayGrid = NO; graph.yAxis.displayGrid = NO;
    graph.xGrid.dotted = NO; graph.yGrid.dotted = NO;
    ClearHistory(document);
    Check(![view validateMenuItem:item], @"Dotted Grid Lines is disabled while no grid is shown");
    [view toggleDottedGrid:item]; Drain();
    Check(!graph.xGrid.dotted && !graph.yGrid.dotted, [@"Hidden grids keep their style: " stringByAppendingString:GridState(graph)]);
    Check(!undo.canUndo && !document.isDocumentEdited, @"Toggling hidden grids registers no undo and leaves the document clean");
    puts("PASS dotted grid: disabled and ignored while no grid is shown");

    // Only the x grid shown: one undo step, document edited, the hidden y grid untouched.
    graph.xAxis.displayGrid = YES;
    ClearHistory(document);
    Check([view validateMenuItem:item] && item.state == NSControlStateValueOff, @"Enabled and unchecked with a solid grid shown");
    [view toggleDottedGrid:item]; Drain();
    Check(graph.xGrid.dotted && !graph.yGrid.dotted, [@"Only the shown grid becomes dotted: " stringByAppendingString:GridState(graph)]);
    Check(undo.canUndo && [undo.undoActionName isEqualToString:@"Change Grid Style"], [NSString stringWithFormat:@"One undo step named Change Grid Style, got %d '%@'", undo.canUndo, undo.undoActionName]);
    Check(document.isDocumentEdited, @"Dotted Grid Lines marks the document edited");
    Check([view validateMenuItem:item] && item.state == NSControlStateValueOn, @"Checked once the shown grid is dotted");
    [undo undo]; Drain();
    Check(!graph.xGrid.dotted && !graph.yGrid.dotted && !undo.canUndo && !document.isDocumentEdited, [@"One undo restores the solid grid and a clean document: " stringByAppendingString:GridState(graph)]);
    [undo redo]; Drain();
    Check(graph.xGrid.dotted && !graph.yGrid.dotted && document.isDocumentEdited, [@"Redo makes the grid dotted again: " stringByAppendingString:GridState(graph)]);
    puts("PASS dotted grid: one undo step named Change Grid Style, marks the document edited, undo and redo");

    // Both shown, only one dotted: the command makes both dotted in one step.
    graph.yAxis.displayGrid = YES;
    ClearHistory(document);
    Check([view validateMenuItem:item] && item.state == NSControlStateValueOff, @"Unchecked while some shown grid is solid");
    [view toggleDottedGrid:item]; Drain();
    Check(graph.xGrid.dotted && graph.yGrid.dotted, [@"Both shown grids dotted: " stringByAppendingString:GridState(graph)]);
    [undo undo]; Drain();
    Check(graph.xGrid.dotted && !graph.yGrid.dotted && !undo.canUndo, [@"One undo restores both grids: " stringByAppendingString:GridState(graph)]);
    puts("PASS dotted grid: both shown grids change together in one step");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool { @try {
        [(Class)NSBundle.mainBundle.principalClass sharedApplication];
        [[FixtureDocumentController alloc] init];
        Check([NSBundle.mainBundle.bundleIdentifier hasPrefix:@"com.graphink.experimentalactionchecks."], @"Unique fixture domain required");
        NSString *domain = NSBundle.mainBundle.bundleIdentifier;
        CFPreferencesSetAppValue(CFSTR("ExperimentalActionIsolationProbe"), (CFStringRef)domain, kCFPreferencesCurrentApplication);
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
        id probe = [(id)CFPreferencesCopyAppValue(CFSTR("ExperimentalActionIsolationProbe"), (CFStringRef)domain) autorelease];
        Check([probe isEqual:domain], @"Current-application defaults did not route to the unique fixture domain");
        OFController *lifecycle = OFController.sharedController;
        Check([lifecycle isKindOfClass:NSClassFromString(@"AppController")], @"OFControllerClass is the production AppController");
        [lifecycle didInitialize]; [lifecycle startedRunning];
        Check(NSApp.delegate == nil, @"Fixture must not install the application delegate");
        CheckDottedGrid();
        Check(NSApp.windows.count == 0, [NSString stringWithFormat:@"No window was created, found %@", NSApp.windows]);
        Check([lifecycle requestTermination] == OFControllerTerminateNow, @"Fixture lifecycle refused termination");
        [lifecycle willTerminate];
        puts("PASS experimental action checks: Dotted Grid Lines; windowless");
    } @catch (NSException *exception) {
        NSLog(@"FAIL experimental actions: %@", exception); return 1;
    } }
    return 0;
}
