#import <AppKit/AppKit.h>
#import "RSModernImages.h"

static void check(BOOL condition, NSString *message)
{
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        check(argc == 2, @"Pass an app bundle path");
        NSBundle *bundle = [NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSError *error = nil;
        check(RSRegisterModernImages(bundle, &error), [error description]);
        NSArray *entries = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:[bundle URLForResource:@"manifest" withExtension:@"json" subdirectory:@"Modern"]] options:0 error:NULL][@"images"];
        NSSet *requiredNames = [NSSet setWithArray:@[
            @"arrowEndsDisabled",
            @"arrowEndsEnabled",
            @"axisPlacementBothEdgesX",
            @"axisPlacementBothEdgesY",
            @"axisPlacementEdgeX",
            @"axisPlacementEdgeY",
            @"axisPlacementNoneX",
            @"axisPlacementNoneY",
            @"axisPlacementOriginX",
            @"axisPlacementOriginY",
            @"axisTickLabelsX",
            @"axisTickLabelsY",
            @"axisTickMarksX",
            @"axisTickMarksY",
            @"axisTitleX",
            @"axisTitleY",
            @"canvasHeight",
            @"canvasWidth",
            @"copyAsImageIcon",
            @"detachIcon",
            @"drawTool",
            @"errorBarsIcon",
            @"errorbar-for-sheet",
            @"fillTool",
            @"gridDisplayHorizontal",
            @"gridDisplayVertical",
            @"groupIcon",
            @"hideGridIcon",
            @"inspectorAxes",
            @"inspectorCanvas",
            @"inspectorData",
            @"inspectorIcon",
            @"inspectorStyle",
            @"interpolateIcon",
            @"lineTypeBestFit",
            @"lineTypeCurved",
            @"lineTypeNone",
            @"lineTypeStraight",
            @"lockIcon",
            @"modifyTool",
            @"opaqueWindowIcon",
            @"pointTypeHorizontalBar",
            @"pointTypeNone",
            @"pointTypePoint",
            @"pointTypeTick",
            @"pointTypeVerticalBar",
            @"scaleDownIcon",
            @"shadowNone",
            @"shadowStrong",
            @"showGridIcon",
            @"textTool",
            @"transparentWindowIcon",
            @"ungroupIcon",
            @"unlockIcon"
        ]];
        check([[NSSet setWithArray:[entries valueForKey:@"name"]] isEqualToSet:requiredNames] && entries.count == requiredNames.count, @"Complete inventoried toolbar/inspector alias set");
        for (NSDictionary *entry in entries) {
            NSImage *image = [NSImage imageNamed:entry[@"name"]];
            check(image && image.isValid, entry[@"name"]);
            check([entry[@"file"] isEqualToString:[NSString stringWithFormat:@"gs-%@.pdf", entry[@"name"]]], @"Expected original resource mapping");
            check(image.isTemplate == [entry[@"template"] boolValue], @"Template state");
            check(NSEqualSizes(image.size, NSMakeSize([entry[@"width"] doubleValue], [entry[@"height"] doubleValue])), @"Logical size");
            NSPDFImageRep *rep = (NSPDFImageRep *)image.representations.firstObject;
            check([rep isKindOfClass:[NSPDFImageRep class]], @"Resolution-independent PDF representation");
            NSData *source = [NSData dataWithContentsOfURL:[bundle URLForResource:entry[@"file"] withExtension:nil subdirectory:@"Modern"]];
            check([rep.PDFRepresentation isEqualToData:source], @"Alias resolves to its original vector bytes");
        }
        check([NSImage imageNamed:@"lockIcon"] && [NSImage imageNamed:@"unlockIcon"] && ![[NSImage imageNamed:@"lockIcon"] isEqual:[NSImage imageNamed:@"unlockIcon"]], @"Lock and unlock remain distinct");
        check([NSImage imageNamed:@"groupIcon"] && [NSImage imageNamed:@"ungroupIcon"] && ![[NSImage imageNamed:@"groupIcon"] isEqual:[NSImage imageNamed:@"ungroupIcon"]], @"Group and ungroup remain distinct");

        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        NSString *resources = [root stringByAppendingPathComponent:@"Invalid.bundle/Contents/Resources/Modern"];
        check([[NSFileManager defaultManager] createDirectoryAtPath:resources withIntermediateDirectories:YES attributes:nil error:&error], @"Create disposable fixture");
        NSBundle *invalidBundle = [NSBundle bundleWithPath:[root stringByAppendingPathComponent:@"Invalid.bundle"]];
        error = nil;
        check(!RSRegisterModernImages(invalidBundle, &error) && error, @"Missing manifest is rejected");
        NSArray *badManifests = @[
            @[],
            @{@"images": @[]},
            @{@"images": @[@{@"name": @"bad", @"file": @"../outside.pdf", @"width": @24, @"height": @24, @"template": @YES}]},
            @{@"images": @[@{@"name": @"bad", @"file": @"missing.pdf", @"width": @24, @"height": @24, @"template": @YES}]},
            @{@"images": @[@{@"name": @"bad", @"file": @"missing.pdf", @"width": @0, @"height": @24, @"template": @YES}]}
        ];
        for (id manifest in badManifests) {
            NSData *data = [NSJSONSerialization dataWithJSONObject:manifest options:0 error:NULL];
            check([data writeToFile:[resources stringByAppendingPathComponent:@"manifest.json"] atomically:YES], @"Write malformed fixture");
            error = nil;
            check(!RSRegisterModernImages(invalidBundle, &error) && error, @"Invalid manifest/resource is rejected");
        }
        NSLog(@"PASS: %lu original vector aliases, template states/sizes, semantic pairs and missing/invalid resource rejection", (unsigned long)entries.count);
    }
    return 0;
}
