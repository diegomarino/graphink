#import <AppKit/AppKit.h>

// Bundled examples and templates, listed by Resources/NewFrom/NewFrom.plist.
// Adding a document needs only a file in that folder and a manifest entry.
//
// Every item, and the first-launch Welcome document, opens as an independently owned untitled copy
// (-openUntitledCopyOfURL:...): the original is read through the normal reader into a clean
// document without a file URL, so closing it unchanged never prompts, it never enters Open Recent,
// autosave and Save write OPC, and Save never writes the bundle. AppKit's
// -duplicateDocumentWithContentsOfURL: is not used: its immediate autosave and keep/delete prompts
// are harder to control and to check without a window.
//
// First launch: AppController asks RSInitialExampleActionFor() (pure, so the checks need no GUI)
// from -applicationShouldOpenUntitledFile:, which AppKit calls only when nothing was restored or
// opened. The example is shown once per preference domain (RSInitialExampleShownKey, written
// before the copy opens). The historical GSFirstTimeUser stays registered but is not read:
// anyone who ran GraphSketcher already has it cleared.
extern NSString * const RSNewFromDirectoryName;
extern NSString * const RSNewFromManifestName;
extern NSString * const RSInitialExampleShownKey;

@interface RSNewFromItem : NSObject
@property(nonatomic,readonly) NSString *title;        // localized, user-visible
@property(nonatomic,readonly) NSString *relativePath; // inside the NewFrom folder
@property(nonatomic,readonly) NSString *sha256;       // checked by the automated checks, not at runtime
@property(nonatomic,readonly) NSURL *fileURL;
@end

@interface RSNewFromGroup : NSObject
@property(nonatomic,readonly) NSString *identifier;
@property(nonatomic,readonly) NSString *title;
@property(nonatomic,readonly) NSArray *items; // RSNewFromItem, manifest order; only usable entries
@end

@interface RSNewFromCatalog : NSObject
+ (RSNewFromCatalog *)mainCatalog;
// Returns nil (with an error) only when the manifest is missing or not a usable dictionary.
// Invalid individual entries are logged and skipped.
+ (RSNewFromCatalog *)catalogWithDirectoryURL:(NSURL *)directory error:(NSError **)outError;
@property(nonatomic,readonly) NSURL *directoryURL;
@property(nonatomic,readonly) RSNewFromItem *initialExample;
@property(nonatomic,readonly) NSArray *groups; // RSNewFromGroup, manifest order, including empty groups
@property(nonatomic,readonly) NSArray *skippedEntries; // descriptions of rejected manifest entries

// Replaces the menu's items. Empty groups are omitted; groups are separated by a separator.
// Returns the number of document items added.
- (NSUInteger)populateMenu:(NSMenu *)menu target:(id)target action:(SEL)action;
@end

@interface NSDocumentController (RSNewFromCatalog)
// Opens an independently owned, clean, untitled document read from url. The original is only read.
- (NSDocument *)openUntitledCopyOfURL:(NSURL *)url displayName:(NSString *)name ofType:(NSString *)typeName display:(BOOL)display error:(NSError **)outError;
// File ▸ New From items; sender's representedObject is an RSNewFromItem.
- (IBAction)newDocumentFromCatalogItem:(id)sender;
@end

typedef NS_ENUM(NSInteger, RSInitialExampleHook) {
    RSInitialExampleHookShouldOpenUntitled, // AppKit has nothing restored or opened to show
    RSInitialExampleHookDidFinishLaunching,
};
typedef NS_ENUM(NSInteger, RSInitialExampleAction) {
    RSInitialExampleNone,
    RSInitialExampleOpen,    // mark shown, then open the untitled copy
    RSInitialExampleConsume, // mark shown without opening (documents were restored or opened)
};
RSInitialExampleAction RSInitialExampleActionFor(BOOL shown, RSInitialExampleHook hook, NSUInteger openDocumentCount);
