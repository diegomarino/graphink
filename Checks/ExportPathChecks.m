// Offscreen fixture for the app's view-based drawing paths, built by Checks/check-export-paths.py from the
// production objects of any revision (the products under test, and a base revision such as main, so the
// paths can be compared before and after a change to the drawing code). It uses only API that predates
// RSGraphExport. For each document, opened the app's way and drawn once in an offscreen window, it writes:
//   NAME.png, NAME@144.png  the graph view's raster export (-rasterDataOfType:resolution:)
//   NAME.view.pdf           the graph view's PDF (-dataWithPDFInsideRect:, File > Export's PDF before RSGraphExport)
//   NAME.copy.pdf/.png/.tiff  Edit > Copy as Image, from a private pasteboard (PNG and TIFF only when the
//                           view can be captured, which needs an on-screen window)
//   NAME.saved.graphink     the document saved (its preview.pdf is drawn by the view)
// Everything in the graph is selected first: none of these may draw the selection or other screen-only state.
#import "GraphDocument.h"
#import "RSGraphView.h"
#import "RSSelector.h"
#import <GraphSketcherModel/RSGraphArchive.h>
#import <OmniFoundation/OFController.h>

@interface FixtureGraphView : RSGraphView
- (void)useDocument:(GraphDocument *)document;
@end
@implementation FixtureGraphView
- (void)useDocument:(GraphDocument *)document { _document = document; }
@end

@interface FixtureDocument : GraphDocument
- (void)useGraphView:(RSGraphView *)view;
@end
@implementation FixtureDocument
- (void)useGraphView:(RSGraphView *)view { _graphView = view; }
@end

static void Check(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL %@", message); exit(1); }
}

static void Write(NSData *data, NSString *path) {
    NSError *error = nil;
    Check(data.length && [data writeToFile:path options:NSDataWritingAtomic error:&error], [NSString stringWithFormat:@"Cannot write %@: %@", path, error]);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool { @try {
        Check(argc >= 3, @"Usage: checks OUTPUT LIST (one document path per line)");
        [NSApplication sharedApplication];
        Check([NSBundle.mainBundle.bundleIdentifier hasPrefix:@"com.graphink.exportpathchecks."], @"Unique fixture domain required");
        OFController *lifecycle = OFController.sharedController;
        [lifecycle didInitialize]; [lifecycle startedRunning];
        Check(NSApp.delegate == nil, @"Fixture must not install the application delegate");
        NSString *output = @(argv[1]);
        NSArray *paths = [[NSString stringWithContentsOfFile:@(argv[2]) encoding:NSUTF8StringEncoding error:NULL] componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
        NSMutableArray *written = [NSMutableArray array];
        NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
        for (NSString *path in paths) {
            if (!path.length) continue;
            NSError *error = nil;
            FixtureDocument *document = [[[FixtureDocument alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] ofType:RSGraphFileType error:&error] autorelease];
            Check(document != nil, [NSString stringWithFormat:@"Cannot open %@: %@", path, error]);
            CGSize canvas = document.graph.canvasSize;
            NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, canvas.width, canvas.height) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO] autorelease];
            window.releasedWhenClosed = NO;
            FixtureGraphView *view = [[[FixtureGraphView alloc] initWithFrame:NSMakeRect(0, 0, canvas.width, canvas.height)] autorelease];
            [view useDocument:document];
            [document useGraphView:view];
            [view setRSSelector:document.selectorObject];
            [window.contentView addSubview:view];
            view.editor = document.editor;
            [view display];
            [view selectAll:nil];
            Check([document.selectorObject selected], [NSString stringWithFormat:@"%@: selecting everything selected nothing", path]);
            [view display];

            NSString *base = [output stringByAppendingPathComponent:[NSString stringWithFormat:@"%lu-%@", (unsigned long)written.count, path.lastPathComponent.stringByDeletingPathExtension]];
            [(id)view commitEditing];  // NSEditor's; deprecated on NSView only
            [view setDrawingToScreen:NO];
            Write([view rasterDataOfType:NSBitmapImageFileTypePNG resolution:72], [base stringByAppendingString:@".png"]);
            Write([view rasterDataOfType:NSBitmapImageFileTypePNG resolution:144], [base stringByAppendingString:@"@144.png"]);
            Write([view dataWithPDFInsideRect:view.bounds], [base stringByAppendingString:@".view.pdf"]);
            [view setDrawingToScreen:YES];

            [document copyAsImageWithPasteboard:pasteboard];
            Write([pasteboard dataForType:NSPasteboardTypePDF], [base stringByAppendingString:@".copy.pdf"]);
            // Copy's PNG and TIFF come from -initWithFocusedViewRect:, which reads a window's backing store and returns
            // nothing for a window that is not on screen; they are written only when there is data.
            NSMutableDictionary *rasters = [NSMutableDictionary dictionary];
            for (NSString *type in @[NSPasteboardTypePNG, NSPasteboardTypeTIFF]) {
                NSData *data = [pasteboard dataForType:type];
                NSString *extension = [type isEqual:NSPasteboardTypePNG] ? @"png" : @"tiff";
                rasters[extension] = @(data.length > 0);
                if (data.length) Write(data, [base stringByAppendingFormat:@".copy.%@", extension]);
            }

            NSURL *saved = [NSURL fileURLWithPath:[base stringByAppendingString:@".saved.graphink"]];
            Check([document writeToURL:saved ofType:RSGraphFileType error:&error], [NSString stringWithFormat:@"Cannot save %@: %@", saved.path, error]);
            Check([document.selectorObject selected], [NSString stringWithFormat:@"%@: the selection was lost", path]);

            [written addObject:@{@"document": path, @"base": base, @"canvas": @[@(canvas.width), @(canvas.height)], @"copyRasters": rasters}];
            [document useGraphView:nil];
            view.editor = nil;
            [view setRSSelector:nil];
            [view removeFromSuperview];
            [window close];
            [document close];
        }
        [pasteboard releaseGlobally];
        Check([lifecycle requestTermination] == OFControllerTerminateNow, @"Fixture lifecycle refused termination");
        [lifecycle willTerminate];
        NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"documents": written} options:NSJSONWritingPrettyPrinted error:NULL];
        Write(json, [output stringByAppendingPathComponent:@"fixture-report.json"]);
        NSLog(@"PASS export paths for %lu documents", (unsigned long)written.count);
    } @catch (NSException *exception) {
        NSLog(@"FAIL exception %@", exception);
        return 1;
    } }
    return 0;
}
