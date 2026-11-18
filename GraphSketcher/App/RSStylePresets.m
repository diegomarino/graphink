#import "RSStylePresets.h"
#import <CoreText/CoreText.h>
#import <GraphSketcherModel/RSGrid.h>
#import <GraphSketcherModel/RSUnknown.h>
#import <GraphSketcherModel/RSFill.h>
#import <GraphSketcherModel/RSConnectLine.h>
#import <GraphSketcherModel/RSGraphRenderer.h>
#import <GraphSketcherModel/RSTextLabel.h>
#import <GraphSketcherModel/RSUndoer.h>

void RSSetLocalCreationValue(RSGraph *graph, NSString *key, id value)
{
    if (!key || !value) return;
    NSMutableDictionary *defaults=[[graph.creationDefaults mutableCopy] autorelease]?:[NSMutableDictionary dictionary];
    defaults[key]=value; graph.creationDefaults=defaults;
}
void RSSetSeriesCreationValue(RSGraph *graph, RSUndoer *undoer, NSString *key, id value)
{
    if (!key || !value) return;
    // Asking for the series must not end the object's own repetitive undo (color panel, slider).
    id object=undoer.undoObject; NSString *action=[[undoer.undoAction retain] autorelease];
    BOOL first=[undoer firstUndoWithObject:graph key:[@"creationDefaults." stringByAppendingString:key]];
    undoer.undoObject=object; undoer.undoAction=action;
    if (first) { RSSetLocalCreationValue(graph,key,value); return; }
    NSUndoManager *manager=graph.undoManager; [manager disableUndoRegistration];
    @try { RSSetLocalCreationValue(graph,key,value); } @finally { [manager enableUndoRegistration]; }
}
NSString *RSCreationColorKey(RSGraphElement *element, BOOL fillMode, BOOL textMode)
{
    if ([element isKindOfClass:RSTextLabel.class]) return @"text-color";
    if ([element isKindOfClass:RSFill.class]) return @"fill-color";
    if ([element isKindOfClass:RSUnknown.class] || !element) return fillMode?@"fill-color":textMode?@"text-color":@"line-color";
    return @"line-color";
}

NSArray *RSStylePresetNames(void) { return @[@"Paper", @"Sketch", @"Chalkboard", @"Studio"]; }

BOOL RSRegisterStyleFonts(NSBundle *bundle, NSError **error)
{
    for (NSString *name in @[@"Kalam-Regular", @"Kalam-Bold"]) {
        NSURL *url = [bundle URLForResource:name withExtension:@"ttf" subdirectory:@"StyleFonts"];
        if (!url) {
            if (error) *error = [NSError errorWithDomain:@"GraphinkStyleFonts" code:1 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Missing bundled font %@", name]}];
            return NO;
        }
        CFErrorRef failure = NULL;
        BOOL result = CTFontManagerRegisterFontsForURL((CFURLRef)url, kCTFontManagerScopeProcess, &failure);
        if (!result && failure && CFErrorGetCode(failure) == kCTFontManagerErrorAlreadyRegistered) result = YES;
        if (!result && error) *error = [[(NSError *)failure retain] autorelease];
        if (failure) CFRelease(failure);
        if (!result) return NO;
    }
    return YES;
}

static NSColor *Ink(unsigned rgb)
{
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 255)/255.0 green:((rgb >> 8) & 255)/255.0 blue:(rgb & 255)/255.0 alpha:1];
}
static CGFloat Linear(CGFloat v) { return v <= 0.04045 ? v/12.92 : pow((v + 0.055)/1.055, 2.4); }
static CGFloat Luminance(NSColor *c) { return 0.2126*Linear(c.redComponent) + 0.7152*Linear(c.greenComponent) + 0.0722*Linear(c.blueComponent); }
static CGFloat Contrast(NSColor *a, NSColor *b)
{
    CGFloat x = Luminance(a), y = Luminance(b);
    return (MAX(x,y)+0.05)/(MIN(x,y)+0.05);
}
static BOOL SameColor(NSColor *a, NSColor *b)
{
    if ([a isEqual:b]) return YES;
    NSColor *x=[a colorUsingColorSpace:NSColorSpace.sRGBColorSpace], *y=[b colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    return x && y && fabs(x.redComponent-y.redComponent)<0.00001 && fabs(x.greenComponent-y.greenComponent)<0.00001 && fabs(x.blueComponent-y.blueComponent)<0.00001 && fabs(x.alphaComponent-y.alphaComponent)<0.00001;
}
static BOOL SameCreationColor(NSColor *a,NSColor *b)
{
    return a==b || (a && b && RSCreationDefaultsEqual(@{@"color":a},@{@"color":b}));
}
void RSRememberTextFormatting(RSGraph *graph, NSAttributedString *before, NSAttributedString *after)
{
    if (!graph.creationDefaults || ![before.string isEqual:after.string]) return;
    for (NSUInteger i=0;i<after.length;i++) {
        NSFont *old=[before attribute:NSFontAttributeName atIndex:i effectiveRange:NULL],*font=[after attribute:NSFontAttributeName atIndex:i effectiveRange:NULL];
        if (font && ![font.fontName isEqual:old.fontName]) { RSSetLocalCreationValue(graph,@"font-name",font.fontName); break; }
    }
    for (NSUInteger i=0;i<after.length;i++) {
        NSColor *old=[before attribute:NSForegroundColorAttributeName atIndex:i effectiveRange:NULL],*color=[after attribute:NSForegroundColorAttributeName atIndex:i effectiveRange:NULL];
        if (color && !SameCreationColor(old,color)) { RSSetLocalCreationValue(graph,@"text-color",color); break; }
    }
}
static BOOL Neutral(NSColor *color)
{
    NSColor *rgb=[color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    return rgb && MAX(rgb.redComponent,MAX(rgb.greenComponent,rgb.blueComponent))-MIN(rgb.redComponent,MIN(rgb.greenComponent,rgb.blueComponent))<0.12;
}
static NSColor *Composite(NSColor *c, NSColor *background)
{
    CGFloat alpha=c.alphaComponent;
    return [NSColor colorWithSRGBRed:c.redComponent*alpha+background.redComponent*(1-alpha)
                             green:c.greenComponent*alpha+background.greenComponent*(1-alpha)
                              blue:c.blueComponent*alpha+background.blueComponent*(1-alpha) alpha:1];
}
// Opacity is intentional: very translucent fills cannot promise stroke-level contrast.
static NSColor *Legible(NSColor *original, NSColor *background, NSColor *ink, CGFloat target)
{
    NSColor *rgb=[original colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!rgb || rgb.alphaComponent==0 || Contrast(Composite(rgb,background),background)>=target-0.001) return original;
    NSColor *limit=[[rgb blendedColorWithFraction:0.85 ofColor:ink] colorWithAlphaComponent:rgb.alphaComponent];
    if (Contrast(Composite(limit,background),background)<target) return original;
    CGFloat low=0,high=0.85; // Retain at least 15% of each source hue, even if opacity limits contrast.
    for (NSUInteger i=0;i<20;i++) {
        CGFloat middle=(low+high)/2;
        NSColor *candidate=[[rgb blendedColorWithFraction:middle ofColor:ink] colorWithAlphaComponent:rgb.alphaComponent];
        if (Contrast(Composite(candidate,background),background)<target) low=middle; else high=middle;
    }
    return [[rgb blendedColorWithFraction:high ofColor:ink] colorWithAlphaComponent:rgb.alphaComponent];
}
NSColor *RSStyleCreationColor(NSColor *color, RSGraph *graph, BOOL fill)
{
    NSColor *background=[graph.backgroundColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!background) return color;
    NSColor *ink=Contrast(Ink(0),background)>Contrast(Ink(0xFFFFFF),background)?Ink(0):Ink(0xFFFFFF);
    // Preserve personalized inks on light canvases; only repair default creation on dark canvases.
    return Luminance(background)<0.18 ? Legible(color,background,ink,fill?1.5:3) : color;
}
void RSAdaptNewObjectColor(RSGraphElement *element, BOOL fill)
{
    RSGraph *graph=element.graph;
    BOOL text=[element isKindOfClass:RSTextLabel.class];
    NSColor *color=graph.creationDefaults[text?@"text-color":fill?@"fill-color":@"line-color"];
    if (!color) color=RSStyleCreationColor(element.color,graph,fill);
    NSString *fontName=text?graph.creationDefaults[@"font-name"]:nil;
    NSUndoManager *undo=element.graph.undoManager;
    [undo disableUndoRegistration];
    @try {
        if (!SameCreationColor(color,element.color)) element.color=color;
        if (fontName) {
            RSTextLabel *label=(RSTextLabel *)element;
            NSMutableAttributedString *value=[[[label attributedString] mutableCopy] autorelease];
            [label.attributedString enumerateAttribute:NSFontAttributeName inRange:NSMakeRange(0,value.length) options:0 usingBlock:^(NSFont *font,NSRange range,BOOL *stop) {
                NSFont *target=[NSFont fontWithName:fontName size:font?font.pointSize:13];
                if (!target) return;
                NSFontManager *manager=[NSFontManager sharedFontManager];
                NSFontTraitMask traits=(font ? [manager traitsOfFont:font] : 0)|[manager traitsOfFont:target];
                NSFont *converted=[manager convertFont:target toHaveTrait:traits];
                if ([manager traitsOfFont:converted]!=traits) converted=font;
                if (converted) [value addAttribute:NSFontAttributeName value:converted range:range];
            }];
            label.attributedString=value;
        }
    } @finally { [undo enableUndoRegistration]; }
}
void RSAcceptStyleCreationDefaults(RSGraphElement *element, BOOL fill)
{
    // Tool preview/default refresh must not create edits for an uncommitted object.
    NSUndoManager *undo=element.graph.undoManager;
    [undo disableUndoRegistration];
    @try {
        [(id)element acceptLatestDefaults];
        RSAdaptNewObjectColor(element,fill);
    } @finally { [undo enableUndoRegistration]; }
}
void RSPositionNewLabel(RSGraphRenderer *renderer, RSGraphElement *owner)
{
    BOOL creating=owner.label==nil;
    [renderer positionLabel:nil forOwner:owner];
    if (creating) RSAdaptNewObjectColor(owner.label, NO);
}
static void Edit(NSMutableArray *edits, id object, NSString *key, id value)
{
    id current=[object valueForKey:key];
    if ([key isEqual:@"creationDefaults"] && RSCreationDefaultsEqual(current,value)) return;
    if ([current isKindOfClass:NSColor.class] && [value isKindOfClass:NSColor.class] && SameColor(current,value)) return;
    if (![current isEqual:value]) [edits addObject:@[object, key, value?:NSNull.null]];
}

// Sketch and Chalkboard use Kalam Regular and Bold (Kalam has no italic); Paper and Studio Helvetica Neue
// and its Medium, the catalog's bold. The model does not tell a title from a note, so free text keeps
// only whether it was emphasized.
NSFont *RSStyleFont(NSUInteger index, RSGraph *graph, RSTextLabel *label, NSFont *font)
{
    NSFontManager *manager = [NSFontManager sharedFontManager];
    BOOL tick = label.isAxisTickLabel || [graph isAxisEndLabel:label];
    BOOL emphasis = !tick && ([graph isAxisTitle:label] || label.owner || (font && ([manager weightOfFont:font] >= 6 || ([manager traitsOfFont:font] & NSBoldFontMask))));
    BOOL italic = font && ([manager traitsOfFont:font] & NSItalicFontMask);
    NSString *name;
    if ((index == 1 || index == 2) && !tick) name = emphasis ? @"Kalam-Bold" : @"Kalam-Regular";
    else name = emphasis ? (italic ? @"HelveticaNeue-MediumItalic" : @"HelveticaNeue-Medium") : (italic ? @"HelveticaNeue-Italic" : @"HelveticaNeue");
    return [NSFont fontWithName:name size:font ? font.pointSize : 13] ?: font;
}

@implementation RSGraphEditor (RSStylePresets)

- (void)restoreStyleProperties:(NSArray *)edits
{
    NSUndoManager *undo = self.graph.undoManager;
    NSMutableArray *inverse = [NSMutableArray array];
    for (NSArray *edit in edits)
        [inverse addObject:@[edit[0], edit[1], [[[edit[0] valueForKey:edit[1]] copy] autorelease]?:NSNull.null]];
    [[undo prepareWithInvocationTarget:self] restoreStyleProperties:inverse];
    [undo disableUndoRegistration];
    @try {
        for (NSArray *edit in edits) [edit[0] setValue:edit[2]==NSNull.null?nil:edit[2] forKey:edit[1]];
    } @finally { [undo enableUndoRegistration]; }
    [self setNeedsDisplay];
}

- (BOOL)applyStylePreset:(NSUInteger)index
{
    if (index >= RSStylePresetNames().count) return NO;
    const unsigned backgrounds[] = {0xFFFFFF, 0xFBF5E9, 0x263330, 0xF8FAFD};
    const unsigned inks[] = {0x30343B, 0x443D35, 0xF3EEDC, 0x24374D};
    const unsigned grids[] = {0xD8DCE2, 0xDDD2BE, 0x56665F, 0xD8E1ED};
    NSColor *background = Ink(backgrounds[index]), *ink = Ink(inks[index]);
    RSGraph *graph = self.graph;
    NSMutableArray *edits = [NSMutableArray array];
    Edit(edits, graph, @"creationDefaults", @{@"font-name":(index==1 || index==2)?@"Kalam-Regular":@"HelveticaNeue",@"line-color":ink,@"fill-color":[ink colorWithAlphaComponent:0.25],@"text-color":ink});
    Edit(edits, graph, @"backgroundColor", background);
    for (RSAxis *axis in @[graph.xAxis, graph.yAxis]) {
        Edit(edits, axis, @"color", ink);
        Edit(edits, axis.grid, @"color", Ink(grids[index]));
    }
    NSMutableSet *labels = [NSMutableSet setWithArray:graph.allLabels];
    [labels addObjectsFromArray:@[graph.xAxis.title, graph.yAxis.title, graph.xAxis.minLabel, graph.xAxis.maxLabel, graph.yAxis.minLabel, graph.yAxis.maxLabel]];
    for (RSTextLabel *label in labels) {
        NSMutableAttributedString *text = [[[label attributedString] mutableCopy] autorelease];
        [label.attributedString enumerateAttribute:NSFontAttributeName inRange:NSMakeRange(0, text.length) options:0 usingBlock:^(NSFont *font, NSRange range, BOOL *stop) {
            NSFont *replacement = RSStyleFont(index, graph, label, font);
            if (replacement && ![replacement isEqual:font]) [text addAttribute:NSFontAttributeName value:replacement range:range];
        }];
        [label.attributedString enumerateAttribute:NSForegroundColorAttributeName inRange:NSMakeRange(0, text.length) options:0 usingBlock:^(NSColor *color, NSRange range, BOOL *stop) {
            BOOL neutral=Neutral(color);
            NSColor *replacement=[graph isAxisLabel:label] || neutral || !color ? [ink colorWithAlphaComponent:color?color.alphaComponent:1] : Legible(color,background,ink,4.5);
            // Finish neutral classification now so the mapped color is a fixed point.
            if (Neutral(replacement)) replacement=[ink colorWithAlphaComponent:replacement.alphaComponent];
            if (!SameColor(color,replacement)) [text addAttribute:NSForegroundColorAttributeName value:replacement range:range];
        }];
        Edit(edits, label, @"attributedString", text);
    }
    for (NSArray *elements in @[graph.Lines, graph.Vertices, graph.Fills])
        for (RSGraphElement *element in elements)
            Edit(edits, element, @"color", Legible(element.color, background, ink, elements==graph.Fills?1.5:3));
    if (!edits.count) return NO;
    [self.undoer endRepetitiveUndo];
    NSUndoManager *undo = graph.undoManager;
    [undo beginUndoGrouping];
    [self restoreStyleProperties:edits];
    [undo setActionName:[NSString stringWithFormat:NSLocalizedString(@"Apply %@ Style", @"Undo style preset"), RSStylePresetNames()[index]]];
    [undo endUndoGrouping];
    [self.undoer endRepetitiveUndo];
    return YES;
}
@end
