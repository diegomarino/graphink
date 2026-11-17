#import <AppKit/AppKit.h>
#import "RSDocumentController.h"

@interface ExtensionDocument : NSDocument
@end
@implementation ExtensionDocument
- (NSData *)dataOfType:(NSString *)type error:(NSError **)error { return [@"preserved fixture content" dataUsingEncoding:NSUTF8StringEncoding]; }
@end

// GraphSketcherModel defines these in the app; the fixture links only AppKit.
NSString * const RSGraphFileType = @"com.diegomarino.graphink.document";
NSString * const RSGraphLegacyFileType = @"com.graphsketcher.graphdocument";

// The runner inserts GraphDocument's exact production extension method here.
#import "ProductionExtensionMethod.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        RSDocumentController *controller = [[RSDocumentController alloc] init];
        NSCAssert([NSDocumentController sharedDocumentController] == controller, @"Custom controller must be installed first");
        [NSApplication sharedApplication];
        NSString *type = RSGraphFileType;
        NSCAssert([[ExtensionDocument readableTypes] containsObject:type], @"Graphink UTI must be readable");
        NSCAssert([[ExtensionDocument readableTypes] containsObject:RSGraphLegacyFileType], @"Original UTI must remain readable");
        NSCAssert([[ExtensionDocument writableTypes] containsObject:RSGraphLegacyFileType], @"Original UTI must remain writable for in-place Save");
        NSCAssert([[controller defaultType] isEqual:type], @"New documents must use the Graphink UTI");
        ExtensionDocument *doc = [[ExtensionDocument alloc] init];
        [doc setFileType:type];
        NSCAssert([[doc fileNameExtensionForType:type saveOperation:NSSaveAsOperation] isEqual:@"graphink"], @"New/Save As default must be graphink");
        NSCAssert([[doc fileNameExtensionForType:type saveOperation:NSSaveOperation] isEqual:@"graphink"], @"Untitled Save must default to graphink");
        NSURL *directory = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]] isDirectory:YES];
        NSDictionary *types = @{@"ograph": RSGraphLegacyFileType, @"graphink": RSGraphFileType};
        for (NSString *ext in @[@"ograph", @"graphink"]) {
            NSURL *url = [directory URLByAppendingPathComponent:[@"in-place." stringByAppendingString:ext]];
            type = types[ext];
            [doc setFileType:type];
            [doc setFileURL:url];
            NSCAssert([[doc fileNameExtensionForType:type saveOperation:NSSaveOperation] isEqual:ext], @"Save must preserve existing extension");
            NSCAssert([[doc fileNameExtensionForType:type saveOperation:NSAutosaveInPlaceOperation] isEqual:ext], @"Autosave must preserve existing extension");
            NSCAssert([[doc fileNameExtensionForType:type saveOperation:NSSaveAsOperation] isEqual:@"graphink"], @"Legacy Save As must propose graphink");
            NSError *error = nil;
            NSCAssert([doc saveToURL:url ofType:type forSaveOperation:NSSaveOperation error:&error], @"Save failed: %@", error);
            NSCAssert([[[NSDocumentController sharedDocumentController] typeForContentsOfURL:url error:&error] isEqual:type], @"Each extension must resolve to its own UTI");
            NSCAssert([[doc fileURL] isEqual:url], @"In-place save changed URL");
            NSCAssert([[NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&error] isEqual:@"preserved fixture content"], @"Saved data changed");
        }
        type = RSGraphFileType;
        [doc setFileType:type];
        [doc setFileURL:[directory URLByAppendingPathComponent:@"unrelated.txt"]];
        NSCAssert([[doc fileNameExtensionForType:type saveOperation:NSSaveAsOperation] isEqual:@"graphink"], @"Unknown extension contaminated Save As");
        NSSavePanel *panel = [NSSavePanel savePanel];
        [panel setNameFieldStringValue:@"Legacy.ograph"];
        NSCAssert([doc prepareSavePanel:panel], @"Save panel preparation refused");
        NSCAssert([[panel nameFieldStringValue] isEqual:@"Legacy.graphink"], @"Save As must replace legacy proposal");
        NSCAssert(([[panel allowedFileTypes] isEqual:@[@"graphink", @"ograph"]]), @"Panel must allow both explicit extensions");
        puts("PASS production extension method: new/Save As, legacy/current Save and autosave; NSDocument in-place path/data writes (fixture serializer)");
    }
    return 0;
}
