// Windowless checks for File ▸ New From: catalog/menu, untitled-copy ownership,
// original preservation and the once-only first-launch hooks, using production App sources.
#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <GraphSketcherModel/RSGraph.h>
#import <GraphSketcherModel/RSGraphEditor.h>
#import <GraphSketcherModel/RSVertex.h>
#import <GraphSketcherModel/RSUndoer.h>
#import <GraphSketcherModel/RSUndoerOwner.h>
#import <WebKit/WebKit.h>
#import <OmniAppKit/OAWebPageViewer.h>
#import "AppController.h"
#import "GraphDocument.h"
#import "RSDocumentController.h"
#import "RSNewFromCatalog.h"

static NSUInteger Failures;
static void Check(BOOL ok, NSString *message) {
    if (!ok) { Failures++; printf("FAIL %s\n", message.UTF8String); }
}
#define CHECK(condition, ...) Check((condition), [NSString stringWithFormat:__VA_ARGS__])

static NSString *SHA256(NSURL *url) {
    NSData *data = [NSData dataWithContentsOfURL:url]; if (!data) return @"missing";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString string]; for (int i=0;i<CC_SHA256_DIGEST_LENGTH;i++) [hex appendFormat:@"%02x",digest[i]];
    return hex;
}
static NSArray *Documents(void) { return [[NSDocumentController sharedDocumentController] documents]; }
static void CloseAll(void) { for (NSDocument *d in [[Documents() copy] autorelease]) [d close]; }

@interface CheckOwner : NSObject <RSUndoerOwner>
@property(nonatomic, retain) NSUndoManager *undoManager;
@end
@implementation CheckOwner
@synthesize undoManager = _undoManager;
- (id)init { if ((self = [super init])) _undoManager = [[NSUndoManager alloc] init]; return self; }
- (void)undoerPerformedChange:(RSUndoer *)undoer {}
- (void)dealloc { [_undoManager release]; [super dealloc]; }
@end

// Production code asks for displayed documents; these checks must never create windows.
static NSUInteger DisplayRequests;
@implementation NSDocumentController (NewFromChecks)
- (NSDocument *)checks_openUntitledCopyOfURL:(NSURL *)url displayName:(NSString *)name ofType:(NSString *)typeName display:(BOOL)display error:(NSError **)outError {
    if (display) DisplayRequests++;
    return [self checks_openUntitledCopyOfURL:url displayName:name ofType:typeName display:NO error:outError];
}
@end
// Reusing an open copy brings it front; with no window controllers that creates nothing, so only count it.
static NSUInteger ShowRequests;
@implementation NSDocument (NewFromChecks)
- (void)checks_showWindows { CHECK(self.windowControllers.count==0, @"windowless documents only"); ShowRequests++; }
@end
static void Swizzle(Class cls, SEL original, SEL replacement) {
    method_exchangeImplementations(class_getInstanceMethod(cls, original), class_getInstanceMethod(cls, replacement));
}

static void CheckPolicy(void) {
    struct { BOOL shown; RSInitialExampleHook hook; NSUInteger docs; RSInitialExampleAction expected; } rows[] = {
        {NO,  RSInitialExampleHookShouldOpenUntitled, 0, RSInitialExampleOpen},
        {NO,  RSInitialExampleHookDidFinishLaunching, 0, RSInitialExampleNone},
        {NO,  RSInitialExampleHookDidFinishLaunching, 2, RSInitialExampleConsume},
        {YES, RSInitialExampleHookShouldOpenUntitled, 0, RSInitialExampleNone},
        {YES, RSInitialExampleHookDidFinishLaunching, 3, RSInitialExampleNone},
    };
    for (size_t i=0;i<sizeof(rows)/sizeof(rows[0]);i++)
        CHECK(RSInitialExampleActionFor(rows[i].shown,rows[i].hook,rows[i].docs)==rows[i].expected, @"policy row %zu", i);
    puts("PASS policy rows=5");
}

static NSArray *Titles(NSMenu *menu) { return [[menu itemArray] valueForKey:@"title"]; }
static void CheckMenuItems(NSMenu *menu, NSUInteger first, NSArray *titles) {
    for (NSUInteger i=0;i<titles.count;i++) {
        NSMenuItem *item = [menu itemAtIndex:first+i];
        CHECK([item.title isEqual:titles[i]], @"menu item %@ title", titles[i]);
        CHECK(item.action==@selector(newDocumentFromCatalogItem:) && item.target==[NSDocumentController sharedDocumentController], @"%@ target/action", titles[i]);
        CHECK([item.representedObject isKindOfClass:[RSNewFromItem class]] && [[item.representedObject fileURL] checkResourceIsReachableAndReturnError:NULL], @"%@ resource", titles[i]);
        CHECK([[NSDocumentController sharedDocumentController] validateUserInterfaceItem:item], @"%@ validates enabled", titles[i]);
        CHECK(item.keyEquivalent.length==0, @"%@ has no key equivalent", titles[i]);
    }
}
static void CheckHeader(NSMenuItem *header, NSString *title) {
    CHECK([header.title isEqual:title], @"header %@", title);
    if (@available(macOS 14.0, *)) CHECK(header.isSectionHeader, @"%@ is a native section header", title);
    CHECK(header.action==NULL, @"%@ header is not actionable", title);
}

// The bundled catalog synced from Examples/NewFrom-manifest.plist: lessons, data charts, templates.
static NSArray *GroupTitles(NSUInteger group) {
    return @[@[@"Market Equilibrium",@"Demand and Supply Shifts",@"Tax Incidence and Welfare",@"Binding Price Ceiling",@"Binding Price Floor",@"Monopoly Output and Price",@"Marginal and Average Cost",@"Budget Line and Indifference Curves",
               @"Elasticity Along a Linear Demand",@"Income and Substitution Effects",@"Isoquants and Isocost Lines",@"A Competitive Firm in the Short Run",@"An Import Tariff",
               @"The Monopsonist Buyer",@"Third-Degree Price Discrimination",@"Cournot Duopoly",@"The Gains from Trade",@"A Negative Externality"],
             @[@"Income Tax Concentration in Spain, 2024",@"Tax Revenue as a Share of GDP, Spain",@"House Prices and Wages in Real Terms, Spain"],
             @[@"Function Plot",@"Time Series",@"Scatter Plot",@"Bar Chart",@"Logarithmic Scale",@"Number Line",@"Supply and Demand",@"Lorenz Curve",@"Production Possibilities Frontier"]][group];
}
static NSArray *AllItems(RSNewFromCatalog *catalog) {
    NSMutableArray *items = [NSMutableArray array];
    for (RSNewFromGroup *group in catalog.groups) [items addObjectsFromArray:group.items];
    [items addObject:catalog.initialExample];
    return items;
}
static void CheckBundledMenu(NSMenu *menu) {
    NSArray *headers = @[@"Examples",@"Data Charts",@"Templates"];
    NSInteger index = 0;
    for (NSUInteger g=0; g<3; g++) {
        if (g) { CHECK([[menu itemAtIndex:index] isSeparatorItem], @"separator before %@", headers[g]); index++; }
        CheckHeader([menu itemAtIndex:index], headers[g]);
        CheckMenuItems(menu, index+1, GroupTitles(g));
        index += 1 + [GroupTitles(g) count];
    }
}

static void CheckCatalog(NSURL *bundledDirectory, NSURL *scratch) {
    RSNewFromCatalog *catalog = [RSNewFromCatalog mainCatalog];
    CHECK(catalog!=nil && [[catalog.directoryURL URLByStandardizingPath] isEqual:[bundledDirectory URLByStandardizingPath]], @"main catalog reads the bundled NewFrom folder");
    CHECK([catalog.initialExample.title isEqual:@"Welcome to Graphink"], @"initial example title");
    CHECK([[catalog.groups valueForKey:@"identifier"] isEqual:(@[@"examples",@"data",@"templates"])], @"groups in manifest order");
    CHECK([[catalog.groups valueForKey:@"title"] isEqual:(@[@"Examples",@"Data Charts",@"Templates"])], @"group titles");
    for (NSUInteger g=0; g<3; g++)
        CHECK([[[catalog.groups[g] items] valueForKey:@"title"] isEqual:GroupTitles(g)], @"%@ titles and order (got %@)", [catalog.groups[g] identifier], [[catalog.groups[g] items] valueForKey:@"title"]);
    CHECK(catalog.skippedEntries.count==0, @"nothing skipped");
    for (RSNewFromItem *item in AllItems(catalog))
        CHECK([SHA256(item.fileURL) isEqual:item.sha256], @"%@ matches its manifest SHA256", item.relativePath);

    NSMenu *menu = [[[NSMenu alloc] initWithTitle:@"New From"] autorelease];
    NSUInteger count = [catalog populateMenu:menu target:[NSDocumentController sharedDocumentController] action:@selector(newDocumentFromCatalogItem:)];
    CHECK(count==30 && menu.numberOfItems==35, @"bundled menu has three headers, two separators and 30 items (got %@)", Titles(menu));
    CheckBundledMenu(menu);

    // A catalog with templates and invalid entries: new documents need only files and manifest entries.
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *dir = [scratch URLByAppendingPathComponent:@"InjectedNewFrom"];
    NSError *error = nil;
    CHECK([fm copyItemAtURL:bundledDirectory toURL:dir error:&error], @"copy catalog: %@", error);
    [fm createDirectoryAtURL:[dir URLByAppendingPathComponent:@"Templates"] withIntermediateDirectories:NO attributes:nil error:NULL];
    [fm copyItemAtURL:[dir URLByAppendingPathComponent:@"Examples/01-market-equilibrium.graphink"] toURL:[dir URLByAppendingPathComponent:@"Templates/supply-and-demand.graphink"] error:NULL];
    NSMutableDictionary *manifest = [NSMutableDictionary dictionaryWithContentsOfURL:[dir URLByAppendingPathComponent:RSNewFromManifestName]];
    NSArray *bad = @[@{@"File":@"/etc/hosts.graphink",@"Title":@"Absolute"}, @{@"File":@"../NewFrom/Examples/01-market-equilibrium.graphink",@"Title":@"Escapes"},
                     @{@"File":@"Templates/notes.txt",@"Title":@"Wrong type"}, @{@"File":@"Templates/missing.graphink",@"Title":@"Missing"},
                     @{@"File":@"Templates/supply-and-demand.graphink"}, @{@"File":@"Templates/supply-and-demand.graphink",@"Title":@"Extra",@"Color":@"red"}, @"not a dictionary"];
    NSMutableArray *templates = [NSMutableArray arrayWithObject:@{@"File":@"Templates/supply-and-demand.graphink",@"Title":@"Supply and Demand"}];
    [templates addObjectsFromArray:bad];
    manifest[@"Groups"] = @[manifest[@"Groups"][0], @{@"Identifier":@"templates",@"Title":@"Templates",@"Items":templates}, @{@"Identifier":@"empty",@"Title":@"Empty",@"Items":@[]}];
    CHECK([manifest writeToURL:[dir URLByAppendingPathComponent:RSNewFromManifestName] atomically:YES], @"write injected manifest");
    RSNewFromCatalog *injected = [RSNewFromCatalog catalogWithDirectoryURL:dir error:&error];
    CHECK(injected.skippedEntries.count==bad.count, @"every invalid entry skipped (%lu of %lu)", (unsigned long)injected.skippedEntries.count, (unsigned long)bad.count);
    count = [injected populateMenu:menu target:[NSDocumentController sharedDocumentController] action:@selector(newDocumentFromCatalogItem:)];
    // The examples group as bundled (header + lessons), a separator, then the one valid template under its header.
    NSUInteger lessons = [GroupTitles(0) count];
    CHECK(count==lessons+1 && menu.numberOfItems==lessons+4 && [[menu itemAtIndex:lessons+1] isSeparatorItem], @"examples, separator, templates; empty group omitted (got %@)", Titles(menu));
    CheckHeader([menu itemAtIndex:lessons+2], @"Templates");
    CheckMenuItems(menu, lessons+3, @[@"Supply and Demand"]);
    CHECK([RSNewFromCatalog catalogWithDirectoryURL:[scratch URLByAppendingPathComponent:@"absent"] error:&error]==nil && error, @"missing manifest is an error");
    printf("PASS catalog-and-menu bundled-items=30 injected-items=%lu rejected=7\n", (unsigned long)lessons+1);
}

static void CheckInstalledMenu(AppController *controller) {
    NSMenu *main = [[[NSMenu alloc] initWithTitle:@"Main"] autorelease], *file = [[[NSMenu alloc] initWithTitle:@"File"] autorelease];
    [file addItemWithTitle:@"New" action:@selector(newDocument:) keyEquivalent:@"n"];
    [file addItemWithTitle:@"Open…" action:@selector(openDocument:) keyEquivalent:@"o"];
    [[main addItemWithTitle:@"File" action:NULL keyEquivalent:@""] setSubmenu:file];
    [[NSApplication sharedApplication] setMainMenu:main];
    ((void (*)(id, SEL))objc_msgSend)(controller, NSSelectorFromString(@"_installNewFromMenu"));
    NSMenuItem *item = [file itemAtIndex:1];
    CHECK([Titles(file) isEqual:(@[@"New",@"New From",@"Open…"])], @"New From sits below New (got %@)", Titles(file));
    CHECK(item.submenu.numberOfItems==35 && item.keyEquivalent.length==0, @"installed New From submenu");
    [file update];
    CHECK(item.isEnabled, @"New From is enabled");
    CheckBundledMenu(item.submenu);
    puts("PASS installed-menu");
}

static void Edit(GraphDocument *document) {
    RSVertex *vertex = document.graph.Vertices.firstObject;
    [document.undoManager beginUndoGrouping];
    [document.editor changeX:vertex.position.x+.5 forElement:vertex];
    [document.undoManager endUndoGrouping];
    [document.undoer endRepetitiveUndo];
    // NSDocument counts the closed undo group on the main queue.
    __block BOOL counted = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ counted = YES; });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (!counted && deadline.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:deadline];
}

static void CheckOwnership(NSURL *scratch) {
    RSNewFromCatalog *catalog = [RSNewFromCatalog mainCatalog];
    NSDocumentController *controller = [NSDocumentController sharedDocumentController];
    NSArray *items = AllItems(catalog);
    NSUInteger index = 0;
    for (RSNewFromItem *item in items) {
        NSString *before = SHA256(item.fileURL); NSError *error = nil;
        GraphDocument *a = (GraphDocument *)[controller openUntitledCopyOfURL:item.fileURL displayName:item.title ofType:RSGraphFileType display:NO error:&error];
        GraphDocument *b = (GraphDocument *)[controller openUntitledCopyOfURL:item.fileURL displayName:item.title ofType:RSGraphFileType display:NO error:&error];
        CHECK([a isKindOfClass:[GraphDocument class]] && [b isKindOfClass:[GraphDocument class]], @"%@ opens as GraphDocument: %@", item.title, error);
        for (GraphDocument *d in @[a,b]) {
            CHECK(d.fileURL==nil && d.autosavedContentsFileURL==nil, @"%@ copy has no file", item.title);
            CHECK(!d.isDocumentEdited && !d.isInAppBundle && ![d.undoManager canUndo], @"%@ copy is clean and user-owned", item.title);
            CHECK([d.fileType isEqual:RSGraphFileType] && d.archiveEncoding==RSGraphArchiveOPC && d.graph.creationDefaults!=nil, @"%@ copy keeps OPC defaults", item.title);
            CHECK([Documents() containsObject:d], @"%@ copy registered", item.title);
        }
        CHECK([a.displayName isEqual:item.title] && [b.displayName isEqual:[item.title stringByAppendingString:@" 2"]], @"%@ display names (%@, %@)", item.title, a.displayName, b.displayName);
        CHECK(a.graph!=b.graph && a.undoManager!=b.undoManager, @"%@ copies are independent", item.title);
        CHECK(![[controller recentDocumentURLs] containsObject:item.fileURL], @"%@ original not in recents", item.title);

        RSDataPoint untouched = [(RSVertex *)b.graph.Vertices.firstObject position];
        Edit(a);
        CHECK(a.isDocumentEdited && !b.isDocumentEdited, @"%@ edit marks only its copy", item.title);
        CHECK([(RSVertex *)b.graph.Vertices.firstObject position].x==untouched.x, @"%@ other copy unchanged", item.title);

        NSURL *saved = [scratch URLByAppendingPathComponent:[NSString stringWithFormat:@"saved-%lu.graphink",(unsigned long)index]];
        NSURL *autosaved = [scratch URLByAppendingPathComponent:[NSString stringWithFormat:@"autosaved-%lu.graphink",(unsigned long)index]];
        CHECK([a saveToURL:saved ofType:RSGraphFileType forSaveOperation:NSSaveAsOperation error:&error], @"%@ Save As: %@", item.title, error);
        CHECK([a.fileURL isEqual:saved] && b.fileURL==nil, @"%@ Save As moves only the saved copy", item.title);
        Edit(b);
        CHECK([b saveToURL:autosaved ofType:RSGraphFileType forSaveOperation:NSAutosaveElsewhereOperation error:&error] && b.fileURL==nil, @"%@ autosave elsewhere: %@", item.title, error);
        for (NSURL *url in @[saved, autosaved]) {
            NSInteger encoding = -1; CheckOwner *owner = [[[CheckOwner alloc] init] autorelease]; RSUndoer *undoer = [[[RSUndoer alloc] initWithOwner:owner] autorelease];
            RSGraph *graph = [RSGraph graphFromURL:url type:RSGraphFileType undoer:undoer encoding:&encoding error:&error];
            CHECK(graph!=nil && encoding==RSGraphArchiveOPC && graph.creationDefaults!=nil, @"%@ %@ reopens as OPC: %@", item.title, url.lastPathComponent, error);
            [graph invalidate]; [undoer invalidate];
        }
        CHECK([SHA256(item.fileURL) isEqual:before] && [before isEqual:item.sha256], @"%@ original hash preserved", item.title);
        CloseAll(); index++;
    }
    printf("PASS ownership items=%lu\n", (unsigned long)index);
}

static void CheckFirstLaunch(AppController *controller) {
    OFPreferenceWrapper *prefs = [OFPreferenceWrapper sharedPreferenceWrapper];
    NSApplication *app = [NSApplication sharedApplication];
    CHECK([[[NSUserDefaults standardUserDefaults] volatileDomainForName:NSRegistrationDomain] objectForKey:RSInitialExampleShownKey]!=nil, @"preference default registered from Info.plist");
    [prefs removeObjectForKey:RSInitialExampleShownKey];
    CHECK(![prefs boolForKey:RSInitialExampleShownKey] && Documents().count==0, @"fresh state");

    // Launch with nothing restored: AppKit asks for an untitled file; the example replaces it, once.
    DisplayRequests = 0;
    CHECK(![controller applicationShouldOpenUntitledFile:app], @"first launch suppresses the empty Untitled window");
    GraphDocument *example = Documents().firstObject;
    CHECK(Documents().count==1 && DisplayRequests==1 && [example.displayName isEqual:@"Welcome to Graphink"] && example.fileURL==nil && !example.isDocumentEdited, @"first launch opens one clean untitled example");
    CHECK([prefs boolForKey:RSInitialExampleShownKey], @"first launch is recorded");
    CHECK([controller applicationShouldOpenUntitledFile:app] && Documents().count==1, @"later launches and reopens open a normal Untitled window, not the example");

    // Help ▸ Getting Started reuses an untouched copy, opens a fresh one once the copy is edited.
    ShowRequests = 0;
    [controller showGettingStarted:nil];
    CHECK(Documents().count==1 && ShowRequests==1 && DisplayRequests==1, @"Getting Started brings the untouched copy front instead of opening another");
    Edit(example);
    [controller showGettingStarted:nil];
    CHECK(Documents().count==2 && DisplayRequests==2, @"Getting Started opens a new copy when the old one was edited");
    CloseAll();

    // A first launch that restored or opened documents is used up without adding the example.
    [prefs removeObjectForKey:RSInitialExampleShownKey];
    NSError *error = nil;
    NSDocument *restored = [[NSDocumentController sharedDocumentController] openUntitledDocumentAndDisplay:NO error:&error];
    RSInitialExampleAction action = ((RSInitialExampleAction (*)(id, SEL, RSInitialExampleHook))objc_msgSend)(controller, NSSelectorFromString(@"_initialExampleAction:"), RSInitialExampleHookDidFinishLaunching);
    CHECK(restored && action==RSInitialExampleConsume && Documents().count==1, @"restored documents consume the first launch");
    CloseAll();
    [prefs removeObjectForKey:RSInitialExampleShownKey];
    puts("PASS first-launch");
}

// Release notes (OmniAppKit's message of the day): never on first launch, once after the bundled
// notes change, never again until they change. Uses the production AppController overrides and
// OAController's own logic; only the viewer is recorded instead of opened (no window is created).
@interface RecordingViewer : NSObject
@property(nonatomic, copy) NSString *mediaStyle;
@property(nonatomic, copy) NSString *loadedPath;
@property(nonatomic) NSUInteger loads;
@end
@implementation RecordingViewer
- (NSWindow *)window { return nil; }
- (void)loadPath:(NSString *)path { self.loadedPath = path; self.loads++; }
@end
static NSData *SHA1(NSData *data) { return [(NSData *)OFDataCreateSHA1Digest(kCFAllocatorDefault, (CFDataRef)data) autorelease]; }
// The bundled notes in a window-less WebView with the media type the production viewer was given:
// the page background and text follow Light/Dark, also when the appearance changes while open.
static NSString *Probe(WebView *web) {
    for (NSUInteger i = 0; i < 20; i++) [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    return [web stringByEvaluatingJavaScriptFromString:@"matchMedia('(prefers-color-scheme: dark)').matches + ' ' + getComputedStyle(document.documentElement).backgroundColor + ' ' + getComputedStyle(document.body).color"];
}
static void CheckReleaseNotesAppearance(RecordingViewer *viewer) {
    CHECK(viewer.loads > 0 && [viewer.loadedPath isEqual:[[NSBundle mainBundle] pathForResource:@"MessageOfTheDay" ofType:@"html"]], @"Help > Release Notes loads the bundled notes");
    CHECK(viewer.mediaStyle == nil, @"release notes use the default (screen) media type, got %@", viewer.mediaStyle);
    WebView *web = [[[WebView alloc] initWithFrame:NSMakeRect(0, 0, 800, 400)] autorelease];
    web.mediaStyle = viewer.mediaStyle;
    web.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    [web.mainFrame loadRequest:[NSURLRequest requestWithURL:[NSURL fileURLWithPath:viewer.loadedPath]]];
    for (NSUInteger i = 0; i < 300 && web.isLoading; i++) [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    NSString *light = @"false rgb(247, 245, 240) rgb(32, 41, 50)", *dark = @"true rgb(20, 25, 30) rgb(233, 238, 242)";
    NSString *opened = Probe(web);
    CHECK([opened isEqual:dark], @"opened in Dark: %@", opened);
    web.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    NSString *switched = Probe(web);
    CHECK([switched isEqual:light], @"switched to Light while open: %@", switched);
    web.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    NSString *back = Probe(web);
    CHECK([back isEqual:dark], @"switched back to Dark while open: %@", back);
    web.mediaStyle = @"release-notes";
    [web.mainFrame reload];
    for (NSUInteger i = 0; i < 300 && web.isLoading; i++) [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    NSString *legacy = Probe(web);
    CHECK([legacy isEqual:light], @"control: the OmniAppKit release-notes media type ignores Dark (%@)", legacy);
    [web close];
    puts("PASS release notes follow Light/Dark (opened dark, live switches)");
}
static void CheckMessageOfTheDay(AppController *controller) {
    OFPreferenceWrapper *prefs = [OFPreferenceWrapper sharedPreferenceWrapper];
    NSString *domain = [[NSBundle mainBundle] bundleIdentifier];
    NSData *(^persisted)(void) = ^{ return (NSData *)[[NSUserDefaults standardUserDefaults] persistentDomainForName:domain][@"OAMessageOfTheDaySignature"]; };
    NSString *path = [[NSBundle mainBundle] pathForResource:@"MessageOfTheDay" ofType:@"html"];
    NSData *notes = path ? [NSData dataWithContentsOfFile:path] : nil;
    CHECK(notes.length > 0, @"bundled MessageOfTheDay.html present");
    CHECK([prefs boolForKey:@"OAMessageOfTheDayCheckOnLaunch"] && ![prefs boolForKey:@"OAShowMessageOfTheDayOnFirstLaunch"], @"registered: check on launch, never on first launch");
    CHECK([[prefs objectForKey:@"OAMessageOfTheDaySignature"] isEqual:[NSData data]], @"OmniAppKit still registers an empty signature (the reason for the override)");
    RecordingViewer *viewer = [[[RecordingViewer alloc] init] autorelease];
    viewer.mediaStyle = @"unset";
    method_setImplementation(class_getClassMethod([OAWebPageViewer class], @selector(sharedViewerNamed:options:)), imp_implementationWithBlock(^id(id me, NSString *name, OAWebPageViewerOptions options) {
        CHECK([name isEqual:@"Release Notes"] && options == OAWebPageViewerOptionsStandardReleaseNotesOptions, @"release notes viewer %@ options %lu", name, (unsigned long)options);
        return viewer;
    }));

    [prefs removeObjectForKey:@"OAMessageOfTheDaySignature"];
    CHECK(persisted()==nil, @"fresh domain");
    [controller checkMessageOfTheDay];
    CHECK(viewer.loads==0 && [persisted() isEqual:SHA1(notes)], @"first launch shows nothing and records the notes (shown %lu)", (unsigned long)viewer.loads);
    [controller checkMessageOfTheDay];
    CHECK(viewer.loads==0, @"unchanged notes stay hidden");

    [prefs setObject:SHA1([@"older notes" dataUsingEncoding:NSUTF8StringEncoding]) forKey:@"OAMessageOfTheDaySignature"];
    [controller checkMessageOfTheDay];
    CHECK(viewer.loads==1 && [persisted() isEqual:SHA1(notes)], @"changed notes show once after an update (shown %lu)", (unsigned long)viewer.loads);
    [controller checkMessageOfTheDay];
    CHECK(viewer.loads==1, @"and only once");

    [prefs removeObjectForKey:@"OAMessageOfTheDaySignature"];
    [prefs setBool:NO forKey:@"OAMessageOfTheDayCheckOnLaunch"];
    [controller checkMessageOfTheDay];
    CHECK(viewer.loads==1 && persisted()==nil, @"disabling the launch check is respected");
    [prefs removeObjectForKey:@"OAMessageOfTheDayCheckOnLaunch"];

    // The real launch hook on a fresh domain; OAController's own launch work and LinkBack are stubbed.
    method_setImplementation(class_getInstanceMethod([OAController class], @selector(applicationDidFinishLaunching:)), imp_implementationWithBlock(^(id me, NSNotification *note) {}));
    method_setImplementation(class_getClassMethod([LinkBack class], @selector(publishServerWithName:bundleIdentifier:delegate:)), imp_implementationWithBlock(^BOOL(id me, NSString *name, NSString *identifier, id delegate) { return YES; }));
    [controller applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];
    CHECK(viewer.loads==1 && [persisted() isEqual:SHA1(notes)], @"fresh-domain launch shows no release notes");
    [prefs removeObjectForKey:@"OAMessageOfTheDaySignature"];
    puts("PASS message-of-the-day first-launch=hidden changed=once");
    [controller showMessageOfTheDay:nil];
    CheckReleaseNotesAppearance(viewer);
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 3) { fprintf(stderr, "usage: checks BUNDLED_NEWFROM_DIR SCRATCH_DIR\n"); return 2; }
        NSURL *bundled = [NSURL fileURLWithPath:@(argv[1]) isDirectory:YES], *scratch = [NSURL fileURLWithPath:@(argv[2]) isDirectory:YES];
        [[[RSDocumentController alloc] init] autorelease];  // first controller becomes shared, as in main.m
        [[[NSBundle mainBundle] principalClass] sharedApplication];
        AppController *controller = (AppController *)[OFController sharedController];
        CHECK([controller isKindOfClass:[AppController class]], @"production AppController");
        [controller didInitialize];
        Swizzle([NSDocumentController class], @selector(openUntitledCopyOfURL:displayName:ofType:display:error:), @selector(checks_openUntitledCopyOfURL:displayName:ofType:display:error:));
        Swizzle([NSDocument class], @selector(showWindows), @selector(checks_showWindows));
        CheckPolicy();
        CheckCatalog(bundled, scratch);
        CheckInstalledMenu(controller);
        CheckOwnership(scratch);
        CheckFirstLaunch(controller);
        CheckMessageOfTheDay(controller);
        CHECK([controller requestTermination]==OFControllerTerminateNow, @"controller termination");
        [controller willTerminate];
        printf("COMPLETE failures=%lu\n", (unsigned long)Failures);
        return Failures ? 1 : 0;
    }
}
