#import <AppKit/AppKit.h>

// Defined by GraphSketcherModel: .graphink (Graphink's exported type) and .ograph (original type, imported).
extern NSString * const RSGraphFileType;
extern NSString * const RSGraphLegacyFileType;

@interface RSDocumentController : NSDocumentController
+ (BOOL)isGraphType:(NSString *)typeName;
+ (NSString *)graphTypeForURL:(NSURL *)url; // nil unless the extension is .graphink or .ograph
@end
