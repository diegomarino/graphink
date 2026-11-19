// Shared code for the graphink subcommands: process setup, the production reader, and export through
// RSGraphExport, the same functions File ▸ Export uses.
#import <Cocoa/Cocoa.h>
#import <GraphSketcherModel/RSGraph.h>
#import <GraphSketcherModel/RSGraphEditor.h>

// Exit statuses shared by every subcommand.
enum { GICExitOK = 0, GICExitFailure = 1, GICExitUsage = 2 };

// Raised for any input or output problem; the subcommands print its reason and exit GICExitFailure.
extern NSString * const GICErrorName;
void GICFail(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);

// "2026.11.0 (build 12)", from the Info.plist embedded in the executable.
NSString *GICVersion(void);

// Starts OmniFoundation (preferences registered from the embedded Info.plist, which carries the app's
// own OFRegistrations under com.diegomarino.Graphink.cli) and registers the style fonts of the bundle
// that contains the tool. Call once, before anything else.
void GICStart(void);
void GICStop(void);

// The bundle whose Contents/Helpers holds the tool: Graphink.app, or the unpacked graphink-cli.zip.
// Symbolic links to the tool (/usr/local/bin/graphink, Homebrew) are resolved first.
NSString *GICContainingBundlePath(void);

// A graph with its own editor and undoer, as GraphDocument holds one. -invalidate releases all three.
@interface GICDocument : NSObject
+ (GICDocument *)documentWithContentsOfFile:(NSString *)path;  // .graphink, .ograph, legacy XML or ZIP
+ (GICDocument *)emptyDocument;  // an empty graph, set up as File ▸ New does
@property(nonatomic, readonly) RSGraph *graph;
@property(nonatomic, readonly) RSGraphEditor *editor;
@property(nonatomic, readonly) NSInteger encoding;  // RSGraphArchiveEncoding of a document read from a file
- (void)layOut;  // what a graph view does before it draws: bounds = canvas, then -prepareForDisplay
- (void)invalidate;
@end

// Export, laid out first: RSGraphPDFData and RSGraphRasterData over the whole canvas.
NSData *GICPDFData(GICDocument *document);
NSData *GICRasterData(GICDocument *document, CGFloat dpi, NSString *typeIdentifier);

// Writes without replacing an existing file unless overwrite is YES; never writes over input.
void GICWrite(NSData *data, NSString *path, BOOL overwrite, NSString *input);

// The subcommands (argv[0] is the subcommand's name).
int GICRenderMain(int argc, const char *argv[]);
int GICCreateMain(int argc, const char *argv[]);
void GICRenderUsage(FILE *out);
void GICCreateUsage(FILE *out);
