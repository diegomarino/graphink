#import <GraphSketcherModel/RSGraphEditor.h>

// Arrange ▸ Apply Style Preset is one undoable action that writes ordinary visual properties
// (canvas, axis and grid colors, label font family and color). No preset name is saved, so
// applying again also styles new objects, and an identical reapplication records no edit. Data
// colors change only when their contrast is too low: they are lifted toward the preset ink,
// keeping at least 15% of the source hue and its alpha, to 3:1 for strokes, 4.5:1 for colored text
// and 1.5:1 for fills after compositing onto the canvas. A color that cannot reach its target is
// left unchanged, which keeps reapplication idempotent. Tick numbers stay Helvetica Neue for
// readable decimals; Kalam (bundled, registered for the process only) has one regular face.
//
// Creation defaults (font, line, fill and text colors) live in each OPC document's control part
// and join the preset's undo step; color and font actions in such a document change it, not the
// shared preferences, and missing fields fall back to the preferences. Legacy .ograph and older
// .graphink documents keep their format on Save, so an action that needs local defaults first asks
// for Save As (-requiresCreationDefaultsSaveAs). On a dark canvas new objects adapt insufficient
// default ink to that canvas; explicit color edits, paste, duplicate and import never do.

@class RSGraphRenderer, RSUndoer;
void RSPositionNewLabel(RSGraphRenderer *renderer, RSGraphElement *owner);
void RSRememberTextFormatting(RSGraph *graph, NSAttributedString *before, NSAttributedString *after);
void RSSetLocalCreationValue(RSGraph *graph, NSString *key, id value);
// For repeated panel and slider changes: the value joins the undo step of the series it belongs to
// (registered by the first change, updated silently by repeats until -endRepetitiveUndo).
void RSSetSeriesCreationValue(RSGraph *graph, RSUndoer *undoer, NSString *key, id value);
NSString *RSCreationColorKey(RSGraphElement *element, BOOL fillMode, BOOL textMode);
NSArray *RSStylePresetNames(void);
NSColor *RSStyleCreationColor(NSColor *color, RSGraph *graph, BOOL fill);
// Call only for fresh objects/default acceptance, never existing user color edits.
void RSAcceptStyleCreationDefaults(RSGraphElement *element, BOOL fill);
void RSAdaptNewObjectColor(RSGraphElement *element, BOOL fill);
BOOL RSRegisterStyleFonts(NSBundle *bundle, NSError **error);

@interface RSGraphEditor (RSStylePresets)
// Changes only the documented visual subset; returns NO without registering undo for a no-op.
- (BOOL)applyStylePreset:(NSUInteger)index;
@end
