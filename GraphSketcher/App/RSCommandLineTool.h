#import <Cocoa/Cocoa.h>

// Graphink ▸ Install Command-Line Tool…: the `graphink` tool ships inside the app, at
// Contents/Helpers/graphink. The app is sandboxed, so it cannot link the tool into /usr/local/bin
// or ask for an administrator password: the window shows the command that does it, for the copy of
// the app that is running, with a Copy button. The app itself writes nothing.

// <bundle>/Contents/Helpers/graphink
NSString *RSCommandLineToolPath(NSBundle *bundle);
// sudo mkdir -p /usr/local/bin && sudo ln -sf '<tool>' /usr/local/bin/graphink (single-quoted, ' as '\'')
NSString *RSCommandLineToolInstallCommand(NSBundle *bundle);
// A note when the running copy is a poor link target (a disk image, or a translocated copy), else nil.
NSString *RSCommandLineToolLocationWarning(NSBundle *bundle);

@interface RSCommandLineToolWindowController : NSWindowController
- (id)initWithBundle:(NSBundle *)bundle;
@property(nonatomic, readonly) NSString *command;
@property(nonatomic, readonly) NSTextField *commandField;
@property(nonatomic, retain) NSPasteboard *pasteboard;  // where Copy puts the command; the general pasteboard
- (IBAction)copyCommand:(id)sender;
@end
