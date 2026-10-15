#import "MeshBubbleCell.h"
#import "MeshEmojiLabel.h"
#import "MeshTheme.h"
#import "MeshGlyphs.h"
#import "MeshL10n.h"
#import "MeshFormat.h"
#import "MeshAvatarView.h"
#import "MeshEmoji.h"
#import "MeshNotifications.h"

static const CGFloat kBubbleMaxFrac = 0.74f;   // max Bubble-Breite (Text)
static const CGFloat kBubblePadX = 12, kBubblePadY = 8, kRowVPad = 3;
static const CGFloat kVoiceIcon = 36;           // runder Play-Knopf der Sprachblase
static const CGFloat kVoiceWidth = 212, kVoiceHeight = 46;
static const CGFloat kFileWidth = 220, kFileHeight = 54, kFileIcon = 38;   // Datei: Symbol, Name, Art · Größe
static const CGFloat kVideoWidth = 220, kVideoHeight = 160, kVideoPlay = 54;   // wie Android (dort 150–280)
static const CGFloat kCardWidth = 252, kCardHead = 78, kCardAction = 46, kCardAvatar = 48, kCardRing = 2.5f;   // Kontakt-Karte wie Android
static const CGFloat kQuoteHeight = 38, kQuoteGap = 2, kQuoteBar = 3;   // Zitat über der Blase
static const CGFloat kReactionHeight = 24, kReactionOverlap = 10;        // ragt so weit unter die Blase
static const CGFloat kHeadHeight = 17;                                   // Absender / "an alle" über der Blase

// Anzeigegröße eines Bildes, in eine max. Breite/Höhe eingepasst.
static CGSize MeshImgDisplaySize(CGSize size, CGFloat maxW, CGFloat maxH) {
    CGFloat w = size.width, h = size.height;
    if (w < 1 || h < 1) return CGSizeMake(maxW, maxW);
    CGFloat s = MIN(MIN(maxW / w, maxH / h), 1.0f);
    return CGSizeMake(roundf(w * s), roundf(h * s));
}

// UILabel mit Innenabstand, damit der Text nicht am Bubble-Rand klebt.
@interface MeshPadLabel : UILabel
@end
@implementation MeshPadLabel
- (void)drawTextInRect:(CGRect)rect {
    UIEdgeInsets in = UIEdgeInsetsMake(kBubblePadY, kBubblePadX, kBubblePadY, kBubblePadX);
    [super drawTextInRect:UIEdgeInsetsInsetRect(rect, in)];
}
@end

// Wellenform-Balken für Sprachnachrichten (26 Balken, deterministisch aus dem Inhalt).
@interface MeshWaveView : UIView
@property (nonatomic, copy) NSString *seed;
@property (nonatomic, assign) BOOL fromMe;
@property (nonatomic, assign) CGFloat progress;   // 0..1 abgespielt
@end
@implementation MeshWaveView
- (void)setSeed:(NSString *)seed { _seed = [seed copy]; [self setNeedsDisplay]; }
// Neu zeichnen nur, wenn sich die Zahl der abgespielten Balken ändert (gleiche Bedingung wie drawRect).
static int playedBars(CGFloat progress) {
    int k = 0;
    for (int i = 0; i < 26; i++) if (progress > 0 && ((CGFloat)i / 26) <= progress) k++;
    return k;
}
- (void)setProgress:(CGFloat)p {
    BOOL same = playedBars(p) == playedBars(_progress);
    _progress = p;
    if (!same) [self setNeedsDisplay];
}
- (void)drawRect:(CGRect)r {
    const int n = 26;
    uint32_t h = 0;   // vorzeichenlos: Überlauf ist hier gewollt und definiert
    for (NSUInteger i = 0; i < _seed.length; i++) h = h * 31 + [_seed characterAtIndex:i];
    CGFloat gap = 3, w = self.bounds.size.width, H = self.bounds.size.height;
    CGFloat bw = (w - gap*(n-1)) / n;
    UIColor *played   = _fromMe ? [MeshTheme bg] : [MeshTheme accent];
    UIColor *unplayed = _fromMe ? [[MeshTheme bubbleMeInk] colorWithAlphaComponent:0.55f]
                                : [[MeshTheme muted] colorWithAlphaComponent:0.55f];
    for (int i = 0; i < n; i++) {
        h = h * 31 + i * 7;
        CGFloat frac = 0.25f + (h % 100) / 100.0f * 0.75f;
        CGFloat bh = H * frac;
        CGFloat x = i * (bw + gap), y = (H - bh)/2;
        BOOL done = (_progress > 0) && ((CGFloat)i / n) <= _progress;
        [(done ? played : unplayed) setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(x, y, bw, bh) cornerRadius:bw/2] fill];
    }
}
@end

// Sprechblase: Text, Bild oder Sprache; links fremde, rechts eigene Nachrichten, mit Haken.
@implementation MeshBubbleCell {
    MeshPadLabel *_bubble;
    UIImageView *_photo;
    UIImageView *_tick;
    UIImageView *_vIcon;        // Play/Pause-Symbol im Kreis
    MeshWaveView *_vBar;
    UILabel *_vDur;
    UIView *_quote;
    UILabel *_quoteAuthor, *_quoteText;
    UILabel *_reaction;
    UIImageView *_fIcon;
    UILabel *_fName, *_fDetail;
    UIImageView *_play;         // Play-Knopf über dem Video-Vorschaubild
    UIView *_cRing, *_cLine;    // Kontakt-Karte: Ring um den Avatar, Trennlinie über der Aktion
    MeshAvatarView *_cAvatar;
    UILabel *_cName, *_cSub, *_cAction;
    UIImageView *_cSubIcon, *_cActionIcon;
    UILabel *_head;             // Absender bzw. "an alle", erst bei Bedarf angelegt
    CGFloat _headH, _quoteH;
    CGFloat _top;               // Platz über der Blase (Kopfzeile + Zitat)
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
        self.backgroundColor = [MeshTheme bg];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _bubble = [[MeshPadLabel alloc] init];
        _bubble.numberOfLines = 0;
        _bubble.font = [MeshTheme bodyFont];
        // Rund wird nur die Hintergrundfarbe (layer.cornerRadius ohne Ausschneiden): Text, Foto (eigene
        // Rundung, 3 pt Rand) und Symbole reichen nicht in die Ecken. clipsToBounds hieße am A4 einen
        // Offscreen-Durchgang pro Blase und Frame – der Hauptgrund für Ruckeln beim Wechseln.
        _bubble.layer.cornerRadius = [MeshTheme bubbleRadius];
        [self.contentView addSubview:_bubble];
        // Bilder und Video-Vorschauen kommen schon gerundet auf der Blasenfarbe (photoForBubble:, videoThumbForBubble:):
        // ohne clipsToBounds. Der Radius rundet nur die Hintergrundfarbe (Platzhalter, solange das Bild lädt).
        _photo = [[UIImageView alloc] init];
        _photo.contentMode = UIViewContentModeScaleAspectFill;
        _photo.layer.cornerRadius = [MeshTheme bubbleRadius] - 3;   // 3 pt Rand in der Blase
        [_bubble addSubview:_photo];
        _tick = [[UIImageView alloc] init];
        [self.contentView addSubview:_tick];
        // Sprache, Datei, Video-Knopf, Kontaktkarte, Zitat und Reaktion erst, wenn eine Zeile sie braucht
    }
    return self;
}

- (void)addVoiceViews {
    if (_vIcon) return;
    // Sprach-Elemente: runder Play/Pause-Kreis + Wellenform + Dauer.
    _vIcon = [[UIImageView alloc] init]; _vIcon.contentMode = UIViewContentModeCenter;
    _vIcon.layer.cornerRadius = kVoiceIcon / 2; _vIcon.hidden = YES;
    [_bubble addSubview:_vIcon];
    _vBar = [[MeshWaveView alloc] init]; _vBar.backgroundColor = [UIColor clearColor]; _vBar.opaque = NO; _vBar.hidden = YES;
    [_bubble addSubview:_vBar];
    _vDur = [[UILabel alloc] init]; _vDur.font = [MeshTheme timeFont]; _vDur.backgroundColor = [UIColor clearColor];
    _vDur.textAlignment = NSTextAlignmentRight; _vDur.hidden = YES; [_bubble addSubview:_vDur];
}

- (void)addPlayView {
    if (_play) return;
    _play = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, kVideoPlay, kVideoPlay)];
    _play.contentMode = UIViewContentModeCenter;
    _play.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6f];
    _play.layer.cornerRadius = kVideoPlay / 2;
    _play.image = [MeshGlyphs playPauseIcon:NO size:26 color:[UIColor whiteColor]];
    _play.hidden = YES;
    [_bubble addSubview:_play];
}

// Ecken des Bildes auf die Blasenfarbe malen statt auszuschneiden: sieht gleich aus, kostet am A4
// aber keinen Offscreen-Durchgang je Zeile und Frame. Aspect-fill wie die UIImageView.
static UIImage *roundedOnBubble(UIImage *img, CGSize box, BOOL fromMe, CGFloat scale) {
    CGRect r = CGRectMake(0, 0, box.width, box.height);
    UIGraphicsBeginImageContextWithOptions(box, YES, scale);
    [(fromMe ? [MeshTheme accentDeep] : [MeshTheme surfaceHi]) setFill];
    UIRectFill(r);
    [[UIBezierPath bezierPathWithRoundedRect:r cornerRadius:[MeshTheme bubbleRadius] - 3] addClip];
    CGSize s = img.size;
    CGFloat f = MAX(box.width / MAX(1, s.width), box.height / MAX(1, s.height));
    CGSize d = CGSizeMake(s.width * f, s.height * f);
    [img drawInRect:CGRectMake((box.width - d.width) / 2, (box.height - d.height) / 2, d.width, d.height)];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out;
}

+ (UIImage *)photoForBubble:(UIImage *)image tableWidth:(CGFloat)width fromMe:(BOOL)fromMe scale:(CGFloat)scale {
    return roundedOnBubble(image, MeshImgDisplaySize(image.size, width * 0.62f, 260), fromMe, scale);
}

+ (UIImage *)videoThumbForBubble:(UIImage *)thumb fromMe:(BOOL)fromMe scale:(CGFloat)scale {
    return roundedOnBubble(thumb, CGSizeMake(kVideoWidth, kVideoHeight), fromMe, scale);
}

- (void)addFileViews {
    if (_fIcon) return;
    _fIcon = [[UIImageView alloc] initWithFrame:CGRectMake(8, (kFileHeight - kFileIcon) / 2, kFileIcon, kFileIcon)];
    _fIcon.contentMode = UIViewContentModeCenter;
    _fIcon.layer.cornerRadius = 9;
    _fName = [[UILabel alloc] initWithFrame:CGRectMake(kFileIcon + 16, 9, kFileWidth - kFileIcon - 24, 18)];
    _fName.font = [MeshTheme labelFont];
    _fName.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _fDetail = [[UILabel alloc] initWithFrame:CGRectMake(kFileIcon + 16, 28, kFileWidth - kFileIcon - 24, 16)];
    _fDetail.font = [MeshTheme timeFont];
    for (UIView *v in @[_fIcon, _fName, _fDetail]) { v.hidden = YES; v.backgroundColor = [UIColor clearColor]; [_bubble addSubview:v]; }
}

- (void)hideFile { _fIcon.hidden = YES; _fName.hidden = YES; _fDetail.hidden = YES; _play.hidden = YES; [self hideCard]; }   // nil: nichts zu tun

- (void)addCardViews {
    if (_cRing) return;
    _cRing = [[UIView alloc] init];
    _cRing.layer.borderWidth = 2;
    _cRing.layer.borderColor = [[MeshTheme accent] colorWithAlphaComponent:0.55f].CGColor;
    _cRing.backgroundColor = [UIColor clearColor];
    _cAvatar = [[MeshAvatarView alloc] initWithFrame:CGRectMake(kCardRing + 2, kCardRing + 2, kCardAvatar, kCardAvatar) source:MeshAvatarContact];
    [_cRing addSubview:_cAvatar];
    _cName = [[MeshEmojiLabel alloc] init];
    _cName.font = [MeshTheme nameFont];
    _cName.textColor = [MeshTheme ink];
    _cSubIcon = [[UIImageView alloc] initWithImage:[MeshGlyphs icon:@"forward" color:[MeshTheme accent] size:12]];
    _cSub = [[UILabel alloc] init];
    _cSub.font = [MeshTheme timeFont];
    _cSub.textColor = [MeshTheme muted];
    _cSub.text = L(@"Shared contact");
    _cLine = [[UIView alloc] init];
    _cLine.backgroundColor = [MeshTheme line];
    _cActionIcon = [[UIImageView alloc] init];
    _cActionIcon.contentMode = UIViewContentModeCenter;
    _cAction = [[UILabel alloc] init];
    _cAction.font = [MeshTheme bodyFont];
    _cAction.textColor = [MeshTheme accent];
    for (UIView *v in @[_cRing, _cName, _cSubIcon, _cSub, _cLine, _cActionIcon, _cAction]) {
        v.hidden = YES;
        if (v != _cRing && v != _cLine) v.backgroundColor = [UIColor clearColor];
        [_bubble addSubview:v];
    }
}

- (void)hideCard {
    if (_cRing) for (UIView *v in @[_cRing, _cName, _cSubIcon, _cSub, _cLine, _cActionIcon, _cAction]) v.hidden = YES;
    _bubble.layer.borderWidth = 0;
}

+ (CGFloat)heightForContactCardWithAction:(BOOL)action {
    return kCardHead + (action ? kCardAction + 1 : 0) + 2 * kRowVPad + 4;
}

// Kontakt-Karte: Avatar mit Mint-Ring, Name, "Geteilter Kontakt"; darunter beim Empfänger die
// Aktion (Hinzufügen / Chat öffnen), die ganze Zeile ist antippbar.
- (void)setContactCard:(NSString *)name pubkey:(NSString *)pubkey action:(NSString *)action glyph:(NSString *)glyph
                fromMe:(BOOL)fromMe status:(MeshMessageStatus)status width:(CGFloat)width {
    [self setCard:name subtitle:L(@"Shared contact") pubkey:pubkey action:action glyph:glyph fromMe:fromMe status:status width:width];
}

- (void)setCard:(NSString *)name subtitle:(NSString *)subtitle pubkey:(NSString *)pubkey action:(NSString *)action glyph:(NSString *)glyph
         fromMe:(BOOL)fromMe status:(MeshMessageStatus)status width:(CGFloat)width {
    _photo.hidden = YES; _photo.image = nil; _bubble.text = nil; [self hideVoice]; [self hideFile];
    [self addCardViews];
    _cSub.text = subtitle;
    CGFloat h = kCardHead + (action ? kCardAction + 1 : 0);
    CGFloat x = fromMe ? (width - kCardWidth - 12) : 12;
    _bubble.frame = CGRectMake(x, kRowVPad + _top, kCardWidth, h);
    _bubble.backgroundColor = [MeshTheme surface];
    _bubble.layer.borderWidth = 1;
    _bubble.layer.borderColor = [MeshTheme line].CGColor;
    CGFloat ring = kCardAvatar + 2 * (kCardRing + 2);
    _cRing.frame = CGRectMake(14, (kCardHead - ring) / 2, ring, ring);
    _cRing.layer.cornerRadius = ring / 2;
    _cAvatar.pubkey = pubkey ?: @"";
    CGFloat tx = 14 + ring + 13, tw = kCardWidth - tx - 12;
    _cName.frame = CGRectMake(tx, kCardHead / 2 - 21, tw, 21);
    _cName.text = name;
    _cSubIcon.frame = CGRectMake(tx, kCardHead / 2 + 5, 12, 12);
    _cSub.frame = CGRectMake(tx + 17, kCardHead / 2 + 1, tw - 17, 18);
    for (UIView *v in @[_cRing, _cName, _cSubIcon, _cSub]) v.hidden = NO;
    if (action) {
        _cLine.frame = CGRectMake(0, kCardHead, kCardWidth, 1);
        CGFloat aw = [action sizeWithFont:_cAction.font].width, gx = (kCardWidth - aw - 26) / 2;
        _cActionIcon.frame = CGRectMake(gx, kCardHead + 1, 18, kCardAction);
        _cActionIcon.image = [MeshGlyphs icon:glyph color:[MeshTheme accent] size:18];
        _cAction.frame = CGRectMake(gx + 26, kCardHead + 1, aw + 2, kCardAction);
        _cAction.text = action;
        for (UIView *v in @[_cLine, _cActionIcon, _cAction]) v.hidden = NO;
    }
    [self layoutTickFor:fromMe status:status];
    [self layoutDecorationsFromMe:fromMe width:width];
}

// Feste Höhe: die Zeilenhöhe steht so fest, bevor das Vorschaubild (im Hintergrund) fertig ist.
+ (CGFloat)heightForVideo { return kVideoHeight + 6 + 2 * kRowVPad + 4; }

// Vorschaubild randlos zugeschnitten in der Blase (3 pt Rand wie Bilder), Play-Knopf mittig.
- (void)setVideo:(UIImage *)thumb fromMe:(BOOL)fromMe status:(MeshMessageStatus)status width:(CGFloat)width {
    _bubble.text = nil; [self hideVoice]; [self hideFile];
    _bubble.backgroundColor = fromMe ? [MeshTheme accentDeep] : [MeshTheme surfaceHi];
    CGFloat vh = kVideoHeight, bw = kVideoWidth + 6, bh = vh + 6;
    CGFloat x = fromMe ? (width - bw - 12) : 12;
    _bubble.frame = CGRectMake(x, kRowVPad + _top, bw, bh);
    _photo.hidden = NO;
    _photo.image = thumb;
    _photo.backgroundColor = [MeshTheme field];
    _photo.frame = CGRectMake(3, 3, kVideoWidth, vh);
    [self addPlayView];
    _play.hidden = NO;
    _play.center = CGPointMake(bw / 2, bh / 2);
    [_bubble bringSubviewToFront:_play];
    [self layoutTickFor:fromMe status:status];
    [self layoutDecorationsFromMe:fromMe width:width];
}

- (void)setFile:(NSString *)name detail:(NSString *)detail fromMe:(BOOL)fromMe status:(MeshMessageStatus)status width:(CGFloat)width {
    _photo.hidden = YES; _photo.image = nil; _bubble.text = nil; [self hideVoice]; [self hideCard]; _play.hidden = YES;
    _bubble.backgroundColor = fromMe ? [MeshTheme accentDeep] : [MeshTheme surfaceHi];
    CGFloat x = fromMe ? (width - kFileWidth - 12) : 12;
    _bubble.frame = CGRectMake(x, kRowVPad + _top, kFileWidth, kFileHeight);
    [self addFileViews];
    _fIcon.hidden = NO; _fName.hidden = NO; _fDetail.hidden = NO;
    _fIcon.backgroundColor = fromMe ? [MeshTheme accent] : [MeshTheme accentDim];
    _fIcon.image = [MeshGlyphs icon:@"file" color:(fromMe ? [MeshTheme bg] : [MeshTheme ink]) size:20];
    _fName.text = name;
    _fName.textColor = fromMe ? [MeshTheme bubbleMeInk] : [MeshTheme ink];
    _fDetail.text = detail;
    _fDetail.textColor = fromMe ? [[MeshTheme bubbleMeInk] colorWithAlphaComponent:0.8f] : [MeshTheme muted];
    [self layoutTickFor:fromMe status:status];
    [self layoutDecorationsFromMe:fromMe width:width];
}

+ (CGFloat)heightForFile { return kFileHeight + 2 * kRowVPad + 4; }

// Linker Balken des Zitats, schon auf die runden Ecken (Radius 8) zugeschnitten: das Zitat braucht
// dann kein clipsToBounds (Offscreen-Durchgang); der Radius rundet nur die Hintergrundfarbe.
static UIImage *quoteBarImage(void) {
    static UIImage *img; static dispatch_once_t once;
    dispatch_once(&once, ^{
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(kQuoteBar, kQuoteHeight), NO, 0);
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 32, kQuoteHeight) cornerRadius:8] addClip];
        [[MeshTheme accent] setFill];
        UIRectFill(CGRectMake(0, 0, kQuoteBar, kQuoteHeight));
        img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    });
    return img;
}

- (void)addQuote {
    if (_quote) return;
    _quote = [[UIView alloc] init];
    _quote.backgroundColor = [MeshTheme surface];
    _quote.layer.cornerRadius = 8;
    _quote.hidden = YES;
    UIImageView *bar = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, kQuoteBar, kQuoteHeight)];
    bar.image = quoteBarImage();
    [_quote addSubview:bar];
    _quoteAuthor = [[MeshEmojiLabel alloc] init];
    _quoteAuthor.font = [MeshTheme timeFont];
    _quoteAuthor.textColor = [MeshTheme accent];
    _quoteAuthor.backgroundColor = [UIColor clearColor];
    [_quote addSubview:_quoteAuthor];
    _quoteText = [[MeshEmojiLabel alloc] init];
    _quoteText.font = [MeshTheme timeFont];
    _quoteText.textColor = [MeshTheme muted];
    _quoteText.backgroundColor = [UIColor clearColor];
    [_quote addSubview:_quoteText];
    [_quote addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(quoteTap)]];
    [self.contentView addSubview:_quote];
}

- (void)addReaction {
    if (_reaction) return;
    _reaction = [[UILabel alloc] init];
    _reaction.font = [UIFont systemFontOfSize:14];
    _reaction.textAlignment = NSTextAlignmentCenter;
    _reaction.backgroundColor = [MeshTheme surfaceHi];
    _reaction.layer.cornerRadius = kReactionHeight / 2;
    _reaction.layer.borderWidth = 1.5f;
    _reaction.layer.borderColor = [MeshTheme bg].CGColor;
    _reaction.hidden = YES;
    [self.contentView addSubview:_reaction];
}

- (void)quoteTap { if (self.quoteTapped) self.quoteTapped(); }

- (void)setQuoteAuthor:(NSString *)author text:(NSString *)text {
    if (author) [self addQuote];
    _quote.hidden = author == nil;
    _quoteAuthor.text = author;
    _quoteText.text = text;
    _quoteH = author ? kQuoteHeight + kQuoteGap : 0;
    _top = _headH + _quoteH;
}

- (void)setHeader:(NSString *)text color:(UIColor *)color {
    if (text.length && !_head) {
        _head = [[MeshEmojiLabel alloc] init];
        _head.font = [MeshTheme timeFont];
        _head.backgroundColor = [MeshTheme bg];
        [self.contentView addSubview:_head];
    }
    _head.hidden = !text.length;
    _head.text = text;
    _head.textColor = color ?: [MeshTheme muted];
    _headH = text.length ? kHeadHeight : 0;
    _top = _headH + _quoteH;
}

- (void)setReactions:(NSString *)reactions {
    if (reactions.length) [self addReaction];
    _reaction.text = reactions;
    _reaction.hidden = reactions.length == 0;
}

+ (CGFloat)extraHeightWithQuote:(BOOL)quote reactions:(BOOL)reactions {
    return [self extraHeightWithQuote:quote reactions:reactions header:NO];
}

+ (CGFloat)extraHeightWithQuote:(BOOL)quote reactions:(BOOL)reactions header:(BOOL)header {
    return (header ? kHeadHeight : 0) + (quote ? kQuoteHeight + kQuoteGap : 0) + (reactions ? kReactionHeight - kReactionOverlap : 0);
}

// Zitat über der Blase (gleiche Seite, mindestens so breit wie der Text darin), Reaktionen
// halb unter der Blase auf der Seite gegenüber dem Haken.
- (void)layoutDecorationsFromMe:(BOOL)fromMe width:(CGFloat)width {
    CGRect b = _bubble.frame;
    if (_head && !_head.hidden) {
        CGFloat hw = width * kBubbleMaxFrac;
        _head.textAlignment = fromMe ? NSTextAlignmentRight : NSTextAlignmentLeft;
        _head.frame = CGRectMake(fromMe ? CGRectGetMaxX(b) - hw - 4 : b.origin.x + 4, kRowVPad, hw, kHeadHeight - 2);
    }
    if (_quote && !_quote.hidden) {
        CGFloat qw = MIN(width * kBubbleMaxFrac, MAX(b.size.width, 140));
        CGFloat qx = fromMe ? CGRectGetMaxX(b) - qw : b.origin.x;
        _quote.frame = CGRectMake(qx, kRowVPad + _headH, qw, kQuoteHeight);
        _quoteAuthor.frame = CGRectMake(kQuoteBar + 8, 3, qw - kQuoteBar - 14, 16);
        _quoteText.frame = CGRectMake(kQuoteBar + 8, 19, qw - kQuoteBar - 14, 16);
    }
    if (_reaction && !_reaction.hidden) {
        CGFloat rw = MAX(kReactionHeight + 6, [MeshEmoji textSize:_reaction.text font:_reaction.font constrainedTo:CGSizeMake(200, 30)].width + 14);
        CGFloat rx = fromMe ? b.origin.x + 6 : CGRectGetMaxX(b) - rw - 6;
        _reaction.frame = CGRectMake(rx, CGRectGetMaxY(b) - kReactionOverlap, rw, kReactionHeight);
        [self.contentView bringSubviewToFront:_reaction];
    }
}
- (void)hideVoice { _vIcon.hidden = YES; _vBar.hidden = YES; _vDur.hidden = YES; }
- (void)setVoice:(int)seconds seed:(NSString *)seed playing:(BOOL)playing fromMe:(BOOL)fromMe status:(MeshMessageStatus)status width:(CGFloat)width {
    _photo.hidden = YES; _photo.image = nil; _bubble.text = nil; [self hideFile];
    _bubble.backgroundColor = fromMe ? [MeshTheme accentDeep] : [MeshTheme surfaceHi];
    CGFloat bw = kVoiceWidth, bh = kVoiceHeight;
    CGFloat x = fromMe ? (width - bw - 12) : 12;
    _bubble.frame = CGRectMake(x, kRowVPad + _top, bw, bh);
    [self addVoiceViews];
    _vIcon.hidden = NO; _vBar.hidden = NO; _vDur.hidden = NO;
    // runder Play/Pause-Knopf (accent bei mir, accentDim beim Gegenüber)
    _vIcon.backgroundColor = fromMe ? [MeshTheme accent] : [MeshTheme accentDim];
    _vIcon.image = [MeshGlyphs playPauseIcon:playing size:18 color:(fromMe ? [MeshTheme bg] : [MeshTheme ink])];
    _vIcon.frame = CGRectMake(6, (bh-kVoiceIcon)/2, kVoiceIcon, kVoiceIcon);
    // Wellenform (deterministisch aus dem Inhalt)
    _vBar.fromMe = fromMe;
    _vBar.seed = seed ?: @"";
    _vBar.frame = CGRectMake(50, (bh-24)/2, 110, 24);
    _vBar.progress = 0.0f;
    // Dauer
    _vDur.textColor = fromMe ? [[MeshTheme bubbleMeInk] colorWithAlphaComponent:0.85f] : [MeshTheme muted];
    _vDur.frame = CGRectMake(166, (bh-20)/2, 40, 20);
    _vDur.text = [MeshFormat duration:seconds];
    [self layoutTickFor:fromMe status:status];
    [self layoutDecorationsFromMe:fromMe width:width];
}
// Gemessene Textgrößen (Zeilenhöhe und Zelle messen denselben Text): einmal messen. Enthält Klartext,
// darum beim Sperren geleert.
static NSCache *TextSizes(void) {
    static NSCache *cache; static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 400;
        for (NSString *name in @[MeshWillLockNotification, MeshIdentityChangedNotification, MeshWipedNotification])
            [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil
                                                          usingBlock:^(NSNotification *n) { [cache removeAllObjects]; }];
    });
    return cache;
}

+ (CGSize)textSize:(NSString *)text width:(CGFloat)width {
    CGFloat maxW = width * kBubbleMaxFrac - 2 * kBubblePadX;
    NSString *key = [NSString stringWithFormat:@"%.0f|%@", maxW, text ?: @""];
    NSValue *known = [TextSizes() objectForKey:key];
    if (known) return [known CGSizeValue];
    CGSize size = [MeshEmoji textSize:text font:[MeshTheme bodyFont] constrainedTo:CGSizeMake(maxW, 10000)];
    [TextSizes() setObject:[NSValue valueWithCGSize:size] forKey:key];
    return size;
}
- (void)layoutTickFor:(BOOL)fromMe status:(MeshMessageStatus)status {
    if (fromMe) {
        _tick.hidden = NO;
        switch (status) {
            case MeshMessageDelivered: _tick.image = [MeshGlyphs icon:@"doublecheck" color:[MeshTheme accent] size:15]; break;
            case MeshMessageFailed:    _tick.image = [MeshGlyphs icon:@"alert" color:[MeshTheme danger] size:15]; break;
            case MeshMessageSending:   _tick.image = [MeshGlyphs icon:@"check" color:[MeshTheme muted] size:15]; break;
        }
        _tick.contentMode = UIViewContentModeScaleAspectFit;
        // unten rechts, höher – im rechten Padding der Bubble (überlappt keinen Text)
        CGFloat tw = 17, th = 12;
        _tick.frame = CGRectMake(CGRectGetMaxX(_bubble.frame) - tw - 3, CGRectGetMaxY(_bubble.frame) - th + 1, tw, th);
    } else {
        _tick.hidden = YES;
    }
}
- (void)setText:(NSString *)text fromMe:(BOOL)fromMe status:(MeshMessageStatus)status width:(CGFloat)width {
    _photo.hidden = YES; _photo.image = nil; [self hideVoice]; [self hideFile];
    _bubble.text = text;
    _bubble.textColor = fromMe ? [MeshTheme bubbleMeInk] : [MeshTheme ink];
    _bubble.backgroundColor = fromMe ? [MeshTheme accentDeep] : [MeshTheme surfaceHi];
    _bubble.textAlignment = NSTextAlignmentLeft;
    CGSize ts = [MeshBubbleCell textSize:text width:width];
    CGFloat bw = ts.width + 2 * kBubblePadX;
    CGFloat bh = ts.height + 2 * kBubblePadY;
    CGFloat x = fromMe ? (width - bw - 12) : 12;
    _bubble.frame = CGRectMake(x, kRowVPad + _top, bw, bh);
    [self layoutTickFor:fromMe status:status];
    [self layoutDecorationsFromMe:fromMe width:width];
}
- (void)setImage:(UIImage *)image fromMe:(BOOL)fromMe status:(MeshMessageStatus)status width:(CGFloat)width {
    [self setImage:image size:image.size fromMe:fromMe status:status width:width];
}

- (void)setImage:(UIImage *)image size:(CGSize)size fromMe:(BOOL)fromMe status:(MeshMessageStatus)status width:(CGFloat)width {
    _bubble.text = nil; [self hideVoice]; [self hideFile];
    _bubble.backgroundColor = fromMe ? [MeshTheme accentDeep] : [MeshTheme surfaceHi];
    CGSize ds = MeshImgDisplaySize(size, width * 0.62f, 260);
    CGFloat bw = ds.width + 6, bh = ds.height + 6;
    CGFloat x = fromMe ? (width - bw - 12) : 12;
    _bubble.frame = CGRectMake(x, kRowVPad + _top, bw, bh);
    _photo.hidden = NO; _photo.image = image;
    _photo.frame = CGRectMake(3, 3, ds.width, ds.height);
    [self layoutTickFor:fromMe status:status];
    [self layoutDecorationsFromMe:fromMe width:width];
}
+ (CGFloat)heightForText:(NSString *)text width:(CGFloat)width {
    return [self textSize:text width:width].height + 2 * kBubblePadY + 2 * kRowVPad + 4;   // +4 = Abstand, Haken sitzt in der Bubble
}
+ (CGFloat)heightForImageOfSize:(CGSize)size width:(CGFloat)width {
    return MeshImgDisplaySize(size, width * 0.62f, 260).height + 6 + 2 * kRowVPad + 4;
}
+ (CGFloat)heightForVoice { return kVoiceHeight + 2 * kRowVPad + 4; }
- (void)setVoiceProgress:(CGFloat)progress { [_vBar setProgress:progress]; }
@end
