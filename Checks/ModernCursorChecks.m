#import <AppKit/AppKit.h>
#import "RSModernImages.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSBundle *bundle = [NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSError *error = nil;
        NSCAssert(RSRegisterModernCursors(bundle, &error), @"Cursor resources failed: %@", error);
        for (NSNumber *fill in @[@NO, @YES]) {
            NSCursor *cursor = RSGraphCursor(fill.boolValue);
            NSImage *image = cursor.image;
            NSPoint expected = fill.boolValue ? NSMakePoint(2, 3) : NSMakePoint(2, 18);
            NSCAssert(NSEqualPoints(cursor.hotSpot, expected), @"Logical top-left hotspot changed");
            NSCAssert(NSEqualSizes(image.size, NSMakeSize(20,20)), @"Cursor logical size changed");
            NSCAssert(!image.isTemplate, @"Cursor must retain black/white contrast");
            NSCAssert(image.representations.count == 1 && [image.representations[0] isKindOfClass:[NSPDFImageRep class]], @"Cursor must remain vector-backed for Retina");
            NSString *file = fill.boolValue ? @"gs-fill-cursor" : @"gs-draw-cursor";
            NSData *packaged = [NSData dataWithContentsOfURL:[bundle URLForResource:file withExtension:@"pdf" subdirectory:@"ModernCursors"]];
            NSCAssert([[(NSPDFImageRep *)image.representations[0] PDFRepresentation] isEqual:packaged], @"Alias must use exact cursor PDF");
        }
        NSCAssert(RSGraphCursor(NO) != RSGraphCursor(YES), @"Draw and Fill cursors must be distinct");
        NSCAssert([NSCursor arrowCursor] != RSGraphCursor(NO) && [NSCursor IBeamCursor] != RSGraphCursor(YES), @"System cursors must remain distinct");
        error = nil;
        NSCAssert(!RSRegisterModernCursors([NSBundle bundleWithPath:@"/missing-cursor-fixture"] , &error) && error, @"Missing cursor resources must fail");
        puts("PASS two exact vector cursor aliases, 20pt size, black/white policy, NSCursor hotspots, distinct system cursors and missing-resource refusal");
    }
    return 0;
}
