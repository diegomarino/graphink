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

// Native SVG recording. The graph renderer still owns every path and label position.
#import <GraphSketcherModel/RSDrawing.h>

static NSString *RSSVGXML(NSString *text)
{
    NSMutableString *escaped = [[text mutableCopy] autorelease];
    [escaped replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:NSMakeRange(0, escaped.length)];
    return escaped;
}

static NSString *RSSVGPaint(NSColor *color, NSString *property)
{
    NSColor *rgb = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    if (!rgb) [NSException raise:NSInvalidArgumentException format:@"SVG requires an RGB-convertible color"];
    CGFloat r, g, b, a;
    [rgb getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"%@=\"rgb(%.12g%%,%.12g%%,%.12g%%)\" %@-opacity=\"%.12g\"", property, 100 * MIN(1, MAX(0, r)), 100 * MIN(1, MAX(0, g)), 100 * MIN(1, MAX(0, b)), property, a];
}

static NSString *RSSVGPath(NSBezierPath *path)
{
    NSMutableString *d = [NSMutableString string];
    for (NSInteger index = 0; index < path.elementCount; index++) {
        NSPoint p[3];
        switch ([path elementAtIndex:index associatedPoints:p]) {
            case NSBezierPathElementMoveTo:
                [d appendFormat:@"M %.12g %.12g ", p[0].x, p[0].y]; break;
            case NSBezierPathElementLineTo:
                [d appendFormat:@"L %.12g %.12g ", p[0].x, p[0].y]; break;
            case NSBezierPathElementCurveTo:
                [d appendFormat:@"C %.12g %.12g %.12g %.12g %.12g %.12g ", p[0].x, p[0].y, p[1].x, p[1].y, p[2].x, p[2].y]; break;
            case NSBezierPathElementClosePath:
                [d appendString:@"Z "]; break;
            default:
                [NSException raise:NSInvalidArgumentException format:@"Unsupported SVG path element"];
        }
    }
    return d;
}

static NSInteger RSSVGFontWeight(NSFont *font)
{
    // A Medium/Semibold face need not have NSBoldFontMask. Match AppKit's weight
    // coordinate to CSS's named weights so those faces survive the export.
    NSDictionary *traits = [font.fontDescriptor objectForKey:NSFontTraitsAttribute];
    CGFloat weight = [traits[NSFontWeightTrait] doubleValue];
    const CGFloat weights[] = {NSFontWeightUltraLight, NSFontWeightThin, NSFontWeightLight,
        NSFontWeightRegular, NSFontWeightMedium, NSFontWeightSemibold, NSFontWeightBold,
        NSFontWeightHeavy, NSFontWeightBlack};
    NSUInteger closest = 0;
    for (NSUInteger i = 1; i < sizeof(weights) / sizeof(weights[0]); i++)
        if (fabs(weight - weights[i]) < fabs(weight - weights[closest])) closest = i;
    return (NSInteger)(closest + 1) * 100;
}

@interface RSSVGDrawing : NSObject <RSDrawing>
{
    NSMutableString *_xml;
}
- (id)initWithBounds:(NSRect)bounds;
- (NSData *)data;
@end

@implementation RSSVGDrawing
- (id)initWithBounds:(NSRect)bounds
{
    if (!(self = [super init])) return nil;
    _xml = [[NSMutableString alloc] initWithFormat:@"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%.12gpt\" height=\"%.12gpt\" viewBox=\"0 0 %.12g %.12g\">\n<g transform=\"matrix(1 0 0 -1 %.12g %.12g)\">\n", bounds.size.width, bounds.size.height, bounds.size.width, bounds.size.height, -bounds.origin.x, NSMaxY(bounds)];
    return self;
}
- (void)dealloc
{
    [_xml release];
    [super dealloc];
}
- (NSData *)data
{
    return [[_xml stringByAppendingString:@"</g>\n</svg>\n"] dataUsingEncoding:NSUTF8StringEncoding];
}
- (void)strokePath:(NSBezierPath *)path color:(NSColor *)color
{
    NSString *cap = @[@"butt", @"round", @"square"][(NSUInteger)path.lineCapStyle];
    NSString *join = @[@"miter", @"round", @"bevel"][(NSUInteger)path.lineJoinStyle];
    [_xml appendFormat:@"<path d=\"%@\" fill=\"none\" %@ stroke-width=\"%.12g\" stroke-linecap=\"%@\" stroke-linejoin=\"%@\" stroke-miterlimit=\"%.12g\"", RSSVGPath(path), RSSVGPaint(color, @"stroke"), path.lineWidth, cap, join, path.miterLimit];
    NSInteger count = 0; CGFloat phase = 0;
    [path getLineDash:NULL count:&count phase:&phase];
    if (count) {
        NSMutableData *storage = [NSMutableData dataWithLength:(NSUInteger)count * sizeof(CGFloat)];
        CGFloat *dash = storage.mutableBytes;
        [path getLineDash:dash count:&count phase:&phase];
        [_xml appendString:@" stroke-dasharray=\""];
        for (NSInteger index = 0; index < count; index++) [_xml appendFormat:@"%s%.12g", index ? " " : "", dash[index]];
        [_xml appendFormat:@"\" stroke-dashoffset=\"%.12g\"", phase];
    }
    [_xml appendString:@"/>\n"];
}
- (void)fillPath:(NSBezierPath *)path color:(NSColor *)color
{
    [_xml appendFormat:@"<path d=\"%@\" %@ fill-rule=\"%@\"/>\n", RSSVGPath(path), RSSVGPaint(color, @"fill"), path.windingRule == NSWindingRuleEvenOdd ? @"evenodd" : @"nonzero"];
}
- (void)fillRect:(NSRect)rect color:(NSColor *)color
{
    [self fillPath:[NSBezierPath bezierPathWithRect:rect] color:color];
}
- (void)drawAttributedString:(NSAttributedString *)string atPoint:(NSPoint)point rotation:(CGFloat)degrees
{
    if (!string.length) return;
    // Use TextKit's actual line fragments and glyph origins. Do not guess line spacing from font size.
    NSTextStorage *storage = [[[NSTextStorage alloc] initWithAttributedString:string] autorelease];
    NSLayoutManager *layout = [[[NSLayoutManager alloc] init] autorelease];
    layout.usesFontLeading = NO; // matches NSStringDrawingUsesLineFragmentOrigin without UsesFontLeading
    [storage addLayoutManager:layout];
    NSRect measured = [string boundingRectWithSize:NSMakeSize(1e7, 1e7) options:NSStringDrawingUsesLineFragmentOrigin];
    NSTextContainer *container = [[[NSTextContainer alloc] initWithContainerSize:NSMakeSize(ceil(measured.size.width) + 1, 1e7)] autorelease];
    container.lineFragmentPadding = 0;
    [layout addTextContainer:container];
    [layout ensureLayoutForTextContainer:container];
    [_xml appendFormat:@"<g transform=\"translate(%.12g %.12g) rotate(%.12g) scale(1 -1)\">\n", point.x, point.y, degrees];
    NSUInteger glyph = 0;
    while (glyph < layout.numberOfGlyphs) {
        NSRange lineRange;
        NSRect line = [layout lineFragmentRectForGlyphAtIndex:glyph effectiveRange:&lineRange];
        NSUInteger end = NSMaxRange(lineRange);
        while (glyph < end) {
            NSUInteger character = [layout characterIndexForGlyphAtIndex:glyph];
            NSRange attributesRange;
            NSDictionary *attributes = [string attributesAtIndex:character effectiveRange:&attributesRange];
            NSRange range = NSIntersectionRange([layout glyphRangeForCharacterRange:attributesRange actualCharacterRange:NULL], NSMakeRange(glyph, end - glyph));
            if (!range.length)
                [NSException raise:NSInvalidArgumentException format:@"Cannot map SVG text glyphs to characters"];
            NSRange characters = [layout characterRangeForGlyphRange:range actualGlyphRange:NULL];
            NSString *text = [string.string substringWithRange:characters];
            // Newlines have layout meaning, not visible glyphs; preserve ordinary spaces exactly.
            text = [text stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
            if (text.length) {
                NSPoint origin = [layout locationForGlyphAtIndex:glyph];
                NSFont *font = [layout substituteFontForFont:attributes[NSFontAttributeName]];
                if (!font) font = [NSFont systemFontOfSize:12];
                NSColor *color = attributes[NSForegroundColorAttributeName] ?: [NSColor blackColor];
                NSFontTraitMask traits = [[NSFontManager sharedFontManager] traitsOfFont:font];
                NSString *stretch = (traits & NSCondensedFontMask) ? @"condensed" : (traits & NSExpandedFontMask) ? @"expanded" : @"normal";
                [_xml appendFormat:@"<text xml:space=\"preserve\" x=\"%.12g\" y=\"%.12g\" font-family=\"%@\" font-size=\"%.12g\" font-weight=\"%ld\" font-style=\"%@\" font-stretch=\"%@\" %@>%@</text>\n", line.origin.x + origin.x, line.origin.y + origin.y - measured.size.height, RSSVGXML(font.familyName), font.pointSize, (long)RSSVGFontWeight(font), (traits & NSItalicFontMask) ? @"italic" : @"normal", stretch, RSSVGPaint(color, @"fill"), RSSVGXML(text)];
            }
            glyph = NSMaxRange(range);
        }
    }
    [_xml appendString:@"</g>\n"];
}
@end

NSData *RSGraphSVGData(RSGraphEditor *editor, NSRect bounds)
{
    if (!(bounds.size.width > 0 && bounds.size.height > 0)) return nil;
    if (editor.graph.shadowStrength != 0)
        [NSException raise:NSInvalidArgumentException format:@"SVG export does not yet support document shadows; export PDF instead"];
    RSSVGDrawing *drawing = [[[RSSVGDrawing alloc] initWithBounds:bounds] autorelease];
    // A tiny offscreen native context keeps existing renderer checks/shadow state well-defined;
    // all export painting is sent to the recorder. Nothing is captured from this bitmap.
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:1 pixelsHigh:1 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0] autorelease];
    [NSGraphicsContext saveGraphicsState];
    @try {
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
        RSWithDrawingBackend(drawing, ^{ RSDrawGraphForExport(editor); });
    } @finally {
        [NSGraphicsContext restoreGraphicsState];
    }
    return drawing.data;
}
