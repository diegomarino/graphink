#import "RSModernImages.h"
#import <math.h>

BOOL RSRegisterModernImages(NSBundle *bundle, NSError **error)
{
    NSURL *manifestURL = [bundle URLForResource:@"manifest" withExtension:@"json" subdirectory:@"Modern"];
    NSData *data = manifestURL ? [NSData dataWithContentsOfURL:manifestURL options:0 error:error] : nil;
    NSDictionary *manifest = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:error] : nil;
    NSArray *entries = [manifest isKindOfClass:[NSDictionary class]] ? manifest[@"images"] : nil;
    NSMutableSet *names = [NSMutableSet set];
    NSMutableArray *images = [NSMutableArray array];
    if (![entries isKindOfClass:[NSArray class]] || entries.count == 0)
        goto invalid;
    for (NSDictionary *entry in entries) {
        if (![entry isKindOfClass:[NSDictionary class]])
            goto invalid;
        NSString *name = entry[@"name"], *file = entry[@"file"];
        NSNumber *width = entry[@"width"], *height = entry[@"height"], *isTemplate = entry[@"template"];
        if (![name isKindOfClass:[NSString class]] || !name.length || [names containsObject:name] ||
            ![file isKindOfClass:[NSString class]] || ![file isEqualToString:file.lastPathComponent] ||
            ![file.pathExtension isEqualToString:@"pdf"] ||
            ![width isKindOfClass:[NSNumber class]] || ![height isKindOfClass:[NSNumber class]] ||
            ![isTemplate isKindOfClass:[NSNumber class]] ||
            !isfinite(width.doubleValue) || !isfinite(height.doubleValue) ||
            width.doubleValue <= 0 || height.doubleValue <= 0)
            goto invalid;
        NSURL *url = [bundle URLForResource:file withExtension:nil subdirectory:@"Modern"];
        NSImage *image = url ? [[[NSImage alloc] initWithContentsOfURL:url] autorelease] : nil;
        if (!image || !image.isValid)
            goto invalid;
        image.size = NSMakeSize(width.doubleValue, height.doubleValue);
        image.template = isTemplate.boolValue;
        [names addObject:name];
        [images addObject:@[name, image]];
    }
    for (NSArray *pair in images) {
        // A nib or framework may have cached a legacy resource during framework startup.
        [[NSImage imageNamed:pair[0]] setName:nil];
        NSImage *image = pair[1];
        if (![image setName:pair[0]])
            goto invalid;
    }
    return YES;
invalid:
    if (error && !*error)
        *error = [NSError errorWithDomain:@"GraphSketcherImages" code:1 userInfo:@{NSLocalizedDescriptionKey: @"The original workflow icon resources are missing or invalid."}];
    return NO;
}

BOOL RSRegisterModernCursors(NSBundle *bundle, NSError **error)
{
    NSArray *names = @[@"GraphinkDrawCursor", @"GraphinkFillCursor"];
    NSArray *files = @[@"gs-draw-cursor", @"gs-fill-cursor"];
    NSMutableArray<NSImage *> *images = [NSMutableArray array];
    for (NSString *file in files) {
        NSURL *url = [bundle URLForResource:file withExtension:@"pdf" subdirectory:@"ModernCursors"];
        NSImage *image = url ? [[[NSImage alloc] initWithContentsOfURL:url] autorelease] : nil;
        if (!image.isValid || ![image.representations.firstObject isKindOfClass:[NSPDFImageRep class]]) {
            if (error)
                *error = [NSError errorWithDomain:@"GraphSketcherImages" code:2 userInfo:@{NSLocalizedDescriptionKey: @"The graph cursor resources are missing or invalid."}];
            return NO;
        }
        image.size = NSMakeSize(20, 20);
        image.template = NO;
        [images addObject:image];
    }
    for (NSUInteger index = 0; index < names.count; index++) {
        [[NSImage imageNamed:names[index]] setName:nil];
        if (![images[index] setName:names[index]]) {
            if (error)
                *error = [NSError errorWithDomain:@"GraphSketcherImages" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Unable to register graph cursor images."}];
            return NO;
        }
    }
    return YES;
}

NSCursor *RSGraphCursor(BOOL fill)
{
    NSImage *image = [NSImage imageNamed:fill ? @"GraphinkFillCursor" : @"GraphinkDrawCursor"];
    if (!image)
        return nil;
    // NSCursor uses logical points from the flipped image's top-left; match the SVG tip.
    return [[[NSCursor alloc] initWithImage:image hotSpot:fill ? NSMakePoint(2, 3) : NSMakePoint(2, 18)] autorelease];
}
