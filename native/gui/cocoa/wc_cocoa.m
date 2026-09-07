/*
 * WaifuCAD Cocoa/AppKit native front-end bridge (v2 — GTK4 layout/feature parity).
 *
 * Mirrors the GTK4 host (native/gui/wc_gtk4.c) one-for-one where AppKit
 * allows: window topology (ribbon with persistent Sections/Mods tabs +
 * contextual tab row + scrolling command groups + nightcore art top-right;
 * Model/Assembly/AI navigator rail; collapsible navigator pane; graphics
 * area with centred command-console overlay; status bar), the Cairo draw
 * pipeline (grid, translucent body bounds, sketches on their real support
 * frames, planar-face selection/hover highlight, CSYS frames with
 * translucent positive-quadrant planes, corner axis triad, palette and
 * fonts), and the interaction maths (yaw/pitch orbit on middle-drag,
 * cursor-centred wheel zoom, WASD pan, Home reset, Enter/Esc focus, body
 * and planar-face hit tests, fit all/selected).
 *
 * All model mutations travel over the semantic SCL/journal callbacks
 * (submit_command, feature_action, feature_reorder) exactly like GTK4; no
 * direct model access. The Metal layer provides the themed background clear
 * (CAMetalLayer), with scene drawing over it in drawRect, matching GTK4's
 * single drawing-area model.
 *
 * Not yet ported (tracked in AGENTS.MD as Cocoa parity work): data-driven
 * feature dialogues (ribbon commands submit their semantic SCL template and
 * report the result instead), interactive sketch mode with snapping, and
 * the dedicated Metal WaifuBRep renderer (bounds-wireframe display matches
 * GTK4's bootstrap solid display).
 *
 * Compile with clang -fobjc-arc; link -framework Cocoa -framework Metal
 * -framework QuartzCore (build.sh does).
 */

#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import "wc_cocoa.h"
#include "wc_gpu_probe.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/* ------------------------------------------------------------------ */
/* Bridge state: mirrors the WcGtk4State fields the Cocoa host uses.   */
/* ------------------------------------------------------------------ */

typedef struct WcCocoaState
{
    double yaw, pitch, zoom, pan_x, pan_y;
    double drag_yaw, drag_pitch;
    int orbit_dragging;
    double orbit_start_x, orbit_start_y;

    uint32_t selected_feature_id;
    uint32_t selected_feature_kind;
    uint32_t selected_feature_exact_status;
    uint32_t selected_feature_depth;
    uint32_t selected_body_feature_id;
    char selected_feature_name[WC_COCOA_UI_ID_CAPACITY];

    uint64_t hover_face_persistent_id;
    uint32_t hover_face_owner_id;
    double pointer_x, pointer_y;
    int pointer_valid;

    int fit_bounds_valid;
    double fit_min_x, fit_min_y, fit_min_z;
    double fit_max_x, fit_max_y, fit_max_z;

    char active_ribbon_tab[WC_COCOA_UI_ID_CAPACITY];
    int ribbon_density;
    int window_width_hint;
    int journal_recording;
} WcCocoaState;

static WcCocoaCallbacks g_callbacks;
static void *g_userData = NULL;
static WcCocoaState g_state;
static WcGpuProbe g_gpu;
static NSMutableDictionary *g_iconCache = nil;
static NSMutableArray *g_rows = nil;          /* WcRow navigator records */
static NSMutableArray *g_panels = nil;         /* retains property/info panels */
static NSColor *g_navigatorColour = nil;       /* config navigator_background */
static NSColor *g_railColour = nil;            /* config navigator_rail_background */
static NSImage *g_nightcore = nil;

@class WcAppDelegate;
static WcAppDelegate *g_delegate = nil;

/* ------------------------------------------------------------------ */
/* Theme palette — the GTK4 CSS values, shared verbatim.               */
/* ------------------------------------------------------------------ */

static NSColor *WcHex(const char *hex, NSColor *fallback)
{
    unsigned int value = 0;
    if (hex == NULL || hex[0] != '#' || strlen(hex) != 7)
        return fallback;
    for (int i = 1; i < 7; ++i)
    {
        char ch = hex[i];
        unsigned digit;
        if (ch >= '0' && ch <= '9') digit = (unsigned)(ch - '0');
        else if (ch >= 'a' && ch <= 'f') digit = (unsigned)(ch - 'a' + 10);
        else if (ch >= 'A' && ch <= 'F') digit = (unsigned)(ch - 'A' + 10);
        else return fallback;
        value = value * 16u + digit;
    }
    return [NSColor colorWithCalibratedRed:((value >> 16) & 0xFF) / 255.0
                                     green:((value >> 8) & 0xFF) / 255.0
                                      blue:(value & 0xFF) / 255.0
                                     alpha:1.0];
}

static NSColor *WcWindowBackground(void) { return WcHex("#0e0c16", nil); }
static NSColor *WcTextMain(void) { return WcHex("#eee8f5", nil); }
static NSColor *WcSubtle(void) { return WcHex("#aaa2b8", nil); }
static NSColor *WcTitlePink(void) { return WcHex("#f59bd6", nil); }
static NSColor *WcRibbonBackground(void) { return WcHex("#1c1728", nil); }
static NSColor *WcRibbonBorder(void) { return WcHex("#3b2d49", nil); }
static NSColor *WcGroupBorder(void) { return WcHex("#43344f", nil); }
static NSColor *WcGroupCaption(void) { return WcHex("#a9a0b5", nil); }
static NSColor *WcTabActiveBackground(void) { return WcHex("#34243f", nil); }
static NSColor *WcTabActiveText(void) { return WcHex("#ffb3e3", nil); }
static NSColor *WcRowSelectedBackground(void) { return WcHex("#34243f", nil); }
static NSColor *WcRowSelectedText(void) { return WcHex("#ffd1ee", nil); }
static NSColor *WcDescendantBackground(void) { return WcHex("#291d35", nil); }
static NSColor *WcDescendantText(void) { return WcHex("#f4c5e6", nil); }
static NSColor *WcRowText(void) { return WcHex("#ddd4e5", nil); }
static NSColor *WcStatusBackground(void) { return WcHex("#171321", nil); }
static NSColor *WcStatusBorder(void) { return WcHex("#31283f", nil); }
static NSColor *WcRailBorder(void) { return WcHex("#372c44", nil); }
static NSColor *WcCommandPanel(void) { return [NSColor colorWithCalibratedRed:25/255.0 green:20/255.0 blue:36/255.0 alpha:0.94]; }

static NSColor *WcRGBA(double r, double g, double b, double a)
{
    return [NSColor colorWithCalibratedRed:r green:g blue:b alpha:a];
}

static const char *WcExactStatusText(uint32_t status)
{
    switch (status)
    {
        case 1u: return "exact";
        case 2u: return "preview";
        case 3u: return "failed";
        default: return "none";
    }
}

/* ------------------------------------------------------------------ */
/* Icon + caption helpers (GTK4 conventions).                          */
/* ------------------------------------------------------------------ */

static NSImage *WcLoadIcon(const char *name, CGFloat size)
{
    if (name == NULL || name[0] == '\0')
        return nil;
    if (g_iconCache == nil)
        g_iconCache = [NSMutableDictionary dictionary];
    NSString *key = [NSString stringWithFormat:@"%s@%d", name, (int)size];
    id cached = g_iconCache[key];
    if (cached != nil)
        return cached == [NSNull null] ? nil : cached;

    NSString *path = [NSString stringWithFormat:@"assets/icons/%s.svg", name];
    NSImage *image = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path])
    {
        image = [[NSImage alloc] initWithContentsOfFile:path];
        if (image != nil)
            image.size = NSMakeSize(size, size);
    }
    if (image != nil)
        g_iconCache[key] = image;
    else
        g_iconCache[key] = [NSNull null];
    return image;
}

static NSString *WcHumanise(const char *identifier)
{
    if (identifier == NULL)
        return @"";
    const char *source = identifier;
    for (const char *scan = identifier; *scan != '\0'; ++scan)
        if (*scan == '.')
            source = scan + 1;
    NSMutableString *output = [NSMutableString string];
    BOOL wordStart = YES;
    for (const char *cursor = source; *cursor != '\0'; ++cursor)
    {
        char ch = *cursor;
        if (ch == '_' || ch == '-')
        {
            [output appendString:@" "];
            wordStart = YES;
            continue;
        }
        if (wordStart && ch >= 'a' && ch <= 'z')
            ch = (char)(ch - 'a' + 'A');
        char piece[2] = { ch, '\0' };
        [output appendString:[NSString stringWithUTF8String:piece]];
        wordStart = NO;
    }
    return output;
}

static NSString *WcString(const char *text)
{
    return text != NULL ? [NSString stringWithUTF8String:text] : @"";
}

static void WcCopyText(char *destination, size_t capacity, const char *source)
{
    if (destination == NULL || capacity == 0)
        return;
    destination[0] = '\0';
    if (source == NULL)
        return;
    size_t i = 0;
    while (source[i] != '\0' && i + 1 < capacity)
    {
        destination[i] = source[i];
        ++i;
    }
    destination[i] = '\0';
}

/* ------------------------------------------------------------------ */
/* View maths — direct ports of the GTK4 projection/transform code.    */
/* ------------------------------------------------------------------ */

typedef struct WcPoint2 { double x; double y; } WcPoint2;

static double WcClamp(double value, double low, double high)
{
    return value < low ? low : (value > high ? high : value);
}

static WcPoint2 WcProjectPoint(double x, double y, double z)
{
    double cy = cos(g_state.yaw);
    double sy = sin(g_state.yaw);
    double cp = cos(g_state.pitch);
    double sp = sin(g_state.pitch);
    double x1 = cy * x - sy * y;
    double y1 = sy * x + cy * y;
    WcPoint2 result;
    result.x = x1;
    result.y = -(sp * y1 + cp * z);
    return result;
}

typedef struct WcViewTransform
{
    double model_cx, model_cy, model_cz;
    double scale, centre_x, centre_y;
    int valid;
} WcViewTransform;

static void WcGetSnapshot(WcCocoaModelSnapshot *snapshot)
{
    memset(snapshot, 0, sizeof(*snapshot));
    if (g_callbacks.model_snapshot != NULL)
        g_callbacks.model_snapshot(g_userData, snapshot);
}

static WcViewTransform WcMakeViewTransform(int width, int height, const WcCocoaModelSnapshot *snapshot)
{
    WcViewTransform transform;
    memset(&transform, 0, sizeof(transform));
    if (snapshot == NULL || (!snapshot->bounds_valid && !g_state.fit_bounds_valid))
        return transform;
    double dx, dy, dz, diagonal;
    if (g_state.fit_bounds_valid)
    {
        dx = g_state.fit_max_x - g_state.fit_min_x;
        dy = g_state.fit_max_y - g_state.fit_min_y;
        dz = g_state.fit_max_z - g_state.fit_min_z;
    }
    else
    {
        dx = snapshot->max_x - snapshot->min_x;
        dy = snapshot->max_y - snapshot->min_y;
        dz = snapshot->max_z - snapshot->min_z;
    }
    diagonal = sqrt(dx * dx + dy * dy + dz * dz);
    if (diagonal < 1e-9)
        diagonal = 100.0;
    /* Orbit is always about the absolute model origin; orientation-invariant
       3D diagonal scale means rotation itself can never zoom the model. */
    transform.model_cx = 0.0;
    transform.model_cy = 0.0;
    transform.model_cz = 0.0;
    transform.scale = fmin((double)width, (double)height) * 0.60 / diagonal * g_state.zoom;
    transform.centre_x = width * 0.5 + g_state.pan_x;
    transform.centre_y = height * 0.5 + g_state.pan_y;
    transform.valid = 1;
    return transform;
}

static WcViewTransform WcMakeEmptyCsysTransform(int width, int height)
{
    WcViewTransform transform;
    memset(&transform, 0, sizeof(transform));
    transform.scale = fmin((double)width, (double)height) * 0.60 / 100.0 * g_state.zoom;
    transform.centre_x = width * 0.5 + g_state.pan_x;
    transform.centre_y = height * 0.5 + g_state.pan_y;
    transform.valid = 1;
    return transform;
}

static void WcModelToScreen(const WcViewTransform *transform, double x, double y, double z,
                            double *sx, double *sy)
{
    WcPoint2 p = WcProjectPoint(x - transform->model_cx, y - transform->model_cy, z - transform->model_cz);
    *sx = transform->centre_x + p.x * transform->scale;
    *sy = transform->centre_y + p.y * transform->scale;
}

static int WcPointInPolygon(const double *xy, uint32_t count, double x, double y)
{
    int inside = 0;
    if (xy == NULL || count < 3)
        return 0;
    for (uint32_t i = 0, j = count - 1; i < count; j = i++)
    {
        double xi = xy[i * 2], yi = xy[i * 2 + 1];
        double xj = xy[j * 2], yj = xy[j * 2 + 1];
        if (((yi > y) != (yj > y)) &&
            (x < (xj - xi) * (y - yi) / ((yj - yi) == 0.0 ? 1e-12 : (yj - yi)) + xi))
            inside = !inside;
    }
    return inside;
}

static int WcBodyBoundsForFeature(uint32_t featureId, WcCocoaBodyRow *result)
{
    WcCocoaBodyRow bodies[WC_COCOA_BODY_ROW_CAPACITY];
    size_t count = 0;
    if (result != NULL)
        memset(result, 0, sizeof(*result));
    if (featureId == 0 || g_callbacks.body_rows == NULL)
        return 0;
    count = g_callbacks.body_rows(g_userData, bodies, WC_COCOA_BODY_ROW_CAPACITY);
    if (count > WC_COCOA_BODY_ROW_CAPACITY)
        count = WC_COCOA_BODY_ROW_CAPACITY;
    for (size_t i = 0; i < count; ++i)
    {
        if (bodies[i].feature_id == featureId)
        {
            if (result != NULL)
                *result = bodies[i];
            return 1;
        }
    }
    return 0;
}

static int WcProjectedBodyContains(const WcViewTransform *transform, const WcCocoaBodyRow *body,
                                   double x, double y)
{
    static const int faces[6][4] = {
        { 0, 1, 3, 2 }, { 4, 6, 7, 5 }, { 0, 4, 5, 1 },
        { 2, 3, 7, 6 }, { 0, 2, 6, 4 }, { 1, 5, 7, 3 }
    };
    double xs[2], ys[2], zs[2], screen[8][2], polygon[8];
    if (transform == NULL || body == NULL || !transform->valid)
        return 0;
    xs[0] = body->min_x; xs[1] = body->max_x;
    ys[0] = body->min_y; ys[1] = body->max_y;
    zs[0] = body->min_z; zs[1] = body->max_z;
    for (int i = 0; i < 8; ++i)
        WcModelToScreen(transform, xs[(i & 1) != 0], ys[(i & 2) != 0], zs[(i & 4) != 0],
                        &screen[i][0], &screen[i][1]);
    for (int face = 0; face < 6; ++face)
    {
        for (int i = 0; i < 4; ++i)
        {
            polygon[i * 2] = screen[faces[face][i]][0];
            polygon[i * 2 + 1] = screen[faces[face][i]][1];
        }
        if (WcPointInPolygon(polygon, 4, x, y))
            return 1;
    }
    return 0;
}

static uint32_t WcHitTestBody(int width, int height, double x, double y)
{
    WcCocoaBodyRow bodies[WC_COCOA_BODY_ROW_CAPACITY];
    WcCocoaModelSnapshot snapshot;
    WcViewTransform transform;
    uint32_t hit = 0;
    double bestArea = 0.0;
    if (g_callbacks.body_rows == NULL)
        return 0;
    WcGetSnapshot(&snapshot);
    transform = WcMakeViewTransform(width, height, &snapshot);
    if (!transform.valid)
        return 0;
    size_t count = g_callbacks.body_rows(g_userData, bodies, WC_COCOA_BODY_ROW_CAPACITY);
    if (count > WC_COCOA_BODY_ROW_CAPACITY)
        count = WC_COCOA_BODY_ROW_CAPACITY;
    for (size_t i = 0; i < count; ++i)
    {
        if (WcProjectedBodyContains(&transform, &bodies[i], x, y))
        {
            double dx = bodies[i].max_x - bodies[i].min_x;
            double dy = bodies[i].max_y - bodies[i].min_y;
            double dz = bodies[i].max_z - bodies[i].min_z;
            double area = fabs(dx * dy) + fabs(dx * dz) + fabs(dy * dz);
            if (hit == 0 || area < bestArea)
            {
                hit = bodies[i].feature_id;
                bestArea = area;
            }
        }
    }
    return hit;
}

static uint64_t WcHitTestPlanarFace(int width, int height, double x, double y, uint32_t *ownerId)
{
    WcCocoaPlanarFaceRow faces[WC_COCOA_FACE_ROW_CAPACITY];
    WcCocoaModelSnapshot snapshot;
    WcViewTransform transform;
    uint64_t hit = 0;
    if (ownerId != NULL)
        *ownerId = 0;
    if (g_callbacks.planar_face_rows == NULL)
        return 0;
    WcGetSnapshot(&snapshot);
    transform = WcMakeViewTransform(width, height, &snapshot);
    if (!transform.valid)
        return 0;
    size_t count = g_callbacks.planar_face_rows(g_userData, faces, WC_COCOA_FACE_ROW_CAPACITY);
    if (count > WC_COCOA_FACE_ROW_CAPACITY)
        count = WC_COCOA_FACE_ROW_CAPACITY;
    for (size_t i = 0; i < count; ++i)
    {
        double polygon[WC_COCOA_FACE_MAX_POINTS * 2];
        if (faces[i].point_count < 3 || faces[i].point_count > WC_COCOA_FACE_MAX_POINTS)
            continue;
        for (uint32_t p = 0; p < faces[i].point_count; ++p)
            WcModelToScreen(&transform, faces[i].points[p * 3], faces[i].points[p * 3 + 1],
                            faces[i].points[p * 3 + 2], &polygon[p * 2], &polygon[p * 2 + 1]);
        if (WcPointInPolygon(polygon, faces[i].point_count, x, y))
        {
            hit = faces[i].persistent_id;
            if (ownerId != NULL)
                *ownerId = faces[i].owner_feature_id;
        }
    }
    return hit;
}

static int WcFeatureNameForId(uint32_t featureId, char *output, size_t capacity)
{
    WcCocoaFeatureRow rows[WC_COCOA_FEATURE_ROW_CAPACITY];
    if (output == NULL || capacity == 0)
        return 0;
    output[0] = '\0';
    if (featureId == 0 || g_callbacks.feature_rows == NULL)
        return 0;
    size_t count = g_callbacks.feature_rows(g_userData, rows, WC_COCOA_FEATURE_ROW_CAPACITY);
    if (count > WC_COCOA_FEATURE_ROW_CAPACITY)
        count = WC_COCOA_FEATURE_ROW_CAPACITY;
    for (size_t i = 0; i < count; ++i)
    {
        if (rows[i].id == featureId && rows[i].name != NULL)
        {
            WcCopyText(output, capacity, rows[i].name);
            return 1;
        }
    }
    return 0;
}

/* ------------------------------------------------------------------ */
/* Navigator row record (mirrors the GTK4 list-row object data).       */
/* ------------------------------------------------------------------ */

@interface WcRow : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic) uint32_t featureId;
@property (nonatomic) uint32_t featureKind;
@property (nonatomic) uint32_t exactStatus;
@property (nonatomic) int depth;
@property (nonatomic) uint32_t supportKind;
@property (nonatomic) uint32_t supportFeatureId;
@property (nonatomic) uint64_t faceId;
@property (nonatomic) BOOL realFeature;
@end

@implementation WcRow
@end

/* ------------------------------------------------------------------ */
/* Controller interface (declared early so the graphics view can call  */
/* back into it; the implementation lives further down).               */
/* ------------------------------------------------------------------ */

@class WcPanelView, WcGroupView, WcCommandBoxView, WcTabButton, WcNavigatorTable, WcGraphicsView;

@protocol WcNavigatorMenuTarget
- (NSMenu *)navigatorMenuForEvent:(NSEvent *)event;
@end

@interface WcAppDelegate : NSObject <NSApplicationDelegate, NSTextFieldDelegate,
                                     NSTableViewDataSource, NSTableViewDelegate,
                                     NSWindowDelegate, WcNavigatorMenuTarget>
@property (strong) NSWindow *window;
@property (strong) WcPanelView *ribbonView;
@property (strong) NSView *tabsHost;
@property (strong) NSScrollView *groupsScroll;
@property (strong) NSImageView *nightcoreView;
@property (strong) WcPanelView *railView;
@property (strong) NSSplitView *splitView;
@property (strong) NSView *navigatorHost;
@property (strong) WcPanelView *modelPage;
@property (strong) WcPanelView *assemblyPage;
@property (strong) WcPanelView *aiPage;
@property (strong) NSTextField *modelNameLabel;
@property (strong) NSTextField *modelStatusLabel;
@property (strong) NSTextField *assemblyNameLabel;
@property (strong) NSTextField *aiSummaryLabel;
@property (strong) NSScrollView *tableScroll;
@property (strong) WcNavigatorTable *table;
@property (strong) NSView *graphicsHost;
@property (strong) WcGraphicsView *graphicsView;
@property (strong) WcCommandBoxView *commandBox;
@property (strong) NSTextField *commandStatusLabel;
@property (strong) NSTextField *commandField;
@property (strong) WcPanelView *statusBar;
@property (strong) NSTextField *rendererStatus;
@property (strong) NSMutableArray<NSString *> *commandIds;
@property (strong) NSMutableArray<NSString *> *sectionIds;
@property (nonatomic) BOOL programmaticSelection;
- (void)setCommandStatus:(NSString *)text;
- (void)focusCommandLine;
- (void)syncNavigatorSelectionToState;
- (void)reloadNavigatorKeepingSelection;
- (void)updateStatus;
- (void)rebuildRibbon;
- (void)buildUiWithConfig:(const WcCocoaWindowConfig *)config;
@end

/* ------------------------------------------------------------------ */
/* Themed container views.                                             */
/* ------------------------------------------------------------------ */

@interface WcPanelView : NSView
@property (nonatomic, strong) NSColor *fillColour;
@property (nonatomic, strong) NSColor *bottomBorderColour;
@property (nonatomic, strong) NSColor *rightBorderColour;
@property (nonatomic, strong) NSColor *topBorderColour;
@property (nonatomic) BOOL flippedLayout;
@end

@implementation WcPanelView
- (BOOL)isFlipped { return self.flippedLayout; }
- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    if (self.fillColour != nil)
    {
        [self.fillColour setFill];
        NSRectFill(self.bounds);
    }
    if (self.bottomBorderColour != nil)
    {
        [self.bottomBorderColour setFill];
        NSRectFill(NSMakeRect(0, 0, self.bounds.size.width, 1));
    }
    if (self.topBorderColour != nil)
    {
        [self.topBorderColour setFill];
        NSRectFill(NSMakeRect(0, self.bounds.size.height - 1, self.bounds.size.width, 1));
    }
    if (self.rightBorderColour != nil)
    {
        [self.rightBorderColour setFill];
        NSRectFill(NSMakeRect(self.bounds.size.width - 1, 0, 1, self.bounds.size.height));
    }
}
@end

@interface WcGroupView : WcPanelView
@property (nonatomic, copy) NSString *caption;
@end

@implementation WcGroupView
- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
    if (self.caption.length > 0)
    {
        NSDictionary *attributes = @{
            NSFontAttributeName : [NSFont systemFontOfSize:9],
            NSForegroundColorAttributeName : WcGroupCaption()
        };
        [self.caption drawAtPoint:NSMakePoint(5, 2) withAttributes:attributes];
    }
}
@end

@interface WcCommandBoxView : NSView
@end

@implementation WcCommandBoxView
- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:8 yRadius:8];
    [WcCommandPanel() setFill];
    [path fill];
}
@end

/* Ribbon tab button: active tab uses the GTK4 active colours. */
@interface WcTabButton : NSButton
@property (nonatomic) BOOL activeTab;
@end

@implementation WcTabButton
- (void)updatePresentation
{
    self.wantsLayer = YES;
    if (self.activeTab)
    {
        self.layer.backgroundColor = [WcTabActiveBackground() CGColor];
        self.attributedTitle = [[NSAttributedString alloc] initWithString:self.title
                                                               attributes:@{ NSFontAttributeName : [NSFont boldSystemFontOfSize:11],
                                                                             NSForegroundColorAttributeName : WcTabActiveText() }];
    }
    else
    {
        self.layer.backgroundColor = [[NSColor clearColor] CGColor];
        self.attributedTitle = [[NSAttributedString alloc] initWithString:self.title
                                                               attributes:@{ NSFontAttributeName : [NSFont systemFontOfSize:11],
                                                                             NSForegroundColorAttributeName : WcTextMain() }];
    }
}
@end

/* Navigator table with a GTK4-style right-click feature menu. */
@interface WcNavigatorTable : NSTableView
@property (nonatomic, weak) id<WcNavigatorMenuTarget> menuTarget;
@end

@implementation WcNavigatorTable
- (NSMenu *)menuForEvent:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger row = [self rowAtPoint:point];
    if (row < 0 || self.menuTarget == nil)
        return nil;
    [self selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    return [self.menuTarget navigatorMenuForEvent:event];
}
@end

/* ------------------------------------------------------------------ */
/* Graphics view: Metal clear + full scene draw + viewport input.      */
/* ------------------------------------------------------------------ */

@interface WcGraphicsView : NSView
{
    id<MTLCommandQueue> _queue;
    BOOL _metal;
    NSTrackingArea *_trackingArea;
}
@property (nonatomic, weak) id controller;
@end

static void WcDrawText(const char *text, double x, double gtkY, double height, NSColor *colour, NSFont *font)
{
    if (text == NULL)
        return;
    NSDictionary *attributes = @{ NSFontAttributeName : font, NSForegroundColorAttributeName : colour };
    [[NSString stringWithUTF8String:text] drawAtPoint:NSMakePoint(x, height - gtkY) withAttributes:attributes];
}

@implementation WcGraphicsView

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self != nil)
    {
        self.wantsLayer = YES;
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (device != nil)
        {
            _queue = [device newCommandQueue];
            CAMetalLayer *layer = [CAMetalLayer layer];
            layer.device = device;
            layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
            layer.framebufferOnly = YES;
            self.layer = layer;
            _metal = YES;
        }
    }
    return self;
}

- (BOOL)acceptsFirstResponder { return YES; }

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    if (_metal && self.window != nil)
    {
        CAMetalLayer *layer = (CAMetalLayer *)self.layer;
        layer.contentsScale = self.window.backingScaleFactor;
    }
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_trackingArea != nil)
        [self removeTrackingArea:_trackingArea];
    _trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                 options:NSTrackingMouseMoved | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)clearMetalBackground
{
    if (!_metal)
    {
        [WcRGBA(0.055, 0.047, 0.085, 1.0) setFill];
        NSRectFill(self.bounds);
        return;
    }
    CAMetalLayer *layer = (CAMetalLayer *)self.layer;
    CGFloat scale = layer.contentsScale > 0.0 ? layer.contentsScale : 1.0;
    CGSize size = CGSizeMake(self.bounds.size.width * scale, self.bounds.size.height * scale);
    if (size.width < 1.0 || size.height < 1.0)
        return;
    layer.drawableSize = size;
    id<CAMetalDrawable> drawable = [layer nextDrawable];
    if (drawable == nil)
        return;
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = drawable.texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0.055, 0.047, 0.085, 1.0);
    id<MTLCommandBuffer> buffer = [_queue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:pass];
    [encoder endEncoding];
    [buffer presentDrawable:drawable];
    [buffer commit];
}

/* Scene helpers ------------------------------------------------------------ */

static void WcStrokeSegment(NSColor *colour, CGFloat lineWidth, NSPoint a, NSPoint b)
{
    [colour setStroke];
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path setLineWidth:lineWidth];
    [path moveToPoint:a];
    [path lineToPoint:b];
    [path stroke];
}

- (void)drawGridWithHeight:(double)height
{
    int width = (int)self.bounds.size.width;
    int viewHeight = (int)height;
    WcCocoaModelSnapshot snapshot;
    WcViewTransform transform;
    double originX = width * 0.5 + g_state.pan_x;
    double originY = height * 0.5 + g_state.pan_y;
    WcGetSnapshot(&snapshot);
    transform = WcMakeViewTransform(width, viewHeight, &snapshot);
    if (transform.valid)
    {
        double sx, sy;
        WcModelToScreen(&transform, 0.0, 0.0, 0.0, &sx, &sy);
        originX = sx;
        originY = height - sy; /* GTK y-down -> AppKit y-up */
    }
    const int step = 32;
    NSColor *gridColour = WcRGBA(0.24, 0.19, 0.34, 0.30);
    [gridColour setStroke];
    NSBezierPath *grid = [NSBezierPath bezierPath];
    [grid setLineWidth:1.0];
    for (int x = (int)floor(originX); x > 0; x -= step)
    { [grid moveToPoint:NSMakePoint(x + 0.5, 0)]; [grid lineToPoint:NSMakePoint(x + 0.5, height)]; }
    for (int x = (int)floor(originX) + step; x < width; x += step)
    { [grid moveToPoint:NSMakePoint(x + 0.5, 0)]; [grid lineToPoint:NSMakePoint(x + 0.5, height)]; }
    for (int y = (int)floor(originY); y > 0; y -= step)
    { [grid moveToPoint:NSMakePoint(0, y + 0.5)]; [grid lineToPoint:NSMakePoint(width, y + 0.5)]; }
    for (int y = (int)floor(originY) + step; y < (int)height; y += step)
    { [grid moveToPoint:NSMakePoint(0, y + 0.5)]; [grid lineToPoint:NSMakePoint(width, y + 0.5)]; }
    [grid stroke];

    WcStrokeSegment(WcRGBA(0.93, 0.28, 0.66, 0.64), 1.4, NSMakePoint(0, originY), NSMakePoint(width, originY));
    WcStrokeSegment(WcRGBA(0.45, 0.68, 1.0, 0.64), 1.4, NSMakePoint(originX, 0), NSMakePoint(originX, height));
}

- (void)strokePolygon:(const double *)screenPoints count:(int)count fill:(NSColor *)fill stroke:(NSColor *)stroke width:(CGFloat)width
{
    NSBezierPath *path = [NSBezierPath bezierPath];
    for (int i = 0; i < count; ++i)
    {
        NSPoint point = NSMakePoint(screenPoints[i * 2], screenPoints[i * 2 + 1]);
        if (i == 0) [path moveToPoint:point]; else [path lineToPoint:point];
    }
    [path closePath];
    if (fill != nil)
    {
        [fill setFill];
        [path fill];
    }
    if (stroke != nil)
    {
        [stroke setStroke];
        [path setLineWidth:width];
        [path stroke];
    }
}

- (void)drawBodyBoundsWithTransform:(const WcViewTransform *)transform height:(double)height
{
    WcCocoaBodyRow bodies[WC_COCOA_BODY_ROW_CAPACITY];
    static const int faces[3][4] = { { 4, 5, 7, 6 }, { 0, 2, 6, 4 }, { 1, 5, 7, 3 } };
    static const int edges[12][2] = {
        {0,1},{0,2},{0,4},{1,3},{1,5},{2,3},
        {2,6},{3,7},{4,5},{4,6},{5,7},{6,7}
    };
    if (g_callbacks.body_rows == NULL || !transform->valid)
        return;
    size_t count = g_callbacks.body_rows(g_userData, bodies, WC_COCOA_BODY_ROW_CAPACITY);
    if (count > WC_COCOA_BODY_ROW_CAPACITY)
        count = WC_COCOA_BODY_ROW_CAPACITY;
    NSColor *faceColours[3] = {
        WcRGBA(0.56, 0.28, 0.82, 0.12),
        WcRGBA(0.96, 0.30, 0.68, 0.10),
        WcRGBA(0.30, 0.58, 0.96, 0.08)
    };
    for (size_t bodyIndex = 0; bodyIndex < count; ++bodyIndex)
    {
        double xs[2], ys[2], zs[2], screen[8][2], polygon[8];
        xs[0] = bodies[bodyIndex].min_x; xs[1] = bodies[bodyIndex].max_x;
        ys[0] = bodies[bodyIndex].min_y; ys[1] = bodies[bodyIndex].max_y;
        zs[0] = bodies[bodyIndex].min_z; zs[1] = bodies[bodyIndex].max_z;
        for (int i = 0; i < 8; ++i)
        {
            double sx, sy;
            WcModelToScreen(transform, xs[(i & 1) != 0], ys[(i & 2) != 0], zs[(i & 4) != 0], &sx, &sy);
            screen[i][0] = sx;
            screen[i][1] = height - sy;
        }
        for (int face = 0; face < 3; ++face)
        {
            for (int i = 0; i < 4; ++i)
            {
                polygon[i * 2] = screen[faces[face][i]][0];
                polygon[i * 2 + 1] = screen[faces[face][i]][1];
            }
            [self strokePolygon:polygon count:4 fill:faceColours[face] stroke:nil width:0];
        }
        NSBezierPath *wire = [NSBezierPath bezierPath];
        [wire setLineWidth:1.8];
        for (int i = 0; i < 12; ++i)
        {
            [wire moveToPoint:NSMakePoint(screen[edges[i][0]][0], screen[edges[i][0]][1])];
            [wire lineToPoint:NSMakePoint(screen[edges[i][1]][0], screen[edges[i][1]][1])];
        }
        [WcRGBA(0.96, 0.72, 0.92, 0.88) setStroke];
        [wire stroke];
    }
}

- (void)drawSketchSegmentWithTransform:(const WcViewTransform *)transform
                                   row:(const WcCocoaSketchGeometryRow *)row
                                    u1:(double)u1 v1:(double)v1 u2:(double)u2 v2:(double)v2
                                height:(double)height
{
    double x1 = row->frame_origin[0] + row->frame_x_axis[0] * u1 + row->frame_y_axis[0] * v1;
    double y1 = row->frame_origin[1] + row->frame_x_axis[1] * u1 + row->frame_y_axis[1] * v1;
    double z1 = row->frame_origin[2] + row->frame_x_axis[2] * u1 + row->frame_y_axis[2] * v1;
    double x2 = row->frame_origin[0] + row->frame_x_axis[0] * u2 + row->frame_y_axis[0] * v2;
    double y2 = row->frame_origin[1] + row->frame_x_axis[1] * u2 + row->frame_y_axis[1] * v2;
    double z2 = row->frame_origin[2] + row->frame_x_axis[2] * u2 + row->frame_y_axis[2] * v2;
    double sx1, sy1, sx2, sy2;
    WcModelToScreen(transform, x1, y1, z1, &sx1, &sy1);
    WcModelToScreen(transform, x2, y2, z2, &sx2, &sy2);
    WcStrokeSegment(WcRGBA(0.98, 0.70, 0.91, 0.94), 2.0,
                    NSMakePoint(sx1, height - sy1), NSMakePoint(sx2, height - sy2));
}

- (void)drawAllSketches3DWithTransform:(const WcViewTransform *)transform height:(double)height
{
    WcCocoaFeatureRow features[WC_COCOA_FEATURE_ROW_CAPACITY];
    WcCocoaSketchGeometryRow geometry[WC_COCOA_FEATURE_ROW_CAPACITY];
    if (g_callbacks.feature_rows == NULL || g_callbacks.sketch_geometry_rows == NULL || !transform->valid)
        return;
    size_t featureCount = g_callbacks.feature_rows(g_userData, features, WC_COCOA_FEATURE_ROW_CAPACITY);
    if (featureCount > WC_COCOA_FEATURE_ROW_CAPACITY)
        featureCount = WC_COCOA_FEATURE_ROW_CAPACITY;
    for (size_t fi = 0; fi < featureCount; ++fi)
    {
        if (features[fi].kind != WC_COCOA_FEATURE_KIND_SKETCH)
            continue;
        size_t count = g_callbacks.sketch_geometry_rows(g_userData, features[fi].id,
                                                        geometry, WC_COCOA_FEATURE_ROW_CAPACITY);
        if (count > WC_COCOA_FEATURE_ROW_CAPACITY)
            count = WC_COCOA_FEATURE_ROW_CAPACITY;
        for (size_t gi = 0; gi < count; ++gi)
        {
            WcCocoaSketchGeometryRow *row = &geometry[gi];
            if (!row->frame_valid)
                continue;
            if (row->kind == WC_COCOA_FEATURE_KIND_SKETCH_LINE)
            {
                [self drawSketchSegmentWithTransform:transform row:row
                                                  u1:row->values[0] v1:row->values[1]
                                                  u2:row->values[2] v2:row->values[3] height:height];
            }
            else if (row->kind == WC_COCOA_FEATURE_KIND_SKETCH_RECTANGLE)
            {
                double x = row->values[0], y = row->values[1], w = row->values[2], h = row->values[3];
                [self drawSketchSegmentWithTransform:transform row:row u1:x v1:y u2:x + w v2:y height:height];
                [self drawSketchSegmentWithTransform:transform row:row u1:x + w v1:y u2:x + w v2:y + h height:height];
                [self drawSketchSegmentWithTransform:transform row:row u1:x + w v1:y + h u2:x v2:y + h height:height];
                [self drawSketchSegmentWithTransform:transform row:row u1:x v1:y + h u2:x v2:y height:height];
            }
            else if (row->kind == WC_COCOA_FEATURE_KIND_SKETCH_CIRCLE || row->kind == WC_COCOA_FEATURE_KIND_SKETCH_ARC)
            {
                double start = 0.0, end = 2.0 * M_PI;
                double cx = row->values[0], cy = row->values[1], radius = fabs(row->values[2]);
                NSBezierPath *curve = [NSBezierPath bezierPath];
                [curve setLineWidth:2.0];
                if (row->kind == WC_COCOA_FEATURE_KIND_SKETCH_ARC)
                {
                    start = row->values[3] * M_PI / 180.0;
                    end = row->values[4] * M_PI / 180.0;
                    if (end < start)
                        end += 2.0 * M_PI;
                }
                for (int segment = 0; segment <= 64; ++segment)
                {
                    double t = start + (end - start) * ((double)segment / 64.0);
                    double wx = row->frame_origin[0] + row->frame_x_axis[0] * (cx + cos(t) * radius) + row->frame_y_axis[0] * (cy + sin(t) * radius);
                    double wy = row->frame_origin[1] + row->frame_x_axis[1] * (cx + cos(t) * radius) + row->frame_y_axis[1] * (cy + sin(t) * radius);
                    double wz = row->frame_origin[2] + row->frame_x_axis[2] * (cx + cos(t) * radius) + row->frame_y_axis[2] * (cy + sin(t) * radius);
                    double sx, sy;
                    WcModelToScreen(transform, wx, wy, wz, &sx, &sy);
                    if (segment == 0) [curve moveToPoint:NSMakePoint(sx, height - sy)];
                    else [curve lineToPoint:NSMakePoint(sx, height - sy)];
                }
                [WcRGBA(0.98, 0.70, 0.91, 0.94) setStroke];
                [curve stroke];
            }
        }
    }
}

- (void)drawPlanarFaceSelectionWithTransform:(const WcViewTransform *)transform height:(double)height
{
    WcCocoaPlanarFaceRow faces[WC_COCOA_FACE_ROW_CAPACITY];
    if (g_callbacks.planar_face_rows == NULL || !transform->valid)
        return;
    size_t count = g_callbacks.planar_face_rows(g_userData, faces, WC_COCOA_FACE_ROW_CAPACITY);
    if (count > WC_COCOA_FACE_ROW_CAPACITY)
        count = WC_COCOA_FACE_ROW_CAPACITY;
    for (size_t i = 0; i < count; ++i)
    {
        double polygon[WC_COCOA_FACE_MAX_POINTS * 2];
        int highlight = faces[i].persistent_id == g_state.hover_face_persistent_id ||
                        (g_state.selected_body_feature_id != 0 &&
                         faces[i].owner_feature_id == g_state.selected_body_feature_id);
        if (!highlight || faces[i].point_count < 3 || faces[i].point_count > WC_COCOA_FACE_MAX_POINTS)
            continue;
        for (uint32_t p = 0; p < faces[i].point_count; ++p)
        {
            double sx, sy;
            WcModelToScreen(transform, faces[i].points[p * 3], faces[i].points[p * 3 + 1],
                            faces[i].points[p * 3 + 2], &sx, &sy);
            polygon[p * 2] = sx;
            polygon[p * 2 + 1] = height - sy;
        }
        [self strokePolygon:polygon count:(int)faces[i].point_count
                       fill:WcRGBA(0.98, 0.48, 0.82, 0.24)
                     stroke:WcRGBA(1.0, 0.72, 0.93, 0.95) width:2.2];
    }
}

- (void)drawSelectedBodyBoundsWithTransform:(const WcViewTransform *)transform height:(double)height
{
    WcCocoaBodyRow body;
    static const int edges[12][2] = {
        {0,1},{0,2},{0,4},{1,3},{1,5},{2,3},
        {2,6},{3,7},{4,5},{4,6},{5,7},{6,7}
    };
    if (g_state.selected_body_feature_id == 0 ||
        !WcBodyBoundsForFeature(g_state.selected_body_feature_id, &body) || !transform->valid)
        return;
    double xs[2], ys[2], zs[2], screen[8][2];
    xs[0] = body.min_x; xs[1] = body.max_x;
    ys[0] = body.min_y; ys[1] = body.max_y;
    zs[0] = body.min_z; zs[1] = body.max_z;
    for (int i = 0; i < 8; ++i)
    {
        double sx, sy;
        WcModelToScreen(transform, xs[(i & 1) != 0], ys[(i & 2) != 0], zs[(i & 4) != 0], &sx, &sy);
        screen[i][0] = sx;
        screen[i][1] = height - sy;
    }
    NSBezierPath *wire = [NSBezierPath bezierPath];
    [wire setLineWidth:3.0];
    for (int i = 0; i < 12; ++i)
    {
        [wire moveToPoint:NSMakePoint(screen[edges[i][0]][0], screen[edges[i][0]][1])];
        [wire lineToPoint:NSMakePoint(screen[edges[i][1]][0], screen[edges[i][1]][1])];
    }
    [WcRGBA(1.0, 0.52, 0.86, 0.98) setStroke];
    [wire stroke];
}

- (void)drawCsysPlaneWithTransform:(const WcViewTransform *)transform
                               row:(const WcCocoaCsysRow *)row
                                 a:(const double *)a b:(const double *)b
                          sideSize:(double)sideSize
                            colour:(NSColor *)colour
                             alpha:(double)alpha
                            height:(double)height
{
    static const double quadrant[4][2] = { {0,0}, {1,0}, {1,1}, {0,1} };
    double polygon[8];
    for (int corner = 0; corner < 4; ++corner)
    {
        double x = row->origin[0] + a[0] * sideSize * quadrant[corner][0] + b[0] * sideSize * quadrant[corner][1];
        double y = row->origin[1] + a[1] * sideSize * quadrant[corner][0] + b[1] * sideSize * quadrant[corner][1];
        double z = row->origin[2] + a[2] * sideSize * quadrant[corner][0] + b[2] * sideSize * quadrant[corner][1];
        double sx, sy;
        WcModelToScreen(transform, x, y, z, &sx, &sy);
        polygon[corner * 2] = sx;
        polygon[corner * 2 + 1] = height - sy;
    }
    NSColor *strokeColour = [colour colorWithAlphaComponent:fmin(0.75, alpha * 2.5)];
    [self strokePolygon:polygon count:4 fill:[colour colorWithAlphaComponent:alpha] stroke:strokeColour width:1.0];
}

- (void)drawAbsoluteCsysWithTransformPtr:(const WcViewTransform *)transformPtr
                                snapshot:(const WcCocoaModelSnapshot *)snapshot
                                  height:(double)height
{
    WcCocoaCsysRow rows[WC_COCOA_CSYS_ROW_CAPACITY];
    size_t count = 0;
    double length = 12.0;
    WcViewTransform transform = *transformPtr;
    if (g_callbacks.csys_rows != NULL)
        count = g_callbacks.csys_rows(g_userData, rows, WC_COCOA_CSYS_ROW_CAPACITY);
    if (count > WC_COCOA_CSYS_ROW_CAPACITY)
        count = WC_COCOA_CSYS_ROW_CAPACITY;
    if (count == 0)
    {
        memset(&rows[0], 0, sizeof(rows[0]));
        rows[0].name = "absolute_csys";
        rows[0].x_axis[0] = 1.0;
        rows[0].y_axis[1] = 1.0;
        rows[0].z_axis[2] = 1.0;
        count = 1;
    }
    if (snapshot->bounds_valid || g_state.fit_bounds_valid)
    {
        double dx, dy, dz, diagonal;
        if (g_state.fit_bounds_valid)
        {
            dx = g_state.fit_max_x - g_state.fit_min_x;
            dy = g_state.fit_max_y - g_state.fit_min_y;
            dz = g_state.fit_max_z - g_state.fit_min_z;
        }
        else
        {
            dx = snapshot->max_x - snapshot->min_x;
            dy = snapshot->max_y - snapshot->min_y;
            dz = snapshot->max_z - snapshot->min_z;
        }
        diagonal = sqrt(dx * dx + dy * dy + dz * dz);
        if (diagonal > 1e-6)
            length = WcClamp(diagonal * 0.18, 5.0, 100.0);
    }
    if (!transform.valid)
        return;

    for (size_t i = 0; i < count; ++i)
    {
        double ox, oy, xx, xy, yx, yy, zx, zy;
        double planeSide = length * 0.62;
        double planeAlpha = rows[i].feature_id == g_state.selected_feature_id ? 0.15 : 0.075;
        /* Positive-quadrant construction planes only; never mirrored. */
        [self drawCsysPlaneWithTransform:&transform row:&rows[i] a:rows[i].x_axis b:rows[i].y_axis
                                sideSize:planeSide colour:WcRGBA(0.95, 0.36, 0.68, 1.0) alpha:planeAlpha height:height];
        [self drawCsysPlaneWithTransform:&transform row:&rows[i] a:rows[i].y_axis b:rows[i].z_axis
                                sideSize:planeSide colour:WcRGBA(0.40, 0.88, 0.60, 1.0) alpha:planeAlpha height:height];
        [self drawCsysPlaneWithTransform:&transform row:&rows[i] a:rows[i].x_axis b:rows[i].z_axis
                                sideSize:planeSide colour:WcRGBA(0.38, 0.66, 1.00, 1.0) alpha:planeAlpha height:height];

        WcModelToScreen(&transform, rows[i].origin[0], rows[i].origin[1], rows[i].origin[2], &ox, &oy);
        WcModelToScreen(&transform, rows[i].origin[0] + rows[i].x_axis[0] * length,
                        rows[i].origin[1] + rows[i].x_axis[1] * length,
                        rows[i].origin[2] + rows[i].x_axis[2] * length, &xx, &xy);
        WcModelToScreen(&transform, rows[i].origin[0] + rows[i].y_axis[0] * length,
                        rows[i].origin[1] + rows[i].y_axis[1] * length,
                        rows[i].origin[2] + rows[i].y_axis[2] * length, &yx, &yy);
        WcModelToScreen(&transform, rows[i].origin[0] + rows[i].z_axis[0] * length,
                        rows[i].origin[1] + rows[i].z_axis[1] * length,
                        rows[i].origin[2] + rows[i].z_axis[2] * length, &zx, &zy);
        CGFloat axisWidth = rows[i].feature_id == g_state.selected_feature_id ? 3.0 : 2.0;
        WcStrokeSegment(WcRGBA(0.95, 0.36, 0.40, 0.96), axisWidth, NSMakePoint(ox, height - oy), NSMakePoint(xx, height - xy));
        WcStrokeSegment(WcRGBA(0.40, 0.88, 0.48, 0.96), axisWidth, NSMakePoint(ox, height - oy), NSMakePoint(yx, height - yy));
        WcStrokeSegment(WcRGBA(0.38, 0.66, 1.0, 0.96), axisWidth, NSMakePoint(ox, height - oy), NSMakePoint(zx, height - zy));
        CGFloat dotRadius = rows[i].feature_id == g_state.selected_feature_id ? 5.0 : 3.5;
        [WcRGBA(0.96, 0.85, 0.95, 0.95) setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(ox - dotRadius, (height - oy) - dotRadius, dotRadius * 2, dotRadius * 2)] fill];
        WcDrawText("X", xx + 3, xy, height, WcRGBA(0.95, 0.36, 0.40, 1.0), [NSFont boldSystemFontOfSize:9]);
        WcDrawText("Y", yx + 3, yy, height, WcRGBA(0.40, 0.88, 0.48, 1.0), [NSFont boldSystemFontOfSize:9]);
        WcDrawText("Z", zx + 3, zy, height, WcRGBA(0.38, 0.66, 1.0, 1.0), [NSFont boldSystemFontOfSize:9]);
        if (rows[i].name != NULL)
            WcDrawText(rows[i].name, ox + 7.0, oy - 7.0, height,
                       WcRGBA(0.86, 0.78, 0.90, 0.86), [NSFont systemFontOfSize:11]);
    }
}

- (void)drawAxisTriadWithHeight:(double)height
{
    WcPoint2 xAxis = WcProjectPoint(1.0, 0.0, 0.0);
    WcPoint2 yAxis = WcProjectPoint(0.0, 1.0, 0.0);
    WcPoint2 zAxis = WcProjectPoint(0.0, 0.0, 1.0);
    double ox = 54.0;
    double oy = 54.0; /* GTK: height - 54 in y-down == 54 in y-up */
    double length = 28.0;
    WcStrokeSegment(WcRGBA(0.95, 0.36, 0.40, 0.95), 2.5, NSMakePoint(ox, oy), NSMakePoint(ox + xAxis.x * length, oy - xAxis.y * length));
    WcStrokeSegment(WcRGBA(0.40, 0.88, 0.48, 0.95), 2.5, NSMakePoint(ox, oy), NSMakePoint(ox + yAxis.x * length, oy - yAxis.y * length));
    WcStrokeSegment(WcRGBA(0.38, 0.66, 1.0, 0.95), 2.5, NSMakePoint(ox, oy), NSMakePoint(ox + zAxis.x * length, oy - zAxis.y * length));
    WcDrawText("X", ox + xAxis.x * length + 3, height - (oy - xAxis.y * length), height, WcRGBA(0.95, 0.36, 0.40, 1.0), [NSFont boldSystemFontOfSize:11]);
    WcDrawText("Y", ox + yAxis.x * length + 3, height - (oy - yAxis.y * length), height, WcRGBA(0.40, 0.88, 0.48, 1.0), [NSFont boldSystemFontOfSize:11]);
    WcDrawText("Z", ox + zAxis.x * length + 3, height - (oy - zAxis.y * length), height, WcRGBA(0.38, 0.66, 1.0, 1.0), [NSFont boldSystemFontOfSize:11]);
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    double height = self.bounds.size.height;
    int width = (int)self.bounds.size.width;
    WcCocoaModelSnapshot snapshot;
    WcViewTransform transform;

    [self clearMetalBackground];
    [self drawGridWithHeight:height];
    WcGetSnapshot(&snapshot);
    transform = WcMakeViewTransform(width, (int)height, &snapshot);
    [self drawBodyBoundsWithTransform:&transform height:height];
    [self drawAllSketches3DWithTransform:&transform height:height];
    [self drawPlanarFaceSelectionWithTransform:&transform height:height];
    [self drawSelectedBodyBoundsWithTransform:&transform height:height];
    [self drawAbsoluteCsysWithTransformPtr:&transform snapshot:&snapshot height:height];
    [self drawAxisTriadWithHeight:height];

    WcDrawText("WaifuCAD", 20.0, 30.0, height, WcRGBA(0.96, 0.76, 0.92, 0.68), [NSFont boldSystemFontOfSize:18]);
    const char *hint = snapshot.bounds_valid
        ? "Wheel: zoom   Middle-drag: orbit   WASD: pan   Enter: command line   Esc: viewport"
        : "Create geometry from the ribbon or command line. Wheel zoom / middle-drag orbit / WASD pan.";
    WcDrawText(hint, 20.0, 48.0, height, WcRGBA(0.75, 0.72, 0.82, 0.72), [NSFont systemFontOfSize:11]);
}

/* Input — GTK4 gesture parity --------------------------------------------- */

- (void)scrollWheel:(NSEvent *)event
{
    double delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.125 : event.scrollingDeltaY;
    if (fabs(delta) < 1.0e-9)
        return;
    double factor = pow(1.14, delta);
    double oldZoom = g_state.zoom;
    g_state.zoom = WcClamp(oldZoom * factor, 0.05, 40.0);
    factor = g_state.zoom / oldZoom;
    double width = self.bounds.size.width;
    double height = self.bounds.size.height;
    NSPoint local = [self convertPoint:event.locationInWindow fromView:nil];
    double px = g_state.pointer_valid ? g_state.pointer_x : width * 0.5;
    double py = g_state.pointer_valid ? g_state.pointer_y : height * 0.5;
    (void)local;
    /* Keep the model point under the cursor fixed while zooming. */
    g_state.pan_x = px - width * 0.5 - factor * (px - width * 0.5 - g_state.pan_x);
    g_state.pan_y = py - height * 0.5 - factor * (py - height * 0.5 - g_state.pan_y);
    [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)event
{
    double height = self.bounds.size.height;
    NSPoint local = [self convertPoint:event.locationInWindow fromView:nil];
    double gx = local.x;
    double gy = height - local.y; /* GTK y-down convention */
    g_state.pointer_x = gx;
    g_state.pointer_y = gy;
    g_state.pointer_valid = 1;
    [self.window makeFirstResponder:self];

    if (event.buttonNumber != 0)
        return;

    int width = (int)self.bounds.size.width;
    uint32_t ownerId = 0;
    uint64_t faceId = 0;
    uint32_t bodyId = WcHitTestBody(width, (int)height, gx, gy);
    if (bodyId == 0)
    {
        faceId = WcHitTestPlanarFace(width, (int)height, gx, gy, &ownerId);
        if (faceId != 0)
            bodyId = ownerId;
    }
    if (bodyId != 0)
    {
        char name[WC_COCOA_UI_ID_CAPACITY];
        g_state.selected_feature_id = bodyId;
        g_state.selected_body_feature_id = bodyId;
        if (WcFeatureNameForId(bodyId, name, sizeof(name)))
            WcCopyText(g_state.selected_feature_name, sizeof(g_state.selected_feature_name), name);
        [g_delegate syncNavigatorSelectionToState];
        [g_delegate setCommandStatus:@"Body selected — right-click for Properties / Fit / Delete"];
    }
    else
    {
        g_state.selected_body_feature_id = 0;
        [g_delegate setCommandStatus:@"Viewport focus — wheel zoom, middle-drag orbit, WASD pan, Enter for command line"];
    }
    [g_delegate reloadNavigatorKeepingSelection];
    [self setNeedsDisplay:YES];
}

- (void)otherMouseDown:(NSEvent *)event
{
    if (event.buttonNumber != 2)
        return;
    double height = self.bounds.size.height;
    NSPoint local = [self convertPoint:event.locationInWindow fromView:nil];
    g_state.orbit_dragging = 1;
    g_state.drag_yaw = g_state.yaw;
    g_state.drag_pitch = g_state.pitch;
    g_state.orbit_start_x = local.x;
    g_state.orbit_start_y = height - local.y;
    [self.window makeFirstResponder:self];
}

- (void)otherMouseDragged:(NSEvent *)event
{
    if (!g_state.orbit_dragging || event.buttonNumber != 2)
        return;
    double height = self.bounds.size.height;
    NSPoint local = [self convertPoint:event.locationInWindow fromView:nil];
    double offsetX = local.x - g_state.orbit_start_x;
    double offsetY = (height - local.y) - g_state.orbit_start_y;
    g_state.yaw = g_state.drag_yaw + offsetX * 0.008;
    g_state.pitch = WcClamp(g_state.drag_pitch + offsetY * 0.008, -1.48, 1.48);
    [self setNeedsDisplay:YES];
}

- (void)otherMouseUp:(NSEvent *)event
{
    (void)event;
    g_state.orbit_dragging = 0;
}

- (void)mouseDragged:(NSEvent *)event
{
    if (!g_state.orbit_dragging)
        return;
    double height = self.bounds.size.height;
    NSPoint local = [self convertPoint:event.locationInWindow fromView:nil];
    double gx = local.x;
    double gy = height - local.y;
    double offsetX = gx - g_state.orbit_start_x;
    double offsetY = gy - g_state.orbit_start_y;
    g_state.yaw = g_state.drag_yaw + offsetX * 0.008;
    g_state.pitch = WcClamp(g_state.drag_pitch + offsetY * 0.008, -1.48, 1.48);
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event
{
    (void)event;
    g_state.orbit_dragging = 0;
}

- (void)mouseMoved:(NSEvent *)event
{
    double height = self.bounds.size.height;
    NSPoint local = [self convertPoint:event.locationInWindow fromView:nil];
    double gx = local.x;
    double gy = height - local.y;
    g_state.pointer_x = gx;
    g_state.pointer_y = gy;
    g_state.pointer_valid = 1;
    uint32_t owner = 0;
    uint64_t face = WcHitTestPlanarFace((int)self.bounds.size.width, (int)height, gx, gy, &owner);
    if (face != g_state.hover_face_persistent_id || owner != g_state.hover_face_owner_id)
    {
        g_state.hover_face_persistent_id = face;
        g_state.hover_face_owner_id = owner;
        [self setNeedsDisplay:YES];
    }
}

- (void)rightMouseDown:(NSEvent *)event
{
    double height = self.bounds.size.height;
    NSPoint local = [self convertPoint:event.locationInWindow fromView:nil];
    double gx = local.x;
    double gy = height - local.y;
    uint32_t hit = WcHitTestBody((int)self.bounds.size.width, (int)height, gx, gy);
    if (hit != 0)
    {
        g_state.selected_feature_id = hit;
        g_state.selected_body_feature_id = hit;
        [g_delegate syncNavigatorSelectionToState];
        [g_delegate reloadNavigatorKeepingSelection];
        [self setNeedsDisplay:YES];
    }
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Viewport"];
    NSMenuItem *fit = [[NSMenuItem alloc] initWithTitle:@"Fit" action:@selector(viewportFitAll:) keyEquivalent:@""];
    fit.target = g_delegate;
    [menu addItem:fit];
    NSMenuItem *fitSelected = [[NSMenuItem alloc] initWithTitle:@"Fit Selected" action:@selector(viewportFitSelected:) keyEquivalent:@""];
    fitSelected.target = g_delegate;
    fitSelected.enabled = g_state.selected_body_feature_id != 0;
    [menu addItem:fitSelected];
    NSMenuItem *properties = [[NSMenuItem alloc] initWithTitle:@"Properties" action:@selector(viewportProperties:) keyEquivalent:@""];
    properties.target = g_delegate;
    properties.enabled = g_state.selected_feature_id != 0;
    [menu addItem:properties];
    [NSMenu popUpContextMenu:menu withEvent:event forView:self];
}

- (void)keyDown:(NSEvent *)event
{
    NSString *characters = event.charactersIgnoringModifiers;
    double step = (event.modifierFlags & NSEventModifierFlagShift) != 0 ? 42.0 : 18.0;
    if (event.keyCode == 53) /* Esc */
    {
        [self.window makeFirstResponder:self];
        [g_delegate setCommandStatus:@"Viewport focus — wheel zoom, middle-drag orbit, WASD pan, Enter for command line"];
        return;
    }
    if (event.keyCode == 36 || event.keyCode == 76) /* Return / keypad Enter */
    {
        [g_delegate focusCommandLine];
        return;
    }
    if (event.keyCode == 115) /* Home */
    {
        g_state.zoom = 1.0;
        g_state.pan_x = 0.0;
        g_state.pan_y = 0.0;
        g_state.yaw = -M_PI / 4.0;
        g_state.pitch = M_PI / 5.5;
        [self setNeedsDisplay:YES];
        return;
    }
    if (characters.length == 1)
    {
        unichar key = [characters characterAtIndex:0];
        switch (key)
        {
            case 'w': case 'W': g_state.pan_y += step; break;
            case 's': case 'S': g_state.pan_y -= step; break;
            case 'a': case 'A': g_state.pan_x += step; break;
            case 'd': case 'D': g_state.pan_x -= step; break;
            default: [super keyDown:event]; return;
        }
        [self setNeedsDisplay:YES];
        return;
    }
    [super keyDown:event];
}

@end

/* ------------------------------------------------------------------ */
/* Controller.                                                         */
/* ------------------------------------------------------------------ */

static void WcFitAll(void)
{
    g_state.fit_bounds_valid = 0;
    g_state.zoom = 1.0;
    g_state.pan_x = 0.0;
    g_state.pan_y = 0.0;
}

static int WcFitFeature(uint32_t featureId)
{
    WcCocoaBodyRow body;
    if (!WcBodyBoundsForFeature(featureId, &body))
        return 0;
    g_state.fit_bounds_valid = 1;
    g_state.fit_min_x = body.min_x;
    g_state.fit_min_y = body.min_y;
    g_state.fit_min_z = body.min_z;
    g_state.fit_max_x = body.max_x;
    g_state.fit_max_y = body.max_y;
    g_state.fit_max_z = body.max_z;
    g_state.zoom = 1.0;
    g_state.pan_x = 0.0;
    g_state.pan_y = 0.0;
    return 1;
}

@implementation WcAppDelegate

/* -- status plumbing ------------------------------------------------ */

- (void)setCommandStatus:(NSString *)text
{
    self.commandStatusLabel.stringValue = text;
}

- (void)focusCommandLine
{
    [self.window makeFirstResponder:self.commandField];
}

/* -- submission ------------------------------------------------------ */

- (int)submitLine:(char *)line
{
    if (line == NULL || g_callbacks.submit_command == NULL)
        return 10;
    return g_callbacks.submit_command(g_userData, line);
}

- (void)commandActivated
{
    NSString *text = self.commandField.stringValue;
    if (text.length == 0)
        return;
    char *line = strdup([text UTF8String]);
    int status = 10;
    if (line != NULL)
    {
        status = [self submitLine:line];
        free(line);
    }
    if (status == 0)
    {
        self.commandField.stringValue = @"";
        [self setCommandStatus:@"Command complete — press Esc for viewport navigation"];
    }
    else
        [self setCommandStatus:[NSString stringWithFormat:@"SCL error %d", status]];
    [self updateStatus];
    [self.graphicsView setNeedsDisplay:YES];
}

/* -- ribbon ---------------------------------------------------------- */

- (const WcCocoaRibbonSnapshot *)activeRibbon
{
    if (g_callbacks.active_ribbon == NULL)
        return NULL;
    return g_callbacks.active_ribbon(g_userData);
}

- (BOOL)ribbonHasTab:(const char *)tabId
{
    const WcCocoaRibbonSnapshot *ribbon = [self activeRibbon];
    if (tabId == NULL || tabId[0] == '\0')
        return NO;
    if (strcmp(tabId, "global.sections") == 0 || strcmp(tabId, "global.mods") == 0)
        return YES;
    if (ribbon == NULL)
        return NO;
    for (size_t i = 0; i < ribbon->tab_count; ++i)
        if (ribbon->tabs[i].id != NULL && strcmp(ribbon->tabs[i].id, tabId) == 0)
            return YES;
    return NO;
}

- (WcTabButton *)makeTabButton:(NSString *)title tabId:(const char *)tabId
{
    WcTabButton *button = [[WcTabButton alloc] init];
    [button setTitle:title];
    button.bezelStyle = NSBezelStyleRounded;
    button.bordered = NO;
    button.target = self;
    button.action = @selector(onRibbonTabClicked:);
    button.toolTip = WcString(tabId);
    button.activeTab = g_state.active_ribbon_tab[0] != '\0' && tabId != NULL &&
                       strcmp(g_state.active_ribbon_tab, tabId) == 0;
    [button updatePresentation];
    NSSize natural = [[button cell] cellSize];
    CGFloat width = natural.width + 20 < 70 ? 70 : natural.width + 20;
    return button;
}

- (void)onRibbonTabClicked:(WcTabButton *)sender
{
    NSString *tabId = sender.toolTip;
    WcCopyText(g_state.active_ribbon_tab, sizeof(g_state.active_ribbon_tab), [tabId UTF8String]);
    [self rebuildRibbon];
}

- (void)onSectionButtonClicked:(NSButton *)sender
{
    NSString *sectionId = self.sectionIds[(NSUInteger)sender.tag];
    [self chooseSection:[sectionId UTF8String]];
}

- (void)chooseSection:(const char *)sectionId
{
    int ok = g_callbacks.choose_section != NULL ? g_callbacks.choose_section(g_userData, sectionId) : 0;
    if (!ok)
    {
        [self setCommandStatus:@"Section change rejected"];
        return;
    }
    g_state.active_ribbon_tab[0] = '\0';
    [self rebuildRibbon];
    [self updateStatus];
}

- (void)onCommandClicked:(NSButton *)sender
{
    NSString *commandId = self.commandIds[(NSUInteger)sender.tag];
    if ([commandId isEqualToString:@"modelling.focus_command_line"])
    {
        [self focusCommandLine];
        return;
    }
    [self runRibbonCommand:[commandId UTF8String]];
}

- (void)runRibbonCommand:(const char *)commandId
{
    char mutableCommand[512];
    const char *templateText;
    int status;

    /* Interactive sketch mode is GTK4-only in this increment. */
    if (strcmp(commandId, "modelling.sketch") == 0)
    {
        [self setCommandStatus:@"Interactive sketch mode is GTK4-only in this Cocoa increment; use sketch(:name, :XY) then sketch_rect/sketch_line/sketch_circle_at"];
        return;
    }
    if (strcmp(commandId, "modelling.measure") == 0 || strcmp(commandId, "modelling.mass_properties") == 0)
    {
        if (g_state.selected_feature_id == 0)
        {
            [self setCommandStatus:@"Select a feature first"];
            return;
        }
        if (strcmp(commandId, "modelling.mass_properties") == 0)
            [self showMassProperties:g_state.selected_feature_id];
        else
            [self showFeatureProperties:g_state.selected_feature_id];
        return;
    }
    if (strcmp(commandId, "modelling.journal_record") == 0)
    {
        if (g_state.journal_recording)
        {
            char stopCommand[32];
            (void)snprintf(stopCommand, sizeof(stopCommand), "%s", "journal_stop()");
            status = [self submitLine:stopCommand];
            if (status == 0)
            {
                g_state.journal_recording = 0;
                [self setCommandStatus:@"Journal recording stopped"];
            }
            else
                [self setCommandStatus:[NSString stringWithFormat:@"Stop journal failed (error %d)", status]];
            return;
        }
        NSSavePanel *panel = [NSSavePanel savePanel];
        panel.title = @"Record Journal";
        panel.nameFieldStringValue = @"model.wjournal";
        if ([panel runModal] == NSModalResponseOK && panel.URL != nil)
            [self submitPathCommand:2 path:[NSString stringWithUTF8String:panel.URL.fileSystemRepresentation]];
        return;
    }
    if (strcmp(commandId, "modelling.run_journal") == 0)
    {
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        panel.title = @"Run Journal";
        panel.allowsMultipleSelection = NO;
        if ([panel runModal] == NSModalResponseOK && panel.URL != nil)
            [self submitPathCommand:3 path:[NSString stringWithUTF8String:panel.URL.fileSystemRepresentation]];
        return;
    }
    if (strcmp(commandId, "modelling.run_script") == 0)
    {
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        panel.title = @"Run Script";
        panel.allowsMultipleSelection = NO;
        if ([panel runModal] == NSModalResponseOK && panel.URL != nil)
            [self submitPathCommand:1 path:[NSString stringWithUTF8String:panel.URL.fileSystemRepresentation]];
        return;
    }

    templateText = g_callbacks.ribbon_template != NULL ? g_callbacks.ribbon_template(g_userData, commandId) : NULL;
    if (templateText == NULL || templateText[0] == '\0')
    {
        [self setCommandStatus:[NSString stringWithFormat:@"No semantic template for %@", WcString(commandId)]];
        return;
    }
    (void)snprintf(mutableCommand, sizeof(mutableCommand), "%s", templateText);
    status = [self submitLine:mutableCommand];
    if (status == 0)
        [self setCommandStatus:[NSString stringWithFormat:@"%@: template submitted", WcHumanise(commandId)]];
    else
        [self setCommandStatus:[NSString stringWithFormat:@"%@: SCL error %d (feature dialogues are GTK4-only in this increment)", WcHumanise(commandId), status]];
    [self updateStatus];
    [self.graphicsView setNeedsDisplay:YES];
}

/* Modes mirror GTK4's WcPathChooserMode: 1 include, 2 journal_start, 3 journal_run. */
- (void)submitPathCommand:(int)mode path:(NSString *)path
{
    if (path.length == 0)
        return;
    const char *verb = mode == 1 ? "include" : (mode == 2 ? "journal_start" : "journal_run");
    NSMutableString *command = [NSMutableString stringWithString:WcString(verb)];
    [command appendString:@"(\""];
    const char *cursor = [path UTF8String];
    for (; *cursor != '\0'; ++cursor)
    {
        if (*cursor == '"' || *cursor == '\\')
            [command appendFormat:@"\\%c", *cursor];
        else if (*cursor != '\r')
            [command appendFormat:@"%c", *cursor];
    }
    [command appendString:@"\")"];
    char buffer[1024];
    (void)snprintf(buffer, sizeof(buffer), "%s", [command UTF8String]);
    int status = [self submitLine:buffer];
    if (status == 0)
    {
        if (mode == 1)
            [self setCommandStatus:[NSString stringWithFormat:@"Script completed: %@", path]];
        else if (mode == 2)
        {
            g_state.journal_recording = 1;
            [self setCommandStatus:[NSString stringWithFormat:@"Recording journal: %@", path]];
        }
        else
            [self setCommandStatus:[NSString stringWithFormat:@"Journal replay completed: %@", path]];
    }
    else
        [self setCommandStatus:[NSString stringWithFormat:@"%@ failed (error %d)",
                                mode == 1 ? @"Script" : (mode == 2 ? @"Journal recording" : @"Journal replay"), status]];
    [self updateStatus];
    [self.graphicsView setNeedsDisplay:YES];
}

/* -- ribbon construction --------------------------------------------- */

- (NSButton *)makeIconTextButton:(const char *)iconName title:(NSString *)title iconSize:(CGFloat)iconSize
                          action:(SEL)action tag:(NSInteger)tag
{
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.font = [NSFont systemFontOfSize:9];
    button.tag = tag;
    NSImage *icon = WcLoadIcon(iconName, iconSize);
    if (icon != nil)
    {
        button.image = icon;
        button.imagePosition = NSImageAbove;
        button.imageScaling = NSImageScaleProportionallyDown;
    }
    [[button cell] setLineBreakMode:NSLineBreakByTruncatingTail];
    return button;
}

- (WcGroupView *)beginGroup:(NSString *)caption
{
    WcGroupView *group = [[WcGroupView alloc] initWithFrame:NSZeroRect];
    group.fillColour = [NSColor clearColor];
    group.rightBorderColour = WcGroupBorder();
    group.caption = caption;
    return group;
}

- (void)rebuildRibbon
{
    const WcCocoaRibbonSnapshot *ribbon = [self activeRibbon];

    /* Tab row: persistent Sections/Mods first, then contextual tabs. */
    for (NSView *subview in [self.tabsHost.subviews copy])
        [subview removeFromSuperview];
    CGFloat x = 6.0;
    WcTabButton *sectionsTab = [self makeTabButton:@"Sections" tabId:"global.sections"];
    sectionsTab.frame = NSMakeRect(x, 1, 84, 26);
    [self.tabsHost addSubview:sectionsTab];
    x += 88.0;
    WcTabButton *modsTab = [self makeTabButton:@"Mods" tabId:"global.mods"];
    modsTab.frame = NSMakeRect(x, 1, 64, 26);
    [self.tabsHost addSubview:modsTab];
    x += 68.0;

    if (ribbon == NULL || ribbon->tab_count == 0)
    {
        if (![self ribbonHasTab:g_state.active_ribbon_tab])
            WcCopyText(g_state.active_ribbon_tab, sizeof(g_state.active_ribbon_tab), "global.sections");
    }
    else
    {
        if (![self ribbonHasTab:g_state.active_ribbon_tab])
            WcCopyText(g_state.active_ribbon_tab, sizeof(g_state.active_ribbon_tab), ribbon->tabs[0].id);
        for (size_t i = 0; i < ribbon->tab_count; ++i)
        {
            NSString *label = WcHumanise(ribbon->tabs[i].id);
            WcTabButton *tab = [self makeTabButton:label tabId:ribbon->tabs[i].id];
            NSSize natural = [[tab cell] cellSize];
            CGFloat width = natural.width + 20 < 70 ? 70 : natural.width + 20;
            tab.frame = NSMakeRect(x, 1, width, 26);
            [self.tabsHost addSubview:tab];
            x += width + 4.0;
        }
    }

    [self rebuildRibbonGroupsWithRibbon:ribbon];
}

- (void)rebuildRibbonGroupsWithRibbon:(const WcCocoaRibbonSnapshot *)ribbon
{
    [self.commandIds removeAllObjects];
    NSView *document = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 64, 110)];
    CGFloat docX = 5.0;
    int compact = g_state.ribbon_density > 0;
    CGFloat buttonWidth = compact ? 58.0 : 82.0;
    CGFloat buttonHeight = compact ? 50.0 : 76.0;
    CGFloat iconSize = compact ? 22.0 : 34.0;

    if (strcmp(g_state.active_ribbon_tab, "global.sections") == 0)
    {
        /* Sections group: 4-per-row icon buttons, then the persistent Mods group. */
        const WcCocoaSectionEntry *entries = NULL;
        size_t count = 0;
        if (g_callbacks.section_entries != NULL)
            entries = g_callbacks.section_entries(g_userData, &count);
        WcGroupView *group = [self beginGroup:@"Sections"];
        [self.sectionIds removeAllObjects];
        CGFloat innerX = 5.0, innerY = 16.0;
        CGFloat groupWidth = 10.0, groupHeight = 32.0;
        size_t inRow = 0;
        for (size_t i = 0; entries != NULL && i < count; ++i)
        {
            NSButton *button = [self makeIconTextButton:entries[i].icon_name
                                                  title:WcHumanise(entries[i].id)
                                               iconSize:compact ? 22 : 30
                                                 action:@selector(onSectionButtonClicked:)
                                                    tag:(NSInteger)i];
            CGFloat sectionWidth = compact ? 62.0 : 80.0;
            CGFloat sectionHeight = compact ? 50.0 : 70.0;
            if (inRow == 4)
            {
                inRow = 0;
                innerX = 5.0;
                innerY += sectionHeight + 2.0;
            }
            button.frame = NSMakeRect(innerX, innerY, sectionWidth, sectionHeight);
            button.toolTip = WcString(entries[i].id);
            [group addSubview:button];
            [self.sectionIds addObject:WcString(entries[i].id)];
            innerX += sectionWidth + 2.0;
            if (innerX + 5.0 > groupWidth)
                groupWidth = innerX + 5.0;
            if (innerY + sectionHeight + 16.0 > groupHeight)
                groupHeight = innerY + sectionHeight + 16.0;
            ++inRow;
        }
        group.frame = NSMakeRect(docX, 2, groupWidth, groupHeight);
        [document addSubview:group];
        docX += groupWidth + 4.0;

        WcGroupView *mods = [self beginGroup:@"Mods"];
        NSButton *manageMods = [self makeIconTextButton:"tab_mods" title:@"Manage Mods" iconSize:26 action:NULL tag:0];
        manageMods.enabled = NO;
        manageMods.target = nil;
        manageMods.frame = NSMakeRect(5, 16, 92, 56);
        manageMods.toolTip = @"Dynamic Mod discovery is still a P1 roadmap item; the versioned Mod ABI already exists";
        [mods addSubview:manageMods];
        mods.frame = NSMakeRect(docX, 2, 102, 90);
        [document addSubview:mods];
        docX += 106.0;
    }
    else if (strcmp(g_state.active_ribbon_tab, "global.mods") == 0)
    {
        WcGroupView *mods = [self beginGroup:@"Mods"];
        NSButton *manageMods = [self makeIconTextButton:"tab_mods" title:@"Manage Mods" iconSize:26 action:NULL tag:0];
        manageMods.enabled = NO;
        manageMods.target = nil;
        manageMods.frame = NSMakeRect(5, 16, 92, 56);
        manageMods.toolTip = @"Dynamic Mod discovery is still a P1 roadmap item; the versioned Mod ABI already exists";
        [mods addSubview:manageMods];
        mods.frame = NSMakeRect(docX, 2, 102, 90);
        [document addSubview:mods];
        docX += 106.0;
    }
    else if (ribbon == NULL)
    {
        NSTextField *placeholder = [NSTextField labelWithString:@"This Section does not have a contextual ribbon yet."];
        placeholder.font = [NSFont systemFontOfSize:11];
        placeholder.textColor = WcSubtle();
        placeholder.frame = NSMakeRect(docX, 44, 340, 16);
        [document addSubview:placeholder];
        docX += 348.0;
    }
    else
    {
        const char *lastGroup = NULL;
        WcGroupView *group = nil;
        CGFloat innerX = 5.0, innerY = 16.0;
        CGFloat groupWidth = 10.0, groupHeight = 32.0;
        size_t inRow = 0;

        for (size_t i = 0; i < ribbon->command_count; ++i)
        {
            const WcCocoaRibbonCommand *command = &ribbon->commands[i];
            if (command->tab_id == NULL || strcmp(command->tab_id, g_state.active_ribbon_tab) != 0)
                continue;
            if (lastGroup == NULL || command->group_id == NULL || strcmp(lastGroup, command->group_id) != 0)
            {
                /* GTK4 ribbon_compact_mode parity: a group with more than four
                   commands, or any group on a narrow window, renders compact. */
                size_t groupCommands = 0;
                for (size_t j = i; j < ribbon->command_count; ++j)
                {
                    const WcCocoaRibbonCommand *candidate = &ribbon->commands[j];
                    if (candidate->tab_id == NULL || strcmp(candidate->tab_id, g_state.active_ribbon_tab) != 0)
                        continue;
                    if ((command->group_id == NULL) != (candidate->group_id == NULL))
                        continue;
                    if (command->group_id != NULL && strcmp(command->group_id, candidate->group_id) != 0)
                        continue;
                    ++groupCommands;
                }
                int groupCompact = groupCommands > 4 || g_state.window_width_hint < 1180 ? 1 : 0;
                buttonWidth = groupCompact ? 58.0 : 82.0;
                buttonHeight = groupCompact ? 50.0 : 76.0;
                iconSize = groupCompact ? 22.0 : 34.0;
                if (group != nil)
                {
                    group.frame = NSMakeRect(group.frame.origin.x, 2, groupWidth, groupHeight);
                    [document addSubview:group];
                    docX += groupWidth + 4.0;
                }
                group = [self beginGroup:WcHumanise(command->group_id != NULL ? command->group_id : "group")];
                group.frame = NSMakeRect(docX, 2, 100, 92); /* provisional; finalised below */
                lastGroup = command->group_id;
                innerX = 5.0;
                innerY = 16.0;
                groupWidth = 10.0;
                groupHeight = 32.0;
                inRow = 0;
            }
            NSButton *button = [self makeIconTextButton:command->icon_name
                                                  title:WcHumanise(command->id)
                                               iconSize:iconSize
                                                 action:@selector(onCommandClicked:)
                                                    tag:(NSInteger)self.commandIds.count];
            button.enabled = (command->flags & WC_COCOA_RIBBON_FLAG_PLANNED) == 0;
            button.frame = NSMakeRect(innerX, innerY, buttonWidth, buttonHeight);
            button.toolTip = [NSString stringWithFormat:@"%@\n%@", WcString(command->localisation_key), WcString(command->id)];
            [group addSubview:button];
            [self.commandIds addObject:WcString(command->id)];
            innerX += buttonWidth + 2.0;
            if (innerX + 5.0 > groupWidth)
                groupWidth = innerX + 5.0;
            if (innerY + buttonHeight + 16.0 > groupHeight)
                groupHeight = innerY + buttonHeight + 16.0;
            ++inRow;
            if (inRow == 4)
            {
                inRow = 0;
                innerX = 5.0;
                innerY += buttonHeight + 2.0;
            }
        }
        if (group != nil)
        {
            group.frame = NSMakeRect(group.frame.origin.x, 2, groupWidth, groupHeight);
            [document addSubview:group];
            docX += groupWidth + 4.0;
        }

        /* Scripts lives in the Home ribbon group. */
        if (strstr(g_state.active_ribbon_tab, ".home") != NULL)
        {
            WcGroupView *scripts = [self beginGroup:@"Scripts"];
            NSButton *runScript = [self makeIconTextButton:"cmd_script" title:@"Run Script" iconSize:compact ? 22 : 30
                                                    action:@selector(onCommandClicked:) tag:(NSInteger)self.commandIds.count];
            [self.commandIds addObject:@"modelling.run_script"];
            runScript.frame = NSMakeRect(5, 16, buttonWidth, buttonHeight);
            [scripts addSubview:runScript];
            NSButton *commandLine = [self makeIconTextButton:"cmd_command" title:@"Command Line" iconSize:compact ? 22 : 30
                                                      action:@selector(onCommandClicked:) tag:(NSInteger)self.commandIds.count];
            [self.commandIds addObject:@"modelling.focus_command_line"];
            commandLine.frame = NSMakeRect(5 + buttonWidth + 2, 16, buttonWidth, buttonHeight);
            [scripts addSubview:commandLine];
            scripts.frame = NSMakeRect(docX, 2, buttonWidth * 2 + 14, buttonHeight + 32);
            [document addSubview:scripts];
            docX += buttonWidth * 2 + 18.0;
        }
    }

    document.frame = NSMakeRect(0, 0, docX + 8, 110);
    self.groupsScroll.documentView = document;
    [self.groupsScroll.contentView scrollToPoint:NSMakePoint(0, 0)];
    [self.groupsScroll reflectScrolledClipView:self.groupsScroll.contentView];
}

/* -- navigator -------------------------------------------------------- */

- (void)refreshModelNavigator
{
    WcCocoaFeatureRow rows[WC_COCOA_FEATURE_ROW_CAPACITY];
    WcCocoaPlanarFaceRow faces[WC_COCOA_FACE_ROW_CAPACITY];
    WcCocoaModelSnapshot snapshot;
    size_t count = 0, faceCount = 0;

    WcGetSnapshot(&snapshot);
    self.modelNameLabel.stringValue = snapshot.model_name != NULL ? WcString(snapshot.model_name) : @"untitled";
    self.modelNameLabel.toolTip = self.modelNameLabel.stringValue;
    self.assemblyNameLabel.stringValue = self.modelNameLabel.stringValue;

    [g_rows removeAllObjects];
    if (g_callbacks.feature_rows != NULL)
        count = g_callbacks.feature_rows(g_userData, rows, WC_COCOA_FEATURE_ROW_CAPACITY);
    if (count > WC_COCOA_FEATURE_ROW_CAPACITY)
        count = WC_COCOA_FEATURE_ROW_CAPACITY;
    if (g_callbacks.planar_face_rows != NULL)
        faceCount = g_callbacks.planar_face_rows(g_userData, faces, WC_COCOA_FACE_ROW_CAPACITY);
    if (faceCount > WC_COCOA_FACE_ROW_CAPACITY)
        faceCount = WC_COCOA_FACE_ROW_CAPACITY;

    if (count == 0)
    {
        WcRow *placeholder = [[WcRow alloc] init];
        placeholder.text = @"Model History";
        placeholder.realFeature = NO;
        [g_rows addObject:placeholder];
        g_state.selected_feature_id = 0;
        [self.table reloadData];
        return;
    }

    for (size_t i = 0; i < count; ++i)
    {
        NSMutableString *text = [NSMutableString stringWithString:rows[i].name != NULL ? WcString(rows[i].name) : @"feature"];
        if (rows[i].dirty)
            [text appendString:@"  •"];
        if (rows[i].kind == WC_COCOA_FEATURE_KIND_DATUM_CSYS)
            [text appendString:@"  [CSYS]"];
        WcRow *row = [[WcRow alloc] init];
        row.text = text;
        row.featureId = rows[i].id;
        row.featureKind = rows[i].kind;
        row.exactStatus = rows[i].exact_status;
        row.depth = (int)rows[i].dependency_depth;
        row.supportKind = rows[i].kind == WC_COCOA_FEATURE_KIND_DATUM_PLANE ? 1 : 0;
        row.supportFeatureId = rows[i].kind == WC_COCOA_FEATURE_KIND_DATUM_PLANE ? rows[i].id : 0;
        row.realFeature = YES;
        [g_rows addObject:row];

        if (rows[i].kind == WC_COCOA_FEATURE_KIND_DATUM_CSYS)
        {
            static const char *planes[3] = { "XY", "YZ", "XZ" };
            for (int pi = 0; pi < 3; ++pi)
            {
                WcRow *planeRow = [[WcRow alloc] init];
                planeRow.text = [NSString stringWithFormat:@"%s Plane", planes[pi]];
                planeRow.featureId = rows[i].id;
                planeRow.featureKind = rows[i].kind;
                planeRow.depth = (int)rows[i].dependency_depth + 1;
                planeRow.supportKind = 2;
                planeRow.supportFeatureId = rows[i].id;
                planeRow.realFeature = NO;
                [g_rows addObject:planeRow];
            }
        }
        for (size_t f = 0; f < faceCount; ++f)
        {
            if (faces[f].owner_feature_id == rows[i].id)
            {
                WcRow *faceRow = [[WcRow alloc] init];
                faceRow.text = [NSString stringWithFormat:@"Face %u  (planar)", faces[f].semantic_slot];
                faceRow.featureId = rows[i].id;
                faceRow.featureKind = rows[i].kind;
                faceRow.depth = (int)rows[i].dependency_depth + 1;
                faceRow.supportKind = 3;
                faceRow.supportFeatureId = rows[i].id;
                faceRow.faceId = faces[f].persistent_id;
                faceRow.realFeature = NO;
                [g_rows addObject:faceRow];
            }
        }
    }
    [self reloadNavigatorKeepingSelection];
}

- (void)reloadNavigatorKeepingSelection
{
    self.programmaticSelection = YES;
    [self.table reloadData];
    if (g_state.selected_feature_id != 0)
    {
        for (NSUInteger i = 0; i < g_rows.count; ++i)
        {
            WcRow *row = g_rows[i];
            if (row.realFeature && row.featureId == g_state.selected_feature_id)
            {
                [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
                break;
            }
        }
    }
    self.programmaticSelection = NO;
}

- (void)syncNavigatorSelectionToState
{
    for (NSUInteger i = 0; i < g_rows.count; ++i)
    {
        WcRow *row = g_rows[i];
        if (row.realFeature && row.featureId == g_state.selected_feature_id)
        {
            g_state.selected_feature_kind = row.featureKind;
            g_state.selected_feature_exact_status = row.exactStatus;
            g_state.selected_feature_depth = (uint32_t)row.depth;
            break;
        }
    }
}

- (NSInteger)numberOfRowsInTable:(NSTableView *)tableView
{
    (void)tableView;
    return (NSInteger)g_rows.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    (void)tableColumn;
    WcRow *record = g_rows[(NSUInteger)row];
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, tableView.bounds.size.width, 20)];
    view.wantsLayer = YES;

    BOOL selected = [tableView selectedRow] == row;
    BOOL descendant = !record.realFeature && g_state.selected_body_feature_id != 0 &&
                      record.supportFeatureId == g_state.selected_body_feature_id;
    if (selected)
        view.layer.backgroundColor = [WcRowSelectedBackground() CGColor];
    else if (descendant)
        view.layer.backgroundColor = [WcDescendantBackground() CGColor];
    else
        view.layer.backgroundColor = [g_navigatorColour CGColor];

    NSTextField *label = [NSTextField labelWithString:record.text];
    label.font = [NSFont systemFontOfSize:10];
    if (selected)
        label.textColor = WcRowSelectedText();
    else if (descendant)
        label.textColor = WcDescendantText();
    else
        label.textColor = record.realFeature ? WcRowText() : WcSubtle();
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    CGFloat indent = 4.0 + (record.depth > 0 ? record.depth * 12.0 : 0.0);
    CGFloat badgeWidth = record.realFeature && record.exactStatus != 0 ? 48.0 : 0.0;
    label.frame = NSMakeRect(indent, 2, view.bounds.size.width - indent - badgeWidth - 8, 16);
    [view addSubview:label];

    if (badgeWidth > 0)
    {
        NSTextField *badge = [NSTextField labelWithString:WcString(WcExactStatusText(record.exactStatus))];
        badge.font = [NSFont systemFontOfSize:8];
        badge.alignment = NSTextAlignmentCenter;
        badge.wantsLayer = YES;
        badge.layer.cornerRadius = 7.0;
        NSColor *badgeBackground = record.exactStatus == 1u ? WcHex("#214a35", nil)
                                 : (record.exactStatus == 3u ? WcHex("#57262e", nil) : WcHex("#4b3a1d", nil));
        NSColor *badgeText = record.exactStatus == 1u ? WcHex("#b7f5d0", nil)
                           : (record.exactStatus == 3u ? WcHex("#ffbdc6", nil) : WcHex("#ffe1a0", nil));
        badge.layer.backgroundColor = [badgeBackground CGColor];
        badge.textColor = badgeText;
        badge.frame = NSMakeRect(view.bounds.size.width - badgeWidth - 4, 3, badgeWidth, 14);
        [view addSubview:badge];
    }
    return view;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    (void)notification;
    if (self.programmaticSelection)
        return;
    NSInteger row = self.table.selectedRow;
    g_state.selected_feature_id = 0;
    g_state.selected_feature_kind = 0;
    g_state.selected_feature_exact_status = 0;
    g_state.selected_feature_depth = 0;
    g_state.selected_feature_name[0] = '\0';
    g_state.selected_body_feature_id = 0;
    if (row >= 0 && (size_t)row < g_rows.count)
    {
        WcRow *record = g_rows[(NSUInteger)row];
        g_state.selected_feature_id = record.featureId;
        g_state.selected_feature_kind = record.featureKind;
        g_state.selected_feature_exact_status = record.exactStatus;
        g_state.selected_feature_depth = (uint32_t)record.depth;
        WcCopyText(g_state.selected_feature_name, sizeof(g_state.selected_feature_name), [record.text UTF8String]);
        if (record.realFeature)
        {
            WcCocoaBodyRow body;
            if (WcBodyBoundsForFeature(record.featureId, &body))
                g_state.selected_body_feature_id = record.featureId;
        }
    }
    [self reloadNavigatorKeepingSelection];
    [self.graphicsView setNeedsDisplay:YES];
}

- (void)onRowActivated:(NSTableView *)sender
{
    NSInteger row = sender.clickedRow;
    if (row < 0 || (size_t)row >= g_rows.count)
        return;
    WcRow *record = g_rows[(NSUInteger)row];
    if (!record.realFeature)
        return;
    g_state.selected_feature_id = record.featureId;
    g_state.selected_feature_kind = record.featureKind;
    [self showFeatureProperties:record.featureId];
}

- (NSMenu *)navigatorMenuForEvent:(NSEvent *)event
{
    (void)event;
    NSInteger row = self.table.selectedRow;
    if (row < 0 || (size_t)row >= g_rows.count)
        return nil;
    WcRow *record = g_rows[(NSUInteger)row];
    if (!record.realFeature)
        return nil;
    NSMenu *menu = [[NSMenu alloc] init];
    NSMenuItem *properties = [[NSMenuItem alloc] initWithTitle:@"Edit / Properties" action:@selector(navigatorProperties:) keyEquivalent:@""];
    properties.target = self;
    properties.representedObject = @(row);
    [menu addItem:properties];
    WcCocoaBodyRow body;
    NSMenuItem *fit = [[NSMenuItem alloc] initWithTitle:@"Fit to Feature" action:@selector(navigatorFit:) keyEquivalent:@""];
    fit.target = self;
    fit.representedObject = @(row);
    fit.enabled = WcBodyBoundsForFeature(record.featureId, &body) ? YES : NO;
    [menu addItem:fit];
    if (record.featureKind == WC_COCOA_FEATURE_KIND_SKETCH)
    {
        NSMenuItem *editSketch = [[NSMenuItem alloc] initWithTitle:@"Edit Sketch" action:@selector(navigatorEditSketch:) keyEquivalent:@""];
        editSketch.target = self;
        editSketch.representedObject = @(row);
        editSketch.enabled = NO; /* interactive sketch mode is GTK4-only in this increment */
        [menu addItem:editSketch];
    }
    NSMenuItem *deleteItem = [[NSMenuItem alloc] initWithTitle:@"Delete" action:@selector(navigatorDelete:) keyEquivalent:@""];
    deleteItem.target = self;
    deleteItem.representedObject = @(row);
    [menu addItem:deleteItem];
    return menu;
}

- (void)navigatorProperties:(NSMenuItem *)sender
{
    WcRow *record = [self rowForMenuItem:sender];
    if (record != nil)
        [self showFeatureProperties:record.featureId];
}

- (void)navigatorFit:(NSMenuItem *)sender
{
    WcRow *record = [self rowForMenuItem:sender];
    if (record == nil)
        return;
    if (WcFitFeature(record.featureId))
        [self setCommandStatus:@"Fit — selected body"];
    else
        [self setCommandStatus:@"No selected body with display bounds"];
    [self.graphicsView setNeedsDisplay:YES];
}

- (void)navigatorEditSketch:(NSMenuItem *)sender
{
    (void)sender;
    [self setCommandStatus:@"Interactive sketch editing is GTK4-only in this Cocoa increment"];
}

- (void)navigatorDelete:(NSMenuItem *)sender
{
    WcRow *record = [self rowForMenuItem:sender];
    if (record == nil)
        return;
    [self runFeatureAction:record.featureId action:0];
}

- (WcRow *)rowForMenuItem:(NSMenuItem *)sender
{
    NSNumber *rowNumber = sender.representedObject;
    if (rowNumber == nil || (NSUInteger)rowNumber.integerValue >= g_rows.count)
        return nil;
    return g_rows[(NSUInteger)rowNumber.integerValue];
}

- (void)runFeatureAction:(uint32_t)featureId action:(int)action
{
    if (featureId == 0 || g_callbacks.feature_action == NULL)
    {
        [self setCommandStatus:@"Select a model-history feature first"];
        return;
    }
    int status = g_callbacks.feature_action(g_userData, featureId, action);
    if (status != 0)
    {
        if (action == 0)
            [self setCommandStatus:[NSString stringWithFormat:@"Delete rejected (SCL error %d). A dependent feature may still reference it.", status]];
        else
            [self setCommandStatus:[NSString stringWithFormat:@"Reorder rejected (SCL error %d). Dependency order must be preserved.", status]];
        return;
    }
    if (action == 0)
    {
        g_state.selected_feature_id = 0;
        g_state.selected_body_feature_id = 0;
        g_state.selected_feature_name[0] = '\0';
        g_state.fit_bounds_valid = 0;
    }
    [self updateStatus];
    [self.graphicsView setNeedsDisplay:YES];
    [self setCommandStatus:action == 0 ? @"Feature deleted" : @"Feature reordered"];
}

/* Drag-and-drop reordering, mirroring the GTK4 drop semantics. */

- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row
{
    (void)tableView;
    if (row < 0 || (size_t)row >= g_rows.count)
        return nil;
    WcRow *record = g_rows[(NSUInteger)row];
    if (!record.realFeature)
        return nil;
    NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
    [item setString:[NSString stringWithFormat:@"%u", record.featureId] forType:NSPasteboardTypeString];
    return item;
}

- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)operation
{
    (void)tableView;
    if (operation != NSTableViewDropOn || row < 0 || (size_t)row >= g_rows.count)
        return NSDragOperationNone;
    WcRow *target = g_rows[(NSUInteger)row];
    if (!target.realFeature)
        return NSDragOperationNone;
    NSString *sourceText = [[info draggingPasteboard] stringForType:NSPasteboardTypeString];
    if (sourceText == nil)
        return NSDragOperationNone;
    uint32_t sourceId = (uint32_t)[sourceText intValue];
    if (sourceId == 0 || sourceId == target.featureId)
        return NSDragOperationNone;
    return NSDragOperationMove;
}

- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id<NSDraggingInfo>)info
              row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation
{
    (void)operation;
    NSString *sourceText = [[info draggingPasteboard] stringForType:NSPasteboardTypeString];
    if (sourceText == nil || row < 0 || (size_t)row >= g_rows.count || g_callbacks.feature_reorder == NULL)
        return NO;
    WcRow *target = g_rows[(NSUInteger)row];
    uint32_t sourceId = (uint32_t)[sourceText intValue];
    if (sourceId == 0 || sourceId == target.featureId)
        return NO;
    NSPoint location = [tableView convertPoint:[info draggingLocation] fromView:nil];
    NSRect rowRect = [tableView rectOfRow:row];
    int after = location.y > NSMidY(rowRect) ? 1 : 0; /* NSTableView is flipped: y grows downward, matching GTK */
    int status = g_callbacks.feature_reorder(g_userData, sourceId, target.featureId, after);
    if (status != 0)
    {
        [self setCommandStatus:[NSString stringWithFormat:@"Reorder rejected (SCL error %d). A dependency blocks that history position.", status]];
        return NO;
    }
    g_state.selected_feature_id = sourceId;
    [self updateStatus];
    [self.graphicsView setNeedsDisplay:YES];
    [self setCommandStatus:@"Feature reordered by drag-and-drop"];
    return YES;
}

/* -- rail + pages ------------------------------------------------------ */

- (void)onRailModel:(NSButton *)sender { (void)sender; [self showNavigatorPage:@"model"]; }
- (void)onRailAssembly:(NSButton *)sender { (void)sender; [self showNavigatorPage:@"assembly"]; }
- (void)onRailAi:(NSButton *)sender
{
    (void)sender;
    [self updateAiSummary];
    [self showNavigatorPage:@"ai"];
}

- (void)showNavigatorPage:(NSString *)page
{
    self.modelPage.hidden = ![page isEqualToString:@"model"];
    self.assemblyPage.hidden = ![page isEqualToString:@"assembly"];
    self.aiPage.hidden = ![page isEqualToString:@"ai"];
    if (self.navigatorHost.frame.size.width < 40)
        [self.splitView setPosition:210 ofDividerAtIndex:0];
}

- (void)onOpenAssemblySection:(NSButton *)sender
{
    (void)sender;
    [self chooseSection:"assembly"];
}

- (void)onRefreshAiSummary:(NSButton *)sender
{
    (void)sender;
    [self updateAiSummary];
    [self setCommandStatus:@"AI Agent refreshed read-only model summary"];
}

- (void)onFocusCommandLine:(NSButton *)sender
{
    (void)sender;
    [self focusCommandLine];
}

- (void)updateAiSummary
{
    WcCocoaModelSnapshot snapshot;
    WcGetSnapshot(&snapshot);
    self.aiSummaryLabel.stringValue = [NSString stringWithFormat:
        @"Read-only model context\n\nModel: %s\nFeatures: %u\nExact: %u\nPreview: %u\nFailed: %u\n\n"
        @"The provider-neutral AI ABI exists, but no external provider is connected in this Cocoa bootstrap.",
        snapshot.model_name != NULL ? snapshot.model_name : "untitled",
        snapshot.feature_count, snapshot.exact_count, snapshot.preview_count, snapshot.failed_count];
}

/* -- fit / panels ------------------------------------------------------ */

- (void)viewportFitAll:(id)sender
{
    (void)sender;
    WcFitAll();
    [self setCommandStatus:@"Fit — whole model"];
    [self.graphicsView setNeedsDisplay:YES];
}

- (void)viewportFitSelected:(id)sender
{
    (void)sender;
    if (g_state.selected_body_feature_id == 0 || !WcFitFeature(g_state.selected_body_feature_id))
    {
        [self setCommandStatus:@"No selected body with display bounds"];
        return;
    }
    [self setCommandStatus:@"Fit — selected body"];
    [self.graphicsView setNeedsDisplay:YES];
}

- (void)viewportProperties:(id)sender
{
    (void)sender;
    if (g_state.selected_feature_id != 0)
        [self showFeatureProperties:g_state.selected_feature_id];
}

- (void)showFeatureProperties:(uint32_t)featureId
{
    WcCocoaBodyRow body;
    NSMutableString *text = [NSMutableString string];
    [text appendFormat:@"Feature ID: %u\nKind: %u\nGeometry: %s\nDependency depth: %u\n",
        featureId, g_state.selected_feature_kind,
        WcExactStatusText(g_state.selected_feature_exact_status), g_state.selected_feature_depth];
    if (WcBodyBoundsForFeature(featureId, &body))
        [text appendFormat:@"\nBounds\nX: %.6g .. %.6g\nY: %.6g .. %.6g\nZ: %.6g .. %.6g",
            body.min_x, body.max_x, body.min_y, body.max_y, body.min_z, body.max_z];
    NSString *title = g_state.selected_feature_name[0] != '\0'
        ? [NSString stringWithUTF8String:g_state.selected_feature_name]
        : @"Feature";
    [self presentInfoPanel:@"Feature Properties" heading:title body:text width:360 height:250];
    [self selectNavigatorRowForFeature:featureId];
}

- (void)showMassProperties:(uint32_t)featureId
{
    WcCocoaMassProperties properties;
    memset(&properties, 0, sizeof(properties));
    if (g_callbacks.mass_properties == NULL)
        return;
    int status = g_callbacks.mass_properties(g_userData, featureId, &properties);
    if (status != 0 || !properties.valid)
    {
        [self setCommandStatus:@"Mass properties require supported exact solid geometry"];
        return;
    }
    char name[WC_COCOA_UI_ID_CAPACITY];
    if (!WcFeatureNameForId(featureId, name, sizeof(name)))
        WcCopyText(name, sizeof(name), "feature");
    NSMutableString *text = [NSMutableString string];
    [text appendFormat:@"Volume: %.6g mm³\nSurface area: %.6g mm²\nCentre of mass: (%.6g, %.6g, %.6g)",
        properties.volume, properties.surface_area,
        properties.centre_of_mass[0], properties.centre_of_mass[1], properties.centre_of_mass[2]];
    [self presentInfoPanel:@"Mass Properties" heading:[NSString stringWithUTF8String:name] body:text width:390 height:260];
}

- (void)selectNavigatorRowForFeature:(uint32_t)featureId
{
    for (NSUInteger i = 0; i < g_rows.count; ++i)
    {
        WcRow *row = g_rows[i];
        if (row.realFeature && row.featureId == featureId)
        {
            self.programmaticSelection = YES;
            [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
            self.programmaticSelection = NO;
            break;
        }
    }
}

- (void)presentInfoPanel:(NSString *)panelTitle heading:(NSString *)heading body:(NSString *)body
                   width:(CGFloat)width height:(CGFloat)height
{
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, width, height)
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    panel.title = panelTitle;
    panel.releasedWhenClosed = NO;
    panel.delegate = self;
    WcPanelView *content = [[WcPanelView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
    content.fillColour = WcWindowBackground();
    content.flippedLayout = YES;
    NSTextField *titleLabel = [NSTextField labelWithString:heading];
    titleLabel.font = [NSFont boldSystemFontOfSize:16];
    titleLabel.textColor = WcTitlePink();
    titleLabel.frame = NSMakeRect(12, 12, width - 24, 22);
    titleLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [content addSubview:titleLabel];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(12, 42, width - 24, height - 54)];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSNoBorder;
    scroll.backgroundColor = WcWindowBackground();
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, width - 40, height - 60)];
    textView.autoresizingMask = NSViewWidthSizable;
    textView.editable = NO;
    textView.selectable = YES;
    textView.richText = NO;
    textView.backgroundColor = WcWindowBackground();
    textView.textColor = WcSubtle();
    textView.font = [NSFont fontWithName:@"Menlo" size:11] ?: [NSFont systemFontOfSize:11];
    textView.string = body;
    scroll.documentView = textView;
    [content addSubview:scroll];
    panel.contentView = content;
    if (g_panels == nil)
        g_panels = [NSMutableArray array];
    [g_panels addObject:panel];
    [panel center];
    [panel makeKeyAndOrderFront:nil];
}

/* -- status ------------------------------------------------------------ */

- (void)updateStatus
{
    WcCocoaModelSnapshot snapshot;
    WcGetSnapshot(&snapshot);
    self.modelStatusLabel.stringValue = [NSString stringWithFormat:@"Features %u   Exact %u   Preview %u   Failed %u",
        snapshot.feature_count, snapshot.exact_count, snapshot.preview_count, snapshot.failed_count];
    [self refreshModelNavigator];
    [self updateAiSummary];
}

/* -- console ------------------------------------------------------------ */

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector
{
    (void)control;
    (void)textView;
    if (commandSelector == @selector(insertNewline:))
    {
        [self commandActivated];
        return YES;
    }
    if (commandSelector == @selector(cancelOperation:))
    {
        [self.window makeFirstResponder:self.graphicsView];
        [self setCommandStatus:@"Viewport focus — wheel zoom, middle-drag orbit, WASD pan, Enter for command line"];
        return YES;
    }
    return NO;
}

/* -- window ------------------------------------------------------------- */

- (void)windowDidResize:(NSNotification *)notification
{
    (void)notification;
    int width = (int)self.window.frame.size.width;
    int density = width < 820 ? 2 : (width < 1180 ? 1 : 0);
    if (density != g_state.ribbon_density)
    {
        g_state.ribbon_density = density;
        g_state.window_width_hint = width;
        [self rebuildRibbon];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    (void)sender;
    return YES;
}

- (void)windowWillClose:(NSNotification *)notification
{
    NSWindow *window = notification.object;
    if (window != nil && [window isKindOfClass:[NSPanel class]])
        [g_panels removeObject:window];
}

/* -- construction -------------------------------------------------------- */

- (void)buildUiWithConfig:(const WcCocoaWindowConfig *)config
{
    CGFloat width = config->width > 0 ? (CGFloat)config->width : 1024.0;
    CGFloat height = config->height > 0 ? (CGFloat)config->height : 768.0;
    NSString *title = config->title != NULL ? WcString(config->title) : @"WaifuCAD";

    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                              NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, width, height)
                                              styleMask:style
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = title;
    self.window.backgroundColor = WcWindowBackground();
    [self.window setContentMinSize:NSMakeSize(800, 600)];
    self.window.delegate = self;

    self.commandIds = [NSMutableArray array];
    self.sectionIds = [NSMutableArray array];

    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
    self.window.contentView = content;

    const CGFloat ribbonHeight = 140.0;
    const CGFloat statusHeight = 22.0;
    const CGFloat railWidth = 48.0;

    /* Ribbon: tab row + scrolling group row + nightcore art top-right. */
    self.ribbonView = [[WcPanelView alloc] initWithFrame:NSMakeRect(0, height - ribbonHeight, width, ribbonHeight)];
    self.ribbonView.fillColour = WcRibbonBackground();
    self.ribbonView.bottomBorderColour = WcRibbonBorder();
    self.ribbonView.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [content addSubview:self.ribbonView];

    self.tabsHost = [[NSView alloc] initWithFrame:NSMakeRect(0, ribbonHeight - 28, width - 128, 28)];
    self.tabsHost.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [self.ribbonView addSubview:self.tabsHost];

    self.groupsScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, width - 128, 112)];
    self.groupsScroll.hasHorizontalScroller = YES;
    self.groupsScroll.hasVerticalScroller = NO;
    self.groupsScroll.borderType = NSNoBorder;
    self.groupsScroll.backgroundColor = WcRibbonBackground();
    self.groupsScroll.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [self.ribbonView addSubview:self.groupsScroll];

    NSImage *nightcore = g_nightcore;
    if (nightcore != nil)
    {
        self.nightcoreView = [[NSImageView alloc] initWithFrame:NSMakeRect(width - 124, 26, 112, 88)];
        self.nightcoreView.image = nightcore;
        self.nightcoreView.imageScaling = NSImageScaleProportionallyDown;
        self.nightcoreView.toolTip = @"Nightcore theme image";
        self.nightcoreView.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
        [self.ribbonView addSubview:self.nightcoreView];
    }

    /* Navigator rail (persistent, 48 px). */
    self.railView = [[WcPanelView alloc] initWithFrame:NSMakeRect(0, statusHeight, railWidth, height - ribbonHeight - statusHeight)];
    self.railView.fillColour = g_railColour;
    self.railView.rightBorderColour = WcRailBorder();
    self.railView.flippedLayout = YES;
    self.railView.autoresizingMask = NSViewHeightSizable | NSViewMaxXMargin;
    [content addSubview:self.railView];

    NSArray<NSString *> *railIcons = @[ @"nav_model", @"nav_assembly", @"nav_ai" ];
    NSArray<NSString *> *railTips = @[ @"Model Navigator", @"Assembly Navigator", @"AI Agent" ];
    NSArray<NSString *> *railActions = @[ @"onRailModel:", @"onRailAssembly:", @"onRailAi:" ];
    for (NSUInteger i = 0; i < railIcons.count; ++i)
    {
        NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(3, 5 + i * 46, 42, 42)];
        NSImage *icon = WcLoadIcon([railIcons[i] UTF8String], 24);
        if (icon != nil)
        {
            button.image = icon;
            button.imagePosition = NSImageOnly;
            button.imageScaling = NSImageScaleProportionallyDown;
        }
        else
            [button setTitle:[railTips[i] substringToIndex:1]];
        button.bezelStyle = NSBezelStyleRegularSquare;
        button.target = self;
        button.action = NSSelectorFromString(railActions[i]);
        button.toolTip = railTips[i];
        [self.railView addSubview:button];
    }

    /* Split pane: collapsible navigator content | graphics overlay host. */
    self.splitView = [[NSSplitView alloc] initWithFrame:NSMakeRect(railWidth, statusHeight, width - railWidth, height - ribbonHeight - statusHeight)];
    self.splitView.vertical = YES;
    self.splitView.dividerStyle = NSSplitViewDividerStyleThin;
    self.splitView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [content addSubview:self.splitView];

    self.navigatorHost = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 210, self.splitView.bounds.size.height)];
    [self.splitView addSubview:self.navigatorHost];
    self.graphicsHost = [[NSView alloc] initWithFrame:NSMakeRect(211, 0, self.splitView.bounds.size.width - 211, self.splitView.bounds.size.height)];
    [self.splitView addSubview:self.graphicsHost];

    [self buildNavigatorPages];
    [self buildGraphicsHost];

    /* Status bar. */
    self.statusBar = [[WcPanelView alloc] initWithFrame:NSMakeRect(0, 0, width, statusHeight)];
    self.statusBar.fillColour = WcStatusBackground();
    self.statusBar.topBorderColour = WcStatusBorder();
    self.statusBar.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [content addSubview:self.statusBar];

    NSTextField *toolkit = [NSTextField labelWithString:@"Cocoa (macOS)"];
    toolkit.font = [NSFont systemFontOfSize:10];
    toolkit.textColor = WcSubtle();
    toolkit.frame = NSMakeRect(8, 4, 120, 14);
    toolkit.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
    [self.statusBar addSubview:toolkit];

    self.rendererStatus = [NSTextField labelWithString:@""];
    self.rendererStatus.font = [NSFont systemFontOfSize:10];
    self.rendererStatus.textColor = WcSubtle();
    self.rendererStatus.lineBreakMode = NSLineBreakByTruncatingTail;
    self.rendererStatus.frame = NSMakeRect(136, 4, width - 144, 14);
    self.rendererStatus.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [self.statusBar addSubview:self.rendererStatus];

    /* Minimal main menu so standard editing key equivalents work. */
    NSMenu *mainMenu = [[NSMenu alloc] init];
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    NSMenu *appMenu = [[NSMenu alloc] init];
    [appMenu addItemWithTitle:@"Quit WaifuCAD" action:@selector(terminate:) keyEquivalent:@"q"];
    appMenuItem.submenu = appMenu;
    [mainMenu addItem:appMenuItem];
    NSMenuItem *editMenuItem = [[NSMenuItem alloc] init];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    editMenuItem.submenu = editMenu;
    [mainMenu addItem:editMenuItem];
    [NSApp setMainMenu:mainMenu];

    self.rendererStatus.stringValue = [NSString stringWithFormat:@"Metal | %s",
        g_gpu.summary[0] != '\0' ? g_gpu.summary : "GPU probe unavailable"];
}

- (void)buildNavigatorPages
{
    CGFloat hostHeight = self.navigatorHost.bounds.size.height;
    CGFloat hostWidth = self.navigatorHost.bounds.size.width;

    /* Model page. */
    self.modelPage = [[WcPanelView alloc] initWithFrame:NSMakeRect(0, 0, hostWidth, hostHeight)];
    self.modelPage.fillColour = g_navigatorColour;
    self.modelPage.flippedLayout = YES;
    self.modelPage.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.navigatorHost addSubview:self.modelPage];

    NSTextField *title = [NSTextField labelWithString:@"Model Navigator"];
    title.font = [NSFont boldSystemFontOfSize:12];
    title.textColor = WcTitlePink();
    title.frame = NSMakeRect(6, 6, hostWidth - 12, 16);
    title.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [self.modelPage addSubview:title];

    self.modelNameLabel = [NSTextField labelWithString:@"untitled"];
    self.modelNameLabel.font = [NSFont boldSystemFontOfSize:13];
    self.modelNameLabel.textColor = WcTextMain();
    self.modelNameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.modelNameLabel.frame = NSMakeRect(6, 24, hostWidth - 12, 18);
    self.modelNameLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [self.modelPage addSubview:self.modelNameLabel];

    self.modelStatusLabel = [NSTextField labelWithString:@"Features 0"];
    self.modelStatusLabel.font = [NSFont systemFontOfSize:11];
    self.modelStatusLabel.textColor = WcSubtle();
    self.modelStatusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.modelStatusLabel.frame = NSMakeRect(6, 43, hostWidth - 12, 14);
    self.modelStatusLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [self.modelPage addSubview:self.modelStatusLabel];

    self.tableScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 60, hostWidth, hostHeight - 60)];
    self.tableScroll.hasVerticalScroller = YES;
    self.tableScroll.borderType = NSNoBorder;
    self.tableScroll.backgroundColor = g_navigatorColour;
    self.tableScroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.modelPage addSubview:self.tableScroll];

    self.table = [[WcNavigatorTable alloc] initWithFrame:NSMakeRect(0, 0, hostWidth, hostHeight - 60)];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"row"];
    column.width = hostWidth - 8;
    [self.table addTableColumn:column];
    self.table.headerView = nil;
    self.table.rowHeight = 20;
    self.table.backgroundColor = g_navigatorColour;
    self.table.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
    self.table.allowsMultipleSelection = NO;
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.doubleAction = @selector(onRowActivated:);
    self.table.target = self;
    self.table.menuTarget = self;
    [self.table registerForDraggedTypes:@[ NSPasteboardTypeString ]];
    self.table.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.tableScroll.documentView = self.table;

    /* Assembly page. */
    self.assemblyPage = [[WcPanelView alloc] initWithFrame:NSMakeRect(0, 0, hostWidth, hostHeight)];
    self.assemblyPage.fillColour = g_navigatorColour;
    self.assemblyPage.flippedLayout = YES;
    self.assemblyPage.hidden = YES;
    self.assemblyPage.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.navigatorHost addSubview:self.assemblyPage];

    NSTextField *assemblyTitle = [NSTextField labelWithString:@"Assembly Navigator"];
    assemblyTitle.font = [NSFont boldSystemFontOfSize:16];
    assemblyTitle.textColor = WcTitlePink();
    assemblyTitle.frame = NSMakeRect(8, 8, hostWidth - 16, 20);
    assemblyTitle.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [self.assemblyPage addSubview:assemblyTitle];

    self.assemblyNameLabel = [NSTextField labelWithString:@"untitled"];
    self.assemblyNameLabel.font = [NSFont boldSystemFontOfSize:13];
    self.assemblyNameLabel.textColor = WcTextMain();
    self.assemblyNameLabel.frame = NSMakeRect(8, 32, hostWidth - 16, 18);
    self.assemblyNameLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [self.assemblyPage addSubview:self.assemblyNameLabel];

    NSTextField *assemblyBody = [NSTextField labelWithString:@"Root occurrence\n  standalone part\n\nAssembly occurrence/load-policy data structures remain planned; suppression and unloading will stay distinct."];
    assemblyBody.font = [NSFont systemFontOfSize:11];
    assemblyBody.textColor = WcSubtle();
    assemblyBody.maximumNumberOfLines = 0;
    assemblyBody.frame = NSMakeRect(8, 56, hostWidth - 16, 96);
    assemblyBody.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [self.assemblyPage addSubview:assemblyBody];

    NSButton *openAssembly = [NSButton buttonWithTitle:@"Open Assembly Section" target:self action:@selector(onOpenAssemblySection:)];
    openAssembly.bezelStyle = NSBezelStyleRounded;
    openAssembly.frame = NSMakeRect(8, 160, hostWidth - 16, 28);
    openAssembly.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    openAssembly.toolTip = @"Switch to the Assembly application context; document structures are still planned";
    [self.assemblyPage addSubview:openAssembly];

    /* AI page. */
    self.aiPage = [[WcPanelView alloc] initWithFrame:NSMakeRect(0, 0, hostWidth, hostHeight)];
    self.aiPage.fillColour = g_navigatorColour;
    self.aiPage.flippedLayout = YES;
    self.aiPage.hidden = YES;
    self.aiPage.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.navigatorHost addSubview:self.aiPage];

    NSTextField *aiTitle = [NSTextField labelWithString:@"AI Agent"];
    aiTitle.font = [NSFont boldSystemFontOfSize:16];
    aiTitle.textColor = WcTitlePink();
    aiTitle.frame = NSMakeRect(8, 8, hostWidth - 16, 20);
    aiTitle.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [self.aiPage addSubview:aiTitle];

    self.aiSummaryLabel = [NSTextField labelWithString:@"Read-only model context"];
    self.aiSummaryLabel.font = [NSFont systemFontOfSize:11];
    self.aiSummaryLabel.textColor = WcSubtle();
    self.aiSummaryLabel.maximumNumberOfLines = 0;
    self.aiSummaryLabel.frame = NSMakeRect(8, 32, hostWidth - 16, hostHeight - 170);
    self.aiSummaryLabel.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.aiPage addSubview:self.aiSummaryLabel];

    NSButton *refreshSummary = [NSButton buttonWithTitle:@"Refresh model summary" target:self action:@selector(onRefreshAiSummary:)];
    refreshSummary.bezelStyle = NSBezelStyleRounded;
    refreshSummary.frame = NSMakeRect(8, hostHeight - 130, hostWidth - 16, 28);
    refreshSummary.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [self.aiPage addSubview:refreshSummary];

    NSTextField *provider = [NSTextField textFieldWithString:@""];
    provider.placeholderString = @"AI provider connection is not configured yet";
    provider.enabled = NO;
    provider.frame = NSMakeRect(8, hostHeight - 96, hostWidth - 16, 24);
    provider.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [self.aiPage addSubview:provider];

    NSButton *focusCommand = [NSButton buttonWithTitle:@"Focus SCL command line" target:self action:@selector(onFocusCommandLine:)];
    focusCommand.bezelStyle = NSBezelStyleRounded;
    focusCommand.frame = NSMakeRect(8, hostHeight - 64, hostWidth - 16, 28);
    focusCommand.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [self.aiPage addSubview:focusCommand];
}

- (void)buildGraphicsHost
{
    CGFloat hostWidth = self.graphicsHost.bounds.size.width;
    CGFloat hostHeight = self.graphicsHost.bounds.size.height;

    self.graphicsView = [[WcGraphicsView alloc] initWithFrame:NSMakeRect(0, 0, hostWidth, hostHeight)];
    self.graphicsView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.graphicsView.controller = self;
    [self.graphicsHost addSubview:self.graphicsView];

    /* Centred command-console overlay (GTK4: 660 wide, bottom, 18 margin). */
    self.commandBox = [[WcCommandBoxView alloc] initWithFrame:NSMakeRect((hostWidth - 660) * 0.5, 18, 660, 62)];
    self.commandBox.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin | NSViewMaxYMargin;
    [self.graphicsHost addSubview:self.commandBox];

    self.commandStatusLabel = [NSTextField labelWithString:@"Viewport ready — Enter focuses command line"];
    self.commandStatusLabel.font = [NSFont systemFontOfSize:11];
    self.commandStatusLabel.textColor = WcSubtle();
    self.commandStatusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.commandStatusLabel.frame = NSMakeRect(8, 40, 644, 15);
    self.commandStatusLabel.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [self.commandBox addSubview:self.commandStatusLabel];

    self.commandField = [NSTextField textFieldWithString:@""];
    self.commandField.placeholderString = @"Command: box(:body, 80.mm, 50.mm, 10.mm)";
    self.commandField.font = [NSFont fontWithName:@"Menlo" size:12] ?: [NSFont systemFontOfSize:12];
    self.commandField.frame = NSMakeRect(8, 8, 644, 26);
    self.commandField.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.commandField.delegate = self;
    [self.commandBox addSubview:self.commandField];
}

@end

/* ------------------------------------------------------------------ */
/* C ABI entry points.                                                 */
/* ------------------------------------------------------------------ */

int wc_cocoa_native_available(void)
{
    return 1;
}

static NSImage *WcFindNightcore(void)
{
    static const char *paths[] = {
        "waifus/nightcore.png",
        "waifus/sakura_riddle.png",
        "waifus/luotianyi.png",
        NULL
    };
    for (int i = 0; paths[i] != NULL; ++i)
    {
        NSString *path = [NSString stringWithUTF8String:paths[i]];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path])
        {
            NSImage *image = [[NSImage alloc] initWithContentsOfFile:path];
            if (image != nil)
                return image;
        }
    }
    return WcLoadIcon("waifucad", 28);
}

int wc_cocoa_run(const WcCocoaWindowConfig *config,
                 const WcCocoaCallbacks *callbacks,
                 void *user_data)
{
    if (config == NULL || callbacks == NULL || callbacks->submit_command == NULL)
        return 10;

    g_callbacks = *callbacks;
    g_userData = user_data;
    memset(&g_state, 0, sizeof(g_state));
    g_state.yaw = -M_PI / 4.0;
    g_state.pitch = M_PI / 5.5;
    g_state.zoom = 1.0;
    g_state.window_width_hint = config->width;
    g_state.ribbon_density = config->width < 820 ? 2 : (config->width < 1180 ? 1 : 0);
    g_rows = [NSMutableArray array];
    g_navigatorColour = WcHex(config->navigator_background, WcHex("#171321", nil));
    g_railColour = WcHex(config->navigator_rail_background, WcHex("#100D18", nil));
    g_nightcore = WcFindNightcore();
    wc_gpu_probe(&g_gpu);

    @autoreleasepool
    {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

        WcAppDelegate *delegate = [[WcAppDelegate alloc] init];
        g_delegate = delegate;
        [NSApp setDelegate:delegate];
        [delegate buildUiWithConfig:config];
        [delegate rebuildRibbon];
        [delegate updateStatus];
        [delegate.window makeKeyAndOrderFront:nil];
        [delegate.splitView setPosition:210 ofDividerAtIndex:0];

        [NSApp activateIgnoringOtherApps:YES];
        [NSApp run];
    }
    return 0;
}
