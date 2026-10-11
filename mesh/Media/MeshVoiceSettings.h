// Gerätweite Einstellungen für Sprachnachrichten (NSUserDefaults).
#import <Foundation/Foundation.h>

@interface MeshVoiceSettings : NSObject

// Stimmeffekt: "none", "high", "deep", "robot", "alien", "anonym"
+ (NSString *)currentEffect;
+ (void)setCurrentEffect:(NSString *)effect;
+ (NSArray *)allEffects;
+ (NSString *)effectLabel:(NSString *)effect;
+ (NSArray *)effectLabels;               // in der Reihenfolge von allEffects

// Wiedergabe-Verstärkung 0…3 (das iPod-Lautsprecherchen ist leise).
+ (int)playGainLevel;
+ (void)setPlayGainLevel:(int)level;
+ (NSString *)gainLabel:(int)level;
+ (NSArray *)gainLabels;                 // Index = Stufe
+ (double)gainFactor:(int)level;

+ (NSString *)noiseLabel:(int)level;   // 0 = Aus … 4 = Sehr stark

// Apples Voice-Processing-Einheit (AGC + Rauschunterdrückung) beim Aufnehmen. Default an.
// vpioBroken merkt sich, dass sie auf diesem Gerät nur Stille liefert.
+ (BOOL)useVPIO;
+ (void)setUseVPIO:(BOOL)on;
+ (BOOL)vpioBroken;
+ (void)setVpioBroken:(BOOL)broken;

// Aufbereitungsprofil für jede Aufnahme ohne Effekt (im Audio-Labor einstellbar).
+ (float)labNoise;      + (void)setLabNoise:(float)v;      // 0…4
+ (float)labHp;         + (void)setLabHp:(float)v;         // Hz
+ (float)labLp;         + (void)setLabLp:(float)v;         // Hz
+ (float)labPresence;   + (void)setLabPresence:(float)v;   // dB
+ (float)labGain;       + (void)setLabGain:(float)v;       // Faktor
@end
