// Copyright 2003-2013 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <GraphSketcherModel/RSEquationLine.h>
#import "AppController.h"

#import <GraphSketcherModel/OFPreference-RSExtensions.h>
#import <GraphSketcherModel/RSNumber.h>
#import <GraphSketcherModel/RSGraph-XML.h>
#import <OmniInspector/OIInspectorRegistry.h>

#import "GraphDocument.h"
#import "GraphWindowController.h"
#import "InfoPlist.h"
#import "RSMode.h"
#import "RSSelector.h"
#import "RSGraphView.h"
#import "RSNewFromCatalog.h"
#import <OmniAppKit/OAApplication.h>
#import <OmniAppKit/OAWebPageViewer.h>
#import <dlfcn.h>
#import <execinfo.h>
#import <objc/runtime.h>

// Cause our mdimporter to get run if it has been updated.  Note that we won't "downgrade" the index if you run an app with an older importer.
//static void RebuildSpotlightIndexIfNewerMetadataImporter(void)
//{
//    static NSString * const MetadataImporterBundleName = @"OGSSpotlightPlugin";
//    
//    NSString *mdimport = @"/usr/bin/mdimport";
//    NSFileManager *manager = [NSFileManager defaultManager];
//    if (![manager fileExistsAtPath:mdimport])
//        return;
//    
//    NSBundle *mainBundle = [NSBundle mainBundle];
//    NSString *importerPath = [[mainBundle bundlePath] stringByAppendingPathComponent:[NSString stringWithFormat:@"Contents/Library/Spotlight/%@.mdimporter", MetadataImporterBundleName]];
//    NSBundle *importerBundle = [NSBundle bundleWithPath:importerPath];
//    if (!importerBundle) {
//        NSLog(@"Unable to locate Spotlight import bundle in our app wrapper");
//        return;
//    }
//    
//    NSString *importerVersionString = [[importerBundle infoDictionary] objectForKey:@"CFBundleVersion"];
//    OFVersionNumber *importerVersionNumber = nil;
//    if (importerVersionString)
//        importerVersionNumber = [[[OFVersionNumber alloc] initWithVersionString:importerVersionString] autorelease];
//    if (!importerVersionNumber) {
//        NSLog(@"Unable to parse Spotlight import bundle version number '%@'", importerVersionString);
//        return;
//    }
//    
//    static NSString * const LastRunImporterVersionStringDefaultKey = @"com.omnigroup.OmniAppKit.LatestSpotlightImporterVersion";
//    NSString *latestRunImporterVersionString = [[NSUserDefaults standardUserDefaults] stringForKey:LastRunImporterVersionStringDefaultKey];
//    OFVersionNumber *latestRunImporterVersionNumber = nil;
//    if (latestRunImporterVersionString)
//        latestRunImporterVersionNumber = [[[OFVersionNumber alloc] initWithVersionString:latestRunImporterVersionString] autorelease];
//    
//    if (latestRunImporterVersionNumber && [latestRunImporterVersionNumber compareToVersionNumber:importerVersionNumber] != NSOrderedAscending) {
//#ifdef DEBUG
//        NSLog(@"Don't need to rebuild spotlight");
//#endif
//        return;
//    }
//    
//    [[NSUserDefaults standardUserDefaults] setObject:importerVersionString forKey:LastRunImporterVersionStringDefaultKey];
//    
//    // This pokes Finder into updating its list of query keys
//    if ([manager fileExistsAtPath:@"/Library/Spotlight"]) {
//        static NSString * const MagicFileName = @"/Library/Spotlight/.com.omnigroup.OmniAppKit.please.rebuild.my.metadata.keys";
//        [[NSData data] writeToFile:MagicFileName atomically:NO];
//        [manager removeFileAtPath:MagicFileName handler:nil];
//    }
//    
//    // Re-index the documents
//    NSString *appName = [[mainBundle infoDictionary] objectForKey:(id)kCFBundleNameKey];
//    NSLog(@"This version of %@ has a newer Spotlight importer (%@, version %@) than previously run (%@).  Requesting a re-index of files handled by our importer.", appName, importerPath, importerVersionString, latestRunImporterVersionString);
//    
//    // We don't wait for termination
//    [NSTask launchedTaskWithLaunchPath:mdimport arguments:[NSArray arrayWithObjects:@"-r", importerPath, nil]];
//}


@implementation AppController

///////////////////////////////
#pragma mark -
#pragma mark Class methods
///////////////////////////////
- (id)frontDocument
// returns a reference to the foremost document controller
{
    // Get shared document controller:
    NSDocumentController *dc = [NSDocumentController sharedDocumentController];
    // Return frontmost document
    return [dc currentDocument];
}

#if 0
- (GraphDocument *)documentAtPath:(NSString *)path load:(BOOL)shouldLoad error:(NSError **)outError;
{
    path = [path stringByResolvingSymlinksInPath]; // Seem to need this in 10.1 to get the /automount prefix...
    NSURL *url = [NSURL fileURLWithPath:path];
    
    NSDocumentController *sharedDocumentController = [NSDocumentController sharedDocumentController];
    GraphDocument *document = [sharedDocumentController documentForURL:url];
    if (document == nil && shouldLoad)
	document = [sharedDocumentController openDocumentWithContentsOfURL:url display:YES error:outError];
    
    return document;
}

- (void)showDocumentNamed:(NSString *)documentName;
{
    NSString *type = @"ograph";
    NSString *documentPath = [[NSBundle mainBundle] pathForResource:documentName ofType:type];
    if (documentPath == nil) {
	NSLog(@"Could not find bundled document '%@' of type '%@'", documentName, type);
	return;
    }
    
    NSError *error = nil;
    GraphDocument *document = [self documentAtPath:documentPath load:YES error:&error];
    if (!document)
	[[NSApplication sharedApplication] presentError:error];
    
    [document setIsInAppBundle:YES];
    DEBUG_RS(@"Loaded '%@' from app bundle.", documentName);
    
    [document showWindows];
}
#else
- (void)showDocumentNamed:(NSString *)documentName;
{
    NSString *extension = @"ograph";
    NSURL *documentURL = [[NSBundle mainBundle] URLForResource:documentName withExtension:extension];
    if (documentURL == nil) {
	NSLog(@"Could not find bundled document '%@' of with extension '%@'", documentName, extension);
	return;
    }
    
    NSError *error = nil;
    GraphDocument *document = [[NSDocumentController sharedDocumentController] makeDocumentForURL:nil withContentsOfURL:documentURL ofType:RSGraphFileType error:&error];
    if (!document)
	[[NSApplication sharedApplication] presentError:error];

    [document makeWindowControllers];
    [document showWindows];
}
#endif

///////////////////////////////
#pragma mark -
#pragma mark init/dealloc
///////////////////////////////
// First message class gets sent is...
//+ (void)initialize;
//{
//    // Set up default user font:
//    [NSFont setUserFont:[[OFPreferenceWrapper sharedPreferenceWrapper] fontForKey:@"DefaultLabelFont"]];
//}

- (void)dealloc
{
    [_inspector release];

    [super dealloc];
}

/////////////////////////////////
#pragma mark -
#pragma mark Assertion handling
/////////////////////////////////

// OFController crashes on every NSAssert routed to the NSAssertionHandler, AppKit's own included.
// Graphink and Omni assertions keep that; assertions Apple's frameworks fail about their own objects
// raise or are logged instead (below). "Apple's" is decided by image path (/System/, /usr/lib/),
// never by class or symbol name, so it also holds in stripped Release builds. Only the main thread
// goes through OFController; other threads already use Apple's handler.
// AppKit opens a menu "for inspection" to answer an accessibility query on one of its items; if
// the menu really opened meanwhile (a popup opened by AXPress while an accessibility client walks
// the hierarchy), -[NSMenu _simulateClosed] fails an internal assertion and does nothing, as it
// does in a build without assertions. Log that one and return, even where the rule below would
// raise: the accessibility query then still gets its value.
static BOOL RSIsHarmlessAppKitAssertion(SEL selector, id object, NSString *fileName)
{
    return selector == NSSelectorFromString(@"_simulateClosed") && [object isKindOfClass:[NSMenu class]] && [[fileName lastPathComponent] isEqualToString:@"NSMenu.m"];
}

// Apple's frameworks and libraries; the system volume holds nothing of ours.
static BOOL RSIsSystemPath(const char *path)
{
    return path != NULL && (strncmp(path, "/System/", 8) == 0 || strncmp(path, "/usr/lib/", 9) == 0);
}

static BOOL RSIsSystemCode(const void *address)
{
    Dl_info info;
    return address != NULL && dladdr(address, &info) && RSIsSystemPath(info.dli_fname);
}

// Decided by the bundle of the object's class: a Graphink or Omni subclass of an AppKit class is ours.
static BOOL RSIsSystemFrameworkObject(id object)
{
    return object != nil && RSIsSystemPath([[[NSBundle bundleForClass:[object class]] bundlePath] fileSystemRepresentation]);
}

// AppKit's accessibility entry points, called by HIServices for each accessibility request, catch
// exceptions and return an accessibility error. Elsewhere on the main thread the innermost catcher
// is OAApplication's -sendEvent: (or -[NSApplication run] around -[OAApplication nextEventMatchingMask:...],
// which every event loop goes through, menu tracking included); both pass the exception to
// OFController, which crashes. So a raise is safe only if AppKit called from HIServices comes
// before any OmniAppKit frame. Checks/check-assertion-policy.py checks both sides.
static BOOL RSInnermostCatcherIsAccessibilityEntryPoint(void)
{
    static const char *appKitImage, *omniAppKitImage, *hiServicesImage;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        appKitImage = class_getImageName([NSApplication class]);
        omniAppKitImage = class_getImageName([OAApplication class]);
        Dl_info info;
        if (dladdr((const void *)AXUIElementCopyAttributeValue, &info))
            hiServicesImage = info.dli_fname;
    });
    if (!appKitImage || !omniAppKitImage || !hiServicesImage)
        return NO;

    void *frames[256];
    int frameCount = backtrace(frames, 256);
    const char *calleeImage = NULL;
    for (int frameIndex = 0; frameIndex < frameCount; frameIndex++) {
        Dl_info info;
        const char *image = dladdr(frames[frameIndex], &info) ? info.dli_fname : NULL;
        if (image && strcmp(image, omniAppKitImage) == 0)
            return NO;
        if (image && strcmp(image, hiServicesImage) == 0)
            return calleeImage && strcmp(calleeImage, appKitImage) == 0;
        calleeImage = image;
    }
    return NO;
}

// Assertions failed by Apple's own code about Apple's own objects. Raise like Apple's default
// NSAssertionHandler where AppKit catches it; where a raise would reach OFController and crash,
// log and return, as a build without assertions would continue.
static void RSHandleSystemFrameworkAssertion(NSString *location, NSString *description)
{
    if (RSInnermostCatcherIsAccessibilityEntryPoint()) {
        NSLog(@"Raising system framework assertion in %@ as NSInternalInconsistencyException: %@", location, description);
        [[NSException exceptionWithName:NSInternalInconsistencyException reason:description userInfo:nil] raise];
    }
    NSLog(@"Ignoring system framework assertion in %@ (a raise here would reach OFController's crash handler): %@", location, description);
}

// Apple's frameworks call these variadic entry points directly, so the return address is the
// asserting code. Our own NSAsserts, and Apple's about objects of our classes, keep crashing.
- (void)handleFailureInMethod:(SEL)selector object:(id)object file:(NSString *)fileName lineNumber:(int)line description:(NSString *)format, ...;
{
    va_list args;
    va_start(args, format);
    if (!RSIsHarmlessAppKitAssertion(selector, object, fileName) && RSIsSystemFrameworkObject(object) && RSIsSystemCode(__builtin_return_address(0))) {
        NSString *description = [[[NSString alloc] initWithFormat:format arguments:args] autorelease];
        va_end(args);
        NSString *location = [NSString stringWithFormat:@"%c[%@ %@] (%@:%d)", class_isMetaClass(object_getClass(object)) ? '+' : '-', NSStringFromClass([object class]), NSStringFromSelector(selector), fileName, line];
        RSHandleSystemFrameworkAssertion(location, description);
        return;
    }
    [self handleFailureInMethod:selector object:object file:fileName lineNumber:line format:format arguments:args];
    va_end(args);
}

// A function assertion has no object; the image of the asserting code decides.
- (void)handleFailureInFunction:(NSString *)functionName file:(NSString *)fileName lineNumber:(int)line description:(NSString *)format, ...;
{
    va_list args;
    va_start(args, format);
    if (RSIsSystemCode(__builtin_return_address(0))) {
        NSString *description = [[[NSString alloc] initWithFormat:format arguments:args] autorelease];
        va_end(args);
        RSHandleSystemFrameworkAssertion([NSString stringWithFormat:@"%@ (%@:%d)", functionName, fileName, line], description);
        return;
    }
    [self handleFailureInFunction:functionName file:fileName lineNumber:line format:format arguments:args];
    va_end(args);
}

- (void)handleFailureInMethod:(SEL)selector object:(id)object file:(NSString *)fileName lineNumber:(int)line format:(NSString *)format arguments:(va_list)args;
{
    if (!RSIsHarmlessAppKitAssertion(selector, object, fileName)) {
        [super handleFailureInMethod:selector object:object file:fileName lineNumber:line format:format arguments:args];
        return;
    }
    NSString *description = [[[NSString alloc] initWithFormat:format arguments:args] autorelease];
    NSLog(@"Ignoring AppKit assertion in -[%@ %@] (%@:%d): %@", NSStringFromClass([object class]), NSStringFromSelector(selector), fileName, line, description);
}

/////////////////////////////////
#pragma mark -
#pragma mark NSApplication delegate
/////////////////////////////////

- (void)applicationWillFinishLaunching:(NSNotification *)notification;
{
    [NSColor setIgnoresAlpha:NO];
    
    // The shared release-notes viewer has no software-update news URL in this app.
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"OSUCurrentNewsURL": @""}];
    [super applicationWillFinishLaunching:notification];
    
    [self _installNewFromMenu];
    
    // Add a menu of experimental features if the preference for it is turned on.
    if ([[OFPreferenceWrapper sharedPreferenceWrapper] boolForKey:@"ShowExperimentalFeaturesMenu"]) {
        NSMenu *experimentalMenu = [[NSMenu alloc] initWithTitle:NSLocalizedString(@"Experimental", @"Experimental menu item")];
        NSInteger index = -1;
        [experimentalMenu insertItemWithTitle:NSLocalizedString(@"Generate Normal Data", @"Experimental menu item") action:@selector(generateStandardNormalData:) keyEquivalent:@"" atIndex:++index];
        
        [experimentalMenu insertItem:[NSMenuItem separatorItem] atIndex:++index];
        [experimentalMenu insertItemWithTitle:NSLocalizedString(@"Tufte Tick Marks", @"Experimental menu item") action:@selector(toggleTickLayoutAtData:) keyEquivalent:@"" atIndex:++index];
        [experimentalMenu insertItemWithTitle:NSLocalizedString(@"Tufte Axis Extent", @"Experimental menu item") action:@selector(toggleAxesUseDataExtent:) keyEquivalent:@"" atIndex:++index];
        [experimentalMenu insertItemWithTitle:NSLocalizedString(@"Show Data Quartiles", @"Experimental menu item") action:@selector(toggleAxesUseDataQuartiles:) keyEquivalent:@"" atIndex:++index];
        
        [experimentalMenu insertItem:[NSMenuItem separatorItem] atIndex:++index];
        [experimentalMenu insertItemWithTitle:NSLocalizedString(@"Dotted Grid Lines", @"Experimental menu item") action:@selector(toggleDottedGrid:) keyEquivalent:@"" atIndex:++index];
        
        [experimentalMenu insertItem:[NSMenuItem separatorItem] atIndex:++index];
        [[experimentalMenu insertItemWithTitle:NSLocalizedString(@"y = x^2 + c", @"Experimental menu item") action:@selector(addEquationLine:) keyEquivalent:@"" atIndex:++index] setTag:RSEquationTypeSquare];
        [[experimentalMenu insertItemWithTitle:NSLocalizedString(@"y = x^3 + c", @"Experimental menu item") action:@selector(addEquationLine:) keyEquivalent:@"" atIndex:++index] setTag:RSEquationTypeCube];
        [[experimentalMenu insertItemWithTitle:NSLocalizedString(@"y = sin(x) + c", @"Experimental menu item") action:@selector(addEquationLine:) keyEquivalent:@"" atIndex:++index] setTag:RSEquationTypeSine];
        [[experimentalMenu insertItemWithTitle:NSLocalizedString(@"y = e^(-x^2) + c (Bell Curve)", @"Experimental menu item") action:@selector(addEquationLine:) keyEquivalent:@"" atIndex:++index] setTag:RSEquationTypeGaussian];
        [[experimentalMenu insertItemWithTitle:NSLocalizedString(@"y = 1/(1 + e^-x) + c (Logistic)", @"Experimental menu item") action:@selector(addEquationLine:) keyEquivalent:@"" atIndex:++index] setTag:RSEquationTypeLogistic];
        
        [experimentalMenu insertItem:[NSMenuItem separatorItem] atIndex:++index];
        [experimentalMenu insertItemWithTitle:NSLocalizedString(@"Import and Replace Data", @"Experimental menu item") action:@selector(importDataSeriesReplacingCurrent:) keyEquivalent:@"" atIndex:++index];
        [experimentalMenu insertItemWithTitle:NSLocalizedString(@"Import Data Series In Rows", @"Experimental menu item") action:@selector(importDataInRows:) keyEquivalent:@"" atIndex:++index];
        
        NSMenuItem *experimentalMenuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Experimental", @"Experimental menu item") action:NULL keyEquivalent:@""];
        [experimentalMenuItem setImage:[NSImage imageNamed:@"experimental"]];
        [experimentalMenuItem setSubmenu:experimentalMenu];
        [[[NSApplication sharedApplication] mainMenu] insertItem:experimentalMenuItem atIndex:7];
        
        [experimentalMenu release];
        [experimentalMenuItem release];
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
    DEBUG_RS(@"ApplicationDidFinishLaunching");
    
    // Documents restored or opened from Finder use up the first launch; the example never joins them.
    if ([self _initialExampleAction:RSInitialExampleHookDidFinishLaunching] == RSInitialExampleConsume)
        [[OFPreferenceWrapper sharedPreferenceWrapper] setBool:YES forKey:RSInitialExampleShownKey];
    
    [self checkMessageOfTheDay];
    
    [super applicationDidFinishLaunching:note];
    
    if (LINKBACK_ENABLED) {
        [LinkBack publishServerWithName:OGSLinkBackServerName bundleIdentifier:@"com.diegomarino.Graphink" delegate:self];
        [LinkBack publishServerWithName:OGSLinkBackServerName bundleIdentifier:@"com.diegomarino.Graphink.MacAppStore" delegate:self];
    }
    
    
    // I'm going to turn this off because it appears to be fixing a 10.4 bug, and I'd rather not force users' computers to rebuild metadata unnecessarily.
    //RebuildSpotlightIndexIfNewerMetadataImporter();
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender;
{
    // AppKit asks only when nothing was restored or opened, so the example never joins other windows.
    if ([self _initialExampleAction:RSInitialExampleHookShouldOpenUntitled] == RSInitialExampleOpen) {
        // Marked first, so a failure is not retried on every launch.
        [[OFPreferenceWrapper sharedPreferenceWrapper] setBool:YES forKey:RSInitialExampleShownKey];
        if ([self _openInitialExample])
            return NO;
    }
    return YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender;
{
    // TODO: End editing in any open documents to commit any pending changes

    return [super applicationShouldTerminate:sender];
}

- (void)applicationWillTerminate:(NSNotification *)notification;
{
    [super applicationWillTerminate:notification];
}



/////////////////////////////////////////
#pragma mark -
#pragma mark LinkBackServerDelegate protocol
/////////////////////////////////////////

- (void)linkBackClientDidRequestEdit:(LinkBack*)link ;
// When a client requests an edit of your application data, your server delegate will receive the -linkBackClientDidRequestEdit: message.  The object passed in is an instance of the LinkBack class.  This represents a single connection between the client and the server application.  You should respond to this message by either opening the data for editing or by automatically refreshing the data.
{
    // Much of this copied from OmniGraffle's LiveLinkHelper
    GraphDocument *document = [link representedObject];
    if (document == nil) {
        NSError *errBuf = nil;
        document = [[NSDocumentController sharedDocumentController] openUntitledDocumentAndDisplay:NO error:&errBuf];
        if (!document) {
            // LinkBack doesn't support NSError returns, but it's DO, so it should handle exceptions
            [[NSException exceptionWithName:NSGenericException reason:[errBuf localizedDescription] userInfo:[NSDictionary dictionaryWithObject:errBuf forKey:@"NSError"]] raise];
        }
        [link setRepresentedObject:document];
        [document setLinkBack:link];
    }
    
    // display the document
    if (![[document windowControllers] count])
        [document makeWindowControllers];
    [document showWindows];
    
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
}

- (void)linkBackDidClose:(LinkBack*)link ;
{
    GraphDocument *document = [link representedObject];
    if ([document linkBack] == link) {
        [document linkBackConnectionDidClose:link];
    } else {
        OBASSERT_NOT_REACHED("Got linkBackDidClose: from a link that we don't think is open");
        [link setRepresentedObject:nil];
    }
}


/////////////////////////////////////////
#pragma mark -
#pragma mark Showing windows
/////////////////////////////////////////
- (IBAction)showGettingStarted:(id)sender;
{
    // Reuse an untouched copy rather than stacking duplicates.
    RSNewFromItem *example = [[RSNewFromCatalog mainCatalog] initialExample];
    for (NSDocument *document in [[NSDocumentController sharedDocumentController] documents]) {
        if (example && ![document fileURL] && ![document isDocumentEdited] && [[document displayName] isEqualToString:example.title]) {
            [document showWindows];
            return;
        }
    }
    if (![self _openInitialExample])
        NSBeep();
}

- (RSInitialExampleAction)_initialExampleAction:(RSInitialExampleHook)hook;
{
    BOOL shown = [[OFPreferenceWrapper sharedPreferenceWrapper] boolForKey:RSInitialExampleShownKey];
    return RSInitialExampleActionFor(shown, hook, [[[NSDocumentController sharedDocumentController] documents] count]);
}

- (BOOL)_openInitialExample;
{
    RSNewFromItem *example = [[RSNewFromCatalog mainCatalog] initialExample];
    NSError *error = nil;
    if (example && [[NSDocumentController sharedDocumentController] openUntitledCopyOfURL:example.fileURL displayName:example.title ofType:RSGraphFileType display:YES error:&error])
        return YES;
    NSLog(@"Could not open the initial example: %@", error);
    return NO;
}

- (void)_installNewFromMenu;
{
    // File ▸ New From ▸ goes directly below File ▸ New; its contents come from the bundled manifest.
    for (NSMenuItem *topItem in [[[NSApplication sharedApplication] mainMenu] itemArray]) {
        NSMenu *menu = [topItem submenu];
        NSInteger index = [menu indexOfItemWithTarget:nil andAction:@selector(newDocument:)];
        if (index < 0)
            continue;
        NSMenu *submenu = [[[NSMenu alloc] initWithTitle:NSLocalizedString(@"New From", @"File menu item")] autorelease];
        NSUInteger count = [[RSNewFromCatalog mainCatalog] populateMenu:submenu target:[NSDocumentController sharedDocumentController] action:@selector(newDocumentFromCatalogItem:)];
        NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"New From", @"File menu item") action:NULL keyEquivalent:@""] autorelease];
        if (count)
            [item setSubmenu:submenu];  // without documents the item has no action, so it stays disabled
        [menu insertItem:item atIndex:index + 1];
        return;
    }
}


/////////////////////////////////////////
#pragma mark -
#pragma mark Inspector registry

- (OIInspectorRegistry *)inspectorRegistry;
{
    return [self inspectorRegistryForWindow:[[NSApplication sharedApplication] mainWindow]];
}


- (OIInspectorRegistry *)inspectorRegistryForWindow:(NSWindow *)window;
{
    id controller = window.windowController;
    return [controller isKindOfClass:[GraphWindowController class]] ? [controller inspectorRegistry] : nil;
}

- (NSWindow *)windowForInspectorRegistry:(OIInspectorRegistry *)registry;
{
    for (NSDocument *document in [[NSDocumentController sharedDocumentController] documents]) {
        for (NSWindowController *controller in document.windowControllers) {
            if ([controller isKindOfClass:[GraphWindowController class]] && [(GraphWindowController *)controller inspectorRegistry] == registry)
                return controller.window;
        }
    }
    return nil;
}

/////////////
#pragma mark -
#pragma mark Menu actions implemented elsewhere
/////
- (IBAction)connectPoints:(id)sender
{
    //[[self frontDocument] connectPoints:sender];
    [[self frontDocument] performMenuItem:@selector(connectPoints:) withName:[sender title]];
}
- (IBAction)connectPointsLeftToRight:(id)sender {
    [[self frontDocument] performMenuItem:@selector(connectPointsLeftToRight:) withName:[sender title]];
}
- (IBAction)connectPointsTopToBottom:(id)sender {
    [[self frontDocument] performMenuItem:@selector(connectPointsTopToBottom:) withName:[sender title]];
}
- (IBAction)connectPointsCircular:(id)sender {
    [[self frontDocument] performMenuItem:@selector(connectPointsCircular:) withName:[sender title]];
}


- (IBAction)fillArea:(id)sender {
    [[self frontDocument] performMenuItem:@selector(fillArea:) withName:[sender title]];
}
- (IBAction)addPointToFill:(id)sender {
    [[self frontDocument] performMenuItem:@selector(addPointToFill:) withName:[sender title]];
}
- (IBAction)bestFitLine:(id)sender {
    [[self frontDocument] performMenuItem:@selector(bestFitLine:) withName:[sender title]];
}
- (IBAction)histogram:(id)sender {
    [[self frontDocument] performMenuItem:@selector(histogram:) withName:[sender title]];
}
- (IBAction)groupUngroup:(id)sender {
    [[self frontDocument] performMenuItem:@selector(groupUngroup:) withName:[sender title]];
}
- (IBAction)lockUnlock:(id)sender {
    [[self frontDocument] performMenuItem:@selector(lockUnlock:) withName:[sender title]];
}


- (IBAction)snapToGrid:(id)sender {
    [[self frontDocument] performMenuItem:@selector(snapToGrid:) withName:[sender title]];
}
- (IBAction)displayGrid:(id)sender {
    [[self frontDocument] performMenuItem:@selector(displayGrid:) withName:[sender title]];
}
- (IBAction)selectConnected:(id)sender {
    [[self frontDocument] performMenuItem:@selector(selectConnected:) withName:[sender title]];
}
- (IBAction)selectConnectedPoints:(id)sender {
    [[self frontDocument] performMenuItem:@selector(selectConnectedPoints:) withName:[sender title]];
}
- (IBAction)selectConnectedLines:(id)sender {
    [[self frontDocument] performMenuItem:@selector(selectConnectedLines:) withName:[sender title]];
}
- (IBAction)selectConnectedLabels:(id)sender {
    [[self frontDocument] performMenuItem:@selector(selectConnectedLabels:) withName:[sender title]];
}
- (IBAction)deselect:(id)sender;
{
    [[self frontDocument] performMenuItem:[sender action]];
}
- (IBAction)pasteAndConnect:(id)sender {
    [[self frontDocument] performMenuItem:@selector(pasteAndConnect:) withName:[sender title]];
}
- (IBAction)pasteAndReplace:(id)sender {
    [[self frontDocument] performMenuItem:@selector(pasteAndReplace:) withName:[sender title]];
}
- (IBAction)copyAsImage:(id)sender {
    [[self frontDocument] copyAsImage:sender];
}

- (IBAction)exportPNG:(id)sender {
    [[self frontDocument] performMenuItem:@selector(exportPNG:) withName:[sender title]];
}
- (IBAction)exportJPG:(id)sender {
    [[self frontDocument] performMenuItem:@selector(exportJPG:) withName:[sender title]];
}
- (IBAction)exportPDF:(id)sender {
    [[self frontDocument] performMenuItem:@selector(exportPDF:) withName:[sender title]];
}
- (IBAction)exportTIFF:(id)sender {
    [[self frontDocument] performMenuItem:@selector(exportTIFF:) withName:[sender title]];
}
- (IBAction)exportEPS:(id)sender {
    [[self frontDocument] performMenuItem:@selector(exportEPS:) withName:[sender title]];
}


- (IBAction)scaleToFitData:(id)sender {
    [[self frontDocument] performMenuItem:@selector(scaleToFitData:) withName:[sender title]];
}


- (IBAction)toggleContinuousSpellCheckingRS:(id)sender {
    [[self frontDocument] performMenuItem:@selector(toggleContinuousSpellCheckingRS:) withName:[sender title]];
}
- (IBAction)toggleSuperscript:(id)sender {
    [[self frontDocument] performMenuItem:@selector(toggleSuperscript:) withName:[sender title]];
}
- (IBAction)toggleSubscript:(id)sender {
    [[self frontDocument] performMenuItem:@selector(toggleSubscript:) withName:[sender title]];
}



/////////////
#pragma mark -
#pragma mark Menu actions implemented in this class
/////

// OmniAppKit registers an empty OAMessageOfTheDaySignature default, so its own first-launch test
// (no signature seen yet) never fires and a fresh preference domain would show the release notes
// over the Welcome document. Here a launch without a *saved* signature is the first launch: record
// the current notes silently. OAController then shows them once after any update that changes
// them, and Help ▸ Release Notes (-showMessageOfTheDay:) shows them on demand.
- (void)checkMessageOfTheDay;
{
    OFPreferenceWrapper *defaults = [OFPreferenceWrapper sharedPreferenceWrapper];
    if ([[OFPreference preferenceForKey:@"OAMessageOfTheDaySignature"] hasPersistentValue] || [defaults boolForKey:@"OAShowMessageOfTheDayOnFirstLaunch"]) {
        [super checkMessageOfTheDay];
        return;
    }
    if (![defaults boolForKey:@"OAMessageOfTheDayCheckOnLaunch"])
        return;
    NSString *path = [[NSBundle mainBundle] pathForResource:@"MessageOfTheDay" ofType:@"html"];
    NSData *notes = path ? [NSData dataWithContentsOfFile:path] : nil;
    if (!notes)
        return;
    NSData *signature = (NSData *)OFDataCreateSHA1Digest(kCFAllocatorDefault, (CFDataRef)notes);
    [defaults setObject:signature forKey:@"OAMessageOfTheDaySignature"];
    [signature release];
}

// OAController shows the notes with the CSS media type "release-notes". WebKit only applies the
// dark appearance (prefers-color-scheme) to the "screen" media type, so the page stayed light in
// Dark mode. Same viewer and window, default media type: the page follows Light/Dark, live.
- (IBAction)showMessageOfTheDay:(id)sender;
{
    NSString *path = [[NSBundle mainBundle] pathForResource:@"MessageOfTheDay" ofType:@"html"];
    if (path == nil)
        return;

    OAWebPageViewer *viewer = [OAWebPageViewer sharedViewerNamed:@"Release Notes" options:OAWebPageViewerOptionsStandardReleaseNotesOptions];

    // don't go fullscreen
    NSRect frame = [[viewer window] frame];
    frame.size.width = 800;
    [[viewer window] setFrame:frame display:NO];
    [[viewer window] setMinSize:NSMakeSize(800, 400)];
    [[viewer window] setMaxSize:NSMakeSize(800, FLT_MAX)];

    [viewer setMediaStyle:nil];
    [viewer loadPath:path];
}

- (IBAction)openProductPageInBrowser:(id)sender;
{
    NSString *productPageURLString = [[OFPreferenceWrapper sharedPreferenceWrapper] stringForKey:@"ProductPageURL"];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:productPageURLString]];
}

- (IBAction)openKeyboardShortcuts:(id)sender;
{
    NSString *path = [[NSBundle mainBundle] pathForResource:@"GraphSketcher Keyboard Shortcuts" ofType:@"pdf"];
    [[NSWorkspace sharedWorkspace] openFile:path];// withApplication:@"Preview"];
}

- (IBAction)importData:(id)sender;
    // display pop-up window explaining that you should copy/paste
{
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:NSLocalizedStringFromTable(@"Importing Data", @"DataImporter", @"Alert explaining how to import data")];
    [alert setInformativeText:NSLocalizedStringFromTable(@"To import and plot data from a spreadsheet, database, or text file, copy (⌘C) the data and paste it (⌘V) directly onto your graph.\n\nThe data must be in columns. If you include column headers, they will automatically be interpreted as axis titles. If the first column is descriptive labels, each label will be associated with the data point that follows.", @"DataImporter", @"Alert explaining how to import data")];
    [alert addButtonWithTitle:NSLocalizedStringFromTable(@"Okay", @"DataImporter", @"Alert explaining how to import data")];
    [alert setShowsHelp:YES];
    [alert setHelpAnchor:@"importdata"];
    
    [alert runModal];
    [alert release];
}

- (IBAction)modifyTool:(id)sender {
    [[RSMode sharedModeController] registerClick:RS_modify];
    [[[self frontDocument] graphView] resetCursorRects];
}
- (IBAction)drawTool:(id)sender {
    [[RSMode sharedModeController] registerClick:RS_draw];
    [[[self frontDocument] graphView] resetCursorRects];
}
- (IBAction)fillTool:(id)sender {
    [[RSMode sharedModeController] registerClick:RS_fill];
    [[[self frontDocument] graphView] resetCursorRects];
}
- (IBAction)textTool:(id)sender {
    [[RSMode sharedModeController] registerClick:RS_text];
    [[[self frontDocument] graphView] resetCursorRects];
}


///////////////////////////////
#pragma mark -
#pragma mark Defaults
///////////////////////////////

//! Copied from old Preferences window.  Should expose in UI somewhere.  In the standard OmniAppKit preferences pane, when you hold down option you get a button to "reset all" prefs, but this just applies to those things controlled in the preferences panes.
- (IBAction)resetAllDefaults:(id)sender {
    // Reset all default values
    NSDictionary *dict = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    NSEnumerator *E = [dict keyEnumerator];
    NSString *key;
    while ((key = [E nextObject])) {
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    }
    
    // post notification so that Inspector updates its display too
    [[NSNotificationCenter defaultCenter] 
     postNotificationName:@"RSContextChanged" object:nil];

    for (NSDocument *document in [[NSDocumentController sharedDocumentController] documents])
        for (id controller in document.windowControllers)
            if ([controller isKindOfClass:[GraphWindowController class]]) [controller refreshInspectors];
}



/////////////
#pragma mark -
#pragma mark Menu actions for demos
/////
- (IBAction)demoCurveConstruc:(id)sender {
    [[self frontDocument] performMenuItem:@selector(demoCurveConstruc:)];
}
- (IBAction)demoPenMode:(id)sender {
    [[OFPreferenceWrapper sharedPreferenceWrapper] 
     setBool: [[OFPreferenceWrapper sharedPreferenceWrapper] boolForKey:@"DrawCurvedLines"]
     forKey: @"DrawCurvedLines"];
}


/////////////
#pragma mark -
#pragma mark Menu validation for actions implemented in this class
/////
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    SEL action = [menuItem action];
    
    if (action == @selector(importData:)) {
	return YES;
    }
    else if (action == @selector(demoPenMode:)) {
	if ( [[OFPreferenceWrapper sharedPreferenceWrapper] boolForKey:@"DrawCurvedLines"] ) {
	    [menuItem setState:NSOnState];
	} else {
	    [menuItem setState:NSOffState];
	}
	
	return YES;
    }
    // seems like there should be a better way, but this does the trick without requiring a major re-write.
    else if ( action == @selector(showMessageOfTheDay:) || action == @selector(sendFeedback:) || action == @selector(openProductPageInBrowser:) || action == @selector(showAboutPanel:) || action == @selector(showPreferencesPanel:) || action == @selector(showGettingStarted:) || action == @selector(openKeyboardShortcuts:) )
    {
	return YES;
    }
    else  return [[self frontDocument] validateMenuItem:menuItem];
}

@end
