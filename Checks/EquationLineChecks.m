// Equation lines through production RSGraph IO and the export renderer. Windowless; no app nib, UI or
// visual acceptance implied. Modes (each output directory must be new):
//   checks OUTPUT                     every family written, reopened, rewritten and rendered (asserting)
//   checks --read PATH...             read report: READ or REFUSED, with the error (never asserts)
//   checks --draw OUTPUT              in-memory render report for each menu curve (never asserts)
//   checks --resave OUTPUT PATH...    each input rewritten as OPC, legacy XML and legacy ZIP
// --read, --draw and --resave use only API older products have too, so the same source can probe them.
#import <Cocoa/Cocoa.h>
#import <GraphSketcherModel/RSGraph.h>
#import <GraphSketcherModel/RSGraphArchive.h>
#import <GraphSketcherModel/RSUndoer.h>
#import <GraphSketcherModel/RSUndoerOwner.h>
#import <GraphSketcherModel/RSVertex.h>
#import <GraphSketcherModel/RSLine.h>
#import <GraphSketcherModel/RSEquationLine.h>
#import <GraphSketcherModel/RSImageExporter.h>
#import <OmniFoundation/OFController.h>
#include <math.h>

static void Check(BOOL value, NSString *reason) { if (!value) { fprintf(stderr, "FAIL: %s\n", reason.UTF8String); fflush(NULL); _Exit(1); } }

@interface CheckController : OFController
@end
@implementation CheckController
- (BOOL)crashOnAssertionOrUnhandledException { return YES; } // Any model assertion while reading is fatal.
@end
@interface CheckOwner : NSObject <RSUndoerOwner>
@property(nonatomic, retain) NSUndoManager *undoManager;
@end
@implementation CheckOwner
@synthesize undoManager = _undoManager;
// No graph editor is the undo target here, so changes register no undo (as when a document loads).
- (id)init { if ((self = [super init])) { _undoManager = [[NSUndoManager alloc] init]; [_undoManager disableUndoRegistration]; } return self; }
- (void)undoerPerformedChange:(RSUndoer *)undoer {}
- (void)dealloc { [_undoManager release]; [super dealloc]; }
@end

static RSUndoer *Undoer;
static NSString *Output;
static NSMutableArray *Graphs;

// Fixed canvas, margins and 0…10 ranges, so y = x^2 leaves the plot area as it does in a new document.
static NSString *const Base = @"<?xml version=\"1.0\" encoding=\"utf-8\"?><document xmlns=\"http://www.omnigroup.com/namespace/OmniGraphSketcher/v1\" app-version=\"11.0\"><graph>"
    "<canvas w='520' h='420' auto-whitespace='false'><whitespace top='20' right='20' bottom='40' left='40'/></canvas>"
    "<axis id='x' dimension='x' min='0' max='10' placement='origin'/><axis id='y' dimension='y' min='0' max='10' placement='origin'/></graph></document>";

static NSURL *Fresh(NSString *name)
{
    NSURL *url = [NSURL fileURLWithPath:[Output stringByAppendingPathComponent:name]];
    Check(![[NSFileManager defaultManager] fileExistsAtPath:url.path], [@"Refuse to overwrite " stringByAppendingString:name]);
    return url;
}
static RSGraph *Read(NSURL *url, NSError **error)
{
    NSString *type = [url.pathExtension caseInsensitiveCompare:@"ograph"] == NSOrderedSame ? RSGraphLegacyFileType : RSGraphFileType;
    RSGraph *graph = [RSGraph graphFromURL:url type:type undoer:Undoer error:error];
    if (graph) [Graphs addObject:graph];
    return graph;
}
static RSGraph *MustRead(NSURL *url)
{
    NSError *error = nil; RSGraph *graph = Read(url, &error);
    Check(graph != nil, [NSString stringWithFormat:@"Production load %@: %@", url.lastPathComponent, error]);
    return graph;
}
static NSData *Generate(RSGraph *graph)
{
    NSError *error = nil; NSData *xml = [graph generateXMLOfType:RSGraphFileType frame:CGRectZero error:&error];
    Check(xml != nil, [NSString stringWithFormat:@"Production generateXML: %@", error]);
    return xml;
}
// The base graph after one save and reopen, as a document the app has saved before. On the first load
// the model creates the hidden axis end labels and numbers them in hash order, so only a saved graph
// has stable identifiers (a property of every document, with or without equation lines).
static RSGraph *BaseGraph(NSString *name)
{
    NSURL *url = Fresh([name stringByAppendingString:@"-base.ograph"]);
    Check([[Base dataUsingEncoding:NSUTF8StringEncoding] writeToURL:url atomically:NO], @"Write disposable base fixture");
    NSURL *saved = Fresh([name stringByAppendingString:@"-base-saved.ograph"]);
    Check([Generate(MustRead(url)) writeToURL:saved atomically:NO], @"Write saved base fixture");
    return MustRead(saved);
}
static NSData *PNG(RSGraph *graph)
{
    RSImageExporter *exporter = [[[RSImageExporter alloc] initWithGraph:graph] autorelease];
    NSData *png = [exporter pngRepresentation];
    Check(png.length > 0, @"Export renderer produced a PNG");
    return png;
}
// Pixels whose RGBA bytes differ between two same-size renders.
static NSUInteger DifferentPixels(NSData *a, NSData *b)
{
    NSBitmapImageRep *x = [NSBitmapImageRep imageRepWithData:a], *y = [NSBitmapImageRep imageRepWithData:b];
    Check(x.pixelsWide == y.pixelsWide && x.pixelsHigh == y.pixelsHigh && x.bytesPerRow == y.bytesPerRow && x.bitsPerPixel == y.bitsPerPixel, @"Renders have the same geometry");
    NSUInteger count = 0, bytes = (NSUInteger)x.bitsPerPixel / 8;
    for (NSInteger row = 0; row < x.pixelsHigh; row++)
        for (NSInteger column = 0; column < x.pixelsWide; column++)
            if (memcmp(x.bitmapData + row * x.bytesPerRow + column * bytes, y.bitmapData + row * y.bytesPerRow + column * bytes, bytes)) count++;
    return count;
}
// The model writes the hidden axis end labels and their tick entries in hash order, which changes from
// one load to the next for every document (check-legacy-roundtrips.py compares the same way): the
// lines are compared as a multiset, and the equation lines' own XML must be identical and in order.
static NSArray *Lines(NSData *xml)
{
    NSString *text = [[[NSString alloc] initWithData:xml encoding:NSUTF8StringEncoding] autorelease];
    return [text componentsSeparatedByString:@"\n"];
}
static NSArray *EquationXML(NSData *xml)
{
    return [Lines(xml) filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *line, NSDictionary *bindings) {
        return [line containsString:@"class=\"equation\""] || [line containsString:@"<equation "];
    }]];
}
static BOOL SameXML(NSData *a, NSData *b)
{
    return [[Lines(a) sortedArrayUsingSelector:@selector(compare:)] isEqual:[Lines(b) sortedArrayUsingSelector:@selector(compare:)]] && [EquationXML(a) isEqual:EquationXML(b)];
}
static NSString *Number(data_p value) { return [NSString stringWithFormat:@"%.15g", value]; }
static NSArray *EquationLines(RSGraph *graph)
{
    NSMutableArray *lines = [NSMutableArray array];
    for (RSLine *L in [graph Lines]) if ([L isKindOfClass:[RSEquationLine class]]) [lines addObject:L];
    return lines;
}
static NSString *Describe(RSEquationLine *L)
{
    RSEquation e = L.equation;
    return [NSString stringWithFormat:@"%d a=%@ b=%@ c=%@ v1=%@ (%@,%@) v2=%@ (%@,%@) width=%g dash=%ld", (int)e.type, Number(e.a), Number(e.b), Number(e.c),
            [L.startVertex identifier], Number(L.startVertex.position.x), Number(L.startVertex.position.y),
            [L.endVertex identifier], Number(L.endVertex.position.x), Number(L.endVertex.position.y), (double)L.width, (long)L.dash];
}
static BOOL WriteArchive(NSData *xml, NSDictionary *defaults, RSGraphArchiveEncoding encoding, NSURL *url, NSError **error)
{
    return [RSGraphArchive writeXML:xml defaults:defaults preview:nil encoding:encoding toURL:url error:error];
}

typedef struct { const char *name; RSEquationType type; data_p a, b, c; } Case;
// The five Experimental menu curves exactly as the menu adds them, then every family (the linear one
// has no menu item) with nondefault parameters, including values without an exact decimal form.
static const Case Cases[] = {
    {"menu-square", RSEquationTypeSquare, 0, 0, 1}, {"menu-cube", RSEquationTypeCube, 0, 0, 1}, {"menu-sine", RSEquationTypeSine, 0, 0, 1},
    {"menu-gaussian", RSEquationTypeGaussian, 0, 0, 1}, {"menu-logistic", RSEquationTypeLogistic, 0, 0, 1},
    {"linear", RSEquationTypeLinear, 0.75, 1.5, 1}, {"square", RSEquationTypeSquare, 5, 2, 0.25}, {"cube", RSEquationTypeCube, 5, 5, -0.04},
    {"sine", RSEquationTypeSine, 1.0 / 3, 5, 2.5}, {"gaussian", RSEquationTypeGaussian, 4.2, 1, 6}, {"logistic", RSEquationTypeLogistic, 5, 0.1, 8},
};
static const NSUInteger MenuCases = 5, CaseCount = sizeof(Cases) / sizeof(Cases[0]);

static RSEquationLine *AddLine(RSGraph *graph, Case c)
{
    RSEquation equation = { .type = c.type, .a = c.a, .b = c.b, .c = c.c };
    RSEquationLine *line = [[[RSEquationLine alloc] initWithGraph:graph identifier:nil equation:equation] autorelease]; // As -[RSGraphView addEquationLine:].
    [graph addLine:line];
    return line;
}

// One saved, reopened and resaved document; returns the reopened graph.
static RSGraph *Roundtrip(RSGraph *graph, NSString *name, NSDictionary *defaults, NSData *baselinePNG)
{
    NSArray *before = EquationLines(graph);
    NSMutableArray *expected = [NSMutableArray array];
    for (RSEquationLine *L in before) [expected addObject:Describe(L)];
    NSData *xml1 = Generate(graph);
    NSString *text = [[[NSString alloc] initWithData:xml1 encoding:NSUTF8StringEncoding] autorelease];
    Check([text componentsSeparatedByString:@"class=\"equation\""].count - 1 == before.count, [name stringByAppendingString:@": every equation line written with its class"]);
    Check([text componentsSeparatedByString:@"<equation family=\""].count - 1 == before.count, [name stringByAppendingString:@": every equation line written with its equation"]);
    Check([xml1 writeToURL:Fresh([name stringByAppendingString:@"-1.xml"]) atomically:NO], @"XML evidence");
    NSData *png1 = PNG(graph);

    NSError *error = nil;
    NSURL *url1 = Fresh([name stringByAppendingString:@"-1.graphink"]);
    Check(WriteArchive(xml1, defaults, RSGraphArchiveOPC, url1, &error), [NSString stringWithFormat:@"%@: OPC write: %@", name, error]);
    RSGraph *reopened = MustRead(url1);
    NSArray *after = EquationLines(reopened);
    Check(after.count == before.count, [name stringByAppendingString:@": equation lines reopen as equation lines"]);
    NSMutableArray *actual = [NSMutableArray array];
    for (RSEquationLine *L in after) {
        [actual addObject:Describe(L)];
        Check([L.startVertex isParent:L] && [L.endVertex isParent:L] && L.startVertex != L.endVertex, [name stringByAppendingString:@": endpoints belong to their line"]);
    }
    Check([actual isEqual:expected], [NSString stringWithFormat:@"%@: family, a, b, c, endpoints and style preserved\n  wrote %@\n  read  %@", name, expected, actual]);
    NSData *xml2 = Generate(reopened);
    if (![xml2 isEqual:xml1]) [xml2 writeToURL:Fresh([name stringByAppendingString:@"-2.xml"]) atomically:NO];
    Check(SameXML(xml1, xml2) && EquationXML(xml1).count == 2 * before.count, [name stringByAppendingString:@": write -> read -> write identical (equation lines byte-identical, axis end labels in any order)"]);
    NSURL *url2 = Fresh([name stringByAppendingString:@"-2.graphink"]);
    Check(WriteArchive(xml2, defaults, RSGraphArchiveOPC, url2, &error), [NSString stringWithFormat:@"%@: OPC rewrite: %@", name, error]);
    NSData *png2 = PNG(reopened);
    Check([png1 writeToURL:Fresh([name stringByAppendingString:@"-1.png"]) atomically:NO] && [png2 writeToURL:Fresh([name stringByAppendingString:@"-2.png"]) atomically:NO], @"PNG evidence");
    Check([png2 isEqual:png1], [name stringByAppendingString:@": reopened render byte-identical"]);
    NSUInteger drawn = DifferentPixels(png1, baselinePNG);
    Check(drawn >= 50, [NSString stringWithFormat:@"%@: the curve draws (%lu pixels differ from the empty graph)", name, (unsigned long)drawn]);

    // Legacy containers cannot carry the required feature: refused, nothing written.
    for (NSNumber *encoding in @[@(RSGraphArchiveLegacyXML), @(RSGraphArchiveLegacyZIP)]) {
        NSURL *legacy = Fresh([NSString stringWithFormat:@"%@-legacy-%@.ograph", name, encoding]);
        error = nil;
        Check(!WriteArchive(xml1, nil, encoding.integerValue, legacy, &error) && [error.domain isEqual:@"GraphinkPackage"] && error.code == 2, [NSString stringWithFormat:@"%@: legacy encoding %@ refused as unsupported (%@)", name, encoding, error]);
        Check(![[NSFileManager defaultManager] fileExistsAtPath:legacy.path], [name stringByAppendingString:@": refused legacy write leaves no file"]);
    }
    // Legacy XML holding an equation line (hand-made or from a pasteboard) still reads, without assertions.
    NSURL *raw = Fresh([name stringByAppendingString:@"-raw.ograph"]);
    Check([xml1 writeToURL:raw atomically:NO], @"Raw legacy XML");
    NSMutableArray *legacyRead = [NSMutableArray array];
    for (RSEquationLine *L in EquationLines(MustRead(raw))) [legacyRead addObject:Describe(L)];
    Check([legacyRead isEqual:expected], [name stringByAppendingString:@": legacy XML reads the same equation lines"]);
    printf("PASS roundtrip %s: %lu equation line(s), XML and render identical (XML byte-identical: %s), %lu pixels drawn, legacy writes refused\n", name.UTF8String, (unsigned long)before.count, [xml2 isEqual:xml1] ? "yes" : "no, axis end labels reordered", (unsigned long)drawn);
    return reopened;
}

static void MainChecks(void)
{
    NSData *baseline = PNG(BaseGraph(@"empty"));
    Check([baseline writeToURL:Fresh(@"empty.png") atomically:NO], @"Baseline PNG");
    NSError *error = nil;
    // Without equation lines nothing changes: no token (checked by the runner) and legacy writes still work.
    NSData *emptyXML = Generate(BaseGraph(@"plain"));
    Check(WriteArchive(emptyXML, nil, RSGraphArchiveOPC, Fresh(@"plain.graphink"), &error), [NSString stringWithFormat:@"Plain OPC write: %@", error]);
    Check(WriteArchive(emptyXML, nil, RSGraphArchiveLegacyXML, Fresh(@"plain-legacy.ograph"), &error), [NSString stringWithFormat:@"Plain legacy XML write: %@", error]);
    Check(WriteArchive(emptyXML, nil, RSGraphArchiveLegacyZIP, Fresh(@"plain-legacy-zip.ograph"), &error), [NSString stringWithFormat:@"Plain legacy ZIP write: %@", error]);

    for (NSUInteger i = 0; i < CaseCount; i++) {
        NSString *name = @(Cases[i].name);
        RSGraph *graph = BaseGraph(name);
        AddLine(graph, Cases[i]);
        Roundtrip(graph, name, nil, baseline);
    }
    // All six families in one document, with creation defaults: both features, in order.
    RSGraph *all = BaseGraph(@"all");
    for (NSUInteger i = MenuCases; i < CaseCount; i++) AddLine(all, Cases[i]);
    RSGraph *reopened = Roundtrip(all, @"all", @{@"font-name": @"HelveticaNeue"}, baseline);
    // Removing the last equation line drops the feature again (checked by the runner).
    for (RSLine *L in EquationLines(reopened)) [reopened removeLine:L];
    Check(WriteArchive(Generate(reopened), nil, RSGraphArchiveOPC, Fresh(@"removed.graphink"), &error), [NSString stringWithFormat:@"Write after removal: %@", error]);
    Check(EquationLines(MustRead([NSURL fileURLWithPath:[Output stringByAppendingPathComponent:@"removed.graphink"]])).count == 0, @"No equation line after removal");
    printf("PASS equation lines removed: document saved and reopened\n");
}

static void ReadReport(NSArray *paths)
{
    for (NSString *path in paths) {
        NSError *error = nil;
        NSURL *url = [NSURL fileURLWithPath:path];
        RSGraph *graph = [RSGraphArchive readURL:url error:&error] ? Read(url, &error) : nil;
        if (!graph) {
            printf("REFUSED %s domain=%s code=%ld description=%s reason=%s\n", path.lastPathComponent.UTF8String, error.domain.UTF8String, (long)error.code,
                   error.localizedDescription.UTF8String, [error.userInfo[NSLocalizedFailureReasonErrorKey] description].UTF8String);
            continue;
        }
        NSUInteger connect = 0;
        for (RSLine *L in [graph Lines]) if ([NSStringFromClass([L class]) isEqual:@"RSConnectLine"]) connect++;
        printf("READ %s lines=%lu equation=%lu connect=%lu vertices=%lu\n", path.lastPathComponent.UTF8String, (unsigned long)[[graph Lines] count],
               (unsigned long)EquationLines(graph).count, (unsigned long)connect, (unsigned long)[[graph Vertices] count]);
    }
}

static void DrawReport(void)
{
    NSData *baseline = PNG(BaseGraph(@"empty"));
    Check([baseline writeToURL:Fresh(@"empty.png") atomically:NO], @"Baseline PNG");
    for (NSUInteger i = 0; i < MenuCases; i++) {
        RSGraph *graph = BaseGraph(@(Cases[i].name));
        AddLine(graph, Cases[i]);
        NSData *png = PNG(graph);
        Check([png writeToURL:Fresh([@(Cases[i].name) stringByAppendingString:@".png"]) atomically:NO], @"PNG evidence");
        printf("DRAW %s pixels-differing-from-empty=%lu identical-to-empty=%s\n", Cases[i].name, (unsigned long)DifferentPixels(png, baseline), [png isEqual:baseline] ? "yes" : "no");
    }
}

// Each input written as OPC, legacy XML and legacy ZIP twice: from its archive's own XML bytes ("raw",
// comparable byte for byte across builds) and from the regenerated model XML ("gen").
static void Resave(NSArray *paths)
{
    for (NSString *path in paths) {
        NSError *error = nil;
        NSString *name = [[path lastPathComponent] stringByDeletingPathExtension];
        NSURL *input = [NSURL fileURLWithPath:path];
        NSDictionary *archive = [RSGraphArchive readURL:input error:&error];
        RSGraph *graph = archive ? Read(input, &error) : nil;
        if (!graph) { printf("UNREADABLE %s %s\n", path.lastPathComponent.UTF8String, error.description.UTF8String); continue; }
        NSDictionary *sources = @{@"raw": @[archive[@"xml"], archive[@"defaults"] ?: @{}], @"gen": @[Generate(graph), graph.creationDefaults ?: @{}]};
        NSDictionary *formats = @{@"opc.graphink": @(RSGraphArchiveOPC), @"xml.ograph": @(RSGraphArchiveLegacyXML), @"zip.ograph": @(RSGraphArchiveLegacyZIP)};
        for (NSString *source in sources) for (NSString *suffix in formats) {
            RSGraphArchiveEncoding encoding = [formats[suffix] integerValue];
            NSURL *url = Fresh([NSString stringWithFormat:@"%@.%@-%@", name, source, suffix]);
            NSDictionary *defaults = encoding == RSGraphArchiveOPC && [sources[source][1] count] ? sources[source][1] : nil;
            Check(WriteArchive(sources[source][0], defaults, encoding, url, &error), [NSString stringWithFormat:@"Resave %@: %@", url.lastPathComponent, error]);
        }
        printf("RESAVED %s\n", path.lastPathComponent.UTF8String);
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
        Check(argc >= 2, @"Usage: checks OUTPUT | --read PATH... | --draw OUTPUT | --resave OUTPUT PATH...");
        NSString *mode = @(argv[1]);
        Undoer = [[RSUndoer alloc] initWithOwner:[[[CheckOwner alloc] init] autorelease]];
        Graphs = [[NSMutableArray alloc] init];
        NSMutableArray *rest = [NSMutableArray array];
        for (int i = 2; i < argc; i++) [rest addObject:@(argv[i])];
        if ([mode isEqual:@"--read"]) {
            ReadReport(rest);
        } else {
            Check(![mode hasPrefix:@"--"] || rest.count >= 1, @"Missing output directory");
            Output = [mode hasPrefix:@"--"] ? rest[0] : mode;
            Check([[NSFileManager defaultManager] createDirectoryAtPath:Output withIntermediateDirectories:NO attributes:nil error:NULL], @"Output directory must be new");
            if ([mode isEqual:@"--draw"]) DrawReport();
            else if ([mode isEqual:@"--resave"]) Resave([rest subarrayWithRange:NSMakeRange(1, rest.count - 1)]);
            else { Check(![mode hasPrefix:@"--"], @"Unknown mode"); MainChecks(); }
        }
        for (RSGraph *graph in Graphs) [graph invalidate];
        [Undoer invalidate];
        Check([controller requestTermination] == OFControllerTerminateNow, @"Controller termination"); [controller willTerminate];
    }
    printf("COMPLETE equation-line checks\n");
    return 0;
}
