#import "MeshVoiceSettings.h"
#import "MeshAudioDSP.h"
#import "MeshL10n.h"

// Schlüssel in NSUserDefaults (nichts davon ist geheim).
static NSString *const kEffect      = @"mesh.voiceEffect";
static NSString *const kPlayGain    = @"mesh.playGain";
static NSString *const kUseVPIO     = @"mesh.useVPIO";
static NSString *const kVpioBroken  = @"mesh.vpioBroken";
static NSString *const kLabNoise    = @"mesh.lab.noise";
static NSString *const kLabHp       = @"mesh.lab.hp";
static NSString *const kLabLp       = @"mesh.lab.lp";
static NSString *const kLabPresence = @"mesh.lab.pres";
static NSString *const kLabGain     = @"mesh.lab.gain";

@implementation MeshVoiceSettings

+ (NSString *)currentEffect {
    NSString *e = [[NSUserDefaults standardUserDefaults] stringForKey:kEffect];
    return e.length ? e : MeshEffectNone;
}
+ (void)setCurrentEffect:(NSString *)effect {
    [[NSUserDefaults standardUserDefaults] setObject:(effect ?: MeshEffectNone) forKey:kEffect];
}
+ (NSArray *)allEffects { return @[MeshEffectNone, MeshEffectHigh, MeshEffectDeep, MeshEffectRobot, MeshEffectAlien, MeshEffectAnonym]; }
+ (NSString *)effectLabel:(NSString *)e {
    if ([e isEqualToString:MeshEffectHigh])  return L(@"High (chipmunk)");
    if ([e isEqualToString:MeshEffectDeep])  return L(@"Deep");
    if ([e isEqualToString:MeshEffectRobot]) return L(@"Robot");
    if ([e isEqualToString:MeshEffectAlien]) return L(@"Alien");
    if ([e isEqualToString:MeshEffectAnonym]) return L(@"Other voice (same tempo)");
    return L(@"Normal");
}
+ (NSArray *)effectLabels {
    NSMutableArray *m = [NSMutableArray array];
    for (NSString *e in [self allEffects]) [m addObject:[self effectLabel:e]];
    return m;
}

+ (int)playGainLevel { return (int)[[NSUserDefaults standardUserDefaults] integerForKey:kPlayGain]; }
+ (void)setPlayGainLevel:(int)l { [[NSUserDefaults standardUserDefaults] setInteger:l forKey:kPlayGain]; }
+ (NSString *)gainLabel:(int)level {
    if (level >= 3) return L(@"Extremely loud");
    if (level == 2) return L(@"Very loud");
    if (level == 1) return L(@"Loud");
    return L(@"Normal");
}
+ (NSArray *)gainLabels { return @[[self gainLabel:0], [self gainLabel:1], [self gainLabel:2], [self gainLabel:3]]; }
+ (double)gainFactor:(int)level {
    switch (level) { case 1: return 1.6; case 2: return 2.4; case 3: return 3.6; default: return 1.0; }
}

+ (NSString *)noiseLabel:(int)level {
    switch (level) { case 0: return L(@"Off"); case 1: return L(@"Mild"); case 3: return L(@"Strong"); case 4: return L(@"Very strong"); default: return L(@"Medium"); }
}

+ (BOOL)useVPIO {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if ([d objectForKey:kUseVPIO] == nil) return YES;
    return [d boolForKey:kUseVPIO];
}
// Wer es von Hand einschaltet, will es erneut versuchen: der Merker "stumm" fällt weg.
+ (void)setUseVPIO:(BOOL)on {
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:kUseVPIO];
    if (on) [self setVpioBroken:NO];
}
+ (BOOL)vpioBroken { return [[NSUserDefaults standardUserDefaults] boolForKey:kVpioBroken]; }
+ (void)setVpioBroken:(BOOL)broken { [[NSUserDefaults standardUserDefaults] setBool:broken forKey:kVpioBroken]; }

// Labor-Profil mit sinnvollen Defaults.
+ (float)labF:(NSString *)k def:(float)def {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    return [d objectForKey:k] ? [d floatForKey:k] : def;
}
+ (float)labNoise    { return [self labF:kLabNoise def:2.0f]; }
+ (void)setLabNoise:(float)v { [[NSUserDefaults standardUserDefaults] setFloat:v forKey:kLabNoise]; }
+ (float)labHp       { return [self labF:kLabHp def:90.0f]; }
+ (void)setLabHp:(float)v { [[NSUserDefaults standardUserDefaults] setFloat:v forKey:kLabHp]; }
+ (float)labLp       { return [self labF:kLabLp def:7000.0f]; }
+ (void)setLabLp:(float)v { [[NSUserDefaults standardUserDefaults] setFloat:v forKey:kLabLp]; }
+ (float)labPresence { return [self labF:kLabPresence def:3.0f]; }
+ (void)setLabPresence:(float)v { [[NSUserDefaults standardUserDefaults] setFloat:v forKey:kLabPresence]; }
+ (float)labGain     { return [self labF:kLabGain def:1.0f]; }
+ (void)setLabGain:(float)v { [[NSUserDefaults standardUserDefaults] setFloat:v forKey:kLabGain]; }

@end
