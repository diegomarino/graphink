// Offscreen production checks for the app side of the graphink command-line tool: File ▸ Export's data for
// each document (to compare with `graphink render`), and the Install Command-Line Tool window. No application
// delegate or launch loop.
#import "GraphDocument.h"
#import "RSGraphView.h"
#import "RSSelector.h"
#import "RSCommandLineTool.h"
#import <GraphSketcherModel/RSGraphArchive.h>
#import <OmniFoundation/OFController.h>

@interface FixtureGraphView : RSGraphView
- (void)useDocument:(GraphDocument *)document;
@end
@implementation FixtureGraphView
- (void)useDocument:(GraphDocument *)document { _document = document; }
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
        Check([NSBundle.mainBundle.bundleIdentifier hasPrefix:@"com.graphink.cliappchecks."], @"Unique fixture domain required");
        OFController *lifecycle = OFController.sharedController;
        [lifecycle didInitialize]; [lifecycle startedRunning];
        Check(NSApp.delegate == nil, @"Fixture must not install the application delegate");
        NSString *output = @(argv[1]);
        NSArray *paths = [[NSString stringWithContentsOfFile:@(argv[2]) encoding:NSUTF8StringEncoding error:NULL] componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
        NSMutableDictionary *report = [NSMutableDictionary dictionary];

        // File ▸ Export, as the save panel's completion handler produces it, from a document opened the app's way
        // and drawn in a window first (the view lays the graph out in -viewWillDraw).
        NSMutableArray *exported = [NSMutableArray array];
        for (NSString *path in paths) {
            if (!path.length) continue;
            NSError *error = nil;
            GraphDocument *document = [[[GraphDocument alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] ofType:RSGraphFileType error:&error] autorelease];
            Check(document != nil, [NSString stringWithFormat:@"Cannot open %@: %@", path, error]);
            CGSize canvas = document.graph.canvasSize;
            NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, canvas.width, canvas.height) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO] autorelease];
            window.releasedWhenClosed = NO;
            FixtureGraphView *view = [[[FixtureGraphView alloc] initWithFrame:NSMakeRect(0, 0, canvas.width, canvas.height)] autorelease];
            [view useDocument:document];
            [view setRSSelector:document.selectorObject];
            [window.contentView addSubview:view];
            view.editor = document.editor;
            [view display];
            NSString *stem = [[path lastPathComponent] stringByDeletingPathExtension];
            NSString *base = [output stringByAppendingPathComponent:[NSString stringWithFormat:@"%lu-%@", (unsigned long)exported.count, stem]];
            Write([view exportDataOfType:@"png" resolution:72], [base stringByAppendingString:@".png"]);
            Write([view exportDataOfType:@"png" resolution:144], [base stringByAppendingString:@"@144.png"]);
            Write([view exportDataOfType:@"pdf" resolution:72], [base stringByAppendingString:@".pdf"]);
            [exported addObject:@{@"document": path, @"export": base}];
            view.editor = nil;
            [view setRSSelector:nil];
            [view removeFromSuperview];
            [window close];
            [document close];
        }
        report[@"exports"] = exported;

        // Install Command-Line Tool…: the command names this bundle's tool, and Copy puts exactly it on the pasteboard.
        RSCommandLineToolWindowController *installer = [[[RSCommandLineToolWindowController alloc] initWithBundle:NSBundle.mainBundle] autorelease];
        NSString *shown = installer.commandField.stringValue;
        NSString *expected = [NSString stringWithFormat:@"sudo mkdir -p /usr/local/bin && sudo ln -sf '%@/Contents/Helpers/graphink' /usr/local/bin/graphink",
                              [NSBundle.mainBundle.bundlePath stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
        Check(installer.window != nil && [shown isEqual:expected], [NSString stringWithFormat:@"The window shows %@, expected %@", shown, expected]);
        NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
        installer.pasteboard = pasteboard;
        [installer copyCommand:nil];
        Check([[pasteboard stringForType:NSPasteboardTypeString] isEqual:expected], @"Copy did not put the command on the pasteboard");
        [pasteboard releaseGlobally];
        report[@"installCommand"] = shown;
        NSView *content = installer.window.contentView;
        content.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        [installer.window layoutIfNeeded];
        [content display];
        NSBitmapImageRep *snapshot = [content bitmapImageRepForCachingDisplayInRect:content.bounds];
        [content cacheDisplayInRect:content.bounds toBitmapImageRep:snapshot];
        Write([snapshot representationUsingType:NSBitmapImageFileTypePNG properties:@{}], [output stringByAppendingPathComponent:@"install-window.png"]);
        // A bundle path with characters the shell would expand; check-cli-app.py reads it back through sh, zsh and bash.
        NSString *odd = [output stringByAppendingPathComponent:@"Odd \"$HOME\" `x` \\ it's !! name!x.app"];
        Check([NSFileManager.defaultManager createDirectoryAtPath:[odd stringByAppendingPathComponent:@"Contents"] withIntermediateDirectories:YES attributes:nil error:NULL], @"Cannot create the odd bundle");
        report[@"oddBundle"] = odd;
        report[@"oddCommand"] = RSCommandLineToolInstallCommand([NSBundle bundleWithPath:odd]);
        Check(RSCommandLineToolLocationWarning(NSBundle.mainBundle) == nil || [NSBundle.mainBundle.bundlePath hasPrefix:@"/Volumes/"], @"Unexpected location warning");

        Check([lifecycle requestTermination] == OFControllerTerminateNow, @"Fixture lifecycle refused termination");
        [lifecycle willTerminate];
        NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL];
        Write(json, [output stringByAppendingPathComponent:@"fixture-report.json"]);
        NSLog(@"PASS File ▸ Export data for %lu documents; install window command and Copy", (unsigned long)exported.count);
    } @catch (NSException *exception) {
        NSLog(@"FAIL exception %@", exception);
        return 1;
    } }
    return 0;
}
