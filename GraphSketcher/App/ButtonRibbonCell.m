// Copyright 2003-2013 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ButtonRibbonCell.h"

const CGFloat ButtonRibbonCellCellHeight = 32;

@implementation ButtonRibbonCell
- (ButtonRibbonCellPosition)position { return _position; }
- (void)setPosition:(ButtonRibbonCellPosition)position { _position = position; }
- (BOOL)pressButton { return _pressButton; }
- (void)setPressButton:(BOOL)pressButton { _pressButton = pressButton; }

- (void)awakeFromNib;
{
    self.bezelStyle = NSBezelStyleRegularSquare;
    [self setShowsStateBy:NSContentsCellMask | NSPushInCellMask];
}

- (void)drawBezelWithFrame:(NSRect)frame inView:(NSView *)controlView;
{
    // AppKit supplies appearance-aware borders, selection and disabled states.
    [super drawBezelWithFrame:frame inView:controlView];
}
@end
