// Focused model/default/XML checks; no app event loop, nibs or windows.
#import <Cocoa/Cocoa.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniAppKit/OAFontDescriptor.h>
#import <GraphSketcherModel/RSGraph.h>
#import <GraphSketcherModel/RSUndoer.h>
#import <GraphSketcherModel/RSUndoerOwner.h>
#import <GraphSketcherModel/RSAxis.h>
#import <GraphSketcherModel/RSTextLabel.h>
#import <GraphSketcherModel/RSConnectLine.h>
#import <GraphSketcherModel/OFPreference-RSExtensions.h>
#import <objc/runtime.h>
#include <dlfcn.h>

static void Check(BOOL value, NSString *reason) {
    if (!value) [NSException raise:@"StyleDefaultsFailure" format:@"%@", reason];
}
@interface StyleCheckOwner : NSObject <RSUndoerOwner>
@property(nonatomic, retain) NSUndoManager *undoManager;
@end
@implementation StyleCheckOwner
@synthesize undoManager = _undoManager;
- (id)init { if ((self = [super init])) _undoManager = [[NSUndoManager alloc] init]; return self; }
- (void)undoerPerformedChange:(RSUndoer *)undoer {}
- (void)dealloc { [_undoManager release]; [super dealloc]; }
@end

static NSDictionary *Font(NSFont *font) {
    Check(font != nil, @"Missing font");
    return @{ @"name":font.fontName, @"family":font.familyName, @"size":@(font.pointSize) };
}
static NSDictionary *Labels(RSGraph *g) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (RSTextLabel *label in g.allLabels)
        result[label.identifier] = Font(label.fontDescriptor.font);
    for (RSAxis *axis in @[g.xAxis, g.yAxis])
        for (NSString *key in axis.userLabelsDictionary) {
            RSTextLabel *label = axis.userLabelsDictionary[key];
            result[label.identifier] = Font(label.fontDescriptor.font);
        }
    return result;
}
static void Expect(RSTextLabel *label, NSString *name, CGFloat size) {
    NSDictionary *font = Font(label.fontDescriptor.font);
    Check([font[@"name"] isEqual:name] && [font[@"size"] doubleValue] == size,
          [NSString stringWithFormat:@"Expected %@ %g, got %@", name, size, font]);
}
static RSGraph *NewGraph(RSUndoer *undoer) {
    RSGraph *g = [[[RSGraph alloc] initWithIdentifier:nil undoer:undoer] autorelease];
    [g setupDefault];
    RSTextLabel *label = [[[RSTextLabel alloc] initWithGraph:g] autorelease];
    label.text = @"Preserved document label";
    [g addLabel:label];
    // Include an interior tick derived from each axis' font, not only its endpoints.
    [g.xAxis userLabelForTick:5]; [g.yAxis userLabelForTick:5];
    return g;
}
static RSTextLabel *FreeLabel(RSGraph *g) {
    for (RSTextLabel *label in g.allLabels) if ([label.text isEqual:@"Preserved document label"]) return label;
    [NSException raise:@"StyleDefaultsFailure" format:@"Missing free label"]; return nil;
}
static void CheckFonts(RSGraph *g, NSString *labelName, CGFloat labelSize,
                       NSString *xTick, CGFloat xSize, NSString *yTick, CGFloat ySize,
                       NSString *xTitle, CGFloat xtSize, NSString *yTitle, CGFloat ytSize) {
    Expect(FreeLabel(g), labelName, labelSize);
    for (RSTextLabel *label in g.xAxis.userLabelsDictionary.allValues) Expect(label,xTick,xSize);
    for (RSTextLabel *label in g.yAxis.userLabelsDictionary.allValues) Expect(label,yTick,ySize);
    Expect(g.xAxis.title,xTitle,xtSize); Expect(g.yAxis.title,yTitle,ytSize);
}
static NSData *Save(RSGraph *graph, NSString *path) {
    NSError *error = nil;
    NSData *xml = [graph generateXMLOfType:RSGraphFileType frame:CGRectZero error:&error];
    Check(xml != nil, [error description]);
    Check([graph writeToURL:[NSURL fileURLWithPath:path] generatedXMLData:xml previewPDFData:nil error:&error], [error description]);
    return xml;
}
static RSGraph *Open(NSString *path, RSUndoer *undoer) {
    NSError *error = nil;
    NSString *type = [[path pathExtension] caseInsensitiveCompare:@"ograph"] == NSOrderedSame ? RSGraphLegacyFileType : RSGraphFileType;
    RSGraph *g = [RSGraph graphFromURL:[NSURL fileURLWithPath:path] type:type undoer:undoer error:&error];
    Check(g != nil, [error description]); return g;
}
static NSDictionary *CustomPreferences(BOOL commonOnly) {
    NSArray *names = @[@"DefaultLabelFont", @"DefaultAxisTickLabelFont", @"DefaultXAxisTickLabelFont", @"DefaultYAxisTickLabelFont", @"DefaultXAxisTitleFont", @"DefaultYAxisTitleFont"];
    NSArray *faces = @[@"Georgia-Italic", @"Courier", @"Menlo-Bold", @"TimesNewRomanPS-ItalicMT", @"HelveticaNeue-Light", @"Georgia-Bold"];
    NSArray *sizes = @[@17,@15,@16,@18,@19,@20];
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSUInteger i=0; i<names.count; i++) {
        if (commonOnly && i != 1) continue;
        OAFontDescriptor *font = [[[OAFontDescriptor alloc] initWithName:faces[i] size:[sizes[i] doubleValue]] autorelease];
        result[names[i]] = font.fontAttributes;
    }
    return result;
}
int main(int argc, const char *argv[]) {
    @autoreleasepool { @try {
        Check(argc == 3, @"Usage: checks MODE EVIDENCE_DIRECTORY");
        NSString *mode = @(argv[1]), *dir = @(argv[2]);
        NSString *domain = NSBundle.mainBundle.bundleIdentifier;
        Check([domain hasPrefix:@"com.graphsketcher.stylechecks."], @"Refuse any production preference domain");
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        BOOL common = [mode hasPrefix:@"common-"];
        if ([mode hasSuffix:@"-seed"]) {
            Check([defaults persistentDomainForName:domain] == nil, @"Refuse to replace an existing domain");
            NSDictionary *custom = CustomPreferences(common);
            [defaults setPersistentDomain:custom forName:domain];
            Check([defaults synchronize], @"Persist isolated test preferences");
            Check([[defaults persistentDomainForName:domain] isEqual:custom], @"Seed test preferences");
            printf("PASS %s\n", argv[1]); return 0;
        }
        NSDictionary *before = [defaults persistentDomainForName:domain];
        if ([mode hasSuffix:@"-read"]) Check([before isEqual:CustomPreferences(common)], [NSString stringWithFormat:@"Custom preferences must persist across processes: actual=%@ expected=%@", before, CustomPreferences(common)]);
        OFController *controller = OFController.sharedController;
        [controller didInitialize]; [controller startedRunning];
        Dl_info implementation;
        IMP imp = method_getImplementation(class_getInstanceMethod([OFPreferenceWrapper class], @selector(fontDescriptorForKey:)));
        Check(dladdr((void *)imp, &implementation) && [@(implementation.dli_fname) isEqual:NSBundle.mainBundle.executablePath], @"Harness must execute the current model preference source");
        StyleCheckOwner *owner = [[[StyleCheckOwner alloc] init] autorelease];
        [owner.undoManager disableUndoRegistration];
        RSUndoer *undoer = [[[RSUndoer alloc] initWithOwner:owner] autorelease];
        NSMutableArray *graphs = [NSMutableArray array];
        RSGraph *g = NewGraph(undoer); [graphs addObject:g];
        if ([mode isEqual:@"baseline"]) {
            CheckFonts(g,@"LucidaGrande",12,@"LucidaGrande",12,@"LucidaGrande",12,@"LucidaGrande",12,@"LucidaGrande",12);
            NSData *xml = Save(g,[dir stringByAppendingPathComponent:@"baseline.ograph"]);
            NSString *text = [[[NSString alloc] initWithData:xml encoding:NSUTF8StringEncoding] autorelease];
            Check(![text containsString:@"key=\"font-size\""] && ![text containsString:@"key=\"font-family\""], @"Baseline must exercise omitted font size/family, not just explicit attributes");
            NSData *fonts = [NSJSONSerialization dataWithJSONObject:Labels(g) options:NSJSONWritingPrettyPrinted error:NULL];
            Check([fonts writeToFile:[dir stringByAppendingPathComponent:@"baseline-fonts.json"] atomically:YES], @"Write baseline font snapshot");
        } else {
            if ([mode isEqual:@"defaults"])
                CheckFonts(g,@"HelveticaNeue",13,@"HelveticaNeue",12,@"HelveticaNeue",12,@"HelveticaNeue-Medium",14,@"HelveticaNeue-Medium",14);
            else if (common)
                CheckFonts(g,@"HelveticaNeue",13,@"Courier",15,@"Courier",15,@"HelveticaNeue-Medium",14,@"HelveticaNeue-Medium",14);
            else
                CheckFonts(g,@"Georgia-Italic",17,@"Menlo-Bold",16,@"TimesNewRomanPS-ItalicMT",18,@"HelveticaNeue-Light",19,@"Georgia-Bold",20);
            OFPreferenceWrapper *prefs = OFPreferenceWrapper.sharedPreferenceWrapper;
            Check([prefs floatForKey:@"DefaultLineWidth"] == 2 && [prefs integerForKey:@"DefaultVertexShape"] == 1, @"Keep line/circle registrations");
            Check(!g.xAxis.displayGrid && !g.yAxis.displayGrid, @"New graph grids remain off");
            NSColor *background = [g.backgroundColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
            Check(background.redComponent == 1 && background.greenComponent == 1 && background.blueComponent == 1, @"New graph canvas remains white");
            RSConnectLine *line = [[[RSConnectLine alloc] initWithGraph:g] autorelease];
            Check(line.width == 2, @"New model line remains 2pt");
            NSString *path = [dir stringByAppendingPathComponent:[mode stringByAppendingString:@".ograph"]];
            NSDictionary *fonts = Labels(g); Save(g,path);
            RSGraph *reopened = Open(path,undoer); [graphs addObject:reopened];
            Check([Labels(reopened) isEqual:fonts], @"Current/custom graph fonts survive save/reopen");
            if ([mode isEqual:@"defaults"]) {
                RSGraph *custom = Open([dir stringByAppendingPathComponent:@"custom-read.ograph"],undoer);
                [graphs addObject:custom];
                CheckFonts(custom,@"Georgia-Italic",17,@"Menlo-Bold",16,@"TimesNewRomanPS-ItalicMT",18,@"HelveticaNeue-Light",19,@"Georgia-Bold",20);
            }
            RSGraph *legacy = Open([dir stringByAppendingPathComponent:@"baseline.ograph"],undoer); [graphs addObject:legacy];
            NSDictionary *oldFonts = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"baseline-fonts.json"]] options:0 error:NULL];
            Check([Labels(legacy) isEqual:oldFonts], @"Baseline omitted-font label/tick/title attributes must not restyle on open");
            NSString *oldPath = [dir stringByAppendingPathComponent:[mode stringByAppendingString:@"-legacy.ograph"]];
            Save(legacy,oldPath);
            RSGraph *oldAgain = Open(oldPath,undoer); [graphs addObject:oldAgain];
            Check([Labels(oldAgain) isEqual:oldFonts], @"Legacy fonts survive a subsequent save/reopen");
        }
        Check([[defaults persistentDomainForName:domain] ?: @{} isEqual:before ?: @{}], @"Model checks must not change personalized preferences");
        for (RSGraph *graph in graphs) [graph invalidate];
        [undoer invalidate];
        Check([controller requestTermination] == OFControllerTerminateNow, @"Terminate headless controller");
        [controller willTerminate];
        printf("PASS %s\n", argv[1]);
    } @catch (NSException *exception) { fprintf(stderr,"FAIL %s\n",exception.description.UTF8String); return 1; } }
    return 0;
}
