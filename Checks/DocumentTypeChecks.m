// Windowless document-type checks: each extension opens with its own UTI, Save keeps it, Save As to
// .graphink adopts Graphink's type. Production App sources; no application delegate or launch loop.
#import <GraphSketcherModel/RSGraph.h>
#import <GraphSketcherModel/RSGraphArchive.h>
#import <GraphSketcherModel/RSUndoer.h>
#import <GraphSketcherModel/RSUndoerOwner.h>
#import "AppController.h"
#import "GraphDocument.h"
#import "RSDocumentController.h"

static NSUInteger Failures;
static void Check(BOOL condition, NSString *message) {
    if (!condition) { Failures++; printf("FAIL %s\n", message.UTF8String); }
}
#define CHECK(condition, ...) Check((condition), [NSString stringWithFormat:__VA_ARGS__])

@interface Owner : NSObject <RSUndoerOwner>
@end
@implementation Owner { NSUndoManager *_undoManager; }
- (id)init { if ((self = [super init])) _undoManager = [[NSUndoManager alloc] init]; return self; }
- (NSUndoManager *)undoManager { return _undoManager; }
- (void)undoerPerformedChange:(RSUndoer *)undoer {}
- (void)dealloc { [_undoManager release]; [super dealloc]; }
@end

static NSInteger ModelEncoding(NSURL *url, NSString *type) {
    Owner *owner = [[[Owner alloc] init] autorelease];
    RSUndoer *undoer = [[[RSUndoer alloc] initWithOwner:owner] autorelease];
    NSError *error = nil; NSInteger encoding = -1;
    RSGraph *graph = [RSGraph graphFromURL:url type:type undoer:undoer encoding:&encoding error:&error];
    CHECK(graph != nil, @"model reopen %@ as %@: %@", url.lastPathComponent, type, error);
    [undoer invalidate];
    return graph ? encoding : -1;
}

static GraphDocument *Open(NSURL *url, NSString *expectedType) {
    NSDocumentController *controller = [NSDocumentController sharedDocumentController];
    NSError *error = nil;
    NSString *type = [controller typeForContentsOfURL:url error:&error];
    CHECK([type isEqual:expectedType], @"%@ maps to %@, expected %@", url.lastPathComponent, type, expectedType);
    GraphDocument *document = (GraphDocument *)[controller makeDocumentWithContentsOfURL:url ofType:type error:&error];
    CHECK([document isKindOfClass:[GraphDocument class]], @"open %@: %@", url.lastPathComponent, error);
    CHECK([document.fileType isEqual:expectedType], @"%@ fileType %@", url.lastPathComponent, document.fileType);
    CHECK(![document shouldRunSavePanelWithAccessoryView], @"%@ save panel must not offer a File Format popup", url.lastPathComponent);
    return document;
}

static void SaveAs(GraphDocument *document, NSURL *url, NSString *passedType, NSString *expectedType, RSGraphArchiveEncoding expectedEncoding) {
    NSError *error = nil;
    CHECK([document saveToURL:url ofType:passedType forSaveOperation:NSSaveAsOperation error:&error], @"Save As %@: %@", url.lastPathComponent, error);
    CHECK([document.fileURL isEqual:url] && [document.fileType isEqual:expectedType], @"Save As %@ gave %@ %@", url.lastPathComponent, document.fileURL.lastPathComponent, document.fileType);
    CHECK(document.archiveEncoding == expectedEncoding, @"Save As %@ encoding %ld", url.lastPathComponent, (long)document.archiveEncoding);
    CHECK([[[NSDocumentController sharedDocumentController] typeForContentsOfURL:url error:&error] isEqual:expectedType], @"Saved %@ type", url.lastPathComponent);
    CHECK(ModelEncoding(url, expectedType) == expectedEncoding, @"Saved %@ container", url.lastPathComponent);
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 3) { fprintf(stderr, "usage: checks LEGACY_OGRAPH SCRATCH_DIR\n"); return 2; }
        NSURL *legacySample = [NSURL fileURLWithPath:@(argv[1])], *scratch = [NSURL fileURLWithPath:@(argv[2]) isDirectory:YES];
        [[[RSDocumentController alloc] init] autorelease];  // first controller becomes shared, as in main.m
        [[[NSBundle mainBundle] principalClass] sharedApplication];
        AppController *app = (AppController *)[OFController sharedController];
        CHECK([app isKindOfClass:[AppController class]], @"production AppController");
        [app didInitialize];
        NSDocumentController *controller = [NSDocumentController sharedDocumentController];
        NSFileManager *files = [NSFileManager defaultManager];

        // Registration as NSDocumentController reads it from the production Info.plist.
        CHECK([RSGraphFileType isEqual:@"com.diegomarino.graphink.document"] && [RSGraphLegacyFileType isEqual:@"com.graphsketcher.graphdocument"], @"model type constants");
        CHECK([controller.defaultType isEqual:RSGraphFileType], @"default type %@", controller.defaultType);
        CHECK(([controller.documentClassNames isEqual:@[@"GraphDocument"]]), @"document classes %@", controller.documentClassNames);
        CHECK([controller documentClassForType:RSGraphFileType] == [GraphDocument class] && [controller documentClassForType:RSGraphLegacyFileType] == [GraphDocument class], @"both types use GraphDocument");
        CHECK([[controller displayNameForType:RSGraphFileType] isEqual:@"Graphink Document"], @"new kind %@", [controller displayNameForType:RSGraphFileType]);
        CHECK([[controller displayNameForType:RSGraphLegacyFileType] isEqual:@"GraphSketcher Document"], @"legacy kind %@", [controller displayNameForType:RSGraphLegacyFileType]);
        CHECK([[GraphDocument readableTypes] containsObject:RSGraphFileType] && [[GraphDocument readableTypes] containsObject:RSGraphLegacyFileType], @"readable %@", [GraphDocument readableTypes]);
        CHECK([[GraphDocument writableTypes] containsObject:RSGraphFileType] && [[GraphDocument writableTypes] containsObject:RSGraphLegacyFileType], @"writable %@", [GraphDocument writableTypes]);
        CHECK([RSDocumentController isGraphType:@"COM.DIEGOMARINO.GRAPHINK.DOCUMENT"] && [RSDocumentController isGraphType:@"Com.GraphSketcher.GraphDocument"] && ![RSDocumentController isGraphType:@"public.data"], @"type comparison");
        CHECK([[RSDocumentController graphTypeForURL:[NSURL fileURLWithPath:@"/x/A.GRAPHINK"]] isEqual:RSGraphFileType] && [RSDocumentController graphTypeForURL:[NSURL fileURLWithPath:@"/x/a.zip"]] == nil, @"extension mapping");
        NSError *error = nil;
        Owner *owner = [[[Owner alloc] init] autorelease];
        RSUndoer *undoer = [[[RSUndoer alloc] initWithOwner:owner] autorelease];
        CHECK([RSGraph graphFromURL:legacySample type:@"public.data" undoer:undoer error:&error] == nil, @"model must refuse an unrelated type");
        [undoer invalidate];

        // 1. .ograph opens as the original type; Save keeps path, type and container.
        NSURL *ograph = [scratch URLByAppendingPathComponent:@"legacy.ograph"];
        CHECK([files copyItemAtURL:legacySample toURL:ograph error:&error], @"copy sample: %@", error);
        GraphDocument *legacy = Open(ograph, RSGraphLegacyFileType);
        CHECK(legacy.archiveEncoding == RSGraphArchiveLegacyZIP, @"legacy sample container %ld", (long)legacy.archiveEncoding);
        CHECK([[legacy fileNameExtensionForType:legacy.fileType saveOperation:NSSaveOperation] isEqual:@"ograph"], @"legacy Save extension");
        CHECK([legacy saveToURL:ograph ofType:legacy.fileType forSaveOperation:NSSaveOperation error:&error], @"legacy Save: %@", error);
        CHECK([legacy.fileURL isEqual:ograph] && [legacy.fileType isEqual:RSGraphLegacyFileType] && legacy.archiveEncoding == RSGraphArchiveLegacyZIP, @"legacy Save changed %@ %@ %ld", legacy.fileURL.lastPathComponent, legacy.fileType, (long)legacy.archiveEncoding);
        CHECK(ModelEncoding(ograph, RSGraphLegacyFileType) == RSGraphArchiveLegacyZIP, @"legacy Save container");

        // 2. Save As from .ograph proposes .graphink; the panel passes the document's (legacy) type.
        CHECK([[legacy fileNameExtensionForType:legacy.fileType saveOperation:NSSaveAsOperation] isEqual:@"graphink"], @"legacy Save As extension");
        SaveAs(legacy, [scratch URLByAppendingPathComponent:@"adopted.graphink"], RSGraphLegacyFileType, RSGraphFileType, RSGraphArchiveOPC);
        GraphDocument *adopted = Open([scratch URLByAppendingPathComponent:@"adopted.graphink"], RSGraphFileType);
        CHECK(adopted.archiveEncoding == RSGraphArchiveOPC, @"adopted reopens as OPC");
        [adopted close]; [legacy close];

        // 3. A phase-1 .graphink (old container, new extension) opens as Graphink's type and keeps its container on Save.
        NSURL *phase1 = [scratch URLByAppendingPathComponent:@"phase1.graphink"];
        CHECK([files copyItemAtURL:legacySample toURL:phase1 error:&error], @"copy sample: %@", error);
        GraphDocument *renamed = Open(phase1, RSGraphFileType);
        CHECK([renamed saveToURL:phase1 ofType:renamed.fileType forSaveOperation:NSSaveOperation error:&error], @"phase-1 Save: %@", error);
        CHECK([renamed.fileType isEqual:RSGraphFileType] && renamed.archiveEncoding == RSGraphArchiveLegacyZIP && ModelEncoding(phase1, RSGraphFileType) == RSGraphArchiveLegacyZIP, @"phase-1 Save changed type or container");

        // 4. Save As to .ograph remains possible and takes the original type; the container follows existing policy.
        SaveAs(renamed, [scratch URLByAppendingPathComponent:@"back.ograph"], RSGraphFileType, RSGraphLegacyFileType, RSGraphArchiveLegacyZIP);
        [renamed close];

        // 5. New documents use Graphink's type and save as OPC .graphink.
        GraphDocument *fresh = (GraphDocument *)[controller makeUntitledDocumentOfType:controller.defaultType error:&error];
        CHECK([fresh isKindOfClass:[GraphDocument class]] && [fresh.fileType isEqual:RSGraphFileType], @"new document %@: %@", fresh.fileType, error);
        CHECK([[fresh fileNameExtensionForType:fresh.fileType saveOperation:NSSaveOperation] isEqual:@"graphink"], @"new document extension");
        SaveAs(fresh, [scratch URLByAppendingPathComponent:@"new.graphink"], fresh.fileType, RSGraphFileType, RSGraphArchiveOPC);
        [fresh close];

        CHECK([app requestTermination] == OFControllerTerminateNow, @"controller termination");
        [app willTerminate];
        if (!Failures) printf("PASS document types: .graphink/.ograph mapping, kinds, open, Save, Save As adoption, new documents\n");
        printf("COMPLETE failures=%lu\n", (unsigned long)Failures);
        return Failures ? 1 : 0;
    }
}
