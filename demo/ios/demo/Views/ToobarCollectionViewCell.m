//
//  ToobarCollectionViewCell.m
//  demo
//
//  Created by PixPark.
//

#import "ToobarCollectionViewCell.h"

@interface ToobarCollectionViewCell ()

@property(nonatomic, strong, readwrite) UIView* circleContainer;
@property(nonatomic, strong, readwrite) UIImageView* iconImageView;
@property(nonatomic, strong, readwrite) UILabel* titleLabel;

@end

@implementation ToobarCollectionViewCell

static NSString* const kToobarCollectionViewCell = @"ToobarCollectionViewCell";

+ (NSString*)reuseIdentifier {
  return kToobarCollectionViewCell;
}

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    [self setupUI];
  }
  return self;
}

- (void)setupUI {
  self.backgroundColor = [UIColor clearColor];

  _circleContainer = [[UIView alloc] init];
  _circleContainer.translatesAutoresizingMaskIntoConstraints = NO;
  _circleContainer.layer.cornerRadius = 29.0;
  _circleContainer.layer.masksToBounds = YES;
  [self.contentView addSubview:_circleContainer];

  _iconImageView = [[UIImageView alloc] init];
  _iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
  _iconImageView.contentMode = UIViewContentModeScaleAspectFit;
  _iconImageView.tintColor = [UIColor whiteColor];
  [_circleContainer addSubview:_iconImageView];

  _titleLabel = [[UILabel alloc] init];
  _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  _titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
  _titleLabel.textAlignment = NSTextAlignmentCenter;
  _titleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.85];
  [_circleContainer addSubview:_titleLabel];

  [NSLayoutConstraint activateConstraints:@[
    [_circleContainer.widthAnchor constraintEqualToConstant:58],
    [_circleContainer.heightAnchor constraintEqualToConstant:58],
    [_circleContainer.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
    [_circleContainer.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],

    [_iconImageView.centerXAnchor constraintEqualToAnchor:_circleContainer.centerXAnchor],
    [_iconImageView.topAnchor constraintEqualToAnchor:_circleContainer.topAnchor constant:8],
    [_iconImageView.widthAnchor constraintEqualToConstant:22],
    [_iconImageView.heightAnchor constraintEqualToConstant:22],

    [_titleLabel.centerXAnchor constraintEqualToAnchor:_circleContainer.centerXAnchor],
    [_titleLabel.bottomAnchor constraintEqualToAnchor:_circleContainer.bottomAnchor constant:-6],
    [_titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_circleContainer.leadingAnchor constant:4],
    [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_circleContainer.trailingAnchor constant:-4],
  ]];
}

- (void)configureWithTitle:(NSString*)title
                  iconName:(NSString*)iconName
                isSelected:(BOOL)isSelected {
  self.titleLabel.text = title;

  UIImage* icon = [UIImage imageNamed:iconName];
  if (!icon) {
    // Fallback to SF symbol if needed
    icon = [UIImage systemImageNamed:@"sparkles"];
  }
  self.iconImageView.image = icon;

  UIColor* accentColor = [UIColor colorWithRed:1.0 green:0.325 blue:0.463 alpha:1.0]; // #FF5376

  if (isSelected) {
    self.circleContainer.backgroundColor = [UIColor colorWithRed:1.0 green:0.325 blue:0.463 alpha:0.25];
    self.circleContainer.layer.borderWidth = 2.0;
    self.circleContainer.layer.borderColor = accentColor.CGColor;
    self.titleLabel.textColor = accentColor;
    self.iconImageView.tintColor = accentColor;
  } else {
    self.circleContainer.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.15];
    self.circleContainer.layer.borderWidth = 0.0;
    self.circleContainer.layer.borderColor = [UIColor clearColor].CGColor;
    self.titleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.85];
    self.iconImageView.tintColor = [UIColor whiteColor];
  }
}

@end
