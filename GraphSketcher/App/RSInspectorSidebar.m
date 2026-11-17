#import "RSInspectorSidebar.h"
#import <Cocoa/Cocoa.h>
#import <OmniInspector/OIInspectorController.h>

@implementation RSInspectorRegistry
// Window restoration owns UI state; Omni's workspace state is process-wide.
- (void)configurationsChanged {}
- (void)restoreInspectorGroups {}
- (void)dynamicMenuPlaceholderSet {}
@end

@interface RSInspectorContentView : NSView
@end
@implementation RSInspectorContentView
- (BOOL)isFlipped { return YES; }
- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    NSView *inspector = self.subviews.firstObject;
    NSRect frame = inspector.frame;
    frame.origin.x = floor((NSWidth(self.bounds) - NSWidth(frame)) / 2);
    inspector.frame = frame;
}
@end

@implementation RSInspectorSidebar {
    NSArray *_sections;
    NSStackView *_selector;
    NSScrollView *_scrollView;
    RSInspectorContentView *_content;
    NSUInteger _selectedSection;
    BOOL _inspecting;
}

- (id)initWithDictionary:(NSDictionary *)dictionary inspectorRegistry:(OIInspectorRegistry *)registry bundle:(NSBundle *)bundle {
    if (!(self = [super initWithDictionary:dictionary inspectorRegistry:registry bundle:bundle]))
        return nil;
    NSMutableArray *sections = [NSMutableArray array];
    for (NSDictionary *tab in dictionary[@"tabs"]) {
        OIInspectorTabController *controller = [[OIInspectorTabController alloc] initWithInspectorDictionary:tab inspectorRegistry:registry bundle:bundle];
        if (!controller) {
            [self release];
            return nil;
        }
        [sections addObject:controller];
        [controller release];
    }
    _sections = [sections copy];
    return self;
}

- (void)dealloc {
    for (OIInspectorTabController *section in _sections)
        if (section.hasLoadedView) [section.inspector inspectObjects:nil];
    [_sections release];
    [super dealloc];
}

- (void)loadView {
    NSView *view = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 280, 500)] autorelease];
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.view = view;
    _selector = [[[NSStackView alloc] initWithFrame:NSMakeRect(8, 440, 264, 52)] autorelease];
    _selector.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    _selector.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _selector.distribution = NSStackViewDistributionFillEqually;
    _selector.spacing = 2;
    NSArray *titles = @[NSLocalizedString(@"Style", @"Inspector section"), NSLocalizedString(@"Axes", @"Inspector section"), NSLocalizedString(@"Canvas", @"Inspector section"), NSLocalizedString(@"Data", @"Inspector section")];
    for (NSUInteger index = 0; index < _sections.count; index++) {
        OIInspectorTabController *section = _sections[index];
        NSButton *button = [NSButton buttonWithTitle:titles[index] target:self action:@selector(changeSection:)];
        button.tag = index;
        button.buttonType = NSButtonTypePushOnPushOff;
        button.bezelStyle = NSBezelStyleRegularSquare;
        button.image = section.image;
        button.imagePosition = NSImageAbove;
        button.imageScaling = NSImageScaleProportionallyDown;
        button.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
        button.toolTip = [NSString stringWithFormat:@"%@ (⌘%lu)", titles[index], (unsigned long)index + 1];
        [button setAccessibilityLabel:titles[index]];
        [_selector addArrangedSubview:button];
    }
    [view addSubview:_selector];
    _scrollView = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 280, 432)] autorelease];
    _scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    _scrollView.drawsBackground = NO;
    _content = [[[RSInspectorContentView alloc] initWithFrame:NSMakeRect(0, 0, 280, 0)] autorelease];
    _content.autoresizingMask = NSViewWidthSizable;
    _scrollView.documentView = _content;
    [view addSubview:_scrollView];
    [self displaySection];
}

- (void)didSetInspectorController {
    [super didSetInspectorController];
    for (OIInspectorTabController *section in _sections)
        section.inspector.inspectorController = self.inspectorController;
}

- (NSUInteger)selectedSection { return _selectedSection; }

- (BOOL)commitEditing {
    return !self.isViewLoaded || !self.view.window || [self.view.window makeFirstResponder:self.view.window];
}

- (BOOL)selectSection:(NSUInteger)section {
    if (section >= _sections.count || ![self commitEditing]) return NO;
    _selectedSection = section;
    [self displaySection];
    [self.view.window invalidateRestorableState];
    return YES;
}

- (void)changeSection:(NSButton *)sender {
    if (![self selectSection:sender.tag])
        [self updateSelector];
}

- (void)updateSelector {
    for (NSButton *button in _selector.arrangedSubviews)
        button.state = button.tag == (NSInteger)_selectedSection ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)displaySection {
    if (!self.isViewLoaded || !_sections.count) return;
    for (NSView *view in [[_content.subviews copy] autorelease]) [view removeFromSuperview];
    OIInspectorTabController *section = _sections[_selectedSection];
    NSView *view = section.inspectorView;
    // Preserve the nib's actual control geometry; only the surrounding sidebar grows.
    NSRect frame = view.frame;
    frame.origin = NSMakePoint(floor((NSWidth(_scrollView.contentView.bounds) - NSWidth(frame)) / 2), 0);
    view.autoresizingMask = NSViewNotSizable;
    view.frame = frame;
    _content.frame = NSMakeRect(0, 0, NSWidth(_scrollView.contentView.bounds), NSHeight(frame));
    [_content addSubview:view];
    [_content scrollPoint:NSZeroPoint];
    [self updateSelector];
    [self refreshInspectors];
}

- (nullable OIInspectorTabController *)tabWithIdentifier:(NSString *)identifier {
    for (OIInspectorTabController *section in _sections)
        if ([section.inspectorIdentifier isEqualToString:identifier]) return section;
    return nil;
}

- (NSPredicate *)inspectedObjectsPredicate { return [NSPredicate predicateWithValue:YES]; }

- (void)inspectObjects:(NSArray *)objects {
    _inspecting = objects.count != 0;
    [self refreshInspectors];
}

- (void)refreshInspectors {
    for (NSUInteger index = 0; index < _sections.count; index++) {
        OIInspectorTabController *section = _sections[index];
        [section inspectObjects:!_inspecting || index != _selectedSection];
    }
}
@end
