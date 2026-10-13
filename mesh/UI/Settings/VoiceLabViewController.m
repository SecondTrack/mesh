#import "VoiceLabViewController.h"
#import "MeshScreen.h"
#import "MeshTheme.h"
#import "MeshGlyphs.h"
#import "MeshPageHeader.h"
#import "MeshPopup.h"
#import "MeshL10n.h"
#import "MeshVoiceSettings.h"
#import "MeshAudioCodec.h"
#import "MeshAudioDSP.h"
#import "MeshVoice.h"
#import "MeshControls.h"
#import "MeshMemory.h"
#import "MeshNotifications.h"

static const NSTimeInterval kLabSeconds = 6;

static const CGFloat kMargin = 16, kGap = 10;

@implementation VoiceLabViewController {
    UIScrollView *_scroll;
    MeshVoice *_voice;
    NSMutableData *_raw;     // rohe PCM16-Aufnahme (16k mono), beim Verlassen überschrieben
    BOOL _recording;
    UIButton *_recBtn;
    UILabel  *_status;
    UISlider *_noiseSlider, *_highPassSlider, *_lowPassSlider, *_presenceSlider, *_gainSlider;
    UILabel  *_noiseValue, *_highPassValue, *_lowPassValue, *_presenceValue, *_gainValue;
}

- (void)loadView {
    [self mesh_loadScreen];
    CGFloat W = self.view.bounds.size.width;

    _scroll = [self mesh_addPageTitled:L(@"Audio Lab")];
    CGFloat y = 16;

    CGFloat inner = W - 2 * kMargin;

    // Aufnehmen, Hinweis darunter
    _recBtn = [MeshControls primaryButtonWithFrame:CGRectMake(kMargin, y, inner, 52) title:L(@"Record") target:self action:@selector(toggleRecord)];
    [_scroll addSubview:_recBtn];
    y += 52 + 8;
    _status = [MeshControls labelWithFrame:CGRectMake(kMargin, y, inner, 18) font:[MeshTheme timeFont] color:[MeshTheme muted]];
    _status.text = L(@"Say a sentence, then turn the sliders.");
    [_scroll addSubview:_status];
    y += 26;

    // Original und Bearbeitet nebeneinander
    CGFloat half = (inner - kGap) / 2;
    UIButton *original = [MeshControls secondaryButtonWithFrame:CGRectMake(kMargin, y, half, 42) title:L(@"Original") target:self action:@selector(playOriginal)];
    UIButton *processed = [MeshControls secondaryButtonWithFrame:CGRectMake(kMargin + half + kGap, y, half, 42) title:L(@"Processed") target:self action:@selector(playProcessed)];
    for (UIButton *b in @[original, processed])
        [MeshControls setIcon:[MeshGlyphs playPauseIcon:NO size:14 color:[MeshTheme ink]] onButton:b];
    processed.backgroundColor = [MeshTheme accentDim];
    [processed setTitleColor:[MeshTheme bg] forState:UIControlStateNormal];
    [_scroll addSubview:original];
    [_scroll addSubview:processed];
    y += 42 + 16;

    // Regler
    UILabel *vn = nil, *vh = nil, *vl = nil, *vp = nil, *vg = nil;
    _noiseSlider    = [self panel:L(@"Noise reduction") at:&y width:W min:0 max:4 val:[MeshVoiceSettings labNoise] valLabel:&vn];
    _highPassSlider = [self panel:L(@"High-pass (low cut)") at:&y width:W min:0 max:300 val:[MeshVoiceSettings labHp] valLabel:&vh];
    _lowPassSlider  = [self panel:L(@"Low-pass (high cut)") at:&y width:W min:2500 max:7800 val:[MeshVoiceSettings labLp] valLabel:&vl];
    _presenceSlider = [self panel:L(@"Presence / clarity") at:&y width:W min:-6 max:12 val:[MeshVoiceSettings labPresence] valLabel:&vp];
    _gainSlider     = [self panel:L(@"Volume") at:&y width:W min:0.5f max:3.0f val:[MeshVoiceSettings labGain] valLabel:&vg];
    _noiseValue = vn; _highPassValue = vh; _lowPassValue = vl; _presenceValue = vp; _gainValue = vg;
    [self updateValueLabels];

    [_scroll addSubview:[MeshControls primaryButtonWithFrame:CGRectMake(kMargin, y + 6, inner, 50) title:L(@"Set as default") target:self action:@selector(applyAsDefault)]];
    y += 50 + 20;
    _scroll.contentSize = CGSizeMake(W, y);
}

- (UISlider *)panel:(NSString *)title at:(CGFloat *)yp width:(CGFloat)W min:(float)mn max:(float)mx val:(float)v valLabel:(UILabel **)outVal {
    CGFloat y = *yp;
    UILabel *t = [MeshControls labelWithFrame:CGRectMake(kMargin + 2, y, W - 120, 20) font:[MeshTheme bodyFont] color:[MeshTheme ink]];
    t.text = title;
    [_scroll addSubview:t];
    UILabel *val = [MeshControls labelWithFrame:CGRectMake(W - 100, y, 84, 20) font:[MeshTheme labelFont] color:[MeshTheme accent]];
    val.textAlignment = NSTextAlignmentRight;
    [_scroll addSubview:val];
    *outVal = val;
    UISlider *s = [[UISlider alloc] initWithFrame:CGRectMake(kMargin, y + 22, W - 2 * kMargin, 28)];
    s.minimumValue = mn;
    s.maximumValue = mx;
    s.value = v;
    [s mesh_tint:[MeshTheme accent]];
    [s addTarget:self action:@selector(sliderMoved) forControlEvents:UIControlEventValueChanged];
    [s addTarget:self action:@selector(sliderDone) forControlEvents:UIControlEventTouchUpInside];
    [s addTarget:self action:@selector(sliderDone) forControlEvents:UIControlEventTouchUpOutside];
    [_scroll addSubview:s];
    *yp = y + 22 + 28 + 14;
    return s;
}

- (void)updateValueLabels {
    _noiseValue.text    = [MeshVoiceSettings noiseLabel:(int)roundf(_noiseSlider.value)];
    _highPassValue.text = [NSString stringWithFormat:@"%d Hz", (int)roundf(_highPassSlider.value)];
    _lowPassValue.text  = [NSString stringWithFormat:@"%d Hz", (int)roundf(_lowPassSlider.value)];
    _presenceValue.text = [NSString stringWithFormat:@"%+d dB", (int)roundf(_presenceSlider.value)];
    _gainValue.text     = [NSString stringWithFormat:@"%.1f×", _gainSlider.value];
}
- (void)sliderMoved { [self updateValueLabels]; }
- (void)sliderDone { [self updateValueLabels]; [self playProcessed]; }   // sofort hören

#pragma mark - Aufnahme

- (void)toggleRecord {
    if (!_voice) _voice = [[MeshVoice alloc] init];
    if (_recording) {
        _recording = NO;
        [_recBtn setTitle:L(@"Record") forState:UIControlStateNormal];
        [MeshControls setIcon:nil onButton:_recBtn];
        _recBtn.backgroundColor = [MeshTheme accent];
        MeshWipe(_raw);
        _raw = [_voice stopRawRecording];
        int secs = (int)(_raw.length / 2 / MeshAudioSampleRate);
        _status.text = _raw.length > 1000 ? LF(@"Recording ready (%d s) — now test the sliders", MAX(1, secs)) : L(@"Recording empty — try again");
        [self playProcessed];
        return;
    }
    if (![_voice startRawRecording:kLabSeconds]) { _status.text = L(@"Microphone unavailable"); return; }
    _recording = YES;
    [_recBtn setTitle:L(@"Stop") forState:UIControlStateNormal];
    [MeshControls setIcon:[MeshGlyphs stopIcon:14 color:[MeshTheme bg]] onButton:_recBtn]; _recBtn.backgroundColor = [MeshTheme danger];
    _status.text = LF(@"Recording … (max %d s)", (int)kLabSeconds);
}

#pragma mark - Abspielen

- (void)playOriginal {
    if (!_raw.length) { _status.text = L(@"Record first"); return; }
    [_voice playPCM:_raw];
}

- (void)playProcessed {
    if (!_raw.length) return;
    [_voice playPCM:[MeshAudioDSP process:_raw noise:_noiseSlider.value hp:_highPassSlider.value lp:_lowPassSlider.value presence:_presenceSlider.value gain:_gainSlider.value]];
}

- (void)applyAsDefault {
    [MeshVoiceSettings setLabNoise:_noiseSlider.value];
    [MeshVoiceSettings setLabHp:_highPassSlider.value];
    [MeshVoiceSettings setLabLp:_lowPassSlider.value];
    [MeshVoiceSettings setLabPresence:_presenceSlider.value];
    [MeshVoiceSettings setLabGain:_gainSlider.value];
    [MeshPopup info:L(@"Applied — now active for all voice messages.")];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(discardRecording)
                                                 name:MeshWillLockNotification object:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self discardRecording];
}

// Die eigene Stimme bleibt nicht im Speicher: beim Verlassen und beim Sperren überschreiben.
- (void)discardRecording {
    [_voice stop];
    if (_recording) {
        MeshWipe([_voice stopRawRecording]);
        _recording = NO;
        [_recBtn setTitle:L(@"Record") forState:UIControlStateNormal];
        [MeshControls setIcon:nil onButton:_recBtn];
        _recBtn.backgroundColor = [MeshTheme accent];
    }
    MeshWipe(_raw);
    _raw = nil;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    MeshWipe(_raw);
}
@end
