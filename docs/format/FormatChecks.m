// Offscreen production-model IO probe. No application window or document UI.
#import <Cocoa/Cocoa.h>
#import <OmniFoundation/OmniFoundation.h>
#import <GraphSketcherModel/RSGraph.h>
#import <GraphSketcherModel/RSUndoer.h>
#import <GraphSketcherModel/RSUndoerOwner.h>
#import <GraphSketcherModel/RSVertex.h>
#import <GraphSketcherModel/RSConnectLine.h>
#import <GraphSketcherModel/RSAxis.h>
#import <OmniBase/assertions.h>

@interface FormatOwner : NSObject <RSUndoerOwner>
@property(nonatomic, retain) NSUndoManager *undoManager;
@end
@implementation FormatOwner
@synthesize undoManager = _undoManager;
- (id)init { if ((self = [super init])) _undoManager = [[NSUndoManager alloc] init]; return self; }
- (void)undoerPerformedChange:(RSUndoer *)undoer {}
- (void)dealloc { [_undoManager release]; [super dealloc]; }
@end
@interface FormatController : OFController
@end
@implementation FormatController
- (BOOL)crashOnAssertionOrUnhandledException { return YES; }
- (void)handleFailureInMethod:(SEL)selector object:(id)object file:(NSString *)file lineNumber:(int)line format:(NSString *)format arguments:(va_list)args
{ fprintf(stderr, "FATAL ASSERTION %s:%d\n", file.UTF8String, line); _Exit(3); }
- (void)handleFailureInFunction:(NSString *)function file:(NSString *)file lineNumber:(int)line format:(NSString *)format arguments:(va_list)args
{ fprintf(stderr, "FATAL ASSERTION %s:%d\n", file.UTF8String, line); _Exit(3); }
@end
static void Check(BOOL ok) { if (!ok) [NSException raise:@"FormatCheck" format:@"Check failed"]; }
int main(int argc, const char **argv) {
    @autoreleasepool { @try {
        if (argc != 3) return 2;
        [NSColor setIgnoresAlpha:NO];
        OFController *controller = [OFController sharedController];
        [controller didInitialize]; [controller startedRunning];
        FormatOwner *owner = [[[FormatOwner alloc] init] autorelease];
        RSUndoer *undoer = [[[RSUndoer alloc] initWithOwner:owner] autorelease];
        NSError *error = nil;
        RSGraph *graph = [RSGraph graphFromURL:[NSURL fileURLWithPath:@(argv[1])] type:RSGraphFileType undoer:undoer error:&error];
        Check(graph != nil);
        NSData *xml = [graph generateXMLOfType:RSGraphFileType frame:CGRectZero error:&error]; Check(xml != nil);
        NSString *stem = @(argv[2]);
        Check([graph writeToURL:[NSURL fileURLWithPath:[stem stringByAppendingString:@".xml"]] generatedXMLData:xml previewPDFData:nil error:&error]);
        // A valid empty one-page PDF probes packaging, not graph rendering.
        NSMutableData *pdf = [NSMutableData data];
        CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((CFMutableDataRef)pdf);
        CGRect box = CGRectMake(0, 0, 520, 420);
        CGContextRef context = CGPDFContextCreate(consumer, &box, NULL);
        CGPDFContextBeginPage(context, NULL); CGPDFContextEndPage(context); CGPDFContextClose(context);
        CGContextRelease(context); CGDataConsumerRelease(consumer);
        Check([graph writeToURL:[NSURL fileURLWithPath:[stem stringByAppendingString:@".zip"]] generatedXMLData:xml previewPDFData:pdf error:&error]);
        for (NSString *ext in @[@".xml", @".zip"]) {
            RSGraph *again = [RSGraph graphFromURL:[NSURL fileURLWithPath:[stem stringByAppendingString:ext]] type:RSGraphFileType undoer:undoer error:&error]; Check(again != nil);
            Check([again.Vertices count] == [graph.Vertices count] && [again.Lines count] == [graph.Lines count]);
        }
        printf("PASS vertices=%lu lines=%lu canvas=%.0fx%.0f x=%.0f:%.0f y=%.0f:%.0f\n", (unsigned long)[graph.Vertices count], (unsigned long)[graph.Lines count], graph.canvasSize.width, graph.canvasSize.height, graph.xAxis.min, graph.xAxis.max, graph.yAxis.min, graph.yAxis.max);
        Check([controller requestTermination] == OFControllerTerminateNow); [controller willTerminate];
        return 0;
    } @catch (NSException *exception) { fprintf(stderr, "FAIL %s\n", exception.description.UTF8String); return 1; } }
}
