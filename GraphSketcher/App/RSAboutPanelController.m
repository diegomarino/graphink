#import <AppKit/AppKit.h>
#import <OmniAppKit/OAAboutPanelController.h>

@interface OAAboutPanelController (RSLinkHandling) <NSTextViewDelegate>
@end

@interface RSAboutPanelController : OAAboutPanelController
@end

@implementation RSAboutPanelController

- (BOOL)textView:(NSTextView *)textView clickedOnLink:(id)link atIndex:(NSUInteger)charIndex;
{
    NSURL *noticesURL = [[NSBundle mainBundle] URLForResource:@"ThirdPartyNotices" withExtension:@"html"];
    if (![link isKindOfClass:[NSURL class]] || ![[link absoluteURL] isEqual:noticesURL])
        return [super textView:textView clickedOnLink:link atIndex:charIndex];

    // TextKit reveals file links in Finder; choose the web browser explicitly.
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    NSURL *browserURL = [workspace URLForApplicationToOpenURL:[NSURL URLWithString:@"https://example.com"]];
    if (browserURL == nil) {
        NSLog(@"Unable to open bundled notices: no default web browser is available.");
        return YES;
    }
    [workspace openURLs:@[noticesURL] withApplicationAtURL:browserURL configuration:[NSWorkspaceOpenConfiguration configuration] completionHandler:^(NSRunningApplication *application, NSError *error) {
        if (error)
            NSLog(@"Unable to open bundled notices: %@", error);
    }];
    return YES;
}

@end
