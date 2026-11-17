#import <OmniInspector/OIInspector.h>
#import <OmniInspector/OIInspectorRegistry.h>
#import <OmniInspector/OIInspectorTabController.h>

NS_ASSUME_NONNULL_BEGIN

// The registry and its four inspectors belong to one document window.
@interface RSInspectorRegistry : OIInspectorRegistry
@end

// The sidebar of one document window: a labelled section selector (Style, Axes, Canvas, Data) over
// the four existing inspectors, which keep OIInspectorController hosting, OIInspectorTabController
// loading and their 240 pt nib geometry, and scroll vertically. Omni's own tab cells draw images
// only and its tab switch ignores a failed field commit, hence this selector: switching a section
// commits the field being edited first and stays put if the commit is refused.
@interface RSInspectorSidebar : OIInspector <OIConcreteInspector, OIInspectorTabContainer>
@property(nonatomic, readonly) NSUInteger selectedSection;
- (BOOL)selectSection:(NSUInteger)section;
- (BOOL)commitEditing;
- (void)refreshInspectors;
- (nullable OIInspectorTabController *)tabWithIdentifier:(NSString *)identifier;
@end

NS_ASSUME_NONNULL_END
