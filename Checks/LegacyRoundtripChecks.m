// Legacy roundtrip regressions through production RSGraph IO. Windowless; no app nib, UI or visual acceptance implied.
#import <Cocoa/Cocoa.h>
#import <GraphSketcherModel/RSGraph.h>
#import <GraphSketcherModel/RSGraphArchive.h>
#import <GraphSketcherModel/RSUndoer.h>
#import <GraphSketcherModel/RSUndoerOwner.h>
#import <GraphSketcherModel/RSVertex.h>
#import <GraphSketcherModel/RSLine.h>
#import <GraphSketcherModel/RSAxis.h>
#import <GraphSketcherModel/RSGroup.h>
#import <GraphSketcherModel/RSTextLabel.h>
#import <OmniFoundation/OFController.h>
#include <math.h>
@interface RSGraph (LegacyRoundtripChecks) // Production pasteboard archiving (RSGraph-XML.h is not public).
+ (NSData *)archivedDataWithRootObject:(RSGraphElement *)GE graphID:(NSString *)graphID error:(NSError **)outError;
- (RSGraphElement *)unarchiveObjectWithData:(NSData *)data getGraphID:(NSString **)graphID error:(NSError **)outError;
@end

static void Check(BOOL value, NSString *reason) { if (!value) { fprintf(stderr, "FAIL: %s\n", reason.UTF8String); fflush(NULL); _Exit(1); } }

@interface CheckController : OFController
@end
@implementation CheckController
- (BOOL)crashOnAssertionOrUnhandledException { return YES; } // Model preconditions (e.g. finite curve times) stay fatal.
@end
@interface CheckOwner : NSObject <RSUndoerOwner>
@property(nonatomic, retain) NSUndoManager *undoManager;
@end
@implementation CheckOwner
@synthesize undoManager = _undoManager;
- (id)init { if ((self = [super init])) _undoManager = [[NSUndoManager alloc] init]; return self; }
- (void)undoerPerformedChange:(RSUndoer *)undoer {}
- (void)dealloc { [_undoManager release]; [super dealloc]; }
@end

static RSUndoer *Undoer;
static NSString *Output;
static NSMutableArray *Graphs;

static NSString *const Axes = @"<axis id='x' dimension='x' placement='origin'/><axis id='y' dimension='y' placement='origin'/>";
static NSData *Document(NSString *graph)
{
    if (![graph hasPrefix:@"<axis"]) graph = [Axes stringByAppendingString:graph]; // Generated XML then validates against the current schema.
    return [[NSString stringWithFormat:@"<?xml version=\"1.0\" encoding=\"utf-8\"?><document xmlns=\"http://www.omnigroup.com/namespace/OmniGraphSketcher/v1\" app-version=\"10.0.0\"><graph>%@</graph></document>", graph] dataUsingEncoding:NSUTF8StringEncoding];
}
static RSGraph *Read(NSURL *url, NSInteger expectedEncoding)
{
    NSError *error = nil; NSInteger encoding = -1;
    // .ograph reads with the original GraphSketcher type, .graphink with Graphink's own.
    NSString *type = [url.pathExtension caseInsensitiveCompare:@"ograph"] == NSOrderedSame ? RSGraphLegacyFileType : RSGraphFileType;
    RSGraph *graph = [RSGraph graphFromURL:url type:type undoer:Undoer encoding:&encoding error:&error];
    Check(graph != nil, [NSString stringWithFormat:@"Production load %@: %@", url.path, error]);
    Check(encoding == expectedEncoding, [NSString stringWithFormat:@"Container encoding %@: %ld", url.lastPathComponent, (long)encoding]);
    [Graphs addObject:graph];
    return graph;
}
static NSData *Generate(RSGraph *graph)
{
    NSError *error = nil; NSData *xml = [graph generateXMLOfType:RSGraphFileType frame:CGRectZero error:&error];
    Check(xml != nil, [NSString stringWithFormat:@"Production generateXML: %@", error]);
    return xml;
}
static NSURL *Fresh(NSString *name)
{
    NSURL *url = [NSURL fileURLWithPath:[Output stringByAppendingPathComponent:name]];
    Check(![[NSFileManager defaultManager] fileExistsAtPath:url.path], [@"Refuse to overwrite " stringByAppendingString:name]);
    return url;
}
static RSGraph *Fixture(NSString *name, NSString *graph)
{
    NSURL *url = Fresh([name stringByAppendingString:@".ograph"]);
    Check([Document(graph) writeToURL:url atomically:NO], @"Write disposable fixture");
    return Read(url, RSGraphArchiveLegacyXML);
}
// Two saves per production container; each reopened graph is checked by the caller's block.
static void Roundtrips(RSGraph *graph, NSString *name, void (^check)(RSGraph *, NSString *))
{
    check(graph, [name stringByAppendingString:@" first-load"]);
    NSDictionary *formats = @{@"xml": @(RSGraphArchiveLegacyXML), @"zip": @(RSGraphArchiveLegacyZIP), @"opc": @(RSGraphArchiveOPC)};
    for (NSString *format in @[@"xml", @"zip", @"opc"]) {
        RSGraph *current = graph;
        for (int pass = 1; pass <= 2; pass++) {
            NSInteger encoding = [formats[format] integerValue];
            NSURL *url = Fresh([NSString stringWithFormat:@"%@-%@-%d.%@", name, format, pass, encoding == RSGraphArchiveOPC ? @"graphink" : @"ograph"]);
            NSError *error = nil;
            Check([RSGraphArchive writeXML:Generate(current) defaults:nil preview:nil encoding:encoding toURL:url error:&error], [NSString stringWithFormat:@"Production write %@: %@", url.lastPathComponent, error]);
            current = Read(url, encoding);
            check(current, [NSString stringWithFormat:@"%@ %@ pass %d", name, format, pass]);
        }
        printf("PASS roundtrip-%s %s\n", format.UTF8String, name.UTF8String);
    }
}

// Arrow vertex shared by two lines; its arrow parent is the line read second.
static NSString *const ArrowJunction = @"<vertex id='a' x='0' y='0'/><vertex id='j' x='1' y='1' shape='arrow' arrow-parent='l2'/><vertex id='b' x='2' y='0' shape='arrow' arrow-parent='l1'/>"
    "<line id='l1' class='connect' method='straight'><vertices ids='j b'/></line><line id='l2' class='connect' method='straight'><vertices ids='a j'/></line>";

static void ArrowParentChecks(void)
{
    Roundtrips(Fixture(@"arrow-junction", ArrowJunction), @"arrow-junction", ^(RSGraph *graph, NSString *stage) {
        RSVertex *junction = [graph objectForIdentifier:@"j"], *end = [graph objectForIdentifier:@"b"];
        Check(junction.arrowParent == [graph objectForIdentifier:@"l2"], [stage stringByAppendingString:@": junction arrow parent l2 retained"]);
        Check(end.arrowParent == [graph objectForIdentifier:@"l1"], [stage stringByAppendingString:@": single-line arrow parent retained"]);
        Check([junction arrowParentIsLine:[graph objectForIdentifier:@"l2"]] && ![junction arrowParentIsLine:[graph objectForIdentifier:@"l1"]], [stage stringByAppendingString:@": arrowhead drawn on l2 only"]);
    });
    // A dangling or unrelated arrow-parent reference never survives load; the first parent line takes over.
    RSGraph *unrelated = Fixture(@"arrow-unrelated", @"<vertex id='a' x='0' y='0'/><vertex id='j' x='1' y='1' shape='arrow' arrow-parent='l9'/><vertex id='c' x='5' y='5'/><vertex id='d' x='6' y='5'/>"
        "<line id='l1' class='connect' method='straight'><vertices ids='a j'/></line><line id='l9' class='connect' method='straight'><vertices ids='c d'/></line>");
    Check([[unrelated objectForIdentifier:@"j"] arrowParent] == [unrelated objectForIdentifier:@"l1"], @"Unrelated arrow parent falls back to the vertex's line");
    RSGraph *missing = Fixture(@"arrow-missing", @"<vertex id='a' x='0' y='0'/><vertex id='j' x='1' y='1' shape='arrow' arrow-parent='nothing'/><line id='l1' class='connect' method='straight'><vertices ids='a j'/></line>");
    Check([[missing objectForIdentifier:@"j"] arrowParent] == [missing objectForIdentifier:@"l1"], @"Missing arrow parent keeps the historical first-line default");
    printf("PASS arrow-parent fallback\n");

    // Pasteboard unarchiving reads vertices before lines too.
    RSGraph *source = Fixture(@"arrow-paste-source", ArrowJunction);
    RSGraph *target = Fixture(@"arrow-paste-target", @"");
    NSError *error = nil;
    RSGroup *everything = [RSGroup groupWithGraph:source];
    for (NSString *identifier in @[@"a", @"j", @"b", @"l1", @"l2"]) [everything addElement:[source objectForIdentifier:identifier]];
    NSData *all = [RSGraph archivedDataWithRootObject:everything graphID:@"source" error:&error];
    Check(all != nil, error.description);
    RSGraphElement *pasted = [target unarchiveObjectWithData:all getGraphID:NULL error:&error];
    Check(pasted != nil, error.description);
    NSUInteger junctions = 0;
    for (RSGraphElement *element in [pasted elements]) {
        if (![element isKindOfClass:[RSVertex class]] || [(RSVertex *)element parentCount] != 2) continue;
        RSVertex *junction = (RSVertex *)element; junctions++;
        RSLine *parent = junction.arrowParent;
        Check(parent && [junction isParent:parent] && [parent endVertex] == junction, @"Pasted junction keeps the line that ends at it");
    }
    Check(junctions == 1, @"Pasted junction present");
    RSGroup *partial = [RSGroup groupWithGraph:source];
    for (NSString *identifier in @[@"a", @"j", @"b", @"l1"]) [partial addElement:[source objectForIdentifier:identifier]];
    NSData *partialData = [RSGraph archivedDataWithRootObject:partial graphID:@"source" error:&error];
    Check(partialData != nil, error.description);
    pasted = [source unarchiveObjectWithData:partialData getGraphID:NULL error:&error]; // Same graph: unpasted l2 still resolves by identifier.
    Check(pasted != nil, error.description);
    for (RSGraphElement *element in [pasted elements]) {
        if (![element isKindOfClass:[RSVertex class]] || [(RSVertex *)element shape] != RS_ARROW) continue;
        RSVertex *V = (RSVertex *)element;
        Check(V.arrowParent == nil || [V isParent:V.arrowParent], @"Pasted arrow parent is never a line outside the paste");
        Check(V.arrowParent != [source objectForIdentifier:@"l2"], @"Pasted junction no longer references the original l2");
    }
    printf("PASS arrow-parent pasteboard\n");
}

static void HiddenAxisTitleChecks(void)
{
    NSString *axes = @"<axis id='x' dimension='x' placement='origin'><title label='tx' visible='false'/></axis><axis id='y' dimension='y' placement='origin'><title label='ty' visible='true'/></axis>"
        "<label id='tx' x='1' y='0'><text><p><run><lit>Hidden</lit></run></p></text></label><label id='ty' x='0' y='1' rotation='90'><text><p><run><lit>Shown</lit></run></p></text></label>";
    Roundtrips(Fixture(@"axis-titles", axes), @"axis-titles", ^(RSGraph *graph, NSString *stage) {
        // One model bit: RSAxis -displayTitle is the title label's visibility.
        Check(![[graph xAxis] displayTitle] && ![[graph objectForIdentifier:@"tx"] isVisible], [stage stringByAppendingString:@": hidden title stays hidden"]);
        Check([[graph yAxis] displayTitle] && [[graph objectForIdentifier:@"ty"] isVisible], [stage stringByAppendingString:@": shown title stays shown"]);
        Check([[[graph xAxis] title] isEqual:[graph objectForIdentifier:@"tx"]] && [[[graph objectForIdentifier:@"tx"] text] isEqual:@"Hidden"], [stage stringByAppendingString:@": hidden title text retained"]);
    });
}

static void NonfiniteSnapChecks(void)
{
    // Writers historically emitted -[NSNumber stringValue] "inf"; RSDataMapper requires finite curve times.
    NSString *snap = @"<vertex id='s' x='0' y='0'/><vertex id='e' x='4' y='0'/><vertex id='v' x='0' y='0'><snapped-to><element idref='l' param='inf'/></snapped-to></vertex>"
        "<line id='l' class='connect' method='straight'><vertices ids='s e'/></line>";
    Roundtrips(Fixture(@"nonfinite-snap", snap), @"nonfinite-snap", ^(RSGraph *graph, NSString *stage) {
        RSVertex *V = [graph objectForIdentifier:@"v"];
        NSNumber *param = [V paramOfSnappedToElement:[graph objectForIdentifier:@"l"]];
        Check(param && isfinite([param doubleValue]) && [param doubleValue] == 0, [stage stringByAppendingFormat:@": nonfinite snap param reads as finite 0 (%@)", param]);
    });
}

// Generated endpoint labels and user tick-label entries follow hash order; compare the lines as a multiset.
static NSArray *Lines(NSData *xml)
{
    NSString *text = [[[NSString alloc] initWithData:xml encoding:NSUTF8StringEncoding] autorelease];
    return [[text componentsSeparatedByString:@"\n"] sortedArrayUsingSelector:@selector(compare:)];
}

// Disposable copies of historical samples: production XML/ZIP/OPC stability plus the established e12 parent.
static void SampleChecks(NSArray *paths)
{
    for (NSString *path in paths) {
        NSString *name = [[[path lastPathComponent] stringByDeletingPathExtension] stringByReplacingOccurrencesOfString:@" " withString:@"-"];
        NSError *error = nil;
        NSDictionary *archive = [RSGraphArchive readURL:[NSURL fileURLWithPath:path] error:&error];
        Check(archive != nil, [NSString stringWithFormat:@"Read %@: %@", path, error]);
        RSGraph *graph = Read([NSURL fileURLWithPath:path], [archive[@"encoding"] integerValue]);
        NSData *first = Generate(graph);
        Check([first writeToURL:Fresh([name stringByAppendingString:@"-first-load.xml"]) atomically:NO], @"First-load evidence");
        Roundtrips(graph, name, ^(RSGraph *current, NSString *stage) {
            NSData *generated = Generate(current);
            if (![Lines(generated) isEqual:Lines(first)]) [generated writeToURL:Fresh([[stage stringByReplacingOccurrencesOfString:@" " withString:@"-"] stringByAppendingString:@"-mismatch.xml"]) atomically:NO];
            Check([Lines(generated) isEqual:Lines(first)], [stage stringByAppendingString:@": generated XML lines identical to first load"]);
            for (RSGraphElement *element in [[current userVertexElements] elements]) {
                RSVertex *V = (RSVertex *)element;
                Check(V.arrowParent == nil || [V isParent:V.arrowParent], [stage stringByAppendingString:@": every arrow parent is one of its vertex's parents"]);
            }
            if ([name isEqual:@"changes-in-quantity"])
                Check([[current objectForIdentifier:@"e12"] arrowParent] == [current objectForIdentifier:@"e20"], [stage stringByAppendingString:@": e12 arrow parent e20 (source XML)"]);
            NSString *title = @{@"example": @"t2", @"jobs-obama": @"e6", @"playfair-original": @"e320", @"Piecewise-Function": @"e53", @"Playfair-Extension": @"e360"}[name];
            if (title) {
                RSTextLabel *label = [current objectForIdentifier:title];
                RSAxis *axis = [[current xAxis] title] == label ? [current xAxis] : [current yAxis];
                Check([axis title] == label && ![axis displayTitle] && ![label isVisible], [stage stringByAppendingFormat:@": %@ stays the hidden axis title (source <title visible=\"false\">)", title]);
            }
            if ([name isEqual:@"climate"]) {
                NSNumber *param = [[current objectForIdentifier:@"e183"] paramOfSnappedToElement:[current objectForIdentifier:@"e546"]];
                Check(param && [param doubleValue] == 0, [stage stringByAppendingString:@": e183/e546 source inf reads as finite 0"]);
            }
        });
    }
}

int main(int argc, const char *argv[])
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    @autoreleasepool {
        [NSApplication sharedApplication];
        OFController *controller = [OFController sharedController];
        Check([controller isKindOfClass:[CheckController class]], @"Runner must select the fatal CheckController");
        [controller didInitialize]; [controller startedRunning];
        Check(argc >= 2, @"Usage: checks NEW_OUTPUT_DIRECTORY [DISPOSABLE_SAMPLE_COPY...]");
        Output = @(argv[1]);
        Check([[NSFileManager defaultManager] createDirectoryAtPath:Output withIntermediateDirectories:NO attributes:nil error:NULL], @"Output directory must be new");
        Undoer = [[RSUndoer alloc] initWithOwner:[[[CheckOwner alloc] init] autorelease]];
        Graphs = [[NSMutableArray alloc] init];
        ArrowParentChecks();
        HiddenAxisTitleChecks();
        NonfiniteSnapChecks();
        NSMutableArray *samples = [NSMutableArray array];
        for (int i = 2; i < argc; i++) [samples addObject:@(argv[i])];
        SampleChecks(samples);
        for (RSGraph *graph in Graphs) [graph invalidate];
        [Undoer invalidate];
        Check([controller requestTermination] == OFControllerTerminateNow, @"Controller termination"); [controller willTerminate];
    }
    printf("COMPLETE legacy-roundtrip checks\n");
    return 0;
}
