// Windowless container/codec checks. No NSApplication, document window or user preference writes.
#import <Cocoa/Cocoa.h>
#import <GraphSketcherModel/RSGraphArchive.h>
#import <GraphSketcherModel/RSGraph.h>
#import <GraphSketcherModel/RSUndoer.h>
#import <GraphSketcherModel/RSUndoerOwner.h>
#import <OmniUnzip/OUZipArchive.h>
#import <OmniUnzip/OUUnzipArchive.h>
#import <OmniUnzip/OUUnzipEntry.h>
#import <objc/runtime.h>
#import <OmniFoundation/OFController.h>
static void Check(BOOL value,NSString *reason) { if (!value) { NSLog(@"FAIL: %@",reason); exit(1); } }
@interface ArchiveOwner : NSObject <RSUndoerOwner>
@property(nonatomic,retain) NSUndoManager *undoManager;
@end
@implementation ArchiveOwner
@synthesize undoManager;
- (void)undoerPerformedChange:(RSUndoer *)undoer {}
@end
static BOOL InjectFailure(id self,SEL selector,NSString *name,NSString *type,NSData *data,NSDate *date,NSError **error)
{
    if (error) *error=[NSError errorWithDomain:@"InjectedArchiveWriteFailure" code:1 userInfo:nil]; return NO;
}
static NSString *BeforePath;
static IMP OriginalNormalizer;
static NSData *CaptureNormalization(id self,SEL selector,NSData *data,NSError **error)
{
    [data writeToFile:BeforePath atomically:NO];
    return ((NSData *(*)(id,SEL,NSData *,NSError **))OriginalNormalizer)(self,selector,data,error);
}
static NSURL *BoundedURL;
static IMP OriginalFullRead,OriginalHandleRead;
static NSUInteger FullReads,ActualRead,MaxRequest;
static BOOL GrowAfterPrefix;
static NSData *CountFullRead(id self,SEL selector,NSURL *url,NSDataReadingOptions options,NSError **error)
{
    if ([url isEqual:BoundedURL]) FullReads++;
    return ((NSData *(*)(id,SEL,NSURL *,NSDataReadingOptions,NSError **))OriginalFullRead)(self,selector,url,options,error);
}
static NSData *CountHandleRead(id self,SEL selector,NSUInteger count,NSError **error)
{
    NSData *data=((NSData *(*)(id,SEL,NSUInteger,NSError **))OriginalHandleRead)(self,selector,count,error);
    ActualRead+=data.length; MaxRequest=MAX(MaxRequest,count);
    if (GrowAfterPrefix && count==4) {
        GrowAfterPrefix=NO;
        NSFileHandle *writer=[NSFileHandle fileHandleForWritingToURL:BoundedURL error:error];
        Check(writer!=nil,@"Open disposable growing file");
        Check([writer truncateAtOffset:128*1024*1024+1024 error:error],@"Grow after the reader metadata snapshot");
        [writer closeAndReturnError:NULL];
    }
    return data;
}
static void BoundedReadChecks(NSURL *package,NSString *directory)
{
    NSError *error=nil; NSFileHandle *probe=[NSFileHandle fileHandleForReadingFromURL:package error:&error]; Check(probe!=nil,error.description);
    Method reads=class_getInstanceMethod(object_getClass(probe),@selector(readDataUpToLength:error:));
    Check(reads!=NULL,@"Native bounded file reader exists"); [probe closeAndReturnError:NULL];
    Method full=class_getClassMethod(NSData.class,@selector(dataWithContentsOfURL:options:error:));
    OriginalFullRead=method_setImplementation(full,(IMP)CountFullRead); OriginalHandleRead=method_setImplementation(reads,(IMP)CountHandleRead);
    @try {
        BoundedURL=package; FullReads=ActualRead=MaxRequest=0;
        Check([RSGraphArchive readURL:package error:&error]!=nil,error.description);
        Check(FullReads==0 && ActualRead>0,@"Package reads must be bounded actual IO, never an unbounded whole-file allocation");
        NSURL *growing=[NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"growing.graphink"]];
        Check([[NSData dataWithBytes:"PK\003\004" length:4] writeToURL:growing atomically:NO],@"Create sparse race fixture");
        BoundedURL=growing; FullReads=ActualRead=MaxRequest=0;GrowAfterPrefix=YES;error=nil;
        Check(![RSGraphArchive readURL:growing error:&error] && [error.domain isEqual:@"GraphinkPackage"] && error.code==2,@"Growing ZIP refuses with unsupported-size NSError");
        Check(!GrowAfterPrefix && FullReads==0 && ActualRead==128*1024*1024+1 && MaxRequest<=1024*1024,@"Actual read limit holds after file grows past initial stat size");
        NSLog(@"PASS bounded package IO bytes=%lu maximumRequest=%lu after metadata-race growth",(unsigned long)ActualRead,(unsigned long)MaxRequest);
    } @finally { method_setImplementation(full,OriginalFullRead); method_setImplementation(reads,OriginalHandleRead);BoundedURL=nil; }
}
int main(int argc,const char *argv[]) { @autoreleasepool {
    OFController *controller=OFController.sharedController; [controller didInitialize]; [controller startedRunning];
    if (argc==3 && [@(argv[1]) isEqual:@"--read"]) {
        NSError *failure=nil; NSDictionary *result=[RSGraphArchive readURL:[NSURL fileURLWithPath:@(argv[2])] error:&failure];
        NSDictionary *receipt=@{@"accepted":@(result!=nil),@"error":failure.localizedDescription?:@"",@"reason":failure.localizedFailureReason?:@""};
        NSData *json=[NSJSONSerialization dataWithJSONObject:receipt options:0 error:NULL]; puts([[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] autorelease].UTF8String);
        Check([controller requestTermination]==OFControllerTerminateNow,@"Fixture termination"); [controller willTerminate];
        return result?0:2;
    }
    if (argc==3 && [@(argv[1]) isEqual:@"--preview"]) {
        NSError *failure=nil; NSData *pdf=nil;
        BOOL accepted=[RSGraph getGraphPDFPreviewData:&pdf modificationDate:NULL fromURL:[NSURL fileURLWithPath:@(argv[2])] error:&failure];
        NSData *json=[NSJSONSerialization dataWithJSONObject:@{@"accepted":@(accepted),@"error":failure.localizedDescription?:@"",@"reason":failure.localizedFailureReason?:@""} options:0 error:NULL];
        puts([[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] autorelease].UTF8String);
        [controller requestTermination]; [controller willTerminate]; return accepted?0:2;
    }
    Check(argc==2,@"Pass a fresh output directory");
    NSString *directory=@(argv[1]); Check(![[NSFileManager defaultManager] fileExistsAtPath:directory],@"Evidence already exists");
    NSError *error=nil; Check([[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error],error.description);
    ArchiveOwner *owner=[ArchiveOwner new]; owner.undoManager=[[[NSUndoManager alloc] init] autorelease];
    RSUndoer *undoer=[[RSUndoer alloc] initWithOwner:owner];
    [owner.undoManager disableUndoRegistration]; RSGraph *graph=[[RSGraph alloc] initWithIdentifier:nil undoer:undoer]; [graph setupDefault]; [owner.undoManager enableUndoRegistration];
    NSData *xml=[graph generateXMLOfType:RSGraphFileType frame:NSZeroRect error:&error]; Check(xml!=nil,error.description);
    BeforePath=[directory stringByAppendingPathComponent:@"producer-before.zip"];
    Method normalizer=class_getClassMethod(RSGraphArchive.class,@selector(normalizeProducedZIP:error:));
    OriginalNormalizer=method_setImplementation(normalizer,(IMP)CaptureNormalization);
    NSURL *url=[NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"native.graphink"]];
    NSImage *image=[[[NSImage alloc] initWithSize:NSMakeSize(2,2)] autorelease];
    NSBitmapImageRep *bitmap=[[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:2 pixelsHigh:2 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0] autorelease];
    [bitmap setColor:NSColor.redColor atX:0 y:0]; [image addRepresentation:bitmap];
    NSArray *colors=@[NSColor.redColor,[NSColor colorWithDisplayP3Red:.1 green:.7 blue:.9 alpha:.4],[NSColor colorWithDeviceCyan:.1 magenta:.2 yellow:.3 black:.4 alpha:.6],[NSColor colorWithCatalogName:@"System" colorName:@"textColor"],[NSColor colorWithPatternImage:image],[NSColor colorWithColorSpace:NSColorSpace.extendedSRGBColorSpace components:(CGFloat[]){-.2,1.2,.5,.8} count:4]];
    for (NSColor *color in colors) {
        NSDictionary *defaults=@{@"font-name":@"UnavailableFace-Test",@"line-color":color,@"fill-color":[NSColor colorWithWhite:.3 alpha:0],@"text-color":NSColor.blackColor};
        error=nil; Check([RSGraphArchive writeXML:xml defaults:defaults preview:nil encoding:RSGraphArchiveOPC toURL:url error:&error],error.description);
        NSDictionary *read=[RSGraphArchive readURL:url error:&error]; Check(read!=nil,error.description);
        Check([read[@"xml"] isEqual:xml] && [read[@"encoding"] integerValue]==RSGraphArchiveOPC,@"Payload unchanged / encoding");
        Check([read[@"defaults"][@"font-name"] isEqual:@"UnavailableFace-Test"],@"Unknown face retained");
        NSColor *decoded=read[@"defaults"][@"line-color"];
        BOOL equal=[color isEqual:decoded];
        // Pattern colors compare decoded pixels, not NSImage object identity.
        if (color.type==NSColorTypePattern && decoded.type==NSColorTypePattern) {
            NSBitmapImageRep *a=[NSBitmapImageRep imageRepWithData:color.patternImage.TIFFRepresentation],*b=[NSBitmapImageRep imageRepWithData:decoded.patternImage.TIFFRepresentation];
            equal=a.pixelsWide==b.pixelsWide && a.pixelsHigh==b.pixelsHigh;
            for (NSInteger y=0;y<a.pixelsHigh;y++) for (NSInteger x=0;x<a.pixelsWide;x++) equal&=[[a colorAtX:x y:y] isEqual:[b colorAtX:x y:y]];
        }
        Check(equal, [NSString stringWithFormat:@"Native color fidelity %@ -> %@",color,decoded]);
        Check([read[@"defaults"][@"fill-color"] alphaComponent]==0,@"Zero opacity preserved");
    }
    Check([RSGraphArchive writeXML:xml defaults:nil preview:nil encoding:RSGraphArchiveOPC toURL:url error:&error],error.description);
    NSData *saved=[NSData dataWithContentsOfURL:url];
    method_setImplementation(normalizer,OriginalNormalizer);
    Check([xml writeToFile:[directory stringByAppendingPathComponent:@"payload.xml"] atomically:NO],@"Payload evidence");
    Method method=class_getInstanceMethod(OUZipArchive.class,@selector(appendEntryNamed:fileType:contents:date:error:));
    IMP original=method_setImplementation(method,(IMP)InjectFailure);
    Check(![RSGraphArchive writeXML:xml defaults:nil preview:nil encoding:RSGraphArchiveOPC toURL:url error:&error],@"Injected append must fail");
    method_setImplementation(method,original);
    Check([[NSData dataWithContentsOfURL:url] isEqual:saved],@"Failed write preserves existing destination bytes");
    error=nil;
    Check(![RSGraphArchive writeXML:xml defaults:nil preview:[@"not a PDF" dataUsingEncoding:NSUTF8StringEncoding] encoding:RSGraphArchiveOPC toURL:url error:&error] && error!=nil,@"Invalid declared preview refuses before replacing the destination");
    Check([[NSData dataWithContentsOfURL:url] isEqual:saved],@"Invalid preview preserves previous destination bytes");
    // Independently-produced mixed Stored/Deflate and empty entries exercise physical normalization.
    NSURL *mixed=[NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"mixed.zip"]];
    OUZipArchive *zip=[[[OUZipArchive alloc] initWithPath:mixed.path error:&error] autorelease];
    for (NSUInteger i=0;i<3;i++) Check([zip appendEntryNamed:[NSString stringWithFormat:@"entry%lu.xml",(unsigned long)i] fileType:NSFileTypeRegular contents:i?xml:[NSData data] raw:NO compressionMethod:i==1?0:8 uncompressedSize:0 crc:0 date:nil error:&error],error.description);
    Check([zip close:&error],error.description); NSData *before=[NSData dataWithContentsOfURL:mixed];
    NSData *after=[RSGraphArchive normalizeProducedZIP:before error:&error]; Check(after!=nil,error.description);
    Check([before writeToFile:[directory stringByAppendingPathComponent:@"before.zip"] atomically:NO] && [after writeToFile:[directory stringByAppendingPathComponent:@"after.zip"] atomically:NO],@"Write diff evidence");
    for (NSUInteger length=0;length<before.length;length++) {
        NSData *truncated=[before subdataWithRange:NSMakeRange(0,length)]; error=nil;
        Check(![RSGraphArchive normalizeProducedZIP:truncated error:&error] && error!=nil,@"Every truncation refuses with NSError");
    }
    BoundedReadChecks(url,directory);
    [graph invalidate]; [graph release]; [undoer invalidate]; [undoer release];
    Check([controller requestTermination]==OFControllerTerminateNow,@"Fixture termination"); [controller willTerminate];
    NSLog(@"PASS: native codec, previewless package, immutable XML, failure preservation, mixed ZIP normalization, all truncations");
} return 0; }
