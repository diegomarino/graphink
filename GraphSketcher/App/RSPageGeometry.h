#import <AppKit/AppKit.h>

// Page and export geometry.
//
// Document canvas sizes are stored in logical units that are PostScript points:
// 72 points per inch, 25.4 millimeters per inch. The canvas size is the page size.
//
//   inches      = points / 72
//   millimeters = points / 72 * 25.4
//   pixels      = round(points * dpi / 72), at least 1 (raster export only)
//
// Paper presets use the conventional whole-point PostScript sizes, so they are
// stored, displayed (the canvas fields show whole points) and exported exactly:
// A4 595 x 842 pt (209.9 x 297.0 mm), A5 420 x 595 pt (148.2 x 209.9 mm) and
// US Letter 612 x 792 pt (8.5 x 11 in). A preset is not stored separately: it is
// derived from the canvas size, so undo/redo and save/reopen carry it with the
// canvas. Any other size is Custom. Orientation is landscape when width > height.
//
// PDF and EPS exports are vector pages whose size is the canvas size in points;
// they have no resolution. PNG, JPEG and TIFF exports are rendered offscreen at
// the chosen resolution, independent of screen backing scale and viewport zoom,
// and record that resolution in the image metadata.

typedef enum {
    RSPaperPresetCustom = 0,
    RSPaperPresetA4 = 1,
    RSPaperPresetA5 = 2,
    RSPaperPresetUSLetter = 3,
} RSPaperPreset;

typedef enum {
    RSPaperOrientationPortrait = 0,
    RSPaperOrientationLandscape = 1,
} RSPaperOrientation;

extern const CGFloat RSPointsPerInch;
extern const CGFloat RSMillimetersPerInch;
extern const CGFloat RSDefaultRasterExportResolution;

NSArray *RSPaperPresets(void); // NSNumber RSPaperPreset values, excluding Custom
NSString *RSPaperPresetName(RSPaperPreset preset);
CGSize RSPaperPresetSize(RSPaperPreset preset, RSPaperOrientation orientation); // CGSizeZero for Custom
RSPaperOrientation RSPaperOrientationForSize(CGSize size);
RSPaperPreset RSPaperPresetForSize(CGSize size); // Custom unless exactly a preset in either orientation
NSString *RSPhysicalSizeDescription(CGSize points); // "209.9 × 297.0 mm · 8.26 × 11.69 in"

NSArray *RSRasterExportResolutions(void); // NSNumber DPI choices: 72, 144, 150, 300
NSSize RSRasterPixelSize(CGSize points, CGFloat dpi);
NSString *RSRasterPixelSizeDescription(CGSize points, CGFloat dpi); // "1190 × 1684 px at 144 DPI"

// Save-panel accessory for raster exports: resolution choice and final pixel size.
@interface RSRasterExportAccessory : NSObject
{
@private
    CGSize _canvasSize;
    NSView *_view;
    NSPopUpButton *_resolutionPopUp;
    NSTextField *_pixelSizeLabel;
}
- (id)initWithCanvasSize:(CGSize)canvasSize;
@property (readonly) NSView *view;
@property (readonly) NSPopUpButton *resolutionPopUp;
@property (readonly) NSTextField *pixelSizeLabel;
@property (readonly) CGFloat resolution;
- (IBAction)changeResolution:(id)sender;
@end
