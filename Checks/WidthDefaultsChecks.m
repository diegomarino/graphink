// Production model regression; isolated preferences, no app window or field editor.
#import <Cocoa/Cocoa.h>
#import <OmniFoundation/OmniFoundation.h>
#import <GraphSketcherModel/RSGraph.h>
#import <GraphSketcherModel/RSGraphEditor.h>
#import <GraphSketcherModel/RSUndoer.h>
#import <GraphSketcherModel/RSUndoerOwner.h>
#import <GraphSketcherModel/RSVertex.h>
#import <GraphSketcherModel/RSConnectLine.h>
#import <GraphSketcherModel/RSGroup.h>
#import <GraphSketcherModel/RSUnknown.h>

static void Check(BOOL value, NSString *reason) {
    if (!value) [NSException raise:@"WidthDefaultsFailure" format:@"%@", reason];
}
@interface WidthDocument : NSDocument <RSUndoerOwner>
@property(nonatomic, retain) RSGraphEditor *editor;
@end
@implementation WidthDocument
- (void)undoerPerformedChange:(RSUndoer *)undoer {}
- (void)dealloc { [_editor invalidate]; [_editor release]; [super dealloc]; }
@end
static WidthDocument *Document(void) {
    WidthDocument *doc = [[[WidthDocument alloc] init] autorelease];
    doc.undoManager.groupsByEvent = NO;
    [doc.undoManager disableUndoRegistration];
    RSUndoer *undoer = [[[RSUndoer alloc] initWithOwner:doc] autorelease];
    RSGraph *graph = [[[RSGraph alloc] initWithIdentifier:nil undoer:undoer] autorelease];
    [graph setupDefault];
    doc.editor = [[[RSGraphEditor alloc] initWithGraph:graph undoer:undoer] autorelease];
    [doc.undoManager enableUndoRegistration];
    return doc;
}
static RSGroup *Group(RSGraph *graph, NSArray *elements) {
    return [[[RSGroup alloc] initWithGraph:graph byCopyingArray:elements] autorelease];
}
static NSDictionary *Domain(NSString *name) {
    return [NSUserDefaults.standardUserDefaults persistentDomainForName:name] ?: @{};
}
static void Unchanged(NSDictionary *before, NSDictionary *global) {
    Check([before isEqual:Domain(NSBundle.mainBundle.bundleIdentifier)], @"Selected thickness must preserve the complete persistent app domain");
    Check([global isEqual:Domain(NSGlobalDomain)], @"Selected thickness must preserve the persistent global domain");
    Check([[OFPreferenceWrapper sharedPreferenceWrapper] floatForKey:@"DefaultLineWidth"] == 10, @"Creation width remains 10");
}
int main(void) { @autoreleasepool { @try {
    OFController *controller = OFController.sharedController;
    [controller didInitialize]; [controller startedRunning];
    OFPreferenceWrapper *preferences = [OFPreferenceWrapper sharedPreferenceWrapper];
    [preferences setDouble:10 forKey:@"DefaultLineWidth"];
    [preferences setInteger:3 forKey:@"DefaultVertexShape"];
    [preferences setInteger:2 forKey:@"DefaultDashStyle"];
    [NSUserDefaults.standardUserDefaults setObject:@"Dark" forKey:@"AppleInterfaceStyle"];
    NSDictionary *before = [[Domain(NSBundle.mainBundle.bundleIdentifier) copy] autorelease];
    NSDictionary *global = [[Domain(NSGlobalDomain) copy] autorelease];
    WidthDocument *a = Document(), *b = Document();
    [a.undoManager disableUndoRegistration];
    RSVertex *a1 = [[[RSVertex alloc] initWithGraph:a.editor.graph] autorelease];
    RSVertex *a2 = [[[RSVertex alloc] initWithGraph:a.editor.graph] autorelease];
    RSConnectLine *line = [[[RSConnectLine alloc] initWithGraph:a.editor.graph vertices:Group(a.editor.graph, @[a1,a2])] autorelease];
    [a.undoManager enableUndoRegistration];
    RSVertex *other = [[[RSVertex alloc] initWithGraph:b.editor.graph] autorelease];
    for (RSGraphElement *object in @[line, a1, Group(a.editor.graph, @[line,a1])]) {
        [a.undoManager beginUndoGrouping];
        [a.editor setWidth:4.09 forElement:object snapDistanceToNearestInteger:YES];
        [a.undoManager endUndoGrouping]; [a.editor.undoer endRepetitiveUndo];
        Check(object.width == 4, @"Slider snaps selected thickness to 0.2");
        Unchanged(before, global);
        Check(other.width == 10, @"Editing A preserves B's existing point");
        Check([[[RSVertex alloc] initWithGraph:b.editor.graph] autorelease].width == 10, @"New point in B retains the app default");
        Check([[[RSConnectLine alloc] initWithGraph:a.editor.graph vertices:Group(a.editor.graph, @[a1,a2])] autorelease].width == 10, @"New line in A retains the app default");
        [a.undoManager undo]; Check(object.width == 10, @"Undo restores selected thickness"); Unchanged(before, global);
        [a.undoManager redo]; Check(object.width == 4, @"Redo restores selected thickness"); Unchanged(before, global);
        [a.undoManager undo]; [a.undoManager removeAllActions];
    }
    [a.undoManager beginUndoGrouping];
    [a.editor setWidth:4.375 forElement:line snapDistanceToNearestInteger:NO];
    [a.undoManager endUndoGrouping]; [a.editor.undoer endRepetitiveUndo];
    Check(line.width == 4.375, @"Typed thickness is not rounded"); Unchanged(before, global);
    [a.undoManager undo]; Check(line.width == 10, @"Typed thickness undo restores the line"); Unchanged(before, global);
    [a.undoManager removeAllActions];
    // The no-selection inspector deliberately configures future creation globally.
    RSUnknown *none = [[[RSUnknown alloc] init] autorelease];
    [a.editor setWidth:6.25 forElement:none snapDistanceToNearestInteger:NO];
    Check(none.width == 6.25 && [preferences floatForKey:@"DefaultLineWidth"] == 6.25, @"No-selection thickness still explicitly changes the creation default");
    NSMutableDictionary *expected = [[before mutableCopy] autorelease]; expected[@"DefaultLineWidth"] = @6.25;
    Check([expected isEqual:Domain(NSBundle.mainBundle.bundleIdentifier)], @"Explicit default setting changes only DefaultLineWidth");
    Check([global isEqual:Domain(NSGlobalDomain)], @"Explicit app default preserves global appearance/font preferences");
    Check(!a.undoManager.canUndo, @"No-selection default does not enter document undo");
    Check([[[RSVertex alloc] initWithGraph:b.editor.graph] autorelease].width == 6.25, @"Explicit app default applies to future creation in B");
    Check(other.width == 10 && line.width == 10, @"Explicit app default preserves existing objects in both documents");
    puts("PASS width defaults: line/vertex/group edits, snapping, undo/redo, two documents, persistent-domain equality and explicit no-selection defaults");
    Check([controller requestTermination] == OFControllerTerminateNow, @"Fixture termination"); [controller willTerminate];
    return 0;
} @catch (NSException *exception) { fprintf(stderr, "FAIL %s\n", exception.description.UTF8String); [OFController.sharedController requestTermination]; [OFController.sharedController willTerminate]; return 1; } } }
