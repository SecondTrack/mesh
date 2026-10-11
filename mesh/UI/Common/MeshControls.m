#import "MeshControls.h"
#import "MeshTheme.h"

@implementation MeshControls

+ (UITextField *)fieldWithFrame:(CGRect)frame placeholder:(NSString *)placeholder mono:(BOOL)mono delegate:(id<UITextFieldDelegate>)delegate {
    UITextField *f = [[UITextField alloc] initWithFrame:frame];
    f.backgroundColor = [MeshTheme field];
    f.textColor = [MeshTheme ink];
    f.font = mono ? [MeshTheme monoFont] : [MeshTheme bodyFont];
    f.layer.cornerRadius = [MeshTheme fieldRadius];
    f.placeholder = placeholder;
    f.autocapitalizationType = mono ? UITextAutocapitalizationTypeNone : UITextAutocapitalizationTypeWords;
    f.autocorrectionType = mono ? UITextAutocorrectionTypeNo : UITextAutocorrectionTypeDefault;
    f.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    f.keyboardAppearance = UIKeyboardAppearanceAlert;
    f.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, frame.size.height)];
    f.leftViewMode = UITextFieldViewModeAlways;
    f.delegate = delegate;
    return f;
}

+ (UIButton *)primaryButtonWithFrame:(CGRect)frame title:(NSString *)title target:(id)target action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = frame;
    b.backgroundColor = [MeshTheme accent];
    b.layer.cornerRadius = [MeshTheme cardRadius];
    b.titleLabel.font = [MeshTheme nameFont];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[MeshTheme bg] forState:UIControlStateNormal];
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

+ (UIButton *)secondaryButtonWithFrame:(CGRect)frame title:(NSString *)title target:(id)target action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = frame;
    b.backgroundColor = [MeshTheme surfaceHi];
    b.layer.cornerRadius = [MeshTheme cardRadius];
    b.layer.borderWidth = 1;
    b.layer.borderColor = [MeshTheme line].CGColor;
    b.titleLabel.font = [MeshTheme nameFont];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[MeshTheme ink] forState:UIControlStateNormal];
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

+ (UILabel *)sectionLabelWithFrame:(CGRect)frame text:(NSString *)text {
    UILabel *l = [[UILabel alloc] initWithFrame:frame];
    l.text = text;
    l.font = [MeshTheme labelFont];
    l.textColor = [MeshTheme muted];
    l.backgroundColor = [UIColor clearColor];
    return l;
}

+ (UILabel *)labelWithFrame:(CGRect)frame font:(UIFont *)font color:(UIColor *)color {
    UILabel *l = [[UILabel alloc] initWithFrame:frame];
    l.font = font;
    l.textColor = color;
    l.backgroundColor = [UIColor clearColor];
    return l;
}

+ (UIView *)switchCardWithFrame:(CGRect)frame title:(NSString *)title subtitle:(NSString *)subtitle
                             on:(BOOL)on target:(id)target action:(SEL)action {
    UIView *card = [self cardWithFrame:frame];
    UISwitch *sw = [[UISwitch alloc] init];
    CGFloat textWidth = frame.size.width - sw.bounds.size.width - 40;
    UILabel *t = [self labelWithFrame:CGRectMake(14, 12, textWidth, 20) font:[MeshTheme bodyFont] color:[MeshTheme ink]];
    t.text = title;
    [card addSubview:t];
    UILabel *s = [self labelWithFrame:CGRectMake(14, 34, textWidth, 18) font:[MeshTheme timeFont] color:[MeshTheme muted]];
    s.text = subtitle;
    [card addSubview:s];
    sw.center = CGPointMake(frame.size.width - 14 - sw.bounds.size.width / 2, frame.size.height / 2);
    sw.onTintColor = [MeshTheme accent];
    sw.on = on;
    [sw addTarget:target action:action forControlEvents:UIControlEventValueChanged];
    [card addSubview:sw];
    return card;
}

+ (UIView *)cardWithFrame:(CGRect)frame {
    UIView *card = [[UIView alloc] initWithFrame:frame];
    card.backgroundColor = [MeshTheme surfaceHi];
    card.layer.cornerRadius = [MeshTheme cardRadius];
    return card;
}

@end
