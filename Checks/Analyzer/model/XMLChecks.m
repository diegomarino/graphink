// Exercise production NSObject XML methods with the actual OFXMLDocument receiver.
// No app delegate, application instance, event loop, or UI.
#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFXMLDocument.h>
#import <OmniFoundation/OFXMLElement.h>
#import <OmniFoundation/OFXMLString.h>
#import <OmniFoundation/NSData-OFEncoding.h>
#import "../../../GraphSketcher/Model/XML/OFObject-XML.h"
#import <GraphSketcherModel/RSDataImporter.h>
#import <GraphSketcherModel/RSGraph.h>
#import "../../../GraphSketcher/OmniStyle/Basic/OSURLStyleAttribute.h"
#include <assert.h>
#include <dlfcn.h>

// Private to OSURLStyleAttribute.m; the check calls it directly.
@interface OSURLStyleAttribute (XMLChecks)
- (id)copyValueFromPropertyList:(id)plist;
@end

static BOOL released;
@interface ModelLifetimeProbe : NSObject @end
@implementation ModelLifetimeProbe
- (void)dealloc { released = YES; [super dealloc]; }
@end

static OFXMLDocument *Document(void)
{
    NSError *error = nil;
    OFXMLDocument *doc = [[OFXMLDocument alloc] initWithRootElementName:@"fixture"
        dtdSystemID:NULL dtdPublicID:nil whitespaceBehavior:nil
        stringEncoding:kCFStringEncodingUTF8 error:&error];
    assert(doc != nil && error == nil);
    return [doc autorelease];
}

static NSData *Bytes(OFXMLDocument *doc)
{
    NSError *error = nil;
    NSData *bytes = [doc xmlData:&error];
    assert(bytes != nil && error == nil);
    return bytes;
}

int main(void)
{
    @autoreleasepool {
        NSString *domain = [[NSBundle mainBundle] bundleIdentifier];
        assert([domain isEqual:@"org.graphink.analyzer.model.xml-fixture"]);
        NSString *routingKey = [@"AnalyzerRoutingProbe-" stringByAppendingString:[[NSUUID UUID] UUIDString]];
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setObject:@"fixture-only" forKey:routingKey];
        assert([defaults synchronize]);
        id routed = (id)CFPreferencesCopyAppValue((CFStringRef)routingKey, (CFStringRef)domain);
        BOOL routingMatches = [routed isEqual:@"fixture-only"];
        [routed release];
        [defaults removeObjectForKey:routingKey];
        assert([defaults synchronize]);
        assert(routingMatches);
        id *application = (id *)dlsym(RTLD_DEFAULT, "NSApp");
        assert(application == NULL || *application == nil);
        assert(NSClassFromString(@"LinkBack") == nil);
        // The original implementation forwarded nil for absent/empty data.
        // Use an id receiver to characterize the runtime contract despite the
        // stricter OFXMLDocument declaration; OFXMLElement accepts nil explicitly.
        OFXMLDocument *legacy = Document();
        [(id)legacy appendElement:@"data" containingString:nil];
        NSData *emptyBytes = Bytes(legacy);
        for (id value in @[[NSNull null], [NSData data], [@"hello" dataUsingEncoding:NSUTF8StringEncoding]]) {
            NSMutableDictionary *object = [NSMutableDictionary dictionary];
            if (value != [NSNull null]) object[@"payload"] = value;
            OFXMLDocument *doc = Document();
            NSData *result = [object writeData:@"payload" document:doc elementName:@"data"];
            BOOL empty = value == [NSNull null] || [value length] == 0;
            assert(empty ? result == nil : [result isEqual:value]);
            NSData *bytes = Bytes(doc);
            if (empty) assert([bytes isEqual:emptyBytes]);
            NSError *error = nil;
            OFXMLDocument *reopened = [[[OFXMLDocument alloc] initWithData:bytes whitespaceBehavior:nil error:&error] autorelease];
            assert(reopened != nil && error == nil);
            OFXMLElement *element = [[reopened rootElement] firstChildNamed:@"data"];
            assert(element != nil);
            NSString *text = OFCharacterDataFromElement(element);
            assert(empty ? [text length] == 0 : [text isEqual:@"aGVsbG8="]);
        }
        // Optional zero is present but omitted; required zero is serialized.
        NSMutableDictionary *object = [NSMutableDictionary dictionaryWithObject:@0 forKey:@"number"];
        OFXMLDocument *doc = Document();
        assert([[object writeOptionalIntegerNumber:@"number" document:doc elementName:@"optional"] isEqual:@0]);
        assert([[doc rootElement] firstChildNamed:@"optional"] == nil);
        assert([[object writeRequiredIntegerNumber:@"number" document:doc elementName:@"required"] isEqual:@0]);
        assert([OFCharacterDataFromElement([[doc rootElement] firstChildNamed:@"required"]) isEqual:@"0"]);
        printf("PASS actual OFXMLDocument nil/empty byte equality, base64 roundtrip, optional/required zero\n");

        NSInteger sentinel = 73;
        assert(![RSDataImporter detectColumnTypes:@[] intoArray:&sentinel] && sentinel == 73);
        assert(![RSDataImporter detectColumnTypes:@[@[]] intoArray:&sentinel] && sentinel == 73);
        NSInteger types[2] = {-1, -1};
        NSArray *table = @[@[@"label", @"value"], @[@"a", @"0"], @[@"b", @"2"]];
        assert([RSDataImporter detectColumnTypes:table intoArray:types]);
        assert(types[0] == RS_LABEL_COL && types[1] == RS_FLOAT_COL);
        RSDataImporter *importer = [[RSDataImporter alloc] init];
        ModelLifetimeProbe *probe = [[ModelLifetimeProbe alloc] init];
        importer.warning = (id)probe;
        [probe release]; [importer release];
        assert(released);
        released = NO;
        // Allocate without initialization to isolate dealloc's retained map slot;
        // this intentionally does not claim full graph lifecycle acceptance.
        RSGraph *graph = [RSGraph alloc];
        probe = [[ModelLifetimeProbe alloc] init];
        NSMutableDictionary *map = [[NSMutableDictionary alloc] initWithObjectsAndKeys:probe, @"old-id", nil];
        graph.idPasteMap = map;
        [probe release]; [map release]; [graph release];
        assert(released);
        OSURLStyleAttribute *attribute = [[OSURLStyleAttribute alloc] initWithKey:@"fixture-url"];
        for (id input in @[[NSNull null], @"", @42, @"https://example.com/path"]) {
            id plist = input == [NSNull null] ? nil : input;
            NSURL *url = [attribute copyValueFromPropertyList:plist];
            assert(url != nil);
            assert([[url absoluteString] isEqual:input == [NSNull null] || [input isEqual:@42] ? @"" : input]);
            [url release];
        }
        [attribute release];
        assert(application == NULL || *application == nil);
        printf("PASS production model detector outputs, retained slots, URL nil/empty/invalid/valid values; NSApp remains nil\n");
    }
    return 0;
}
