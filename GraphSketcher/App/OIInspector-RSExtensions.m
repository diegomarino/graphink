// Copyright 2003-2013 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OIInspector-RSExtensions.h"
#import "GraphDocument.h"
#import "RSGraphView.h"


@implementation OIInspector (RSExtensions)

- (BOOL)commitEditingForDocument:(GraphDocument *)document;
{
    RSGraphView *graphView = document.graphView;
    NSWindow *window = graphView.window;
    if (!window || self.view.window != window || ![window makeFirstResponder:graphView])
        return NO;
    // Color/font panels must operate on this document, not a sidebar field editor.
    [window makeKeyWindow];
    return YES;
}

// Copied from Graffle's InspectorPanel.m
// see <bug://bugs/55083>; this is necessary to capture text field edits if another control is used. The problem is that -updateDisplay resets the values and discards any edits. Thus, sending -makeFirstResponder:nil will confirm and commit the edit. Note that setting the first responder to the control results in the focus ring drawing around the control which then results in some strange drawing issues. Since each inspector is in its own window, it is necessary to make the calling inspector key.
- (void)updateKeyWindowAndFirstResponder:(id)sender;
{
    if ([[[NSApplication sharedApplication] keyWindow] isKindOfClass:[NSPanel class]])
        [[sender window] makeKeyWindow];
    [[sender window] makeFirstResponder:nil];
}


@end
