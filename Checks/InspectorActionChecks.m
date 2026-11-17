// Production inspector action routing with offscreen windows; no panels open.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "../GraphSketcher/App/Inspectors/DocumentInspector.h"
#import "../GraphSketcher/App/Inspectors/AxisInspector.h"
#import "../GraphSketcher/App/Inspectors/StyleInspector.h"

@interface RSMode : NSObject
@end
@implementation RSMode
@end

@interface GraphDocument : NSDocument
@property(nonatomic, assign) id graphView;
@end
@implementation GraphDocument
@end

@interface RSGraphView : NSView
@property(nonatomic) NSUInteger fontChanges;
@end
@implementation RSGraphView
- (BOOL)acceptsFirstResponder { return YES; }
- (void)changeFont:(id)sender { _fontChanges++; }
@end

@interface ActionWindow : NSWindow
@property(nonatomic) BOOL refusesCommit;
@end
@implementation ActionWindow
- (BOOL)makeFirstResponder:(NSResponder *)responder { return !_refusesCommit && [super makeFirstResponder:responder]; }
@end

@interface ActionApplication : NSApplication
@property(nonatomic, assign) NSWindow *actionWindow;
@end
@implementation ActionApplication
- (NSWindow *)mainWindow { return _actionWindow ?: [super mainWindow]; }
- (NSWindow *)keyWindow { return _actionWindow ?: [super keyWindow]; }
@end

@interface ActionGraph : NSObject
@property(nonatomic) NSUInteger backgroundChanges;
@property(nonatomic) NSUInteger gridChanges;
@end
@implementation ActionGraph
- (void)setBackgroundColor:(NSColor *)color { _backgroundChanges++; }
- (NSColor *)gridColor { return [NSColor grayColor]; }
- (void)setGridColor:(NSColor *)color { _gridChanges++; }
- (void)displayGridIfNotAlready {}
@end

@interface ActionSelector : NSObject
@property(nonatomic, assign) GraphDocument *document;
@end
@implementation ActionSelector
- (BOOL)selected { return YES; }
- (id)undoer { return self; }
- (void)registerRepetitiveUndoWithObject:(id)object action:(NSString *)action state:(id)state name:(NSString *)name {}
- (void)sendChange:(id)sender {}
@end

@interface CanvasActionInspector : DocumentInspector
- (void)useGraph:(id)graph;
@end
@implementation CanvasActionInspector
- (void)useGraph:(id)graph { _graph = graph; }
- (void)loadView { self.view = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 240, 398)] autorelease]; }
- (void)updateDisplay {}
@end

@interface AxisActionInspector : AxisInspector
- (void)useGraph:(id)graph selector:(id)selector;
@end
@implementation AxisActionInspector
- (void)useGraph:(id)graph selector:(id)selector { _graph = graph; _s = selector; }
- (void)loadView { self.view = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 240, 559)] autorelease]; }
- (void)updateDisplay {}
@end

@interface StyleActionInspector : StyleInspector
- (void)useSelector:(id)selector;
@end
@implementation StyleActionInspector
- (void)useSelector:(id)selector { _s = selector; }
- (void)loadView { self.view = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 240, 449)] autorelease]; }
- (void)updateDisplay {}
@end

static id FontActionTarget;
static void CaptureFontAction(id manager, SEL selector, id sender) {
    NSApplication *application = [NSApplication sharedApplication];
    FontActionTarget = [application targetForAction:@selector(changeFont:)];
    if ([FontActionTarget isKindOfClass:[RSGraphView class]])
        [application sendAction:@selector(changeFont:) to:nil from:manager];
}

int main(void) {
    @autoreleasepool {
        ActionApplication *app = (id)[ActionApplication sharedApplication];
        Method panel = class_getInstanceMethod([NSFontManager class], @selector(orderFrontFontPanel:));
        IMP originalPanel = method_setImplementation(panel, (IMP)CaptureFontAction);
        NSMutableArray *graphs = [NSMutableArray array];
        for (NSUInteger index = 0; index < 2; index++) {
            ActionWindow *window = [[[ActionWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 600) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES] autorelease];
            app.actionWindow = window;
            GraphDocument *document = [[[GraphDocument alloc] init] autorelease];
            RSGraphView *graphView = [[[RSGraphView alloc] initWithFrame:NSMakeRect(0, 0, 240, 420)] autorelease];
            [graphs addObject:graphView];
            document.graphView = graphView;
            [window.contentView addSubview:graphView];
            NSTextField *field = [[[NSTextField alloc] initWithFrame:NSMakeRect(260, 100, 100, 24)] autorelease];
            NSColorWell *well = [[[NSColorWell alloc] initWithFrame:NSMakeRect(260, 150, 40, 24)] autorelease];
            [window.contentView addSubview:field];
            [window.contentView addSubview:well];
            ActionGraph *graph = [[[ActionGraph alloc] init] autorelease];
            ActionSelector *selection = [[[ActionSelector alloc] init] autorelease];
            selection.document = document;
            NSDictionary *definition = @{@"identifier": @"action-checks"};
            id registry = [[[NSObject alloc] init] autorelease];
            CanvasActionInspector *canvas = [[[CanvasActionInspector alloc] initWithDictionary:definition inspectorRegistry:registry bundle:[NSBundle mainBundle]] autorelease];
            canvas.document = document;
            canvas.backgroundColorWell = well;
            [canvas useGraph:graph];
            AxisActionInspector *axes = [[[AxisActionInspector alloc] initWithDictionary:definition inspectorRegistry:registry bundle:[NSBundle mainBundle]] autorelease];
            axes.document = document;
            axes.gridColorWell = well;
            [axes useGraph:graph selector:selection];
            StyleActionInspector *style = [[[StyleActionInspector alloc] initWithDictionary:definition inspectorRegistry:registry bundle:[NSBundle mainBundle]] autorelease];
            [style useSelector:selection];
            for (id inspector in @[canvas, axes, style]) [window.contentView addSubview:[inspector view]];
            NSCAssert([window makeFirstResponder:field], @"Field focus failed");
            [canvas changeBackgroundColor:well];
            NSCAssert(graph.backgroundChanges == 1, @"Canvas color rejected an owned sidebar field");
            NSCAssert([window makeFirstResponder:window], @"Window focus failed");
            [axes changeGridColor:well];
            NSCAssert(graph.gridChanges == 1, @"Axes color rejected the sidebar commit transition");
            NSCAssert([window makeFirstResponder:field], @"Field focus failed");
            window.refusesCommit = YES;
            [canvas changeBackgroundColor:well];
            [axes changeGridColor:well];
            FontActionTarget = nil;
            [style showFontPicker:field];
            NSCAssert(graph.backgroundChanges == 1 && graph.gridChanges == 1 && FontActionTarget == nil, @"Inspector action ignored rejected validation");
            window.refusesCommit = NO;
            [style showFontPicker:field];
            NSCAssert(FontActionTarget == graphView && graphView.fontChanges == 1, @"Style font action did not reach its owning graph after committing a field");
            NSCAssert([window makeFirstResponder:window], @"Window focus failed");
            [style showFontPicker:field];
            NSCAssert(FontActionTarget == graphView && graphView.fontChanges == 2, @"Style font action lost target after section commit");
        }
        NSCAssert([(RSGraphView *)graphs.firstObject fontChanges] == 2, @"Second inspector's font action reached the first graph");
        method_setImplementation(panel, originalPanel);
        puts("PASS inspector actions: owned Canvas/Axes colors, field/window font routing, refused validation and two-window isolation; no panels opened");
    }
    return 0;
}
