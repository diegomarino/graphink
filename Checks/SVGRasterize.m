// Offscreen WebKit rasterizer for check-svg-export.py. Never orders a window on screen.
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@interface SVGSnapshot : NSObject <WKNavigationDelegate>
@property(nonatomic) BOOL done;
@property(nonatomic) int status;
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, copy) NSString *output;
@property(nonatomic) NSSize size;
@end

@implementation SVGSnapshot
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    fprintf(stderr, "%s\n", error.description.UTF8String);
    self.status = 1;
    self.done = YES;
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    [self webView:webView didFailNavigation:navigation withError:error];
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
    // Hidden windows throttle animation frames. Wait for font loading; the snapshot itself
    // requests a rendering update, without needing a visible window or a guessed sleep.
    [webView callAsyncJavaScript:@"await document.fonts.ready; return document.fonts.status;"
                       arguments:@{} inFrame:nil inContentWorld:WKContentWorld.pageWorld completionHandler:^(id value, NSError *error) {
        if (error) {
            fprintf(stderr, "%s\n", error.description.UTF8String);
            self.status = 1; self.done = YES; return;
        }
        WKSnapshotConfiguration *config = [WKSnapshotConfiguration new];
        config.rect = NSMakeRect(0, 0, self.size.width, self.size.height);
        config.snapshotWidth = @(self.size.width * 2);
        [webView takeSnapshotWithConfiguration:config completionHandler:^(NSImage *image, NSError *snapshotError) {
            if (!image || snapshotError) {
                fprintf(stderr, "snapshot: %s\n", snapshotError.description.UTF8String);
                self.status = 1; self.done = YES; return;
            }
            // Fix the output at 2 pixels per graph point, independent of the host screen scale.
            NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)(self.size.width * 2) pixelsHigh:(NSInteger)(self.size.height * 2) bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
            rep.size = self.size;
            [NSGraphicsContext saveGraphicsState];
            NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
            [image drawInRect:NSMakeRect(0, 0, self.size.width, self.size.height)];
            [NSGraphicsContext restoreGraphicsState];
            NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            self.status = [png writeToFile:self.output atomically:YES] ? 0 : 1;
            self.done = YES;
        }];
    }];
}
@end

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc != 6 && argc != 7) {
            fputs("Usage: SVGRasterize IN.svg WIDTH HEIGHT OUT.png FONT_DIR|- [plain]\n", stderr);
            return 2;
        }
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        SVGSnapshot *snapshot = [SVGSnapshot new];
        snapshot.output = @(argv[4]);
        snapshot.size = NSMakeSize(atof(argv[2]), atof(argv[3]));
        WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistentDataStore;
        snapshot.webView = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, snapshot.size.width, snapshot.size.height) configuration:configuration];
        snapshot.webView.navigationDelegate = snapshot;
        // The view has a backing store but its window is never shown.
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(-10000, -10000, snapshot.size.width, snapshot.size.height) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        window.contentView = snapshot.webView;
        NSString *svg = [NSString stringWithContentsOfFile:@(argv[1]) encoding:NSUTF8StringEncoding error:NULL];
        if (!svg) return 2;
        NSMutableString *fonts = [NSMutableString string];
        // Fonts are supplied only by the checker, not embedded in the exported SVG. This measures
        // fidelity on a machine with Graphink's fonts available, separately from fallback behavior.
        if (strcmp(argv[5], "-") && argc == 6) {
            for (NSString *weight in @[@"Regular", @"Bold"]) {
                NSString *path = [@(argv[5]) stringByAppendingPathComponent:[NSString stringWithFormat:@"Kalam-%@.ttf", weight]];
                NSString *base64 = [[NSData dataWithContentsOfFile:path] base64EncodedStringWithOptions:0];
                if (!base64) return 2;
                [fonts appendFormat:@"@font-face{font-family:'Kalam';font-weight:%@;src:url(data:font/ttf;base64,%@)}", [weight isEqual:@"Bold"] ? @"700" : @"400", base64];
            }
        }
        NSString *html = [NSString stringWithFormat:@"<!doctype html><meta charset='utf-8'><style>%@ html,body{margin:0;padding:0;background:white}svg{display:block;width:%gpx;height:%gpx}</style>%@", fonts, snapshot.size.width, snapshot.size.height, svg];
        [snapshot.webView loadHTMLString:html baseURL:nil];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:45];
        while (!snapshot.done && deadline.timeIntervalSinceNow > 0)
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        if (!snapshot.done) { fputs("WebKit snapshot timed out\n", stderr); return 1; }
        return snapshot.status;
    }
}
