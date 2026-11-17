// Offscreen checks of AppController's assertion policy on the main-thread paths that matter:
// accessibility requests (AppKit's real in-process AX entry points), event dispatch through
// OAApplication -sendEvent: (a menu key equivalent), and run-loop callouts under -[NSApplication run].
// No application delegate and no visible window; the run loop runs with a prohibited activation policy.
#import "RSBoxSeparator.h"
#import <OmniAppKit/OAApplication.h>
#import <OmniFoundation/OFController.h>
#import <dlfcn.h>

static void Check(BOOL condition, NSString *message) {
    if (!condition) [NSException raise:@"AssertionPolicyCheckFailure" format:@"%@", message];
}

// Apple's frameworks call the handler from their own code. NSInvocation makes CoreFoundation the
// caller, so the handler sees what it sees for a real AppKit NSAssert.
static NSUInteger ReturnedFromHandler;
static void SystemMethodAssertion(id object, NSString *selectorName, NSString *file) {
    NSAssertionHandler *handler = NSAssertionHandler.currentHandler;
    Check((id)handler == OFController.sharedController, @"The production OFController subclass is the main thread's assertion handler");
    SEL handlerSelector = @selector(handleFailureInMethod:object:file:lineNumber:description:);
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[handler methodSignatureForSelector:handlerSelector]];
    invocation.target = handler; invocation.selector = handlerSelector;
    SEL failing = NSSelectorFromString(selectorName); int line = 1492; NSString *description = @"Fixture system framework assertion";
    [invocation setArgument:&failing atIndex:2]; [invocation setArgument:&object atIndex:3]; [invocation setArgument:&file atIndex:4];
    [invocation setArgument:&line atIndex:5]; [invocation setArgument:&description atIndex:6];
    [invocation invoke];
    ReturnedFromHandler++;
}
static void SystemFunctionAssertion(void) {
    NSAssertionHandler *handler = NSAssertionHandler.currentHandler;
    SEL handlerSelector = @selector(handleFailureInFunction:file:lineNumber:description:);
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[handler methodSignatureForSelector:handlerSelector]];
    invocation.target = handler; invocation.selector = handlerSelector;
    NSString *function = @"_NSFixtureFunction", *file = @"NSFixture.m", *description = @"Fixture system framework function assertion"; int line = 7;
    [invocation setArgument:&function atIndex:2]; [invocation setArgument:&file atIndex:3]; [invocation setArgument:&line atIndex:4]; [invocation setArgument:&description atIndex:5];
    [invocation invoke];
    ReturnedFromHandler++;
}
static NSMenu *SystemObject(void) { return [[[NSMenu alloc] initWithTitle:@""] autorelease]; }

// What each probe does when AppKit (or the fixture) reaches it.
static NSString *Armed;
static void Probe(NSString *name) {
    if (![Armed isEqual:name]) return;
    Armed = nil;
    NSString *kind = [name substringFromIndex:[name rangeOfString:@"-"].location + 1];  // after the path prefix
    if ([kind isEqual:@"method"]) SystemMethodAssertion(SystemObject(), @"_fixtureSelector", @"NSMenu.m");
    else if ([kind isEqual:@"function"]) SystemFunctionAssertion();
    else if ([kind isEqual:@"harmless"]) SystemMethodAssertion(SystemObject(), @"_simulateClosed", @"NSMenu.m");
    else if ([kind isEqual:@"raw-raise"]) [NSException raise:NSInternalInconsistencyException format:@"Fixture raw raise (%@)", name];
    else if ([kind isEqual:@"graphink-object"]) SystemMethodAssertion([[[RSBoxSeparator alloc] initWithFrame:NSZeroRect] autorelease], @"_fixtureSelector", @"NSBox.m");
    else if ([kind isEqual:@"omni-object"]) SystemMethodAssertion(NSApp, @"_fixtureSelector", @"NSApplication.m");
    else if ([kind isEqual:@"our-caller"]) [NSAssertionHandler.currentHandler handleFailureInMethod:@selector(update) object:SystemObject() file:@"NSMenu.m" lineNumber:1 description:@"Graphink code asserting about an AppKit object"];
    else if ([kind isEqual:@"graphink-function"]) NSCAssert(NO, @"A Graphink NSCAssert still crashes");
    else if ([kind isEqual:@"nested-loop"]) {
        // A nested event loop inside an accessibility request: the innermost catcher is no longer AppKit's AX entry point.
        Armed = @"nested-method";
        [NSApp performSelector:@selector(fixtureProbeNested) withObject:nil afterDelay:0];
        [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate dateWithTimeIntervalSinceNow:0.3] inMode:NSDefaultRunLoopMode dequeue:YES];
        Check(Armed == nil, @"The nested event loop ran the probe");
    }
    else Check(NO, [@"Unknown probe " stringByAppendingString:name]);
}

// The application element is OAApplication itself; these accessibility overrides are fixture-only.
@interface OAApplication (AssertionPolicyChecks)
@end
@implementation OAApplication (AssertionPolicyChecks)
- (void)fixtureProbeNested { Probe(@"nested-method"); }
- (void)fixtureProbeTimer:(NSString *)name { Armed = name; Probe(name); }
- (void)fixtureStop { [self stop:nil]; [self postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0] atStart:NO]; }
- (NSArray *)accessibilityAttributeNames { return [[super accessibilityAttributeNames] arrayByAddingObject:@"AXPolicyProbe"]; }
- (id)accessibilityAttributeValue:(NSString *)attribute {
    if (![attribute isEqual:@"AXPolicyProbe"]) return [super accessibilityAttributeValue:attribute];
    Probe(Armed);
    return @"value";
}
- (BOOL)accessibilityIsAttributeSettable:(NSString *)attribute { return [attribute isEqual:@"AXPolicyProbe"] || [super accessibilityIsAttributeSettable:attribute]; }
- (void)accessibilitySetValue:(id)value forAttribute:(NSString *)attribute {
    if ([attribute isEqual:@"AXPolicyProbe"]) Probe(Armed); else [super accessibilitySetValue:value forAttribute:attribute];
}
- (NSArray *)accessibilityParameterizedAttributeNames { return @[@"AXPolicyParameterizedProbe"]; }
- (id)accessibilityAttributeValue:(NSString *)attribute forParameter:(id)parameter { Probe(Armed); return @"value"; }
- (NSArray *)accessibilityActionNames { return @[@"AXPolicyAction"]; }
- (void)accessibilityPerformAction:(NSString *)action { Probe(Armed); }
@end

// Event dispatch: a Command key equivalent goes through OAApplication -sendEvent: and AppKit's menu
// key-equivalent dispatch to this menu item's action. No window is needed.
@interface ProbeTarget : NSObject
@end
@implementation ProbeTarget
- (void)probe:(id)sender { Probe(Armed); }
@end
static void SendProbeKeyEquivalent(NSString *name) {
    static ProbeTarget *target;
    if (!target) {
        target = [[ProbeTarget alloc] init];
        NSMenu *mainMenu = [[[NSMenu alloc] initWithTitle:@""] autorelease], *submenu = [[[NSMenu alloc] initWithTitle:@"Probe"] autorelease];
        NSMenuItem *item = [submenu addItemWithTitle:@"Probe" action:@selector(probe:) keyEquivalent:@"k"];
        item.target = target;
        [mainMenu addItemWithTitle:@"Probe" action:NULL keyEquivalent:@""].submenu = submenu;
        NSApp.mainMenu = mainMenu;
    }
    Armed = name;
    NSEvent *key = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:0 context:nil characters:@"k" charactersIgnoringModifiers:@"k" isARepeat:NO keyCode:40];
    [NSApp sendEvent:key];
    Check(Armed == nil, [@"The key equivalent reached the probe: " stringByAppendingString:name]);
}
// Run-loop callouts under -[NSApplication run]: a delayed perform fires the probe, then the loop stops.
static void RunProbeUnderApplicationRun(NSString *name) {
    [NSApp performSelector:@selector(fixtureProbeTimer:) withObject:name afterDelay:0];
    [NSApp performSelector:@selector(fixtureStop) withObject:nil afterDelay:0.2];
    [NSApp run];
    Check(Armed == nil, [@"-[NSApplication run] fired the probe: " stringByAppendingString:name]);
}

// Accessibility requests: AXUIElement calls on our own application element run synchronously on the
// calling thread through HIServices' request routines and AppKit's entry points, as a remote request does.
typedef AXError (*CopyHierarchyFunction)(AXUIElementRef, CFArrayRef, CFDictionaryRef, CFDictionaryRef *);
static AXError AccessibilityRequest(NSString *kind, NSString *probe) {
    AXUIElementRef application = AXUIElementCreateApplication(getpid());
    CFTypeRef value = NULL; AXError error = kAXErrorSuccess;
    Armed = probe;
    if ([kind isEqual:@"get"]) error = AXUIElementCopyAttributeValue(application, CFSTR("AXPolicyProbe"), &value);
    else if ([kind isEqual:@"set"]) error = AXUIElementSetAttributeValue(application, CFSTR("AXPolicyProbe"), kCFBooleanTrue);
    else if ([kind isEqual:@"parameterized"]) error = AXUIElementCopyParameterizedAttributeValue(application, CFSTR("AXPolicyParameterizedProbe"), kCFBooleanTrue, &value);
    else if ([kind isEqual:@"action"]) error = AXUIElementPerformAction(application, CFSTR("AXPolicyAction"));
    else if ([kind isEqual:@"multiple"] || [kind isEqual:@"hierarchy"]) {
        // These answer per attribute inside a successful reply; a failed attribute counts as an error.
        CFArrayRef attributes = (CFArrayRef)@[@"AXRole", @"AXPolicyProbe"];
        if ([kind isEqual:@"multiple"]) {
            CFArrayRef values = NULL;
            error = AXUIElementCopyMultipleAttributeValues(application, attributes, 0, &values);
            if (!error) {
                id probeValue = [(NSArray *)values lastObject];
                error = [probeValue isEqual:@"value"] ? kAXErrorSuccess : kAXErrorFailure;
                CFRelease(values);
            }
        } else {
            CopyHierarchyFunction copyHierarchy = (CopyHierarchyFunction)dlsym(RTLD_DEFAULT, "AXUIElementCopyHierarchy");
            Check(copyHierarchy != NULL, @"HIServices has AXUIElementCopyHierarchy (the request that crashed natively)");
            CFDictionaryRef hierarchy = NULL;
            error = copyHierarchy(application, attributes, NULL, &hierarchy);
            if (!error) {
                // One entry, our element; an attribute whose getter raised is left out.
                NSDictionary *element = [[(NSDictionary *)hierarchy allValues] lastObject];
                error = [element[@"AXPolicyProbe"][@"value"] isEqual:@"value"] ? kAXErrorSuccess : kAXErrorFailure;
                CFRelease(hierarchy);
            }
        }
    } else Check(NO, [@"Unknown accessibility request " stringByAppendingString:kind]);
    if (value) CFRelease(value);
    CFRelease(application);
    Check(Armed == nil, [NSString stringWithFormat:@"The %@ request reached the probe %@", kind, probe]);
    return error;
}

static void CheckAccessibilityRequests(void) {
    // Option C: a system framework assertion raises; AppKit's entry point catches it and answers with an error.
    for (NSString *kind in @[@"get", @"set", @"parameterized", @"action", @"multiple", @"hierarchy"]) {
        for (NSString *probe in @[@"ax-method", @"ax-function"]) {
            NSUInteger returned = ReturnedFromHandler;
            AXError error = AccessibilityRequest(kind, probe);
            Check(error != kAXErrorSuccess, [NSString stringWithFormat:@"%@ request with %@ answered with an accessibility error", kind, probe]);
            Check(ReturnedFromHandler == returned, [NSString stringWithFormat:@"%@ request with %@ unwound out of the asserting code", kind, probe]);
        }
    }
    // The same raise without going through the handler, as Apple's default handler would raise it.
    Check(AccessibilityRequest(@"get", @"ax-raw-raise") != kAXErrorSuccess, @"A raw raise in an accessibility request is answered with an error");
    // The proven -[NSMenu _simulateClosed] rule still wins: logged, returns, the query gets its value.
    NSUInteger returned = ReturnedFromHandler;
    Check(AccessibilityRequest(@"get", @"ax-harmless") == kAXErrorSuccess && ReturnedFromHandler == returned + 1, @"The _simulateClosed assertion is ignored and the value is returned");
    // A nested event loop inside a request: the catcher would be OFController's, so log and return.
    returned = ReturnedFromHandler;
    Check(AccessibilityRequest(@"get", @"ax-nested-loop") == kAXErrorSuccess && ReturnedFromHandler == returned + 1, @"An assertion in a nested event loop inside a request is logged and returns");
    // Requests still work afterwards.
    AXUIElementRef application = AXUIElementCreateApplication(getpid()); CFTypeRef role = NULL;
    Check(AXUIElementCopyAttributeValue(application, kAXRoleAttribute, &role) == kAXErrorSuccess && [(id)role isEqual:NSAccessibilityApplicationRole], @"Accessibility requests still work after the raises");
    CFRelease(role); CFRelease(application);
    puts("PASS accessibility requests: system framework assertions raise and AppKit answers with an error (get, set, parameterized, action, multiple, hierarchy; method and function)");
}

static void CheckEventDispatchAndRunLoop(void) {
    // Option B fallback: here a raise would reach OAApplication -reportException: and crash (see the crash modes).
    NSUInteger returned = ReturnedFromHandler;
    SendProbeKeyEquivalent(@"event-method"); SendProbeKeyEquivalent(@"event-function");
    Check(ReturnedFromHandler == returned + 2, @"Event dispatch: system framework assertions are logged and return");
    RunProbeUnderApplicationRun(@"run-method"); RunProbeUnderApplicationRun(@"run-function");
    Check(ReturnedFromHandler == returned + 4, @"Run-loop callouts: system framework assertions are logged and return");
    puts("PASS event dispatch and run-loop callouts: system framework assertions are logged and execution continues");
}

// Each crash mode runs in its own process; the runner sets OFCrashShouldExitWithCode.
static void TriggerCrashMode(NSString *mode) {
    NSLog(@"Crash mode %@: expecting OFController to crash", mode);
    if ([mode hasPrefix:@"ax-"]) AccessibilityRequest(@"get", mode);
    else if ([mode hasPrefix:@"event-"]) SendProbeKeyEquivalent(mode);
    else if ([mode hasPrefix:@"run-"]) RunProbeUnderApplicationRun(mode);
    else Check(NO, [@"Unknown crash mode " stringByAppendingString:mode]);
    puts("CRASH MODE DID NOT CRASH");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool { @try {
        Check(argc >= 2, @"Pass an owned output directory");
        [(Class)NSBundle.mainBundle.principalClass sharedApplication];  // OAApplication, as in the app
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        [NSApp finishLaunching];  // registers the application for accessibility requests; no delegate to notify
        Check([NSApp isMemberOfClass:[OAApplication class]], @"NSApp is OAApplication, as in the app");
        Check([NSBundle.mainBundle.bundleIdentifier hasPrefix:@"com.graphink.assertionpolicychecks."], @"Unique fixture domain required");
        OFController *lifecycle = OFController.sharedController;
        Check([lifecycle isKindOfClass:NSClassFromString(@"AppController")], @"OFControllerClass is the production AppController");
        [lifecycle didInitialize]; [lifecycle startedRunning];
        Check(NSApp.delegate == nil, @"Fixture must not install the application delegate");
        Check([[OFPreference preferenceForKey:@"OFCrashOnAssertionOrUnhandledException"] boolValue], @"Fixture keeps OmniFoundation's crash-on-assertion default");
        if (argc >= 4 && !strcmp(argv[2], "--crash")) {
            TriggerCrashMode(@(argv[3]));
            return 2;
        }
        CheckAccessibilityRequests();
        CheckEventDispatchAndRunLoop();
        Check([lifecycle requestTermination] == OFControllerTerminateNow, @"Fixture lifecycle refused termination");
        [lifecycle willTerminate];
        puts("PASS assertion policy checks; offscreen only");
    } @catch (NSException *exception) {
        NSLog(@"FAIL assertion policy: %@", exception); return 1;
    } }
    return 0;
}
