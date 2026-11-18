// Phase-2 in-memory checks. No file-format decision, application nib or window.
#import <Cocoa/Cocoa.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniAppKit/OAFontDescriptor.h>
#import <GraphSketcherModel/RSGraph.h>
#import <GraphSketcherModel/RSGraphEditor.h>
#import <GraphSketcherModel/RSUndoer.h>
#import <GraphSketcherModel/RSUndoerOwner.h>
#import <GraphSketcherModel/RSTextLabel.h>
#import <GraphSketcherModel/RSVertex.h>
#import <GraphSketcherModel/RSConnectLine.h>
#import <GraphSketcherModel/RSFill.h>
#import <GraphSketcherModel/RSDataMapper.h>
#import <GraphSketcherModel/OFPreference-RSExtensions.h>
#import "RSStylePresets.h"
#import "RSSelector.h"
#import "RSMode.h"
#import "RSTextTool.h"
#import "RSDrawTool.h"
#import "RSFillTool.h"
#import "Inspectors/DataInspector.h"
#import "Inspectors/StyleInspector.h"

static void Check(BOOL value,NSString *reason) { if (!value) [NSException raise:@"CreationDefaultsFailure" format:@"%@",reason]; }
// Only mode context is simulated; production tools/inspectors and real model code run below.
@implementation RSMode
+ (RSMode *)sharedModeController { static RSMode *mode; if (!mode) mode=[[self alloc] init]; return mode; }
- (NSUInteger)mode { return _currentMode; }
- (void)registerClick:(NSUInteger)mode { _currentMode=mode; }
- (void)toolWasUsed:(NSUInteger)mode {}
- (BOOL)mouseDragging { return NO; }
@end
@interface GraphDocument : NSDocument <RSUndoerOwner>
@property(nonatomic,retain) RSGraphEditor *editor;
- (RSGraph *)graph;
- (RSUndoer *)undoer;
@end
@implementation GraphDocument
- (RSGraph *)graph { return self.editor.graph; }
- (RSUndoer *)undoer { return self.editor.undoer; }
- (void)undoerPerformedChange:(RSUndoer *)undoer { [self updateChangeCount:NSChangeDone]; }
- (void)dealloc { [_editor release]; [super dealloc]; }
@end
@interface MemoryView : NSView
@property(nonatomic,assign) GraphDocument *document;
@property(nonatomic,retain) RSSelector *selector;
- (RSGraphEditor *)editor;
- (RSGraph *)graph;
- (RSSelector *)RSSelector;
- (void)deselect;
- (void)setSelection:(id)object;
@end
@implementation MemoryView
- (RSGraphEditor *)editor { return self.document.editor; }
- (RSGraph *)graph { return self.document.graph; }
- (RSSelector *)RSSelector { return self.selector; }
- (void)deselect { [self.selector deselect]; }
- (void)setSelection:(id)object { [self.selector setSelection:object]; }
- (BOOL)wasEditingText { return NO; }
- (void)setWasEditingText:(BOOL)value {}
- (void)startEditingLabel {} // Observe the created attributed label without starting a field editor.
- (void)dealloc { [_selector release]; [super dealloc]; }
@end
@interface MemoryStyleInspector : StyleInspector @end
@implementation MemoryStyleInspector
- (void)updateKeyWindowAndFirstResponder:(id)sender {} // No fixture window or field editor.
@end
@interface DataInspector (CreationChecks)
- (void)tableView:(NSTableView *)table setObjectValue:(id)value forTableColumn:(NSTableColumn *)column row:(NSInteger)row;
@end
@interface RSDrawTool (CreationChecks)
- (BOOL)commitEditing;
@end
@interface RSFillTool (CreationChecks)
- (BOOL)commitEditing;
@end
@interface ColorSender : NSObject
@property(nonatomic,retain) NSColor *color;
@end
@implementation ColorSender
- (void)dealloc { [_color release]; [super dealloc]; }
@end
static GraphDocument *Document(void) {
    GraphDocument *doc=[[[GraphDocument alloc] init] autorelease]; doc.undoManager.groupsByEvent=NO;
    [doc.undoManager disableUndoRegistration];
    RSUndoer *undo=[[[RSUndoer alloc] initWithOwner:doc] autorelease];
    RSGraph *graph=[[[RSGraph alloc] initWithIdentifier:nil undoer:undo] autorelease]; [graph setupDefault];
    doc.editor=[[[RSGraphEditor alloc] initWithGraph:graph undoer:undo] autorelease];
    [doc.editor updateBounds:CGRectMake(0,0,520,340)];
    [doc.undoManager enableUndoRegistration]; [doc updateChangeCount:NSChangeCleared]; return doc;
}
static MemoryView *View(GraphDocument *document) {
    MemoryView *view=[[[MemoryView alloc] initWithFrame:NSMakeRect(0,0,520,340)] autorelease]; view.document=document;
    view.selector=[[[RSSelector alloc] initWithDocument:document] autorelease]; return view;
}
static RSTextLabel *Text(MemoryView *view) {
    RSTextTool *tool=[[[RSTextTool alloc] initWithView:(id)view] autorelease];
    [view.selector setHalfSelection:nil]; [tool mouseUp:nil];
    RSTextLabel *label=(id)view.selector.selection; Check([label isKindOfClass:RSTextLabel.class],@"Real Text tool creates a label"); return label;
}
static NSString *Face(RSTextLabel *label) { return [[label.attributedString attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL] fontName]; }
static BOOL Same(NSColor *a,NSColor *b) { return RSCreationDefaultsEqual(@{@"color":a},@{@"color":b}); }
int main(void) { @autoreleasepool { @try {
    OFController *controller=OFController.sharedController; [controller didInitialize]; [controller startedRunning];
    NSError *error=nil; Check(RSRegisterStyleFonts(NSBundle.mainBundle,&error),error.description);
    // AppKit lazily registers its built-in font names when inspectors initialize.
    (void)[NSFont userFontOfSize:0]; (void)[NSFont userFixedPitchFontOfSize:0];
    (void)[NSFont systemFontOfSize:0]; (void)[NSFont boldSystemFontOfSize:0];
    NSDictionary *preferences=[NSUserDefaults.standardUserDefaults.dictionaryRepresentation copy];
    NSDictionary *persistent=[[NSUserDefaults.standardUserDefaults persistentDomainForName:NSBundle.mainBundle.bundleIdentifier] copy];
    NSDictionary *global=[[NSUserDefaults.standardUserDefaults persistentDomainForName:NSGlobalDomain] copy];
    NSString *userFont=[[NSFont userFontOfSize:0].fontName copy];
    for (NSUInteger preset=0;preset<RSStylePresetNames().count;preset++) {
        GraphDocument *doc=Document(); MemoryView *view=View(doc),*secondView=View(doc);
        Check(!doc.graph.creationDefaults,@"Old/inactive graph has no local defaults");
        Check([doc.editor applyStylePreset:preset],@"Preset establishes concrete document values");
        NSDictionary *defaults=[[doc.graph.creationDefaults copy] autorelease];
        NSString *expected=(preset==1 || preset==2)?@"Kalam-Regular":@"HelveticaNeue";
        Check([defaults[@"font-name"] isEqual:expected],@"Concrete font face belongs to graph");
        Check(doc.isDocumentEdited,@"Saving actual creation values is a document edit");
        [doc.undoManager undo]; Check(!doc.graph.creationDefaults && !doc.isDocumentEdited,@"One undo restores absent defaults and clean state");
        [doc.undoManager disableUndoRegistration]; RSTextLabel *old=Text(view);
        Check(![Face(old) isEqual:@"Kalam-Regular"],@"Creation after undo follows old defaults"); [doc.graph removeLabel:old];
        [doc.undoManager enableUndoRegistration]; [doc.undoManager redo];
        Check(RSCreationDefaultsEqual(defaults,doc.graph.creationDefaults),@"Redo restores concrete defaults");
        [doc.undoManager removeAllActions]; [doc updateChangeCount:NSChangeCleared];
        Check(![doc.editor applyStylePreset:preset] && !doc.undoManager.canUndo && !doc.isDocumentEdited,@"Identical application has no undo/dirty effect");
        [doc.undoManager disableUndoRegistration];
        Check([Face(Text(view)) isEqual:expected],@"Exact manual repro: apply preset then actual Text tool uses its face");
        Check([Face(Text(secondView)) isEqual:expected],@"Two view contexts of one document consult the same graph values");
        RSDrawTool *pointTool=[[[RSDrawTool alloc] initWithView:(id)view] autorelease];
        [pointTool setValue:[pointTool valueForKey:@"newDrawVertex"] forKey:@"newDrawObject"]; // Supply hit-test result, not a UI event.
        [pointTool mouseDown:nil]; Check([pointTool commitEditing],@"Actual Draw click/commit creates a point");
        RSVertex *point=doc.graph.Vertices.lastObject;
        Check(Same(point.color,defaults[@"line-color"]),@"Actual Draw click accepts local point defaults");
        [view.selector setHalfSelection:point];
        RSTextTool *ownerTool=[[[RSTextTool alloc] initWithView:(id)view] autorelease]; [ownerTool mouseUp:nil];
        Check([Face(point.label) isEqual:expected],@"Actual Text owner-label route uses the document font");
        [view.selector setHalfSelection:nil];
        RSDrawTool *draw=[[[RSDrawTool alloc] initWithView:(id)view] autorelease];
        RSConnectLine *line=[draw valueForKey:@"lineInProgress"];
        Check(Same(line.color,defaults[@"line-color"]),@"Production Draw tool initial line uses document color");
        for (NSUInteger i=0;i<2;i++) {
            RSVertex *vertex=[[[RSVertex alloc] initWithGraph:doc.graph] autorelease];
            RSAcceptStyleCreationDefaults(vertex,NO); vertex.position=RSDataPointMake(i+1,i+2); [line addVertexAtEnd:vertex];
        }
        Check([draw commitEditing],@"Real Draw tool commits the line");
        Check(Same(((RSLine *)doc.graph.Lines.lastObject).color,defaults[@"line-color"]),@"Committed drawing keeps local color");
        RSFillTool *fillTool=[[[RSFillTool alloc] initWithView:(id)view] autorelease]; RSFill *fill=[fillTool valueForKey:@"fillInProgress"];
        for (NSArray *position in @[@[@1,@1],@[@3,@1],@[@2,@3]]) {
            RSVertex *vertex=[[[RSVertex alloc] initWithGraph:doc.graph] autorelease]; vertex.position=RSDataPointMake([position[0] doubleValue],[position[1] doubleValue]); [fill addVertexAtEnd:vertex];
        }
        Check([fillTool commitEditing] && Same(((RSFill *)doc.graph.Fills.lastObject).color,defaults[@"fill-color"]),@"Production Fill tool commits document color");
        DataInspector *data=[[[DataInspector alloc] initWithDictionary:@{@"identifier":@"Memory.Data"} inspectorRegistry:nil bundle:NSBundle.mainBundle] autorelease]; [data setValue:doc.graph forKey:@"graph"];
        NSUInteger row=doc.graph.Vertices.count; NSTableColumn *x=[[[NSTableColumn alloc] initWithIdentifier:@"positionx"] autorelease],*y=[[[NSTableColumn alloc] initWithIdentifier:@"positiony"] autorelease];
        [data tableView:nil setObjectValue:@"4" forTableColumn:x row:row]; [data tableView:nil setObjectValue:@"5" forTableColumn:y row:row];
        Check(Same(((RSVertex *)doc.graph.Vertices.lastObject).color,defaults[@"line-color"]),@"Actual Data table creation uses local values");
        MemoryStyleInspector *style=[[[MemoryStyleInspector alloc] initWithDictionary:@{@"identifier":@"Memory.Style"} inspectorRegistry:nil bundle:NSBundle.mainBundle] autorelease]; style.editor=doc.editor; [style setValue:view.selector forKey:@"s"];
        [view.selector deselect]; [[RSMode sharedModeController] registerClick:RS_text];
        ColorSender *sender=[[[ColorSender alloc] init] autorelease]; sender.color=NSColor.redColor; [style changeColor:sender];
        Check(Same(doc.graph.creationDefaults[@"text-color"],NSColor.redColor),@"No-selection production inspector changes local text default");
        RSTextLabel *explicit=Text(view); Check(Same(explicit.color,NSColor.redColor),@"Explicit color overrides preset for the next Text action");
        NSColor *otherColor=((RSVertex *)doc.graph.Vertices[0]).color;
        sender.color=NSColor.blackColor; [style changeColor:sender];
        Check(Same(explicit.color,NSColor.blackColor) && Same(((RSVertex *)doc.graph.Vertices[0]).color,otherColor),@"Explicit object edit preserves siblings");
        NSColor *p3Black=[NSColor colorWithDisplayP3Red:0 green:0 blue:0 alpha:1];
        [view.selector deselect]; sender.color=p3Black; [style changeColor:sender];
        Check([doc.graph.creationDefaults[@"text-color"] isEqual:p3Black],@"Actual inspector retains authored native P3 value");
        RSTextLabel *nativeText=Text(view);
        Check([nativeText.color isEqual:p3Black],@"Actual next Text preserves explicit P3 black rather than visually equal sRGB");
        RSSetLocalCreationValue(doc.graph,@"line-color",p3Black);
        RSDrawTool *nativeDraw=[[[RSDrawTool alloc] initWithView:(id)view] autorelease];
        Check([((RSVertex *)[nativeDraw valueForKey:@"newDrawVertex"]).color isEqual:p3Black],@"Draw default preserves native color space");
        NSColor *p3Fill=[p3Black colorWithAlphaComponent:.25];RSSetLocalCreationValue(doc.graph,@"fill-color",p3Fill);
        RSFillTool *nativeFill=[[[RSFillTool alloc] initWithView:(id)view] autorelease];
        Check([((RSFill *)[nativeFill valueForKey:@"fillInProgress"]).color isEqual:p3Fill],@"Fill default preserves native space and opacity");
        NSUInteger nativeRow=doc.graph.Vertices.count;
        [data tableView:nil setObjectValue:@"7" forTableColumn:x row:nativeRow];[data tableView:nil setObjectValue:@"8" forTableColumn:y row:nativeRow];
        Check([((RSVertex *)doc.graph.Vertices.lastObject).color isEqual:p3Black],@"Data creation preserves native space");
        RSSetLocalCreationValue(doc.graph,@"text-color",NSColor.blackColor);
        RSTextLabel *formatColor=Text(view); NSAttributedString *beforeColor=formatColor.attributedString;
        NSMutableAttributedString *colored=[[beforeColor mutableCopy] autorelease];
        [colored addAttribute:NSForegroundColorAttributeName value:p3Black range:NSMakeRange(0,colored.length)];
        RSRememberTextFormatting(doc.graph,beforeColor,colored);
        Check([doc.graph.creationDefaults[@"text-color"] isEqual:p3Black],@"Formatting remembers native P3 choice even when sRGB appearance matches");
        RSSetLocalCreationValue(doc.graph,@"font-name",@"Menlo-Bold");
        Check([Face(Text(view)) isEqual:@"Menlo-Bold"],@"Explicit face and native bold survive fresh creation");
        RSTextLabel *label=Text(view); NSAttributedString *before=label.attributedString;
        NSMutableAttributedString *formatted=[[before mutableCopy] autorelease];
        [formatted addAttribute:NSFontAttributeName value:[NSFont fontWithName:@"Georgia-Italic" size:17] range:NSMakeRange(0,formatted.length)];
        RSRememberTextFormatting(doc.graph,before,formatted);
        Check([Face(Text(view)) isEqual:@"Georgia-Italic"],@"Field-editor formatting seam remembers explicit face for subsequent Text");
        NSAttributedString *authored=[[[NSAttributedString alloc] initWithString:@"Explicit pasted text" attributes:@{NSFontAttributeName:[NSFont fontWithName:@"TimesNewRomanPS-ItalicMT" size:19],NSForegroundColorAttributeName:NSColor.blueColor}] autorelease];
        RSTextLabel *decoded=[[[RSTextLabel alloc] initWithGraph:doc.graph identifier:nil attributedString:authored position:RSDataPointMake(2,2) rotation:0] autorelease];
        RSTextLabel *copied=[[decoded copy] autorelease];
        Check([decoded.attributedString isEqualToAttributedString:authored] && [copied.attributedString isEqualToAttributedString:authored],@"Explicit decode/paste initializer and duplicate preserve authored attributes");
        GraphDocument *other=Document(); [other.editor applyStylePreset:preset==2?0:2]; [other.undoManager disableUndoRegistration];
        NSString *otherExpected=preset==2?@"HelveticaNeue":@"Kalam-Regular";
        Check([Face(Text(View(other))) isEqual:otherExpected] && [doc.graph.creationDefaults[@"font-name"] isEqual:@"Georgia-Italic"],@"Documents isolate defaults and explicit overrides");
        [other.editor invalidate];
        [doc.undoManager enableUndoRegistration]; [doc.undoer endRepetitiveUndo];
        [doc updateChangeCount:NSChangeCleared];
        NSDictionary *beforeDefaults=[[doc.graph.creationDefaults copy] autorelease];
        [doc.undoManager beginUndoGrouping]; RSSetLocalCreationValue(doc.graph,@"font-name",@"HelveticaNeue"); [doc.undoManager endUndoGrouping];
        Check(doc.isDocumentEdited,@"Explicit local default edit dirties document");
        [doc.undoManager undo]; Check(RSCreationDefaultsEqual(beforeDefaults,doc.graph.creationDefaults) && !doc.isDocumentEdited,@"Explicit local default undo restores values and clean state");
        [doc.undoManager redo]; Check([doc.graph.creationDefaults[@"font-name"] isEqual:@"HelveticaNeue"],@"Explicit local default redo restored");
        [doc.editor invalidate];
        NSDictionary *afterPrefs=NSUserDefaults.standardUserDefaults.dictionaryRepresentation;
        Check([preferences isEqual:afterPrefs],@"No preference values change after lazy framework font registration");
        Check([persistent?:@{} isEqual:[NSUserDefaults.standardUserDefaults persistentDomainForName:NSBundle.mainBundle.bundleIdentifier]?:@{}],@"No persisted app preference mutation");
        Check([global?:@{} isEqual:[NSUserDefaults.standardUserDefaults persistentDomainForName:NSGlobalDomain]?:@{}],@"No global preference mutation");
        Check([userFont isEqual:[NSFont userFontOfSize:0].fontName],@"No process user-font mutation");
        printf("PASS memory %s actual Text/Draw/Fill/Data/Style routes, two views/documents, explicit overrides, undo/redo/no-op\n",[RSStylePresetNames()[preset] UTF8String]);
    }
    [preferences release]; [persistent release]; [global release]; [userFont release]; Check([controller requestTermination]==OFControllerTerminateNow,@"Headless termination"); [controller willTerminate];
    printf("PASS document creation defaults in memory; persistence and UI deliberately untested\n"); return 0;
} @catch(NSException *exception) { NSLog(@"FAIL %@",exception); return 1; } } }
