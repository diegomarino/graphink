#import <AppKit/AppKit.h>

// Register original vector artwork before any toolbar, menu or inspector nib loads.
BOOL RSRegisterModernImages(NSBundle *bundle, NSError **error);

// Separate non-template pointer resources; legacy cursor images stay untouched.
BOOL RSRegisterModernCursors(NSBundle *bundle, NSError **error);
NSCursor *RSGraphCursor(BOOL fill);
