// Copyright 2003-2013 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSUserDefaults-OAExtensions.h>
#import "DocumentInspector.h"

#import <GraphSketcherModel/RSGraph.h>
#import <AppKit/NSColor.h>

#import "GraphDocument.h"
#import "RSSelector.h"
#import "RSGraphView.h"
#import "OIInspector-RSExtensions.h"
#import "RSPageGeometry.h"
#import <GraphSketcherModel/RSUndoer.h>

@implementation DocumentInspector

#pragma mark -
#pragma mark Class methods

- (void)updateDisplay;
{
    if (!_graph || !_s || ![_s document]) {
	[_backgroundColorWell setColor:[NSColor whiteColor]];
	[self setCanEditWhitespace:NO];
	
	return;
    }
    
    // Shadow strength is updated with cocoa bindings
    
    // Cocoa bindings caused some havoc with the background color well: <bug://bugs/52797> (Editing Text Just After Changing the Background Color Causes a Black canvas)
    [_backgroundColorWell setColor:[_graph backgroundColor]];
    
    // Automatic margins checkbox is updated with cocoa bindings... to canEditWhitespace
    [self setCanEditWhitespace:![_graph autoMaintainsWhitespace]];
    
    NSSize canvasSize = [_graph canvasSize];
    [_canvasWidth setFloatValue:(float)canvasSize.width];
    [_canvasWidthStepper setFloatValue:(float)canvasSize.width];
    [_canvasHeight setFloatValue:(float)canvasSize.height];
    [_canvasHeightStepper setFloatValue:(float)canvasSize.height];
    
    // The preset is derived from the canvas size; any non-preset size shows Custom.
    [_paperPresetPopUp selectItemWithTag:RSPaperPresetForSize(canvasSize)];
    [_paperOrientationPopUp selectItemWithTag:RSPaperOrientationForSize(canvasSize)];
    [_physicalSizeLabel setStringValue:RSPhysicalSizeDescription(canvasSize)];

    RSBorder whitespace = [_graph whitespace];
    [_marginTop setFloatValue:(float)whitespace.top];
    [_marginRight setFloatValue:(float)whitespace.right];
    [_marginBottom setFloatValue:(float)whitespace.bottom];
    [_marginLeft setFloatValue:(float)whitespace.left];
    
    if (_shadowLabel) {
        if (_graph.tufteEasterEgg) {
            [_shadowLabel setStringValue:@"Chartjunk:"];
        } else {
            [_shadowLabel setStringValue:originalShadowLabelString];
        }
    }
}


#pragma mark -
#pragma mark init/dealloc

- (id)initWithDictionary:(NSDictionary *)dict inspectorRegistry:(OIInspectorRegistry *)inspectorRegistry bundle:(NSBundle *)sourceBundle;
{
    self = [super initWithDictionary:dict inspectorRegistry:inspectorRegistry bundle:sourceBundle];
    if (!self)
        return nil;
    
    _document = nil;
    _s = nil;
    _graph = nil;
    
    return self;
}

- (NSString *)nibName;
{
    return NSStringFromClass([self class]);
}

- (NSBundle *)nibBundle;
{
    return OMNI_BUNDLE;
}

- (void)awakeFromNib;
{
    if (_shadowLabel) {
        originalShadowLabelString = [[_shadowLabel stringValue] retain];
    }
    
    [self updateDisplay];
}


#pragma mark -
#pragma mark OIConcreteInspector protocol

- (NSPredicate *)inspectedObjectsPredicate;
// Return a predicate to filter the inspected objects down to what this inspector wants sent to its -inspectObjects: method
{
    static NSPredicate *predicate = nil;
    if (!predicate)
	predicate = [[NSComparisonPredicate isKindOfClassPredicate:[GraphDocument class]] retain];
    return predicate;
}

- (void)inspectObjects:(NSArray *)objects;
// This method is called whenever the selection changes
{
    GraphDocument *newDocument = nil;
    
    for (id obj in objects) {
	if ([obj isKindOfClass:[GraphDocument class]]) {
	    newDocument = obj;
	    break;
	}
    }
    
    // The graph can change on "revert to saved", even if the document is the same.
    RSGraph *newGraph = [newDocument graph];
    if (newGraph == _graph)
        return;
    
    if (_graph) {
	// stop observing changes to the old graph
	[_graph removeObserver:self forKeyPath:@"canvasSize"];
	[_graph removeObserver:self forKeyPath:@"whitespace"];
	[_graph removeObserver:self forKeyPath:@"autoMaintainsWhitespace"];
	[_graph removeObserver:self forKeyPath:@"tufteEasterEgg"];
    }
    
    [self setDocument:newDocument];
    _s = [[self document] selectorObject];
    _graph = newGraph;
    
    if (newGraph) {
	// start observing changes to the new graph
	[_graph addObserver:self forKeyPath:@"canvasSize" options:NSKeyValueObservingOptionNew context:NULL];
	[_graph addObserver:self forKeyPath:@"whitespace" options:NSKeyValueObservingOptionNew context:NULL];
	[_graph addObserver:self forKeyPath:@"autoMaintainsWhitespace" options:NSKeyValueObservingOptionNew context:NULL];
	[_graph addObserver:self forKeyPath:@"tufteEasterEgg" options:NSKeyValueObservingOptionNew context:NULL];
    }
    
    [self updateDisplay];
}


#pragma mark -
#pragma mark KVO (instead of cocoa bindings)

+ (NSSet *)keyPathsForValuesAffectingDocumentExists;
// "documentExists" is the key that depends on other key paths
{
    return [NSSet setWithObject:@"document"];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
		      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context;
{
    // for now we'll take the brute-force approach of just updating the entire display
    [self updateDisplay];
}


#pragma mark -
#pragma mark Accessors

@synthesize document = _document;

- (BOOL)documentExists;
{
    return [self document] != nil;
}

@synthesize canEditWhitespace = _canEditWhitespace;


#pragma mark -
#pragma mark IBActions


- (IBAction)changeShadowStrength:(id)sender;
{
    //? Set user preference:
    
    // do the deed:
    [_graph setShadowStrength:[sender floatValue]];
    [self updateDisplay];
}

- (IBAction)changeBackgroundColor:(id)sender;
// called when color well updated
{
    if (![self commitEditingForDocument:_document]) {
        [_backgroundColorWell deactivate];
        return;
    }
        
    
    NSColor *newColor = [sender color];
    
    // set user preference:
    //[[OFPreferenceWrapper sharedPreferenceWrapper] setColor:newColor forKey: @"DefaultBackgroundColor"];
    
    [_graph setBackgroundColor:newColor];
    [self updateDisplay];
}


- (IBAction)changeCanvasSize:(id)sender;
{
    NSSize canvasSize = [_graph canvasSize];
    
    if (sender == _canvasWidth || sender == _canvasWidthStepper) {
	canvasSize.width = [sender floatValue];
    }
    else if (sender == _canvasHeight || sender == _canvasHeightStepper) {
	canvasSize.height = [sender floatValue];
    }
    
    [_document.editor setCanvasSize:canvasSize];
    [self updateDisplay];
}

- (IBAction)changePaperPreset:(id)sender;
// Presets and orientation change only the canvas size, as one undoable step.
{
    if (![self commitEditingForDocument:_document]) {
        [self updateDisplay];
        return;
    }

    CGSize canvasSize = [_graph canvasSize];
    RSPaperOrientation orientation = (RSPaperOrientation)[_paperOrientationPopUp selectedTag];

    if (sender == _paperOrientationPopUp) {
        if (orientation != RSPaperOrientationForSize(canvasSize))
            canvasSize = CGSizeMake(canvasSize.height, canvasSize.width);
    }
    else {
        RSPaperPreset preset = (RSPaperPreset)[_paperPresetPopUp selectedTag];
        if (preset != RSPaperPresetCustom)
            canvasSize = RSPaperPresetSize(preset, orientation);
    }

    if (!CGSizeEqualToSize(canvasSize, [_graph canvasSize])) {
        RSUndoer *undoer = [_document.editor undoer];
        [undoer endRepetitiveUndo];
        [_document.editor setCanvasSize:canvasSize];
        [undoer setActionName:NSLocalizedStringFromTable(@"Change Paper Size", @"UndoActions", @"Undo action name")];
        [undoer endRepetitiveUndo];
    }
    [self updateDisplay];
}

- (IBAction)changeMarginBorder:(id)sender;
{
    RSBorder whitespace = [_graph whitespace];
    NSSize expandSize = [_graph potentialWhitespaceExpansionSize];
    CGFloat max = 0;
    CGFloat newBorder = [sender floatValue];
    
    if (sender == _marginTop) {
	max = whitespace.top + expandSize.height;
	if (newBorder > max)  newBorder = max;
	whitespace.top = newBorder;
    }
    else if (sender == _marginRight) {
	max = whitespace.right + expandSize.width;
	if (newBorder > max)  newBorder = max;
	whitespace.right = newBorder;
    }
    if (sender == _marginBottom) {
	max = whitespace.bottom + expandSize.height;
	if (newBorder > max)  newBorder = max;
	whitespace.bottom = newBorder;
    }
    if (sender == _marginLeft) {
	max = whitespace.left + expandSize.width;
	if (newBorder > max)  newBorder = max;
	whitespace.left = newBorder;
    }
    
    [_graph setWhitespace:whitespace];
    [self updateDisplay];
}

- (IBAction)changeWindowTranslucency:(id)sender;
{
    [_document setWindowOpacity:[sender floatValue]];
}


@end
