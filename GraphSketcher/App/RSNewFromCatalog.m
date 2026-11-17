#import "RSNewFromCatalog.h"
#import "GraphDocument.h"
#import <GraphSketcherModel/RSGraph.h>

NSString * const RSNewFromDirectoryName = @"NewFrom";
NSString * const RSNewFromManifestName = @"NewFrom.plist";
NSString * const RSInitialExampleShownKey = @"GraphinkInitialExampleShown";

static NSString *RSNewFromTitle(id title)
{
    if (![title isKindOfClass:[NSString class]] || ![title length]) return nil;
    return [[NSBundle mainBundle] localizedStringForKey:title value:title table:@"NewFrom"];
}

@interface RSNewFromItem ()
- (id)initWithEntry:(id)entry directory:(NSURL *)directory reason:(NSString **)reason;
@end

@implementation RSNewFromItem
@synthesize title = _title, relativePath = _relativePath, sha256 = _sha256, fileURL = _fileURL;
- (id)initWithEntry:(id)entry directory:(NSURL *)directory reason:(NSString **)reason;
{
    if (!(self = [super init])) return nil;
    NSString *problem = nil;
    if (![entry isKindOfClass:[NSDictionary class]]) problem = @"entry is not a dictionary";
    else {
        NSSet *known = [NSSet setWithObjects:@"File", @"Title", @"SHA256", nil];
        NSString *path = entry[@"File"];
        if (![[NSSet setWithArray:[entry allKeys]] isSubsetOfSet:known]) problem = @"unknown keys";
        else if (![path isKindOfClass:[NSString class]] || ![path length] || [path isAbsolutePath] || [[path pathComponents] containsObject:@".."]) problem = @"File must be a relative path inside the NewFrom folder";
        else if ([[path pathExtension] caseInsensitiveCompare:@"graphink"] != NSOrderedSame) problem = @"File must be a .graphink document";
        else if (!RSNewFromTitle(entry[@"Title"])) problem = @"missing Title";
        else {
            _relativePath = [path copy];
            _title = [RSNewFromTitle(entry[@"Title"]) copy];
            _sha256 = [entry[@"SHA256"] isKindOfClass:[NSString class]] ? [entry[@"SHA256"] copy] : nil;
            _fileURL = [[directory URLByAppendingPathComponent:path] retain];
            if (![_fileURL checkResourceIsReachableAndReturnError:NULL]) problem = @"file is missing";
        }
    }
    if (problem) {
        if (reason) *reason = [NSString stringWithFormat:@"%@: %@", problem, entry];
        [self release];
        return nil;
    }
    return self;
}
- (void)dealloc;
{
    [_title release]; [_relativePath release]; [_sha256 release]; [_fileURL release];
    [super dealloc];
}
@end

@interface RSNewFromGroup ()
@property(nonatomic,copy) NSString *identifier;
@property(nonatomic,copy) NSString *title;
@property(nonatomic,copy) NSArray *items;
@end

@implementation RSNewFromGroup
@synthesize identifier = _identifier, title = _title, items = _items;
- (void)dealloc;
{
    [_identifier release]; [_title release]; [_items release];
    [super dealloc];
}
@end

@interface RSNewFromCatalog ()
@property(nonatomic,retain) NSURL *directoryURL;
@property(nonatomic,retain) RSNewFromItem *initialExample;
@property(nonatomic,copy) NSArray *groups;
@property(nonatomic,copy) NSArray *skippedEntries;
@end

@implementation RSNewFromCatalog
@synthesize directoryURL = _directoryURL, initialExample = _initialExample, groups = _groups, skippedEntries = _skippedEntries;

+ (RSNewFromCatalog *)mainCatalog;
{
    static RSNewFromCatalog *catalog = nil;
    if (!catalog) {
        NSURL *directory = [[[NSBundle mainBundle] resourceURL] URLByAppendingPathComponent:RSNewFromDirectoryName isDirectory:YES];
        NSError *error = nil;
        catalog = [[self catalogWithDirectoryURL:directory error:&error] retain];
        if (!catalog) NSLog(@"New From catalog unavailable: %@", error);
    }
    return catalog;
}

+ (RSNewFromCatalog *)catalogWithDirectoryURL:(NSURL *)directory error:(NSError **)outError;
{
    NSURL *manifestURL = [directory URLByAppendingPathComponent:RSNewFromManifestName];
    NSDictionary *manifest = [NSDictionary dictionaryWithContentsOfURL:manifestURL];
    if (![manifest isKindOfClass:[NSDictionary class]] || ![manifest[@"FormatVersion"] isEqual:@1]) {
        if (outError) *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:@{NSLocalizedDescriptionKey:@"Missing or unsupported New From manifest", NSURLErrorKey:manifestURL}];
        return nil;
    }
    RSNewFromCatalog *catalog = [[[self alloc] init] autorelease];
    catalog.directoryURL = directory;
    NSMutableArray *skipped = [NSMutableArray array];
    NSString *reason = nil;
    if (manifest[@"InitialExample"]) {
        catalog.initialExample = [[[RSNewFromItem alloc] initWithEntry:manifest[@"InitialExample"] directory:directory reason:&reason] autorelease];
        if (!catalog.initialExample) [skipped addObject:[@"InitialExample " stringByAppendingString:reason ?: @"invalid entry"]];
    }
    NSMutableArray *groups = [NSMutableArray array];
    NSArray *groupEntries = [manifest[@"Groups"] isKindOfClass:[NSArray class]] ? manifest[@"Groups"] : @[];
    for (NSDictionary *groupEntry in groupEntries) {
        NSString *title = [groupEntry isKindOfClass:[NSDictionary class]] ? RSNewFromTitle(groupEntry[@"Title"]) : nil;
        NSArray *itemEntries = title ? groupEntry[@"Items"] : nil;
        if (![itemEntries isKindOfClass:[NSArray class]] || ![groupEntry[@"Identifier"] isKindOfClass:[NSString class]]) {
            [skipped addObject:[NSString stringWithFormat:@"group needs Identifier, Title and Items: %@", groupEntry]];
            continue;
        }
        NSMutableArray *items = [NSMutableArray array];
        for (id entry in itemEntries) {
            RSNewFromItem *item = [[[RSNewFromItem alloc] initWithEntry:entry directory:directory reason:&reason] autorelease];
            if (item) [items addObject:item];
            else [skipped addObject:reason ?: @"invalid entry"];
        }
        RSNewFromGroup *group = [[[RSNewFromGroup alloc] init] autorelease];
        group.identifier = groupEntry[@"Identifier"]; group.title = title; group.items = items;
        [groups addObject:group];
    }
    catalog.groups = groups;
    catalog.skippedEntries = skipped;
    for (NSString *problem in skipped)
        NSLog(@"Skipping New From entry: %@", problem);
    return catalog;
}

- (void)dealloc;
{
    [_directoryURL release]; [_initialExample release]; [_groups release]; [_skippedEntries release];
    [super dealloc];
}

- (NSUInteger)populateMenu:(NSMenu *)menu target:(id)target action:(SEL)action;
{
    [menu removeAllItems];
    NSUInteger count = 0;
    for (RSNewFromGroup *group in _groups) {
        if (![group.items count]) continue;  // no dead headers for groups without documents
        if ([menu numberOfItems]) [menu addItem:[NSMenuItem separatorItem]];
        NSMenuItem *header;
        BOOL nativeHeader = NO;
        if (@available(macOS 14.0, *)) {
            header = [NSMenuItem sectionHeaderWithTitle:group.title];
            nativeHeader = YES;
        } else {
            header = [[[NSMenuItem alloc] initWithTitle:group.title action:NULL keyEquivalent:@""] autorelease];
            [header setEnabled:NO];
        }
        [menu addItem:header];
        for (RSNewFromItem *item in group.items) {
            NSMenuItem *menuItem = [[[NSMenuItem alloc] initWithTitle:item.title action:action keyEquivalent:@""] autorelease];
            [menuItem setTarget:target];
            [menuItem setRepresentedObject:item];
            if (!nativeHeader)
                [menuItem setIndentationLevel:1];
            [menu addItem:menuItem];
            count++;
        }
    }
    return count;
}
@end

@implementation NSDocumentController (RSNewFromCatalog)

- (NSDocument *)openUntitledCopyOfURL:(NSURL *)url displayName:(NSString *)name ofType:(NSString *)typeName display:(BOOL)display error:(NSError **)outError;
{
    // A normal untitled document that only reads the original: no fileURL, so Save always asks where.
    NSDocument *document = [self makeUntitledDocumentOfType:typeName error:outError];
    if (!document || ![document readFromURL:url ofType:typeName error:outError])
        return nil;
    [document updateChangeCount:NSChangeCleared];
    if ([document isKindOfClass:[GraphDocument class]])
        [(GraphDocument *)document setIsCatalogCopy:YES];  // before its window loads

    NSString *displayName = name;
    NSUInteger suffix = 1;
    while ([[[self documents] valueForKey:@"displayName"] containsObject:displayName])
        displayName = [NSString stringWithFormat:@"%@ %lu", name, (unsigned long)++suffix];
    [document setDisplayName:displayName];

    [self addDocument:document];
    if (display) {
        [document makeWindowControllers];
        [document showWindows];
    }
    return document;
}

- (IBAction)newDocumentFromCatalogItem:(id)sender;
{
    RSNewFromItem *item = [sender representedObject];
    if (![item isKindOfClass:[RSNewFromItem class]])
        return;
    NSError *error = nil;
    if (![self openUntitledCopyOfURL:item.fileURL displayName:item.title ofType:RSGraphFileType display:YES error:&error])
        [self presentError:error];
}

@end

RSInitialExampleAction RSInitialExampleActionFor(BOOL shown, RSInitialExampleHook hook, NSUInteger openDocumentCount)
{
    if (shown)
        return RSInitialExampleNone;
    if (hook == RSInitialExampleHookShouldOpenUntitled)
        return RSInitialExampleOpen;
    // Restored or Finder-opened documents use up the first launch without adding the example.
    return openDocumentCount ? RSInitialExampleConsume : RSInitialExampleNone;
}
