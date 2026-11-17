// Copyright 2003-2013 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFPreference.h>

@class OAFontDescriptor, NSColor;

@interface OFPreferenceWrapper (RSExtensions)

- (OAFontDescriptor *)fontDescriptorForKey:(NSString *)defaultName;
- (void)setFontDescriptor:(OAFontDescriptor *)fontDescriptor forKey:(NSString *)defaultName;

// Keeps the existing RGB preference when the native color cannot be represented.
- (void)setColorIfConvertible:(NSColor *)color forKey:(NSString *)defaultName;

- (CGSize)sizeForKey:(NSString *)defaultName;

@end
