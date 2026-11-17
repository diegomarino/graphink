// Isolated AppKit/Foundation probes: no Omni or model build/runtime acceptance.
#import <Cocoa/Cocoa.h>
#include <math.h>

static void Check(BOOL condition, NSString *message)
{
    if (!condition) [NSException raise:@"PlatformCompatibilityFailure" format:@"%@", message];
}

static NSArray *RGB(NSColor *color)
{
    NSColor *normalized = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    Check(normalized != nil, @"Normalize color to sRGB");
    CGFloat r, g, b, a;
    [normalized getRed:&r green:&g blue:&b alpha:&a];
    return @[@(r), @(g), @(b), @(a)];
}

int main(void)
{
    @autoreleasepool {
        @try {
            NSDecimalNumber *nan = [NSDecimalNumber notANumber];
            Check(nan == [NSDecimalNumber notANumber], @"NaN singleton identity");
            id copied = [nan copy];
            Check(copied == nan, @"NaN identity survives default-value copy");
            [copied release];
            Check([nan isKindOfClass:[NSNumber class]] && [nan isEqual:nan], @"NaN NSNumber type and self-equality");
            Check(isnan([nan doubleValue]) && isnan([nan floatValue]), @"NaN numeric conversion");
            Check([[nan stringValue] isEqual:@"NaN"] && ![nan isEqual:@0], @"Literal NaN serialization remains distinct from zero");
            NSXMLElement *element = [NSXMLElement elementWithName:@"value" stringValue:[nan stringValue]];
            NSError *error = nil;
            NSXMLDocument *xml = [[[NSXMLDocument alloc] initWithXMLString:[element XMLString] options:0 error:&error] autorelease];
            Check(xml != nil && [[[xml rootElement] stringValue] isEqual:@"NaN"], @"Literal NaN XML text");

            // Exact RGB tuple from Model/XML/example.ograph canvas; constructors
            // match pinned 2014 OQColor.toColor and 2022 OAColor.makePlatformColor.
            NSColor *legacy = [NSColor colorWithCalibratedRed:1 green:0.044186 blue:0.61031 alpha:1];
            NSColor *candidate = [NSColor colorWithRed:1 green:0.044186 blue:0.61031 alpha:1];
            NSArray *oldRGB = RGB(legacy), *newRGB = RGB(candidate);
            double maximumDelta = 0;
            for (NSUInteger i = 0; i < 4; i++) maximumDelta = fmax(maximumDelta, fabs([oldRGB[i] doubleValue] - [newRGB[i] doubleValue]));
            // Converting the original color, unlike reinterpreting its components,
            // preserves normalized values. This does not implement an XML migration.
            NSColor *converted = [legacy colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
            Check([RGB(converted) isEqual:oldRGB], @"Color-space conversion preserves normalized interpretation");
            NSColor *legacyGray = [NSColor colorWithCalibratedWhite:0.5 alpha:0.7];
            NSColor *candidateGray = [NSColor colorWithWhite:0.5 alpha:0.7];
            NSDictionary *report = @{@"scope": @"Platform constructors and sentinel only; Omni/model XML and visual fidelity unverified",
                @"nan_contract": @"passed", @"legacy_xml": @"Model/XML/example.ograph canvas color",
                @"legacy_space": [[legacy colorSpace] localizedName], @"candidate_space": [[candidate colorSpace] localizedName],
                @"legacy_srgb": oldRGB, @"candidate_srgb": newRGB, @"maximum_component_delta": @(maximumDelta),
                @"legacy_gray_srgb": RGB(legacyGray), @"candidate_gray_srgb": RGB(candidateGray),
                @"equivalent_rgb_interpretation": @(maximumDelta <= 1e-6)};
            NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:&error];
            Check(json != nil, [error description]);
            fwrite([json bytes], 1, [json length], stdout);
            fputc('\n', stdout);
            return maximumDelta <= 1e-6 ? 0 : 3; // 3: observed color-compatibility gate, not a passing migration.
        } @catch (NSException *exception) {
            fprintf(stderr, "FAIL %s\n", [[exception description] UTF8String]);
            return 1;
        }
    }
}
