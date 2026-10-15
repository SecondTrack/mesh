#import "MeshEmojiLabel.h"
#import "MeshEmoji.h"

@implementation MeshEmojiLabel {
    BOOL _emoji;   // bei setText: bestimmt, nicht bei jedem Zeichnen
}

- (void)setText:(NSString *)text {
    NSString *old = self.text;
    if (old == text || [old isEqualToString:text]) return;   // Zellen-Wiederverwendung mit gleichem Text
    _emoji = [MeshEmoji containsEmoji:text];
    [super setText:text];
}

- (UIColor *)drawColor { return self.highlighted && self.highlightedTextColor ? self.highlightedTextColor : self.textColor; }

- (void)drawTextInRect:(CGRect)rect {
    if (!_emoji) { [super drawTextInRect:rect]; return; }
    [MeshEmoji draw:self.text font:self.font color:[self drawColor] alignment:self.textAlignment lines:self.numberOfLines inRect:rect];
}

// Maße wie gezeichnet (sizeToFit, Breite für Zentrieren)
- (CGSize)sizeThatFits:(CGSize)size {
    if (!_emoji) return [super sizeThatFits:size];
    CGFloat w = size.width > 0 ? size.width : CGFLOAT_MAX;
    return [MeshEmoji sizeOf:self.text font:self.font constrainedTo:CGSizeMake(w, CGFLOAT_MAX) lines:self.numberOfLines];
}

@end
