// ============================================================
//  werx1z.mm - ПОЛНАЯ ВЕРСИЯ + АНИМАЦИЯ МЕНЮ
//  Компиляция: clang++ -dynamiclib -arch arm64 -framework UIKit -framework CoreGraphics -framework QuartzCore -framework Foundation werx1z.mm -o werx1z.dylib
// ============================================================

#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <math.h>

// ============================================================
//  ОФФСЕТЫ
// ============================================================
#define OFFSET_LOCAL_PLAYER    0x00F4A8B0
#define OFFSET_HEALTH          0xEC
#define OFFSET_POSITION        0x34
#define OFFSET_TEAM            0x49
#define OFFSET_VIEW_ANGLES     0x40C0
#define OFFSET_HEAD_POS        0x48
#define OFFSET_PLAYER_NAME     0x220
#define OFFSET_IS_DEATH        0xE8
#define OFFSET_ARMOR           0xF0

// ============================================================
//  РАБОТА С ПАМЯТЬЮ
// ============================================================
template <typename T>
T ReadMemory(uintptr_t address) {
    T value = {};
    vm_size_t size = sizeof(T);
    vm_read_overwrite(mach_task_self(), (vm_address_t)address, size, (vm_address_t)&value, &size);
    return value;
}

template <typename T>
void WriteMemory(uintptr_t address, T value) {
    vm_write(mach_task_self(), (vm_address_t)address, (vm_address_t)&value, sizeof(T));
}

uintptr_t GetLocalPlayer() {
    return ReadMemory<uintptr_t>(OFFSET_LOCAL_PLAYER);
}

// ============================================================
//  СТРУКТУРЫ
// ============================================================
struct Vector3 {
    float x, y, z;
};

struct PlayerData {
    uintptr_t address;
    float health;
    Vector3 position;
    Vector3 headPosition;
    int team;
    char name[32];
    bool isAlive;
};

// ============================================================
//  ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ
// ============================================================
static BOOL g_espEnabled = YES;
static BOOL g_silentAimEnabled = NO;
static BOOL g_noRecoilEnabled = NO;
static BOOL g_noSpreadEnabled = NO;
static BOOL g_skeletonEnabled = NO;
static BOOL g_chinaHatEnabled = NO;
static NSMutableArray *g_players = nil;
static float g_viewMatrix[16];

// ============================================================
//  ПОЛУЧЕНИЕ ВСЕХ ИГРОКОВ
// ============================================================
NSArray* GetPlayers() {
    NSMutableArray *players = [NSMutableArray array];
    uintptr_t localPlayer = GetLocalPlayer();
    if (!localPlayer) return players;
    
    int localTeam = ReadMemory<int>(localPlayer + OFFSET_TEAM);
    Vector3 localPos = ReadMemory<Vector3>(localPlayer + OFFSET_POSITION);
    
    for (uintptr_t addr = 0x10000000; addr < 0x40000000; addr += 4) {
        @try {
            float health = ReadMemory<float>(addr + OFFSET_HEALTH);
            if (health > 0 && health < 1000) {
                int team = ReadMemory<int>(addr + OFFSET_TEAM);
                if (team >= 0 && team < 10 && team != localTeam) {
                    Vector3 pos = ReadMemory<Vector3>(addr + OFFSET_POSITION);
                    if (fabs(pos.x) < 50 && fabs(pos.z) < 50) {
                        PlayerData *player = [[PlayerData alloc] init];
                        player.address = addr;
                        player.health = health;
                        player.position = pos;
                        player.headPosition = ReadMemory<Vector3>(addr + OFFSET_HEAD_POS);
                        player.team = team;
                        player.isAlive = !ReadMemory<bool>(addr + OFFSET_IS_DEATH);
                        
                        char* namePtr = (char*)(addr + OFFSET_PLAYER_NAME);
                        for (int i = 0; i < 31 && namePtr[i]; i++) {
                            player.name[i] = namePtr[i];
                        }
                        player.name[31] = '\0';
                        
                        [players addObject:player];
                        if (players.count > 20) break;
                    }
                }
            }
        } @catch (NSException *e) {}
    }
    
    return players;
}

// ============================================================
//  W2S (World to Screen)
// ============================================================
bool WorldToScreen(Vector3 worldPos, float* screenX, float* screenY) {
    for (int i = 0; i < 16; i++) {
        g_viewMatrix[i] = ReadMemory<float>(0x00F5A2B0 + i * 4);
    }
    
    float w = g_viewMatrix[12] * worldPos.x + g_viewMatrix[13] * worldPos.y + g_viewMatrix[14] * worldPos.z + g_viewMatrix[15];
    if (w < 0.01f) return false;
    
    float invW = 1.0f / w;
    float x = (g_viewMatrix[0] * worldPos.x + g_viewMatrix[1] * worldPos.y + g_viewMatrix[2] * worldPos.z + g_viewMatrix[3]) * invW;
    float y = (g_viewMatrix[4] * worldPos.x + g_viewMatrix[5] * worldPos.y + g_viewMatrix[6] * worldPos.z + g_viewMatrix[7]) * invW;
    
    CGRect screen = [UIScreen mainScreen].bounds;
    *screenX = (screen.size.width / 2.0f) * (1.0f + x);
    *screenY = (screen.size.height / 2.0f) * (1.0f - y);
    
    return (*screenX >= 0 && *screenX <= screen.size.width && *screenY >= 0 && *screenY <= screen.size.height);
}

// ============================================================
//  SKELETON ESP
// ============================================================
void DrawSkeleton(CGContextRef ctx, PlayerData *player, CGColorRef color) {
    float headX, headY;
    if (!WorldToScreen(player->headPosition, &headX, &headY)) return;
    
    float bodyX, bodyY;
    Vector3 bodyPos = {player->position.x, player->position.y + 0.5f, player->position.z};
    WorldToScreen(bodyPos, &bodyX, &bodyY);
    
    float height = fabs(bodyY - headY);
    if (height < 10) return;
    
    float width = height * 0.4;
    float shoulderY = headY + height * 0.3;
    float shoulderLeftX = headX - width;
    float shoulderRightX = headX + width;
    float hipY = headY + height * 0.7;
    float handY = hipY + height * 0.3;
    float handLeftX = shoulderLeftX - width * 0.5;
    float handRightX = shoulderRightX + width * 0.5;
    float footY = bodyY;
    float footLeftX = headX - width * 0.3;
    float footRightX = headX + width * 0.3;
    
    CGContextSetStrokeColorWithColor(ctx, color);
    CGContextSetLineWidth(ctx, 2.0);
    CGContextSetShadowWithColor(ctx, CGSizeMake(0, 0), 10.0, color);
    
    float headRadius = height * 0.12;
    CGContextStrokeEllipseInRect(ctx, CGRectMake(headX - headRadius, headY - headRadius, headRadius * 2, headRadius * 2));
    
    CGContextMoveToPoint(ctx, headX, headY + headRadius);
    CGContextAddLineToPoint(ctx, headX, shoulderY);
    CGContextStrokePath(ctx);
    
    CGContextMoveToPoint(ctx, shoulderLeftX, shoulderY);
    CGContextAddLineToPoint(ctx, shoulderRightX, shoulderY);
    CGContextStrokePath(ctx);
    
    CGContextMoveToPoint(ctx, shoulderLeftX, shoulderY);
    CGContextAddLineToPoint(ctx, handLeftX, handY);
    CGContextStrokePath(ctx);
    
    CGContextMoveToPoint(ctx, shoulderRightX, shoulderY);
    CGContextAddLineToPoint(ctx, handRightX, handY);
    CGContextStrokePath(ctx);
    
    CGContextMoveToPoint(ctx, headX, shoulderY + height * 0.1);
    CGContextAddLineToPoint(ctx, headX, hipY);
    CGContextStrokePath(ctx);
    
    CGContextMoveToPoint(ctx, headX - width * 0.5, hipY);
    CGContextAddLineToPoint(ctx, headX + width * 0.5, hipY);
    CGContextStrokePath(ctx);
    
    CGContextMoveToPoint(ctx, headX - width * 0.2, hipY);
    CGContextAddLineToPoint(ctx, footLeftX, footY);
    CGContextStrokePath(ctx);
    
    CGContextMoveToPoint(ctx, headX + width * 0.2, hipY);
    CGContextAddLineToPoint(ctx, footRightX, footY);
    CGContextStrokePath(ctx);
    
    float jointRadius = 4;
    CGContextSetFillColorWithColor(ctx, color);
    CGContextFillEllipseInRect(ctx, CGRectMake(shoulderLeftX - jointRadius, shoulderY - jointRadius, jointRadius * 2, jointRadius * 2));
    CGContextFillEllipseInRect(ctx, CGRectMake(shoulderRightX - jointRadius, shoulderY - jointRadius, jointRadius * 2, jointRadius * 2));
    CGContextFillEllipseInRect(ctx, CGRectMake(headX - jointRadius, hipY - jointRadius, jointRadius * 2, jointRadius * 2));
    CGContextFillEllipseInRect(ctx, CGRectMake(handLeftX - jointRadius, handY - jointRadius, jointRadius * 2, jointRadius * 2));
    CGContextFillEllipseInRect(ctx, CGRectMake(handRightX - jointRadius, handY - jointRadius, jointRadius * 2, jointRadius * 2));
    CGContextFillEllipseInRect(ctx, CGRectMake(footLeftX - jointRadius, footY - jointRadius, jointRadius * 2, jointRadius * 2));
    CGContextFillEllipseInRect(ctx, CGRectMake(footRightX - jointRadius, footY - jointRadius, jointRadius * 2, jointRadius * 2));
    
    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
}

// ============================================================
//  CHINA HAT
// ============================================================
void DrawChinaHat(CGContextRef ctx, PlayerData *player) {
    float headX, headY;
    if (!WorldToScreen(player->headPosition, &headX, &headY)) return;
    
    float dotY = headY - 25;
    float dotRadius = 8;
    static float phase = 0;
    phase += 0.05;
    float pulse = 0.7 + 0.3 * sinf(phase);
    
    CGContextSetShadowWithColor(ctx, CGSizeMake(0, 0), 25.0, [UIColor redColor].CGColor);
    CGContextSetFillColorWithColor(ctx, [UIColor redColor].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(headX - dotRadius, dotY - dotRadius, dotRadius * 2, dotRadius * 2));
    
    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
    CGContextSetFillColorWithColor(ctx, [UIColor whiteColor].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(headX - dotRadius * 0.4, dotY - dotRadius * 0.4, dotRadius * 0.8, dotRadius * 0.8));
    
    CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.3 * pulse].CGColor);
    CGContextSetLineWidth(ctx, 2.0);
    CGContextSetShadowWithColor(ctx, CGSizeMake(0, 0), 30.0, [UIColor redColor].CGColor);
    
    for (int i = 0; i < 8; i++) {
        float angle = phase + i * M_PI / 4;
        float length = 15 + 10 * sinf(phase + i);
        CGContextMoveToPoint(ctx, headX, dotY);
        CGContextAddLineToPoint(ctx, headX + cosf(angle) * length, dotY + sinf(angle) * length);
        CGContextStrokePath(ctx);
    }
    
    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
}

// ============================================================
//  ESP OVERLAY
// ============================================================
@interface ESPOverlayView : UIView {
    NSArray *playersCache;
    NSTimer *updateTimer;
}
@end

@implementation ESPOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        self.opaque = NO;
        
        updateTimer = [NSTimer scheduledTimerWithTimeInterval:0.03
                                                       target:self
                                                     selector:@selector(updateESP)
                                                     userInfo:nil
                                                      repeats:YES];
    }
    return self;
}

- (void)updateESP {
    if (g_espEnabled || g_silentAimEnabled || g_skeletonEnabled || g_chinaHatEnabled) {
        playersCache = GetPlayers();
        [self setNeedsDisplay];
    }
}

- (void)drawRect:(CGRect)rect {
    if (!g_espEnabled && !g_silentAimEnabled && !g_skeletonEnabled && !g_chinaHatEnabled) return;
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextClearRect(ctx, rect);
    
    uintptr_t localPlayer = GetLocalPlayer();
    if (!localPlayer || !playersCache.count) return;
    
    Vector3 localPos = ReadMemory<Vector3>(localPlayer + OFFSET_POSITION);
    PlayerData *closestEnemy = nil;
    float closestDist = INFINITY;
    
    for (PlayerData *player in playersCache) {
        float screenX, screenY;
        if (!WorldToScreen(player.position, &screenX, &screenY)) continue;
        
        float headX, headY;
        WorldToScreen(player.headPosition, &headX, &headY);
        
        float dist = sqrtf(powf(player.position.x - localPos.x, 2) + powf(player.position.y - localPos.y, 2) + powf(player.position.z - localPos.z, 2));
        
        if (dist < closestDist) {
            closestDist = dist;
            closestEnemy = player;
        }
        
        float t = fminf(dist / 120.0f, 1.0f);
        float phase = (float)CFAbsoluteTimeGetCurrent() / 1.6f;
        float r = 0.2 + 0.8 * (0.5 + 0.5 * sinf(t * 3.0 + phase * 0.5));
        float g = 0.2 + 0.8 * (0.5 + 0.5 * sinf(t * 2.5 + phase * 0.7 + 1.8));
        float b = 0.2 + 0.8 * (0.5 + 0.5 * sinf(t * 2.0 + phase * 0.9 + 2.4));
        float bright = 0.8 + 0.2 * (1.0 - t);
        
        UIColor *color = [UIColor colorWithRed:r * bright green:g * bright * 0.5 blue:b * bright alpha:1.0];
        CGColorRef cgColor = color.CGColor;
        
        if (g_espEnabled) {
            float boxHeight = fabs(screenY - headY);
            if (boxHeight < 10) boxHeight = 60;
            float boxWidth = boxHeight * 0.5;
            float x = screenX - boxWidth / 2;
            float y = headY;
            
            CGContextSaveGState(ctx);
            CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
            NSArray *gradientColors = @[
                (id)[UIColor colorWithRed:r * bright green:g * bright * 0.5 blue:b * bright alpha:0.04].CGColor,
                (id)[UIColor colorWithRed:r * bright green:g * bright * 0.5 blue:b * bright alpha:0.12].CGColor,
                (id)[UIColor colorWithRed:r * bright green:g * bright * 0.5 blue:b * bright alpha:0.16].CGColor,
                (id)[UIColor colorWithRed:r * bright green:g * bright * 0.5 blue:b * bright alpha:0.04].CGColor
            ];
            CGFloat locations[] = {0.0, 0.3, 0.6, 1.0};
            CGGradientRef gradient = CGGradientCreateWithColors(colorSpace, (__bridge CFArrayRef)gradientColors, locations);
            CGContextDrawLinearGradient(ctx, gradient, CGPointMake(x, y), CGPointMake(x + boxWidth, y), 0);
            CGGradientRelease(gradient);
            CGColorSpaceRelease(colorSpace);
            CGContextRestoreGState(ctx);
            
            CGContextSetStrokeColorWithColor(ctx, cgColor);
            CGContextSetLineWidth(ctx, 2.0);
            CGContextSetShadowWithColor(ctx, CGSizeMake(0, 0), 15.0, cgColor);
            CGContextStrokeRect(ctx, CGRectMake(x, y, boxWidth, boxHeight));
            CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
            
            CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithWhite:1.0 alpha:0.04].CGColor);
            CGContextSetLineWidth(ctx, 0.8);
            CGContextStrokeRect(ctx, CGRectMake(x + 3, y + 3, boxWidth - 6, boxHeight - 6));
            
            CGContextSetShadowWithColor(ctx, CGSizeMake(0, 0), 6.0, [UIColor blackColor].CGColor);
            CGContextSetFillColorWithColor(ctx, cgColor);
            UIFont *font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightBold];
            NSString *distText = [NSString stringWithFormat:@"%.0fm", dist];
            [distText drawAtPoint:CGPointMake(screenX - 20, screenY + 12) withAttributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: color}];
            CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
        }
        
        if (g_skeletonEnabled) {
            DrawSkeleton(ctx, player, cgColor);
        }
        
        if (g_chinaHatEnabled) {
            DrawChinaHat(ctx, player);
        }
    }
    
    if (g_silentAimEnabled && closestEnemy) {
        Vector3 target = closestEnemy.headPosition;
        Vector3 localPos = ReadMemory<Vector3>(localPlayer + OFFSET_POSITION);
        
        float dx = target.x - localPos.x;
        float dy = target.y - localPos.y;
        float dz = target.z - localPos.z;
        float dist = sqrtf(dx*dx + dy*dy + dz*dz);
        
        if (dist > 0.5) {
            float pitch = -asinf(dz / dist) * (180.0f / M_PI);
            float yaw = atan2f(dy, dx) * (180.0f / M_PI);
            
            WriteMemory<float>(localPlayer + OFFSET_VIEW_ANGLES, yaw);
            WriteMemory<float>(localPlayer + OFFSET_VIEW_ANGLES + 4, pitch);
        }
        
        float headX, headY;
        if (WorldToScreen(closestEnemy.headPosition, &headX, &headY)) {
            CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:0.8].CGColor);
            CGContextSetLineWidth(ctx, 2.5);
            CGContextSetShadowWithColor(ctx, CGSizeMake(0, 0), 20.0, [UIColor redColor].CGColor);
            CGContextStrokeEllipseInRect(ctx, CGRectMake(headX - 12, headY - 12, 24, 24));
            CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
            
            CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:0.6].CGColor);
            CGContextSetLineWidth(ctx, 1.5);
            CGContextMoveToPoint(ctx, headX - 20, headY);
            CGContextAddLineToPoint(ctx, headX + 20, headY);
            CGContextMoveToPoint(ctx, headX, headY - 20);
            CGContextAddLineToPoint(ctx, headX, headY + 20);
            CGContextStrokePath(ctx);
        }
    }
}

@end

// ============================================================
//  NO RECOIL / NO SPREAD
// ============================================================
void ApplyNoRecoil() {
    if (!g_noRecoilEnabled) return;
    uintptr_t localPlayer = GetLocalPlayer();
    if (!localPlayer) return;
    
    uintptr_t punchAddr = localPlayer + 0x41C0;
    WriteMemory<float>(punchAddr, 0.0f);
    WriteMemory<float>(punchAddr + 4, 0.0f);
    WriteMemory<float>(punchAddr + 8, 0.0f);
}

void ApplyNoSpread() {
    if (!g_noSpreadEnabled) return;
    uintptr_t localPlayer = GetLocalPlayer();
    if (!localPlayer) return;
    
    uintptr_t spreadAddr = localPlayer + 0x41E0;
    WriteMemory<float>(spreadAddr, 0.0f);
    
    for (int offset = 0; offset < 0x40; offset += 4) {
        uintptr_t testAddr = spreadAddr + offset;
        float val = ReadMemory<float>(testAddr);
        if (val > 0 && val < 10) {
            WriteMemory<float>(testAddr, 0.0f);
        }
    }
}

// ============================================================
//  МЕНЮ С АНИМАЦИЕЙ
// ============================================================
@interface TweakMenuView : UIView {
    UIView *menuView;
    UIPanGestureRecognizer *panGesture;
    UITapGestureRecognizer *threeFingerTap;
    UILabel *titleLabel;
    UISwitch *espSwitch;
    UISwitch *aimSwitch;
    UISwitch *recoilSwitch;
    UISwitch *spreadSwitch;
    UISwitch *skeletonSwitch;
    UISwitch *chinaHatSwitch;
    UILabel *watermarkLabel;
    NSTimer *watermarkTimer;
    BOOL menuVisible;
}
@end

@implementation TweakMenuView

- (instancetype)init {
    self = [super init];
    if (self) {
        menuVisible = YES;
        [self setupGesture];
        [self setupMenu];
        [self setupWatermark];
        [self startBackgroundTasks];
    }
    return self;
}

// ============================================================
//  === ЖЕСТ: ДВОЙНОЙ ТАП ТРЁМЯ ПАЛЬЦАМИ ===
// ============================================================
- (void)setupGesture {
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    
    threeFingerTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleThreeFingerTap:)];
    threeFingerTap.numberOfTouchesRequired = 3;
    threeFingerTap.numberOfTapsRequired = 2;
    [keyWindow addGestureRecognizer:threeFingerTap];
    
    NSLog(@"✅ Three-finger tap gesture registered");
}

- (void)handleThreeFingerTap:(UITapGestureRecognizer *)gesture {
    menuVisible = !menuVisible;
    
    if (menuVisible) {
        [self showMenuWithAnimation];
    } else {
        [self hideMenuWithAnimation];
    }
    
    NSLog(@"Menu: %@", menuVisible ? @"SHOW" : @"HIDE");
}

// ============================================================
//  === АНИМАЦИЯ ПОЯВЛЕНИЯ ===
// ============================================================
- (void)showMenuWithAnimation {
    // Меню
    menuView.transform = CGAffineTransformMakeScale(0.8, 0.8);
    menuView.alpha = 0.0;
    menuView.hidden = NO;
    
    [UIView animateWithDuration:0.35
                          delay:0
         usingSpringWithDamping:0.8
          initialSpringVelocity:0.5
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self->menuView.transform = CGAffineTransformIdentity;
        self->menuView.alpha = 1.0;
    } completion:nil];
    
    // Ватермарка
    watermarkLabel.transform = CGAffineTransformMakeScale(0.9, 0.9);
    watermarkLabel.alpha = 0.0;
    watermarkLabel.hidden = NO;
    
    [UIView animateWithDuration:0.3
                          delay:0.1
         usingSpringWithDamping:0.8
          initialSpringVelocity:0.5
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self->watermarkLabel.transform = CGAffineTransformIdentity;
        self->watermarkLabel.alpha = 1.0;
    } completion:nil];
}

// ============================================================
//  === АНИМАЦИЯ ИСЧЕЗНОВЕНИЯ ===
// ============================================================
- (void)hideMenuWithAnimation {
    [UIView animateWithDuration:0.25
                          delay:0
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self->menuView.transform = CGAffineTransformMakeScale(0.7, 0.7);
        self->menuView.alpha = 0.0;
    } completion:^(BOOL finished) {
        self->menuView.hidden = YES;
        self->menuView.transform = CGAffineTransformIdentity;
        self->menuView.alpha = 1.0;
    }];
    
    [UIView animateWithDuration:0.2
                          delay:0.05
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self->watermarkLabel.transform = CGAffineTransformMakeScale(0.8, 0.8);
        self->watermarkLabel.alpha = 0.0;
    } completion:^(BOOL finished) {
        self->watermarkLabel.hidden = YES;
        self->watermarkLabel.transform = CGAffineTransformIdentity;
        self->watermarkLabel.alpha = 1.0;
    }];
}

// ============================================================
//  === МЕНЮ ===
// ============================================================
- (void)setupMenu {
    CGRect screen = [UIScreen mainScreen].bounds;
    
    menuView = [[UIView alloc] initWithFrame:CGRectMake(20, 60, 320, 380)];
    menuView.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.55];
    menuView.layer.cornerRadius = 20;
    menuView.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:0.15].CGColor;
    menuView.layer.borderWidth = 1.5;
    menuView.clipsToBounds = YES;
    
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    blurView.frame = menuView.bounds;
    blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [menuView insertSubview:blurView atIndex:0];
    
    titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, 320, 35)];
    titleLabel.text = @"✦ werx1z.dll";
    titleLabel.font = [UIFont fontWithName:@"CourierNewPS-BoldMT" size:18];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self applyGradientToLabel:titleLabel colors:@[
        [UIColor colorWithRed:1.0 green:0.3 blue:0.58 alpha:1.0],
        [UIColor colorWithRed:0.66 green:0.34 blue:0.97 alpha:1.0],
        [UIColor colorWithRed:0.48 green:0.41 blue:0.93 alpha:1.0]
    ]];
    [menuView addSubview:titleLabel];
    
    NSArray *labels = @[@"ESP Box", @"Silent Aim", @"No Recoil", @"No Spread", @"Skeleton", @"China Hat"];
    NSArray *tags = @[@0, @1, @2, @3, @4, @5];
    
    for (int i = 0; i < labels.count; i++) {
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 60 + i*44, 180, 30)];
        label.text = labels[i];
        label.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
        label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightLight];
        [menuView addSubview:label];
        
        UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(240, 55 + i*44, 50, 30)];
        sw.onTintColor = [UIColor colorWithRed:1.0 green:0.3 blue:0.58 alpha:0.8];
        sw.tintColor = [UIColor colorWithWhite:0.2 alpha:0.5];
        sw.on = (i == 0);
        sw.tag = i;
        [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        [menuView addSubview:sw];
        
        if (i == 0) espSwitch = sw;
        else if (i == 1) aimSwitch = sw;
        else if (i == 2) recoilSwitch = sw;
        else if (i == 3) spreadSwitch = sw;
        else if (i == 4) skeletonSwitch = sw;
        else if (i == 5) chinaHatSwitch = sw;
    }
    
    UILabel *footerLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 345, 320, 20)];
    footerLabel.text = @"✦ H5GG · AURORA";
    footerLabel.textColor = [UIColor colorWithWhite:0.15 alpha:0.5];
    footerLabel.font = [UIFont systemFontOfSize:9];
    footerLabel.textAlignment = NSTextAlignmentCenter;
    [menuView addSubview:footerLabel];
    
    panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragMenu:)];
    [menuView addGestureRecognizer:panGesture];
    
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    [keyWindow addSubview:menuView];
}

- (void)switchChanged:(UISwitch *)sender {
    switch (sender.tag) {
        case 0: g_espEnabled = sender.on; break;
        case 1: g_silentAimEnabled = sender.on; break;
        case 2: g_noRecoilEnabled = sender.on; break;
        case 3: g_noSpreadEnabled = sender.on; break;
        case 4: g_skeletonEnabled = sender.on; break;
        case 5: g_chinaHatEnabled = sender.on; break;
    }
    NSLog(@"Switch %ld: %@", (long)sender.tag, sender.on ? @"ON" : @"OFF");
}

- (void)dragMenu:(UIPanGestureRecognizer *)gesture {
    UIView *view = gesture.view;
    CGPoint translation = [gesture translationInView:view.superview];
    view.center = CGPointMake(view.center.x + translation.x, view.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:view.superview];
}

- (void)applyGradientToLabel:(UILabel *)label colors:(NSArray *)colors {
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = label.bounds;
    NSMutableArray *cgColors = [NSMutableArray array];
    for (UIColor *color in colors) {
        [cgColors addObject:(id)color.CGColor];
    }
    gradient.colors = cgColors;
    gradient.startPoint = CGPointMake(0, 0.5);
    gradient.endPoint = CGPointMake(1, 0.5);
    gradient.locations = @[@0, @0.5, @1];
    
    UIGraphicsBeginImageContext(gradient.bounds.size);
    [gradient renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *gradientImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    label.textColor = [UIColor colorWithPatternImage:gradientImage];
}

// ============================================================
//  ВАТЕРМАРКА
// ============================================================
- (void)setupWatermark {
    watermarkLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 20, 200, 40)];
    watermarkLabel.text = @"✦ werx1z.dll v2.4";
    watermarkLabel.font = [UIFont fontWithName:@"CourierNewPS-BoldMT" size:16];
    watermarkLabel.textAlignment = NSTextAlignmentLeft;
    watermarkLabel.layer.shadowColor = [UIColor blackColor].CGColor;
    watermarkLabel.layer.shadowRadius = 10;
    watermarkLabel.layer.shadowOpacity = 0.3;
    [self applyGradientToLabel:watermarkLabel colors:@[
        [UIColor colorWithRed:1.0 green:0.3 blue:0.58 alpha:1.0],
        [UIColor colorWithRed:0.66 green:0.34 blue:0.97 alpha:1.0],
        [UIColor colorWithRed:0.48 green:0.41 blue:0.93 alpha:1.0],
        [UIColor colorWithRed:1.0 green:0.3 blue:0.58 alpha:1.0]
    ]];
    
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    blurView.frame = watermarkLabel.frame;
    blurView.layer.cornerRadius = 12;
    blurView.clipsToBounds = YES;
    blurView.alpha = 0.15;
    [watermarkLabel.superview insertSubview:blurView belowSubview:watermarkLabel];
    
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    [keyWindow addSubview:watermarkLabel];
    
    watermarkTimer = [NSTimer scheduledTimerWithTimeInterval:0.05
                                                     target:self
                                                   selector:@selector(animateWatermark)
                                                   userInfo:nil
                                                    repeats:YES];
}

- (void)animateWatermark {
    static float phase = 0;
    phase += 0.02;
    
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = watermarkLabel.bounds;
    gradient.colors = @[
        (id)[UIColor colorWithRed:1.0 green:0.3 blue:0.58 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.66 green:0.34 blue:0.97 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.48 green:0.41 blue:0.93 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:1.0 green:0.3 blue:0.58 alpha:1.0].CGColor
    ];
    gradient.startPoint = CGPointMake(0.3 + 0.7 * sinf(phase), 0.5);
    gradient.endPoint = CGPointMake(0.7 + 0.7 * sinf(phase + 1.5), 0.5);
    gradient.locations = @[@0, @0.33, @0.66, @1];
    
    UIGraphicsBeginImageContext(gradient.bounds.size);
    [gradient renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *gradientImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    watermarkLabel.textColor = [UIColor colorWithPatternImage:gradientImage];
}

// ============================================================
//  ФОНОВЫЕ ЗАДАЧИ
// ============================================================
- (void)startBackgroundTasks {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        while (true) {
            @autoreleasepool {
                ApplyNoRecoil();
                ApplyNoSpread();
                usleep(10000);
            }
        }
    });
}

@end

// ============================================================
//  ТОЧКА ВХОДА
// ============================================================
__attribute__((constructor))
static void Initialize() {
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            TweakMenuView *menu = [[TweakMenuView alloc] init];
            
            UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
            ESPOverlayView *espView = [[ESPOverlayView alloc] initWithFrame:keyWindow.bounds];
            espView.backgroundColor = [UIColor clearColor];
            espView.userInteractionEnabled = NO;
            espView.opaque = NO;
            [keyWindow addSubview:espView];
            
            NSLog(@"✅ werx1z.dll loaded successfully!");
        }
    });
}
