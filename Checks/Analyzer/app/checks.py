#!/usr/bin/env python3
"""Run extracted production method contracts without loading the application."""
import argparse
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
args.output.mkdir(parents=True, exist_ok=False)

def method(file, signature):
    text = (root / "GraphSketcher/App" / file).read_text()
    start = text.index(signature)
    opening = text.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end]

# Keep the model's production equation enum and structure in the fixture.
equations = (root / "GraphSketcher/Model/RSEquationLine.h").read_text()
equations = equations[equations.index("typedef enum"):equations.index("RSEquation RSEquationZero")]

copy_method = method("GraphDocument.m", "- (IBAction)copyAsImageWithPasteboard:")
linkback = copy_method[copy_method.index("        // Even on error"):copy_method.index("\n    }", copy_method.index("        // Even on error"))]

source = r'''#import <Foundation/Foundation.h>
#include <ctype.h>
#define RS_none 0
#define RS_draw 2
#define RS_fill 3
#define RS_HOTKEY_DRAW 'd'
#define RS_HOTKEY_FILL 'f'
#define DEBUG_RS(...) do {} while (0)
typedef double data_p;
''' + equations + r'''
static RSEquation addedEquation;
@interface NSObject (GraphContract)
- (void)addLine:(id)line;
- (NSInteger)tag;
@end
@interface RSEquationLine : NSObject
- (id)initWithGraph:(id)graph identifier:(id)identifier equation:(RSEquation)equation;
@end
@implementation RSEquationLine
- (id)initWithGraph:(id)graph identifier:(id)identifier equation:(RSEquation)equation {
    self = [super init]; addedEquation = equation; return self;
}
@end
@interface EquationFixture : NSObject { id _graph; }
- (void)setSelection:(id)value;
@end
@implementation EquationFixture
- (void)setSelection:(id)value {}
''' + method("RSGraphView.m", "- (IBAction)addEquationLine:") + r'''
@end
@interface MenuFixture : NSObject
@property(nonatomic) NSInteger tag;
- (NSString *)title;
@end
@implementation MenuFixture
@synthesize tag;
- (NSString *)title { return @"Translated title without formula"; }
@end
static NSString * const OGSLinkBackServerName = @"fixture-server";
static NSString * const LinkBackPboardType = @"fixture-linkback";
@interface NSDictionary (LinkBackContract)
+ (NSDictionary *)linkBackDataWithServerName:(NSString *)server appData:(NSData *)data;
@end
@implementation NSDictionary (LinkBackContract)
+ (NSDictionary *)linkBackDataWithServerName:(NSString *)server appData:(NSData *)data {
    return @{@"server": server, @"data": data};
}
@end
@interface PasteboardFixture : NSObject
@property(nonatomic, retain) id value;
- (BOOL)setPropertyList:(id)value forType:(NSString *)type;
- (BOOL)setData:(NSData *)data forType:(NSString *)type;
@end
@implementation PasteboardFixture
@synthesize value;
- (BOOL)setPropertyList:(id)newValue forType:(NSString *)type {
    NSCAssert(newValue != nil, @"Property list API requires nonnull payload"); self.value = newValue; return YES;
}
- (BOOL)setData:(NSData *)data forType:(NSString *)type { self.value = data; return YES; }
- (void)dealloc { [value release]; [super dealloc]; }
@end
static void WriteLinkBack(PasteboardFixture *pb, NSData *documentXMLData) {
''' + linkback + r'''
}
static NSUInteger destroyed;
@interface Sentinel : NSObject @end
@implementation Sentinel
- (void)dealloc { destroyed++; [super dealloc]; }
@end
@interface GraphViewFixture : NSObject {
    id _halfSelectionLayer, _penCursor, _fillCursor;
@public
    id _textSnapshot;
}
@property(nonatomic, assign) id editor;
- (void)setRSSelector:(id)value;
@end
@implementation GraphViewFixture
- (void)setRSSelector:(id)value {}
@synthesize editor;
''' + method("RSGraphView.m", "- (void)dealloc") + r'''
@end
@interface ModifyFixture : NSObject {
    id _movers, _vertexCluster;
@public
    id _originalSelection;
}
@end
@implementation ModifyFixture
''' + method("RSModifyTool.m", "- (void)dealloc") + r'''
@end
@interface OpacityFixture : NSObject { @public id _color; } @end
@implementation OpacityFixture
''' + (method("OpacityControlCell.m", "- (void)dealloc") if "- (void)dealloc" in (root / "GraphSketcher/App/OpacityControlCell.m").read_text() else "") + r'''
@end
@interface Section : NSObject
@property(nonatomic, copy) NSString *inspectorIdentifier;
@end
@implementation Section
@synthesize inspectorIdentifier;
- (void)dealloc { [inspectorIdentifier release]; [super dealloc]; }
@end
#define OIInspectorTabController Section
@interface SidebarFixture : NSObject { @public NSArray *_sections; }
@end
@implementation SidebarFixture
''' + method("RSInspectorSidebar.m", "- (" + ("nullable " if "- (nullable OIInspectorTabController" in (root / "GraphSketcher/App/RSInspectorSidebar.m").read_text() else "") + "OIInspectorTabController *") + r'''
@end
''' + method("RSMode.m", "static NSUInteger modeFromChar") + r'''
int main(void) {
    @autoreleasepool {
        PasteboardFixture *pb = [PasteboardFixture new];
        NSData *xml = [@"fixture XML" dataUsingEncoding:NSUTF8StringEncoding];
        WriteLinkBack(pb, xml);
        NSCAssert([pb.value[@"data"] isEqual:xml], @"Successful XML payload changed");
        WriteLinkBack(pb, nil);
        NSCAssert(pb.value == nil, @"Failed XML must clear announced LinkBack payload");
        [pb release];
        EquationFixture *graph = [EquationFixture new];
        MenuFixture *menu = [MenuFixture new];
        for (NSInteger type = RSEquationTypeSquare; type <= RSEquationTypeLogistic; type++) {
            menu.tag = type;
            [graph addEquationLine:menu];
            NSCAssert(addedEquation.type == type && addedEquation.a == 0 && addedEquation.b == 0 && addedEquation.c == 1, @"Equation action depended on localized title for type %ld", type);
        }
        [menu release]; [graph release];
        GraphViewFixture *view = [GraphViewFixture new];
        view->_textSnapshot = [Sentinel new];
        [view release];
        NSCAssert(destroyed == 1, @"Text snapshot survived graph view destruction");
        ModifyFixture *tool = [ModifyFixture new];
        tool->_originalSelection = [Sentinel new];
        [tool release];
        NSCAssert(destroyed == 2, @"Original selection survived tool destruction");
        OpacityFixture *cell = [OpacityFixture new];
        cell->_color = [Sentinel new];
        [cell release];
        NSCAssert(destroyed == 3, @"Color survived cell destruction");
        Section *section = [Section new]; section.inspectorIdentifier = @"style";
        SidebarFixture *sidebar = [SidebarFixture new]; sidebar->_sections = @[section];
        NSCAssert([sidebar tabWithIdentifier:@"style"] == section, @"Known section lookup failed");
        NSCAssert([sidebar tabWithIdentifier:@"missing"] == nil, @"Unknown section must remain absent");
        sidebar->_sections = @[];
        NSCAssert([sidebar tabWithIdentifier:@"style"] == nil, @"Empty sidebar must return nil");
        [sidebar release]; [section release];
        for (unsigned ch = 0; ch <= 0xffff; ch++) {
            NSUInteger expected = ch == 'd' || ch == 'D' ? RS_draw : ch == 'f' || ch == 'F' ? RS_fill : RS_none;
            NSCAssert(modeFromChar((unichar)ch) == expected, @"Unexpected hotkey mapping: %u", ch);
        }
        puts("PASS: LinkBack success/error payload contracts; all five equation actions independent of localized titles; three retained ivars released; known/missing/empty section lookup; all UTF-16 hotkey inputs");
    }
    return 0;
}
'''
fixture = args.output / "Contracts.m"
fixture.write_text(source)
subprocess.run(["xcrun", "clang", "-fno-objc-arc", "-fobjc-exceptions", "-g", "-fsanitize=address", "-framework", "Foundation", str(fixture), "-o", str(args.output / "contracts")], check=True)
subprocess.run([str(args.output / "contracts")], check=True)
