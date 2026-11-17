#!/usr/bin/env python3
"""Run verbatim production method slices with Foundation, ASan and UBSan.

No model/framework initialization, application, controller, preferences, or
LinkBack startup. This checks method behavior, not integrated native acceptance.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile


def method(source, signature):
    start = source.index(signature)
    body = source.index("{", start)
    depth = 1
    end = body + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def main():
    parser = argparse.ArgumentParser(description=__doc__, epilog="Example: python3 Checks/Analyzer/model/check-model.py --output /private/tmp/model-check-evidence")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    output = args.output or Path(tempfile.mkdtemp(prefix="graphink-model-check-"))
    output.mkdir(parents=True, exist_ok=True)
    root = args.root
    importer = (root / "GraphSketcher/Model/RSDataImporter.m").read_text()
    graph = (root / "GraphSketcher/Model/RSGraph.m").read_text()
    number = (root / "GraphSketcher/Model/RSNumber.m").read_text()
    snapping = (root / "GraphSketcher/Model/RSHitTester-Snapping.m").read_text()
    detector_returns_bool = "+ (BOOL)detectColumnTypes:" in importer
    detector_signature = "+ (BOOL)detectColumnTypes:" if detector_returns_bool else "+ (void)detectColumnTypes:"
    code = r'''
#import <Foundation/Foundation.h>
#include <assert.h>
#define DEBUG_RS(...)
#define DEBUG_DATA_IMPORT(...)
#define RS_UNKNOWN_COL 0
#define RS_LABEL_COL 1
#define RS_FLOAT_COL 2
#define RS_DATE_COL 3
#define RS_NM_OF_COL_TYPES 4
#define RSSnapConstraintXKey @"RSSnapConstraintXKey"
#define RSSnapConstraintYKey @"RSSnapConstraintYKey"
typedef struct { double x, y; } RSDataPoint;
static NSUInteger columnTypeForCell(NSString *cell);
static BOOL released;
@interface LifetimeProbe : NSObject @end
@implementation LifetimeProbe
- (void)dealloc { released = YES; [super dealloc]; }
@end
@interface RSDataImporter : NSObject { NSDictionary *_warning; }
@property(retain) NSDictionary *warning;
+ (NSUInteger)numberOfColumnsInTable:(NSArray *)table;
+ (BOOL)detectColumnTypes:(NSArray *)table intoArray:(NSInteger *)types;
+ (BOOL)isABlank:(NSString *)string;
+ (BOOL)isAFloat:(NSString *)string;
+ (BOOL)isADate:(NSString *)string;
+ (BOOL)getDoubleValue:(double *)value forString:(NSString *)string;
+ (NSString *)unadornedString:(NSString *)string;
+ (NSString *)thousandsSeparator;
+ (NSDictionary *)noDataDetectedMessage;
@end
static NSString *_cachedThousandsSeparator;
static NSCharacterSet *numberAdornmentCharacterSet;
static BOOL transposeInput;
@interface OFPreferenceWrapper : NSObject
+ (id)sharedPreferenceWrapper;
- (BOOL)boolForKey:(NSString *)key;
@end
@implementation OFPreferenceWrapper
+ (id)sharedPreferenceWrapper { return [[[self alloc] init] autorelease]; }
- (BOOL)boolForKey:(NSString *)key { assert([key isEqual:@"ImportDataSeriesAsRows"]); return transposeInput; }
@end
@implementation RSDataImporter
@synthesize warning = _warning;
+ (NSDictionary *)noDataDetectedMessage { return @{@"fixture": @"no data"}; }
'''
    for signature in ["+ (NSUInteger)numberOfColumnsInTable:", detector_signature,
                      "+ (BOOL)isABlank:", "+ (BOOL)isAFloat:", "+ (BOOL)isADate:",
                      "+ (BOOL)getDoubleValue:", "+ (NSString *)unadornedString:",
                      "+ (NSString *)thousandsSeparator;"]:
        code += method(importer, signature) + "\n"
    # The missing dealloc is the baseline defect, so leave its absence intact.
    if "- (void)dealloc" in importer:
        code += method(importer, "- (void)dealloc")
    code += method(importer, "- (NSArray *)transposeTable:")
    # The production caller's actual dimensions, allocation, and detection.
    start = importer.index("    // Get stats and initialize some variables")
    end = importer.index("    NSMutableArray *numberColumns", start)
    prefix = importer[start:end]
    code += "\n- (NSArray *)checkTable:(NSArray *)table {\n" + prefix
    code += "\nassert(nmofRows == [table count]);\nassert(nmofCols == [RSDataImporter numberOfColumnsInTable:table]);\nreturn @[@(nmofRows), @(nmofCols)];\n}\n"
    code += "\n@end\n" + method(importer, "static NSUInteger columnTypeForCell(")
    code += r'''
@interface GraphLifetime : NSObject { id _bgColor, _IPs; NSMutableDictionary *_idPasteMap; }
@property(retain) NSMutableDictionary *idPasteMap;
- (void)invalidate;
@end
@implementation GraphLifetime
@synthesize idPasteMap = _idPasteMap;
- (void)invalidate {}
'''
    code += method(graph, "- (void)dealloc")
    code += r'''
@end
@interface RSNumber : NSObject
+ (BOOL)getStrictDoubleValue:(double *)value forString:(NSString *)string;
@end
static NSNumberFormatter *_strictNumberFormatter;
@implementation RSNumber
'''
    code += method(number, "+ (BOOL)getStrictDoubleValue:")
    code += r'''
@end
@interface SnapFixture : NSObject
- (RSDataPoint)applyConstraints:(NSDictionary *)constraints toPoint:(RSDataPoint)p;
@end
@implementation SnapFixture
'''
    code += method(snapping, "- (RSDataPoint)applyConstraints:")
    code += r'''
@end
int main(int argc, const char **argv) {
    @autoreleasepool {
        assert(argc == 2);
        NSString *check = [NSString stringWithUTF8String:argv[1]];
        if ([check isEqual:@"empty-columns"]) {
            NSInteger sentinel = 73;
            for (NSArray *table in @[@[], @[@[]], @[@[], @[]]]) {
                assert(![RSDataImporter detectColumnTypes:table intoArray:&sentinel]);
                assert(sentinel == 73);
            }
            NSInteger types[2] = {-1, -1};
            assert(([RSDataImporter detectColumnTypes:@[@[@"label", @"value"], @[@"a", @"0"], @[@"b", @"2"]] intoArray:types]));
            assert(types[0] == RS_LABEL_COL && types[1] == RS_FLOAT_COL);
        } else if ([check isEqual:@"importer-lifetime"]) {
            RSDataImporter *importer = [[RSDataImporter alloc] init];
            LifetimeProbe *probe = [[LifetimeProbe alloc] init];
            importer.warning = (id)probe;
            [probe release]; [importer release];
            assert(released);
        } else if ([check isEqual:@"paste-map-lifetime"]) {
            GraphLifetime *graph = [[GraphLifetime alloc] init];
            LifetimeProbe *probe = [[LifetimeProbe alloc] init];
            NSMutableDictionary *map = [[NSMutableDictionary alloc] init];
            [map setObject:probe forKey:@"old-id"];
            graph.idPasteMap = map;
            [probe release]; [map release]; [graph release];
            assert(released);
        } else if ([check isEqual:@"zero-presence"]) {
            double value = 17;
            assert([RSNumber getStrictDoubleValue:&value forString:@"0"] && value == 0);
            value = 17;
            assert(![RSNumber getStrictDoubleValue:&value forString:@"no-number"] && value == 17);
            SnapFixture *snap = [[SnapFixture alloc] init];
            RSDataPoint initial = {13, 17};
            RSDataPoint result = [snap applyConstraints:@{RSSnapConstraintXKey:@0} toPoint:initial];
            assert(result.x == 0 && result.y == 17);
            result = [snap applyConstraints:@{RSSnapConstraintYKey:@0} toPoint:initial];
            assert(result.x == 13 && result.y == 0);
            [snap release];
        } else if ([check isEqual:@"rectangular-columns"] || [check isEqual:@"rectangular-rows"]) {
            transposeInput = [check isEqual:@"rectangular-rows"];
            RSDataImporter *importer = [[RSDataImporter alloc] init];
            for (NSArray *table in @[@[@[@"0", @"1"], @[@"2", @"3"], @[@"4", @"5"], @[@"6", @"7"]],
                                    @[@[@"0", @"1", @"2", @"3"], @[@"4", @"5", @"6", @"7"]]]) {
                NSArray *dimensions = [importer checkTable:table];
                assert(dimensions != nil);
            }
            [importer release];
        } else { assert(!"Unknown check"); }
        printf("PASS %s\n", argv[1]);
    }
    return 0;
}
'''
    if not detector_returns_bool:
        # Support the original void contract to reproduce the baseline defects.
        code = code.replace("+ (BOOL)detectColumnTypes:", "+ (void)detectColumnTypes:")
        code = code.replace("assert(![RSDataImporter detectColumnTypes:table intoArray:&sentinel]);",
                            "[RSDataImporter detectColumnTypes:table intoArray:&sentinel];")
        code = code.replace('assert(([RSDataImporter detectColumnTypes:@[@[@"label", @"value"], @[@"a", @"0"], @[@"b", @"2"]] intoArray:types]));',
                            '[RSDataImporter detectColumnTypes:@[@[@"label", @"value"], @[@"a", @"0"], @[@"b", @"2"]] intoArray:types];')
    source = output / "model-methods.m"
    source.write_text(code)
    binary = output / "model-methods"
    subprocess.run(["xcrun", "clang", "-fno-objc-arc", "-g", "-fsanitize=address,undefined",
                    "-fno-sanitize-recover=all", "-framework", "Foundation",
                    str(source), "-o", str(binary)], check=True)
    failed = []
    for check in ["empty-columns", "importer-lifetime", "paste-map-lifetime", "zero-presence",
                  "rectangular-columns", "rectangular-rows"]:
        result = subprocess.run([str(binary), check], text=True, capture_output=True)
        (output / (check + ".log")).write_text(result.stdout + result.stderr)
        print(check, "PASS" if result.returncode == 0 else "FAIL", flush=True)
        if result.returncode:
            failed.append(check)
    print("Evidence:", output)
    return bool(failed)


if __name__ == "__main__":
    raise SystemExit(main())
