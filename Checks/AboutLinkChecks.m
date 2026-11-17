// Non-GUI contract check: intercept workspace dispatch; never launch a browser or Finder.
#import <AppKit/AppKit.h>
#import <OmniAppKit/OAAboutPanelController.h>
#import <objc/runtime.h>

static NSURL *openedURL, *openedApplication;
static NSUInteger reveals, queries;
static BOOL missingBrowser, failOpen;

@interface WorkspaceRecorder : NSObject
@end
@implementation WorkspaceRecorder
- (NSURL *)URLForApplicationToOpenURL:(NSURL *)url
{
    NSCAssert([url.scheme isEqual:@"https"], @"Resolve the default web browser, not the HTML file association");
    queries++;
    return missingBrowser ? nil : [NSURL fileURLWithPath:@"/test/Default Browser.app"];
}
- (void)openURLs:(NSArray *)urls withApplicationAtURL:(NSURL *)application configuration:(NSWorkspaceOpenConfiguration *)configuration completionHandler:(void (^)(NSRunningApplication *, NSError *))completion
{
    NSCAssert(urls.count == 1, @"One notices document");
    openedURL = [urls.firstObject copy];
    openedApplication = [application copy];
    if (failOpen && completion)
        completion(nil, [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoPermissionError userInfo:nil]);
}
- (BOOL)selectFile:(NSString *)path inFileViewerRootedAtPath:(NSString *)root
{
    reveals++;
    return YES;
}
- (void)activateFileViewerSelectingURLs:(NSArray *)urls
{
    reveals++;
}
- (BOOL)openURL:(NSURL *)url
{
    NSCAssert(NO, @"Unexpected default-app dispatch");
    return NO;
}
@end

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        // Do not call NSApplication/run, load a panel nib, or invoke real workspace opens.
        NSBundle *bundle = [NSBundle mainBundle];
        NSString *className = [bundle objectForInfoDictionaryKey:@"OAAboutPanelControllerClass"] ?: @"OAAboutPanelController";
        OAAboutPanelController<NSTextViewDelegate> *controller = [NSClassFromString(className) new];
        NSCAssert(controller != nil, @"Configured About controller must exist");
        [controller addContentVariantFromMainBundleFile:@"Credits" ofType:@"html"];
        NSAttributedString *credits = controller.contentVariants.firstObject;
        NSCAssert(credits != nil, @"Import real Credits using the production importer");
        NSCAssert([credits.string containsString:@"Based on GraphSketcher / OmniGraphSketcher"], @"Additive provenance must import");
        NSDictionary *currentLinks = @{@"Graphink repository": @"https://github.com/diegomarino/graphink", @"Graphink documentation": @"https://diegomarino.github.io/graphink/"};
        for (NSString *label in currentLinks) {
            NSRange currentRange = [credits.string rangeOfString:label];
            NSCAssert(currentRange.location != NSNotFound, @"Current Graphink link must import: %@", label);
            id currentURL = [credits attribute:NSLinkAttributeName atIndex:currentRange.location effectiveRange:NULL];
            NSCAssert([[currentURL absoluteString] isEqual:currentLinks[label]], @"Current link target changed: %@", label);
            NSCAssert(![controller textView:[NSTextView new] clickedOnLink:currentURL atIndex:currentRange.location], @"Keep native HTTPS handling");
        }
        NSRange upstreamRange = [credits.string rangeOfString:@"Original GraphSketcher repository"];
        NSCAssert(upstreamRange.location != NSNotFound, @"Original upstream link must import");
        id upstream = [credits attribute:NSLinkAttributeName atIndex:upstreamRange.location effectiveRange:NULL];
        NSCAssert([[upstream absoluteString] isEqual:@"https://github.com/graphsketcher/GraphSketcher"], @"Link must target original upstream");
        NSCAssert(![controller textView:[NSTextView new] clickedOnLink:upstream atIndex:upstreamRange.location], @"Preserve native HTTPS link handling");
        NSRange range = [credits.string rangeOfString:@"Licenses and acknowledgments"];
        NSCAssert(range.location != NSNotFound, @"Credits link exists");
        id link = [credits attribute:NSLinkAttributeName atIndex:range.location effectiveRange:NULL];
        NSURL *expected = [bundle URLForResource:@"ThirdPartyNotices" withExtension:@"html"];
        NSCAssert([link isKindOfClass:[NSURL class]] && [[link absoluteURL] isEqual:expected], @"Bundled relative link resolves after relocation");
        NSError *error = nil;
        NSAttributedString *notices = [[NSAttributedString alloc] initWithURL:expected options:@{} documentAttributes:NULL error:&error];
        NSCAssert(notices != nil, @"Import packaged notices: %@", error);
        __block NSUInteger originalLicenseLinks = 0;
        [notices enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0, notices.length) options:0 usingBlock:^(id value, NSRange linkRange, BOOL *stop) {
            if ([value isKindOfClass:[NSURL class]] && [[[value absoluteURL] lastPathComponent] isEqual:@"OmniSourceLicense.html"]) {
                NSCAssert([[value absoluteURL] isEqual:[bundle URLForResource:@"OmniSourceLicense" withExtension:@"html"]], @"Original license resolves within the bundle");
                originalLicenseLinks++;
            }
        }];
        NSCAssert(originalLicenseLinks == 2, @"Both original-license links remain accessible");
        NSTextView *view = [NSTextView new];
        view.delegate = controller;
        view.editable = NO;
        view.selectable = YES;
        [view.textStorage setAttributedString:credits];
        id recorder = [WorkspaceRecorder new];
        Method method = class_getClassMethod([NSWorkspace class], @selector(sharedWorkspace));
        method_setImplementation(method, imp_implementationWithBlock(^id(id receiver) { return recorder; }));
        [view clickedOnLink:link atIndex:range.location];
        NSLog(@"Dispatch: browser queries=%lu, Finder reveals=%lu, opened=%@", queries, reveals, openedURL);
        NSCAssert([openedURL isEqual:expected] && openedApplication != nil && reveals == 0, @"Notices must go to browser, never Finder");
        NSCAssert(![controller textView:view clickedOnLink:[NSURL URLWithString:@"https://example.com"] atIndex:0], @"Keep upstream web-link behavior");
        NSCAssert(![controller textView:view clickedOnLink:[NSURL fileURLWithPath:@"/tmp/ThirdPartyNotices.html"] atIndex:0], @"Do not intercept unrelated files");
        NSCAssert(![controller textView:view clickedOnLink:@"unrelated" atIndex:0], @"Keep upstream non-URL behavior");
        openedURL = nil;
        missingBrowser = YES;
        NSCAssert([controller textView:view clickedOnLink:link atIndex:range.location], @"No browser must still consume the click");
        NSCAssert(openedURL == nil && reveals == 0, @"No Finder fallback on failure");
        missingBrowser = NO;
        failOpen = YES;
        NSCAssert([controller textView:view clickedOnLink:link atIndex:range.location], @"Open failure must still consume the click");
        NSCAssert(reveals == 0, @"No Finder fallback on async failure");
        NSLog(@"PASS About link contract (workspace recorded, no actual browser acceptance)");
    }
    return 0;
}
