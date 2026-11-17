#!/usr/bin/env python3
"""ASan checks using verbatim production routines, without loading Omni frameworks or an app."""
import argparse
import hashlib
import json
import plistlib
import uuid
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source-root', type=Path, default=Path(__file__).resolve().parents[3])
parser.add_argument('--case', choices=('canonicalization', 'reference', 'namespace', 'ownership', 'layout', 'all'), default='all')
args = parser.parse_args()
root = args.source_root.resolve()
source = (root / 'OmniGroup/Frameworks/OmniFoundation/XML/OFXMLSignature.m').read_text()


def routine(text, marker):
    start = text.index(marker)
    return text[start:text.index('\n}', start) + 2]


canonical = routine(source, 'static BOOL canonicalizeToBuffer(')
reference = routine(source, '- (BOOL)_writeReference:(xmlNode *)referenceNode')
namespace = routine((root / 'OmniGroup/Frameworks/OmniFoundation/XML/OFXMLMaker.m').read_text(), '- (NSString *)assignPrefixForNamespace:')
initializer = routine((root / 'OmniGroup/Frameworks/OmniFoundation/OpenStepExtensions.subproj/NSObject-OFAppleScriptExtensions.m').read_text(), '- (id)appleScriptBlankInit;')
header = (root / 'OmniGroup/Frameworks/OmniFoundation/OpenStepExtensions.subproj/NSObject-OFAppleScriptExtensions.h').read_text()
init_declaration = next((line for line in header.splitlines() if 'appleScriptBlankInit' in line), '- (id)appleScriptBlankInit;')
storage_initializer = routine((root / 'OmniGroup/Frameworks/OmniAppKit/OpenStepExtensions.subproj/NSTextStorage-OAExtensions.m').read_text(), '- (id)appleScriptBlankInit;')
layout_source = (root / 'OmniGroup/Frameworks/OmniInspector/OIScrollingTabbedInspector.m').read_text()
start = layout_source.index('    NSView *firstInspectorView = firstTab.inspectorView;')
layout = layout_source[start:layout_source.index('    if (!self.scrollViewWidthConstraint)', start)]
constants = '\n'.join(line for line in source.splitlines() if line.startswith('#define XMLCanonicalization'))
fixture = r'''
#import <Foundation/Foundation.h>
#include <libxml/tree.h>
#include <libxml/c14n.h>
#include <libxml/xpointer.h>
#include <assert.h>
#define XMLSignatureNamespace ((const xmlChar *)"http://www.w3.org/2000/09/xmldsig#")
#define XMLExclusiveCanonicalizationNamespace ((const xmlChar *)"http://www.w3.org/2001/10/xml-exc-c14n#")
#define OBASSERT(x) assert(x)
@interface NSString (Fixture)
+ (BOOL)isEmptyString:(NSString *)value;
@end
@implementation NSString (Fixture)
+ (BOOL)isEmptyString:(NSString *)value { return value == nil || [value length] == 0; }
@end
static BOOL failure(NSError **error, NSString *format, va_list ap) {
    NSString *message = [[[NSString alloc] initWithFormat:format arguments:ap] autorelease];
    if (error) *error = [NSError errorWithDomain:@"invalid.example.graphink.analyzer.fixture" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
    return NO;
}
static BOOL signatureValidationFailure(NSError **error, NSString *format, ...) {
    va_list ap; va_start(ap, format); BOOL ok = failure(error, format, ap); va_end(ap); return ok;
}
#define signatureStructuralFailure signatureValidationFailure
static BOOL translateLibXMLError(NSError **error, BOOL flag, NSString *format, ...) {
    va_list ap; va_start(ap, format); BOOL ok = failure(error, format, ap); va_end(ap); return ok;
}
static xmlChar *lessBrokenGetAttribute(xmlNode *node, const char *name, const xmlChar *ns) { return xmlGetProp(node, (const xmlChar *)name); }
static xmlNode *OFLibXMLChildNamed(xmlNode *parent, const char *name, const xmlChar *ns, unsigned int *count) {
    xmlNode *found = NULL; *count = 0;
    for (xmlNode *n = parent->children; n; n = n->next) if (n->type == XML_ELEMENT_NODE && xmlStrEqual(n->name, (const xmlChar *)name)) { found = n; (*count)++; }
    return found;
}
static int isOneVisible(void *user, xmlNode *node, xmlNode *parent) { return 1; }
#define isOneVisibleOmittingComments isOneVisible
static BOOL isNamed(xmlNode *node, const char *name, const xmlChar *ns, void *unused) { return xmlStrEqual(node->name, (const xmlChar *)name); }
struct OFXMLSignatureVerifyContinuation {
    void *ctxt; struct OFXMLSignatureVerifyContinuation *next;
    xmlOutputBuffer *(*openStream)(struct OFXMLSignatureVerifyContinuation *, NSError **);
    BOOL (*acceptNodes)(struct OFXMLSignatureVerifyContinuation *, xmlDocPtr, xmlC14NIsVisibleCallback, void *, NSError **);
    void (*cleanup)(void *);
};
'''
fixture += constants + '\n' + canonical + '\n'
fixture += routine(source, 'static xmlNode *singleNodeFromXptrExpression(') + '\n'
fixture += r'''
static int writes, nodeSets, deaths, storageDeaths;
static int discard(void *context, const char *buffer, int size) { return size; }
static xmlOutputBuffer *openBytes(struct OFXMLSignatureVerifyContinuation *stream, NSError **error) { return xmlOutputBufferCreateIO(discard, NULL, NULL, NULL); }
static BOOL acceptNodes(struct OFXMLSignatureVerifyContinuation *stream, xmlDocPtr doc, xmlC14NIsVisibleCallback callback, void *context, NSError **error) { nodeSets++; return YES; }
@interface ReferenceFixture : NSObject { @public xmlDoc *owningDocument; }
- (BOOL)_writeReference:(xmlNode *)referenceNode to:(struct OFXMLSignatureVerifyContinuation *)stream error:(NSError **)error;
- (BOOL)writeReference:(NSString *)uri type:(NSString *)type to:(xmlOutputBuffer *)stream error:(NSError **)error;
@end
@implementation ReferenceFixture
- (BOOL)writeReference:(NSString *)uri type:(NSString *)type to:(xmlOutputBuffer *)stream error:(NSError **)error { writes++; return YES; }
'''
fixture += reference + '\n@end\n'
fixture += '@interface NSObject (FixtureInit)\n' + init_declaration + '\n@end\n@implementation NSObject (FixtureInit)\n' + initializer + '\n@end\n'
fixture += r'''
@interface LifetimeFixture : NSObject
@end
@implementation LifetimeFixture
- (void)dealloc { deaths++; [super dealloc]; }
@end
@interface NamespaceFixture : NSObject { NSMutableDictionary *knownNamespaceBindings; NSMutableSet *knownNamespacePrefixes; int namespacePrefixNextUniqueID; }
- (NSString *)assignPrefixForNamespace:(NSString *)ns hint:(NSString *)prefixHint;
@end
@implementation NamespaceFixture
- (id)init { if ((self = [super init])) { knownNamespaceBindings = [NSMutableDictionary new]; knownNamespacePrefixes = [NSMutableSet new]; } return self; }
- (void)dealloc { [knownNamespaceBindings release]; [knownNamespacePrefixes release]; [super dealloc]; }
'''
fixture += namespace + '\n@end\n'
fixture += r'''
@interface StorageFixture : NSObject
@property(nonatomic, copy) NSString *text;
@end
@interface InitializedStorageFixture : StorageFixture
@end
@interface NilStorageFixture : StorageFixture
@end
@implementation InitializedStorageFixture
@end
@implementation NilStorageFixture
- (id)init { self = [super init]; [self release]; return nil; }
@end
@implementation StorageFixture
@synthesize text;
- (id)init {
    if ([self class] == [StorageFixture class]) { [self release]; return [[InitializedStorageFixture alloc] init]; }
    return [super init];
}
- (void)setText:(NSString *)value { if (text != value) { [text release]; text = [value copy]; } }
- (void)dealloc { storageDeaths++; [text release]; [super dealloc]; }
'''
fixture += storage_initializer + '\n@end\n'

# Deliberately strict doubles model nonnull anchors and constraint removal. No AppKit startup.
fixture += r'''
#define NSLayoutPriorityDefaultLow 250
@class Constraint;
@interface Anchor : NSObject
- (Constraint *)constraintEqualToAnchor:(Anchor *)anchor;
@end
@interface Constraint : NSObject
@property(assign) id secondItem;
@property int priority;
@end
@implementation Constraint
@synthesize secondItem, priority;
@end
@implementation Anchor
- (Constraint *)constraintEqualToAnchor:(Anchor *)anchor { assert(anchor); Constraint *c = [[[Constraint alloc] init] autorelease]; c.secondItem = anchor; return c; }
@end
@interface NSView : NSObject
@property(retain) Anchor *topAnchor;
@property(retain) Anchor *bottomAnchor;
@property int removed;
- (void)removeConstraint:(Constraint *)constraint;
@end
@implementation NSView
@synthesize topAnchor, bottomAnchor, removed;
- (id)init { if ((self = [super init])) { self.topAnchor = [[[Anchor alloc] init] autorelease]; self.bottomAnchor = [[[Anchor alloc] init] autorelease]; } return self; }
- (void)removeConstraint:(Constraint *)constraint { self.removed++; }
- (void)dealloc { [topAnchor release]; [bottomAnchor release]; [super dealloc]; }
@end
@interface Tab : NSObject
@property(retain) NSView *inspectorView;
@end
@implementation Tab
@synthesize inspectorView;
- (void)dealloc { [inspectorView release]; [super dealloc]; }
@end
@interface LayoutFixture : NSObject
@property(retain) NSView *contentView;
@property(retain) Constraint *topConstraint;
@property(retain) Constraint *bottomConstraint;
- (void)layoutFirst:(Tab *)firstTab last:(Tab *)lastTab;
@end
@implementation LayoutFixture
@synthesize contentView, topConstraint, bottomConstraint;
- (void)layoutFirst:(Tab *)firstTab last:(Tab *)lastTab { NSMutableArray *constraints = [NSMutableArray array];
'''
fixture += layout + '\n}\n- (void)dealloc { [contentView release]; [topConstraint release]; [bottomConstraint release]; [super dealloc]; }\n@end\n'
fixture += r'''
int main(int argc, char **argv) { @autoreleasepool {
    assert([[[NSBundle mainBundle] bundleIdentifier] hasPrefix:@"invalid.example.graphink.analyzer.fixture."]);
    assert(argc == 2); NSString *test = [NSString stringWithUTF8String:argv[1]];
    xmlDoc *doc = xmlReadMemory("<root/>", 7, NULL, NULL, 0); assert(doc);
    xmlNode *node = xmlDocGetRootElement(doc); NSError *error = nil;
    if ([test isEqual:@"canonicalization"]) {
        xmlSetProp(node, (const xmlChar *)"Algorithm", (const xmlChar *)"urn:fixture:unsupported-algorithm");
        assert(!canonicalizeToBuffer(doc, node, node, NULL, &error));
        assert([[error localizedDescription] containsString:@"urn:fixture:unsupported-algorithm"]);
        xmlSetProp(node, (const xmlChar *)"Algorithm", XMLCanonicalization10_OmitComments);
        xmlOutputBuffer *output = openBytes(NULL, NULL);
        assert(canonicalizeToBuffer(doc, node, node, output, &error)); assert(xmlOutputBufferClose(output) >= 0);
    } else if ([test isEqual:@"reference"]) {
        xmlNodeSetName(node, (const xmlChar *)"Reference");
        ReferenceFixture *f = [ReferenceFixture new]; f->owningDocument = doc;
        struct OFXMLSignatureVerifyContinuation stream = {.openStream = NULL, .acceptNodes = acceptNodes};
        xmlSetProp(node, (const xmlChar *)"URI", (const xmlChar *)"https://example.invalid/fixture");
        assert(![f _writeReference:node to:&stream error:&error]); assert(error && writes == 0);
        stream.openStream = openBytes;
        assert([f _writeReference:node to:&stream error:&error]); assert(writes == 1);
        stream.openStream = NULL;
        xmlSetProp(node, (const xmlChar *)"URI", (const xmlChar *)"");
        assert([f _writeReference:node to:&stream error:&error]); assert(nodeSets == 1);
        xmlSetProp(node, (const xmlChar *)"URI", (const xmlChar *)"#xpointer(/Reference)");
        assert([f _writeReference:node to:&stream error:&error]); assert(nodeSets == 2);
        [f release];
    } else if ([test isEqual:@"namespace"]) {
        NamespaceFixture *f = [NamespaceFixture new];
        NSString *first = [f assignPrefixForNamespace:@"urn:first" hint:nil]; assert([first hasPrefix:@"ns"]);
        assert([[f assignPrefixForNamespace:@"urn:first" hint:nil] isEqual:first]);
        assert([[f assignPrefixForNamespace:@"urn:second" hint:@"preferred"] isEqual:@"preferred"]);
        assert(![[f assignPrefixForNamespace:@"urn:third" hint:@"preferred"] isEqual:@"preferred"]);
        [f release];
    } else if ([test isEqual:@"ownership"]) {
        LifetimeFixture *f = [[LifetimeFixture alloc] appleScriptBlankInit]; [f release]; assert(deaths == 1);
        StorageFixture *storage = [[StorageFixture alloc] appleScriptBlankInit];
        assert([storage isKindOfClass:[InitializedStorageFixture class]]); assert([storage.text isEqual:@" "]); [storage release]; assert(storageDeaths == 2);
        assert([[NilStorageFixture alloc] appleScriptBlankInit] == nil); assert(storageDeaths == 3);
    } else if ([test isEqual:@"layout"]) {
        LayoutFixture *f = [LayoutFixture new]; f.contentView = [[[NSView alloc] init] autorelease];
        Tab *tab = [Tab new]; tab.inspectorView = [[[NSView alloc] init] autorelease];
        [f layoutFirst:tab last:tab]; assert(f.topConstraint && f.bottomConstraint);
        [f layoutFirst:nil last:nil]; assert(!f.topConstraint && !f.bottomConstraint); assert(f.contentView.removed == 2);
        [f layoutFirst:nil last:nil]; assert(f.contentView.removed == 2);
        [f layoutFirst:tab last:tab]; assert(f.topConstraint && f.bottomConstraint);
        [tab release]; [f release];
    } else { assert(0); }
    xmlFreeDoc(doc); printf("PASS %s\n", argv[1]);
} return 0; }
'''
evidence = Path(tempfile.mkdtemp(prefix='graphink-dependency-regressions-', dir='/private/tmp'))
(evidence / 'Checks.m').write_text(fixture)
# This bundle loads Foundation only; no Omni framework, preference API, app delegate, or event loop.
# The unique main bundle also keeps any Foundation fallback domain away from production domains.
domain = 'invalid.example.graphink.analyzer.fixture.' + uuid.uuid4().hex
contents = evidence / 'Fixture.app/Contents'
(contents / 'MacOS').mkdir(parents=True)
(contents / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': domain, 'CFBundleExecutable': 'Checks', 'CFBundlePackageType': 'APPL'}))
def preferences():
    snapshots = {}
    for domain in ('com.diegomarino.Graphink', 'com.diegomarino.Graphink.MacAppStore'):
        result = subprocess.run(['defaults', 'export', domain, '-'], capture_output=True)
        paths = [Path.home() / 'Library/Preferences' / (domain + '.plist'), Path.home() / 'Library/Containers' / domain / 'Data/Library/Preferences' / (domain + '.plist')]
        paths += sorted((Path.home() / 'Library/Preferences/ByHost').glob(domain + '.*.plist'))
        snapshots[domain] = {'export_status': result.returncode, 'export_sha256': hashlib.sha256(result.stdout).hexdigest(), 'files': {str(path): hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None for path in paths}}
    return snapshots
before = preferences()
(evidence / 'preferences.before.json').write_text(json.dumps(before, indent=2) + '\n')
sdk = subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()
command = ['xcrun', 'clang', '-fno-objc-arc', '-fsanitize=address', '-g', '-isysroot', sdk, '-I' + sdk + '/usr/include/libxml2', '-framework', 'Foundation', '-lxml2', str(evidence / 'Checks.m'), '-o', str(contents / 'MacOS/Checks')]
subprocess.run(command, check=True)
cases = ('canonicalization', 'reference', 'namespace', 'ownership', 'layout') if args.case == 'all' else (args.case,)
failures = []
for case in cases:
    result = subprocess.run([str(contents / 'MacOS/Checks'), case], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (evidence / (case + '.log')).write_text(result.stdout)
    print(result.stdout, end='')
    if result.returncode != 0:
        failures.append(case)
after = preferences()
(evidence / 'preferences.after.json').write_text(json.dumps(after, indent=2) + '\n')
assert before == after, 'Real preference domains changed; inspect retained evidence'
print('PASS unique fixture bundle and real preference domains unchanged')
print(f'Fixture evidence: {evidence}')
assert not failures, f'Failed cases: {failures}; evidence: {evidence}'
