// Copyright 2003-2013 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSUserDefaults-OAExtensions.h>
#import "GraphDocument.h"
#import "RSDocumentController.h"
#import "RSStylePresets.h"
#import "AppController.h"

#import "GraphWindowController.h"
#import "RSGraphView.h"
#import "RSLabelFinder.h"
#import "RSSelector.h"

#import <LinkBack/LinkBack.h>
#import <GraphSketcherModel/OFPreference-RSExtensions.h>
#import <GraphSketcherModel/RSGraph.h>
#import <GraphSketcherModel/RSGraphEditor.h>
#import <GraphSketcherModel/RSGrid.h>
#import <GraphSketcherModel/RSGroup.h>
#import <GraphSketcherModel/RSHitTester-Snapping.h>
#import <GraphSketcherModel/RSTextLabel.h>
#import <GraphSketcherModel/RSUndoer.h>
#import <AppKit/NSColor.h>

NSString *RSErrorDomain = @"OmniGraphSketcher Error Domain";

@implementation GraphDocument

////////////////////////////////////////////
#pragma mark -
#pragma mark Class methods
//////
- (NSWindow *)window;
{
    NSArray *controllers = [self windowControllers];
    if (!controllers || ![controllers count]) {
	OBASSERT_NOT_REACHED("No windowControllers found");
	return nil;
    }
    
    NSWindowController *windowController = [controllers objectAtIndex:0];
    NSWindow *window = [windowController window];
    return window;
}

////////////////////////////////////////////
#pragma mark -
#pragma mark init/dealloc
//////

- (id)init;
{
    self = [super init];
    if (!self)
	return nil;

    // Add your subclass-specific initialization here.
    // If an error occurs here, send a [self release] message and return nil.
    
    _isFromFile = NO;
    _isInAppBundle = NO;
    _isCatalogCopy = NO;
    _isAutosaving = NO;
    _archiveEncoding = RSGraphArchiveOPC;
    _graphView = nil;  // this will be set by the windowController on awakeFromNib.
    
    _linkBack = nil;
    
    // reset "user font"
    //[NSFont setUserFont:[[OFPreferenceWrapper sharedPreferenceWrapper] fontForKey:@"DefaultLabelFont"]];
    
    // Set up Undo
    [self setHasUndoManager:YES];
    // create undo management object
    _u = [(RSUndoer *)[RSUndoer alloc] initWithOwner:self];
    _addedElements = [[NSMutableArray alloc] init];
    
    // create selection object
    _s = [(RSSelector *)[RSSelector alloc] initWithDocument:self];
    
    // Autosave timing is AppKit's (autosavesInPlace, autosavingDelay left at 0). The historical
    // 120 s delay postponed the first autosave of an untitled document past a crash 30 s later.
    // After a crash, window restoration reopens the autosaved untitled document, edited. (Restoring
    // after Quit also needs macOS's "Close windows when quitting an application" off.)

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(undoManagerWillUndoOrRedo:) name:NSUndoManagerWillUndoChangeNotification object:[self undoManager]];
    [nc addObserver:self selector:@selector(undoManagerWillUndoOrRedo:) name:NSUndoManagerWillRedoChangeNotification object:[self undoManager]];
    [nc addObserver:self selector:@selector(undoManagerDidUndoOrRedo:) name:NSUndoManagerDidUndoChangeNotification object:[self undoManager]];
    [nc addObserver:self selector:@selector(undoManagerDidUndoOrRedo:) name:NSUndoManagerDidRedoChangeNotification object:[self undoManager]];
    
    DEBUG_RS(@"GraphDocument init");
	
    return self;
}

// This gets called only when opening a new, blank document
- (id)initWithType:(NSString *)typeName error:(NSError **)outError;
{
    if ([super initWithType:typeName error:outError] == nil)
        return nil;

    RSGraph *graph;
    [[_u undoManager] disableUndoRegistration];
    @try {
        graph = [[[RSGraph alloc] initWithIdentifier:nil undoer:_u] autorelease];
        [graph setupDefault];
        graph.creationDefaults = @{};
    } @finally {
        [[_u undoManager] enableUndoRegistration];
    }
    
    assert(_editor == nil);
    _editor = [[RSGraphEditor alloc] initWithGraph:graph undoer:_u];
    _editor.delegate = self;
    
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[self undoManager] removeAllActions];
    [self setUndoManager:nil];
    
    [_u invalidate];
    [_s release];
    
    [_editor invalidate];
    [_u release]; // RSGraphEditor calls -invalidate
    _u = nil;
    
    [_addedElements release];
    
    [super dealloc];
}



////////////////////////////////////////////////
#pragma mark -
#pragma mark Opening/Saving
////////////////////////////////////////////////
+ (BOOL)shouldLoadFile:(NSString *)fileName
 writtenByNewerVersion:(OFVersionNumber *)fileVersion
	    appVersion:(OFVersionNumber *)appVersion;
{
    NSString *appName = [[[NSBundle mainBundle] infoDictionary] objectForKey:(id)kCFBundleNameKey];
    
    NSString *titleFormat = NSLocalizedStringFromTableInBundle(@"'%1$@' was written by a newer version of '%2$@'", nil, [GraphDocument bundle], @"newer file format alert title");
    NSString *title = [NSString stringWithFormat:titleFormat, fileName, appName];
    
    NSString *messageFormat = NSLocalizedStringFromTableInBundle(@"The file was written with version %1$@ while the version of %2$@ you are running understands files written by version %3$@ and older.  Loading this file may not work correctly and might lose some data.", nil, [GraphDocument bundle], @"newer file format alert message");
    NSString *message = [NSString stringWithFormat:messageFormat, [fileVersion cleanVersionString], appName, [appVersion cleanVersionString]];
    
    NSInteger rc = NSRunAlertPanel(title, @"%@", NSLocalizedStringFromTableInBundle(@"Open File", nil, [GraphDocument bundle], @"alert panel button title"), NSLocalizedStringFromTableInBundle(@"Cancel", nil, [GraphDocument bundle], @"alert panel button"), message, nil);
    return (rc == NSAlertDefaultReturn);
}

- (void)becomeUntitledWithType:(NSString *)docType;
{
    [self setFileURL:nil];
    [self setFileType:docType]; // Resetting this is important so that the document inspector will display the correct state for the 'compressed' checkbox before you've saved the document.
}

////////////////////////////////////////////////
#pragma mark -
#pragma mark NSDocument subclass
////////////////////////////////////////////////

- (NSString *)fileNameExtensionForType:(NSString *)typeName saveOperation:(NSSaveOperationType)saveOperation;
{
    if (![RSDocumentController isGraphType:typeName])
        return [super fileNameExtensionForType:typeName saveOperation:saveOperation];

    // Save As adopts the new brand; existing documents keep their path on Save/autosave.
    if (saveOperation == NSSaveOperation || saveOperation == NSAutosaveInPlaceOperation || saveOperation == NSAutosaveElsewhereOperation) {
        NSString *extension = [[self fileURL] pathExtension];
        if ([extension length] && ([extension caseInsensitiveCompare:@"ograph"] == NSOrderedSame || [extension caseInsensitiveCompare:@"graphink"] == NSOrderedSame))
            return extension;
    }
    return @"graphink";
}

- (BOOL)prepareSavePanel:(NSSavePanel *)savePanel;
{
    if (![super prepareSavePanel:savePanel])
        return NO;
    if ([RSDocumentController isGraphType:[self fileType]]) {
        // Use explicit tags because the system UTI may belong to an older app copy.
        [savePanel setAllowedFileTypes:@[@"graphink", @"ograph"]];
        NSString *name = [savePanel nameFieldStringValue];
        if ([[name pathExtension] caseInsensitiveCompare:@"ograph"] == NSOrderedSame)
            name = [name stringByDeletingPathExtension];
        if (![[[name pathExtension] lowercaseString] isEqualToString:@"graphink"])
            name = [name stringByAppendingPathExtension:@"graphink"];
        [savePanel setNameFieldStringValue:name];
        // Saving a legacy .ograph makes a Graphink copy: show the new extension (the panel hides
        // extensions by default, which left only "Legacy" in the name field).
        if ([[[[self fileURL] pathExtension] lowercaseString] isEqualToString:@"ograph"])
            [savePanel setExtensionHidden:NO];
    }
    return YES;
}

- (BOOL)shouldRunSavePanelWithAccessoryView;
{
    // Both graph types are writable; the chosen extension picks the type, so no File Format popup.
    return ![RSDocumentController isGraphType:[self fileType]] && [super shouldRunSavePanelWithAccessoryView];
}

- (NSString *)_typeForSaveToURL:(NSURL *)url ofType:(NSString *)typeName;
{
    // .graphink saves get Graphink's type and .ograph saves the original one, whatever type the caller passed.
    NSString *extensionType = [RSDocumentController isGraphType:typeName] ? [RSDocumentController graphTypeForURL:url] : nil;
    return extensionType ?: typeName;
}

+ (BOOL)autosavesInPlace;
{
    return YES;
}

- (BOOL)canAsynchronouslyWriteToURL:(NSURL *)url ofType:(NSString *)typeName forSaveOperation:(NSSaveOperationType)saveOperation;
{
    // Saving commits AppKit controls and renders the live graph view into a PDF preview.
    return NO;
}

- (BOOL)isDocumentEdited;
{
    // Don't pay attention to edits in bundled graphs like Getting Started.
    if ([self isInAppBundle])
        return NO;
    
    return [super isDocumentEdited];
}

- (void)makeWindowControllers;
{
    GraphWindowController *windowController = [[GraphWindowController alloc] init];
    [self addWindowController:windowController];
    [windowController release];
}



#pragma mark File writing/exporting

//#define GRAPH_DOCUMENT_QUICKLOOK_THUMBNAIL_MAX_SIZE 256

// Thumbnails are now generated from preview.pdf by the QuickLook plugin.  That way they don't take up extra space in the file, and look better in Cover Flow in the Finder.
//
//    // Generate and add a Quicklook thumbnail image
//    NSImage *thumbImage = [[[NSImage alloc] initWithData:qlData] autorelease];
//    // Scale down image if necessary
//    NSSize canvasSize = [_graph canvasSize];
//    NSSize thumbSize = canvasSize;
//    if (canvasSize.width > GRAPH_DOCUMENT_QUICKLOOK_THUMBNAIL_MAX_SIZE || canvasSize.height > GRAPH_DOCUMENT_QUICKLOOK_THUMBNAIL_MAX_SIZE) {
//        float scale = MIN(GRAPH_DOCUMENT_QUICKLOOK_THUMBNAIL_MAX_SIZE/canvasSize.width, GRAPH_DOCUMENT_QUICKLOOK_THUMBNAIL_MAX_SIZE/canvasSize.height);
//        OBASSERT(scale > 0);
//        thumbSize = NSMakeSize(nearbyint(canvasSize.width * scale),
//                               nearbyint(canvasSize.height * scale));
//    }
//    [thumbImage setSize:thumbSize];
//    DEBUG_RS(@"Creating thumbnail with size: %@", NSStringFromSize(thumbSize));
//    // Create tiff data
//    NSData *thumbnailData = [thumbImage TIFFRepresentation];//UsingCompression:NSTIFFCompressionLZW factor:0.0];
//    if (![zipArchive appendZipMemberWithData:thumbnailData preferredFilename:@"thumbnail.tiff" error:outError]) {
//        return NO;
//    }

- (BOOL)writeToURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError;
{
    // Tell tools/editors to clean and update the model.
    if (!_isAutosaving && _graphView) {
        [_graphView commitEditing];
        [_editor prepareForSave];
    }
    
    // Preview is derived; autosave retains the document container without generating it.
    NSData *previewPDFData = nil;
    if (!_isAutosaving && ![[OFPreferenceWrapper sharedPreferenceWrapper] boolForKey:@"SaveFilesAsPlainXML"]) {
        // Generate a Quicklook preview and add it to the zip archive
        if (!_graphView) {
            // This happens if we are upgrading a legacy graph file
            //OBASSERT_NOT_REACHED("There is no graphView to generate a pdf");
            //return NO;
        }
        else if ( [[OFPreferenceWrapper sharedPreferenceWrapper] boolForKey:@"IncludeQuicklookPreview"] ) {
            previewPDFData = [_graphView dataWithPDFInsideRect:[_graphView bounds]];
        }
    }
    
    NSRect frame = NSZeroRect;
    if ([[self windowControllers] count])  // this will be false during upgrading of a legacy file
        frame = [[self window] frame];
    
    NSData *xmlData = [_editor.graph generateXMLOfType:typeName frame:frame error:outError];
    if (!xmlData) {
        if (outError != NULL)
            OBASSERT(*outError);
        return NO;
    }
    
    NSDictionary *creationDefaults=[[_editor.graph.creationDefaults copy] autorelease];
    RSGraphArchiveEncoding encoding=_hasWriteArchiveEncoding?_writeArchiveEncoding:_archiveEncoding;
    // The snapshot is complete before writing the archive.
#if defined(MAC_OS_X_VERSION_10_7) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7
    [self unblockUserInteraction];
#endif
    
    BOOL result = [RSGraphArchive writeXML:xmlData defaults:creationDefaults preview:previewPDFData encoding:encoding toURL:absoluteURL error:outError];
    
    //sleep(5);
    return result;
}


- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)typeName forSaveOperation:(NSSaveOperationType)saveOperation originalContentsURL:(NSURL *)absoluteOriginalContentsURL error:(NSError **)outError;
{
    // With autosavesInPlace AppKit never calls -autosaveDocumentWithDelegate:..., so every autosave
    // (in place, elsewhere, as a draft) is recognized here: it writes no preview and does not end
    // the editing in progress.
    BOOL autosave = saveOperation == NSAutosaveInPlaceOperation || saveOperation == NSAutosaveElsewhereOperation || saveOperation == NSAutosaveAsOperation;
    BOOL previous = _isAutosaving;
    _isAutosaving = previous || autosave;
    @try { return [super writeToURL:url ofType:typeName forSaveOperation:saveOperation originalContentsURL:absoluteOriginalContentsURL error:outError]; }
    @finally { _isAutosaving = previous; }
}

- (void)autosaveDocumentWithDelegate:(id)delegate didAutosaveSelector:(SEL)didAutosaveSelector contextInfo:(void *)contextInfo;
// Autosave documentation is at: http://developer.apple.com/documentation/Cocoa/Conceptual/Documents/Articles/Autosaving.html#//apple_ref/doc/uid/TP40003276
{
    if ([self isInAppBundle])
        return;
    
#ifdef DEBUG
    NSDate *startTime = [NSDate date];
#endif
    
    _isAutosaving = YES;
    [super autosaveDocumentWithDelegate:delegate didAutosaveSelector:didAutosaveSelector contextInfo:contextInfo];
    _isAutosaving = NO;
    
#ifdef DEBUG
    NSLog(@"Autosave elapsed time: %f", [startTime timeIntervalSinceNow]);
#endif
}


- (RSGraphArchiveEncoding)archiveEncoding { return _archiveEncoding; }
- (BOOL)requiresCreationDefaultsSaveAs { return _archiveEncoding!=RSGraphArchiveOPC; }
- (RSGraphArchiveEncoding)_encodingForSaveOperation:(NSSaveOperationType)operation URL:(NSURL *)url;
{
    return operation==NSSaveAsOperation && [url.pathExtension.lowercaseString isEqual:@"graphink"]?RSGraphArchiveOPC:_archiveEncoding;
}
- (NSError *)_bundledSaveError;
{
    return [NSError errorWithDomain:RSErrorDomain code:RSBundledGraphDocument userInfo:@{NSLocalizedDescriptionKey:NSLocalizedString(@"Cannot modify bundled example graphs.",@"error description")}];
}
- (void)saveToURL:(NSURL *)url ofType:(NSString *)typeName forSaveOperation:(NSSaveOperationType)operation completionHandler:(void (^)(NSError *))completionHandler;
{
    if (self.isInAppBundle) { if (completionHandler) completionHandler([self _bundledSaveError]); return; }
    typeName=[self _typeForSaveToURL:url ofType:typeName];
    BOOL previousActive=_hasWriteArchiveEncoding; RSGraphArchiveEncoding previous=_writeArchiveEncoding;
    RSGraphArchiveEncoding target=[self _encodingForSaveOperation:operation URL:url];
    _hasWriteArchiveEncoding=YES; _writeArchiveEncoding=target;
    [super saveToURL:url ofType:typeName forSaveOperation:operation completionHandler:^(NSError *error){
        self->_hasWriteArchiveEncoding=previousActive; self->_writeArchiveEncoding=previous;
        if (!error && (operation==NSSaveAsOperation || operation==NSSaveOperation)) {
            self->_archiveEncoding=target;
            if (target==RSGraphArchiveOPC && !self->_editor.graph.creationDefaults) {
                NSUndoManager *manager=self.undoManager; [manager disableUndoRegistration];
                @try { self->_editor.graph.creationDefaults=@{}; } @finally { [manager enableUndoRegistration]; }
            }
        }
        if (completionHandler) completionHandler(error);
    }];
}
- (BOOL)saveToURL:(NSURL *)url ofType:(NSString *)typeName forSaveOperation:(NSSaveOperationType)operation error:(NSError **)outError;
{
    if (self.isInAppBundle) { if (outError) *outError=[self _bundledSaveError]; return NO; }
    typeName=[self _typeForSaveToURL:url ofType:typeName];
    BOOL previousActive=_hasWriteArchiveEncoding; RSGraphArchiveEncoding previous=_writeArchiveEncoding;
    RSGraphArchiveEncoding target=previousActive?_writeArchiveEncoding:[self _encodingForSaveOperation:operation URL:url];
    _hasWriteArchiveEncoding=YES; _writeArchiveEncoding=target;
    BOOL saved=NO;
    @try { saved=[super saveToURL:url ofType:typeName forSaveOperation:operation error:outError]; }
    @finally { _hasWriteArchiveEncoding=previousActive; _writeArchiveEncoding=previous; }
    if (saved && (operation==NSSaveAsOperation || operation==NSSaveOperation)) {
        _archiveEncoding=target;
        if (target==RSGraphArchiveOPC && !_editor.graph.creationDefaults) {
            NSUndoManager *manager=self.undoManager; [manager disableUndoRegistration];
            @try { _editor.graph.creationDefaults=@{}; } @finally { [manager enableUndoRegistration]; }
        }
    }
    return saved;
}

- (void)saveDocumentWithDelegate:(id)delegate didSaveSelector:(SEL)didSaveSelector contextInfo:(void *)contextInfo;
{
    // If this is a LinkBack document, don't display a "save as" panel (just send the edits back to the LinkBack client).
    if (_linkBack != nil) {
        [self sendLinkEdit];
        
        // Perform the callback so that AppKit will close the window and/or do other cleanup tasks
        //- (void)document:(NSDocument *)doc didSave:(BOOL)didSave contextInfo:(void  *)contextInfo
        if (delegate) {
            void (*delegateImp)(id self, SEL _cmd, NSDocument *doc, BOOL didSave, void *contextInfo);
            delegateImp = (typeof(delegateImp))[delegate methodForSelector:didSaveSelector];
            OBASSERT(delegateImp);
            if (delegateImp)
                delegateImp(delegate, didSaveSelector, self, YES, contextInfo);
        }
        return;
    }
    
    [super saveDocumentWithDelegate:delegate didSaveSelector:didSaveSelector contextInfo:contextInfo];
}




# pragma mark File reading/importing

- (void)_adoptGraph:(RSGraph *)graph undoer:(RSUndoer *)undoer encoding:(RSGraphArchiveEncoding)encoding;
{
    // Only a fully parsed graph may replace the editor, undo history and origin mode.
    _graphView.editor=nil;
    [_s deselect];
    [self.undoManager removeAllActions];
    [_editor invalidate]; [_editor release]; _editor=nil;
    [_u invalidate]; [_u release]; _u=[undoer retain];
    _archiveEncoding=encoding; _isFromFile=YES;
    _editor=[[RSGraphEditor alloc] initWithGraph:graph undoer:_u];
    _editor.delegate=self; _graphView.editor=_editor;
}
- (BOOL)readOGSFileFromData:(NSData *)data fileName:(NSString *)fileName error:(NSError **)outError;
{
    RSUndoer *pending=[[RSUndoer alloc] initWithOwner:self];
    RSGraph *graph=[RSGraph graphFromData:data fileName:fileName type:RSGraphFileType undoer:pending error:outError];
    if (graph) [self _adoptGraph:graph undoer:pending encoding:RSGraphArchiveLegacyXML];
    else [pending invalidate];
    [pending release]; return graph!=nil;
}
- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)outError;
{
    RSUndoer *pending=[[RSUndoer alloc] initWithOwner:self]; NSInteger encoding;
    RSGraph *graph=[RSGraph graphFromURL:url type:typeName undoer:pending encoding:&encoding error:outError];
    if (graph) [self _adoptGraph:graph undoer:pending encoding:encoding];
    else [pending invalidate];
    [pending release]; return graph!=nil;
}

- (NSString *)displayName;
{
    if (_linkBack) {
        return [NSString stringWithFormat: @"LinkBack from %@ (%@)", [_linkBack sourceName], [_linkBack sourceApplicationName]];
    } else
        return [super displayName];
}



////////////////////////////////////////////////
#pragma mark -
#pragma mark LinkBack
////////////////////////////////////////////////

@synthesize linkBack = _linkBack;
- (void)setLinkBack:(LinkBack *)link;
{
    if (_linkBack == link)
        return;
    
    if (_linkBack)
        [_linkBack release];
    
    _linkBack = [link retain];
    
    if (!_linkBack)
        return;
    
    // If there is a new, non-nil linkback link, then read its data into this document.
    NSDictionary *linkBackData = [[link pasteboard] propertyListForType: LinkBackPboardType];
    NSData *documentXMLData = [linkBackData linkBackAppData];
    NSError *outError = nil;
    [self readOGSFileFromData:documentXMLData fileName:[self displayName] error:&outError];
}

- (void)sendLinkEdit;
{
    NSPasteboard *pasteboard = [_linkBack pasteboard];
    [self copyAsImageWithPasteboard:pasteboard];
    
    [_linkBack sendEdit];
    
    [self updateChangeCount: NSChangeCleared] ;
}

- (void)closeLinkBackConnection;
{
    if (!_linkBack)
        return;
    
    [_linkBack closeLink];
}

- (void)linkBackConnectionDidClose:(LinkBack *)link;
{
    OBASSERT(_linkBack == link);
    
    [self retain];
    [link setRepresentedObject:nil];
    
    // If there are no unsaved changes, simply close the linkback document.
    if (![self isDocumentEdited]) {
        [self close];
        [self release];
        return;
    }
    
    // If there are unsaved changes, ask the user whether to close or convert to untitled.
    NSString *alertTitle = [NSString stringWithFormat:NSLocalizedString(@"%@ has closed the connection for this LinkBack attachment.  Do you want to keep the changes?", "broken linkback connection dialog - alert text"), [link sourceApplicationName]];
    NSString *errorDescription = NSLocalizedString(@"This document has modifications that cannot be saved because %@ has closed the connection to it or exited.  You may preserve your changes by making this document untitled and severing the link, or you may close this window and abandon your changes.", "broken linkback connection dialog - alert text");
    
    NSBeginAlertSheet(alertTitle,
                      NSLocalizedString(@"Make Untitled", "broken linkback connection dialog - alert button"),
                      NSLocalizedString(@"Don't Save", "broken linkback connection dialog - alert button"),
                      nil,
                      [self windowForSheet],
                      self,
                      @selector(_linkBackDidCloseSheetDidEnd:returnCode:contextInfo:),
                      NULL,
                      nil,
                      errorDescription,
                      [link sourceApplicationName]);
    // _linkBackDidCloseSheetDidEnd:returnCode:contextInfo: will release the document when it gets called (to match the retain at the top of this method)

}

- (void)_linkBackDidCloseSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
{
    if (returnCode == NSAlertDefaultReturn) {
        [self setLinkBack:nil];
        [[NSDocumentController sharedDocumentController] addDocument:self];
        [[self windowControllers] makeObjectsPerformSelector:@selector(synchronizeWindowTitleWithDocumentName)];
    } else  
        [self close];
    
    [self autorelease];  // matches the retain in -linkBackConnectionDidClose:
}

#pragma mark -
#pragma mark RSUndoerOwner

- (void)undoerPerformedChange:(RSUndoer *)undoer;
{
    // RSUndoer registers on this document's undo manager, and NSDocument already counts each closed
    // undo group as one change (and each undo/redo). Counting the registration again made one undo
    // leave the document edited with nothing left to undo.
}

#pragma mark -
#pragma mark RSGraphEditorDelegate

- (void)graphEditorDidUpdate:(RSGraphEditor *)editor;
{
    //don't do this, because we are sometimes called from -drawRect:
    //[_graphView setNeedsDisplay:YES];
    
    [_s sendChange:self];
}

- (void)graphEditorNeedsDisplay:(RSGraphEditor *)editor;
{
    OBPRECONDITION(editor == _editor);
    [_graphView setNeedsDisplay:YES];
    [[(RSGraphView *)_graphView labelFinder] contentDidChange];
}

- (void)graphEditorDeselect:(RSGraphEditor *)editor;
{
    OBPRECONDITION(editor == _editor);

    [(RSGraphView *)_graphView deselect];
    //[_s deselect];
}

- (void)graphEditor:(RSGraphEditor *)editor addedElementDuringUndoOrRedo:(id)element;
{
    OBPRECONDITION(editor == _editor);

    //[_s setSelection:obj];
    [_addedElements addObject:element];
}

////////////////////////////////////////////////
#pragma mark -
#pragma mark Printing
////////////////////////////////////////////////
- (void)printDocument:(id)sender {
    NSPrintInfo *pInfo = [self printInfo];
    [pInfo setHorizontallyCentered:YES];
    [pInfo setVerticallyCentered:YES];
    [pInfo setHorizontalPagination:NSFitPagination];
    [pInfo setVerticalPagination:NSFitPagination];
    [pInfo setLeftMargin:30];
    [pInfo setRightMargin:30];
    [pInfo setTopMargin:30];
    [pInfo setBottomMargin:30];
    
    [_graphView commitEditing];
    
    NSPrintOperation *op = [NSPrintOperation
			    printOperationWithView:_graphView
			    printInfo:pInfo]; //[self printInfo]]; // default printInfo
    
    [op runOperationModalForWindow:[self windowForSheet]
			  delegate:self
		    didRunSelector:@selector(printOperationDidRun:success:contextInfo:)
		       contextInfo:NULL];
}

- (void)printOperationDidRun:(NSPrintOperation *)printOperation
		     success:(BOOL)success
		 contextInfo:(void *)info {
    if (success) {
        // Can save updated NSPrintInfo, but only if you have
        // a specific reason for doing so
        // [self setPrintInfo: [printOperation printInfo]];
	
    }
}



/////////////////////////////////////////////
#pragma mark -
#pragma mark Menu items
/////////////////////////////////////////////

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    SEL menuAction = [menuItem action];
    
    if (menuAction == @selector(applyStylePreset:)) return _editor != nil;
    if (menuAction == @selector(saveDocument:)) {
	return !_isInAppBundle;
    }
    else if (menuAction == @selector(revertDocumentToSaved:)) {
        return ([self isDocumentEdited] && [self fileURL]);
    }
    else if (menuAction == @selector(connectPoints:)) {
	if ( [RSGraph hasMultipleVertices:[_s selection]] )
	    [menuItem setTitle:NSLocalizedString(@"In Selection Order", @"Menu item")];
	else
	    [menuItem setTitle:NSLocalizedString(@"In Creation Order", @"Menu item")];
    }
    else if (menuAction == @selector(bestFitLine:)) {
	if ( [_s selected] )
	    [menuItem setTitle:NSLocalizedString(@"Insert Best-Fit Line for Selection", @"Menu item")];
	else
	    [menuItem setTitle:NSLocalizedString(@"Insert Best-Fit Line", @"Menu item")];
    }
    else if (menuAction == @selector(histogram:)) {
	if ( [_editor.graph displayHistogram] ) {
	    //[menuItem setTitle:@"Hide Grid"];
	    [menuItem setState:NSOnState];
	} else {
	    //[menuItem setTitle:@"Display Grid"];
	    [menuItem setState:NSOffState];
	}
    }
    else if (menuAction == @selector(toggleContinuousSpellCheckingRS:)) {
	if ( [[OFPreferenceWrapper sharedPreferenceWrapper] boolForKey:@"UseContinuousSpellChecking"] ) {
	    [menuItem setState:NSOnState];
	} else {
	    [menuItem setState:NSOffState];
	}
    }
    else if (menuAction == @selector(toggleWindowOpacity:)) {
	if ( [self windowIsOpaque] )
	    [menuItem setState:NSOffState];
	else
	    [menuItem setState:NSOnState];
    }
    // now pass request along to graphView
    return [_graphView validateMenuItem:menuItem];
}
- (void)performMenuItem:(SEL)menuAction;
{
    [self performMenuItem:menuAction withName:nil];
}
- (void)performMenuItem:(SEL)menuAction withName:(NSString *)actionName;
{
    // pass request along to graphView
    [_graphView performMenuItem:menuAction withName:actionName];
}

// The toolbar's Show/Hide Grid item targets the first responder. The graph view is only in the
// responder chain while the canvas has focus; the document always is, so it forwards the action
// (as the menu's View > Show Grid does through AppController).
- (IBAction)showHideGrid:(id)sender;
{
    [_graphView showHideGrid:sender];
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)item;
{
    SEL sel = [item action];
    if (sel == @selector(printDocument:)) {
        return YES;
    }
    else if (sel == @selector(toggleWindowOpacity:)) {
        if ([self windowIsOpaque]) {
            [item setLabel:NSLocalizedString(@"Transparent Window", @"Toolbar label")];
            [item setImage:[NSImage imageNamed:@"transparentWindowIcon"]];
        }
        else {
            [item setLabel:NSLocalizedString(@"Opaque Window", @"Toolbar label")];
            [item setImage:[NSImage imageNamed:@"opaqueWindowIcon"]];
        }
        return YES;
    }
    
    // pass request along to graphView
    return [_graphView validateToolbarItem:item];
}

- (IBAction)applyStylePreset:(id)sender
{
    if ([sender tag]<0 || (NSUInteger)[sender tag]>=RSStylePresetNames().count) return;
    if ([self requiresCreationDefaultsSaveAs]) {
        NSAlert *alert=[[[NSAlert alloc] init] autorelease];
        alert.messageText=NSLocalizedString(@"Save a Graphink copy before applying a style",@"Legacy style adoption");
        alert.informativeText=NSLocalizedString(@"This document uses a legacy format. Choose Save As and save a .graphink copy, then apply the style again. Cancel leaves the document unchanged.",@"Legacy style adoption explanation");
        [alert addButtonWithTitle:NSLocalizedString(@"Save As…",@"Save As button")];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel",@"Cancel button")];
        if ([alert runModal]==NSAlertFirstButtonReturn) [self saveDocumentAs:nil];
        return;
    }
    if (![self.window makeFirstResponder:self.window]) return;
    if ([_editor applyStylePreset:[sender tag]]) [_s sendChange:self];
}

- (IBAction)makeCurrentSettingsDefault:(id)sender;
{
    RSGraph *graph = _editor.graph;
    OFPreferenceWrapper *prefWrapper = [OFPreferenceWrapper sharedPreferenceWrapper];
    
    // Label fonts
    RSTextLabel *recentLabel = [[graph Labels] lastObject];
    [prefWrapper setFontDescriptor:[recentLabel fontDescriptor] forKey:@"DefaultLabelFont"];
    [prefWrapper setFontDescriptor:[[[graph xAxis] maxLabel] fontDescriptor] forKey:@"DefaultXAxisTickLabelFont"];
    [prefWrapper setFontDescriptor:[[[graph yAxis] maxLabel] fontDescriptor] forKey:@"DefaultYAxisTickLabelFont"];
    [prefWrapper setFontDescriptor:[[[graph xAxis] title] fontDescriptor] forKey:@"DefaultXAxisTitleFont"];
    [prefWrapper setFontDescriptor:[[[graph yAxis] title] fontDescriptor] forKey:@"DefaultYAxisTitleFont"];
    
    // Axis visibility settings
    [prefWrapper setBool:[graph displayAxes] forKey:@"DisplayAxis"];
    [prefWrapper setBool:[graph displayAxisLabels] forKey:@"DisplayAxisTickLabels"];
    [prefWrapper setBool:[graph displayAxisTicks] forKey:@"DisplayAxisTicks"];
    [prefWrapper setDouble:[[graph xAxis] tickWidthIn] forKey:@"DefaultAxisTickWidthIn"];
    [prefWrapper setDouble:[[graph xAxis] tickWidthOut] forKey:@"DefaultAxisTickWidthOut"];
    [prefWrapper setBool:[graph displayAxisTitles] forKey:@"DisplayAxisTitles"];
    [prefWrapper setObject:nameFromPlacement([[graph xAxis] placement]) forKey:@"DefaultAxisPlacement"];
    [prefWrapper setBool:[[graph xAxis] displayGrid] forKey:@"DisplayVerticalGrid"];
    [prefWrapper setBool:[[graph yAxis] displayGrid] forKey:@"DisplayHorizontalGrid"];
    [prefWrapper setBool:[[graph xAxis] shape] forKey:@"DefaultAxisShape"];
    
    // Axis style settings
    [[OFPreferenceWrapper sharedPreferenceWrapper] setColorIfConvertible:[[graph xAxis] color] forKey:@"DefaultAxisColor"];
    [prefWrapper setDouble:[[graph xAxis] width] forKey:@"DefaultAxisWidth"];
    [[OFPreferenceWrapper sharedPreferenceWrapper] setColorIfConvertible:[[graph xGrid] color] forKey:@"DefaultGridColor"];
    [prefWrapper setDouble:[[graph xGrid] width] forKey:@"DefaultGridWidth"];
    [prefWrapper setDouble:[[graph xAxis] titlePlacement] forKey:@"DefaultXAxisTitlePlacement"];
    [prefWrapper setDouble:[[graph yAxis] titlePlacement] forKey:@"DefaultYAxisTitlePlacement"];
    [prefWrapper setObject:nameFromScientificNotationSetting([[graph xAxis] scientificNotationSetting]) forKey:@"ScientificNotationSetting"];
    
    // Canvas settings
    [[OFPreferenceWrapper sharedPreferenceWrapper] setColorIfConvertible:[graph backgroundColor] forKey:@"DefaultBackgroundColor"];
    // Written even for an unsaved New From copy: the user asked for these settings.
    [prefWrapper setObject:NSStringFromSize([graph canvasSize]) forKey:@"LastCanvasSize"];
}



/////////////////////////////////////////////
#pragma mark -
#pragma mark Action methods
/////////////////////////////////////////////
- (IBAction)delete:(id)sender {
    [self performMenuItem:@selector(delete:)];
}
- (IBAction)deleteBackward:(id)sender {
    [self performMenuItem:@selector(deleteBackward:)];
}

- (IBAction)cut:(id)sender {
    [self performMenuItem:@selector(cut:)];
}
- (IBAction)copy:(id)sender {
    [self performMenuItem:@selector(copy:)];
}
- (IBAction)paste:(id)sender {
    [self performMenuItem:@selector(paste:)];
}


- (IBAction)copyAsImageWithPasteboard:(NSPasteboard *)pb;
{
    // relevant pboard types:
    // NSPDFPboardType, NSTIFFPboardType, NSPICTPboardType
    
    [_graphView commitEditing];
    [_graphView setDrawingToScreen:NO];
    
    NSRect r = [_graphView bounds];
    
    // Declare types
    NSArray *pbTypes = [NSArray arrayWithObjects:NSPDFPboardType, kUTTypePNG, NSTIFFPboardType, nil];
    if (LINKBACK_ENABLED) {
        pbTypes = [pbTypes arrayByAddingObject:LinkBackPboardType];
    }
    [pb declareTypes:pbTypes owner:_graphView];
    
    // Copy data to the pasteboard
    [pb setData: [_graphView dataWithPDFInsideRect: r]
	forType: NSPDFPboardType];
    
    [pb setData: [_graphView dataWithPNGInsideRect: r]
	forType: (NSString *)kUTTypePNG];  // NSPasteboardTypePNG is defined in Mac OS X 10.6 and up
    
    [pb setData: [_graphView dataWithTIFFInsideRect: r]
	forType: NSTIFFPboardType];
    
    // Add LinkBack data
    if (LINKBACK_ENABLED) {
        // Tell tools/editors to clean and update the model.
        if (!_isAutosaving && _graphView) {
            [_graphView commitEditing];
            [_editor prepareForSave];
        }
        
        NSRect frame = NSZeroRect;
        if ([[self windowControllers] count])
            frame = [[self window] frame];
        
        NSError *error = nil;
        NSData *documentXMLData = [_editor.graph generateXMLOfType:RSGraphFileType frame:frame error:&error];
        if (!documentXMLData)
            NSLog(@"Unable to generate XML for LinkBack: %@", [error toPropertyList]);


        // Even on error, we need to put something on the pasteboard for this type since we declared it.
        if (documentXMLData)
            [pb setPropertyList:[NSDictionary linkBackDataWithServerName:OGSLinkBackServerName appData:documentXMLData] forType:LinkBackPboardType];
        else
            [pb setData:nil forType:LinkBackPboardType];
    }
    
    // And we're done
    [_graphView setDrawingToScreen:YES];
}

// copies the whole graph image to the clipboard
- (IBAction)copyAsImage:(id)sender;
{
    [self copyAsImageWithPasteboard:[NSPasteboard generalPasteboard]];
}




- (BOOL)windowIsOpaque;
{
    CGFloat alpha = [_editor.graph windowAlpha];
    OBASSERT(alpha <= 1 && alpha >= 0);
    
    if (alpha == 1)
        return YES;
    
    return NO;
}

- (void)setWindowOpacity:(CGFloat)alpha;
{
    NSWindow *window = [self window];
    
    if (alpha >= 1) {
        [window setOpaque:YES];
        [window setBackgroundColor:[NSColor windowBackgroundColor]];
        [_editor.graph setWindowAlpha:1];
    }
    else {
        [window setOpaque:NO];
        [window setBackgroundColor:[NSColor colorWithDeviceWhite:0 alpha:0]];
        [_editor.graph setWindowAlpha:alpha];
        
        if (alpha < 0.9) {
            // Remember as default
            [[OFPreferenceWrapper sharedPreferenceWrapper] setFloat:(float)alpha forKey:@"DefaultTransparentWindowOpacity"];
        }
    }
    
    [_graphView.editor setNeedsDisplay];
}

- (IBAction)toggleWindowOpacity:(id)sender;
{
    if ([self windowIsOpaque]) {
        float defaultAlpha = [[OFPreferenceWrapper sharedPreferenceWrapper] floatForKey:@"DefaultTransparentWindowOpacity"];
        [self setWindowOpacity:defaultAlpha];
    }
    else {
        [self setWindowOpacity:1];
    }
}


#pragma mark -
#pragma mark Accessor methods

@synthesize editor = _editor;

- (RSGraph *)graph;
{
    return _editor.graph;
}
- (RSSelector *)selectorObject;
{
    return _s;
}
- (RSUndoer *)undoer;
{
    return _u;
}

@synthesize graphView = _graphView;

@synthesize isFromFile = _isFromFile;
@synthesize isInAppBundle = _isInAppBundle;
@synthesize isCatalogCopy = _isCatalogCopy;
- (BOOL)isUnsavedCatalogCopy { return _isCatalogCopy && ![self fileURL]; }


/////////////////////////////////////////////
#pragma mark -
#pragma mark Undo methods
/////////////////////////////////////////////

- (void)undoManagerWillUndoOrRedo:(NSNotification *)note;
{
    [_addedElements removeAllObjects];
}
- (void)undoManagerDidUndoOrRedo:(NSNotification *)note;
{
    if ([_addedElements count]) {
        RSGroup *G = [[RSGroup alloc] initWithGraph:_editor.graph byCopyingArray:_addedElements];
        [_s setSelection:G];
        [G release];
    }
    
    [_editor setNeedsDisplay];
}


///////////////////////////////////////////
#pragma mark Accessors for scripting
///////////////////////////////////////////
- (NSArray *)lines {
    return [_editor.graph userLineElements];
}

//! TO DO: 
// get name objectSpecifier method code from sketch document class
// more accessors here that route to _graph




@end
