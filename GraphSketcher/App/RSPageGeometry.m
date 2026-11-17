#import "RSPageGeometry.h"

const CGFloat RSPointsPerInch = 72;
const CGFloat RSMillimetersPerInch = 25.4;
const CGFloat RSDefaultRasterExportResolution = 144;

NSArray *RSPaperPresets(void)
{
    return @[@(RSPaperPresetA4), @(RSPaperPresetA5), @(RSPaperPresetUSLetter)];
}

NSString *RSPaperPresetName(RSPaperPreset preset)
{
    switch (preset) {
        case RSPaperPresetA4:
            return NSLocalizedString(@"A4", @"Paper size preset");
        case RSPaperPresetA5:
            return NSLocalizedString(@"A5", @"Paper size preset");
        case RSPaperPresetUSLetter:
            return NSLocalizedString(@"US Letter", @"Paper size preset");
        case RSPaperPresetCustom:
            break;
    }
    return NSLocalizedString(@"Custom", @"Paper size preset for any other canvas size");
}

CGSize RSPaperPresetSize(RSPaperPreset preset, RSPaperOrientation orientation)
{
    CGSize portrait = CGSizeZero;
    switch (preset) {
        case RSPaperPresetA4:
            portrait = CGSizeMake(595, 842);
            break;
        case RSPaperPresetA5:
            portrait = CGSizeMake(420, 595);
            break;
        case RSPaperPresetUSLetter:
            portrait = CGSizeMake(612, 792);
            break;
        case RSPaperPresetCustom:
            return CGSizeZero;
    }
    if (orientation == RSPaperOrientationLandscape)
        return CGSizeMake(portrait.height, portrait.width);
    return portrait;
}

RSPaperOrientation RSPaperOrientationForSize(CGSize size)
{
    return size.width > size.height ? RSPaperOrientationLandscape : RSPaperOrientationPortrait;
}

RSPaperPreset RSPaperPresetForSize(CGSize size)
{
    // Saved canvas sizes are single-precision reals; whole-point presets survive exactly.
    for (NSNumber *number in RSPaperPresets()) {
        CGSize presetSize = RSPaperPresetSize([number intValue], RSPaperOrientationForSize(size));
        if (fabs(presetSize.width - size.width) < 0.01 && fabs(presetSize.height - size.height) < 0.01)
            return [number intValue];
    }
    return RSPaperPresetCustom;
}

NSString *RSPhysicalSizeDescription(CGSize points)
{
    CGFloat widthInches = points.width / RSPointsPerInch;
    CGFloat heightInches = points.height / RSPointsPerInch;
    NSString *format = NSLocalizedString(@"%.1f × %.1f mm · %.2f × %.2f in", @"Physical canvas size: millimeters and inches");
    return [NSString stringWithFormat:format, widthInches * RSMillimetersPerInch, heightInches * RSMillimetersPerInch, widthInches, heightInches];
}

NSArray *RSRasterExportResolutions(void)
{
    return @[@72, @144, @150, @300];
}

static CGFloat RSRasterPixelLength(CGFloat points, CGFloat dpi)
{
    return MAX(1, round(points * dpi / RSPointsPerInch));
}

NSSize RSRasterPixelSize(CGSize points, CGFloat dpi)
{
    return NSMakeSize(RSRasterPixelLength(points.width, dpi), RSRasterPixelLength(points.height, dpi));
}

NSString *RSRasterPixelSizeDescription(CGSize points, CGFloat dpi)
{
    NSSize pixels = RSRasterPixelSize(points, dpi);
    NSString *format = NSLocalizedString(@"%.0f × %.0f px at %.0f DPI", @"Raster export final pixel size and resolution");
    return [NSString stringWithFormat:format, pixels.width, pixels.height, dpi];
}


@implementation RSRasterExportAccessory

- (id)initWithCanvasSize:(CGSize)canvasSize;
{
    if (!(self = [super init]))
        return nil;

    _canvasSize = canvasSize;
    _view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, 60)];

    NSTextField *label = [NSTextField labelWithString:NSLocalizedString(@"Resolution:", @"Raster export resolution label")];
    label.frame = NSMakeRect(12, 32, 100, 17);
    label.alignment = NSTextAlignmentRight;
    [_view addSubview:label];

    _resolutionPopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(116, 28, 120, 25) pullsDown:NO];
    for (NSNumber *dpi in RSRasterExportResolutions()) {
        NSString *format = NSLocalizedString(@"%@ DPI", @"Raster export resolution choice");
        [_resolutionPopUp addItemWithTitle:[NSString stringWithFormat:format, dpi]];
        _resolutionPopUp.lastItem.tag = dpi.integerValue;
    }
    [_resolutionPopUp selectItemWithTag:(NSInteger)RSDefaultRasterExportResolution];
    _resolutionPopUp.target = self;
    _resolutionPopUp.action = @selector(changeResolution:);
    [_view addSubview:_resolutionPopUp];

    _pixelSizeLabel = [[NSTextField labelWithString:@""] retain];
    _pixelSizeLabel.frame = NSMakeRect(116, 8, 240, 17);
    _pixelSizeLabel.textColor = [NSColor secondaryLabelColor];
    [_view addSubview:_pixelSizeLabel];

    [self changeResolution:nil];
    return self;
}

- (void)dealloc;
{
    _resolutionPopUp.target = nil;
    [_pixelSizeLabel release];
    [_resolutionPopUp release];
    [_view release];
    [super dealloc];
}

@synthesize view = _view, resolutionPopUp = _resolutionPopUp, pixelSizeLabel = _pixelSizeLabel;

- (CGFloat)resolution;
{
    return (CGFloat)_resolutionPopUp.selectedTag;
}

- (IBAction)changeResolution:(id)sender;
{
    _pixelSizeLabel.stringValue = RSRasterPixelSizeDescription(_canvasSize, self.resolution);
}

@end
