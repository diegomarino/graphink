#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>
#import <OmniFoundation/OmniFoundation.h>
#import <GraphSketcherModel/RSGraph.h>
#import <GraphSketcherModel/RSGraphArchive.h>
#import <GraphSketcherModel/RSUndoer.h>
#import <GraphSketcherModel/RSUndoerOwner.h>
#import <GraphSketcherModel/RSGraphRenderer.h>
#import <GraphSketcherModel/RSDataMapper.h>
#import <GraphSketcherModel/RSConnectLine.h>
#import <GraphSketcherModel/RSVertex.h>
#import <GraphSketcherModel/RSGrid.h>
#import <GraphSketcherModel/RSGroup.h>
#import <GraphSketcherModel/RSFill.h>
#import <GraphSketcherModel/RSTextLabel.h>
#import "RSStylePresets.h"
#import "Inspectors/DataInspector.h"

static void Check(BOOL value, NSString *why) { if (!value) [NSException raise:@"PresetCheckFailure" format:@"%@",why]; }
@interface Owner : NSObject <RSUndoerOwner>
@property(nonatomic,retain) NSUndoManager *undoManager;
@end
@implementation Owner
@synthesize undoManager = _undoManager;
- (id)init { if ((self=[super init])) { _undoManager=[[NSUndoManager alloc] init]; _undoManager.groupsByEvent=NO; } return self; }
- (void)undoerPerformedChange:(RSUndoer *)u {}
- (void)dealloc { [_undoManager release]; [super dealloc]; }
@end
static NSData *XML(RSGraph *g) { NSError *e=nil; NSData *d=[g generateXMLOfType:RSGraphFileType frame:CGRectMake(0,0,520,340) error:&e]; Check(d!=nil,e.description); return d; }
static RSTextLabel *Label(RSGraph *g, NSString *s, double x, double y) {
    RSTextLabel *l=[[[RSTextLabel alloc] initWithGraph:g] autorelease]; l.text=s; l.position=RSDataPointMake(x,y); [g addLabel:l]; return l;
}
static RSGraphEditor *Chart(id<RSUndoerOwner> owner) {
    [owner.undoManager disableUndoRegistration];
    RSUndoer *u=[[[RSUndoer alloc] initWithOwner:owner] autorelease];
    RSGraph *g=[[[RSGraph alloc] initWithIdentifier:nil undoer:u] autorelease]; [g setupDefault];
    g.canvasSize=CGSizeMake(520,340); g.autoMaintainsWhitespace=NO; g.whitespace=RSMakeBorder(35,40,55,65);
    [g setAxisRangesXMin:0 xMax:10 yMin:0 yMax:10];
    g.xAxis.title.text=@"Quantity (Q)"; g.yAxis.title.text=@"Price (€)";
    for (NSUInteger i=0;i<2;i++) {
        RSVertex *a=[[[RSVertex alloc] initWithGraph:g] autorelease], *b=[[[RSVertex alloc] initWithGraph:g] autorelease];
        a.position=RSDataPointMake(1,i?2:9); b.position=RSDataPointMake(9,i?8:1);
        NSColor *c=i?[NSColor colorWithSRGBRed:0.70 green:0.29 blue:0.08 alpha:1]:[NSColor colorWithSRGBRed:0.12 green:0.38 blue:0.70 alpha:1];
        a.shape=RS_CIRCLE; b.shape=RS_CIRCLE; a.width=3; b.width=3; a.color=c; b.color=c; [g addVertex:a]; [g addVertex:b];
        RSConnectLine *line=[[[RSConnectLine alloc] initWithGraph:g start:a end:b] autorelease]; line.color=c; [g addLine:line];
        if (i==0) [g makeLabelForOwner:line].text=@"D";
    }
    NSMutableArray *polygon=[NSMutableArray array];
    for (NSArray *point in @[@[@3,@3],@[@5,@5],@[@7,@3]]) {
        RSVertex *v=[[[RSVertex alloc] initWithGraph:g] autorelease]; v.position=RSDataPointMake([point[0] doubleValue],[point[1] doubleValue]); [g addVertex:v]; [polygon addObject:v];
    }
    RSGroup *vertices=[[[RSGroup alloc] initWithGraph:g byCopyingArray:polygon] autorelease];
    RSFill *fill=[[[RSFill alloc] initWithGraph:g vertexGroup:vertices] autorelease];
    fill.color=[NSColor colorWithSRGBRed:0.12 green:0.38 blue:0.70 alpha:0.25]; [g addFill:fill];
    Label(g,@"Demand",7,3.5); Label(g,@"Supply",7,7.8);
    RSTextLabel *l=Label(g,@"Market equilibrium · α − β = 2.5",1,9.8);
    NSMutableAttributedString *s=[[[l attributedString] mutableCopy] autorelease];
    [s addAttribute:NSFontAttributeName value:[NSFont boldSystemFontOfSize:15] range:NSMakeRange(0,6)];
    [s addAttribute:NSFontAttributeName value:[NSFont fontWithName:@"HelveticaNeue-Italic" size:13] range:NSMakeRange(7,4)];
    [s addAttribute:NSSuperscriptAttributeName value:@1 range:NSMakeRange(s.length-1,1)]; l.attributedString=s;
    RSGraphEditor *editor=[[[RSGraphEditor alloc] initWithGraph:g undoer:u] autorelease];
    [editor updateBounds:CGRectMake(0,0,520,340)]; [editor prepareForDisplay];
    [owner.undoManager enableUndoRegistration]; [owner.undoManager removeAllActions];
    return editor;
}
@interface ChartView : NSView
@property(nonatomic,assign) RSGraphEditor *editor;
@end
@implementation ChartView
@synthesize editor;
- (void)drawRect:(NSRect)rect { [editor.renderer drawBackgroundWithColor:editor.graph.backgroundColor]; [editor.renderer drawAllGraphElementsExcept:nil]; }
@end
static NSArray *Color(NSColor *c) {
    c=[c colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    return @[@(round(c.redComponent*1000)/1000),@(round(c.greenComponent*1000)/1000),@(round(c.blueComponent*1000)/1000),@(round(c.alphaComponent*1000)/1000)];
}
static double Linear(double x) { return x<=0.04045?x/12.92:pow((x+0.055)/1.055,2.4); }
static double VisibleContrast(NSColor *c,NSColor *bg) {
    c=[c colorUsingColorSpace:NSColorSpace.sRGBColorSpace]; bg=[bg colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    double a=c.alphaComponent;
    double foreground=0.2126*Linear(c.redComponent*a+bg.redComponent*(1-a))+0.7152*Linear(c.greenComponent*a+bg.greenComponent*(1-a))+0.0722*Linear(c.blueComponent*a+bg.blueComponent*(1-a));
    double background=0.2126*Linear(bg.redComponent)+0.7152*Linear(bg.greenComponent)+0.0722*Linear(bg.blueComponent);
    return (MAX(foreground,background)+0.05)/(MIN(foreground,background)+0.05);
}
static NSDictionary *Visuals(RSGraph *g) {
    NSMutableDictionary *r=[NSMutableDictionary dictionary];
    r[@"background"]=Color(g.backgroundColor); r[@"axes"]=@[Color(g.xAxis.color),Color(g.yAxis.color),Color(g.xGrid.color),Color(g.yGrid.color)];
    for (RSTextLabel *l in g.allLabels) {
        NSMutableArray *runs=[NSMutableArray array];
        for (NSUInteger k=0;k<l.attributedString.length;k++) {
            NSFont *f=[l.attributedString attribute:NSFontAttributeName atIndex:k effectiveRange:NULL];
            [runs addObject:@[f.fontName,@(f.pointSize),Color([l.attributedString attribute:NSForegroundColorAttributeName atIndex:k effectiveRange:NULL]),[l.attributedString attribute:NSSuperscriptAttributeName atIndex:k effectiveRange:NULL]?:@0]];
        }
        r[l.identifier]=@[l.text,runs];
    }
    for (NSArray *elements in @[g.Lines,g.Vertices,g.Fills]) for (RSGraphElement *e in elements) r[e.identifier]=Color(e.color);
    return r;
}
// The face a preset must give a run: Kalam in Sketch and Chalkboard except tick numbers, emphasis for axis
// titles, object labels and free text that was Medium or heavier; italic kept in Helvetica Neue.
static NSString *ExpectedFace(NSUInteger preset, RSGraph *g, RSTextLabel *label, NSFont *before) {
    NSFontManager *m=[NSFontManager sharedFontManager];
    BOOL tick=label.isAxisTickLabel || [g isAxisEndLabel:label];
    BOOL emphasis=!tick && ([g isAxisTitle:label] || label.owner!=nil || [m weightOfFont:before]>=6 || ([m traitsOfFont:before]&NSBoldFontMask));
    BOOL italic=([m traitsOfFont:before]&NSItalicFontMask)!=0;
    if ((preset==1 || preset==2) && !tick) return emphasis?@"Kalam-Bold":@"Kalam-Regular";
    return emphasis?(italic?@"HelveticaNeue-MediumItalic":@"HelveticaNeue-Medium"):(italic?@"HelveticaNeue-Italic":@"HelveticaNeue");
}
static NSArray *Layout(RSGraph *g) {
    return @[@(g.xAxis.displayAxis),@(g.xAxis.displayTicks),@(g.xAxis.displayTickLabels),@(g.xAxis.displayGrid),
             @(g.yAxis.displayAxis),@(g.yAxis.displayTicks),@(g.yAxis.displayTickLabels),@(g.yAxis.displayGrid)];
}
static NSDictionary *Geometry(RSGraph *g) {
    NSMutableArray *p=[NSMutableArray array]; for (RSVertex *v in g.Vertices) [p addObject:@[@(v.position.x),@(v.position.y),@(v.width),@(v.shape)]];
    NSMutableArray *labels=[NSMutableArray array]; for (RSTextLabel *l in g.allLabels) [labels addObject:@[l.identifier,l.text,@(l.position.x),@(l.position.y)]];
    return @{@"points":p,@"labels":labels,@"size":NSStringFromSize(g.canvasSize),@"range":@[@(g.xMin),@(g.xMax),@(g.yMin),@(g.yMax)],@"scale":@[@(g.xAxis.axisType),@(g.yAxis.axisType)]};
}
// Link-only stand-in for DataInspector's unused document-class predicate. The real
// DataInspector table edit/creation source is compiled; no GraphDocument UI is exercised.
@interface GraphDocument : NSDocument @end
@implementation GraphDocument @end
@interface ReviewDocument : NSDocument <RSUndoerOwner> @end
@implementation ReviewDocument
- (void)undoerPerformedChange:(RSUndoer *)undoer { [self updateChangeCount:NSChangeDone]; }
@end
@interface DataInspector (ReviewChecks)
- (void)tableView:(NSTableView *)table setObjectValue:(id)value forTableColumn:(NSTableColumn *)column row:(NSInteger)row;
@end
static BOOL ReviewRegressions(NSString *directory) {
    BOOL passed=YES;
    for (NSUInteger preset=0;preset<RSStylePresetNames().count;preset++) {
        ReviewDocument *document=[[[ReviewDocument alloc] init] autorelease];
        document.undoManager.groupsByEvent=NO;
        RSGraphEditor *editor=Chart(document); RSGraph *g=editor.graph;
        [document.undoManager disableUndoRegistration];
        RSTextLabel *annotation=g.userLabels[0];
        annotation.color=[NSColor colorWithSRGBRed:.02 green:.08 blue:.20 alpha:1];
        [document.undoManager enableUndoRegistration];
        [document updateChangeCount:NSChangeCleared];
        [editor applyStylePreset:preset];
        NSData *applied=XML(g); NSColor *first=annotation.color;
        [document.undoManager removeAllActions]; [document updateChangeCount:NSChangeCleared];
        BOOL changed=[editor applyStylePreset:preset];
        BOOL stable=!changed && [applied isEqual:XML(g)] && !document.undoManager.canUndo && !document.isDocumentEdited;
        NSLog(@"%@ review annotation %@ first=%@ second=%@ dirty=%d undo=%d",stable?@"PASS":@"FAIL",RSStylePresetNames()[preset],Color(first),Color(annotation.color),document.isDocumentEdited,document.undoManager.canUndo);
        passed &= stable;
        // Legacy payloads retain visuals; OPC additionally retains concrete creation defaults.
        for (NSNumber *format in @[@(RSGraphArchiveLegacyXML),@(RSGraphArchiveLegacyZIP),@(RSGraphArchiveOPC)]) {
            ReviewDocument *owner=[[[ReviewDocument alloc] init] autorelease]; owner.undoManager.groupsByEvent=NO;
            RSUndoer *undo=[[[RSUndoer alloc] initWithOwner:owner] autorelease]; [owner.undoManager disableUndoRegistration];
            NSError *error=nil;
            NSURL *url=[NSURL fileURLWithPath:[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"review-%lu-%@.graphink",(unsigned long)preset,format]]];
            Check([RSGraphArchive writeXML:applied defaults:format.integerValue==RSGraphArchiveOPC?g.creationDefaults:nil preview:nil encoding:format.integerValue toURL:url error:&error],error.description);
            RSGraph *reopened=[RSGraph graphFromURL:url type:RSGraphFileType undoer:undo error:&error];
            Check(reopened!=nil,error.description); [owner.undoManager enableUndoRegistration];
            RSGraphEditor *reopenEditor=[[[RSGraphEditor alloc] initWithGraph:reopened undoer:undo] autorelease];
            NSData *before=XML(reopened); [owner updateChangeCount:NSChangeCleared];
            BOOL adopted=[reopenEditor applyStylePreset:preset];
            BOOL correct=[before isEqual:XML(reopened)];
            if (format.integerValue==RSGraphArchiveOPC) correct &= !adopted && !owner.undoManager.canUndo && !owner.isDocumentEdited;
            else correct &= adopted && RSCreationDefaultsEqual(reopened.creationDefaults,g.creationDefaults);
            Check(![reopenEditor applyStylePreset:preset],@"Second application is a fixed point after explicit model-level adoption");
            NSLog(@"%@ review format=%@ reopen visual fixed point / OPC defaults %@",correct?@"PASS":@"FAIL",format,RSStylePresetNames()[preset]);
            passed &= correct; [reopenEditor invalidate];
        }
        [editor invalidate];
    }
    for (NSUInteger preset=0;preset<RSStylePresetNames().count;preset++) {
        Owner *owner=[[[Owner alloc] init] autorelease]; RSGraphEditor *editor=Chart(owner);
        [owner.undoManager disableUndoRegistration];
        RSTextLabel *label=editor.graph.userLabels[0];
        NSFont *font=[NSFont fontWithName:@"HelveticaNeue-CondensedBlack" size:15];
        NSMutableAttributedString *text=[[[label attributedString] mutableCopy] autorelease];
        [text addAttribute:NSFontAttributeName value:font range:NSMakeRange(0,text.length)]; label.attributedString=text;
        [owner.undoManager enableUndoRegistration]; [editor applyStylePreset:preset];
        NSFont *after=[label.attributedString attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
        NSString *expected=(preset==1 || preset==2)?@"Kalam-Bold":@"HelveticaNeue-Medium";
        BOOL styled=[after.fontName isEqual:expected] && after.pointSize==15;
        NSLog(@"%@ review condensed black %@ -> %@ (expected %@)",styled?@"PASS":@"FAIL",RSStylePresetNames()[preset],after.fontName,expected);
        passed &= styled; [editor invalidate];
    }
    for (NSNumber *dark in @[@NO,@YES]) {
        Owner *owner=[[[Owner alloc] init] autorelease]; RSGraphEditor *editor=Chart(owner);
        if (dark.boolValue) [editor applyStylePreset:2];
        [owner.undoManager disableUndoRegistration];
        DataInspector *inspector=[[[DataInspector alloc] initWithDictionary:@{@"identifier":@"PresetChecks.Data"} inspectorRegistry:nil bundle:NSBundle.mainBundle] autorelease];
        [inspector setValue:editor.graph forKey:@"graph"];
        NSTableColumn *x=[[[NSTableColumn alloc] initWithIdentifier:@"positionx"] autorelease],*y=[[[NSTableColumn alloc] initWithIdentifier:@"positiony"] autorelease];
        NSUInteger row=editor.graph.Vertices.count;
        [inspector tableView:nil setObjectValue:@"4" forTableColumn:x row:row];
        [inspector tableView:nil setObjectValue:@"6" forTableColumn:y row:row];
        RSVertex *point=editor.graph.Vertices.lastObject;
        BOOL readable=editor.graph.Vertices.count==row+1 && (!dark.boolValue || VisibleContrast(point.color,editor.graph.backgroundColor)>=3);
        NSLog(@"%@ review actual DataInspector %@ creation contrast %.4f",readable?@"PASS":@"FAIL",dark.boolValue?@"dark":@"light",VisibleContrast(point.color,editor.graph.backgroundColor));
        passed &= readable;
        point.color=NSColor.blackColor;
        [inspector tableView:nil setObjectValue:@"7" forTableColumn:x row:row];
        Check([Color(point.color) isEqual:Color(NSColor.blackColor)],@"Editing explicit existing Data point preserves its color");
        Owner *loadedOwner=[[[Owner alloc] init] autorelease]; RSUndoer *loadedUndo=[[[RSUndoer alloc] initWithOwner:loadedOwner] autorelease];
        [loadedOwner.undoManager disableUndoRegistration]; NSError *error=nil;
        RSGraph *loaded=[RSGraph graphFromData:XML(editor.graph) fileName:@"Explicit.graphink" type:RSGraphFileType undoer:loadedUndo error:&error];
        Check(loaded!=nil,error.description); [inspector setValue:loaded forKey:@"graph"];
        [inspector tableView:nil setObjectValue:@"8" forTableColumn:y row:row];
        Check([Color(((RSVertex *)loaded.Vertices[row]).color) isEqual:Color(NSColor.blackColor)],@"Editing a loaded Data point preserves its explicit color");
        [loaded invalidate]; [loadedUndo invalidate];
        [owner.undoManager enableUndoRegistration]; [editor invalidate];
    }
    return passed;
}
int main(int argc,const char **argv) { @autoreleasepool { @try {
    Check(argc==2,@"Supply output directory");
    OFController *controller=[OFController sharedController]; [controller didInitialize]; [controller startedRunning];
    NSError *error=nil; Check(RSRegisterStyleFonts(NSBundle.mainBundle,&error),error.description);
    Check([[NSFont fontWithName:@"Kalam-Regular" size:15].fontName isEqual:@"Kalam-Regular"] && [[NSFont fontWithName:@"Kalam-Bold" size:15].fontName isEqual:@"Kalam-Bold"],@"Exact Kalam faces");
    Check(ReviewRegressions(@(argv[1])),@"Independent review adverse inputs");
    NSDictionary *preferences=[[NSUserDefaults.standardUserDefaults dictionaryRepresentation] copy];
    Owner *otherOwner=[[[Owner alloc] init] autorelease]; RSGraphEditor *other=Chart(otherOwner); NSData *otherXML=XML(other.graph);
    [otherOwner.undoManager disableUndoRegistration];
    for (NSNumber *opacity in @[@0,@0.01,@0.25,@0.5,@1]) {
        NSColor *blue=[NSColor colorWithSRGBRed:0.02 green:0.08 blue:0.2 alpha:opacity.doubleValue];
        NSColor *red=[NSColor colorWithSRGBRed:0.2 green:0.04 blue:0.02 alpha:opacity.doubleValue];
        NSColor *dark=[NSColor colorWithSRGBRed:38/255.0 green:51/255.0 blue:48/255.0 alpha:1];
        NSColor *saved=other.graph.backgroundColor; other.graph.backgroundColor=dark;
        NSColor *a=RSStyleCreationColor(blue,other.graph,YES), *b=RSStyleCreationColor(red,other.graph,YES);
        Check(fabs(a.alphaComponent-opacity.doubleValue)<1e-9 && fabs(b.alphaComponent-opacity.doubleValue)<1e-9,@"Opacity including zero preserved");
        Check(![Color(a) isEqual:Color(b)],@"Translucent series remain distinguishable");
        Check(VisibleContrast(a,dark)>=VisibleContrast(blue,dark)-1e-6,@"Composited fill contrast never decreases");
        if (opacity.doubleValue>=0.25) Check(VisibleContrast(a,dark)>=1.499,@"Representative translucent fill reaches region target");
        NSLog(@"ALPHA %@ composited fill contrast %.4f (preserved alpha %.2f)",opacity,VisibleContrast(a,dark),a.alphaComponent);
        NSColor *again=RSStyleCreationColor(a,other.graph,YES);
        Check([Color(again) isEqual:Color(a)],@"Opacity-constrained adaptation remains idempotent");
        if (opacity.doubleValue==0) Check(a==blue && b==red,@"Fully transparent colors unchanged");
        other.graph.backgroundColor=saved;
    }
    [otherOwner.undoManager enableUndoRegistration];
    NSMutableData *sheet=[NSMutableData data]; NSRect media=NSMakeRect(0,0,1670,850);
    CGDataConsumerRef consumer=CGDataConsumerCreateWithCFData((CFMutableDataRef)sheet);
    CGContextRef context=CGPDFContextCreate(consumer,&media,NULL); CGPDFContextBeginPage(context,NULL);
    NSGraphicsContext *old=[NSGraphicsContext currentContext]; [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:context flipped:NO]];
    for (NSUInteger i=0;i<RSStylePresetNames().count;i++) {
        Owner *owner=[[[Owner alloc] init] autorelease]; RSGraphEditor *editor=Chart(owner); RSGraph *g=editor.graph;
        NSData *before=XML(g); NSDictionary *geometry=Geometry(g); NSDictionary *beforeVisuals=Visuals(g); NSArray *layout=Layout(g);
        Check([editor applyStylePreset:i],@"First apply changes style"); NSData *after=XML(g);
        // Only Editorial changes axis and grid visibility: x baseline, horizontal rules, no y line or ticks.
        NSArray *editorial=@[@YES,layout[1],layout[2],@YES,@NO,@NO,layout[6],@NO];
        Check([Layout(g) isEqual:i==4?editorial:layout],@"Axis and grid visibility follow the preset");
        for (RSTextLabel *label in g.allLabels) {
            NSArray *oldRuns=beforeVisuals[label.identifier][1];
            for (NSUInteger k=0;k<label.attributedString.length;k++) {
                NSFont *f=[label.attributedString attribute:NSFontAttributeName atIndex:k effectiveRange:NULL];
                Check(f.pointSize==[oldRuns[k][1] doubleValue],@"Run sizes preserved");
                NSFont *oldFont=[NSFont fontWithName:oldRuns[k][0] size:f.pointSize];
                NSString *expected=ExpectedFace(i,g,label,oldFont);
                Check([f.fontName isEqual:expected],[NSString stringWithFormat:@"%@: \"%@\" run %lu is %@ (was %@), expected %@",RSStylePresetNames()[i],label.text,(unsigned long)k,f.fontName,oldRuns[k][0],expected]);
                Check([[label.attributedString attribute:NSSuperscriptAttributeName atIndex:k effectiveRange:NULL]?:@0 isEqual:oldRuns[k][3]],@"Superscript preserved");
            }
        }
        Check([geometry isEqual:Geometry(g)],@"Apply preserves data, positions, canvas, ranges, scales, widths/shapes");
        [owner.undoManager undo]; Check([before isEqual:XML(g)],@"One undo restores exact serialized document"); Check(!owner.undoManager.canUndo,@"Only one undo entry");
        [owner.undoManager redo]; Check([after isEqual:XML(g)],@"Redo exact style");
        Check(![editor applyStylePreset:i],@"Identical reapplication is no-op");
        Check([otherXML isEqual:XML(other.graph)] && !otherOwner.undoManager.canUndo,@"Per-document isolation");
        Owner *reopenOwner=[[[Owner alloc] init] autorelease];
        RSUndoer *newUndo=[[[RSUndoer alloc] initWithOwner:reopenOwner] autorelease];
        [reopenOwner.undoManager disableUndoRegistration];
        RSGraph *reopened=[RSGraph graphFromData:after fileName:@"Style.graphink" type:RSGraphFileType undoer:newUndo error:&error];
        [reopenOwner.undoManager enableUndoRegistration];
        Check(reopened!=nil,error.description); Check([Visuals(g) isEqual:Visuals(reopened)],@"XML save/reopen preserves all serialized style properties"); RSUndoer *reopenUndo=reopened.undoer;
        RSGraphEditor *reopenEditor=[[[RSGraphEditor alloc] initWithGraph:reopened undoer:reopenUndo] autorelease];
        NSData *normalizedBefore=XML(reopened);
        Check([reopenEditor applyStylePreset:i] && [normalizedBefore isEqual:XML(reopened)] && RSCreationDefaultsEqual(reopened.creationDefaults,g.creationDefaults),@"Legacy model-level adoption adds only concrete defaults; native color normalization is stable");
        Check(![reopenEditor applyStylePreset:i],@"Reapplication after explicit defaults adoption is no-op");
        Check([Layout(reopened) isEqual:Layout(g)],@"Save/reopen preserves axis and grid visibility");
        [reopenEditor invalidate];
        Check([preferences isEqual:[NSUserDefaults.standardUserDefaults dictionaryRepresentation]],@"No preference mutation");
        if (i==2) {
            [otherOwner.undoManager disableUndoRegistration];
            [owner.undoManager disableUndoRegistration];
            for (RSGraphEditor *document in @[editor,other]) {
                RSGraph *canvas=document.graph;
                RSVertex *fresh=[[[RSVertex alloc] initWithGraph:canvas] autorelease];
                RSFill *fill=[[[RSFill alloc] initWithGraph:canvas] autorelease];
                RSTextLabel *text=[[[RSTextLabel alloc] initWithGraph:canvas] autorelease];
                NSColor *original=fresh.color;
                RSAdaptNewObjectColor(fresh,NO); RSAdaptNewObjectColor(fill,YES); RSAdaptNewObjectColor(text,NO);
                if (document==editor) Check(![Color(fresh.color) isEqual:Color(original)] && ![Color(text.color) isEqual:Color(NSColor.blackColor)],@"New dark-canvas Draw/Text defaults adapted");
                else Check([Color(fresh.color) isEqual:Color(original)],@"Light document keeps personalized defaults");
                fresh.color=NSColor.blackColor; Check([Color(fresh.color) isEqual:Color(NSColor.blackColor)],@"Explicit dark override preserved by ordinary model setter");
                [fresh invalidate]; [fill invalidate]; [text invalidate];
            }
            [owner.undoManager enableUndoRegistration];
            [otherOwner.undoManager enableUndoRegistration];
            [owner.undoManager undo];
            Check(RSStyleCreationColor(NSColor.blackColor,g,NO)==NSColor.blackColor,@"Creation follows canvas after undo");
            [owner.undoManager redo];
            Check(![Color(RSStyleCreationColor(NSColor.blackColor,g,NO)) isEqual:Color(NSColor.blackColor)],@"Creation follows canvas after redo");
        }
        RSVertex *preview=[[[RSVertex alloc] initWithGraph:g] autorelease];
        BOOL canUndo=owner.undoManager.canUndo;
        for (NSUInteger refresh=0;refresh<3;refresh++) RSAcceptStyleCreationDefaults(preview,NO);
        Check(owner.undoManager.canUndo==canUndo,@"Tool default/preview refresh registers no undo");
        [preview invalidate];
        NSString *name=RSStylePresetNames()[i]; NSString *dir=@(argv[1]);
        [after writeToFile:[dir stringByAppendingPathComponent:[name stringByAppendingString:@".xml"]] atomically:YES];
        [editor prepareForDisplay];
        ChartView *view=[[[ChartView alloc] initWithFrame:NSMakeRect(0,0,520,340)] autorelease]; view.editor=editor;
        Check(![editor applyStylePreset:i],@"Reapply after native layout remains no-op");
        NSData *pdf=[view dataWithPDFInsideRect:view.bounds]; Check(pdf.length>1000,@"Native vector PDF export");
        [pdf writeToFile:[dir stringByAppendingPathComponent:[name stringByAppendingString:@".pdf"]] atomically:YES];
        NSURL *saved=[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:[name stringByAppendingString:@".graphink"]]];
        Check([g writeToURL:saved generatedXMLData:XML(g) previewPDFData:pdf error:&error],error.description);
        NSURL *opcSaved=[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:[name stringByAppendingString:@"-opc.graphink"]]];
        Check([RSGraphArchive writeXML:XML(g) defaults:g.creationDefaults preview:pdf encoding:RSGraphArchiveOPC toURL:opcSaved error:&error],error.description);
        NSData *previewData=nil;
        Check([RSGraph getGraphPDFPreviewData:&previewData modificationDate:NULL fromURL:opcSaved error:&error] && [previewData isEqual:pdf],@"OPC typed/related real vector preview extracts through gated model URL API");
        Owner *zipOwner=[[[Owner alloc] init] autorelease]; RSUndoer *zipUndo=[[[RSUndoer alloc] initWithOwner:zipOwner] autorelease];
        [zipOwner.undoManager disableUndoRegistration];
        RSGraph *zip=[RSGraph graphFromURL:saved type:RSGraphFileType undoer:zipUndo error:&error];
        Check(zip!=nil,error.description); Check([Visuals(zip) isEqual:Visuals(g)],@"Ordinary ZIP document save/reopen preserves style");
        [zip invalidate]; [zipUndo invalidate];
        NSAttributedString *sample=[[[NSAttributedString alloc] initWithString:@"0123456789 − + = € α β Γ Δ" attributes:@{NSFontAttributeName:[NSFont fontWithName:@"Kalam-Regular" size:15]}] autorelease];
        CTLineRef line=CTLineCreateWithAttributedString((CFAttributedStringRef)sample);
        for (id run in (NSArray *)CTLineGetGlyphRuns(line)) { CFIndex count=CTRunGetGlyphCount((CTRunRef)run); CGGlyph glyphs[count]; CTRunGetGlyphs((CTRunRef)run,CFRangeMake(0,0),glyphs); for(CFIndex k=0;k<count;k++) Check(glyphs[k]!=0,@"Numbers/signs/Greek resolve through native fallback"); }
        CFRelease(line);
        [NSGraphicsContext saveGraphicsState]; CGFloat x=20+(i%3)*550,y=450-(i/3)*410; CGContextTranslateCTM(context,x,y);
        [name drawAtPoint:NSMakePoint(0,365) withAttributes:@{NSFontAttributeName:[NSFont boldSystemFontOfSize:18]}];
        NSString *caption=@[@"Helvetica Neue/Medium · #FFFFFF / #30343B / #D8DCE2",@"Kalam Regular/Bold, Helvetica Neue ticks · #FBF5E9 / #443D35 / #DDD2BE",@"Kalam Regular/Bold, Helvetica Neue ticks · #263330 / #F3EEDC / #56665F",@"Helvetica Neue/Medium · #F8FAFD / #24374D / #D8E1ED",@"Helvetica Neue/Medium · #FAFAF8 / #1A1D21 / #C9CED4 · accent #1D5FA8 · horizontal rules"][i];
        [caption drawAtPoint:NSMakePoint(0,345) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:10]}];
        [view drawRect:view.bounds]; [NSGraphicsContext restoreGraphicsState];
        [editor invalidate]; printf("PASS %s apply undo redo no-op geometry isolation reopen PDF glyphs\n",name.UTF8String);
    }
    [NSGraphicsContext setCurrentContext:old]; CGPDFContextEndPage(context); CGPDFContextClose(context); CGContextRelease(context); CGDataConsumerRelease(consumer);
    [sheet writeToFile:[@(argv[1]) stringByAppendingPathComponent:@"comparison.pdf"] atomically:YES];
    [other invalidate]; [preferences release]; Check([controller requestTermination]==OFControllerTerminateNow,@"Headless termination"); [controller willTerminate]; printf("PASS all presets\n");
    return 0;
} @catch(NSException *e) { NSLog(@"FAIL %@",e); return 1; } } }
