// Copyright 2003-2013 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

// The drawing and export code here was moved from RSGraphView.m.
#import "RSGraphExport.h"
#import "RSPageGeometry.h"
#import <ImageIO/ImageIO.h>
#import <GraphSketcherModel/RSGraph.h>
#import <GraphSketcherModel/RSGraphEditor.h>
#import <GraphSketcherModel/RSGraphRenderer.h>
#import <GraphSketcherModel/RSDataMapper.h>

void RSDrawGraphForExport(RSGraphEditor *editor)
{
    [editor.mapper resetCurveCache];
    [editor.renderer drawBackgroundWithColor:editor.graph.backgroundColor];
    [editor.renderer drawAllGraphElementsExcept:nil];
}

// A plain view, so the PDF comes from AppKit's -dataWithPDFInsideRect: as it always has, without
// the graph view's screen-only state.
@interface RSGraphExportView : NSView
{
    RSGraphEditor *_editor;
}
- (id)initWithEditor:(RSGraphEditor *)editor bounds:(NSRect)bounds;
@end

@implementation RSGraphExportView

- (id)initWithEditor:(RSGraphEditor *)editor bounds:(NSRect)bounds;
{
    if (!(self = [super initWithFrame:NSMakeRect(0, 0, bounds.size.width, bounds.size.height)]))
        return nil;
    _editor = [editor retain];
    [self setBoundsOrigin:bounds.origin];
    return self;
}

- (void)dealloc;
{
    [_editor release];
    [super dealloc];
}

- (void)drawRect:(NSRect)rect;
{
    RSDrawGraphForExport(_editor);
}

@end

NSData *RSGraphPDFData(RSGraphEditor *editor, NSRect bounds)
{
    RSGraphExportView *view = [[[RSGraphExportView alloc] initWithEditor:editor bounds:bounds] autorelease];
    return [view dataWithPDFInsideRect:bounds];
}

NSBitmapImageRep *RSGraphBitmapImageRep(RSGraphEditor *editor, NSRect bounds, CGFloat dpi)
{
    NSSize pixels = RSRasterPixelSize(bounds.size, dpi);
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)pixels.width pixelsHigh:(NSInteger)pixels.height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0] autorelease];
    if (!rep)
        return nil;

    // The rep's point size records the resolution (pixels / points * 72) in exported metadata.
    [rep setSize:bounds.size];

    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    if (!context)
        return nil;

    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:context];
    CGContextRef ctx = [context CGContext];
    // The context already maps the rep's point size onto its pixels, so drawing in points fills the whole bitmap.
    CGContextTranslateCTM(ctx, -bounds.origin.x, -bounds.origin.y);
    RSDrawGraphForExport(editor);
    [context flushGraphics];
    [NSGraphicsContext restoreGraphicsState];
    return rep;
}

NSData *RSGraphRasterData(RSGraphEditor *editor, NSRect bounds, NSString *typeIdentifier, CGFloat dpi)
{
    NSMutableDictionary *properties = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                       [NSNumber numberWithDouble:dpi], (id)kCGImagePropertyDPIWidth,
                                       [NSNumber numberWithDouble:dpi], (id)kCGImagePropertyDPIHeight, nil];
    if ([typeIdentifier isEqual:@"public.jpeg"])
        [properties setObject:[NSNumber numberWithDouble:1] forKey:(id)kCGImageDestinationLossyCompressionQuality];
    else if (![typeIdentifier isEqual:@"public.png"] && ![typeIdentifier isEqual:@"public.tiff"])
        return nil;

    CGImageRef image = [RSGraphBitmapImageRep(editor, bounds, dpi) CGImage];
    if (!image)
        return nil;

    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((CFMutableDataRef)data, (CFStringRef)typeIdentifier, 1, NULL);
    if (!destination)
        return nil;
    CGImageDestinationAddImage(destination, image, (CFDictionaryRef)properties);
    BOOL finished = CGImageDestinationFinalize(destination);
    CFRelease(destination);

    return finished ? data : nil;
}
