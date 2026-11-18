// Shared code for the graphink-render and graphink-create command-line tools: process setup, the
// production reader, and the drawing the app's File ▸ Export uses (RSGraphView -drawRect: off screen).
#import <Cocoa/Cocoa.h>
#import <GraphSketcherModel/RSGraph.h>
#import <GraphSketcherModel/RSGraphEditor.h>

// Exit statuses shared by both tools.
enum { GICExitOK = 0, GICExitFailure = 1, GICExitUsage = 2 };

// Raised for any input or output problem; the tools print its reason and exit GICExitFailure.
extern NSString * const GICErrorName;
void GICFail(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);

// Starts OmniFoundation (preferences registered from the tool bundle's Info.plist, which carries the
// app's own OFRegistrations) and registers the bundled style fonts. Call once, before anything else.
void GICStart(void);
void GICStop(void);

// A graph with its own editor and undoer, as GraphDocument holds one. -invalidate releases all three.
@interface GICDocument : NSObject
+ (GICDocument *)documentWithContentsOfFile:(NSString *)path;  // .graphink, .ograph, legacy XML or ZIP
+ (GICDocument *)newDocument;  // an empty graph, set up as File ▸ New does
@property(nonatomic, readonly) RSGraph *graph;
@property(nonatomic, readonly) RSGraphEditor *editor;
@property(nonatomic, readonly) NSInteger encoding;  // RSGraphArchiveEncoding of a document read from a file
- (void)layOut;  // the layout pass a graph view runs before it draws (whitespace, axis and owned labels)
- (void)invalidate;
@end

// Export, as RSGraphView does it: background and every element, never selection or tool feedback.
NSData *GICPDFData(GICDocument *document);
// pixels = round(points * dpi / 72), like the app's raster export; the image records the dpi.
NSData *GICRasterData(GICDocument *document, CGFloat dpi, NSString *typeIdentifier);
CGSize GICRasterPixelSize(CGSize points, CGFloat dpi);

// Writes without replacing an existing file unless overwrite is YES; never writes over input.
void GICWrite(NSData *data, NSString *path, BOOL overwrite, NSString *input);
