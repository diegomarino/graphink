// Production GraphDocument save/read/undo paths, windowless. No app nib or field editor.
#import "GraphDocument.h"
#import "GraphWindowController.h"
#import "RSStylePresets.h"
#import <GraphSketcherModel/RSGraph.h>
#import <GraphSketcherModel/RSGraphEditor.h>
#import <GraphSketcherModel/RSUndoer.h>
#import <GraphSketcherModel/RSTextLabel.h>
#import <OmniFoundation/OFController.h>
#import <OmniUnzip/OUZipArchive.h>
#import <OmniUnzip/OUUnzipArchive.h>
#import <OmniUnzip/OUUnzipEntry.h>
#import "RSSelector.h"
#import "RSMode.h"
#import "RSTextTool.h"
@implementation GraphWindowController @end // Class reference only; never instantiated.
@interface GraphDocument (ArchiveTests)
- (RSGraphArchiveEncoding)_encodingForSaveOperation:(NSSaveOperationType)operation URL:(NSURL *)url;
@end
static void DrainDocumentEvents(void) {
    __block BOOL reached=NO; dispatch_async(dispatch_get_main_queue(),^{ reached=YES; });
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:1];
    while (!reached && deadline.timeIntervalSinceNow>0) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:deadline];
}
static void Check(BOOL value,NSString *reason) { if (!value) [NSException raise:@"DocumentArchiveFailure" format:@"%@",reason]; }
@interface CheckedDocument : GraphDocument @end
@implementation CheckedDocument
- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error {
    NSLog(@"WRITE target=%@ fileURL=%@ type=%@ origin=%ld",url,self.fileURL,type,(long)self.archiveEncoding);
    return [super writeToURL:url ofType:type error:error];
}
@end
@implementation RSMode
+ (RSMode *)sharedModeController { static RSMode *mode; if (!mode) mode=[[self alloc] init]; return mode; }
- (NSUInteger)mode { return RS_text; }
- (void)toolWasUsed:(NSUInteger)mode {}
@end
@interface TextContext : NSView
@property(nonatomic,assign) GraphDocument *document;
@end
@implementation TextContext
- (RSGraphEditor *)editor { return self.document.editor; }
- (RSGraph *)graph { return self.document.graph; }
- (RSSelector *)RSSelector { return self.document.selectorObject; }
- (void)deselect { [self.document.selectorObject deselect]; }
- (void)setSelection:(id)object { [self.document.selectorObject setSelection:object]; }
- (BOOL)wasEditingText { return NO; }
- (void)setWasEditingText:(BOOL)value {}
- (void)startEditingLabel {} // Creation is observed before an AppKit field editor starts.
@end
static void NewText(GraphDocument *doc,NSString *expected) {
    TextContext *view=[[[TextContext alloc] initWithFrame:NSMakeRect(0,0,520,340)] autorelease];view.document=doc;
    [doc.editor updateBounds:view.bounds]; [doc.selectorObject setHalfSelection:nil];
    RSTextTool *tool=[[[RSTextTool alloc] initWithView:(id)view] autorelease];
    [doc.undoManager disableUndoRegistration]; @try { [tool mouseUp:nil]; } @finally { [doc.undoManager enableUndoRegistration]; }
    RSTextLabel *label=(id)doc.selectorObject.selection;
    Check([label isKindOfClass:RSTextLabel.class] && [[[label.attributedString attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL] fontName] isEqual:expected],@"Production Text route uses reopened document face");
    [doc.undoManager disableUndoRegistration]; [doc.graph removeLabel:label]; [doc.selectorObject deselect]; [doc.undoManager enableUndoRegistration];
}
static GraphDocument *Document(void) {
    NSError *error=nil; GraphDocument *document=[[[CheckedDocument alloc] initWithType:RSGraphFileType error:&error] autorelease];
    Check(document!=nil,error.description); document.undoManager.groupsByEvent=NO; return document;
}
static void Write(GraphDocument *doc,NSURL *url) {
    NSError *error=nil; Check([doc writeToURL:url ofType:RSGraphFileType error:&error],error.description);
}
int main(int argc,const char *argv[]) { @autoreleasepool { @try {
    OFController *controller=OFController.sharedController; [controller didInitialize]; [controller startedRunning];
    Check(argc==2,@"Pass a fresh output directory");
    NSString *directory=@(argv[1]); Check(![[NSFileManager defaultManager] fileExistsAtPath:directory],@"Evidence exists");
    NSError *error=nil; Check([[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error],error.description);
    Check(RSRegisterStyleFonts(NSBundle.mainBundle,&error),error.description);
    GraphDocument *doc=Document(); Check(doc.archiveEncoding==RSGraphArchiveOPC && doc.graph.creationDefaults!=nil,@"New documents use OPC/local defaults");
    NSURL *(^URL)(NSString *)=^NSURL *(NSString *name){return [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:name]];};
    NSURL *first=URL(@"first.graphink");
    GraphDocument *writer=Document(); Write(writer,first);
    Check([[RSGraphArchive readURL:first error:&error][@"encoding"] integerValue]==RSGraphArchiveOPC,@"New previewless write is OPC");
    [doc setFileURL:first]; // Match NSDocument safe-save lifecycle with an owned writable target.
    [doc updateChangeCount:NSChangeCleared];
    Check([doc.editor applyStylePreset:2],@"Chalkboard applies"); DrainDocumentEvents();
    Check(doc.isDocumentEdited && [doc.graph.creationDefaults[@"font-name"] isEqual:@"Kalam-Regular"],@"Saved local defaults edit/dirty");
    NSDictionary *chalk=[[doc.graph.creationDefaults copy] autorelease];
    [doc.undoManager undo]; Check(![doc.graph.creationDefaults[@"font-name"] isEqual:@"Kalam-Regular"],@"Undo includes creation defaults");
    [doc.undoManager redo]; Check(RSCreationDefaultsEqual(doc.graph.creationDefaults,chalk),@"Redo includes defaults");
    NewText(doc,@"Kalam-Regular");
    Write(doc,first);
    GraphDocument *reopened=[[[CheckedDocument alloc] initWithContentsOfURL:first ofType:RSGraphFileType error:&error] autorelease]; Check(reopened!=nil,error.description); reopened.undoManager.groupsByEvent=NO;
    Check(!reopened.isDocumentEdited && !reopened.undoManager.canUndo,@"Reopen is clean without undo");
    Check(RSCreationDefaultsEqual(reopened.graph.creationDefaults,chalk),@"OPC defaults reopen");
    Check(![reopened.editor applyStylePreset:2],@"Reopened preset fixed point");
    Check(!reopened.isDocumentEdited && !reopened.undoManager.canUndo,@"No-op no dirty/undo");
    NewText(reopened,@"Kalam-Regular");
    [reopened.undoManager beginUndoGrouping]; RSSetLocalCreationValue(reopened.graph,@"font-name",@"HelveticaNeue"); [reopened.undoManager endUndoGrouping];DrainDocumentEvents();
    [reopened.undoManager beginUndoGrouping]; RSSetLocalCreationValue(reopened.graph,@"font-name",@"Georgia"); [reopened.undoManager endUndoGrouping];DrainDocumentEvents();
    [reopened.undoManager undo]; Check([reopened.graph.creationDefaults[@"font-name"] isEqual:@"HelveticaNeue"],@"Separate explicit default edits retain separate undo state");
    [reopened.undoManager undo]; Check([reopened.graph.creationDefaults[@"font-name"] isEqual:@"Kalam-Regular"],@"Default edit undo returns to saved values");
    [reopened.undoManager removeAllActions]; [reopened updateChangeCount:NSChangeCleared];
    // Recognized unsupported envelope cannot replace the graph/editor or mutate undo/dirty.
    NSURL *bad=URL(@"future.graphink");
    OUUnzipArchive *source=[[[OUUnzipArchive alloc] initWithPath:first.path error:&error] autorelease];
    OUZipArchive *badZIP=[[[OUZipArchive alloc] initWithPath:bad.path error:&error] autorelease];
    for (OUUnzipEntry *entry in source.entries) {
        NSData *part=[source dataForEntry:entry error:&error];
        if ([entry.name isEqual:@"graphink/document.xml"]) {
            NSString *control=[[[NSString alloc] initWithData:part encoding:NSUTF8StringEncoding] autorelease];
            part=[[control stringByReplacingOccurrencesOfString:@"version=\"1\"" withString:@"version=\"99\""] dataUsingEncoding:NSUTF8StringEncoding];
        }
        Check([badZIP appendEntryNamed:entry.name fileType:NSFileTypeRegular contents:part date:nil error:&error],error.description);
    }
    Check([badZIP close:&error],error.description);
    NSData *normalized=[RSGraphArchive normalizeProducedZIP:[NSData dataWithContentsOfURL:bad] error:&error];Check(normalized && [normalized writeToURL:bad atomically:NO],error.description);
    RSGraph *previous=reopened.graph; RSGraphEditor *previousEditor=reopened.editor;
    [reopened.undoManager beginUndoGrouping]; RSSetLocalCreationValue(reopened.graph,@"text-color",NSColor.redColor);[reopened.undoManager endUndoGrouping];DrainDocumentEvents();
    BOOL dirty=reopened.isDocumentEdited,undo=reopened.undoManager.canUndo; NSDictionary *previousDefaults=[[reopened.graph.creationDefaults copy] autorelease];
    error=nil; Check(![reopened readFromURL:bad ofType:RSGraphFileType error:&error] && error!=nil,@"Unsupported envelope rejected");
    Check(reopened.graph==previous && reopened.editor==previousEditor && reopened.isDocumentEdited==dirty && reopened.undoManager.canUndo==undo && RSCreationDefaultsEqual(previousDefaults,reopened.graph.creationDefaults),@"Rejected read preserves existing model/editor/dirty/undo/defaults");
    NSDictionary *archive=[RSGraphArchive readURL:first error:&error];
    NSData *xml=archive[@"xml"];
    NSURL *legacy=URL(@"legacy.ograph"); Check([xml writeToURL:legacy atomically:NO],@"Legacy fixture");
    GraphDocument *old=[[[CheckedDocument alloc] initWithContentsOfURL:legacy ofType:RSGraphFileType error:&error] autorelease]; Check(old!=nil,error.description);
    Check(old.archiveEncoding==RSGraphArchiveLegacyXML && old.graph.creationDefaults==nil && old.requiresCreationDefaultsSaveAs,@"Old file fallback/adoption gate");
    NSURL *same=URL(@"legacy-normal-save.graphink"); Write(old,same);
    Check([[RSGraphArchive readURL:same error:&error][@"encoding"] integerValue]==RSGraphArchiveLegacyXML,@"Legacy ordinary Save retains origin regardless of extension");
    Check([old _encodingForSaveOperation:NSSaveAsOperation URL:first]==RSGraphArchiveOPC,@"Explicit SaveAs chooses OPC");
    Check([old _encodingForSaveOperation:NSAutosaveOperation URL:first]==RSGraphArchiveLegacyXML,@"Recovery retains legacy origin");
    // Exercise synchronous NSDocument safe-save operation, including temporary output path.
    NSURL *adopted=URL(@"adopted.graphink");
    NSLog(@"SAFE-SAVE source=%@ destination=%@ fileURL=%@ type=%@ operation=%lu origin=%ld sourceExists=%d targetExists=%d",legacy,adopted,old.fileURL,old.fileType,(unsigned long)NSSaveAsOperation,(long)old.archiveEncoding,[[NSFileManager defaultManager] fileExistsAtPath:legacy.path],[[NSFileManager defaultManager] fileExistsAtPath:adopted.path]);
    error=nil; BOOL adoptedOK=[old saveToURL:adopted ofType:RSGraphFileType forSaveOperation:NSSaveAsOperation error:&error];
    for (NSError *nested=error;nested;nested=nested.userInfo[NSUnderlyingErrorKey]) NSLog(@"SAFE-SAVE error domain=%@ code=%ld userInfo=%@",nested.domain,(long)nested.code,nested.userInfo);
    Check(adoptedOK,error.description);
    Check(old.archiveEncoding==RSGraphArchiveOPC && old.graph.creationDefaults!=nil && !old.requiresCreationDefaultsSaveAs,@"Successful explicit adoption");
    Check([[RSGraphArchive readURL:URL(@"adopted.graphink") error:&error][@"encoding"] integerValue]==RSGraphArchiveOPC,@"Adopted container");
    // XML/ZIP legacy import with preview omitted must not become raw XML on normal Save.
    NSURL *legacyZIP=URL(@"legacy-zip.graphink"); Check([RSGraphArchive writeXML:xml defaults:nil preview:nil encoding:RSGraphArchiveLegacyZIP toURL:legacyZIP error:&error],error.description);
    GraphDocument *zipped=[[[CheckedDocument alloc] initWithContentsOfURL:legacyZIP ofType:RSGraphFileType error:&error] autorelease]; Check(zipped!=nil,error.description); Write(zipped,URL(@"legacy-zip-normal.graphink"));
    Check([[RSGraphArchive readURL:URL(@"legacy-zip-normal.graphink") error:&error][@"encoding"] integerValue]==RSGraphArchiveLegacyZIP,@"Legacy ZIP preserved without preview");
    [controller requestTermination]; [controller willTerminate];
    NSLog(@"PASS production GraphDocument: new OPC, dirty/undo/redo, reopen/no-op, legacy origin, explicit safe SaveAs");
} @catch(NSException *exception) { NSLog(@"FAIL: %@",exception);return 1; } } return 0; }
