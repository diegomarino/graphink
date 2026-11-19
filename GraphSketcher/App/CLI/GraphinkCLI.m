#import "GraphinkCLI.h"
#import <mach-o/dyld.h>
#import <sys/stat.h>
#import <OmniFoundation/OmniFoundation.h>
#import <GraphSketcherModel/RSGraphArchive.h>
#import <GraphSketcherModel/RSUndoer.h>
#import <GraphSketcherModel/RSUndoerOwner.h>
#import "RSGraphExport.h"
#import "RSPageGeometry.h"
#import "RSStylePresets.h"

NSString * const GICErrorName = @"GraphinkCLIError";

void GICFail(NSString *format, ...)
{
    va_list args; va_start(args, format);
    NSString *reason = [[[NSString alloc] initWithFormat:format arguments:args] autorelease];
    va_end(args);
    [NSException raise:GICErrorName format:@"%@", reason];
}

NSString *GICVersion(void)
{
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    return [NSString stringWithFormat:@"%@ (build %@)", info[@"CFBundleShortVersionString"] ?: @"unknown", info[@"CFBundleVersion"] ?: @"unknown"];
}

// The tool's controller (OFControllerClass in the embedded Info.plist): its own errors are reported as one line,
// not logged with a stack trace like an unexpected exception.
@interface GICController : OFController
@end
@implementation GICController
- (BOOL)shouldLogException:(NSException *)exception mask:(NSUInteger)aMask
{
    return ![exception.name isEqual:GICErrorName] && [super shouldLogException:exception mask:aMask];
}
@end

NSString *GICContainingBundlePath(void)
{
    uint32_t size = 0;
    _NSGetExecutablePath(NULL, &size);
    NSMutableData *buffer = [NSMutableData dataWithLength:size];
    if (_NSGetExecutablePath(buffer.mutableBytes, &size) != 0) return nil;
    NSString *executable = [NSString stringWithUTF8String:buffer.bytes].stringByResolvingSymlinksInPath;
    // <bundle>/Contents/Helpers/graphink
    NSString *helpers = executable.stringByDeletingLastPathComponent;
    if (![helpers.lastPathComponent isEqual:@"Helpers"]) return nil;
    return helpers.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent;
}

void GICStart(void)
{
    [NSApplication sharedApplication];
    [NSColor setIgnoresAlpha:NO];
    OFController *controller = [OFController sharedController];
    if (![controller isKindOfClass:GICController.class]) GICFail(@"graphink was built without its Info.plist");
    [controller didInitialize];
    [controller startedRunning];
    // Sketch and Chalkboard documents name Kalam; without it AppKit would substitute another face.
    NSString *root = GICContainingBundlePath();
    NSBundle *resources = root ? [NSBundle bundleWithPath:root] : nil;
    NSError *error = nil;
    if (!resources || !RSRegisterStyleFonts(resources, &error))
        GICFail(@"Cannot register the style fonts of %@ (Contents/Resources/StyleFonts): %@; run graphink from Graphink.app/Contents/Helpers or the unpacked graphink-cli.zip",
                root ?: @"the bundle that contains graphink", error.localizedDescription ?: @"no such bundle");
}

void GICStop(void)
{
    OFController *controller = [OFController sharedController];
    if (controller.status <= OFControllerStatusRunning && [controller requestTermination] == OFControllerTerminateNow)
        [controller willTerminate];
}

@interface GICUndoOwner : NSObject <RSUndoerOwner>
@property(nonatomic, retain) NSUndoManager *undoManager;
@end
@implementation GICUndoOwner
@synthesize undoManager = _undoManager;
- (id)init
{
    if ((self = [super init])) { _undoManager = [[NSUndoManager alloc] init]; _undoManager.groupsByEvent = NO; }
    return self;
}
- (void)undoerPerformedChange:(RSUndoer *)undoer {}
- (void)dealloc { [_undoManager release]; [super dealloc]; }
@end

@implementation GICDocument
{
    GICUndoOwner *_owner;
    RSGraphEditor *_editor;
    NSInteger _encoding;
}
@synthesize editor = _editor, encoding = _encoding;

- (id)initWithGraph:(RSGraph *)graph undoer:(RSUndoer *)undoer owner:(GICUndoOwner *)owner encoding:(NSInteger)encoding
{
    if (!(self = [super init])) return nil;
    _owner = [owner retain];
    _editor = [[RSGraphEditor alloc] initWithGraph:graph undoer:undoer];
    _encoding = encoding;
    return self;
}

+ (GICDocument *)documentWithContentsOfFile:(NSString *)path
{
    GICUndoOwner *owner = [[[GICUndoOwner alloc] init] autorelease];
    RSUndoer *undoer = [[[RSUndoer alloc] initWithOwner:owner] autorelease];
    // The extension picks the type, as when the app opens a file; the container is detected from the bytes.
    NSString *type = [path.pathExtension caseInsensitiveCompare:@"ograph"] == NSOrderedSame ? RSGraphLegacyFileType : RSGraphFileType;
    NSError *error = nil; NSInteger encoding = -1;
    [owner.undoManager disableUndoRegistration];
    RSGraph *graph = [RSGraph graphFromURL:[NSURL fileURLWithPath:path] type:type undoer:undoer encoding:&encoding error:&error];
    [owner.undoManager enableUndoRegistration];
    if (!graph) {
        [undoer invalidate];
        GICFail(@"Cannot read %@: %@", path, error.localizedDescription ?: @"unknown error");
    }
    return [[[GICDocument alloc] initWithGraph:graph undoer:undoer owner:owner encoding:encoding] autorelease];
}

+ (GICDocument *)emptyDocument
{
    GICUndoOwner *owner = [[[GICUndoOwner alloc] init] autorelease];
    RSUndoer *undoer = [[[RSUndoer alloc] initWithOwner:owner] autorelease];
    [owner.undoManager disableUndoRegistration];
    RSGraph *graph = [[[RSGraph alloc] initWithIdentifier:nil undoer:undoer] autorelease];
    [graph setupDefault];
    graph.creationDefaults = @{};
    [owner.undoManager enableUndoRegistration];
    return [[[GICDocument alloc] initWithGraph:graph undoer:undoer owner:owner encoding:RSGraphArchiveOPC] autorelease];
}

- (RSGraph *)graph { return _editor.graph; }

- (void)layOut
{
    RSGraph *graph = _editor.graph;
    // The graph view's bounds are the canvas: RSGraphView -setEditor: and -windowDidResize, then -viewWillDraw.
    [_editor updateBounds:CGRectMake(0, 0, graph.canvasSize.width, graph.canvasSize.height)];
    [_editor prepareForDisplay];
}

- (void)invalidate
{
    [_editor invalidate];  // also invalidates the graph and the undoer
    [_editor release]; _editor = nil;
    [_owner release]; _owner = nil;
}

- (void)dealloc
{
    if (_editor) [self invalidate];
    [super dealloc];
}
@end

static NSRect Canvas(GICDocument *document)
{
    CGSize size = document.graph.canvasSize;
    if (!(size.width > 0 && size.height > 0)) GICFail(@"The document has an empty canvas");
    return NSMakeRect(0, 0, size.width, size.height);
}

NSData *GICPDFData(GICDocument *document)
{
    NSRect bounds = Canvas(document);
    [document layOut];
    NSData *data = RSGraphPDFData(document.editor, bounds);
    if (!data.length) GICFail(@"Cannot draw the PDF");
    return data;
}

NSData *GICRasterData(GICDocument *document, CGFloat dpi, NSString *typeIdentifier)
{
    NSRect bounds = Canvas(document);
    NSSize pixels = RSRasterPixelSize(bounds.size, dpi);
    if (pixels.width * pixels.height > 400e6) GICFail(@"%.0f × %.0f px is too large; lower --dpi or --scale", pixels.width, pixels.height);
    [document layOut];
    NSData *data = RSGraphRasterData(document.editor, bounds, typeIdentifier, dpi);
    if (!data.length) GICFail(@"Cannot draw a %.0f × %.0f px %@ image", pixels.width, pixels.height, typeIdentifier);
    return data;
}

void GICCheckOutput(NSString *path, BOOL overwrite, NSString *input)
{
    struct stat link, target, source;
    if (lstat(path.fileSystemRepresentation, &link) != 0) return;  // nothing there yet
    BOOL resolves = stat(path.fileSystemRepresentation, &target) == 0;
    if (input && stat(input.fileSystemRepresentation, &source) == 0) {
        BOOL same = (link.st_dev == source.st_dev && link.st_ino == source.st_ino) ||
                    (resolves && target.st_dev == source.st_dev && target.st_ino == source.st_ino);
        if (same) GICFail(@"Refusing to write over the input %@ (%@ is the same file)", input, path);
    }
    if (resolves && S_ISDIR(target.st_mode)) GICFail(@"%@ is a directory; it is never replaced", path);
    if (!overwrite) GICFail(@"%@ already exists; pass --force to replace it", path);
}

void GICWrite(NSData *data, NSString *path, BOOL overwrite, NSString *input)
{
    GICCheckOutput(path, overwrite, input);
    NSError *error = nil;
    if (![data writeToFile:path options:NSDataWritingAtomic error:&error])
        GICFail(@"Cannot write %@: %@", path, error.localizedDescription);
}
