// Offscreen native qualification checks: legacy style adoption, autosave/recovery, font and color panels with
// two documents, and the full-screen frame. Nib-loaded production document windows that are never
// shown; AppKit's key/main window is emulated and the shared panels are never ordered front.
// No application delegate launch, launch loop or visible window.
#import "GraphDocument.h"
#import "GraphWindowController.h"
#import "RSGraphView.h"
#import "RSSelector.h"
#import "RSDocumentController.h"
#import "RSInspectorSidebar.h"
#import "RSStylePresets.h"
#import <GraphSketcherModel/RSGraph.h>
#import <GraphSketcherModel/RSGraphArchive.h>
#import <GraphSketcherModel/RSGraphEditor.h>
#import <GraphSketcherModel/RSTextLabel.h>
#import <GraphSketcherModel/RSUndoer.h>
#import <OmniAppKit/OAColorWell.h>
#import <OmniFoundation/OFController.h>
#import <OmniInspector/OIInspectorTabController.h>
#import <OmniUnzip/OUUnzipArchive.h>
#import <OmniUnzip/OUUnzipEntry.h>
#import <OmniUnzip/OUZipArchive.h>
#import <objc/runtime.h>

@interface GraphDocument (NativeQualification)
- (NSWindow *)window;
@end
@interface GraphWindowController (NativeQualification)
- (RSInspectorSidebar *)inspectorSidebar;
- (void)saveGraphFrame;
- (void)windowDidResize:(NSNotification *)note;
- (void)windowDidMove:(NSNotification *)note;
- (void)windowDidBecomeMain:(NSNotification *)note;
@end

static void Check(BOOL condition, NSString *message) {
    if (!condition) [NSException raise:@"NativeQualificationFailure" format:@"%@", message];
}
static void Drain(void) {
    __block BOOL finished = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ finished = YES; });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (!finished && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:deadline];
    Check(finished, @"Main queue did not drain");
}
// Runs the run loop until the condition holds or the timeout passes; returns the condition.
static BOOL WaitUntil(BOOL (^condition)(void), NSTimeInterval timeout) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    return condition();
}
static void Swizzle(Class cls, SEL selector, id block) {
    Method method = class_getInstanceMethod(cls, selector);
    Check(method != NULL, [NSString stringWithFormat:@"%@ implements %@", cls, NSStringFromSelector(selector)]);
    method_setImplementation(method, imp_implementationWithBlock(block));
}
static IMP Original(Class cls, SEL selector) { return method_getImplementation(class_getInstanceMethod(cls, selector)); }
static NSString *Sha(NSURL *url) {
    NSData *data = [NSData dataWithContentsOfURL:url];
    Check(data != nil, [@"Readable " stringByAppendingString:url.path]);
    return [NSString stringWithFormat:@"%lu:%lu", (unsigned long)data.length, (unsigned long)data.hash];
}
static NSData *Bytes(NSURL *url) { NSData *data = [NSData dataWithContentsOfURL:url]; Check(data != nil, url.path); return data; }
static NSData *XML(GraphDocument *document) {
    NSError *error = nil;
    NSData *xml = [document.graph generateXMLOfType:RSGraphFileType frame:NSZeroRect error:&error];
    Check(xml != nil, error.description);
    return xml;
}
static NSDictionary *Archive(NSURL *url) {
    NSError *error = nil;
    NSDictionary *archive = [RSGraphArchive readURL:url error:&error];
    Check(archive != nil, [NSString stringWithFormat:@"%@ reads: %@", url.lastPathComponent, error]);
    return archive;
}
static RSGraphArchiveEncoding Encoding(NSURL *url) { return [Archive(url)[@"encoding"] integerValue]; }

// Emulated AppKit state. The windows are never ordered in and the process is never activated, so
// AppKit has no key or main window of its own; the fixture names them, and AppKit's own responder
// chain search (-[NSApplication sendAction:to:from:]) does the rest.
static NSWindow *KeyWindow;
static NSMutableSet *FullScreenWindows;
// Recorded modal UI. Alerts answer AlertAnswer; the Save panel "chooses" SavePanelChoice.
static NSMutableArray *Alerts;
static NSModalResponse AlertAnswer;
static NSMutableArray *SavePanels;
static NSURL *SavePanelChoice;
static NSUInteger CommitEditingCalls;
static NSUInteger ScheduledAutosaves;
static NSDocument *TimedAutosaveDocument;
static NSURL *Scratch;
static NSMutableArray *InspectorColorChanges;
static void InstallEmulation(void) {
    FullScreenWindows = [[NSMutableSet alloc] init];
    Alerts = [[NSMutableArray alloc] init];
    SavePanels = [[NSMutableArray alloc] init];
    InspectorColorChanges = [[NSMutableArray alloc] init];
    Swizzle(NSApplication.class, @selector(keyWindow), ^NSWindow *(NSApplication *app) { return KeyWindow; });
    Swizzle(NSApplication.class, @selector(mainWindow), ^NSWindow *(NSApplication *app) { return KeyWindow; });
    BOOL (^isKey)(NSWindow *) = ^BOOL(NSWindow *window) { return window == KeyWindow; };
    Swizzle(NSWindow.class, @selector(isKeyWindow), isKey);
    Swizzle(NSWindow.class, @selector(isMainWindow), isKey);
    NSWindowStyleMask (*styleMask)(id, SEL) = (void *)Original(NSWindow.class, @selector(styleMask));
    Swizzle(NSWindow.class, @selector(styleMask), ^NSWindowStyleMask(NSWindow *window) {
        NSWindowStyleMask mask = styleMask(window, @selector(styleMask));
        return [FullScreenWindows containsObject:[NSValue valueWithNonretainedObject:window]] ? mask | NSWindowStyleMaskFullScreen : mask;
    });
    // The fixture declares no document types (Checks/check-fixture-bundles.py), so NSDocument would
    // find nothing it may write in place; give it the app's two Editor types (the harness checks
    // they are exactly the ones Graphink.app declares).
    NSArray *types = [NSBundle.mainBundle objectForInfoDictionaryKey:@"NativeQualificationEditorTypes"];
    Check(types.count == 2 && [types containsObject:RSGraphFileType] && [types containsObject:RSGraphLegacyFileType], @"Editor types from Graphink.app");
    Class meta = object_getClass(GraphDocument.class);
    method_setImplementation(class_getClassMethod(GraphDocument.class, @selector(writableTypes)), imp_implementationWithBlock(^NSArray *(Class cls) { return types; }));
    method_setImplementation(class_getClassMethod(GraphDocument.class, @selector(readableTypes)), imp_implementationWithBlock(^NSArray *(Class cls) { return types; }));
    method_setImplementation(class_getClassMethod(GraphDocument.class, @selector(isNativeType:)), imp_implementationWithBlock(^BOOL(Class cls, NSString *type) { return [types containsObject:type]; }));
    (void)meta;
    // The shared panels are created and used, never shown.
    for (Class panel in @[NSColorPanel.class, NSFontPanel.class]) {
        Swizzle(panel, @selector(orderFront:), ^(id self, id sender) {});
        Swizzle(panel, @selector(makeKeyAndOrderFront:), ^(id self, id sender) {});
    }
    Swizzle(NSApplication.class, @selector(orderFrontColorPanel:), ^(id self, id sender) {});
    Swizzle(NSDocument.class, @selector(presentError:modalForWindow:delegate:didPresentSelector:contextInfo:), ^(NSDocument *document, NSError *error, NSWindow *window, id delegate, SEL selector, void *context) {
        NSLog(@"FAIL presented error for %@: %@", document.displayName, error);
        [Alerts addObject:@{@"error": error}];
        if (delegate) ((void (*)(id, SEL, BOOL, void *))objc_msgSend)(delegate, selector, NO, context);
    });
    Swizzle(NSAlert.class, @selector(runModal), ^NSModalResponse(NSAlert *alert) {
        [Alerts addObject:@{@"message": alert.messageText ?: @"", @"informative": alert.informativeText ?: @"", @"buttons": [alert.buttons valueForKey:@"title"]}];
        return AlertAnswer;
    });
    // File > Save As runs the Save panel; the "user" picks SavePanelChoice, or cancels when it is nil.
    Swizzle(NSDocument.class, @selector(runModalSavePanelForSaveOperation:delegate:didSaveSelector:contextInfo:), ^(NSDocument *document, NSSaveOperationType operation, id delegate, SEL didSave, void *context) {
        NSSavePanel *panel = [NSSavePanel savePanel];
        BOOL prepared = [document prepareSavePanel:panel];
        [SavePanels addObject:@{@"operation": @(operation), @"prepared": @(prepared), @"name": panel.nameFieldStringValue ?: @"", @"types": panel.allowedFileTypes ?: @[], @"extensionHidden": @(panel.extensionHidden)}];
        if (!SavePanelChoice) {
            if (delegate) ((void (*)(id, SEL, NSDocument *, BOOL, void *))objc_msgSend)(delegate, didSave, document, NO, context);
            return;
        }
        [document saveToURL:SavePanelChoice ofType:[RSDocumentController graphTypeForURL:SavePanelChoice] forSaveOperation:operation delegate:delegate didSaveSelector:didSave contextInfo:context];
    });
    BOOL (*commit)(id, SEL) = (void *)Original(RSGraphView.class, @selector(commitEditing));
    Swizzle(RSGraphView.class, @selector(commitEditing), ^BOOL(RSGraphView *view) { CommitEditingCalls++; return commit(view, @selector(commitEditing)); });
    // AppKit's own autosave timer would write untitled documents to ~/Library/Autosave Information;
    // the fixture runs every autosave itself, into its evidence directory. Only TimedAutosaveDocument,
    // whose autosave URL is in the evidence directory, keeps AppKit's real timer.
    void (*scheduleAutosaving)(id, SEL) = (void *)Original(NSDocument.class, @selector(scheduleAutosaving));
    Swizzle(NSDocument.class, @selector(scheduleAutosaving), ^(NSDocument *document) {
        ScheduledAutosaves++;
        if (document == TimedAutosaveDocument && [document.autosavedContentsFileURL.path hasPrefix:Scratch.path])
            scheduleAutosaving(document, @selector(scheduleAutosaving));
    });
    // The fixture declares no document types; reopening by URL makes Graphink documents.
    Class (*documentClass)(id, SEL, NSString *) = (void *)Original(NSDocumentController.class, @selector(documentClassForType:));
    Swizzle(NSDocumentController.class, @selector(documentClassForType:), ^Class(NSDocumentController *controller, NSString *type) {
        return [RSDocumentController isGraphType:type] ? GraphDocument.class : documentClass(controller, @selector(documentClassForType:), type);
    });
    Class style = NSClassFromString(@"StyleInspector");
    void (*changeColor)(id, SEL, id) = (void *)Original(style, @selector(changeColor:));
    Swizzle(style, @selector(changeColor:), ^(id inspector, id sender) {
        [InspectorColorChanges addObject:[inspector valueForKey:@"editor"] ?: NSNull.null];
        changeColor(inspector, @selector(changeColor:), sender);
    });
}

static const NSRect Screen = {{0, 0}, {1440, 875}};
static void ClearFrameKeys(void) {
    for (NSString *key in @[@"LastFrameString", @"LastCanvasSize"]) [[OFPreferenceWrapper sharedPreferenceWrapper] removeObjectForKey:key];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"NSWindow Frame RSGraphDocumentWindow"];
}
static GraphWindowController *OpenWindow(GraphDocument *document) {
    [(NSDocumentController *)NSDocumentController.sharedDocumentController addDocument:document];
    [document makeWindowControllers];
    GraphWindowController *owner = document.windowControllers.firstObject;
    Check(owner.window != nil && !owner.window.visible, @"Nib window loaded and not shown");
    [owner chooseInitialWindowFrameInVisibleFrame:Screen];
    [owner refreshInspectors];
    Drain();
    return owner;
}
static void Clean(GraphDocument *document) {
    Drain(); [document.undoManager removeAllActions]; [document updateChangeCount:NSChangeCleared]; Drain();
}
static GraphDocument *Open(NSURL *url) {
    NSError *error = nil;
    GraphDocument *document = [[[GraphDocument alloc] initWithContentsOfURL:url ofType:[RSDocumentController graphTypeForURL:url] error:&error] autorelease];
    Check(document != nil, [NSString stringWithFormat:@"%@ opens: %@", url.lastPathComponent, error]);
    OpenWindow(document);
    Clean(document);
    return document;
}
static void Close(GraphDocument *document) {
    if (KeyWindow == document.window) KeyWindow = nil;
    [document close];
    Drain();
}
static RSGraphView *GraphView(GraphDocument *document) { return document.graphView; }
static void Select(GraphDocument *document, RSGraphElement *element) {
    [document.selectorObject setSelection:element];
    [document.selectorObject sendChange:nil];
    Drain();
}
// An ordinary undoable edit, so Cancel has an undo stack and a dirty state to preserve.
static void Edit(GraphDocument *document, RSTextLabel *label, NSColor *color) {
    [document.undoManager beginUndoGrouping];
    [label setColor:color];
    [document.undoManager endUndoGrouping];
    Drain();
}
static id StylePresetItem(NSInteger tag) {
    NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:RSStylePresetNames()[tag] action:@selector(applyStylePreset:) keyEquivalent:@""] autorelease];
    item.tag = tag;
    return item;
}
static NSURL *ScratchURL(NSString *name) { return [Scratch URLByAppendingPathComponent:name]; }

#pragma mark - Legacy adoption

typedef struct { NSData *xml; RSGraphEditor *editor; RSGraph *graph; RSGraphElement *selection; BOOL canUndo; NSString *undoName; BOOL edited; NSURL *fileURL; RSGraphArchiveEncoding encoding; NSResponder *firstResponder; RSGraphEditor *viewEditor; } DocumentState;
static DocumentState State(GraphDocument *document) {
    return (DocumentState){XML(document), document.editor, document.graph, document.selectorObject.selection, document.undoManager.canUndo, document.undoManager.undoActionName, document.isDocumentEdited, document.fileURL, document.archiveEncoding, document.window.firstResponder, GraphView(document).editor};
}
static void CheckUnchanged(GraphDocument *document, DocumentState before, NSString *what) {
    DocumentState now = State(document);
    Check([now.xml isEqual:before.xml], [what stringByAppendingString:@": model unchanged"]);
    Check(now.editor == before.editor && now.graph == before.graph && now.viewEditor == before.viewEditor, [what stringByAppendingString:@": editor and graph view unchanged"]);
    Check(now.selection == before.selection, [what stringByAppendingString:@": selection unchanged"]);
    Check(now.canUndo == before.canUndo && [now.undoName isEqual:before.undoName], [NSString stringWithFormat:@"%@: undo unchanged (%@ -> %@)", what, before.undoName, now.undoName]);
    Check(now.edited == before.edited, [what stringByAppendingString:@": dirty state unchanged"]);
    Check([now.fileURL isEqual:before.fileURL] && now.encoding == before.encoding, [what stringByAppendingString:@": file and format unchanged"]);
    Check(now.firstResponder == before.firstResponder, [what stringByAppendingString:@": first responder unchanged"]);
}

static NSArray *Texts(NSArray *labels) {
    NSMutableArray *texts = [NSMutableArray array];
    for (RSTextLabel *label in labels) [texts addObject:label.text ?: @""];
    return texts;
}
static void CheckLegacyAdoption(NSURL *legacy, RSGraphArchiveEncoding expected, NSUInteger index) {
    NSString *what = legacy.lastPathComponent;
    NSData *original = Bytes(legacy);
    GraphDocument *document = Open(legacy);
    Check(document.archiveEncoding == expected && document.requiresCreationDefaultsSaveAs && document.graph.creationDefaults == nil, [what stringByAppendingString:@": legacy origin requires Save As before adoption"]);
    NSArray *labels = document.graph.userLabels;
    Check(labels.count >= 2, [what stringByAppendingString:@": sample has labels"]);
    KeyWindow = document.window;
    Check([document.window makeFirstResponder:GraphView(document)], [what stringByAppendingString:@": canvas takes focus"]);
    Select(document, labels[0]);
    Edit(document, labels[1], NSColor.purpleColor);
    Check(document.isDocumentEdited && document.undoManager.canUndo, [what stringByAppendingString:@": an ordinary edit dirties the document"]);
    DocumentState before = State(document);
    NSArray *texts = Texts(labels);

    // Cancel.
    [Alerts removeAllObjects]; [SavePanels removeAllObjects];
    AlertAnswer = NSAlertSecondButtonReturn;
    Check([NSApp sendAction:@selector(applyStylePreset:) to:nil from:StylePresetItem(1)], [what stringByAppendingString:@": Apply Style Preset reaches the document"]);
    Drain();
    Check(Alerts.count == 1 && [Alerts[0][@"message"] isEqual:@"Save a Graphink copy before applying a style"] && [Alerts[0][@"buttons"] isEqual:(@[@"Save As…", @"Cancel"])], [NSString stringWithFormat:@"%@: one Save As alert before any change: %@", what, Alerts]);
    Check(SavePanels.count == 0, [what stringByAppendingString:@": Cancel runs no Save panel"]);
    CheckUnchanged(document, before, [what stringByAppendingString:@" Cancel"]);
    Check([Bytes(legacy) isEqual:original], [what stringByAppendingString:@": Cancel leaves the original bytes"]);

    // Save As…, then Cancel in the Save panel: still nothing changes.
    [Alerts removeAllObjects];
    AlertAnswer = NSAlertFirstButtonReturn; SavePanelChoice = nil;
    [NSApp sendAction:@selector(applyStylePreset:) to:nil from:StylePresetItem(1)];
    Drain();
    Check(Alerts.count == 1 && SavePanels.count == 1 && [SavePanels[0][@"operation"] integerValue] == NSSaveAsOperation && [SavePanels[0][@"prepared"] boolValue], [NSString stringWithFormat:@"%@: Save As… runs the Save As panel: %@", what, SavePanels]);
    Check([SavePanels[0][@"name"] hasSuffix:@".graphink"] && ![SavePanels[0][@"name"] containsString:@".ograph"] && [SavePanels[0][@"types"] isEqual:(@[@"graphink", @"ograph"])], [NSString stringWithFormat:@"%@: the panel proposes a .graphink name: %@", what, SavePanels[0]]);
    // Retest v5 L3: the panel hid extensions, so only "Legacy" showed; a .ograph shows the new one.
    if ([legacy.pathExtension isEqualToString:@"ograph"])
        Check(![SavePanels[0][@"extensionHidden"] boolValue], [NSString stringWithFormat:@"%@: the panel shows the .graphink extension: %@", what, SavePanels[0]]);
    CheckUnchanged(document, before, [what stringByAppendingString:@" Save As then Cancel"]);
    Check([Bytes(legacy) isEqual:original], [what stringByAppendingString:@": cancelled Save As leaves the original bytes"]);

    // Save As… to a .graphink: OPC, same editor/selection/undo, original untouched, style not yet applied.
    [Alerts removeAllObjects]; [SavePanels removeAllObjects];
    NSURL *adopted = ScratchURL([NSString stringWithFormat:@"opc-adopted-%lu.graphink", (unsigned long)index]);
    SavePanelChoice = adopted;
    [NSApp sendAction:@selector(applyStylePreset:) to:nil from:StylePresetItem(1)];
    WaitUntil(^BOOL { return [document.fileURL isEqual:adopted] && !document.isDocumentEdited; }, 20);
    SavePanelChoice = nil;
    Check(SavePanels.count == 1 && [document.fileURL isEqual:adopted], [NSString stringWithFormat:@"%@: Save As adopted %@ (now %@)", what, adopted.lastPathComponent, document.fileURL]);
    Check(document.archiveEncoding == RSGraphArchiveOPC && !document.requiresCreationDefaultsSaveAs && [document.graph.creationDefaults isEqual:@{}], [what stringByAppendingString:@": the copy is an OPC document with its own (empty) defaults"]);
    Check(Encoding(adopted) == RSGraphArchiveOPC, [what stringByAppendingString:@": the written copy is OPC"]);
    Check(document.editor == before.editor && document.graph == before.graph && GraphView(document).editor == before.editor && document.selectorObject.selection == before.selection, [what stringByAppendingString:@": Save As keeps the editor and selection"]);
    // Saving runs the historical save-time layout cleanup (label positions, whitespace), as every
    // explicit Save does; the content itself (the same objects, texts and the edit) is kept.
    Check([document.graph.userLabels isEqual:labels] && [Texts(labels) isEqual:texts] && [((RSTextLabel *)labels[1]).color isEqual:NSColor.purpleColor], [what stringByAppendingString:@": Save As keeps the content and the edit"]);
    Check(!document.isDocumentEdited, [what stringByAppendingString:@": Save As leaves the document clean"]);
    Check([Bytes(legacy) isEqual:original], [what stringByAppendingString:@": Save As never touches the original"]);
    Check(document.graph.creationDefaults.count == 0, [what stringByAppendingString:@": the style is applied only when asked again"]);

    // Applying again adopts the preset, with one undo back to the saved copy.
    [Alerts removeAllObjects];
    [NSApp sendAction:@selector(applyStylePreset:) to:nil from:StylePresetItem(1)];
    Drain();
    Check(Alerts.count == 0 && [document.graph.creationDefaults[@"font-name"] isEqual:@"Kalam-Regular"] && document.isDocumentEdited, [what stringByAppendingString:@": the adopted copy applies the preset without asking"]);
    [document.undoManager undo]; Drain();
    Check(document.graph.creationDefaults.count == 0 && !document.isDocumentEdited, [what stringByAppendingString:@": one undo returns to the saved copy"]);
    Close(document);
    Check([Bytes(legacy) isEqual:original], [what stringByAppendingString:@": the original is unchanged after close"]);
    NSLog(@"PASS legacy adoption %@: Save As proposes .graphink (shown for .ograph); Cancel, Save panel Cancel and Save As keep model/editor/selection/undo/dirty/original; adopted copy applies", what);
}

static void CheckLegacySave(NSURL *legacy, RSGraphArchiveEncoding expected) {
    NSString *what = legacy.lastPathComponent;
    GraphDocument *document = Open(legacy);
    KeyWindow = document.window;
    RSGraphEditor *editor = document.editor;
    Edit(document, document.graph.userLabels[0], NSColor.orangeColor);
    [SavePanels removeAllObjects];
    Check([NSApp targetForAction:@selector(saveDocument:)] == document, [NSString stringWithFormat:@"%@: File > Save reaches the document (%@)", what, [NSApp targetForAction:@selector(saveDocument:)]]);
    [NSApp sendAction:@selector(saveDocument:) to:nil from:nil];
    Drain(); Drain();
    WaitUntil(^BOOL { return !document.isDocumentEdited; }, 20);
    Check(SavePanels.count == 0 && !document.isDocumentEdited, [NSString stringWithFormat:@"%@: File > Save saves in place without a panel (panels %@, edited %d)", what, SavePanels, document.isDocumentEdited]);
    Check([document.fileURL isEqual:legacy] && Encoding(legacy) == expected && document.archiveEncoding == expected && document.requiresCreationDefaultsSaveAs, [what stringByAppendingString:@": ordinary Save keeps the file, its extension and its legacy format"]);
    Check(document.editor == editor && document.graph.creationDefaults == nil, [what stringByAppendingString:@": ordinary Save adopts nothing"]);
    Close(document);
    GraphDocument *reopened = Open(legacy);
    Check([((RSTextLabel *)reopened.graph.userLabels[0]).color isEqual:NSColor.orangeColor], [what stringByAppendingString:@": the saved edit reopens"]);
    Close(reopened);
    NSLog(@"PASS legacy save routing %@: Save keeps path, extension and format", what);
}

#pragma mark - Autosave and recovery

static void Autosave(GraphDocument *document) {
    __block BOOL done = NO; __block NSError *failure = nil;
    [document autosaveWithImplicitCancellability:NO completionHandler:^(NSError *error) { failure = [error retain]; done = YES; }];
    WaitUntil(^BOOL { return done; }, 20);
    Check(done && failure == nil, [NSString stringWithFormat:@"%@ autosaves: %@", document.displayName, [failure autorelease]]);
}
static void CheckAutosave(NSURL *sample) {
    NSError *error = nil;
    // A saved Graphink document: explicit Save writes the preview; autosave in place does not.
    GraphDocument *document = Open(sample);
    NSURL *saved = ScratchURL(@"opc-autosave-in-place.graphink");
    CommitEditingCalls = 0;
    Check([document saveToURL:saved ofType:RSGraphFileType forSaveOperation:NSSaveAsOperation error:&error], error.description);
    Check(Archive(saved)[@"preview"] != nil && CommitEditingCalls > 0, [NSString stringWithFormat:@"Explicit Save commits editing and writes the preview (%lu commits)", (unsigned long)CommitEditingCalls]);
    KeyWindow = document.window;
    RSTextLabel *label = document.graph.userLabels[0];
    Select(document, label);
    Edit(document, label, NSColor.brownColor);
    Check(document.hasUnautosavedChanges, @"The edit is not autosaved yet");
    // Editing a label in place: autosave must not end it.
    [GraphView(document) startEditingLabel];
    Drain();
    NSResponder *editing = document.window.firstResponder;
    CommitEditingCalls = 0;
    Autosave(document);
    Check(CommitEditingCalls == 0, [NSString stringWithFormat:@"Autosave in place does not commit editing (%lu commits)", (unsigned long)CommitEditingCalls]);
    Check(document.window.firstResponder == editing, [NSString stringWithFormat:@"Autosave leaves the label being edited (%@ -> %@)", editing.className, document.window.firstResponder.className]);
    NSDictionary *archive = Archive(saved);
    Check([archive[@"encoding"] integerValue] == RSGraphArchiveOPC && archive[@"preview"] == nil, @"Autosave in place writes OPC without a preview");
    Check(!document.hasUnautosavedChanges && [document.fileURL isEqual:saved], @"Autosave in place keeps the file");
    [GraphView(document) commitEditing];
    NSArray *texts = Texts(document.graph.userLabels);
    Close(document);
    GraphDocument *reopened = Open(saved);
    Check([((RSTextLabel *)reopened.graph.userLabels[0]).color isEqual:NSColor.brownColor] && [Texts(reopened.graph.userLabels) isEqual:texts], @"The autosaved file reopens with the edit");
    Close(reopened);

    // A legacy .ograph autosaves in place as itself.
    NSURL *legacy = ScratchURL(@"legacy-autosave.ograph");
    Check([NSFileManager.defaultManager copyItemAtURL:sample toURL:legacy error:&error], error.description);
    GraphDocument *old = Open(legacy);
    KeyWindow = old.window;
    Edit(old, old.graph.userLabels[0], NSColor.cyanColor);
    CommitEditingCalls = 0;
    Autosave(old);
    Check(CommitEditingCalls == 0 && [old.fileURL isEqual:legacy] && Encoding(legacy) == RSGraphArchiveLegacyZIP && old.requiresCreationDefaultsSaveAs, @"Legacy autosave in place keeps the .ograph and its format");
    Check(![NSFileManager.defaultManager fileExistsAtPath:[legacy.URLByDeletingPathExtension URLByAppendingPathExtension:@"graphink"].path], @"Legacy autosave writes no .graphink sibling");
    Close(old);
    NSLog(@"PASS autosave: in place without preview or ending edits, explicit Save with preview, legacy kept as .ograph");

    // Recovery. An untitled document's autosave goes elsewhere (AppKit's Autosave Information folder in
    // the app; here the evidence directory). Reopening those contents is what relaunch recovery does.
    GraphDocument *untitled = [[[GraphDocument alloc] initWithType:RSGraphFileType error:&error] autorelease];
    Check(untitled != nil, error.description);
    OpenWindow(untitled); Clean(untitled);
    KeyWindow = untitled.window;
    [untitled.undoManager beginUndoGrouping]; RSSetLocalCreationValue(untitled.graph, @"font-name", @"Georgia"); [untitled.undoManager endUndoGrouping]; Drain();
    Check([untitled.editor applyStylePreset:2], @"Chalkboard applies to the untitled document");
    Drain();
    NSURL *elsewhere = ScratchURL(@"opc-autosave-elsewhere.graphink");
    CommitEditingCalls = 0;
    // AppKit's own autosave entry point, pointed at the evidence directory instead of the user's folder.
    untitled.autosavedContentsFileURL = elsewhere;
    Autosave(untitled);
    Check(WaitUntil(^BOOL { return [NSFileManager.defaultManager fileExistsAtPath:elsewhere.path]; }, 10), @"The untitled autosave is written");
    Check([untitled.autosavedContentsFileURL isEqual:elsewhere], [NSString stringWithFormat:@"Untitled autosave goes to the chosen place (%@)", untitled.autosavedContentsFileURL]);
    Check(CommitEditingCalls == 0 && Archive(elsewhere)[@"preview"] == nil && untitled.fileURL == nil, @"Autosave elsewhere writes no preview, commits nothing and leaves the document untitled");
    NSSize canvas = untitled.graph.canvasSize; NSColor *background = untitled.graph.backgroundColor;
    NSUInteger labelCount = untitled.graph.Labels.count, vertexCount = untitled.graph.Vertices.count;
    NSDictionary *untitledDefaults = [[untitled.graph.creationDefaults copy] autorelease];
    // A crash leaves the autosaved contents behind; an ordinary close discards them.
    NSURL *crashed = ScratchURL(@"opc-autosave-after-crash.graphink");
    NSURL *crashedSaved = ScratchURL(@"opc-autosave-after-crash-saved.graphink");
    Check([NSFileManager.defaultManager copyItemAtURL:elsewhere toURL:crashed error:&error] && [NSFileManager.defaultManager copyItemAtURL:elsewhere toURL:crashedSaved error:&error], error.description);
    Close(untitled);
    Check(WaitUntil(^BOOL { return ![NSFileManager.defaultManager fileExistsAtPath:elsewhere.path]; }, 10), @"Closing the document discards its autosaved contents");
    elsewhere = crashed;
    GraphDocument *recovered = [[[GraphDocument alloc] initForURL:nil withContentsOfURL:elsewhere ofType:RSGraphFileType error:&error] autorelease];
    Check(recovered != nil, error.description);
    OpenWindow(recovered);
    Check(recovered.fileURL == nil && recovered.isDocumentEdited, @"Recovered untitled document stays untitled and edited");
    // Reading normalizes axis tick labels (order, hidden ends) as on any open; compare what the user set.
    Check(NSEqualSizes(recovered.graph.canvasSize, canvas) && RSCreationDefaultsEqual(@{@"color": recovered.graph.backgroundColor}, @{@"color": background}) && recovered.graph.Labels.count == labelCount && recovered.graph.Vertices.count == vertexCount, [NSString stringWithFormat:@"Recovered model equals the autosaved document (canvas %@/%@, background %@/%@, labels %lu/%lu, vertices %lu/%lu)", NSStringFromSize(recovered.graph.canvasSize), NSStringFromSize(canvas), recovered.graph.backgroundColor, background, (unsigned long)recovered.graph.Labels.count, (unsigned long)labelCount, (unsigned long)recovered.graph.Vertices.count, (unsigned long)vertexCount]);
    Check(RSCreationDefaultsEqual(recovered.graph.creationDefaults, untitledDefaults) && recovered.archiveEncoding == RSGraphArchiveOPC, [NSString stringWithFormat:@"Recovered defaults equal the autosaved ones (%@ vs %@)", recovered.graph.creationDefaults, untitledDefaults]);
    Close(recovered);
    // A saved document whose newest contents sit elsewhere (Versions, or a crash between saves).
    GraphDocument *versioned = [[[GraphDocument alloc] initForURL:saved withContentsOfURL:crashedSaved ofType:RSGraphFileType error:&error] autorelease];
    Check(versioned != nil, error.description);
    Drain();
    Check([versioned.fileURL isEqual:saved] && versioned.isDocumentEdited, [NSString stringWithFormat:@"Contents from elsewhere reopen as an edited version of the saved file (%@, edited %d)", versioned.fileURL, versioned.isDocumentEdited]);
    OpenWindow(versioned);
    Close(versioned);
    NSLog(@"PASS recovery: untitled and saved documents reopen from autosaved contents, edited, defaults kept");
}

// Retest v5 U3: a new untitled document with a label, unsaved, killed 30 s later, came back edited
// but empty. AppKit's real timer must have autosaved it by then (the app's 120 s delay postponed
// the first autosave), and reopening those contents as state restoration does
// (-reopenDocumentForURL:withContentsOfURL:display:completionHandler:) must bring the label back.
static void CheckCrashRecovery(void) {
    NSError *error = nil;
    GraphDocument *untitled = [[[GraphDocument alloc] initWithType:RSGraphFileType error:&error] autorelease];
    Check(untitled != nil, error.description);
    OpenWindow(untitled); Clean(untitled);
    KeyWindow = untitled.window;
    // Retest v5 Z5: nothing of Graphink's turns window restoration off; AppKit restores document
    // windows through the document controller (the system "Close windows when quitting" setting
    // still discards the state on a normal quit).
    Check(untitled.window.isRestorable && [untitled.window.restorationClass isSubclassOfClass:NSDocumentController.class], [NSString stringWithFormat:@"Document windows are restorable through the document controller (restorable %d, class %@)", untitled.window.isRestorable, untitled.window.restorationClass]);
    NSURL *autosaved = ScratchURL(@"opc-crash-untitled-autosave.graphink");
    untitled.autosavedContentsFileURL = autosaved;
    TimedAutosaveDocument = untitled;
    NSDate *edited = [NSDate date];
    [untitled.undoManager beginUndoGrouping];
    RSTextLabel *label = [[[RSTextLabel alloc] initWithGraph:untitled.graph] autorelease];
    [label setText:@"Crash"];
    [label setPosition:RSDataPointMake(([untitled.graph xMin] + [untitled.graph xMax]) / 2, ([untitled.graph yMin] + [untitled.graph yMax]) / 2)];
    [untitled.graph addLabel:label];
    [untitled.undoManager endUndoGrouping];
    Drain();
    Check(untitled.isDocumentEdited && untitled.hasUnautosavedChanges, @"The new label leaves the untitled document edited and not autosaved");
    // The retest waited 30 s before kill -9.
    BOOL written = WaitUntil(^BOOL { return !untitled.hasUnautosavedChanges && [NSFileManager.defaultManager fileExistsAtPath:autosaved.path]; }, 30);
    NSTimeInterval seconds = -edited.timeIntervalSinceNow;
    TimedAutosaveDocument = nil;
    Check(written, [NSString stringWithFormat:@"AppKit autosaves the untitled document within 30 s of the edit (autosaving delay %g s; nothing written after %.1f s)", NSDocumentController.sharedDocumentController.autosavingDelay, seconds]);
    Check(untitled.fileURL == nil && [untitled.autosavedContentsFileURL isEqual:autosaved], @"The autosave went to the evidence directory and the document stays untitled");
    // kill -9 leaves the autosaved contents behind; an ordinary close would discard them.
    NSURL *crashed = ScratchURL(@"opc-crash-left-behind.graphink");
    Check([NSFileManager.defaultManager copyItemAtURL:autosaved toURL:crashed error:&error], error.description);
    Close(untitled);
    __block GraphDocument *recovered = nil; __block NSError *failure = nil; __block BOOL done = NO;
    [NSDocumentController.sharedDocumentController reopenDocumentForURL:nil withContentsOfURL:crashed display:NO completionHandler:^(NSDocument *document, BOOL alreadyOpen, NSError *reopenError) {
        recovered = (GraphDocument *)[document retain]; failure = [reopenError retain]; done = YES;
    }];
    WaitUntil(^BOOL { return done; }, 20);
    [recovered autorelease]; [failure autorelease];
    Check(done && [recovered isKindOfClass:GraphDocument.class], [NSString stringWithFormat:@"The autosaved contents reopen as restoration does: %@", failure]);
    [recovered makeWindowControllers];
    GraphWindowController *owner = recovered.windowControllers.firstObject;
    Check(owner.window != nil && !owner.window.visible, @"The recovered document's nib window loaded and not shown");
    [owner chooseInitialWindowFrameInVisibleFrame:Screen];
    Drain();
    NSArray *texts = Texts(recovered.graph.userLabels);
    Check(recovered.fileURL == nil && recovered.isDocumentEdited, [NSString stringWithFormat:@"The recovered document is untitled and edited (%@, edited %d)", recovered.fileURL, recovered.isDocumentEdited]);
    Check([texts containsObject:@"Crash"] && GraphView(recovered).editor == recovered.editor, [NSString stringWithFormat:@"The recovered canvas shows the label 'Crash' (labels %@)", texts]);
    // U4: closing it without saving discards the recovered contents, so it does not come back.
    Check([recovered.autosavedContentsFileURL isEqual:crashed], [NSString stringWithFormat:@"The recovered document keeps the autosaved contents as its autosave (%@)", recovered.autosavedContentsFileURL]);
    Close(recovered);
    Check(WaitUntil(^BOOL { return ![NSFileManager.defaultManager fileExistsAtPath:crashed.path]; }, 10), @"Closing the recovered document without saving discards its autosaved contents");
    NSLog(@"PASS crash recovery: AppKit autosaved the untitled label after %.1f s; reopened as restoration does, untitled, edited, with 'Crash'; closing discards it; windows restorable", seconds);
}

static NSURL *FuturePackage(NSURL *from) {
    NSError *error = nil;
    NSURL *bad = ScratchURL(@"unsupported-future.graphink");
    OUUnzipArchive *source = [[[OUUnzipArchive alloc] initWithPath:from.path error:&error] autorelease];
    Check(source != nil, error.description);
    OUZipArchive *zip = [[[OUZipArchive alloc] initWithPath:bad.path error:&error] autorelease];
    Check(zip != nil, error.description);
    for (OUUnzipEntry *entry in source.entries) {
        NSData *part = [source dataForEntry:entry error:&error];
        Check(part != nil, error.description);
        if ([entry.name isEqual:@"graphink/document.xml"]) {
            NSString *control = [[[NSString alloc] initWithData:part encoding:NSUTF8StringEncoding] autorelease];
            Check([control containsString:@"version=\"1\""], @"Control part has a version");
            part = [[control stringByReplacingOccurrencesOfString:@"version=\"1\"" withString:@"version=\"99\""] dataUsingEncoding:NSUTF8StringEncoding];
        }
        Check([zip appendEntryNamed:entry.name fileType:NSFileTypeRegular contents:part date:nil error:&error], error.description);
    }
    Check([zip close:&error], error.description);
    NSData *normalized = [RSGraphArchive normalizeProducedZIP:[NSData dataWithContentsOfURL:bad] error:&error];
    Check(normalized && [normalized writeToURL:bad atomically:NO], error.description);
    return bad;
}
static void CheckUnsupportedPackage(void) {
    NSURL *saved = ScratchURL(@"opc-autosave-in-place.graphink");
    NSURL *bad = FuturePackage(saved);
    NSError *error = nil;
    GraphDocument *refused = [[[GraphDocument alloc] initWithContentsOfURL:bad ofType:RSGraphFileType error:&error] autorelease];
    Check(refused == nil && error != nil, @"An unsupported package does not open");
    GraphDocument *document = Open(saved);
    KeyWindow = document.window;
    [document.window makeFirstResponder:GraphView(document)];
    Select(document, document.graph.userLabels[1]);
    Edit(document, document.graph.userLabels[0], NSColor.magentaColor);
    DocumentState before = State(document);
    NSData *savedBytes = Bytes(saved);
    error = nil;
    Check(![document revertToContentsOfURL:bad ofType:RSGraphFileType error:&error] && error != nil, @"Revert to an unsupported package is refused");
    Drain();
    CheckUnchanged(document, before, @"Refused revert");
    error = nil;
    Check(![document readFromURL:bad ofType:RSGraphFileType error:&error] && error != nil, @"Reading an unsupported package is refused");
    CheckUnchanged(document, before, @"Refused read");
    Check([Bytes(saved) isEqual:savedBytes], @"The open document's file is untouched");
    Close(document);
    NSLog(@"PASS unsupported package: refused on open, revert and read without replacing the active editor");
}

#pragma mark - Font and color panels, two documents

static GraphDocument *OPCCopy(NSURL *sample, NSString *name) {
    NSError *error = nil;
    NSURL *url = ScratchURL(name);
    GraphDocument *source = [[[GraphDocument alloc] initWithContentsOfURL:sample ofType:RSGraphFileType error:&error] autorelease];
    Check(source && [source saveToURL:url ofType:RSGraphFileType forSaveOperation:NSSaveAsOperation error:&error], error.description);
    [source close];
    return Open(url);
}
static NSString *FontName(RSTextLabel *label) { return label.fontDescriptor.font.fontName; }
static void CheckFontPanel(GraphDocument *a, GraphDocument *b) {
    NSFontManager *manager = NSFontManager.sharedFontManager;
    NSFontPanel *panel = [manager fontPanel:YES];
    RSTextLabel *labelA = a.graph.userLabels[0], *labelB = b.graph.userLabels[1];
    NSString *fontA = FontName(labelA), *otherA = FontName(a.graph.userLabels[1]), *otherB = FontName(b.graph.userLabels[0]);
    NSDictionary *defaultsA = [[a.graph.creationDefaults copy] autorelease];
    Select(a, labelA); Select(b, labelB);
    // An edit registered through RSUndoer (font, inspector and canvas edits) is one change: one
    // undo leaves the document clean, as AppKit's own change counting expects.
    [b.undoer registerUndoWithObject:labelB action:@"setColor" state:labelB.color]; [labelB setColor:NSColor.yellowColor]; Drain();
    Check(b.isDocumentEdited, @"An RSUndoer edit dirties the document");
    [b.undoManager undo]; Drain();
    Check(!b.undoManager.canUndo && !b.isDocumentEdited, @"Undoing the only RSUndoer edit leaves the document clean");
    [b.undoManager redo]; Drain();
    Check(b.isDocumentEdited, @"Redo dirties it again");
    [b.undoManager undo]; Drain(); [b.undoManager removeAllActions];
    Check(!b.isDocumentEdited, @"Undo after redo is clean again");
    // B is key: the panel's choice goes to B's selection only.
    KeyWindow = b.window;
    Check([b.window makeFirstResponder:GraphView(b)] && [NSApp targetForAction:@selector(changeFont:)] == GraphView(b), @"changeFont: reaches the key window's canvas");
    NSFont *georgia = [NSFont fontWithName:@"Georgia" size:17];
    [panel setPanelFont:georgia isMultiple:NO];
    [manager modifyFontViaPanel:panel];
    Drain();
    Check([FontName(labelB) hasPrefix:@"Georgia"] && [FontName(b.graph.userLabels[0]) isEqual:otherB], [NSString stringWithFormat:@"The font panel changes B's selected label only (%@)", FontName(labelB)]);
    Check([FontName(labelA) isEqual:fontA] && [FontName(a.graph.userLabels[1]) isEqual:otherA] && RSCreationDefaultsEqual(a.graph.creationDefaults, defaultsA) && !a.isDocumentEdited && !a.undoManager.canUndo, @"Document A is untouched by B's font change");
    Check([b.graph.creationDefaults[@"font-name"] hasPrefix:@"Georgia"] && b.isDocumentEdited, @"B remembers the font for new text");
    [panel setPanelFont:[NSFont fontWithName:@"Georgia-Bold" size:17] isMultiple:NO];
    [manager modifyFontViaPanel:panel];
    Drain();
    Check([FontName(labelB) hasPrefix:@"Georgia-Bold"], [NSString stringWithFormat:@"A second pick changes B's label again (%@)", FontName(labelB)]);
    [b.undoManager undo]; Drain();
    Check(!b.undoManager.canUndo, @"Two font picks on one label are one undo step");
    Check(![FontName(labelB) hasPrefix:@"Georgia"] && !b.isDocumentEdited, [NSString stringWithFormat:@"Undo in B restores B's label (%@, edited %d, defaults %@, can undo %d '%@')", FontName(labelB), b.isDocumentEdited, b.graph.creationDefaults, b.undoManager.canUndo, b.undoManager.undoActionName]);
    [b.undoManager redo]; Drain();
    Check([FontName(labelB) hasPrefix:@"Georgia"], @"Redo in B reapplies it");
    Check(!a.undoManager.canUndo && !a.isDocumentEdited, @"A's undo stack is untouched");
    // A is key with nothing selected: the panel sets A's font for new text, nothing in B.
    KeyWindow = a.window;
    [a.selectorObject deselect]; [a.selectorObject sendChange:nil]; Drain();
    Check([a.window makeFirstResponder:GraphView(a)] && [NSApp targetForAction:@selector(changeFont:)] == GraphView(a), @"changeFont: reaches A's canvas");
    NSDictionary *defaultsB = [[b.graph.creationDefaults copy] autorelease];
    NSData *xmlB = XML(b);
    [panel setPanelFont:[NSFont fontWithName:@"Menlo-Regular" size:13] isMultiple:NO];
    [manager modifyFontViaPanel:panel];
    Drain();
    Check([a.graph.creationDefaults[@"font-name"] hasPrefix:@"Menlo"] && [FontName(labelA) isEqual:fontA], @"With no selection the panel sets A's font for new text only");
    Check(RSCreationDefaultsEqual(b.graph.creationDefaults, defaultsB) && [XML(b) isEqual:xmlB], @"B is untouched by A's font change");
    [a.undoManager undo]; Drain();
    Check(RSCreationDefaultsEqual(a.graph.creationDefaults, defaultsA) && !a.isDocumentEdited, @"Undo in A restores its defaults");
    NSLog(@"PASS font panel: two documents, distinct selections, key window routing, undo/redo per document");
}

static NSColorWell *StyleColorWell(GraphDocument *document) {
    GraphWindowController *owner = document.windowControllers.firstObject;
    RSInspectorSidebar *sidebar = [owner inspectorSidebar];
    Check([sidebar selectSection:0], @"Style section");
    Drain();
    id inspector = [sidebar tabWithIdentifier:@"com.graphsketcher.GraphSketcher.inspector.style"].inspector;
    Check(inspector != nil, @"Style inspector");
    NSColorWell *well = [inspector valueForKey:@"colorWell"];
    Check([well isKindOfClass:NSColorWell.class] && well.window == document.window, @"Style color well is in the document's sidebar");
    return well;
}
// What the shared color panel does when the user picks a color: active wells take it and send their
// action; the panel also sends -changeColor: along the key window's responder chain.
static void PickColor(NSColor *color) {
    NSColorPanel *panel = NSColorPanel.sharedColorPanel;
    panel.color = color;
    [NSApp sendAction:@selector(changeColor:) to:nil from:panel];
    Drain();
}
static BOOL SameColor(NSColor *x, NSColor *y) { return RSCreationDefaultsEqual(@{@"color": x}, @{@"color": y}); }
// One color pick from the shared panel: exactly the documents in `changed` get it, once.
static void CheckPick(NSColor *color, NSArray *documents, NSArray *labels, NSArray *changed, NSString *what) {
    NSMutableArray *before = [NSMutableArray array];
    for (RSTextLabel *label in labels) [before addObject:label.color];
    NSMutableArray *undo = [NSMutableArray array];
    for (GraphDocument *document in documents) [undo addObject:@(document.undoManager.canUndo)];
    [InspectorColorChanges removeAllObjects];
    PickColor(color);
    for (NSUInteger index = 0; index < documents.count; index++) {
        GraphDocument *document = documents[index]; RSTextLabel *label = labels[index];
        BOOL expected = [changed containsObject:document];
        Check(expected ? SameColor(label.color, color) : SameColor(label.color, before[index]), [NSString stringWithFormat:@"%@: %@ %@ (%@ -> %@)", what, document.displayName, expected ? @"takes the color" : @"is untouched", before[index], label.color]);
        Check(expected ? document.undoManager.canUndo : document.undoManager.canUndo == [undo[index] boolValue], [NSString stringWithFormat:@"%@: undo of %@", what, document.displayName]);
    }
    NSLog(@"%@: inspector color changes for %lu document(s)", what, (unsigned long)InspectorColorChanges.count);
}
static void CheckColorPanel(GraphDocument *a, GraphDocument *b, GraphDocument *legacy) {
    NSArray *documents = @[a, b, legacy];
    NSArray *labels = @[a.graph.userLabels[0], b.graph.userLabels[1], legacy.graph.userLabels[0]];
    for (NSUInteger index = 0; index < 3; index++) { Select(documents[index], labels[index]); [[documents[index] undoManager] removeAllActions]; }
    NSColor *colorA0 = ((RSTextLabel *)labels[0]).color;
    NSDictionary *defaultsA0 = [[a.graph.creationDefaults copy] autorelease];
    Check(legacy.graph.creationDefaults == nil, @"The third document is legacy");
    NSColorWell *wellA = StyleColorWell(a), *wellLegacy = StyleColorWell(legacy);
    StyleColorWell(b);
    Check([wellA isKindOfClass:OAColorWell.class] && [wellLegacy isKindOfClass:OAColorWell.class], [NSString stringWithFormat:@"The Style color well tells the canvas when it is active (%@)", wellA.className]);
    // 1. No active well: the panel colors the key window's selection (Format > Show Colors).
    KeyWindow = b.window; [b.window makeFirstResponder:GraphView(b)];
    CheckPick(NSColor.systemGreenColor, documents, labels, @[b], @"No active well, B key");
    KeyWindow = legacy.window; [legacy.window makeFirstResponder:GraphView(legacy)];
    CheckPick(NSColor.systemBlueColor, documents, labels, @[legacy], @"No active well, legacy key");
    // 2. A's Style well is active, then B becomes key: the well still belongs to A.
    KeyWindow = a.window; [a.window makeFirstResponder:GraphView(a)];
    [wellA activate:YES];
    Check(wellA.isActive && [OAColorWell hasActiveColorWell], @"A's color well is active");
    CheckPick(NSColor.systemOrangeColor, documents, labels, @[a], @"A's well active, A key");
    KeyWindow = b.window; [b.window makeFirstResponder:GraphView(b)];
    CheckPick(NSColor.systemRedColor, documents, labels, @[a], @"A's well active, B key");
    Check(InspectorColorChanges.count == 1 && InspectorColorChanges[0] == a.editor, @"Only A's inspector applied it");
    [wellA deactivate];
    // 3. A legacy document's well: it colors the legacy selection, from its own window or another.
    KeyWindow = legacy.window; [legacy.window makeFirstResponder:GraphView(legacy)];
    [wellLegacy activate:YES];
    CheckPick(NSColor.systemPurpleColor, documents, labels, @[legacy], @"Legacy well active, legacy key");
    KeyWindow = a.window; [a.window makeFirstResponder:GraphView(a)];
    CheckPick(NSColor.systemTealColor, documents, labels, @[legacy], @"Legacy well active, A key");
    [wellLegacy deactivate];
    // A series of picks on one object is one undo step (the user's choice in native qualification): one undo in A
    // returns A's label and A's color for new text to before the series, and never touches B.
    NSColor *colorB = ((RSTextLabel *)labels[1]).color;
    Check([a.undoManager.undoActionName length] && a.undoManager.canUndo, @"A has the color series to undo");
    [a.undoManager undo]; Drain();
    Check(SameColor(((RSTextLabel *)labels[0]).color, colorA0) && RSCreationDefaultsEqual(a.graph.creationDefaults, defaultsA0), [NSString stringWithFormat:@"One undo in A returns the label and the text default to before the series (label %@, defaults %@)", ((RSTextLabel *)labels[0]).color, a.graph.creationDefaults]);
    Check(!a.undoManager.canUndo && !a.isDocumentEdited && SameColor(((RSTextLabel *)labels[1]).color, colorB), @"Nothing else is left to undo in A, and B is untouched");
    [a.undoManager redo]; Drain();
    Check(SameColor(((RSTextLabel *)labels[0]).color, NSColor.systemRedColor) && SameColor(a.graph.creationDefaults[@"text-color"], NSColor.systemRedColor), @"Redo reapplies the last color of the series and its default");
    NSLog(@"PASS color panel: two Graphink documents and a legacy one, distinct selections, active wells and key-window routing, undo per document");
}

#pragma mark - Full screen

static void CheckFullScreen(GraphDocument *document) {
    GraphWindowController *owner = document.windowControllers.firstObject;
    NSWindow *window = owner.window;
    KeyWindow = window;
    // Full screen needs a window AppKit may make full screen and that can grow to the screen.
    Check(window.styleMask & NSWindowStyleMaskResizable, @"Document window is resizable");
    Check(!(window.collectionBehavior & (NSWindowCollectionBehaviorFullScreenNone | NSWindowCollectionBehaviorFullScreenAuxiliary)), @"Document window may go full screen");
    Check(window.contentMaxSize.width >= 4096 && window.contentMaxSize.height >= 4096 && window.maxSize.width >= 4096, @"No maximum size blocks full screen");
    // A normal user resize sets the default frame for new windows.
    NSRect normal = NSMakeRect(100, 100, 900, 700);
    [window setFrame:normal display:NO];
    [owner saveGraphFrame];
    NSString *saved = [[OFPreferenceWrapper sharedPreferenceWrapper] stringForKey:@"LastFrameString"];
    Check(saved.length, @"A normal frame is saved");
    // In full screen the window fills the screen; that frame must not become the default.
    [FullScreenWindows addObject:[NSValue valueWithNonretainedObject:window]];
    [NSNotificationCenter.defaultCenter postNotificationName:NSWindowWillEnterFullScreenNotification object:window];
    [window setFrame:NSMakeRect(0, 0, 1440, 900) display:NO];
    [owner windowDidResize:[NSNotification notificationWithName:NSWindowDidResizeNotification object:window]];
    [owner windowDidMove:[NSNotification notificationWithName:NSWindowDidMoveNotification object:window]];
    [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidEnterFullScreenNotification object:window];
    Check([[[OFPreferenceWrapper sharedPreferenceWrapper] stringForKey:@"LastFrameString"] isEqual:saved], [NSString stringWithFormat:@"Full screen resize keeps the saved frame (%@ -> %@)", saved, [[OFPreferenceWrapper sharedPreferenceWrapper] stringForKey:@"LastFrameString"]]);
    [owner windowDidBecomeMain:[NSNotification notificationWithName:NSWindowDidBecomeMainNotification object:window]];
    Check([[[OFPreferenceWrapper sharedPreferenceWrapper] stringForKey:@"LastFrameString"] isEqual:saved], @"Becoming main in full screen keeps the saved frame");
    // Closing a full-screen window keeps the frame it had before full screen.
    Close(document);
    Check([[[OFPreferenceWrapper sharedPreferenceWrapper] stringForKey:@"LastFrameString"] isEqual:saved], @"Closing in full screen keeps the saved frame");
    [FullScreenWindows removeAllObjects];
    NSLog(@"PASS full screen: resizable, no size cap, full-screen frame never saved as the default");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool { @try {
        [(Class)NSBundle.mainBundle.principalClass sharedApplication];
        [[RSDocumentController alloc] init];
        Check([NSBundle.mainBundle.bundleIdentifier hasPrefix:@"com.graphink.nativequalificationchecks."], @"Unique fixture domain required");
        NSString *domain = NSBundle.mainBundle.bundleIdentifier;
        CFPreferencesSetAppValue(CFSTR("NativeQualificationIsolationProbe"), (CFStringRef)domain, kCFPreferencesCurrentApplication);
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
        id probe = [(id)CFPreferencesCopyAppValue(CFSTR("NativeQualificationIsolationProbe"), (CFStringRef)domain) autorelease];
        Check([probe isEqual:domain], @"Current-application defaults did not route to the unique fixture domain");
        Check(argc >= 3, @"Pass the sample copy and a scratch directory");
        NSURL *sample = [NSURL fileURLWithPath:@(argv[1])];
        Scratch = [[NSURL fileURLWithPath:@(argv[2]) isDirectory:YES] retain];
        OFController *lifecycle = OFController.sharedController;
        Check([lifecycle isKindOfClass:NSClassFromString(@"AppController")], @"OFControllerClass is the production AppController");
        [lifecycle didInitialize]; [lifecycle startedRunning];
        Check(NSApp.delegate == nil, @"No application delegate before the fixture sets one");
        NSApp.delegate = (id <NSApplicationDelegate>)lifecycle;
        NSError *error = nil;
        Check(RSRegisterStyleFonts(NSBundle.mainBundle, &error), error.description);
        InstallEmulation();
        ClearFrameKeys();
        NSData *sampleBytes = Bytes(sample);
        Check(Encoding(sample) == RSGraphArchiveLegacyZIP, @"The sample is a legacy ZIP .ograph");

        // Disposable legacy copies: the ZIP .ograph itself, a plain-XML .ograph, a phase-1 .graphink.
        NSData *xml = Archive(sample)[@"xml"];
        NSURL *zipOgraph = ScratchURL(@"legacy-zip.ograph"), *xmlOgraph = ScratchURL(@"legacy-xml.ograph"), *phase1 = ScratchURL(@"legacy-phase1.graphink");
        Check([NSFileManager.defaultManager copyItemAtURL:sample toURL:zipOgraph error:&error], error.description);
        Check([xml writeToURL:xmlOgraph atomically:NO], @"Plain XML copy");
        Check([RSGraphArchive writeXML:xml defaults:nil preview:nil encoding:RSGraphArchiveLegacyZIP toURL:phase1 error:&error], error.description);
        NSArray *legacy = @[@[zipOgraph, @(RSGraphArchiveLegacyZIP)], @[xmlOgraph, @(RSGraphArchiveLegacyXML)], @[phase1, @(RSGraphArchiveLegacyZIP)]];
        NSUInteger index = 0;
        for (NSArray *item in legacy) CheckLegacyAdoption(item[0], [item[1] integerValue], index++);
        for (NSArray *item in legacy) CheckLegacySave(item[0], [item[1] integerValue]);

        CheckAutosave(sample);
        CheckCrashRecovery();
        CheckUnsupportedPackage();

        GraphDocument *a = OPCCopy(sample, @"opc-two-a.graphink"), *b = OPCCopy(sample, @"opc-two-b.graphink");
        CheckFontPanel(a, b);
        NSURL *legacyColors = ScratchURL(@"legacy-colors.ograph");
        Check([NSFileManager.defaultManager copyItemAtURL:sample toURL:legacyColors error:&error], error.description);
        GraphDocument *legacyDocument = Open(legacyColors);
        CheckColorPanel(a, b, legacyDocument);
        Close(legacyDocument);
        Close(b);
        CheckFullScreen(a);
        ClearFrameKeys();
        Check([Bytes(sample) isEqual:sampleBytes], @"The sample copy is unchanged");
        Check(ScheduledAutosaves > 0, @"AppKit asked to schedule autosaves (and the fixture ran them itself)");

        Check([lifecycle requestTermination] == OFControllerTerminateNow, @"Fixture lifecycle refused termination");
        [lifecycle willTerminate];
        puts("PASS native qualification checks; offscreen only");
    } @catch (NSException *exception) {
        NSLog(@"FAIL native qualification: %@", exception); return 1;
    } }
    return 0;
}
