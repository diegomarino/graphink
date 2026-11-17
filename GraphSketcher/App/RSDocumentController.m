#import "RSDocumentController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation RSDocumentController

+ (BOOL)isGraphType:(NSString *)typeName;
{
    return typeName && ([typeName caseInsensitiveCompare:RSGraphFileType] == NSOrderedSame || [typeName caseInsensitiveCompare:RSGraphLegacyFileType] == NSOrderedSame);
}

+ (NSString *)graphTypeForURL:(NSURL *)url;
{
    NSString *extension = [[url pathExtension] lowercaseString];
    if ([extension isEqualToString:@"graphink"])
        return RSGraphFileType;
    if ([extension isEqualToString:@"ograph"])
        return RSGraphLegacyFileType;
    return nil;
}

- (NSString *)typeForContentsOfURL:(NSURL *)url error:(NSError **)outError;
{
    // Other installed copies may still claim these extensions for other types; the extension decides.
    NSString *type = [[self class] graphTypeForURL:url];
    return type ?: [super typeForContentsOfURL:url error:outError];
}

- (void)beginOpenPanel:(NSOpenPanel *)openPanel forTypes:(NSArray<NSString *> *)types completionHandler:(void (^)(NSInteger result))completionHandler;
{
    // Also accept whatever type the system currently resolves for each extension.
    NSMutableArray *acceptedTypes = [NSMutableArray arrayWithArray:types];
    for (NSString *extension in @[@"graphink", @"ograph"]) {
        NSString *extensionType = [UTType typeWithFilenameExtension:extension].identifier;
        if (extensionType && ![acceptedTypes containsObject:extensionType])
            [acceptedTypes addObject:extensionType];
    }
    [super beginOpenPanel:openPanel forTypes:acceptedTypes completionHandler:completionHandler];
}

@end
