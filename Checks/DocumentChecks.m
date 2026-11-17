// Production document IO checks; no importer, editor, UI or visual acceptance implied.
#import <Cocoa/Cocoa.h>
#import <OmniFoundation/OmniFoundation.h>
#import <GraphSketcherModel/RSGraph.h>
#import <GraphSketcherModel/RSUndoer.h>
#import <GraphSketcherModel/RSUndoerOwner.h>
#import "../GraphSketcher/OmniStyle/Basic/OSNumberStyleAttribute.h"
#import <OmniFoundation/OFXMLDocument.h>
#import <OmniFoundation/OFXMLCursor.h>
#import <OmniUnzip/OUUnzipArchive.h>
#import <OmniUnzip/OUUnzipEntry.h>
#import <GraphSketcherModel/RSVertex.h>
#import <GraphSketcherModel/RSConnectLine.h>
#import <GraphSketcherModel/RSFill.h>
#import <GraphSketcherModel/RSGroup.h>
#import <GraphSketcherModel/RSGrid.h>
#import <GraphSketcherModel/RSTextLabel.h>
#import <GraphSketcherModel/RSDataImporter.h>
#import <GraphSketcherModel/RSDataMapper.h>
#import <GraphSketcherModel/RSGraphRenderer.h>
#import <GraphSketcherModel/OFPreference-RSExtensions.h>
#import <OmniAppKit/NSUserDefaults-OAExtensions.h>
@interface RSDataImporter (DocumentChecks)
+ (NSColor *)_colorForDataSeriesNumber:(NSUInteger)n;
@end
#include <math.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <locale.h>
#include <xlocale.h>
#import <CommonCrypto/CommonDigest.h>
#import <OmniBase/assertions.h>
#import <objc/runtime.h>

static void Require(BOOL condition, NSString *message)
{
    if (!condition)
        [NSException raise:@"DocumentCheckFailure" format:@"%@", message];
}

// Do not throw: the per-sample exception handler must never swallow an assertion.
static void FatalAssertion(const char *type, const char *expression, const char *file, unsigned int line, const char *reason)
{
    fprintf(stderr, "FATAL ASSERTION %s %s %s:%u %s\n", type ?: "", expression ?: "", file ?: "", line, reason ?: "");
    fflush(NULL);
    _Exit(1);
}

@interface CheckController : OFController
@end
@implementation CheckController
- (BOOL)crashOnAssertionOrUnhandledException { return YES; }
- (void)handleFailureInMethod:(SEL)selector object:(id)object file:(NSString *)file lineNumber:(int)line format:(NSString *)format arguments:(va_list)args
{
    FatalAssertion("NSAssertion", sel_getName(selector), [file UTF8String], line,
        [[[[NSString alloc] initWithFormat:format arguments:args] autorelease] UTF8String]);
}
- (void)handleFailureInFunction:(NSString *)function file:(NSString *)file lineNumber:(int)line format:(NSString *)format arguments:(va_list)args
{
    FatalAssertion("NSAssertion", [function UTF8String], [file UTF8String], line,
        [[[[NSString alloc] initWithFormat:format arguments:args] autorelease] UTF8String]);
}
@end

static void TerminateController(OFController *controller)
{
    if (!controller) return;
    if (controller.status <= OFControllerStatusRunning)
        Require([controller requestTermination] == OFControllerTerminateNow, @"Controller termination cancelled or postponed");
    Require(controller.status == OFControllerStatusTerminating, @"Unexpected final controller status");
    [controller willTerminate];
}

static NSNumber *Number(NSString *token)
{
    const char *start = [token UTF8String];
    Require(start && *start && strspn(start, "+-.eE0123456789") == strlen(start),
            [@"Invalid numeric token: " stringByAppendingString:token ?: @"(nil)"]);
    static locale_t locale;
    if (!locale) locale = newlocale(LC_NUMERIC_MASK, "C", NULL);
    Require(locale != NULL, @"Create numeric C locale");
    char *end = NULL;
    errno = 0;
    double value = strtod_l(start, &end, locale);
    Require(end != start && end == start + [token lengthOfBytesUsingEncoding:NSUTF8StringEncoding] && errno != ERANGE && isfinite(value),
            [@"Invalid finite numeric token: " stringByAppendingString:token]);
    return @(value);
}

static NSMutableDictionary *Attributes(NSXMLElement *element, NSDictionary *defaults)
{
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    for (NSString *attribute in defaults) {
        id fallback = defaults[attribute];
        NSString *value = [[element attributeForName:attribute] stringValue] ?: [fallback description];
        fields[attribute] = [fallback isKindOfClass:[NSNumber class]] ? (id)Number(value) : (id)value;
    }
    return fields;
}

@interface CheckOwner : NSObject <RSUndoerOwner>
@property(nonatomic, retain) NSUndoManager *undoManager;
@end
@implementation CheckOwner
@synthesize undoManager = _undoManager;
- (id)init { if ((self = [super init])) _undoManager = [[NSUndoManager alloc] init]; return self; }
- (void)undoerPerformedChange:(RSUndoer *)undoer {}
- (void)dealloc { [_undoManager release]; [super dealloc]; }
@end

// Use the real model/native preference methods with only their storage in memory.
@interface CheckPreferences : OFPreferenceWrapper {
    NSMutableDictionary *_values;
}
+ (instancetype)memoryPreferences;
@end
@implementation CheckPreferences
+ (instancetype)memoryPreferences
{
    // Like production wrappers, this in-memory receiver lives for the process.
    static CheckPreferences *preferences;
    if (!preferences) {
        preferences = [self alloc];
        preferences->_values = [[NSMutableDictionary alloc] init];
    }
    return preferences;
}
- (void)setObject:(id)value forKey:(NSString *)key { if (value) _values[key] = value; else [_values removeObjectForKey:key]; }
- (id)objectForKey:(NSString *)key { return _values[key]; }
- (NSString *)stringForKey:(NSString *)key { return _values[key]; }
@end

static NSArray *Nodes(NSXMLNode *node, NSString *xpath)
{
    NSError *error = nil;
    NSArray *result = [node nodesForXPath:xpath error:&error];
    Require(result != nil, [NSString stringWithFormat:@"XPath %@: %@", xpath, error]);
    return result;
}

static NSString *Attr(NSXMLElement *element, NSString *name, NSString *fallback)
{
    return [[element attributeForName:name] stringValue] ?: fallback;
}

static NSArray *IDs(NSString *text)
{
    return [[text componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
            filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
}

static NSXMLDocument *XML(NSData *data)
{
    NSError *error = nil;
    NSXMLDocument *doc = [[[NSXMLDocument alloc] initWithData:data
        options:NSXMLNodePreserveWhitespace | NSXMLNodeLoadExternalEntitiesNever error:&error] autorelease];
    Require(doc != nil, [NSString stringWithFormat:@"Parse XML: %@", error]);
    Require([Nodes(doc, @"/*[local-name()='document']/*[local-name()='graph']") count] == 1,
            @"Expected one graph in document");
    return doc;
}

static NSData *SourceXML(NSString *path)
{
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&error];
    Require(data != nil, [NSString stringWithFormat:@"Read %@: %@", path, error]);
    if ([data length] >= 2 && memcmp([data bytes], "PK", 2) == 0) {
        OUUnzipArchive *zip = [[[OUUnzipArchive alloc] initWithPath:path error:&error] autorelease];
        OUUnzipEntry *entry = [zip entryNamed:@"contents.xml"];
        Require(entry != nil, [NSString stringWithFormat:@"Missing contents.xml: %@", error]);
        data = [zip dataForEntry:entry error:&error];
        Require(data != nil, [NSString stringWithFormat:@"Extract contents.xml: %@", error]);
    }
    return data;
}

// Only byte-identical T44 specimens receive these narrow baseline diagnostics.
// The original bytes still go through graphFromURL; only the independent source
// projection folds identical duplicates and models the reader's dangling-ref drop.
static NSDictionary *BaselineForDigest(NSString *digest)
{
    if ([digest isEqual:@"a5e01c458e24b0beb3d06483b3c491eef8794e2e154dcd84019bdf1e33f46f42"])
        return @{@"drop": @{@"e2641/e4165": @"0"}, @"description": @"one unresolved snap"};
    if ([digest isEqual:@"e9134f856a188bae516f57661cfabcc108302322fc37acaa9f3bacfc34dff370"])
        return @{@"duplicates": @[@"e146", @"e147", @"e149", @"e150"], @"description": @"four identical duplicate labels"};
    if ([digest isEqual:@"8a916a38229e6038dea64b1fddf139e990f173d071b41e4e69402abb9397d081"])
        return @{@"drop": @{@"e183/e559": @"inf", @"e210/e520": @"inf", @"e210/e503": @"inf"},
            @"nonfinite": @[@"e183/e546"], @"description": @"three unresolved snaps; one retained inf parameter; extra vertex color schema content"};
    return nil;
}

static NSDictionary *Baseline(NSString *path)
{
    NSData *bytes = [NSData dataWithContentsOfFile:path];
    Require(bytes != nil && [bytes length] <= UINT32_MAX, @"Read source for baseline SHA-256");
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256([bytes bytes], (CC_LONG)[bytes length], hash);
    NSMutableString *digest = [NSMutableString string];
    for (NSUInteger i = 0; i < sizeof(hash); i++) [digest appendFormat:@"%02x", hash[i]];
    NSDictionary *baseline = BaselineForDigest(digest);
    if (baseline) printf("BASELINE sha256=%s %s\n", [digest UTF8String], [baseline[@"description"] UTF8String]);
    return baseline;
}

// A bounded semantic projection, independent of the model reader. Numeric defaults
// below mirror baseline XML readers. Metadata, window frame, styles and previews
// are outside this check; paragraph text retains literal whitespace and order.
static NSDictionary *Snapshot(NSXMLDocument *doc, BOOL historical, NSDictionary *baseline)
{
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSMutableDictionary *seenXML = [NSMutableDictionary dictionary];
    NSArray *elements = Nodes(doc, @"/*[local-name()='document']/*[local-name()='graph']/*");
    NSMutableSet *tickLabels = [NSMutableSet set];
    NSMutableSet *parentedVertices = [NSMutableSet set];
    for (NSXMLElement *element in elements) {
        NSString *name = [element localName];
        if ([name isEqual:@"axis"])
            for (NSXMLElement *label in Nodes(element, @"./*[local-name()='tick-labels']/*[local-name()='user-labels']/*[local-name()='label']"))
                [tickLabels addObject:Attr(label, @"idref", @"")];
        if ([name isEqual:@"line"] || [name isEqual:@"fill"]) {
            for (NSXMLElement *refs in Nodes(element, @"./*[local-name()='vertices' or local-name()='data']"))
                [parentedVertices addObjectsFromArray:IDs(Attr(refs, @"ids", @""))];
            for (NSString *key in @[@"v1", @"v2"])
                [parentedVertices addObject:Attr(element, key, @"")];
        }
    }
    NSString *version = Attr([doc rootElement], @"app-version", nil);
    NSUInteger hiddenTickLabels = 0;
    BOOL pre10 = historical && version && [version compare:@"10.0.0" options:NSNumericSearch] == NSOrderedAscending;
    for (NSXMLElement *element in elements) {
        NSString *name = [element localName];
        NSString *identifier = Attr(element, @"id", @"");
        NSDictionary *defaults = nil;
        if ([name isEqual:@"canvas"])
            defaults = @{@"w": @800, @"h": @600};
        else if ([name isEqual:@"axis"])
            defaults = @{@"dimension": @"", @"min": @0, @"max": @10, @"scale": @"linear",
                @"placement": @"origin", @"extent": @"full", @"visible": @"true",
                @"userModifiedRange": @"true", @"width": @2, @"end-shape": @"none"};
        else if ([name isEqual:@"vertex"])
            defaults = @{@"x": @0, @"y": @0, @"shape": @"none", @"width": @2, @"locked": @"false", @"arrow-parent": @""};
        else if ([name isEqual:@"line"])
            defaults = @{@"class": @"connect", @"method": @"curved", @"v1": @"", @"v2": @""};
        else if ([name isEqual:@"fill"] || [name isEqual:@"group"])
            defaults = @{};
        else if ([name isEqual:@"label"])
            defaults = @{@"x": @0, @"y": @0, @"owner": @"", @"rotation": @0, @"visible": @"true", @"locked": @"false"};
        else
            continue;
        NSString *key = [NSString stringWithFormat:@"%@/%@", name, identifier];
        if (result[key]) {
            Require(historical && [baseline[@"duplicates"] containsObject:identifier] &&
                    [seenXML[key] isEqual:[element XMLString]], [@"Unexpected duplicate semantic key: " stringByAppendingString:key]);
            printf("BASELINE identical duplicate label %s\n", [identifier UTF8String]);
            continue; // The retained first occurrence still participates in every comparison.
        }
        seenXML[key] = [element XMLString];
        NSMutableDictionary *fields = Attributes(element, defaults);
        if ([name isEqual:@"line"] && [fields[@"class"] isEqual:@"fit"])
            fields[@"method"] = Attr(element, @"method", @"linear-regression");
        if ([name isEqual:@"vertex"] && pre10 && [fields[@"shape"] isEqual:@"none"] && ![parentedVertices containsObject:identifier]) {
            fields[@"shape"] = @"circle";
            fields[@"width"] = @([fields[@"width"] doubleValue] / 4);
            printf("CONVERSION pre-v10 none -> circle, width / 4: %s\n", [identifier UTF8String]);
        }
        for (NSString *child in @[@"vertices", @"data"])
            for (NSXMLElement *refs in Nodes(element, [NSString stringWithFormat:@"./*[local-name()='%@']", child]))
                fields[child] = IDs(Attr(refs, @"ids", @""));
        if ([name isEqual:@"vertex"]) {
            NSMutableDictionary *snaps = [NSMutableDictionary dictionary];
            for (NSXMLElement *ref in Nodes(element, @"./*[local-name()='snapped-to']/*[local-name()='element']"))
            {
                NSString *target = Attr(ref, @"idref", @"");
                NSString *pair = [identifier stringByAppendingFormat:@"/%@", target];
                NSString *param = Attr(ref, @"param", @"0.5");
                if (historical && baseline[@"drop"][pair]) {
                    Require([param isEqual:baseline[@"drop"][pair]], @"Baseline dangling parameter changed");
                    printf("BASELINE production drops unresolved snap %s\n", [pair UTF8String]);
                    continue;
                }
                if ([baseline[@"nonfinite"] containsObject:pair]) {
                    Require([param isEqual:@"inf"], @"Baseline nonfinite parameter changed");
                    snaps[target] = @"BASELINE:inf"; // Preserve this exact hash-bound field symbolically.
                } else {
                    snaps[target] = Number(param);
                }
            }
            fields[@"snapped-to"] = snaps;
        }
        if ([name isEqual:@"group"])
            fields[@"elements"] = [IDs(Attr(element, @"elements", @"")) sortedArrayUsingSelector:@selector(compare:)];
        if ([name isEqual:@"axis"]) {
            NSMutableDictionary *refs = [NSMutableDictionary dictionary];
            for (NSXMLElement *label in Nodes(element, @"./*[local-name()='tick-labels']/*[local-name()='user-labels']/*[local-name()='label']"))
                refs[Attr(label, @"tick", @"")] = Attr(label, @"idref", @"");
            fields[@"tick-labels"] = refs;
            NSArray *titles = Nodes(element, @"./*[local-name()='title']");
            NSXMLElement *title = [titles count] ? titles[0] : nil;
            fields[@"title"] = Attr(title, @"label", @"");
            fields[@"title-settings"] = Attributes(title, @{@"distance": @18, @"placement": title ? @0.5 : @0, @"visible": title ? @"true" : @"false"});
            NSArray *ticks = Nodes(element, @"./*[local-name()='ticks']");
            fields[@"ticks"] = Attributes([ticks count] ? ticks[0] : nil,
                @{@"spacing": @1, @"user-spacing": @0, @"layout": @"simple", @"width-in": @3, @"width-out": @1, @"visible": [ticks count] ? @"true" : @"false"});
            NSArray *labels = Nodes(element, @"./*[local-name()='tick-labels']");
            BOOL horizontal = [fields[@"dimension"] isEqual:@"x"];
            fields[@"tick-label-settings"] = Attributes([labels count] ? labels[0] : nil,
                @{@"distance": horizontal ? @3 : @5, @"padding": horizontal ? @10 : @4,
                  @"scientific-notation": @"auto", @"visible": [labels count] ? @"true" : @"false"});
        }
        if ([name isEqual:@"label"]) {
            NSMutableArray *paragraphs = [NSMutableArray array];
            for (NSXMLElement *p in Nodes(element, @"./*[local-name()='text']/*[local-name()='p']")) {
                NSMutableString *text = [NSMutableString string];
                for (NSXMLNode *lit in Nodes(p, @"./*[local-name()='run']/*[local-name()='lit']"))
                    [text appendString:[lit stringValue]];
                [paragraphs addObject:text];
            }
            fields[@"text"] = paragraphs;
            // RSGraph-XML resets user tick visibility on every load, before layout.
            if ([tickLabels containsObject:identifier]) {
                if (historical && ![fields[@"visible"] isEqual:@"false"]) hiddenTickLabels++;
                fields[@"visible"] = @"false";
            }
        }
        result[key] = fields;
    }
    if (hiddenTickLabels) printf("CONVERSION reset %lu user tick-label visibility flags before layout\n", (unsigned long)hiddenTickLabels);
    return result;
}

static void CompareValue(id expected, id actual, NSString *path)
{
    if ([expected isKindOfClass:[NSDictionary class]]) {
        Require([actual isKindOfClass:[NSDictionary class]] && [expected count] == [actual count],
                [NSString stringWithFormat:@"%@ field count: %@ -> %@", path, expected, actual]);
        for (NSString *key in expected)
            CompareValue(expected[key], actual[key], [path stringByAppendingFormat:@"/%@", key]);
    } else if ([expected isKindOfClass:[NSNumber class]] && [actual isKindOfClass:[NSNumber class]]) {
        double a = [expected doubleValue], b = [actual doubleValue];
        NSString *field = [path lastPathComponent];
        double tolerance = [@[@"x", @"y", @"min", @"max", @"w", @"h"] containsObject:field] ? 1e-12 : 1e-6;
        Require(isfinite(a) && isfinite(b) && fabs(a - b) <= tolerance * fmax(1, fmax(fabs(a), fabs(b))),
                [NSString stringWithFormat:@"%@ numeric drift: %@ -> %@", path, expected, actual]);
    } else {
        Require([expected isEqual:actual], [NSString stringWithFormat:@"%@ changed: %@ -> %@", path, expected, actual]);
    }
}

static void Compare(NSDictionary *expected, NSDictionary *actual, BOOL firstLoad)
{
    if (!firstLoad)
        Require([expected count] == [actual count], @"Roundtrip element count changed");
    NSMutableSet *generated = [NSMutableSet set];
    for (NSString *key in expected) {
        NSDictionary *fields = expected[key];
        if (firstLoad && [key hasPrefix:@"axis/"] && actual[key]) {
            NSMutableDictionary *axis = [[fields mutableCopy] autorelease];
            NSMutableDictionary *ticks = [[axis[@"tick-labels"] mutableCopy] autorelease];
            for (NSString *endpoint in @[@"minLabel", @"maxLabel"]) {
                if (!ticks[endpoint] && actual[key][@"tick-labels"][endpoint]) {
                    NSString *ref = actual[key][@"tick-labels"][endpoint];
                    NSString *labelKey = [@"label/" stringByAppendingString:ref];
                    Require(expected[labelKey] == nil && ![generated containsObject:labelKey], @"Generated endpoint reused an existing label");
                    // Unchanged-bound setters return early, leaving the constructor text "Label".
                    CompareValue(@{@"x": @0, @"y": @0, @"owner": @"", @"rotation": @0, @"locked": @"false", @"visible": @"false", @"text": @[@"Label"]}, actual[labelKey], labelKey);
                    [generated addObject:labelKey];
                    ticks[endpoint] = ref;
                    printf("CONVERSION generated missing axis %s %s\n", [key UTF8String], [endpoint UTF8String]);
                }
            }
            axis[@"tick-labels"] = ticks;
            fields = axis;
        }
        CompareValue(fields, actual[key], key);
    }
    // Only missing endpoint labels occur in this corpus; no arbitrary label allowance.
    if (firstLoad)
        for (NSString *key in actual)
            Require(expected[key] != nil || [generated containsObject:key], [@"Unexpected first-load element: " stringByAppendingString:key]);
}

static void MustReject(void (^check)(void))
{
    BOOL rejected = NO;
    @try { check(); }
    @catch (NSException *exception) {
        Require([[exception name] isEqual:@"DocumentCheckFailure"], @"Unexpected self-check exception");
        rejected = YES;
    }
    Require(rejected, @"Self-check missed a required rejection");
}

static NSXMLDocument *Fixture(NSString *graph)
{
    return XML([[NSString stringWithFormat:@"<document><graph>%@</graph></document>", graph] dataUsingEncoding:NSUTF8StringEncoding]);
}

static void ComparatorSelfCheck(void)
{
    Require([Number(@"-1.25e-3") isEqual:@(-0.00125)] && [Number(@"0") isEqual:@0], @"Valid numeric tokens rejected");
    for (NSString *token in @[@"", @"garbage", @"0garbage", @"1.5suffix", @"1e", @"nan", @"inf", @"-Infinity", @"1e309", @" 0", @"0x1"])
        MustReject(^{ Number(token); });
    NSDictionary *paragraphLabels = Snapshot(Fixture(@"<label id='a'><text><p><run><lit>first</lit></run></p></text></label><label id='b'><text><p><run><lit>second</lit></run></p></text></label>"), NO, nil);
    Require([paragraphLabels[@"label/a"][@"text"] isEqual:@[@"first"]] && [paragraphLabels[@"label/b"][@"text"] isEqual:@[@"second"]], @"Paragraph projection crossed label boundaries");
    NSDictionary *base = @{@"vertex/v1": @{@"x": @2.33},
        @"label/t1": @{@"text": @[@" keep space "]}, @"line/l1": @{@"vertices": @[@"v1", @"v2"]}};
    Compare(base, base, NO);
    for (NSDictionary *changed in @[
        @{@"label/t1": base[@"label/t1"], @"line/l1": base[@"line/l1"]},
        @{@"vertex/v1": @{@"x": @2.34}, @"label/t1": base[@"label/t1"], @"line/l1": base[@"line/l1"]},
        @{@"vertex/v1": base[@"vertex/v1"], @"label/t1": @{@"text": @[@"keep space"]}, @"line/l1": base[@"line/l1"]},
        @{@"vertex/v1": base[@"vertex/v1"], @"label/t1": base[@"label/t1"], @"line/l1": @{@"vertices": @[@"v2", @"v1"]}}])
        MustReject(^{ Compare(base, changed, YES); });

    NSXMLDocument *axisDoc = Fixture(@"<axis id='ax' dimension='x' placement='origin' extent='full' visible='true'><ticks spacing='1' user-spacing='2' visible='true'/><tick-labels visible='true' distance='3' padding='10'/><title label='t' visible='true' distance='18' placement='0.5'/></axis><label id='t'/>");
    NSDictionary *axes = Snapshot(axisDoc, NO, nil);
    for (NSArray *mutation in @[
        @[@"axis", @"placement", @"edge"], @[@"axis", @"extent", @"data-range"], @[@"axis", @"visible", @"false"],
        @[@"ticks", @"spacing", @"3"], @[@"ticks", @"user-spacing", @"3"], @[@"ticks", @"visible", @"false"],
        @[@"tick-labels", @"visible", @"false"], @[@"tick-labels", @"distance", @"4"], @[@"tick-labels", @"padding", @"11"],
        @[@"title", @"visible", @"false"], @[@"title", @"distance", @"19"], @[@"title", @"placement", @"0.7"]]) {
        NSXMLDocument *changed = [[axisDoc copy] autorelease];
        NSXMLElement *element = Nodes(changed, [NSString stringWithFormat:@"//*[local-name()='%@']", mutation[0]])[0];
        [[element attributeForName:mutation[1]] setStringValue:mutation[2]];
        MustReject(^{ Compare(axes, Snapshot(changed, NO, nil), NO); });
    }
    NSMutableDictionary *withEndpoint = [[axes mutableCopy] autorelease];
    NSMutableDictionary *axis = [[axes[@"axis/ax"] mutableCopy] autorelease];
    axis[@"tick-labels"] = @{@"minLabel": @"generated"};
    withEndpoint[@"axis/ax"] = axis;
    NSDictionary *label = @{@"x": @0, @"y": @0, @"rotation": @0, @"owner": @"", @"visible": @"false", @"locked": @"false", @"text": @[@"Label"]};
    withEndpoint[@"label/generated"] = label;
    Compare(axes, withEndpoint, YES);
    withEndpoint[@"label/unrelated"] = label;
    MustReject(^{ Compare(axes, withEndpoint, YES); });
    [withEndpoint removeObjectForKey:@"label/unrelated"];
    NSMutableDictionary *wrongDefault = [[label mutableCopy] autorelease];
    wrongDefault[@"x"] = @1;
    withEndpoint[@"label/generated"] = wrongDefault;
    MustReject(^{ Compare(axes, withEndpoint, YES); });

    NSDictionary *small = BaselineForDigest(@"a5e01c458e24b0beb3d06483b3c491eef8794e2e154dcd84019bdf1e33f46f42");
    NSXMLDocument *dangling = Fixture(@"<vertex id='e2641' x='2'><snapped-to><element idref='e4165' param='0'/></snapped-to></vertex>");
    NSDictionary *normalized = Snapshot(dangling, YES, small);
    Compare(normalized, Snapshot(Fixture(@"<vertex id='e2641' x='2'/>"), NO, small), NO);
    MustReject(^{ Compare(normalized, Snapshot(Fixture(@"<vertex id='e2641' x='3'/>"), NO, small), NO); });
    Require(BaselineForDigest(@"changed-hash") == nil, @"Baseline diagnostics escaped their exact hash");
    MustReject(^{ Compare(normalized, Snapshot(dangling, YES, nil), NO); });
    NSDictionary *duplicate = BaselineForDigest(@"e9134f856a188bae516f57661cfabcc108302322fc37acaa9f3bacfc34dff370");
    NSXMLDocument *labels = Fixture(@"<label id='e146' x='2'/><label id='e146' x='2'/><vertex id='v' x='1'/>");
    NSDictionary *deduplicated = Snapshot(labels, YES, duplicate);
    Compare(deduplicated, Snapshot(Fixture(@"<label id='e146' x='2'/><vertex id='v' x='1'/>"), NO, nil), NO);
    MustReject(^{ Snapshot(labels, YES, nil); });
    MustReject(^{ Compare(deduplicated, Snapshot(Fixture(@"<label id='e146' x='3'/><vertex id='v' x='1'/>"), NO, nil), NO); });
    NSDictionary *climate = BaselineForDigest(@"8a916a38229e6038dea64b1fddf139e990f173d071b41e4e69402abb9397d081");
    NSXMLDocument *infinite = Fixture(@"<vertex id='e183'><snapped-to><element idref='e546' param='inf'/></snapped-to></vertex>");
    Compare(Snapshot(infinite, YES, climate), Snapshot(infinite, NO, climate), NO);
    MustReject(^{ Snapshot(infinite, YES, nil); });
}

// Production style reader/writer check; executed only with the reviewed model build.
static void NaNSemanticsCheck(void)
{
    NSDecimalNumber *nan = [NSDecimalNumber notANumber];
    OSNumberStyleAttribute *attribute = [[[OSNumberStyleAttribute alloc] initWithKey:@"migration-nan"
        defaultValue:nan valueExtent:OFExtentMake(-1000, 2000) integral:NO] autorelease];
    Require([attribute defaultValue] == nan && [nan isEqual:nan] && isnan([nan doubleValue]), @"NaN default identity, self-equality and numeric meaning");
    Require([attribute validValueForValue:nan] == nan && [[attribute validValueForValue:@0] isEqual:@0], @"NaN default and explicit zero remain distinct");
    NSError *error = nil;
    OFXMLDocument *doc = [[[OFXMLDocument alloc] initWithRootElementName:@"value" namespaceURL:nil
        whitespaceBehavior:nil stringEncoding:kCFStringEncodingUTF8 error:&error] autorelease];
    Require(doc != nil, [NSString stringWithFormat:@"NaN XML document: %@", error]);
    [attribute appendXML:doc forValue:nan];
    NSData *data = [doc xmlData:&error];
    NSXMLDocument *literal = [[[NSXMLDocument alloc] initWithData:data options:0 error:&error] autorelease];
    Require(literal != nil && [[[literal rootElement] stringValue] isEqual:@"NaN"], @"Production writer must serialize literal NaN");
    OFXMLDocument *reopened = [[[OFXMLDocument alloc] initWithData:data whitespaceBehavior:nil error:&error] autorelease];
    Require(reopened != nil, [NSString stringWithFormat:@"Reopen NaN XML: %@", error]);
    OFXMLCursor *cursor = [[[OFXMLCursor alloc] initWithDocument:reopened] autorelease];
    id value = [attribute copyValueFromXML:cursor];
    Require(value == nan && [attribute validValueForValue:value] == nan, @"Production NaN reader must restore the exact default sentinel");
    [value release];
}

static RSGraph *Load(NSString *path, RSUndoer *undoer)
{
    NSError *error = nil;
    // .ograph is the original GraphSketcher type; everything else is read as Graphink's own.
    NSString *type = [[path pathExtension] caseInsensitiveCompare:@"ograph"] == NSOrderedSame ? RSGraphLegacyFileType : RSGraphFileType;
    RSGraph *graph = [RSGraph graphFromURL:[NSURL fileURLWithPath:path]
        type:type undoer:undoer error:&error];
    Require(graph != nil, [NSString stringWithFormat:@"Production load %@: %@", path, error]);
    return graph;
}

static NSData *Generate(RSGraph *graph)
{
    NSError *error = nil;
    NSData *data = [graph generateXMLOfType:RSGraphFileType frame:CGRectZero error:&error];
    Require(data != nil, [NSString stringWithFormat:@"Production generateXML: %@", error]);
    return data;
}

static NSData *Preview(void)
{
    NSMutableData *pdf = [NSMutableData data];
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((CFMutableDataRef)pdf);
    CGRect bounds = CGRectMake(0, 0, 10, 10);
    CGContextRef context = CGPDFContextCreate(consumer, &bounds, NULL);
    Require(context != NULL, @"Create disposable PDF preview");
    CGPDFContextBeginPage(context, NULL);
    CGPDFContextEndPage(context);
    CGPDFContextClose(context);
    CGContextRelease(context);
    CGDataConsumerRelease(consumer);
    return pdf; // Exercises ZIP packaging only; not a rendered graph preview.
}

static void CheckColor(NSColor *expected, NSColor *actual)
{
    Require(actual != nil, @"Missing native color");
    if (expected.type == NSColorTypePattern) {
        Require(actual.type == NSColorTypePattern, @"Pattern representation lost");
        NSBitmapImageRep *a = [NSBitmapImageRep imageRepWithData:expected.patternImage.TIFFRepresentation];
        NSBitmapImageRep *b = [NSBitmapImageRep imageRepWithData:actual.patternImage.TIFFRepresentation];
        Require(a.pixelsWide == b.pixelsWide && a.pixelsHigh == b.pixelsHigh, @"Pattern dimensions changed");
        expected = [a colorAtX:0 y:0]; actual = [b colorAtX:0 y:0];
    } else if (expected.type == NSColorTypeCatalog) {
        Require(actual.type == NSColorTypeCatalog && [expected.catalogNameComponent isEqual:actual.catalogNameComponent] &&
                [expected.colorNameComponent isEqual:actual.colorNameComponent], @"Named color representation lost");
    }
    NSColor *components = [expected colorUsingType:NSColorTypeComponentBased];
    NSColor *converted = [actual colorUsingColorSpace:components.colorSpace];
    Require(components != nil && converted != nil && components.numberOfComponents == converted.numberOfComponents, @"Native color conversion failed");
    CGFloat a[8], b[8]; Require(components.numberOfComponents <= 8, @"Too many color components");
    [components getComponents:a]; [converted getComponents:b];
    for (NSInteger i = 0; i < components.numberOfComponents; i++)
        Require(isfinite(a[i]) && isfinite(b[i]) && fabs(a[i] - b[i]) <= 1e-6, @"Current native color components changed");
}

static void CheckGraphColors(RSGraph *graph, NSColor *color, NSString *labelID)
{
    RSGroup *group = [[graph objectForIdentifier:@"v1"] group];
    Require(group.count == 2 && group.color != nil, @"Reopened same-color group lost color consensus");
    CheckColor(color, group.color);
    for (NSColor *actual in @[[graph backgroundColor], [[graph objectForIdentifier:@"v1"] color],
        [[graph objectForIdentifier:@"l1"] color], [[graph objectForIdentifier:@"f1"] color],
        [[graph xAxis] color], [[graph yGrid] color], [[graph objectForIdentifier:labelID] color]])
        CheckColor(color, actual);
}

static void CheckDrawing(RSGraph *graph, NSString *output)
{
    NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:256 pixelsHigh:256
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0] autorelease];
    Require(bitmap != nil, @"Create drawing surface");
    [NSGraphicsContext saveGraphicsState];
    @try {
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap]];
        RSDataMapper *mapper = [[[RSDataMapper alloc] initWithGraph:graph] autorelease]; mapper.bounds = CGRectMake(0, 0, 256, 256);
        RSGraphRenderer *renderer = [[[RSGraphRenderer alloc] initWithMapper:mapper] autorelease];
        [renderer drawBackgroundWithColor:graph.backgroundColor];
        [renderer drawAllGraphElementsExcept:nil];
        [renderer drawSelected:[graph objectForIdentifier:@"v1"] windowIsKey:YES];
        drawRectangularSelectRect(CGRectMake(20, 20, 80, 80));
        NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        Require(png != nil && [png writeToFile:output atomically:YES], @"Save drawing/selection diagnostic");

    } @finally { [NSGraphicsContext restoreGraphicsState]; }
}

static void CurrentDocumentChecks(NSString *output, NSUInteger *completed, NSUInteger *roundtrips, NSUInteger *failed)
{
    // Process-local settings exercise the real native preference and palette paths.
    NSMutableDictionary *arguments = [[[[NSUserDefaults standardUserDefaults] volatileDomainForName:NSArgumentDomain] mutableCopy] autorelease];
    if (!arguments) arguments = [NSMutableDictionary dictionary];
    arguments[@"UseColorPaletteWhenImportingData"] = @YES;
    arguments[@"DataSeriesColorPalette"] = @[@"0.2 0.4 0.6 0.35"];
    [[NSUserDefaults standardUserDefaults] setVolatileDomain:arguments forName:NSArgumentDomain];
    CheckColor([NSColor colorWithSRGBRed:0.2 green:0.4 blue:0.6 alpha:0.35], [RSDataImporter _colorForDataSeriesNumber:0]);
    NSBitmapImageRep *pixel = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:1 pixelsHigh:1 bitsPerSample:8
        samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0] autorelease];
    NSUInteger patternPixel[] = {51, 102, 153, 255}, populatedPixel[4];
    [pixel setPixel:patternPixel atX:0 y:0]; [pixel getPixel:populatedPixel atX:0 y:0];
    Require(memcmp(patternPixel, populatedPixel, sizeof(patternPixel)) == 0, @"Pattern fixture pixels were not populated");
    NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(1, 1)] autorelease]; [image addRepresentation:pixel];
    CGFloat cmyk[] = {0.1, 0.2, 0.3, 0.4, 0.6}, extended[] = {1.1, -0.05, 0.6, 0.7};
    NSArray *colors = @[[NSColor colorWithSRGBRed:0.2 green:0.4 blue:0.6 alpha:0.35], [NSColor colorWithWhite:0.5 alpha:0.7],
        [NSColor colorWithHue:0.6 saturation:0.7 brightness:0.8 alpha:0.4], [NSColor colorWithDisplayP3Red:0.1 green:0.7 blue:0.2 alpha:0.6],
        [NSColor colorWithColorSpace:[NSColorSpace genericCMYKColorSpace] components:cmyk count:5],
        [NSColor colorWithCatalogName:@"System" colorName:@"textColor"], [NSColor colorWithPatternImage:image],
        [NSColor colorWithColorSpace:[NSColorSpace extendedSRGBColorSpace] components:extended count:4]];
    for (NSUInteger index = 0; index < colors.count; index++) {
        CheckOwner *owner = [[[CheckOwner alloc] init] autorelease]; owner.undoManager.groupsByEvent = NO;
        RSUndoer *undoer = [[[RSUndoer alloc] initWithOwner:owner] autorelease];
        NSMutableArray *graphs = [NSMutableArray array]; NSColor *color = colors[index];
        @try {
            [owner.undoManager disableUndoRegistration];
            RSGraph *graph = [[[RSGraph alloc] initWithIdentifier:nil undoer:undoer] autorelease]; [graphs addObject:graph];
            [graph setupDefault]; [graph setCanvasSize:CGSizeMake(256, 256)]; graph.backgroundColor = color;
            graph.xAxis.color = color; graph.yGrid.color = color;
            RSVertex *v1 = [[[RSVertex alloc] initWithGraph:graph identifier:@"v1" point:RSDataPointMake(2, 3) width:5 color:color shape:RS_CIRCLE] autorelease];
            RSVertex *v2 = [[[RSVertex alloc] initWithGraph:graph identifier:@"v2" point:RSDataPointMake(4, 6) width:5 color:color shape:RS_CIRCLE] autorelease];
            RSVertex *v3 = [[[RSVertex alloc] initWithGraph:graph identifier:@"v3" point:RSDataPointMake(7, 2) width:5 color:color shape:RS_CIRCLE] autorelease];
            for (RSVertex *v in @[v1, v2, v3]) [graph addVertex:v];
            RSGroup *vertices = [[[RSGroup alloc] initWithGraph:graph byCopyingArray:@[v1, v2, v3]] autorelease];
            RSConnectLine *line = [[[RSConnectLine alloc] initWithGraph:graph identifier:@"l1" vertices:vertices color:color width:2 dash:0 slide:0.5 labelDistance:2] autorelease];
            [graph addLine:line];
            RSFill *fill = [[[RSFill alloc] initWithGraph:graph identifier:@"f1" vertexGroup:vertices color:color placement:CGPointMake(0.5, 0.5)] autorelease];
            [graph addFill:fill];
            RSTextLabel *label = [[[RSTextLabel alloc] initWithGraph:graph] autorelease]; [label setText:@"Current native color"]; label.color = color; [graph addLabel:label];
            NSString *labelID = [graph identiferForObject:label];
            RSGroup *group = [RSGroup groupWithGraph:graph]; [graph setGroup:group forElement:v1]; [graph setGroup:group forElement:v2];
            [owner.undoManager enableUndoRegistration]; [undoer endRepetitiveUndo];
            [owner.undoManager beginUndoGrouping]; v1.color = [NSColor orangeColor]; [owner.undoManager endUndoGrouping];
            [undoer endRepetitiveUndo]; [owner.undoManager undo]; CheckColor(color, v1.color);
            [owner.undoManager redo]; CheckColor([NSColor orangeColor], v1.color);
            [owner.undoManager disableUndoRegistration]; v1.color = color;
            NSColor *nativeOpacityColor = [color colorWithAlphaComponent:0.42];
            CGFloat originalOpacity = v1.opacity;
            v1.opacity = 0.42;
            Require(v1.color != nil, @"Opacity removed the graph element color");
            CheckColor(nativeOpacityColor ?: color, v1.color);
            Require(fabs(v1.opacity - (nativeOpacityColor ? 0.42 : originalOpacity)) < 1e-6, @"Unsupported native opacity must preserve the original color and opacity");
            v1.color = color;
            [owner.undoManager enableUndoRegistration]; [owner.undoManager removeAllActions]; [undoer endRepetitiveUndo];
            CheckGraphColors(graph, color, labelID);
            [owner.undoManager disableUndoRegistration];
            v2.color = [NSColor orangeColor];
            Require(group.color == nil, @"Mixed-color group incorrectly reports color consensus");
            v2.color = color;
            if (color.type == NSColorTypePattern) {
                NSBitmapImageRep *differentPixel = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:1 pixelsHigh:1
                    bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0] autorelease];
                NSUInteger blackPixel[] = {0, 0, 0, 255};
                [differentPixel setPixel:blackPixel atX:0 y:0];
                NSImage *differentImage = [[[NSImage alloc] initWithSize:image.size] autorelease]; [differentImage addRepresentation:differentPixel];
                Require(![color.patternImage.TIFFRepresentation isEqual:differentImage.TIFFRepresentation], @"Negative group fixture patterns are identical");
                v2.color = [NSColor colorWithPatternImage:differentImage];
                Require(group.color == nil, @"Different native patterns incorrectly report color consensus");
                v2.color = color;
            }
            [owner.undoManager enableUndoRegistration]; [undoer endRepetitiveUndo];
            CheckPreferences *preferences = [CheckPreferences memoryPreferences];
            NSString *key = @"DefaultLineColor", *original = @"0.2 0.4 0.6 0.35";
            [preferences setObject:original forKey:key];
            [preferences setColorIfConvertible:color forKey:key];
            NSColor *rgb = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
            if (rgb) CheckColor(rgb, [preferences colorForKey:key]);
            else Require([[preferences objectForKey:key] isEqual:original], @"Unsupported native color corrupted numeric preference");
            CheckGraphColors(graph, color, labelID);
            NSDictionary *structure = Snapshot(XML(Generate(graph)), NO, nil);
            for (NSString *format in @[@"xml", @"zip"]) {
                RSGraph *current = graph;
                for (int pass = 1; pass <= 2; pass++) {
                    NSString *path = [output stringByAppendingPathComponent:[NSString stringWithFormat:@"%02lu-%@-%d.ograph", (unsigned long)index + 1, format, pass]];
                    Require(![[NSFileManager defaultManager] fileExistsAtPath:path], @"Refuse to overwrite a current-document output");
                    NSError *error = nil;
                    Require([current writeToURL:[NSURL fileURLWithPath:path] generatedXMLData:Generate(current)
                        previewPDFData:[format isEqual:@"zip"] ? Preview() : nil error:&error], [NSString stringWithFormat:@"Current document save: %@", error]);
                    current = Load(path, undoer); [graphs addObject:current];
                    CheckGraphColors(current, color, labelID); Compare(structure, Snapshot(XML(Generate(current)), NO, nil), NO);
                }
                (*roundtrips)++; printf("PASS roundtrip-%s sample=%lu\n", format.UTF8String, (unsigned long)index + 1);
            }
            CheckDrawing(graph, [output stringByAppendingPathComponent:[NSString stringWithFormat:@"drawing-%lu.png", (unsigned long)index + 1]]);
            printf("PASS sample=%lu\n", (unsigned long)index + 1);
        } @catch (NSException *exception) {
            (*failed)++; fprintf(stderr, "FAIL current document %lu: %s\n", (unsigned long)index + 1, exception.description.UTF8String);
        } @finally {
            for (RSGraph *graph in graphs) [graph invalidate]; [undoer invalidate];
        }
        (*completed)++;
    }
}

int main(int argc, const char *argv[])
{
    NSUInteger failed = 0, completed = 0, roundtrips = 0, baselines = 0;
    BOOL selfchecks = NO;
    setvbuf(stdout, NULL, _IOLBF, 0);
    @autoreleasepool {
        OFController *controller = nil;
        @try {
            if (argc < 2) { fprintf(stderr, "Usage: DocumentChecks OUTPUT_DIRECTORY [LEGACY_SAMPLE...]\n"); return 2; }
            printf("SELF-CHECK comparator begin\n");
            ComparatorSelfCheck();
            printf("SELF-CHECK comparator passed\n");
            [NSApplication sharedApplication];
            [NSColor setIgnoresAlpha:NO];
            controller = [OFController sharedController];
            Require([controller isKindOfClass:[CheckController class]], @"Runner must select the fatal CheckController");
            [controller didInitialize];
            [controller startedRunning];
            NaNSemanticsCheck();
            selfchecks = YES;
            NSString *output = [NSString stringWithUTF8String:argv[1]];
            if (argc == 2) CurrentDocumentChecks(output, &completed, &roundtrips, &failed);
            for (int i = 2; i < argc; i++) {
                @autoreleasepool {
                    NSString *path = [NSString stringWithUTF8String:argv[i]];
                    CheckOwner *owner = [[[CheckOwner alloc] init] autorelease];
                    RSUndoer *undoer = [[[RSUndoer alloc] initWithOwner:owner] autorelease];
                    NSMutableArray *graphs = [NSMutableArray array];
                    BOOL sampleFailed = NO;
                    @try {
                        printf("CHECK %s\n", [path UTF8String]);
                        NSDictionary *baseline = Baseline(path);
                        if (baseline) baselines++;
                        NSDictionary *source = Snapshot(XML(SourceXML(path)), YES, baseline);
                        RSGraph *graph = Load(path, undoer);
                        [graphs addObject:graph];
                        NSData *firstXML = Generate(graph);
                        NSDictionary *first = Snapshot(XML(firstXML), NO, baseline);
                        // Compare before any save: a stable roundtrip cannot prove initial preservation.
                        @try { Compare(source, first, YES); }
                        @catch (NSException *exception) {
                            sampleFailed = YES;
                            fprintf(stderr, "FAIL first-load %s: %s\n", [path UTF8String], [[exception description] UTF8String]);
                        } // Keep exercising saves even when a historical source comparison fails.
                        for (NSString *format in @[@"xml", @"zip"]) {
                            @try {
                                RSGraph *current = graph;
                                for (int pass = 1; pass <= 2; pass++) {
                                    NSString *saved = [output stringByAppendingPathComponent:
                                        [NSString stringWithFormat:@"%02d-%@-%d.ograph", i - 1, format, pass]];
                                    Require(![[NSFileManager defaultManager] fileExistsAtPath:saved], @"Refuse to overwrite an output");
                                    NSError *error = nil;
                                    NSData *xml = Generate(current);
                                    NSData *preview = [format isEqual:@"zip"] ? Preview() : nil;
                                    Require([current writeToURL:[NSURL fileURLWithPath:saved] generatedXMLData:xml previewPDFData:preview error:&error],
                                            [NSString stringWithFormat:@"Production save: %@", error]);
                                    NSData *bytes = [NSData dataWithContentsOfFile:saved];
                                    BOOL zipped = [bytes length] >= 2 && memcmp([bytes bytes], "PK", 2) == 0;
                                    Require(zipped == [format isEqual:@"zip"], @"Incorrect save container");
                                    current = Load(saved, undoer);
                                    [graphs addObject:current];
                                    Compare(first, Snapshot(XML(Generate(current)), NO, baseline), NO);
                                }
                                roundtrips++;
                                printf("PASS roundtrip-%s sample=%d\n", [format UTF8String], i - 1);
                            } @catch (NSException *exception) {
                                sampleFailed = YES;
                                fprintf(stderr, "FAIL roundtrip-%s %s: %s\n", [format UTF8String], [path UTF8String], [[exception description] UTF8String]);
                            }
                        }
                        printf("%s sample=%d\n", sampleFailed ? "FAIL" : "PASS", i - 1);
                    } @catch (NSException *exception) {
                        sampleFailed = YES;
                        fprintf(stderr, "FAIL %s: %s\n", [path UTF8String], [[exception description] UTF8String]);
                    } @finally {
                        for (RSGraph *graph in graphs) [graph invalidate];
                        [undoer invalidate];
                    }
                    if (sampleFailed) failed++;
                    completed++;
                }
            }
        } @catch (NSException *exception) {
            failed++;
            fprintf(stderr, "FAIL harness: %s\n", [[exception description] UTF8String]);
        } @finally {
            TerminateController(controller);
        }
    } // Drain model objects before writing the completion marker.
    printf("COMPLETE samples=%lu failed=%lu roundtrips=%lu baseline=%lu selfchecks=%d\n",
        (unsigned long)completed, (unsigned long)failed, (unsigned long)roundtrips, (unsigned long)baselines, selfchecks);
    return failed ? 1 : 0;
}
