#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, RSGraphArchiveEncoding) {
    RSGraphArchiveLegacyXML,
    RSGraphArchiveLegacyZIP,
    RSGraphArchiveOPC
};

@interface RSGraphArchive : NSObject
// Reads/gates the container before any graph model is constructed. Raw XML APIs remain separate.
+ (NSDictionary *)readURL:(NSURL *)url error:(NSError **)error;
+ (BOOL)writeXML:(NSData *)xml defaults:(NSDictionary *)defaults preview:(NSData *)preview encoding:(RSGraphArchiveEncoding)encoding toURL:(NSURL *)url error:(NSError **)error;
// Narrow physical producer adaptation, also exercised independently by regression fixtures.
+ (NSData *)normalizeProducedZIP:(NSData *)data error:(NSError **)error;
@end
