#import "RSCommandLineTool.h"

NSString *RSCommandLineToolPath(NSBundle *bundle)
{
    return [[[bundle bundlePath] stringByAppendingPathComponent:@"Contents/Helpers"] stringByAppendingPathComponent:@"graphink"];
}

// Single quotes: nothing inside them is special, not even ! (history expansion in interactive zsh and
// bash, which still applies inside double quotes). A ' itself is written as '\'' (close, escaped quote, reopen).
static NSString *ShellQuoted(NSString *string)
{
    return [NSString stringWithFormat:@"'%@'", [string stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
}

NSString *RSCommandLineToolInstallCommand(NSBundle *bundle)
{
    // /usr/local/bin does not exist on a new Mac until something creates it.
    return [NSString stringWithFormat:@"sudo mkdir -p /usr/local/bin && sudo ln -sf %@ /usr/local/bin/graphink", ShellQuoted(RSCommandLineToolPath(bundle))];
}

NSString *RSCommandLineToolLocationWarning(NSBundle *bundle)
{
    NSString *path = [bundle bundlePath];
    if ([path hasPrefix:@"/Volumes/"])
        return NSLocalizedString(@"This copy of Graphink runs from a disk image. Move it to the Applications folder first, then choose this command again.", @"Install Command-Line Tool: app runs from a disk image");
    if ([path rangeOfString:@"/AppTranslocation/"].location != NSNotFound)
        return NSLocalizedString(@"macOS is running this copy of Graphink from a temporary location. Move it to the Applications folder, open it from there, then choose this command again.", @"Install Command-Line Tool: app is translocated");
    return nil;
}

@implementation RSCommandLineToolWindowController
{
    NSString *_command;
    NSTextField *_commandField;
    NSPasteboard *_pasteboard;
}
@synthesize command = _command, commandField = _commandField, pasteboard = _pasteboard;

static NSTextField *Label(NSString *string, NSFont *font)
{
    NSTextField *label = [NSTextField wrappingLabelWithString:string];
    label.font = font;
    label.selectable = YES;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (id)initWithBundle:(NSBundle *)bundle;
{
    NSPanel *panel = [[[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 560, 200) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:YES] autorelease];
    panel.title = NSLocalizedString(@"Install Command-Line Tool", @"Install Command-Line Tool window title");
    panel.releasedWhenClosed = NO;
    panel.hidesOnDeactivate = NO;
    if (!(self = [super initWithWindow:panel]))
        return nil;
    _command = [RSCommandLineToolInstallCommand(bundle) copy];
    _pasteboard = [[NSPasteboard generalPasteboard] retain];

    NSFont *small = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    NSTextField *intro = Label(NSLocalizedString(@"The graphink command creates and exports Graphink documents from Terminal and scripts, without opening the app. It is inside this copy of Graphink. To run it as graphink, paste this command into Terminal; it asks for your administrator password:", @"Install Command-Line Tool explanation"), [NSFont systemFontOfSize:0]);
    _commandField = [Label(_command, [NSFont userFixedPitchFontOfSize:[NSFont systemFontSize]]) retain];
    _commandField.accessibilityLabel = NSLocalizedString(@"Install command", @"Install Command-Line Tool: accessibility label of the command");
    NSString *notes = NSLocalizedString(@"Graphink cannot run this for you: it is sandboxed and changes nothing outside its own files. If you move Graphink, run the command again. To remove the tool: sudo rm /usr/local/bin/graphink.", @"Install Command-Line Tool notes");
    NSString *warning = RSCommandLineToolLocationWarning(bundle);
    NSTextField *details = Label(warning ? [NSString stringWithFormat:@"%@\n\n%@", warning, notes] : notes, small);
    details.textColor = [NSColor secondaryLabelColor];

    NSButton *copy = [NSButton buttonWithTitle:NSLocalizedString(@"Copy", @"Install Command-Line Tool: copy the command") target:self action:@selector(copyCommand:)];
    copy.keyEquivalent = @"\r";
    NSButton *done = [NSButton buttonWithTitle:NSLocalizedString(@"Done", @"Install Command-Line Tool: close the window") target:panel action:@selector(performClose:)];
    done.keyEquivalent = @"\e";
    NSStackView *buttons = [[[NSStackView alloc] init] autorelease];
    [buttons addView:done inGravity:NSStackViewGravityTrailing];
    [buttons addView:copy inGravity:NSStackViewGravityTrailing];

    NSStackView *stack = [NSStackView stackViewWithViews:@[intro, _commandField, details, buttons]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;
    stack.edgeInsets = NSEdgeInsetsMake(20, 20, 20, 20);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack setCustomSpacing:16 afterView:details];
    NSView *content = panel.contentView;
    [content addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [content.widthAnchor constraintEqualToConstant:560],
        [buttons.widthAnchor constraintEqualToAnchor:stack.widthAnchor constant:-40],
    ]];
    for (NSTextField *label in @[intro, _commandField, details])
        label.preferredMaxLayoutWidth = 520;
    [panel center];
    return self;
}

- (void)dealloc;
{
    [_command release];
    [_commandField release];
    [_pasteboard release];
    [super dealloc];
}

- (IBAction)copyCommand:(id)sender;
{
    [_pasteboard clearContents];
    [_pasteboard setString:_command forType:NSPasteboardTypeString];
}

@end
