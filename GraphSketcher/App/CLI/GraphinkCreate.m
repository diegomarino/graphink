// graphink create: build a Graphink document from a small JSON spec (skills/graphink/references/spec.md) with the production
// model, save it with the production OPC writer, then reopen it with the production reader to check it.
#import "GraphinkCLI.h"
#import <GraphSketcherModel/RSGraphArchive.h>
#import <GraphSketcherModel/RSGraphRenderer.h>
#import <GraphSketcherModel/RSDataMapper.h>
#import <GraphSketcherModel/RSHitTester-Snapping.h>
#import <GraphSketcherModel/RSUndoer.h>
#import <GraphSketcherModel/RSVertex.h>
#import <GraphSketcherModel/RSConnectLine.h>
#import <GraphSketcherModel/RSGroup.h>
#import <GraphSketcherModel/RSFill.h>
#import <GraphSketcherModel/RSTextLabel.h>
#import "RSStylePresets.h"

#pragma mark Spec reading

// Every value is read through a path, so an error names the exact place in the spec ("objects[3].points[2]").
static NSString *Describe(id value)
{
    if (!value) return @"nothing";
    if ([value isKindOfClass:NSString.class]) return @"a string";
    if ([value isKindOfClass:NSArray.class]) return @"a list";
    if ([value isKindOfClass:NSDictionary.class]) return @"an object";
    if (CFGetTypeID((CFTypeRef)value) == CFBooleanGetTypeID()) return @"true/false";
    return @"a number";
}
static BOOL IsBool(id value) { return value && CFGetTypeID((CFTypeRef)value) == CFBooleanGetTypeID(); }
static BOOL IsNumber(id value) { return [value isKindOfClass:NSNumber.class] && !IsBool(value); }

static void Keys(NSDictionary *object, NSString *path, NSArray *allowed)
{
    for (NSString *key in object)
        if (![allowed containsObject:key])
            GICFail(@"%@: unknown key \"%@\" (allowed: %@)", path, key, [allowed componentsJoinedByString:@", "]);
}
static NSString *Join(NSString *path, id key)
{
    return [key isKindOfClass:NSNumber.class] ? [NSString stringWithFormat:@"%@[%@]", path, key] : (path.length ? [NSString stringWithFormat:@"%@.%@", path, key] : key);
}
static id Value(NSDictionary *object, NSString *key, Class cls, NSString *path, BOOL required)
{
    id value = object[key];
    if (!value) { if (required) GICFail(@"%@: \"%@\" is required", path, key); return nil; }
    if (![value isKindOfClass:cls] || (cls == NSNumber.class && !IsNumber(value)))
        GICFail(@"%@ must be %@, not %@", Join(path, key), Describe(cls == NSNumber.class ? @0 : cls == NSString.class ? @"" : cls == NSArray.class ? @[] : @{}), Describe(value));
    return value;
}
static double Number(NSDictionary *object, NSString *key, NSString *path, double fallback)
{
    NSNumber *value = Value(object, key, NSNumber.class, path, NO);
    if (value == nil) return fallback;
    if (!isfinite(value.doubleValue)) GICFail(@"%@ must be finite", Join(path, key));
    return value.doubleValue;
}
static double RequiredNumber(NSDictionary *object, NSString *key, NSString *path)
{
    Value(object, key, NSNumber.class, path, YES);
    return Number(object, key, path, 0);
}
static BOOL Bool(NSDictionary *object, NSString *key, NSString *path, BOOL fallback)
{
    id value = object[key];
    if (!value) return fallback;
    if (!IsBool(value)) GICFail(@"%@ must be true or false, not %@", Join(path, key), Describe(value));
    return [value boolValue];
}
static NSString *Choice(NSDictionary *object, NSString *key, NSString *path, NSArray *choices, NSString *fallback)
{
    NSString *value = Value(object, key, NSString.class, path, NO);
    if (!value) return fallback;
    if (![choices containsObject:value]) GICFail(@"%@ must be one of %@, not \"%@\"", Join(path, key), [choices componentsJoinedByString:@", "], value);
    return value;
}
static RSDataPoint ReadPoint(id value, NSString *path)
{
    if (![value isKindOfClass:NSArray.class] || [value count] < 2 || !IsNumber(value[0]) || !IsNumber(value[1]))
        GICFail(@"%@ must be a point [x, y], not %@", path, Describe(value));
    double x = [value[0] doubleValue], y = [value[1] doubleValue];
    if (!isfinite(x) || !isfinite(y)) GICFail(@"%@ must be finite", path);
    return RSDataPointMake(x, y);
}

#pragma mark Colors and text

static NSColor *Hex(unsigned rgb, CGFloat alpha)
{
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 255)/255.0 green:((rgb >> 8) & 255)/255.0 blue:(rgb & 255)/255.0 alpha:alpha];
}
// The example catalog's palette (Examples/Tools/GenerateCatalog.m), so created graphs match the bundled ones.
static NSDictionary *Palette(void)
{
    return @{@"ink":Hex(0x1F2E3D, 1), @"blue":Hex(0x1F61A8, 1), @"teal":Hex(0x087863, 1), @"orange":Hex(0xB84F14, 1),
             @"purple":Hex(0x7D4A9E, 1), @"red":Hex(0xB3261E, 1), @"green":Hex(0x2E7D32, 1), @"gray":Hex(0x808C99, 1),
             @"guide":Hex(0x808C99, 1), @"black":Hex(0x000000, 1), @"white":Hex(0xFFFFFF, 1)};
}
static NSColor *Color(NSDictionary *object, NSString *key, NSString *path, NSColor *fallback)
{
    NSString *value = Value(object, key, NSString.class, path, NO);
    if (!value) return fallback;
    NSColor *named = Palette()[value.lowercaseString];
    if (named) return named;
    NSScanner *scanner = [NSScanner scannerWithString:value];
    unsigned long long hex = 0;
    if ([value hasPrefix:@"#"] && (value.length == 7 || value.length == 9)) {
        scanner.scanLocation = 1;
        if ([scanner scanHexLongLong:&hex] && scanner.isAtEnd)
            return value.length == 7 ? Hex((unsigned)hex, 1) : Hex((unsigned)(hex >> 8), (hex & 255)/255.0);
    }
    GICFail(@"%@ must be #RRGGBB, #RRGGBBAA or one of %@, not \"%@\"", Join(path, key),
            [[Palette().allKeys sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "], value);
    return nil;
}

static NSAttributedString *Text(NSString *string, CGFloat size, BOOL bold, NSColor *color)
{
    NSFont *font = [NSFont fontWithName:bold ? @"HelveticaNeue-Medium" : @"HelveticaNeue" size:size];
    if (!font) GICFail(@"The Helvetica Neue system font is not available");
    return [[[NSAttributedString alloc] initWithString:string attributes:@{NSFontAttributeName:font, NSForegroundColorAttributeName:color}] autorelease];
}

#pragma mark Function expressions

// A small recursive-descent evaluator: numbers, x, pi, e, + - * / ^ (right-associative), unary minus,
// parentheses and sin cos tan asin acos atan sinh cosh tanh exp ln log log2 sqrt abs floor ceil.
typedef struct { const char *s; size_t i; NSString *error; } Parser;
static double Expression(Parser *p, double x);
static void Space(Parser *p) { while (p->s[p->i] == ' ' || p->s[p->i] == '\t') p->i++; }
static double Primary(Parser *p, double x)
{
    Space(p);
    char c = p->s[p->i];
    if (c == '(') {
        p->i++; double v = Expression(p, x); Space(p);
        if (p->s[p->i] != ')') { p->error = @"missing )"; return NAN; }
        p->i++; return v;
    }
    if (isdigit((unsigned char)c) || c == '.') {
        char *end = NULL; double v = strtod(p->s + p->i, &end);
        if (end == p->s + p->i) { p->error = @"bad number"; return NAN; }
        p->i = end - p->s; return v;
    }
    if (isalpha((unsigned char)c)) {
        size_t start = p->i;
        while (isalnum((unsigned char)p->s[p->i])) p->i++;
        NSString *name = [[[NSString alloc] initWithBytes:p->s + start length:p->i - start encoding:NSASCIIStringEncoding] autorelease];
        if ([name isEqual:@"x"]) return x;
        if ([name isEqual:@"pi"]) return M_PI;
        if ([name isEqual:@"e"]) return M_E;
        static NSDictionary *functions;
        if (!functions) functions = [@{@"sin":[NSValue valueWithPointer:(void *)sin], @"cos":[NSValue valueWithPointer:(void *)cos], @"tan":[NSValue valueWithPointer:(void *)tan],
            @"asin":[NSValue valueWithPointer:(void *)asin], @"acos":[NSValue valueWithPointer:(void *)acos], @"atan":[NSValue valueWithPointer:(void *)atan],
            @"sinh":[NSValue valueWithPointer:(void *)sinh], @"cosh":[NSValue valueWithPointer:(void *)cosh], @"tanh":[NSValue valueWithPointer:(void *)tanh],
            @"exp":[NSValue valueWithPointer:(void *)exp], @"ln":[NSValue valueWithPointer:(void *)log], @"log":[NSValue valueWithPointer:(void *)log10],
            @"log2":[NSValue valueWithPointer:(void *)log2], @"sqrt":[NSValue valueWithPointer:(void *)sqrt], @"abs":[NSValue valueWithPointer:(void *)fabs],
            @"floor":[NSValue valueWithPointer:(void *)floor], @"ceil":[NSValue valueWithPointer:(void *)ceil]} retain];
        double (*function)(double) = (double (*)(double))[functions[name] pointerValue];
        if (!function) { p->error = [NSString stringWithFormat:@"unknown name \"%@\" (use x, pi, e and %@)", name, [[functions.allKeys sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "]]; return NAN; }
        Space(p);
        if (p->s[p->i] != '(') { p->error = [NSString stringWithFormat:@"%@ needs parentheses: %@(...)", name, name]; return NAN; }
        return function(Primary(p, x));
    }
    p->error = c ? [NSString stringWithFormat:@"unexpected \"%c\"", c] : @"unexpected end";
    return NAN;
}
static double Unary(Parser *p, double x);
static double Power(Parser *p, double x)
{
    double base = Primary(p, x); Space(p);
    if (p->s[p->i] == '^') { p->i++; return pow(base, Unary(p, x)); }
    return base;
}
static double Unary(Parser *p, double x)
{
    Space(p);
    if (p->s[p->i] == '-') { p->i++; return -Unary(p, x); }
    if (p->s[p->i] == '+') { p->i++; return Unary(p, x); }
    return Power(p, x);
}
static double Term(Parser *p, double x)
{
    double v = Unary(p, x);
    for (;;) {
        Space(p); char c = p->s[p->i];
        if (c == '*') { p->i++; v *= Unary(p, x); }
        else if (c == '/') { p->i++; v /= Unary(p, x); }
        else return v;
    }
}
static double Expression(Parser *p, double x)
{
    double v = Term(p, x);
    for (;;) {
        Space(p); char c = p->s[p->i];
        if (c == '+') { p->i++; v += Term(p, x); }
        else if (c == '-') { p->i++; v -= Term(p, x); }
        else return v;
    }
}
static double Evaluate(NSString *formula, double x, NSString *path)
{
    Parser p = {formula.UTF8String, 0, nil};
    double v = Expression(&p, x); Space(&p);
    if (!p.error && p.s[p.i]) p.error = [NSString stringWithFormat:@"unexpected \"%s\"", p.s + p.i];
    if (p.error) GICFail(@"%@: cannot read \"%@\": %@", path, formula, p.error);
    return v;
}

#pragma mark Building

@interface Builder : NSObject
{
@public
    GICDocument *document;
    RSGraph *g;
    NSMutableDictionary *points;  // shared vertices by exact coordinate, as the example generator shares them
    NSColor *ink;
    NSMutableArray *pending;  // owned labels, positioned once the layout is final: @[owner, attributed string, slide or NSNull]
    NSMutableArray *pageLabels;  // @[label, page point, alignment]
    NSUInteger arrows;
}
@end
@implementation Builder
- (void)dealloc { [points release]; [pending release]; [pageLabels release]; [super dealloc]; }
@end

static RSVertex *Vertex(Builder *b, RSDataPoint p, BOOL shared)
{
    NSString *key = [NSString stringWithFormat:@"%.17g,%.17g", p.x, p.y];
    RSVertex *v = shared ? b->points[key] : nil;
    if (!v) {
        v = [[[RSVertex alloc] initWithGraph:b->g identifier:nil point:p width:1.8 color:b->ink shape:RS_NONE] autorelease];
        [b->g addVertex:v];
        if (shared) b->points[key] = v;
    }
    return v;
}
static NSValue *Boxed(RSDataPoint p) { return [NSValue valueWithBytes:&p objCType:@encode(RSDataPoint)]; }
static RSDataPoint Unboxed(NSValue *v) { RSDataPoint p; [v getValue:&p]; return p; }
static RSGroup *Group(Builder *b, NSArray *coordinates, BOOL shareEnds, BOOL shareAll)
{
    NSMutableArray *vertices = [NSMutableArray array];
    [coordinates enumerateObjectsUsingBlock:^(NSValue *p, NSUInteger i, BOOL *stop) {
        BOOL end = i == 0 || i + 1 == coordinates.count;
        [vertices addObject:Vertex(b, Unboxed(p), shareAll && (!end || shareEnds))];
    }];
    return [[[RSGroup alloc] initWithGraph:b->g byCopyingArray:vertices] autorelease];
}

static NSDictionary *Shapes(void)
{
    return @{@"none":@RS_NONE, @"circle":@RS_CIRCLE, @"triangle":@RS_TRIANGLE, @"square":@RS_SQUARE, @"star":@RS_STAR,
             @"diamond":@RS_DIAMOND, @"x":@RS_X, @"cross":@RS_CROSS, @"hollow":@RS_HOLLOW};
}
static NSDictionary *Dashes(void)
{
    // RSGraphRenderer -applyDashStyleForLine:toPath:.
    return @{@"solid":@0, @"dotted":@2, @"short-dash":@3, @"dashed":@4, @"long-dash":@5, @"dash-dot":@6};
}

// A label spec: "text" or {"text", "size", "bold", "color", "position"}; position is 0-1 along a line.
static void OwnedLabel(Builder *b, RSGraphElement *owner, id spec, NSString *path, NSColor *color, BOOL alongLine)
{
    if (!spec) return;
    NSDictionary *object = [spec isKindOfClass:NSString.class] ? @{@"text":spec} : spec;
    if (![object isKindOfClass:NSDictionary.class]) GICFail(@"%@ must be a string or an object, not %@", path, Describe(spec));
    Keys(object, path, alongLine ? @[@"text", @"size", @"bold", @"color", @"position"] : @[@"text", @"size", @"bold", @"color"]);
    NSString *text = Value(object, @"text", NSString.class, path, YES);
    double slide = Number(object, @"position", path, 0.5);
    if (slide < 0 || slide > 1) GICFail(@"%@.position must be between 0 and 1", path);
    NSAttributedString *string = Text(text, Number(object, @"size", path, 15), Bool(object, @"bold", path, YES), Color(object, @"color", path, color));
    [b->pending addObject:@[owner, string, alongLine ? @(slide) : NSNull.null]];
}

// The area centroid of a simple polygon (the vertex mean when the area is zero).
static RSDataPoint Centroid(NSArray *list)
{
    double area = 0, cx = 0, cy = 0, mx = 0, my = 0;
    for (NSUInteger i = 0; i < list.count; i++) {
        RSDataPoint p = Unboxed(list[i]), q = Unboxed(list[(i + 1) % list.count]);
        double cross = p.x * q.y - q.x * p.y;
        area += cross; cx += (p.x + q.x) * cross; cy += (p.y + q.y) * cross; mx += p.x; my += p.y;
    }
    if (fabs(area) < 1e-12) return RSDataPointMake(mx / list.count, my / list.count);
    return RSDataPointMake(cx / (3 * area), cy / (3 * area));
}

static NSArray *PointList(id value, NSString *path, NSUInteger minimum, NSMutableArray *names)
{
    if (![value isKindOfClass:NSArray.class]) GICFail(@"%@ must be a list of points [[x, y], ...], not %@", path, Describe(value));
    NSMutableArray *list = [NSMutableArray array];
    [value enumerateObjectsUsingBlock:^(id p, NSUInteger i, BOOL *stop) {
        NSString *at = Join(path, @(i));
        [list addObject:Boxed(ReadPoint(p, at))];
        if ([p count] > 2) {
            if (!names || [p count] > 3 || ![p[2] isKindOfClass:NSString.class]) GICFail(@"%@ must be [x, y]%@", at, names ? @" or [x, y, \"label\"]" : @"");
            [names addObject:p[2]];
        } else if (names) [names addObject:NSNull.null];
    }];
    if (list.count < minimum) GICFail(@"%@ needs at least %lu points", path, (unsigned long)minimum);
    return list;
}

// "csv": text with one row per line, comma, semicolon or tab separated; rows that are not all numbers are skipped
// (headers, notes). "columns": [x column, y column] by index (0-based) or header name.
static NSArray *CSVPoints(NSDictionary *object, NSString *path)
{
    NSString *csv = Value(object, @"csv", NSString.class, path, YES);
    NSArray *columns = Value(object, @"columns", NSArray.class, path, NO) ?: @[@0, @1];
    if (columns.count != 2) GICFail(@"%@.columns must be [x, y]", path);
    NSInteger index[2] = {-1, -1};
    NSArray *header = nil;
    NSMutableArray *list = [NSMutableArray array];
    NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@",;\t"];
    for (NSString *line in [csv componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        if (![line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length) continue;
        NSMutableArray *cells = [NSMutableArray array];
        for (NSString *cell in [line componentsSeparatedByCharactersInSet:separators])
            [cells addObject:[cell stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" \t\""]]];
        // The first row names the columns when "columns" uses names; it is never data.
        BOOL headerRow = NO;
        for (int k = 0; k < 2; k++) {
            if (index[k] >= 0) continue;
            id column = columns[k];
            if (IsNumber(column) && [column integerValue] >= 0) index[k] = [column integerValue];
            else if ([column isKindOfClass:NSString.class]) {
                if (!header) header = cells;
                headerRow = YES;
                index[k] = [header indexOfObject:column];
                if (index[k] == NSNotFound) GICFail(@"%@: no column named \"%@\" in the first row (%@)", path, column, [header componentsJoinedByString:@", "]);
            }
            else GICFail(@"%@.columns entries must be column numbers (from 0) or header names", path);
        }
        if (headerRow) continue;
        if ((NSUInteger)MAX(index[0], index[1]) >= cells.count) continue;
        char *end = NULL; double x = strtod([cells[index[0]] UTF8String], &end); BOOL ok = end && !*end && [cells[index[0]] length];
        double y = strtod([cells[index[1]] UTF8String], &end); ok = ok && end && !*end && [cells[index[1]] length];
        if (ok && isfinite(x) && isfinite(y)) [list addObject:Boxed(RSDataPointMake(x, y))];
    }
    if (!list.count) GICFail(@"%@.csv has no numeric rows in columns %@", path, [columns componentsJoinedByString:@", "]);
    return list;
}

static RSConnectLine *Line(Builder *b, NSArray *coordinates, NSDictionary *object, NSString *path, NSColor *color, BOOL shared, NSString *connect)
{
    double width = Number(object, @"width", path, 2.6);
    if (width <= 0) GICFail(@"%@.width must be positive", path);
    NSInteger dash = [Dashes()[Choice(object, @"dash", path, [Dashes().allKeys sortedArrayUsingSelector:@selector(compare:)], @"solid")] integerValue];
    NSString *arrow = Choice(object, @"arrow", path, @[@"none", @"start", @"end", @"both"], @"none");
    BOOL arrowStart = [arrow isEqual:@"start"] || [arrow isEqual:@"both"], arrowEnd = [arrow isEqual:@"end"] || [arrow isEqual:@"both"];
    // An arrowhead belongs to one line: its end vertex is never shared.
    NSMutableArray *vertices = [NSMutableArray array];
    [coordinates enumerateObjectsUsingBlock:^(NSValue *p, NSUInteger i, BOOL *stop) {
        BOOL arrowed = (i == 0 && arrowStart) || (i + 1 == coordinates.count && arrowEnd);
        [vertices addObject:Vertex(b, Unboxed(p), shared && !arrowed)];
    }];
    RSGroup *group = [[[RSGroup alloc] initWithGraph:b->g byCopyingArray:vertices] autorelease];
    RSConnectLine *line = [[[RSConnectLine alloc] initWithGraph:b->g identifier:nil vertices:group color:color width:width dash:dash slide:0.5 labelDistance:4] autorelease];
    line.connectMethod = [connect isEqual:@"curved"] ? RSConnectCurved : RSConnectStraight;
    [b->g addLine:line];
    if (arrowStart) [b->document.editor changeArrowhead:RS_ARROW forElement:line isLeft:YES];
    if (arrowEnd) [b->document.editor changeArrowhead:RS_ARROW forElement:line isLeft:NO];
    b->arrows += arrowStart + arrowEnd;
    return line;
}

static void ApplyMarker(Builder *b, RSVertex *v, NSDictionary *object, NSString *path, NSString *shapeKey, NSString *fallback, NSColor *color)
{
    v.shape = [Shapes()[Choice(object, shapeKey, path, [Shapes().allKeys sortedArrayUsingSelector:@selector(compare:)], fallback)] integerValue];
    double size = Number(object, @"size", path, 1.8);
    if (size <= 0) GICFail(@"%@.size must be positive", path);
    v.width = size;
    v.color = color;
}

static void AddObject(Builder *b, NSDictionary *object, NSString *path)
{
    NSString *type = Choice(object, @"type", path, @[@"line", @"function", @"series", @"point", @"fill", @"bars", @"label"], nil);
    if (!type) GICFail(@"%@: \"type\" is required (line, function, series, point, fill, bars or label)", path);
    BOOL shared = Bool(object, @"shared", path, YES);
    NSColor *color = Color(object, @"color", path, nil);
    if ([type isEqual:@"line"]) {
        Keys(object, path, @[@"type", @"points", @"color", @"width", @"dash", @"curve", @"arrow", @"label", @"shared"]);
        NSString *connect = Choice(object, @"curve", path, @[@"straight", @"curved"], @"straight");
        RSConnectLine *line = Line(b, PointList(object[@"points"], Join(path, @"points"), 2, nil), object, path, color ?: Palette()[@"blue"], shared, connect);
        OwnedLabel(b, line, object[@"label"], Join(path, @"label"), line.color, YES);
    }
    else if ([type isEqual:@"function"]) {
        Keys(object, path, @[@"type", @"f", @"from", @"to", @"samples", @"color", @"width", @"dash", @"label", @"shared"]);
        NSString *formula = Value(object, @"f", NSString.class, path, YES);
        double from = RequiredNumber(object, @"from", path), to = RequiredNumber(object, @"to", path);
        double samples = Number(object, @"samples", path, 201);
        if (!(to > from)) GICFail(@"%@: \"to\" must be greater than \"from\"", path);
        if (samples < 2 || samples > 5000 || samples != floor(samples)) GICFail(@"%@.samples must be a whole number from 2 to 5000", path);
        // Straight segments through samples: never the curved connection, which can invent extrema between them.
        // Points where f is not finite (or leaves the y range by far) split the curve into pieces.
        double span = b->g.yAxis.max - b->g.yAxis.min;
        BOOL xLog = b->g.xAxis.axisType == RSAxisTypeLogarithmic, yLog = b->g.yAxis.axisType == RSAxisTypeLogarithmic;
        if (xLog && from <= 0) GICFail(@"%@.from must be above 0 on a logarithmic x axis", path);
        NSMutableArray *pieces = [NSMutableArray arrayWithObject:[NSMutableArray array]];
        for (NSUInteger i = 0; i < (NSUInteger)samples; i++) {
            double x = from + (to - from) * i / (samples - 1), y = Evaluate(formula, x, Join(path, @"f"));
            // On a logarithmic axis the renderer draws nothing of a line that goes below the axis minimum.
            BOOL inside = yLog ? y >= b->g.yAxis.min && y < b->g.yAxis.max * 1e10 : y > b->g.yAxis.min - 10 * span && y < b->g.yAxis.max + 10 * span;
            if (isfinite(y) && inside) [pieces.lastObject addObject:Boxed(RSDataPointMake(x, y))];
            else if ([pieces.lastObject count]) [pieces addObject:[NSMutableArray array]];
        }
        RSConnectLine *first = nil;
        for (NSArray *piece in pieces) {
            if (piece.count < 2) continue;
            RSConnectLine *line = Line(b, piece, object, path, color ?: Palette()[@"blue"], shared, @"straight");
            if (!first) first = line;
        }
        if (!first) GICFail(@"%@: f has fewer than two finite points between %g and %g", path, from, to);
        OwnedLabel(b, first, object[@"label"], Join(path, @"label"), first.color, YES);
    }
    else if ([type isEqual:@"series"]) {
        Keys(object, path, @[@"type", @"points", @"csv", @"columns", @"connect", @"marker", @"size", @"color", @"width", @"dash", @"label", @"labels", @"shared"]);
        NSMutableArray *names = [NSMutableArray array];
        NSArray *list;
        if (object[@"points"] && object[@"csv"]) GICFail(@"%@: give \"points\" or \"csv\", not both", path);
        if (object[@"csv"]) list = CSVPoints(object, path);
        else list = PointList(object[@"points"], Join(path, @"points"), 1, names);
        NSString *connect = Choice(object, @"connect", path, @[@"none", @"straight", @"curved"], @"none");
        NSColor *seriesColor = color ?: Palette()[@"blue"];
        NSMutableArray *vertices = [NSMutableArray array];
        if ([connect isEqual:@"none"]) {
            for (NSValue *p in list) [vertices addObject:Vertex(b, Unboxed(p), shared)];
            if (object[@"label"]) GICFail(@"%@.label names a connected line; for unconnected points use \"labels\" or a label object", path);
        } else {
            if (list.count < 2) GICFail(@"%@: a connected series needs at least two points", path);
            RSConnectLine *line = Line(b, list, object, path, seriesColor, shared, connect);
            [vertices addObjectsFromArray:line.vertices.elements];
            OwnedLabel(b, line, object[@"label"], Join(path, @"label"), seriesColor, YES);
        }
        NSString *defaultMarker = [connect isEqual:@"none"] ? @"circle" : @"none";
        for (RSVertex *v in vertices) ApplyMarker(b, v, object, path, @"marker", defaultMarker, seriesColor);
        NSArray *labels = Value(object, @"labels", NSArray.class, path, NO);
        if (labels && labels.count != vertices.count) GICFail(@"%@.labels has %lu entries for %lu points", path, (unsigned long)labels.count, (unsigned long)vertices.count);
        for (NSUInteger i = 0; i < vertices.count; i++) {
            id name = labels ? labels[i] : (i < names.count ? names[i] : NSNull.null);
            if (name != NSNull.null) OwnedLabel(b, vertices[i], name, Join(Join(path, labels ? @"labels" : @"points"), @(i)), Palette()[@"ink"], NO);
        }
    }
    else if ([type isEqual:@"point"]) {
        Keys(object, path, @[@"type", @"at", @"marker", @"size", @"color", @"label", @"shared"]);
        RSVertex *v = Vertex(b, ReadPoint(object[@"at"], Join(path, @"at")), shared);
        ApplyMarker(b, v, object, path, @"marker", @"circle", color ?: b->ink);
        OwnedLabel(b, v, object[@"label"], Join(path, @"label"), b->ink, NO);
    }
    else if ([type isEqual:@"fill"]) {
        Keys(object, path, @[@"type", @"points", @"color", @"opacity", @"label", @"shared"]);
        double opacity = Number(object, @"opacity", path, 0.17);
        if (opacity <= 0 || opacity > 1) GICFail(@"%@.opacity must be in (0, 1]", path);
        NSColor *fillColor = [color ?: Palette()[@"blue"] colorWithAlphaComponent:opacity];
        NSArray *list = PointList(object[@"points"], Join(path, @"points"), 3, nil);
        RSFill *fill = [[[RSFill alloc] initWithGraph:b->g identifier:nil vertexGroup:Group(b, list, YES, shared) color:fillColor placement:CGPointMake(.5, .5)] autorelease];
        [b->g addFill:fill];
        // A fill's name is a free label centered on the region (an owned fill label sits on its edge).
        id spec = object[@"label"];
        if (spec) {
            NSString *at = Join(path, @"label");
            NSDictionary *label = [spec isKindOfClass:NSString.class] ? @{@"text":spec} : spec;
            if (![label isKindOfClass:NSDictionary.class]) GICFail(@"%@ must be a string or an object, not %@", at, Describe(spec));
            Keys(label, at, @[@"text", @"size", @"bold", @"color", @"at"]);
            RSDataPoint center = label[@"at"] ? ReadPoint(label[@"at"], Join(at, @"at")) : Centroid(list);
            RSTextLabel *text = [[[RSTextLabel alloc] initWithGraph:b->g identifier:nil attributedString:Text(Value(label, @"text", NSString.class, at, YES),
                Number(label, @"size", at, 15), Bool(label, @"bold", at, YES), Color(label, @"color", at, [color ?: Palette()[@"blue"] colorWithAlphaComponent:1])) position:center rotation:0] autorelease];
            [b->g addLabel:text];
            [b->pageLabels addObject:@[text, Boxed(center), @"centroid"]];
        }
    }
    else if ([type isEqual:@"bars"]) {
        Keys(object, path, @[@"type", @"points", @"width", @"color", @"opacity", @"base"]);
        NSMutableArray *names = [NSMutableArray array];
        NSArray *list = PointList(object[@"points"], Join(path, @"points"), 1, names);
        double width = Number(object, @"width", path, 0.6), base = Number(object, @"base", path, 0), opacity = Number(object, @"opacity", path, 0.8);
        if (width <= 0) GICFail(@"%@.width must be positive (in x units)", path);
        if (opacity <= 0 || opacity > 1) GICFail(@"%@.opacity must be in (0, 1]", path);
        NSColor *barColor = [color ?: Palette()[@"blue"] colorWithAlphaComponent:opacity];
        // Bars are filled rectangles, as in the Bar Chart template; a name becomes a category label under the bar.
        for (NSUInteger i = 0; i < list.count; i++) {
            RSDataPoint p = Unboxed(list[i]);
            NSArray *corners = @[Boxed(RSDataPointMake(p.x - width/2, base)), Boxed(RSDataPointMake(p.x - width/2, p.y)),
                                 Boxed(RSDataPointMake(p.x + width/2, p.y)), Boxed(RSDataPointMake(p.x + width/2, base))];
            RSFill *fill = [[[RSFill alloc] initWithGraph:b->g identifier:nil vertexGroup:Group(b, corners, NO, NO) color:barColor placement:CGPointMake(.5, .5)] autorelease];
            [b->g addFill:fill];
            if (names[i] != NSNull.null) {
                RSTextLabel *label = [[[RSTextLabel alloc] initWithGraph:b->g identifier:nil attributedString:Text(names[i], 14, NO, b->ink) position:RSDataPointMake(p.x, base) rotation:0] autorelease];
                [b->g addLabel:label];
                [b->pageLabels addObject:@[label, Boxed(RSDataPointMake(p.x, base)), @"category"]];
            }
        }
    }
    else {  // label
        Keys(object, path, @[@"type", @"text", @"at", @"page", @"size", @"bold", @"color", @"rotation", @"align"]);
        NSString *text = Value(object, @"text", NSString.class, path, YES);
        if (!!object[@"at"] == !!object[@"page"]) GICFail(@"%@: give \"at\" (data coordinates) or \"page\" (points from the bottom-left page corner), exactly one", path);
        NSString *align = Choice(object, @"align", path, @[@"left", @"center", @"right"], @"left");
        RSTextLabel *label = [[[RSTextLabel alloc] initWithGraph:b->g identifier:nil attributedString:Text(text, Number(object, @"size", path, 14), Bool(object, @"bold", path, NO), color ?: b->ink)
            position:RSDataPointMake(0, 0) rotation:Number(object, @"rotation", path, 0)] autorelease];
        [b->g addLabel:label];
        RSDataPoint at = ReadPoint(object[@"at"] ?: object[@"page"], Join(path, object[@"at"] ? @"at" : @"page"));
        [b->pageLabels addObject:@[label, Boxed(at), [align stringByAppendingString:object[@"at"] ? @"-data" : @"-page"]]];
    }
}

static void Axis(Builder *b, RSAxis *axis, NSDictionary *object, NSString *path, BOOL edge)
{
    Keys(object, path, @[@"title", @"min", @"max", @"step", @"placement", @"grid", @"log", @"ticks", @"tickLabels", @"titleSize"]);
    double step = Number(object, @"step", path, 0);
    if (step < 0) GICFail(@"%@.step must be positive", path);
    NSString *placement = Choice(object, @"placement", path, @[@"origin", @"edge", @"both-edges", @"hidden"], edge ? @"edge" : @"origin");
    axis.placement = [placement isEqual:@"origin"] ? RSOriginPlacement : [placement isEqual:@"both-edges"] ? RSBothEdgesPlacement : RSEdgePlacement;
    axis.displayAxis = ![placement isEqual:@"hidden"];
    axis.width = 1.5; axis.color = b->ink; axis.shape = RS_NONE;
    axis.displayTicks = Bool(object, @"ticks", path, axis.displayAxis);
    axis.displayTickLabels = Bool(object, @"tickLabels", path, axis.displayAxis);
    // "grid" means lines at this axis's ticks. In the model an axis's own grid runs parallel to it (the x axis's grid
    // is the horizontal lines at the y ticks), so the flag belongs to the other axis.
    [b->g otherAxis:axis].displayGrid = Bool(object, @"grid", path, NO);
    if (step) { axis.userSpacing = step; axis.spacing = step; }
    axis.titleDistance = 24;
    NSString *title = Value(object, @"title", NSString.class, path, NO);
    axis.displayTitle = title.length > 0;
    [axis.title setAttributedString:Text(title ?: @"", Number(object, @"titleSize", path, 15), YES, b->ink)];
}

static GICDocument *Build(NSDictionary *spec)
{
    Keys(spec, @"spec", @[@"graphink", @"page", @"style", @"title", @"subtitle", @"x", @"y", @"objects", @"$comment"]);
    NSNumber *version = Value(spec, @"graphink", NSNumber.class, @"spec", YES);
    if (version.integerValue != 1) GICFail(@"spec.graphink must be 1 (this tool reads spec version 1)");
    NSDictionary *page = Value(spec, @"page", NSDictionary.class, @"spec", NO) ?: @{};
    Keys(page, @"page", @[@"width", @"height", @"margins", @"background"]);
    NSDictionary *xSpec = Value(spec, @"x", NSDictionary.class, @"spec", YES), *ySpec = Value(spec, @"y", NSDictionary.class, @"spec", YES);
    double xMin = RequiredNumber(xSpec, @"min", @"x"), xMax = RequiredNumber(xSpec, @"max", @"x");
    double yMin = RequiredNumber(ySpec, @"min", @"y"), yMax = RequiredNumber(ySpec, @"max", @"y");
    if (!(xMax > xMin) || !(yMax > yMin)) GICFail(@"Each axis needs max > min");
    BOOL xLog = Bool(xSpec, @"log", @"x", NO), yLog = Bool(ySpec, @"log", @"y", NO);
    if ((xLog && xMin <= 0) || (yLog && yMin <= 0)) GICFail(@"A logarithmic axis needs min > 0");
    // The app's style presets (Arrange ▸ Apply Style Preset), by lowercase name.
    NSArray *styles = [RSStylePresetNames() valueForKey:@"lowercaseString"];
    NSString *style = Choice(spec, @"style", @"spec", styles, nil);

    GICDocument *document = [GICDocument emptyDocument];
    Builder *b = [[[Builder alloc] init] autorelease];
    b->document = document; b->g = document.graph; b->ink = Palette()[@"ink"];
    b->points = [[NSMutableDictionary alloc] init]; b->pending = [[NSMutableArray alloc] init]; b->pageLabels = [[NSMutableArray alloc] init];
    RSGraph *g = b->g;
    NSUndoManager *undo = g.undoManager;
    [undo disableUndoRegistration];
    @try {
        double width = Number(page, @"width", @"page", 1080), height = Number(page, @"height", @"page", 800);
        if (width < 100 || height < 100 || width > 5000 || height > 5000) GICFail(@"page width and height must be 100-5000 points");
        g.canvasSize = CGSizeMake(width, height);
        g.autoMaintainsWhitespace = NO;
        g.backgroundColor = Color(page, @"background", @"page", NSColor.whiteColor);
        g.creationDefaults = @{@"font-name":@"HelveticaNeue", @"line-color":b->ink, @"text-color":b->ink, @"fill-color":[b->ink colorWithAlphaComponent:.17]};
        if (xLog) [g.xAxis setAxisType:RSAxisTypeLogarithmic];
        if (yLog) [g.yAxis setAxisType:RSAxisTypeLogarithmic];
        [g setAxisRangesXMin:xMin xMax:xMax yMin:yMin yMax:yMax];
        // Axes cross at the origin unless a range starts above zero (years, log scale): then they sit on the edges.
        BOOL edge = xMin > 0 || yMin > 0 || xMax < 0 || yMax < 0;
        Axis(b, g.xAxis, xSpec, @"x", edge);
        Axis(b, g.yAxis, ySpec, @"y", edge);

        // Margins: given, or room for the title block and for each axis title beyond its tick labels
        // (Examples/Tools/GenerateCatalog.m MakeGraph, 58 pt from the page edge).
        NSString *title = Value(spec, @"title", NSString.class, @"spec", NO), *subtitle = Value(spec, @"subtitle", NSString.class, @"spec", NO);
        RSBorder margins = RSMakeBorder(60 + (title ? 70 : 0) + (subtitle ? 34 : 0), 70, 60, 70);
        id given = page[@"margins"];
        if (given) {
            if (![given isKindOfClass:NSDictionary.class]) GICFail(@"page.margins must be {\"top\", \"right\", \"bottom\", \"left\"}");
            Keys(given, @"page.margins", @[@"top", @"right", @"bottom", @"left"]);
            margins = RSMakeBorder(Number(given, @"top", @"page.margins", margins.top), Number(given, @"right", @"page.margins", margins.right),
                                   Number(given, @"bottom", @"page.margins", margins.bottom), Number(given, @"left", @"page.margins", margins.left));
        }
        g.whitespace = margins;
        if (!given[@"left"] || !given[@"bottom"]) {
            RSDataMapper *mapper = [[[RSDataMapper alloc] initWithGraph:g] autorelease];
            mapper.bounds = CGRectMake(0, 0, width, height);
            RSGraphRenderer *renderer = [[[RSGraphRenderer alloc] initWithMapper:mapper] autorelease];
            [renderer positionAxisTickLabels];
            RSBorder ticks = [renderer tickLabelWhitespaceBorder];
            BOOL xOnEdge = g.xAxis.placement != RSOriginPlacement || yMin >= 0, yOnEdge = g.yAxis.placement != RSOriginPlacement || xMin >= 0;
            if (!given[@"left"]) margins.left = MAX(margins.left, (g.yAxis.displayTitle && yOnEdge ? 58 + g.yAxis.title.size.height + g.yAxis.titleDistance : 30) + ticks.left);
            if (!given[@"bottom"]) margins.bottom = MAX(margins.bottom, (g.xAxis.displayTitle && xOnEdge ? 58 + g.xAxis.title.size.height + g.xAxis.titleDistance : 30) + ticks.bottom);
            g.whitespace = margins;
        }
        if (margins.left + margins.right >= width - 50 || margins.top + margins.bottom >= height - 50) GICFail(@"page.margins leave no room for the plot");

        NSArray *objects = Value(spec, @"objects", NSArray.class, @"spec", NO) ?: @[];
        [objects enumerateObjectsUsingBlock:^(id object, NSUInteger i, BOOL *stop) {
            NSString *path = [NSString stringWithFormat:@"objects[%lu]", (unsigned long)i];
            if (![object isKindOfClass:NSDictionary.class]) GICFail(@"%@ must be an object, not %@", path, Describe(object));
            AddObject(b, object, path);
        }];
        if (title) [b->pageLabels addObject:@[[[[RSTextLabel alloc] initWithGraph:g identifier:nil attributedString:Text(title, 29, YES, b->ink) position:RSDataPointMake(0, 0) rotation:0] autorelease],
                                              Boxed(RSDataPointMake(58, height - 70)), @"left-page"]];
        if (subtitle) [b->pageLabels addObject:@[[[[RSTextLabel alloc] initWithGraph:g identifier:nil attributedString:Text(subtitle, 16, NO, b->ink) position:RSDataPointMake(0, 0) rotation:0] autorelease],
                                                 Boxed(RSDataPointMake(58, height - 70 - (title ? 34 : 0))), @"left-page"]];

        // Layout pass, then labels whose place depends on it: free labels (page points, alignment) and owned ones.
        [document layOut];
        RSDataMapper *mapper = document.editor.mapper;
        for (NSArray *entry in b->pageLabels) {
            RSTextLabel *label = entry[0]; RSDataPoint at = Unboxed(entry[1]); NSString *mode = entry[2];
            if (![g.Labels containsObjectIdenticalTo:label]) [g addLabel:label];
            CGPoint p = [mode hasSuffix:@"-page"] ? CGPointMake(at.x, at.y) : [mapper convertToViewCoords:at];
            if ([mode isEqual:@"category"]) p = CGPointMake(p.x - label.size.width / 2, p.y - 28);
            else if ([mode isEqual:@"centroid"]) p = CGPointMake(p.x - label.size.width / 2, p.y - label.size.height / 2);
            else if ([mode hasPrefix:@"center"]) p.x -= label.size.width / 2;
            else if ([mode hasPrefix:@"right"]) p.x -= label.size.width;
            label.position = [mapper convertToDataCoords:p];
        }
        for (NSArray *entry in b->pending) {
            RSGraphElement *owner = entry[0];
            if ([owner isKindOfClass:RSVertex.class]) [document.editor.hitTester autoSetLabelPositioningForVertex:(RSVertex *)owner];
            if (entry[2] != NSNull.null) [(RSLine *)owner setSlide:[entry[2] doubleValue]];
            // The app's own placement for a new owned label, then the text, then placement again for its size.
            RSPositionNewLabel(document.editor.renderer, owner);
            owner.label.attributedString = entry[1];
            [document.editor.renderer positionLabel:owner.label forOwner:owner];
        }
        [g recomputeNow];
    } @finally {
        [undo enableUndoRegistration];
    }
    if (style) {
        NSUInteger index = [styles indexOfObject:style];
        [document.editor applyStylePreset:index];  // Arrange ▸ Apply Style Preset, the production action
    }
    [undo removeAllActions];
    [document.editor prepareForSave];
    return document;
}

#pragma mark Saving and checking

static NSDictionary *Counts(RSGraph *g)
{
    return @{@"vertices":@(g.Vertices.count), @"lines":@(g.Lines.count), @"fills":@(g.Fills.count), @"labels":@(g.userLabels.count)};
}

void GICCreateUsage(FILE *out)
{
    fputs("Usage: graphink create SPEC.json -o OUTPUT.graphink [--force]\n"
          "\n"
          "Builds a Graphink document from a JSON spec (version 1) with Graphink's own model, saves it\n"
          "with the production OPC writer (a PDF preview included) and reopens it with the production\n"
          "reader to check it. Pass - as SPEC.json to read the spec from standard input. The spec is\n"
          "described in the agent skill: https://github.com/diegomarino/graphink/tree/main/skills/graphink\n"
          "\n"
          "  -o, --output PATH  the .graphink file to write; an existing file is refused unless --force\n"
          "  --force            replace OUTPUT if it exists\n"
          "\n"
          "Then: graphink render OUTPUT.graphink -o preview.png\n"
          "Exit status: 0 written and reopened, 1 invalid spec or failure (the message names the place in\n"
          "the spec), 2 invalid arguments.\n", out);
}

int GICCreateMain(int argc, const char *argv[])
{
    @autoreleasepool {
        NSString *input = nil, *output = nil; BOOL force = NO;
        for (int i = 1; i < argc; i++) {
            NSString *arg = @(argv[i]);
            if ([arg isEqual:@"-h"] || [arg isEqual:@"--help"]) { GICCreateUsage(stdout); return GICExitOK; }
            else if (([arg isEqual:@"-o"] || [arg isEqual:@"--output"]) && i + 1 < argc) output = @(argv[++i]);
            else if ([arg isEqual:@"--force"]) force = YES;
            else if (([arg isEqual:@"-"] || ![arg hasPrefix:@"-"]) && !input) input = arg;
            else { fprintf(stderr, "graphink create: unexpected argument %s\n\n", argv[i]); GICCreateUsage(stderr); return GICExitUsage; }
        }
        if (!input || !output) { GICCreateUsage(stderr); return GICExitUsage; }
        if ([output.pathExtension caseInsensitiveCompare:@"graphink"] != NSOrderedSame) { fputs("graphink create: OUTPUT must end in .graphink\n", stderr); return GICExitUsage; }

        int status = GICExitOK;
        GICDocument *document = nil, *reopened = nil;
        @try {
            NSData *json = [input isEqual:@"-"] ? [[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile] : [NSData dataWithContentsOfFile:input];
            if (!json) GICFail(@"Cannot read %@", input);
            NSError *error = nil;
            NSDictionary *spec = [NSJSONSerialization JSONObjectWithData:json options:0 error:&error];
            if (![spec isKindOfClass:NSDictionary.class]) GICFail(@"%@ is not a JSON object: %@", input, error.localizedDescription ?: @"the top level must be {...}");
            GICStart();
            document = Build(spec);
            RSGraph *g = document.graph;
            NSData *xml = [g generateXMLOfType:RSGraphFileType frame:CGRectZero error:&error];
            if (!xml) GICFail(@"Cannot generate the document XML: %@", error.localizedDescription);
            NSData *preview = GICPDFData(document);  // the Quick Look preview the app saves with each document
            if ([NSFileManager.defaultManager fileExistsAtPath:output] && !force) GICFail(@"%@ already exists; pass --force to replace it", output);
            // Write next to the target, check it, then move it into place: a failed check leaves no document behind.
            NSString *temporary = [[output stringByDeletingLastPathComponent] stringByAppendingPathComponent:
                [NSString stringWithFormat:@".%@.%@.graphink", output.lastPathComponent, NSUUID.UUID.UUIDString]];
            @try {
                if (![RSGraphArchive writeXML:xml defaults:g.creationDefaults preview:preview encoding:RSGraphArchiveOPC toURL:[NSURL fileURLWithPath:temporary] error:&error])
                    GICFail(@"The OPC writer refused the document: %@", error.localizedDescription);
                reopened = [GICDocument documentWithContentsOfFile:temporary];
                if (reopened.encoding != RSGraphArchiveOPC) GICFail(@"The written file did not reopen as an OPC package");
                if (![Counts(reopened.graph) isEqual:Counts(g)]) GICFail(@"Reopened %@, expected %@", Counts(reopened.graph), Counts(g));
                if (!CGSizeEqualToSize(reopened.graph.canvasSize, g.canvasSize)) GICFail(@"The canvas size changed on reopen");
                NSURL *target = [NSURL fileURLWithPath:output];
                if (force && [NSFileManager.defaultManager fileExistsAtPath:output]) {
                    if (![NSFileManager.defaultManager replaceItemAtURL:target withItemAtURL:[NSURL fileURLWithPath:temporary] backupItemName:nil options:0 resultingItemURL:NULL error:&error])
                        GICFail(@"Cannot replace %@: %@", output, error.localizedDescription);
                } else if (![NSFileManager.defaultManager moveItemAtPath:temporary toPath:output error:&error])
                    GICFail(@"Cannot write %@: %@", output, error.localizedDescription);
            } @finally {
                [NSFileManager.defaultManager removeItemAtPath:temporary error:NULL];
            }
            NSDictionary *counts = Counts(g);
            printf("wrote %s (%.0f × %.0f pt; %s vertices, %s lines, %s fills, %s labels); reopened with the production reader\n", output.UTF8String,
                   g.canvasSize.width, g.canvasSize.height, [counts[@"vertices"] description].UTF8String, [counts[@"lines"] description].UTF8String,
                   [counts[@"fills"] description].UTF8String, [counts[@"labels"] description].UTF8String);
        } @catch (NSException *exception) {
            fprintf(stderr, "graphink create: %s\n", exception.reason.UTF8String);
            status = GICExitFailure;
        } @finally {
            [reopened invalidate];
            [document invalidate];
            GICStop();
        }
        return status;
    }
}
