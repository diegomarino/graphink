#import "GraphinkCLI.h"
#import <ImageIO/ImageIO.h>
#import <OmniFoundation/OmniFoundation.h>
#import <GraphSketcherModel/RSGraphArchive.h>
#import <GraphSketcherModel/RSGraphRenderer.h>
#import <GraphSketcherModel/RSDataMapper.h>
#import <GraphSketcherModel/RSUndoer.h>
#import <GraphSketcherModel/RSUndoerOwner.h>
#import "RSStylePresets.h"

NSString * const GICErrorName = @"GraphinkCLIError";

void GICFail(NSString *format, ...)
{
    va_list args; va_start(args, format);
    NSString *reason = [[[NSString alloc] initWithFormat:format arguments:args] autorelease];
    va_end(args);
    [NSException raise:GICErrorName format:@"%@", reason];
}

// The tools' controller (OFControllerClass in the bundle's Info.plist): their own errors are reported as one line,
// not logged with a stack trace like an unexpected exception.
@interface GICController : OFController
@end
@implementation GICController
- (BOOL)shouldLogException:(NSException *)exception mask:(NSUInteger)aMask
{
    return ![exception.name isEqual:GICErrorName] && [super shouldLogException:exception mask:aMask];
}
@end

void GICStart(void)
{
    [NSApplication sharedApplication];
    [NSColor setIgnoresAlpha:NO];
    OFController *controller = [OFController sharedController];
    if (![controller isKindOfClass:GICController.class]) GICFail(@"Run the tool from its bundle (tools/cli/build.sh)");
    [controller didInitialize];
    [controller startedRunning];
    NSError *error = nil;
    // Sketch and Chalkboard documents name Kalam; without it AppKit would substitute another face.
    if (!RSRegisterStyleFonts([NSBundle mainBundle], &error))
        GICFail(@"Cannot register the bundled style fonts: %@", error.localizedDescription);
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

+ (GICDocument *)newDocument
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
    // The graph view's bounds are the canvas: RSGraphView -setEditor: and -windowDidResize.
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

// RSGraphView -drawRect: with drawingToScreen off: background, then every element; nothing else.
static void Draw(GICDocument *document, CGContextRef context)
{
    [NSGraphicsContext saveGraphicsState];
    @try {
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:context flipped:NO]];
        [document layOut];
        RSGraphEditor *editor = document.editor;
        [editor.mapper resetCurveCache];
        [editor.renderer drawBackgroundWithColor:document.graph.backgroundColor];
        [editor.renderer drawAllGraphElementsExcept:nil];
        [[NSGraphicsContext currentContext] flushGraphics];
    } @finally {
        [NSGraphicsContext restoreGraphicsState];
    }
}

NSData *GICPDFData(GICDocument *document)
{
    CGSize size = document.graph.canvasSize;
    if (!(size.width > 0 && size.height > 0)) GICFail(@"The document has an empty canvas");
    NSMutableData *data = [NSMutableData data];
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((CFMutableDataRef)data);
    CGRect box = CGRectMake(0, 0, size.width, size.height);
    NSDictionary *info = @{(id)kCGPDFContextCreator:@"Graphink"};
    CGContextRef context = CGPDFContextCreate(consumer, &box, (CFDictionaryRef)info);
    CGDataConsumerRelease(consumer);
    if (!context) GICFail(@"Cannot create a PDF context");
    CGPDFContextBeginPage(context, NULL);
    @try { Draw(document, context); }
    @finally {
        CGPDFContextEndPage(context); CGPDFContextClose(context); CGContextRelease(context);
    }
    return data;
}

CGSize GICRasterPixelSize(CGSize points, CGFloat dpi)
{
    // RSRasterPixelSize (RSPageGeometry.m).
    return CGSizeMake(MAX(1, round(points.width * dpi / 72)), MAX(1, round(points.height * dpi / 72)));
}

NSData *GICRasterData(GICDocument *document, CGFloat dpi, NSString *typeIdentifier)
{
    // RSGraphView -bitmapImageRepWithResolution: and -rasterDataOfType:resolution:, without the double scale.
    CGSize points = document.graph.canvasSize;
    if (!(points.width > 0 && points.height > 0)) GICFail(@"The document has an empty canvas");
    CGSize pixels = GICRasterPixelSize(points, dpi);
    if (pixels.width * pixels.height > 400e6) GICFail(@"%.0f × %.0f px is too large; lower --dpi or --scale", pixels.width, pixels.height);
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)pixels.width pixelsHigh:(NSInteger)pixels.height
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0] autorelease];
    if (!rep) GICFail(@"Cannot allocate a %.0f × %.0f px image", pixels.width, pixels.height);
    [rep setSize:points];
    NSGraphicsContext *graphics = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    if (!graphics) GICFail(@"Cannot create a bitmap context");
    CGContextRef context = graphics.CGContext;
    // The context already maps the rep's point size onto its pixels (its CTM scales by pixels / points). RSGraphView
    // scales once more, which draws only the lower-left part of the page above 72 DPI; this does not.
    CGAffineTransform ctm = CGContextGetCTM(context);
    if (fabs(ctm.a - pixels.width / points.width) > 1e-6 || fabs(ctm.d - pixels.height / points.height) > 1e-6)
        CGContextScaleCTM(context, pixels.width / points.width / ctm.a, pixels.height / points.height / ctm.d);
    Draw(document, context);

    NSMutableDictionary *properties = [NSMutableDictionary dictionaryWithDictionary:@{(id)kCGImagePropertyDPIWidth:@(dpi), (id)kCGImagePropertyDPIHeight:@(dpi)}];
    if ([typeIdentifier isEqual:@"public.jpeg"]) properties[(id)kCGImageDestinationLossyCompressionQuality] = @1;
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((CFMutableDataRef)data, (CFStringRef)typeIdentifier, 1, NULL);
    if (!destination) GICFail(@"Cannot encode %@", typeIdentifier);
    CGImageDestinationAddImage(destination, rep.CGImage, (CFDictionaryRef)properties);
    BOOL finished = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    if (!finished) GICFail(@"Cannot encode %@", typeIdentifier);
    return data;
}

void GICWrite(NSData *data, NSString *path, BOOL overwrite, NSString *input)
{
    NSString *target = path.stringByStandardizingPath.stringByResolvingSymlinksInPath;
    if (input && [target isEqual:input.stringByStandardizingPath.stringByResolvingSymlinksInPath])
        GICFail(@"Refusing to write over the input %@", input);
    NSFileManager *files = [NSFileManager defaultManager];
    BOOL directory = NO;
    if ([files fileExistsAtPath:path isDirectory:&directory] && (directory || !overwrite))
        GICFail(@"%@ already exists; pass --force to replace it", path);
    NSError *error = nil;
    if (![data writeToFile:path options:NSDataWritingAtomic error:&error])
        GICFail(@"Cannot write %@: %@", path, error.localizedDescription);
}
