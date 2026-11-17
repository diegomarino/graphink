// Offscreen production paper-preset, page undo/save and export checks. No application delegate or launch loop.
#import "GraphDocument.h"
#import "GraphWindowController.h"
#import "RSGraphView.h"
#import "RSInspectorSidebar.h"
#import "RSPageGeometry.h"
#import "Inspectors/DocumentInspector.h"
#import <GraphSketcherModel/RSGraphEditor.h>
#import <GraphSketcherModel/RSUndoer.h>
#import <OmniFoundation/OFController.h>
#import <OmniInspector/OIInspectorController.h>
#import <OmniInspector/OIInspectorTabController.h>
#import <ImageIO/ImageIO.h>

@interface GraphWindowController (PageSizeChecks)
- (void)installInspectorSidebar;
- (void)updateWindowSize;
@end
@interface FixtureGraphView : RSGraphView
- (void)useDocument:(GraphDocument *)document;
@end
@implementation FixtureGraphView
- (void)useDocument:(GraphDocument *)document { _document = document; }
@end
@interface PageWindowController : GraphWindowController
- (void)prepare;
@property(readonly) NSPopUpButton *zoom;
@end
@implementation PageWindowController
- (NSPopUpButton *)zoom { return _viewportZoom; }
- (void)prepare {
    GraphDocument *document = self.document;
    _graph = [document.graph retain];
    FixtureGraphView *view = [[[FixtureGraphView alloc] initWithFrame:NSMakeRect(0, 20, 520, 420)] autorelease];
    [view useDocument:document];
    _graphView = view;
    document.graphView = view;
    [view setRSSelector:document.selectorObject];
    [self.window.contentView addSubview:view];
    [self installInspectorSidebar];
    [self updateWindowSize];
    view.editor = document.editor;
    [_graph addObserver:self forKeyPath:@"canvasSize" options:0 context:NULL];
    [_graph addObserver:self forKeyPath:@"whitespace" options:0 context:NULL];
    [document addObserver:self forKeyPath:@"graph" options:0 context:NULL];
    self.window.delegate = (id)self;
}
@end

// The second document reports Retina backing; raster export must not inherit it.
@interface RetinaWindow : NSWindow
@end
@implementation RetinaWindow
- (CGFloat)backingScaleFactor { return 2; }
@end

static void Check(BOOL condition, NSString *message) {
    if (!condition) [NSException raise:@"PageSizeCheckFailure" format:@"%@", message];
}
static void Drain(void) {
    __block BOOL finished = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ finished = YES; });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (!finished && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:deadline];
    Check(finished, @"Main queue did not drain");
}
static BOOL SameSize(CGSize a, CGSize b) { return fabs(a.width - b.width) < 0.01 && fabs(a.height - b.height) < 0.01; }

// Independent expectations: ISO/ANSI millimeters, and pixels = round(points * dpi / 72).
typedef struct { RSPaperPreset preset; CGFloat width, height, widthMM, heightMM; NSUInteger pixels[4][2]; } PaperExpectation;
static const PaperExpectation Papers[] = {
    {RSPaperPresetA4, 595, 842, 210, 297, {{595, 842}, {1190, 1684}, {1240, 1754}, {2479, 3508}}},
    {RSPaperPresetA5, 420, 595, 148, 210, {{420, 595}, {840, 1190}, {875, 1240}, {1750, 2479}}},
    {RSPaperPresetUSLetter, 612, 792, 215.9, 279.4, {{612, 792}, {1224, 1584}, {1275, 1650}, {2550, 3300}}},
    {RSPaperPresetCustom, 500, 300, 176.4, 105.8, {{500, 300}, {1000, 600}, {1042, 625}, {2083, 1250}}},
};
static const CGFloat Resolutions[] = {72, 144, 150, 300};

static void CheckGeometry(void) {
    Check([RSRasterExportResolutions() isEqual:(@[@72, @144, @150, @300])] && RSDefaultRasterExportResolution == 144, @"Raster resolution choices/default differ from the agreed list");
    Check([RSPaperPresets() isEqual:(@[@(RSPaperPresetA4), @(RSPaperPresetA5), @(RSPaperPresetUSLetter)])], @"Preset list differs from A4/A5/US Letter");
    for (NSUInteger index = 0; index < 4; index++) {
        PaperExpectation paper = Papers[index];
        CGSize portrait = CGSizeMake(paper.width, paper.height), landscape = CGSizeMake(paper.height, paper.width);
        if (paper.preset != RSPaperPresetCustom) {
            Check(SameSize(RSPaperPresetSize(paper.preset, RSPaperOrientationPortrait), portrait) && SameSize(RSPaperPresetSize(paper.preset, RSPaperOrientationLandscape), landscape), @"Preset point geometry is wrong");
            Check(RSPaperPresetForSize(portrait) == paper.preset && RSPaperPresetForSize(landscape) == paper.preset, @"Preset not recognized from its canvas size");
            Check(RSPaperPresetForSize(CGSizeMake((float)paper.width, (float)paper.height)) == paper.preset, @"Preset not recognized after single-precision save");
            Check(RSPaperPresetForSize(CGSizeMake(paper.width + 1, paper.height)) == RSPaperPresetCustom, @"Near-preset size was not Custom");
        } else {
            Check(RSPaperPresetForSize(portrait) == RSPaperPresetCustom, @"Custom size matched a preset");
        }
        Check(RSPaperOrientationForSize(portrait) == (paper.width > paper.height ? RSPaperOrientationLandscape : RSPaperOrientationPortrait) && RSPaperOrientationForSize(landscape) == (paper.height > paper.width ? RSPaperOrientationLandscape : RSPaperOrientationPortrait), @"Orientation derivation is wrong");
        CGFloat widthMM = paper.width / 72 * 25.4, heightMM = paper.height / 72 * 25.4;
        Check(fabs(widthMM - paper.widthMM) < 0.25 && fabs(heightMM - paper.heightMM) < 0.25, @"Preset physical size is not within 0.25 mm of the paper standard");
        NSString *physical = RSPhysicalSizeDescription(portrait);
        Check([physical hasPrefix:[NSString stringWithFormat:@"%.1f × %.1f mm", widthMM, heightMM]], @"Physical size description is wrong");
        for (NSUInteger dpi = 0; dpi < 4; dpi++) {
            NSSize pixels = RSRasterPixelSize(portrait, Resolutions[dpi]);
            Check(pixels.width == paper.pixels[dpi][0] && pixels.height == paper.pixels[dpi][1], [NSString stringWithFormat:@"Pixel size for %@ at %.0f DPI is %@", RSPaperPresetName(paper.preset), Resolutions[dpi], NSStringFromSize(pixels)]);
        }
    }
    Check(NSEqualSizes(RSRasterPixelSize(CGSizeMake(0.2, 0.2), 72), NSMakeSize(1, 1)), @"Tiny canvas produced an empty raster");
    RSRasterExportAccessory *accessory = [[[RSRasterExportAccessory alloc] initWithCanvasSize:CGSizeMake(595, 842)] autorelease];
    Check(accessory.resolution == 144 && accessory.resolutionPopUp.numberOfItems == 4, @"Raster export accessory does not default to 144 DPI");
    Check([accessory.pixelSizeLabel.stringValue isEqual:@"1190 × 1684 px at 144 DPI"], accessory.pixelSizeLabel.stringValue);
    [accessory.resolutionPopUp selectItemWithTag:300];
    [accessory.resolutionPopUp sendAction:accessory.resolutionPopUp.action to:accessory.resolutionPopUp.target];
    Check(accessory.resolution == 300 && [accessory.pixelSizeLabel.stringValue isEqual:@"2479 × 3508 px at 300 DPI"], accessory.pixelSizeLabel.stringValue);
    NSLog(@"PASS preset geometry, physical sizes, raster pixel table and export accessory");
}

static DocumentInspector *CanvasInspector(PageWindowController *owner) {
    RSInspectorSidebar *sidebar = (id)owner.inspectorRegistry.controllers.firstObject.inspector;
    DocumentInspector *inspector = (id)[sidebar tabWithIdentifier:@"com.graphsketcher.GraphSketcher.inspector.document"].inspector;
    Check([inspector isKindOfClass:DocumentInspector.class], @"Window has no production Canvas inspector");
    // Show the Canvas section as a click on its sidebar tab would; this loads the production nib.
    for (NSUInteger section = 0; inspector.view.window != owner.window && section < 4; section++)
        [sidebar selectSection:section];
    Check(inspector.view.window == owner.window, @"Canvas inspector section is not shown in its document window");
    Check([inspector.paperPresetPopUp isKindOfClass:NSPopUpButton.class] && [inspector.paperOrientationPopUp isKindOfClass:NSPopUpButton.class] && [inspector.physicalSizeLabel isKindOfClass:NSTextField.class], @"Canvas inspector nib lacks paper preset controls");
    return inspector;
}
static void Choose(DocumentInspector *inspector, NSPopUpButton *popUp, NSInteger tag) {
    Check([popUp selectItemWithTag:tag], @"Missing popup item");
    Check([popUp.selectedItem isEnabled], @"Chosen popup item is disabled");
    [NSApp sendAction:popUp.action to:popUp.target from:popUp];
    Check(popUp.target == inspector && popUp.action == @selector(changePaperPreset:), @"Paper popup is not wired to the Canvas inspector");
    Drain(); // Each click is its own event, so the undo manager closes its group.
}
static void CheckShown(DocumentInspector *inspector, GraphDocument *document, RSPaperPreset preset, RSPaperOrientation orientation) {
    CGSize size = document.graph.canvasSize;
    Check([inspector.paperPresetPopUp selectedTag] == preset && [inspector.paperOrientationPopUp selectedTag] == orientation, [NSString stringWithFormat:@"Inspector shows %@/%ld for %@", [inspector.paperPresetPopUp titleOfSelectedItem], (long)[inspector.paperOrientationPopUp selectedTag], NSStringFromSize(size)]);
    Check([inspector.canvasWidth floatValue] == (float)size.width && [inspector.canvasHeight floatValue] == (float)size.height, @"Canvas fields disagree with the page");
    Check([[inspector.physicalSizeLabel stringValue] isEqual:RSPhysicalSizeDescription(size)], @"Physical size label disagrees with the page");
}
static CGSize SaveAndReopen(GraphDocument *document, NSString *path) {
    NSError *error = nil;
    Check([document writeToURL:[NSURL fileURLWithPath:path] ofType:RSGraphFileType error:&error], error.description);
    GraphDocument *reopened = [[[GraphDocument alloc] init] autorelease];
    Check([reopened readFromURL:[NSURL fileURLWithPath:path] ofType:RSGraphFileType error:&error], error.description);
    return reopened.graph.canvasSize;
}

static NSDictionary *ImageProperties(NSData *data, CGImageRef *outImage) {
    CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef)data, NULL);
    Check(source != NULL && CGImageSourceGetCount(source) == 1, @"Raster export is not a single image");
    NSDictionary *properties = [(NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, 0, NULL) autorelease];
    if (outImage) *outImage = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
    return properties;
}
static void CheckRaster(RSGraphView *view, CGSize page, const NSUInteger pixels[4][2], NSString *name) {
    for (NSUInteger dpi = 0; dpi < 4; dpi++) {
        for (NSNumber *type in @[@(NSBitmapImageFileTypePNG), @(NSBitmapImageFileTypeJPEG)]) {
            [view setDrawingToScreen:NO];
            NSData *data = [view rasterDataOfType:(NSBitmapImageFileType)type.unsignedIntegerValue resolution:Resolutions[dpi]];
            [view setDrawingToScreen:YES];
            Check(data.length > 0, @"Raster export produced no data");
            CGImageRef image = NULL;
            NSDictionary *properties = ImageProperties(data, &image);
            NSUInteger width = CGImageGetWidth(image), height = CGImageGetHeight(image);
            Check(width == pixels[dpi][0] && height == pixels[dpi][1], [NSString stringWithFormat:@"%@ %@ at %.0f DPI exported %lux%lu", name, type, Resolutions[dpi], (unsigned long)width, (unsigned long)height]);
            Check([[properties[(id)kCGImagePropertyPixelWidth] description] isEqual:[@(width) description]], @"Raster metadata pixel width disagrees");
            Check(fabs([properties[(id)kCGImagePropertyDPIWidth] doubleValue] - Resolutions[dpi]) < 0.5 && fabs([properties[(id)kCGImagePropertyDPIHeight] doubleValue] - Resolutions[dpi]) < 0.5, [NSString stringWithFormat:@"%@ raster metadata records %@ DPI, expected %.0f", name, properties[(id)kCGImagePropertyDPIWidth], Resolutions[dpi]]);
            if (dpi == 1) {
                // The page drawing actually reached the bitmap: the axes differ from the background.
                NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithCGImage:image] autorelease];
                NSMutableSet *colors = [NSMutableSet set];
                for (NSUInteger y = 0; y < height; y += 7)
                    for (NSUInteger x = 0; x < width; x += 7) [colors addObject:[[rep colorAtX:(NSInteger)x y:(NSInteger)y] description]];
                Check(colors.count > 1, @"Raster export is blank");
            }
            CGImageRelease(image);
        }
    }
    // PDF/EPS: vector page equal to the paper size, with text kept as text.
    NSData *pdf = [view dataWithPDFInsideRect:view.bounds];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)pdf);
    CGPDFDocumentRef document = CGPDFDocumentCreateWithProvider(provider);
    CGDataProviderRelease(provider);
    Check(document && CGPDFDocumentGetNumberOfPages(document) == 1, @"PDF export is not one page");
    CGPDFPageRef pdfPage = CGPDFDocumentGetPage(document, 1);
    CGRect media = CGPDFPageGetBoxRect(pdfPage, kCGPDFMediaBox);
    Check(SameSize(media.size, page), [NSString stringWithFormat:@"%@ PDF page is %@, expected %@", name, NSStringFromSize(media.size), NSStringFromSize(page)]);
    CGPDFDictionaryRef resources = NULL, fonts = NULL, xobjects = NULL;
    Check(CGPDFDictionaryGetDictionary(CGPDFPageGetDictionary(pdfPage), "Resources", &resources) && CGPDFDictionaryGetDictionary(resources, "Font", &fonts) && CGPDFDictionaryGetCount(fonts) > 0, @"PDF export lost vector text fonts");
    if (CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects)) {
        CGPDFDictionaryApplyBlock(xobjects, ^bool(const char *key, CGPDFObjectRef value, void *info) {
            CGPDFStreamRef stream = NULL; const char *subtype = NULL;
            if (CGPDFObjectGetValue(value, kCGPDFObjectTypeStream, &stream))
                Check(!(CGPDFDictionaryGetName(CGPDFStreamGetDictionary(stream), "Subtype", &subtype) && strcmp(subtype, "Image") == 0), @"PDF export rasterized the page");
            return true;
        }, NULL);
    }
    CGPDFDocumentRelease(document);
    NSString *eps = [[[NSString alloc] initWithData:[view dataWithEPSInsideRect:view.bounds] encoding:NSISOLatin1StringEncoding] autorelease];
    NSString *box = [NSString stringWithFormat:@"%%%%BoundingBox: 0 0 %.0f %.0f", page.width, page.height];
    Check([eps rangeOfString:box].location != NSNotFound, [NSString stringWithFormat:@"%@ EPS bounding box is not %@", name, box]);
    NSLog(@"PASS %@ %@ pt: PNG/JPEG pixels and DPI at 72/144/150/300, vector PDF page and EPS box", name, NSStringFromSize(page));
}

int main(int argc, const char *argv[]) {
    @autoreleasepool { @try {
        Check(argc >= 2, @"Pass an owned output directory");
        [NSApplication sharedApplication];
        Check([NSBundle.mainBundle.bundleIdentifier hasPrefix:@"com.graphink.pagesizechecks."], @"Unique fixture domain required");
        NSString *domain = NSBundle.mainBundle.bundleIdentifier;
        CFPreferencesSetAppValue(CFSTR("PageSizeIsolationProbe"), (CFStringRef)domain, kCFPreferencesCurrentApplication);
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
        id probe = [(id)CFPreferencesCopyAppValue(CFSTR("PageSizeIsolationProbe"), (CFStringRef)domain) autorelease];
        Check([probe isEqual:domain], @"Current-application defaults did not route to the unique fixture domain");
        NSLog(@"Preference routing verified: %@", domain);
        OFController *lifecycle = OFController.sharedController;
        [lifecycle didInitialize]; [lifecycle startedRunning];
        Check(NSApp.delegate == nil, @"Fixture must not install the application delegate");
        [NSUserDefaults.standardUserDefaults registerDefaults:@{@"SnapToGrid": @NO, @"UseStickyTools": @YES}];
        NSString *output = @(argv[1]);

        CheckGeometry();

        NSMutableArray *controllers = [NSMutableArray array];
        NSMutableArray *inspectors = [NSMutableArray array];
        for (NSUInteger index = 0; index < 2; index++) {
            NSError *error = nil;
            GraphDocument *document = [[[GraphDocument alloc] initWithType:RSGraphFileType error:&error] autorelease];
            Check(document != nil, error.description);
            NSWindow *window = [[(index ? RetinaWindow.class : NSWindow.class) alloc] initWithContentRect:NSMakeRect(0, 0, 800, 440) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
            [window autorelease];
            PageWindowController *owner = [[[PageWindowController alloc] initWithWindow:window] autorelease];
            [document addWindowController:owner];
            [controllers addObject:owner];
            [owner prepare];
            DocumentInspector *inspector = CanvasInspector(owner);
            [inspector inspectObjects:@[document]];
            [inspectors addObject:inspector];
            Drain();
            [document.undoer endRepetitiveUndo];
            [document.undoManager removeAllActions];
            [document updateChangeCount:NSChangeCleared];
        }
        Check(inspectors[0] != inspectors[1], @"Documents share a Canvas inspector");

        PageWindowController *ownerA = controllers[0], *ownerB = controllers[1];
        GraphDocument *a = ownerA.document, *b = ownerB.document;
        DocumentInspector *inspectorA = inspectors[0], *inspectorB = inspectors[1];
        CGSize original = a.graph.canvasSize;
        Check(RSPaperPresetForSize(original) == RSPaperPresetCustom, @"Default canvas unexpectedly matches a preset");
        CheckShown(inspectorA, a, RSPaperPresetCustom, RSPaperOrientationForSize(original));
        Check(![[inspectorA.paperPresetPopUp itemAtIndex:[inspectorA.paperPresetPopUp indexOfItemWithTag:RSPaperPresetCustom]] isEnabled], @"Custom should be a state, not a choosable size");

        // Preset choice: one undo step that changes only the page size.
        RSBorder whitespace = a.graph.whitespace;
        NSColor *background = a.graph.backgroundColor;
        Choose(inspectorA, inspectorA.paperOrientationPopUp, RSPaperOrientationPortrait);
        CGSize portraitCustom = a.graph.canvasSize;
        Check(SameSize(portraitCustom, CGSizeMake(MIN(original.width, original.height), MAX(original.width, original.height))), [NSString stringWithFormat:@"Orientation did not swap a Custom page: %@ -> %@", NSStringFromSize(original), NSStringFromSize(portraitCustom)]);
        CheckShown(inspectorA, a, RSPaperPresetCustom, RSPaperOrientationPortrait);
        Choose(inspectorA, inspectorA.paperPresetPopUp, RSPaperPresetA4);
        Drain();
        Check(SameSize(a.graph.canvasSize, CGSizeMake(595, 842)), @"A4 portrait not applied");
        CheckShown(inspectorA, a, RSPaperPresetA4, RSPaperOrientationPortrait);
        Check(NSEqualSizes(a.graphView.bounds.size, a.graph.canvasSize), @"Graph view did not follow the page");
        Check([a.graph.backgroundColor isEqual:background] && (a.graph.autoMaintainsWhitespace || (a.graph.whitespace.left == whitespace.left && a.graph.whitespace.top == whitespace.top)), @"Preset changed more than the page size");
        Check([a.undoManager.undoActionName isEqual:@"Change Paper Size"] && a.isDocumentEdited, @"Preset is not a named undoable document edit");
        Choose(inspectorA, inspectorA.paperOrientationPopUp, RSPaperOrientationLandscape);
        Check(SameSize(a.graph.canvasSize, CGSizeMake(842, 595)), @"A4 landscape not applied");
        CheckShown(inspectorA, a, RSPaperPresetA4, RSPaperOrientationLandscape);
        [a.undoManager undo]; Drain();
        Check(SameSize(a.graph.canvasSize, CGSizeMake(595, 842)), @"Undo did not restore A4 portrait");
        CheckShown(inspectorA, a, RSPaperPresetA4, RSPaperOrientationPortrait);
        [a.undoManager undo]; Drain();
        Check(SameSize(a.graph.canvasSize, portraitCustom), @"Undo did not restore the Custom page");
        CheckShown(inspectorA, a, RSPaperPresetCustom, RSPaperOrientationPortrait);
        [a.undoManager undo]; Drain();
        Check(SameSize(a.graph.canvasSize, original) && NSEqualSizes(a.graphView.bounds.size, original), @"Undo did not restore the original page");
        [a.undoManager redo]; [a.undoManager redo]; [a.undoManager redo]; Drain();
        Check(SameSize(a.graph.canvasSize, CGSizeMake(842, 595)), @"Redo did not reapply A4 landscape");
        CheckShown(inspectorA, a, RSPaperPresetA4, RSPaperOrientationLandscape);
        Choose(inspectorA, inspectorA.paperOrientationPopUp, RSPaperOrientationPortrait);
        NSLog(@"PASS preset/orientation choices, inspector labels, named undo/redo");

        // Window resizing and viewport zoom never rewrite the page.
        [a.undoer endRepetitiveUndo];
        NSError *error = nil;
        NSData *before = [a.graph generateXMLOfType:RSGraphFileType frame:CGRectZero error:&error];
        NSString *undoName = a.undoManager.undoActionName;
        for (NSUInteger step = 0; step < 6; step++) {
            [ownerA.zoom selectItemAtIndex:step]; [ownerA changeViewportZoom:ownerA.zoom];
            [ownerA.window setContentSize:NSMakeSize(500 + step * 90, 200 + step * 70)];
        }
        Drain();
        NSData *after = [a.graph generateXMLOfType:RSGraphFileType frame:CGRectZero error:&error];
        Check([before isEqual:after] && SameSize(a.graph.canvasSize, CGSizeMake(595, 842)) && [a.undoManager.undoActionName isEqual:undoName], @"Window resize or zoom rewrote the page");
        CheckShown(inspectorA, a, RSPaperPresetA4, RSPaperOrientationPortrait);
        NSLog(@"PASS window resize and zoom leave the page, XML and undo history unchanged");

        // Two-document isolation: B's page edits never reach A or A's inspector.
        Choose(inspectorB, inspectorB.paperPresetPopUp, RSPaperPresetA5);
        Drain();
        Check(SameSize(b.graph.canvasSize, CGSizeMake(595, 420)) || SameSize(b.graph.canvasSize, CGSizeMake(420, 595)), @"A5 not applied to the second document");
        Choose(inspectorB, inspectorB.paperOrientationPopUp, RSPaperOrientationPortrait);
        CheckShown(inspectorB, b, RSPaperPresetA5, RSPaperOrientationPortrait);
        Check(SameSize(a.graph.canvasSize, CGSizeMake(595, 842)) && [a.undoManager.undoActionName isEqual:undoName], @"Second document's page edit leaked into the first");
        CheckShown(inspectorA, a, RSPaperPresetA4, RSPaperOrientationPortrait);
        // Custom via the existing fields.
        [inspectorB.canvasWidth setFloatValue:500]; [inspectorB changeCanvasSize:inspectorB.canvasWidth];
        [inspectorB.canvasHeight setFloatValue:300]; [inspectorB changeCanvasSize:inspectorB.canvasHeight];
        Drain();
        Check(SameSize(b.graph.canvasSize, CGSizeMake(500, 300)), @"Custom field edit not applied");
        CheckShown(inspectorB, b, RSPaperPresetCustom, RSPaperOrientationLandscape);
        Check(SameSize(a.graph.canvasSize, CGSizeMake(595, 842)), @"Custom edit leaked into the first document");
        NSLog(@"PASS two-document page isolation and Custom field edits");

        // Save/reopen keeps every preset and orientation, plus Custom.
        NSUInteger saved = 0;
        for (NSNumber *preset in RSPaperPresets()) {
            for (NSInteger orientation = RSPaperOrientationPortrait; orientation <= RSPaperOrientationLandscape; orientation++) {
                Choose(inspectorA, inspectorA.paperOrientationPopUp, orientation);
                Choose(inspectorA, inspectorA.paperPresetPopUp, preset.integerValue);
                CGSize expected = RSPaperPresetSize(preset.intValue, (RSPaperOrientation)orientation);
                Check(SameSize(a.graph.canvasSize, expected), @"Preset/orientation combination not applied");
                CGSize reopened = SaveAndReopen(a, [output stringByAppendingPathComponent:[NSString stringWithFormat:@"page-%@-%ld.graphink", preset, (long)orientation]]);
                Check(SameSize(reopened, expected) && RSPaperPresetForSize(reopened) == preset.intValue && RSPaperOrientationForSize(reopened) == orientation, @"Save/reopen lost the paper preset");
                saved++;
            }
        }
        CGSize reopenedCustom = SaveAndReopen(b, [output stringByAppendingPathComponent:@"page-custom.graphink"]);
        Check(SameSize(reopenedCustom, CGSizeMake(500, 300)) && RSPaperPresetForSize(reopenedCustom) == RSPaperPresetCustom, @"Save/reopen lost the Custom page");
        NSLog(@"PASS save/reopen of %lu preset pages and one Custom page", (unsigned long)saved);

        // Exports: physical paper sizes, independent of zoom and screen backing scale.
        for (NSUInteger index = 0; index < 3; index++) {
            Choose(inspectorA, inspectorA.paperOrientationPopUp, RSPaperOrientationPortrait);
            Choose(inspectorA, inspectorA.paperPresetPopUp, Papers[index].preset);
            Drain();
            CheckRaster(a.graphView, a.graph.canvasSize, Papers[index].pixels, RSPaperPresetName(Papers[index].preset));
        }
        CheckRaster(b.graphView, b.graph.canvasSize, Papers[3].pixels, @"Custom");
        [ownerA.zoom selectItemAtIndex:4]; [ownerA changeViewportZoom:ownerA.zoom]; Drain();
        [a.graphView setDrawingToScreen:NO];
        NSData *zoomed = [a.graphView rasterDataOfType:NSBitmapImageFileTypePNG resolution:144];
        [ownerA.zoom selectItemAtIndex:0]; [ownerA changeViewportZoom:ownerA.zoom]; Drain();
        NSData *unzoomed = [a.graphView rasterDataOfType:NSBitmapImageFileTypePNG resolution:144];
        [a.graphView setDrawingToScreen:YES];
        Check([zoomed isEqual:unzoomed], @"Raster export depends on viewport zoom");
        NSDictionary *tiff = ImageProperties([a.graphView rasterDataOfType:NSBitmapImageFileTypeTIFF resolution:300], NULL);
        Check([tiff[(id)kCGImagePropertyPixelWidth] integerValue] == 2550 && [tiff[(id)kCGImagePropertyPixelHeight] integerValue] == 3300, @"TIFF export ignores the chosen resolution");
        Check(SameSize(a.graph.canvasSize, CGSizeMake(612, 792)) && SameSize(b.graph.canvasSize, CGSizeMake(500, 300)), @"Export changed a page");
        Check(ownerB.window.backingScaleFactor == 2 && ownerB.window.backingScaleFactor != ownerA.window.backingScaleFactor, @"Fixture did not compare backing scales");
        NSLog(@"PASS raster export independent of 400%%/25%% zoom and of backing scale (%.1f and %.1f windows)", ownerA.window.backingScaleFactor, ownerB.window.backingScaleFactor);

        Check(!ownerA.window.visible && !ownerB.window.visible, @"Offscreen fixture showed a window");
        for (PageWindowController *controller in controllers) {
            GraphDocument *document = controller.document;
            [document.undoManager removeAllActions]; [document updateChangeCount:NSChangeCleared];
            [document close];
        }
        Check([lifecycle requestTermination] == OFControllerTerminateNow, @"Fixture lifecycle refused termination");
        [lifecycle willTerminate];
        puts("PASS production paper presets, page undo/save and export resolution; offscreen only");
    } @catch (NSException *exception) {
        NSLog(@"FAIL page size: %@", exception); return 1;
    } }
    return 0;
}
