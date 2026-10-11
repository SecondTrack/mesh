#import "AudioSettingsViewController.h"
#import "MeshScreen.h"
#import "MeshTheme.h"
#import "MeshPageHeader.h"
#import "MeshPopup.h"
#import "VoiceLabViewController.h"
#import "MeshL10n.h"
#import "MeshVoiceSettings.h"
#import "MeshMenuRow.h"
#import "MeshControls.h"

enum { RowVPIO = 1, RowPlayGain, RowEffect, RowLab };

@implementation AudioSettingsViewController {
    UIScrollView *_scroll;
    NSMutableDictionary *_rows;   // tag(NSNumber) -> MeshMenuRow
}

- (void)loadView {
    [self mesh_loadScreen];
    _rows = [NSMutableDictionary dictionary];
    CGFloat W = self.view.bounds.size.width;

    _scroll = [self mesh_addPageTitled:L(@"Sound & Microphone")];

    CGFloat y = 14;
    y = [self rowAt:y width:W icon:@"sliders" title:L(@"Audio Lab") sub:L(@"Tune recording quality live") tag:RowLab];
    y = [self section:L(@"RECORDING") at:y+6 width:W];
    y = [self rowAt:y width:W icon:@"mic" title:L(@"Apple Voice Unit") sub:L(@"Hardware noise reduction + AGC") tag:RowVPIO];
    y = [self rowAt:y width:W icon:@"wave" title:L(@"Voice effect") sub:L(@"Distortion") tag:RowEffect];
    y = [self section:L(@"PLAYBACK") at:y+6 width:W];
    y = [self rowAt:y width:W icon:@"speaker" title:L(@"Playback volume") sub:L(@"Make voice messages louder") tag:RowPlayGain];

    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(20, y+10, W-40, 90)];
    hint.text = L(@"In the Audio Lab you record once and instantly hear the result as you move the sliders — noise filter, high-pass, low-pass, presence, volume. “Set as default” uses the values for all voice messages.");
    hint.font = [MeshTheme timeFont]; hint.textColor = [MeshTheme muted]; hint.numberOfLines = 0; hint.backgroundColor = [UIColor clearColor];
    [_scroll addSubview:hint];
    _scroll.contentSize = CGSizeMake(W, y + 100);

    [self refresh];
}

- (CGFloat)section:(NSString *)text at:(CGFloat)y width:(CGFloat)W {
    [_scroll addSubview:[MeshControls sectionLabelWithFrame:CGRectMake(18, y, W - 36, 18) text:text]];
    return y + 24;
}

- (CGFloat)rowAt:(CGFloat)y width:(CGFloat)W icon:(NSString *)icon title:(NSString *)title sub:(NSString *)sub tag:(NSInteger)tag {
    MeshMenuRow *row = [MeshMenuRow rowAtY:y width:W icon:icon title:title subtitle:sub];
    row.tag = tag;
    [row addTarget:self action:@selector(tapRow:) forControlEvents:UIControlEventTouchUpInside];
    [_scroll addSubview:row];
    _rows[@(tag)] = row;
    return y + [MeshMenuRow height];
}

- (void)refresh {
    [(MeshMenuRow *)_rows[@(RowVPIO)]     setDetail:[MeshVoiceSettings useVPIO] ? L(@"On") : L(@"Off")];
    [(MeshMenuRow *)_rows[@(RowPlayGain)] setDetail:[MeshVoiceSettings gainLabel:[MeshVoiceSettings playGainLevel]]];
    [(MeshMenuRow *)_rows[@(RowEffect)]   setDetail:[MeshVoiceSettings effectLabel:[MeshVoiceSettings currentEffect]]];
}

- (void)tapRow:(UIButton *)row {
    NSInteger tag = row.tag;
    if (tag == RowLab)  { [self.navigationController pushViewController:[[VoiceLabViewController alloc] init] animated:YES]; return; }
    if (tag == RowVPIO) { [MeshVoiceSettings setUseVPIO:![MeshVoiceSettings useVPIO]]; [self refresh]; return; }

    BOOL effect = (tag == RowEffect);
    NSString *title = effect ? L(@"Voice effect") : L(@"Playback volume");
    NSArray *opts = effect ? [MeshVoiceSettings effectLabels] : [MeshVoiceSettings gainLabels];

    [MeshPopup sheet:title options:opts destructiveIndex:-1 handler:^(NSInteger idx) {
        if (idx < 0) return;
        if (effect) [MeshVoiceSettings setCurrentEffect:[MeshVoiceSettings allEffects][idx]];
        else        [MeshVoiceSettings setPlayGainLevel:(int)idx];
        [self refresh];
    }];
}

@end
