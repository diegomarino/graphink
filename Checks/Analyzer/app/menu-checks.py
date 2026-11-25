#!/usr/bin/env python3
"""Check real AppKit menu construction, the Debug-only Experimental menu guard and production equation dispatch offscreen."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True, help='New isolated output directory')
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=False)
contents = output / 'MenuChecks.app/Contents'
(contents / 'MacOS').mkdir(parents=True)
domain = 'com.graphsketcher.AnalyzerAppChecks.' + uuid.uuid4().hex
(contents / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': domain, 'CFBundleExecutable': 'checks', 'CFBundlePackageType': 'APPL'}))

def extract(text, signature):
    start = text.index(signature)
    opening = text.index('{', start)
    end, depth = opening + 1, 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]

controller = (root / 'GraphSketcher/App/AppController.m').read_text()
# The Experimental menu is Debug-only: its builder and its one call sit inside `#ifdef DEBUG`
# (DEBUG comes from Omni-Global-Debug.xcconfig), and no preference can turn it on in Release.
assert 'ShowExperimentalFeaturesMenu' not in controller, 'The Experimental menu must not depend on a preference'
assert b'ShowExperimentalFeaturesMenu' not in (root / 'GraphSketcher/App/Info.plist').read_bytes(), 'Stale ShowExperimentalFeaturesMenu default'
assert '#define DEBUG' not in controller and '#undef DEBUG' not in controller
assert 'DEBUG DEBUG_$(USER)' in (root / 'OmniGroup/Configurations/Omni-Global-Debug.xcconfig').read_text(), 'Debug no longer defines DEBUG'
assert 'PREPROCESSOR_DEFINITIONS' not in (root / 'OmniGroup/Configurations/Omni-Global-Release.xcconfig').read_text(), 'Release must not define DEBUG'
DEFINITION = '#ifdef DEBUG\n- (void)_installExperimentalMenu;\n{\n'
CALL = '#ifdef DEBUG\n    // Debug builds always show the Experimental menu; Release builds compile it out entirely.\n    [self _installExperimentalMenu];\n#endif\n}\n'
assert controller.count('_installExperimentalMenu') == 2 and controller.count(DEFINITION) == 1 and controller.count(CALL) == 1
assert controller.index(CALL) < controller.index('- (void)applicationDidFinishLaunching:'), 'The call must stay in applicationWillFinishLaunching:'
method = extract(controller, '- (void)_installExperimentalMenu;')
assert controller[controller.index(method) + len(method):].startswith('\n#endif\n'), 'The builder must end inside its #ifdef DEBUG'
assert controller.count('"Experimental menu item"') == method.count('"Experimental menu item"'), 'Experimental strings outside the Debug-only builder'
menu = method[method.index('{') + 1:-1]
# Preprocess the production text (no headers needed) the way each configuration does: with
# -DDEBUG the call and the builder survive; without it nothing of the menu does.
region = controller[controller.index(CALL):controller.index(method) + len(method) + len('\n#endif\n')]
for flags, present in ((['-DDEBUG', '-DDEBUG_ci'], True), ([], False)):
    preprocessed = subprocess.run(['xcrun', 'clang', '-E', '-P', '-x', 'objective-c', *flags, '-'], input=region, capture_output=True, text=True, check=True).stdout
    for needle in ('_installExperimentalMenu', 'NSLocalizedString(@"Experimental"', 'insertItem:experimentalMenuItem atIndex:7'):
        assert (needle in preprocessed) == present, (flags, needle)
(output / 'preprocessed-release.m').write_text(preprocessed)
print('PASS: Experimental menu builder and call only under #ifdef DEBUG; the Release preprocessor output has none of it')
action = extract((root / 'GraphSketcher/App/RSGraphView.m').read_text(), '- (IBAction)addEquationLine:')
model = (root / 'GraphSketcher/Model/RSEquationLine.h').read_text()
model = model[model.index('typedef enum'):model.index('RSEquation RSEquationZero')]
style = (root / 'GraphSketcher/App/RSStylePresets.m').read_text()
font_block = style[style.index('                NSFont *target=[NSFont fontWithName:fontName'):style.index('            }];', style.index('void RSAdaptNewObjectColor'))]
source = '''#import <Cocoa/Cocoa.h>
typedef double data_p;
''' + model + '''
static RSEquation added;
@interface RSEquationLine : NSObject
- (id)initWithGraph:(id)graph identifier:(NSString *)identifier equation:(RSEquation)equation;
@end
@implementation RSEquationLine
- (id)initWithGraph:(id)graph identifier:(NSString *)identifier equation:(RSEquation)equation {
    self = [super init]; added = equation; return self;
}
@end
@interface NSObject (GraphContract)
- (void)addLine:(id)line;
@end
@interface Dispatch : NSObject { id _graph; }
- (void)setSelection:(id)value;
@end
@implementation Dispatch
- (void)setSelection:(id)value {}
''' + action + '''
@end
static void ApplyTextFont(NSFont *font, NSString *fontName, NSMutableAttributedString *value) {
    NSRange range = NSMakeRange(0, value.length);
''' + font_block + '''
}
static void BuildMenu(void) {
''' + menu + '''
}
int main(void) {
    @autoreleasepool {
        NSString *domain = NSBundle.mainBundle.bundleIdentifier;
        NSCAssert([domain hasPrefix:@"com.graphsketcher.AnalyzerAppChecks."], @"Wrong fixture domain");
        CFPreferencesSetAppValue(CFSTR("RoutingProbe"), (CFStringRef)domain, kCFPreferencesCurrentApplication);
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
        id probe = [(id)CFPreferencesCopyAppValue(CFSTR("RoutingProbe"), (CFStringRef)domain) autorelease];
        NSCAssert([probe isEqual:domain], @"Preference routing failed");
        [NSApplication sharedApplication];
        NSMutableAttributedString *text = [[[NSMutableAttributedString alloc] initWithString:@"text"] autorelease];
        ApplyTextFont(nil, @"Helvetica", text);
        NSFont *fallback = [text attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
        NSCAssert(fallback && fallback.pointSize == 13, @"Missing source font must use target at fallback size");
        NSAttributedString *before = [[text copy] autorelease];
        ApplyTextFont(nil, @"UnavailableFont-AnalyzerFixture", text);
        NSCAssert([text isEqualToAttributedString:before], @"Unavailable target font must preserve text");
        NSFont *bold = [NSFont boldSystemFontOfSize:18];
        ApplyTextFont(bold, @"Helvetica", text);
        NSFont *converted = [text attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
        NSCAssert(converted.pointSize == 18 && ([[NSFontManager sharedFontManager] traitsOfFont:converted] & NSBoldFontMask), @"Font substitution must preserve size and bold trait");
        NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"Fixture"];
        for (NSUInteger i = 0; i < 7; i++) [mainMenu addItemWithTitle:@"Fixture" action:NULL keyEquivalent:@""];
        NSApp.mainMenu = mainMenu;
        BuildMenu();
        NSMenu *menu = [mainMenu itemAtIndex:7].submenu;
        NSArray *titles = @[@"y = x^2 + c", @"y = x^3 + c", @"y = sin(x) + c", @"y = e^(-x^2) + c (Bell Curve)", @"y = 1/(1 + e^-x) + c (Logistic)"];
        Dispatch *view = [[Dispatch alloc] init];
        NSUInteger count = 0;
        for (NSMenuItem *item in menu.itemArray) {
            if (item.action != @selector(addEquationLine:)) continue;
            NSCAssert(count < titles.count && [item.title isEqual:titles[count]], @"Source English changed");
            NSCAssert(item.tag == (NSInteger)count + RSEquationTypeSquare, @"Menu tag wiring is incorrect");
            item.title = @"Translated title without formula";
            [view performSelector:item.action withObject:item];
            NSCAssert(added.type == item.tag && added.a == 0 && added.b == 0 && added.c == 1, @"Translated menu dispatch failed");
            count++;
        }
        NSCAssert(count == 5, @"Expected all five equation commands");
        [view release]; NSApp.mainMenu = nil; [mainMenu release];
        puts("PASS: real AppKit menu wiring, five equation selectors/tags, translated-title dispatch, missing/invalid/source-trait font cases, isolated preference routing");
    }
    return 0;
}
'''
fixture = output / 'MenuChecks.m'
fixture.write_text(source)
command = ['xcrun', 'clang', '-fno-objc-arc', '-fobjc-exceptions', '-Wall', '-Werror', '-g', '-fsanitize=address', '-framework', 'AppKit', str(fixture), '-o', str(contents / 'MacOS/checks')]
(output / 'compile-command.json').write_text(json.dumps(command, indent=2) + '\n')
subprocess.run(command, check=True)

# Match the existing sidebar runner's real-domain preservation check.
def snapshot():
    result = {}
    for real in ('com.diegomarino.Graphink', 'com.diegomarino.Graphink.MacAppStore'):
        exported = subprocess.run(['defaults', 'export', real, '-'], capture_output=True)
        result[real] = {'status': exported.returncode, 'sha256': hashlib.sha256(exported.stdout).hexdigest()}
        files = [Path.home() / 'Library/Preferences' / (real + '.plist'), Path.home() / 'Library/Containers' / real / 'Data/Library/Preferences' / (real + '.plist')]
        files += list((Path.home() / 'Library/Preferences/ByHost').glob(real + '.*.plist'))
        result[real + ':files'] = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() if p.exists() else None for p in files}
    return result

before = snapshot()
(output / 'preferences-before.json').write_text(json.dumps(before, indent=2) + '\n')
try:
    ran = subprocess.run([str(contents / 'MacOS/checks')], capture_output=True)
    log = ran.stdout + ran.stderr
    (output / 'checks.log').write_bytes(log)
    print(log.decode(errors='replace'))
    ran.check_returncode()
    assert b'PASS: real AppKit menu wiring' in log and not any(x in log for x in (b'ASSERT failed', b'Assertion Failed:', b'ERROR: AddressSanitizer'))
finally:
    after = snapshot()
    (output / 'preferences-after.json').write_text(json.dumps(after, indent=2) + '\n')
    assert before == after, 'Real application preference domains changed'
print('PASS: real application preference domains unchanged')
