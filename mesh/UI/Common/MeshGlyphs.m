#import "MeshGlyphs.h"
#include <math.h>
#import "MeshTheme.h"

// Symbolpfade im 24×24-Raster (wie in der Android-App)
static NSString *pathFor(NSString *name) {
    static NSDictionary *d = nil;
    if (!d) d = @{
        @"chat":       @"M4,5h16a2,2 0 0 1 2,2v8a2,2 0 0 1 -2,2h-9l-5,4v-4h-2a2,2 0 0 1 -2,-2v-8a2,2 0 0 1 2,-2z",
        @"key":        @"M20.5,3.5l-8,8 M18.3,5.7l1.6,1.6 M15.3,8.7l1.6,1.6 M8.6,12.4a3.4,3.4 0 1 0 0.01,0",
        @"scan":       @"M4,8V6a2,2 0 0 1 2,-2h2 M16,4h2a2,2 0 0 1 2,2v2 M20,16v2a2,2 0 0 1 -2,2h-2 M8,20h-2a2,2 0 0 1 -2,-2v-2 M4,12h16",
        @"send":       @"M21.5,2.5L10.5,13.5 M21.5,2.5L14.5,21.5L10.5,13.5L2.5,9.5Z",
        @"back":       @"M15,4l-8,8l8,8",
        @"add":        @"M12,5v14 M5,12h14",
        @"shield":     @"M12,3l7,3v5c0,4.5 -3,7.5 -7,9c-4,-1.5 -7,-4.5 -7,-9v-5z M9,12l2,2l4,-4",
        @"camera":     @"M5,7h3l1.3,-2h5.4l1.3,2h3a2,2 0 0 1 2,2v8a2,2 0 0 1 -2,2h-14a2,2 0 0 1 -2,-2v-8a2,2 0 0 1 2,-2z M12,10a3,3 0 1 0 0.01,0",
        @"search":     @"M11,4a7,7 0 1 0 0.01,0 M16.2,16.2l4.3,4.3",
        @"check":      @"M5,12l5,5l9,-11",
        @"doublecheck":@"M1,13l3.4,3.4l6.6,-8 M10,16.4l6.6,-8",
        @"mic":        @"M12,3a3,3 0 0 1 3,3v5a3,3 0 0 1 -6,0v-5a3,3 0 0 1 3,-3z M6,11a6,6 0 0 0 12,0 M12,17v4 M8.5,21h7",
        @"forward":    @"M9,4l8,8l-8,8",
        @"onion":      @"M12,5C16,7 19,10.5 19,14.5A7,6 0 0 1 5,14.5C5,10.5 8,7 12,5z M12,8.5C14.5,10 15.5,12.5 15.5,14.5A3.5,4 0 0 1 8.5,14.5C8.5,12.5 9.5,10 12,8.5z M12,5V2.5 M12,4C13,3 14.5,2.5 15.5,2.8",   // Tor
        @"alert":      @"M12,3a9,9 0 1 0 0.01,0z M12,7.5v6 M12,16.2v0.6",
        @"speaker":    @"M4,9h4l5,-4v14l-5,-4h-4z M16,9a4,4 0 0 1 0,6 M18.5,6.5a7.5,7.5 0 0 1 0,11",
        @"sliders":    @"M4,7h10 M18,7h2 M16,5v4 M4,17h2 M10,17h10 M8,15v4",
        @"wave":       @"M3,12h2 M7,8v8 M11,5v14 M15,9v6 M19,11v2",
        @"timer":      @"M12,5a8,8 0 1 0 0.01,0z M12,9v4l2.5,2 M10,2h4",
        @"reply":      @"M9,6l-5,5l5,5 M4,11h10a6,6 0 0 1 6,6v2",
        @"more":       @"M5,12h0.5 M12,12h0.5 M19,12h0.5",
        @"file":       @"M6,3h8l5,5v13h-13z M14,3v5h5",
        @"close":      @"M6,6l12,12 M18,6l-12,12",
    };
    return d[name];
}

// Mini-SVG-Pfad-Parser (M/L/H/V/C/A/Z, absolut+relativ; Kreisbögen mit rx=ry)
static double readNum(const char *s, int n, int *i) {
    while (*i < n && (s[*i] == ' ' || s[*i] == ',')) (*i)++;
    int st = *i;
    if (*i < n && (s[*i] == '+' || s[*i] == '-')) (*i)++;
    while (*i < n && ((s[*i] >= '0' && s[*i] <= '9') || s[*i] == '.')) (*i)++;
    if (*i < n && (s[*i] == 'e' || s[*i] == 'E')) {
        (*i)++;
        if (*i < n && (s[*i] == '+' || s[*i] == '-')) (*i)++;
        while (*i < n && s[*i] >= '0' && s[*i] <= '9') (*i)++;
    }
    return atof([[NSString stringWithFormat:@"%.*s", *i-st, s+st] UTF8String]);
}

// Kreisbogen von cur nach end mit Radius r (SVG-Flags large-arc und sweep).
static void arcTo(UIBezierPath *p, CGPoint cur, CGPoint end, double r, int large, int sweep) {
    if (r <= 0 || (fabs(cur.x - end.x) < 0.0001 && fabs(cur.y - end.y) < 0.0001)) { [p addLineToPoint:end]; return; }
    double mx = (cur.x + end.x) / 2, my = (cur.y + end.y) / 2;
    double dx = (cur.x - end.x) / 2, dy = (cur.y - end.y) / 2;
    double dsq = dx * dx + dy * dy, dist = sqrt(dsq);
    if (dist > r) r = dist;
    double h = sqrt(fmax(0, r * r - dsq));
    double ux = -dy / dist, uy = dx / dist;            // Einheitssenkrechte zur Sehne
    double sign = (large != sweep) ? -1 : 1;
    double cx = mx + sign * h * ux, cy = my + sign * h * uy;
    double a0 = atan2(cur.y - cy, cur.x - cx), a1 = atan2(end.y - cy, end.x - cx);
    [p addArcWithCenter:CGPointMake(cx, cy) radius:r startAngle:a0 endAngle:a1 clockwise:(sweep == 1)];
}

static CGPoint point(CGPoint cur, BOOL relative, double x, double y) {
    return relative ? CGPointMake(cur.x + x, cur.y + y) : CGPointMake(x, y);
}

static UIBezierPath *bezierFromSVG(NSString *d) {
    UIBezierPath *p = [UIBezierPath bezierPath];
    const char *s = d.UTF8String;
    int n = (int)strlen(s), i = 0;
    CGPoint cur = CGPointZero, start = CGPointZero;
    char cmd = 0;
    while (i < n) {
        while (i < n && (s[i] == ' ' || s[i] == ',')) i++;
        if (i >= n) break;
        char c = s[i];
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) { cmd = c; i++; }
        BOOL rel = cmd >= 'a';
        char upper = rel ? cmd - 32 : cmd;
        if (upper == 'M') {
            double x = readNum(s, n, &i), y = readNum(s, n, &i);
            cur = start = point(cur, rel, x, y);
            [p moveToPoint:cur];
            cmd = rel ? 'l' : 'L';                         // weitere Paare sind Linien
        } else if (upper == 'L') {
            double x = readNum(s, n, &i), y = readNum(s, n, &i);
            cur = point(cur, rel, x, y);
            [p addLineToPoint:cur];
        } else if (upper == 'H') {
            double x = readNum(s, n, &i);
            cur = CGPointMake(rel ? cur.x + x : x, cur.y);
            [p addLineToPoint:cur];
        } else if (upper == 'V') {
            double y = readNum(s, n, &i);
            cur = CGPointMake(cur.x, rel ? cur.y + y : y);
            [p addLineToPoint:cur];
        } else if (upper == 'C') {
            double x1 = readNum(s, n, &i), y1 = readNum(s, n, &i);
            double x2 = readNum(s, n, &i), y2 = readNum(s, n, &i);
            double x = readNum(s, n, &i), y = readNum(s, n, &i);
            CGPoint end = point(cur, rel, x, y);
            [p addCurveToPoint:end controlPoint1:point(cur, rel, x1, y1) controlPoint2:point(cur, rel, x2, y2)];
            cur = end;
        } else if (upper == 'A') {
            double rx = readNum(s, n, &i);
            readNum(s, n, &i);                             // ry: nur Kreisbögen
            readNum(s, n, &i);                             // Drehung
            int large = (int)readNum(s, n, &i), sweep = (int)readNum(s, n, &i);
            double x = readNum(s, n, &i), y = readNum(s, n, &i);
            CGPoint end = point(cur, rel, x, y);
            arcTo(p, cur, end, rx, large, sweep);
            cur = end;
        } else if (upper == 'Z') {
            [p closePath];
            cur = start;
        } else {
            i++;
        }
    }
    return p;
}

@implementation MeshGlyphs

+ (UIImage *)icon:(NSString *)name color:(UIColor *)color size:(CGFloat)size {
    NSString *d = pathFor(name);
    if (!d) return nil;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    CGContextScaleCTM(UIGraphicsGetCurrentContext(), size / 24.0, size / 24.0);
    UIBezierPath *bp = bezierFromSVG(d);
    bp.lineWidth = 1.9;
    bp.lineCapStyle = kCGLineCapRound;
    bp.lineJoinStyle = kCGLineJoinRound;
    [color setStroke];
    [bp stroke];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

+ (UIImage *)logo:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    CGContextScaleCTM(UIGraphicsGetCurrentContext(), size / 108.0, size / 108.0);   // Raster 108 wie das Android-Icon
    UIColor *accent = [MeshTheme accent];
    CGPoint center = CGPointMake(54, 54);
    CGPoint nodes[6] = { {79, 54}, {66.5, 32.4}, {41.5, 32.4}, {29, 54}, {41.5, 75.6}, {66.5, 75.6} };

    // Speichen vom Zentrum zu den Knoten
    [[accent colorWithAlphaComponent:0.55] setStroke];
    UIBezierPath *links = [UIBezierPath bezierPath];
    links.lineWidth = 2.4;
    links.lineCapStyle = kCGLineCapRound;
    for (int j = 0; j < 6; j++) { [links moveToPoint:center]; [links addLineToPoint:nodes[j]]; }
    [links stroke];

    // Ring durch die Knoten
    [[accent colorWithAlphaComponent:0.32] setStroke];
    UIBezierPath *ring = [UIBezierPath bezierPath];
    ring.lineWidth = 2.0;
    ring.lineJoinStyle = kCGLineJoinRound;
    [ring moveToPoint:nodes[0]];
    for (int j = 1; j < 6; j++) [ring addLineToPoint:nodes[j]];
    [ring closePath];
    [ring stroke];

    // Knoten, dann das Zentrum: heller Kern mit dunklem Loch
    [accent setFill];
    for (int j = 0; j < 6; j++)
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(nodes[j].x - 5, nodes[j].y - 5, 10, 10)] fill];
    [[UIColor colorWithRed:0x5C / 255.0 green:0xFF / 255.0 blue:0xC6 / 255.0 alpha:1] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(46, 46, 16, 16)] fill];
    [[MeshTheme bg] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(51, 51, 6, 6)] fill];

    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

+ (UIImage *)stopIcon:(CGFloat)size color:(UIColor *)color {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    [color setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(size * 0.30f, size * 0.30f, size * 0.40f, size * 0.40f)
                                cornerRadius:size * 0.07f] fill];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

+ (UIImage *)playPauseIcon:(BOOL)playing size:(CGFloat)s color:(UIColor *)color {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(s, s), NO, 0);
    [color setFill];
    if (playing) {
        CGFloat bw = s * 0.13f, gap = s * 0.14f, h = s * 0.46f, y = s * 0.27f;
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(s * 0.5f - gap / 2 - bw, y, bw, h) cornerRadius:bw * 0.35f] fill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(s * 0.5f + gap / 2, y, bw, h) cornerRadius:bw * 0.35f] fill];
    } else {
        UIBezierPath *path = [UIBezierPath bezierPath];
        path.lineJoinStyle = kCGLineJoinRound;
        [path moveToPoint:CGPointMake(s * 0.34f, s * 0.26f)];
        [path addLineToPoint:CGPointMake(s * 0.34f, s * 0.74f)];
        [path addLineToPoint:CGPointMake(s * 0.75f, s * 0.50f)];
        [path closePath];
        [path fill];
    }
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

@end
