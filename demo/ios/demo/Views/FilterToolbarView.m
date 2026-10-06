//
//  FilterToolbarView.m
//  demo
//
//  Created by PixPark.
//

#import "FilterToolbarView.h"
#import "ToobarCollectionViewCell.h"

@implementation BeautyOption

+ (instancetype)optionWithId:(BeautyOptionId)optionId
                        name:(NSString*)name
                    iconName:(NSString*)iconName
                    category:(BeautyCategory)category
             defaultProgress:(NSInteger)defaultProgress {
  BeautyOption* opt = [[BeautyOption alloc] init];
  opt.optionId = optionId;
  opt.name = name;
  opt.iconName = iconName;
  opt.category = category;
  opt.progress = defaultProgress;
  opt.defaultProgress = defaultProgress;
  return opt;
}

@end

@interface FilterToolbarView () <UICollectionViewDelegate,
                                UICollectionViewDataSource,
                                UICollectionViewDelegateFlowLayout>

@property(nonatomic, strong, readwrite) NSArray<BeautyOption*>* allOptions;
@property(nonatomic, strong) NSMutableArray<BeautyOption*>* filteredOptions;
@property(nonatomic, strong, readwrite, nullable) BeautyOption* selectedOption;
@property(nonatomic, assign, readwrite) BeautyCategory currentCategory;

// UI
@property(nonatomic, strong) UIVisualEffectView* blurEffectView;
@property(nonatomic, strong) UIView* sliderContainer;
@property(nonatomic, strong) UIButton* dismissBtn;
@property(nonatomic, strong) UILabel* optionTitleLabel;
@property(nonatomic, strong) UILabel* optionValueLabel;
@property(nonatomic, strong) UISlider* intensitySlider;

@property(nonatomic, strong) UICollectionView* collectionView;
@property(nonatomic, strong) UICollectionViewFlowLayout* flowLayout;

@property(nonatomic, strong) UIView* categoryBar;
@property(nonatomic, strong) NSMutableArray<UIButton*>* categoryButtons;
@property(nonatomic, strong) UIView* categoryIndicator;

@end

@implementation FilterToolbarView

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    [self initOptions];
    [self setupUI];
  }
  return self;
}

- (instancetype)initWithFrame:(CGRect)frame
                 filterTitles:(nullable NSArray<NSString*>*)filterTitles {
  return [self initWithFrame:frame];
}

- (void)initOptions {
  NSMutableArray<BeautyOption*>* opts = [NSMutableArray array];

  // 美肤 (Skin)
  [opts addObject:[BeautyOption optionWithId:BeautyOptionSmooth
                                        name:@"磨皮"
                                    iconName:@"ic_skin_smooth"
                                    category:BeautyCategorySkin
                             defaultProgress:45]];
  [opts addObject:[BeautyOption optionWithId:BeautyOptionWhite
                                        name:@"美白"
                                    iconName:@"ic_skin_white"
                                    category:BeautyCategorySkin
                             defaultProgress:35]];
  [opts addObject:[BeautyOption optionWithId:BeautyOptionSharpen
                                        name:@"清晰"
                                    iconName:@"ic_sharpen"
                                    category:BeautyCategorySkin
                             defaultProgress:25]];

  // 美型 (Shape)
  [opts addObject:[BeautyOption optionWithId:BeautyOptionThinFace
                                        name:@"瘦脸"
                                    iconName:@"ic_thin_face"
                                    category:BeautyCategoryShape
                             defaultProgress:30]];
  [opts addObject:[BeautyOption optionWithId:BeautyOptionBigEye
                                        name:@"大眼"
                                    iconName:@"ic_big_eye"
                                    category:BeautyCategoryShape
                             defaultProgress:25]];

  // 美妆 (Makeup)
  [opts addObject:[BeautyOption optionWithId:BeautyOptionLipstick
                                        name:@"口红"
                                    iconName:@"ic_lipstick"
                                    category:BeautyCategoryMakeup
                             defaultProgress:25]];
  [opts addObject:[BeautyOption optionWithId:BeautyOptionBlusher
                                        name:@"腮红"
                                    iconName:@"ic_blusher"
                                    category:BeautyCategoryMakeup
                             defaultProgress:20]];

  // 滤镜 (Filter)
  [opts addObject:[BeautyOption optionWithId:BeautyOptionFilterOrigin
                                        name:@"原图"
                                    iconName:@"ic_filter"
                                    category:BeautyCategoryFilter
                             defaultProgress:100]];
  [opts addObject:[BeautyOption optionWithId:BeautyOptionFilterPink
                                        name:@"粉嫩"
                                    iconName:@"ic_filter"
                                    category:BeautyCategoryFilter
                             defaultProgress:100]];
  [opts addObject:[BeautyOption optionWithId:BeautyOptionFilterCool
                                        name:@"冷白"
                                    iconName:@"ic_filter"
                                    category:BeautyCategoryFilter
                             defaultProgress:100]];
  [opts addObject:[BeautyOption optionWithId:BeautyOptionFilterFilm
                                        name:@"胶片"
                                    iconName:@"ic_filter"
                                    category:BeautyCategoryFilter
                             defaultProgress:100]];
  [opts addObject:[BeautyOption optionWithId:BeautyOptionFilterBW
                                        name:@"黑白"
                                    iconName:@"ic_filter"
                                    category:BeautyCategoryFilter
                             defaultProgress:100]];

  // 贴纸 (Stickers)
  [opts addObject:[BeautyOption optionWithId:BeautyOptionStickerNone
                                        name:@"无贴纸"
                                    iconName:@"ic_reset"
                                    category:BeautyCategorySticker
                             defaultProgress:0]];
  [opts addObject:[BeautyOption optionWithId:BeautyOptionStickerCatEars
                                        name:@"猫耳朵"
                                    iconName:@"ic_beauty_wand"
                                    category:BeautyCategorySticker
                             defaultProgress:100]];
  [opts addObject:[BeautyOption optionWithId:BeautyOptionStickerBunnyEars
                                        name:@"兔耳朵"
                                    iconName:@"ic_beauty_wand"
                                    category:BeautyCategorySticker
                             defaultProgress:100]];
  [opts addObject:[BeautyOption optionWithId:BeautyOptionStickerCrown
                                        name:@"金皇冠"
                                    iconName:@"ic_beauty_wand"
                                    category:BeautyCategorySticker
                             defaultProgress:100]];
  [opts addObject:[BeautyOption optionWithId:BeautyOptionStickerAngelHalo
                                        name:@"天使环"
                                    iconName:@"ic_beauty_wand"
                                    category:BeautyCategorySticker
                             defaultProgress:100]];
  [opts addObject:[BeautyOption optionWithId:BeautyOptionStickerDevilHorns
                                        name:@"恶魔角"
                                    iconName:@"ic_beauty_wand"
                                    category:BeautyCategorySticker
                             defaultProgress:100]];
  [opts addObject:[BeautyOption optionWithId:BeautyOptionStickerSunglasses
                                        name:@"酷墨镜"
                                    iconName:@"ic_beauty_wand"
                                    category:BeautyCategorySticker
                             defaultProgress:100]];
  [opts addObject:[BeautyOption optionWithId:BeautyOptionStickerHeartBlush
                                        name:@"爱心贴"
                                    iconName:@"ic_beauty_wand"
                                    category:BeautyCategorySticker
                             defaultProgress:100]];
  [opts addObject:[BeautyOption optionWithId:BeautyOptionStickerClownNose
                                        name:@"小丑鼻"
                                    iconName:@"ic_beauty_wand"
                                    category:BeautyCategorySticker
                             defaultProgress:100]];
  [opts addObject:[BeautyOption optionWithId:BeautyOptionStickerMustache
                                        name:@"绅士胡"
                                    iconName:@"ic_beauty_wand"
                                    category:BeautyCategorySticker
                             defaultProgress:100]];
  [opts addObject:[BeautyOption optionWithId:BeautyOptionStickerFlowerHairpin
                                        name:@"樱花夹"
                                    iconName:@"ic_beauty_wand"
                                    category:BeautyCategorySticker
                             defaultProgress:100]];

  self.allOptions = [opts copy];
  self.filteredOptions = [NSMutableArray array];
  self.currentCategory = BeautyCategorySkin;
  self.selectedOption = self.allOptions.firstObject;
}

- (void)setupUI {
  self.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.08 alpha:0.88];
  self.layer.cornerRadius = 24.0;
  self.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
  self.layer.masksToBounds = YES;

  // Visual Blur
  UIBlurEffect* blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
  _blurEffectView = [[UIVisualEffectView alloc] initWithEffect:blur];
  _blurEffectView.frame = self.bounds;
  _blurEffectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [self addSubview:_blurEffectView];

  // 1. Slider Row
  _sliderContainer = [[UIView alloc] init];
  _sliderContainer.translatesAutoresizingMaskIntoConstraints = NO;
  [self addSubview:_sliderContainer];

  _dismissBtn = [UIButton buttonWithType:UIButtonTypeCustom];
  _dismissBtn.translatesAutoresizingMaskIntoConstraints = NO;
  UIImage* downIcon = [UIImage imageNamed:@"ic_arrow_down"];
  if (!downIcon) downIcon = [UIImage systemImageNamed:@"chevron.down"];
  [_dismissBtn setImage:downIcon forState:UIControlStateNormal];
  _dismissBtn.tintColor = [UIColor colorWithWhite:1.0 alpha:0.7];
  [_dismissBtn addTarget:self action:@selector(onDismissTapped) forControlEvents:UIControlEventTouchUpInside];
  [_sliderContainer addSubview:_dismissBtn];

  _optionTitleLabel = [[UILabel alloc] init];
  _optionTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  _optionTitleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
  _optionTitleLabel.textColor = [UIColor whiteColor];
  [_sliderContainer addSubview:_optionTitleLabel];

  _optionValueLabel = [[UILabel alloc] init];
  _optionValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
  _optionValueLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
  _optionValueLabel.textColor = [UIColor colorWithRed:1.0 green:0.325 blue:0.463 alpha:1.0];
  [_sliderContainer addSubview:_optionValueLabel];

  _intensitySlider = [[UISlider alloc] init];
  _intensitySlider.translatesAutoresizingMaskIntoConstraints = NO;
  _intensitySlider.minimumValue = 0.0;
  _intensitySlider.maximumValue = 100.0;
  _intensitySlider.minimumTrackTintColor = [UIColor colorWithRed:1.0 green:0.325 blue:0.463 alpha:1.0];
  _intensitySlider.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.25];
  [_intensitySlider addTarget:self action:@selector(onSliderChanged:) forControlEvents:UIControlEventValueChanged];
  [_sliderContainer addSubview:_intensitySlider];

  // 2. CollectionView for options
  _flowLayout = [[UICollectionViewFlowLayout alloc] init];
  _flowLayout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
  _flowLayout.itemSize = CGSizeMake(58, 58);
  _flowLayout.minimumLineSpacing = 12;
  _flowLayout.sectionInset = UIEdgeInsetsMake(0, 16, 0, 16);

  _collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:_flowLayout];
  _collectionView.translatesAutoresizingMaskIntoConstraints = NO;
  _collectionView.backgroundColor = [UIColor clearColor];
  _collectionView.showsHorizontalScrollIndicator = NO;
  _collectionView.delegate = self;
  _collectionView.dataSource = self;
  [_collectionView registerClass:[ToobarCollectionViewCell class]
      forCellWithReuseIdentifier:[ToobarCollectionViewCell reuseIdentifier]];
  [self addSubview:_collectionView];

  // 3. Category Tab Bar
  _categoryBar = [[UIView alloc] init];
  _categoryBar.translatesAutoresizingMaskIntoConstraints = NO;
  [self addSubview:_categoryBar];

  NSArray* categories = @[ @"美肤", @"美型", @"美妆", @"滤镜", @"贴纸" ];
  _categoryButtons = [NSMutableArray array];
  UIStackView* catStack = [[UIStackView alloc] init];
  catStack.translatesAutoresizingMaskIntoConstraints = NO;
  catStack.axis = UILayoutConstraintAxisHorizontal;
  catStack.distribution = UIStackViewDistributionEqualSpacing;
  catStack.alignment = UIStackViewAlignmentCenter;
  [_categoryBar addSubview:catStack];

  for (NSInteger i = 0; i < categories.count; i++) {
    UIButton* btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.tag = i;
    [btn setTitle:categories[i] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [btn setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.55] forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateSelected];
    [btn addTarget:self action:@selector(onCategoryTapped:) forControlEvents:UIControlEventTouchUpInside];
    [catStack addArrangedSubview:btn];
    [_categoryButtons addObject:btn];
  }

  _categoryIndicator = [[UIView alloc] init];
  _categoryIndicator.translatesAutoresizingMaskIntoConstraints = NO;
  _categoryIndicator.backgroundColor = [UIColor colorWithRed:1.0 green:0.325 blue:0.463 alpha:1.0];
  _categoryIndicator.layer.cornerRadius = 1.5;
  [_categoryBar addSubview:_categoryIndicator];

  [NSLayoutConstraint activateConstraints:@[
    // Slider Container
    [_sliderContainer.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
    [_sliderContainer.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
    [_sliderContainer.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
    [_sliderContainer.heightAnchor constraintEqualToConstant:40],

    [_dismissBtn.leadingAnchor constraintEqualToAnchor:_sliderContainer.leadingAnchor],
    [_dismissBtn.centerYAnchor constraintEqualToAnchor:_sliderContainer.centerYAnchor],
    [_dismissBtn.widthAnchor constraintEqualToConstant:32],
    [_dismissBtn.heightAnchor constraintEqualToConstant:32],

    [_optionTitleLabel.leadingAnchor constraintEqualToAnchor:_dismissBtn.trailingAnchor constant:4],
    [_optionTitleLabel.centerYAnchor constraintEqualToAnchor:_sliderContainer.centerYAnchor],

    [_optionValueLabel.leadingAnchor constraintEqualToAnchor:_optionTitleLabel.trailingAnchor constant:6],
    [_optionValueLabel.centerYAnchor constraintEqualToAnchor:_sliderContainer.centerYAnchor],

    [_intensitySlider.leadingAnchor constraintEqualToAnchor:_optionValueLabel.trailingAnchor constant:12],
    [_intensitySlider.trailingAnchor constraintEqualToAnchor:_sliderContainer.trailingAnchor constant:-8],
    [_intensitySlider.centerYAnchor constraintEqualToAnchor:_sliderContainer.centerYAnchor],

    // CollectionView
    [_collectionView.topAnchor constraintEqualToAnchor:_sliderContainer.bottomAnchor constant:10],
    [_collectionView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
    [_collectionView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    [_collectionView.heightAnchor constraintEqualToConstant:64],

    // Category Bar
    [_categoryBar.topAnchor constraintEqualToAnchor:_collectionView.bottomAnchor constant:8],
    [_categoryBar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:24],
    [_categoryBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-24],
    [_categoryBar.heightAnchor constraintEqualToConstant:38],
    [_categoryBar.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-6],

    [catStack.topAnchor constraintEqualToAnchor:_categoryBar.topAnchor],
    [catStack.bottomAnchor constraintEqualToAnchor:_categoryBar.bottomAnchor],
    [catStack.leadingAnchor constraintEqualToAnchor:_categoryBar.leadingAnchor],
    [catStack.trailingAnchor constraintEqualToAnchor:_categoryBar.trailingAnchor],

    [_categoryIndicator.heightAnchor constraintEqualToConstant:3],
    [_categoryIndicator.widthAnchor constraintEqualToConstant:20],
    [_categoryIndicator.bottomAnchor constraintEqualToAnchor:_categoryBar.bottomAnchor constant:-2],
  ]];

  [self updateCategoryFilter:BeautyCategorySkin];
}

- (void)layoutSubviews {
  [super layoutSubviews];
  [self updateIndicatorPositionAnimated:NO];
}

#pragma mark - Actions

- (void)onDismissTapped {
  if ([self.delegate respondsToSelector:@selector(beautyToolbarViewDidRequestDismiss:)]) {
    [self.delegate beautyToolbarViewDidRequestDismiss:self];
  }
}

- (void)onCategoryTapped:(UIButton*)btn {
  [self updateCategoryFilter:(BeautyCategory)btn.tag];
}

- (void)onSliderChanged:(UISlider*)slider {
  if (self.selectedOption) {
    self.selectedOption.progress = (NSInteger)roundf(slider.value);
    _optionValueLabel.text = [NSString stringWithFormat:@"%ld%%", (long)self.selectedOption.progress];

    if ([self.delegate respondsToSelector:@selector(beautyToolbarView:didChangeValue:forOption:)]) {
      [self.delegate beautyToolbarView:self
                        didChangeValue:self.selectedOption.progress
                             forOption:self.selectedOption];
    }
  }
}

- (void)updateCategoryFilter:(BeautyCategory)category {
  self.currentCategory = category;

  for (UIButton* b in self.categoryButtons) {
    b.selected = (b.tag == category);
    b.titleLabel.font = b.selected ? [UIFont systemFontOfSize:14 weight:UIFontWeightBold]
                                   : [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
  }

  [self updateIndicatorPositionAnimated:YES];

  [self.filteredOptions removeAllObjects];
  for (BeautyOption* opt in self.allOptions) {
    if (opt.category == category) {
      [self.filteredOptions addObject:opt];
    }
  }

  [self.collectionView reloadData];

  // Auto select first option in category if current selection is not in this category
  if (!self.selectedOption || self.selectedOption.category != category) {
    if (self.filteredOptions.count > 0) {
      [self selectOption:self.filteredOptions.firstObject];
    }
  } else {
    [self selectOption:self.selectedOption];
  }
}

- (void)updateIndicatorPositionAnimated:(BOOL)animated {
  if (self.categoryButtons.count == 0) return;
  UIButton* selBtn = self.categoryButtons[self.currentCategory];

  void (^action)(void) = ^{
    CGPoint center = [selBtn.superview convertPoint:selBtn.center toView:self.categoryBar];
    self.categoryIndicator.center = CGPointMake(center.x, self.categoryBar.bounds.size.height - 3);
  };

  if (animated) {
    [UIView animateWithDuration:0.25 animations:action];
  } else {
    action();
  }
}

- (void)selectOption:(BeautyOption*)option {
  self.selectedOption = option;

  _optionTitleLabel.text = option.name;
  _optionValueLabel.text = [NSString stringWithFormat:@"%ld%%", (long)option.progress];
  _intensitySlider.value = option.progress;

  // Category and index in filtered options
  NSInteger idx = [self.filteredOptions indexOfObject:option];
  if (idx != NSNotFound) {
    NSIndexPath* ip = [NSIndexPath indexPathForItem:idx inSection:0];
    [self.collectionView selectItemAtIndexPath:ip
                                      animated:YES
                                scrollPosition:UICollectionViewScrollPositionCenteredHorizontally];
  }

  if ([self.delegate respondsToSelector:@selector(beautyToolbarView:didSelectOption:)]) {
    [self.delegate beautyToolbarView:self didSelectOption:option];
  }
}

- (void)updateSliderValue:(NSInteger)progress {
  if (self.selectedOption) {
    self.selectedOption.progress = progress;
    _intensitySlider.value = progress;
    _optionValueLabel.text = [NSString stringWithFormat:@"%ld%%", (long)progress];
  }
}

- (void)resetAllToDefaults {
  for (BeautyOption* opt in self.allOptions) {
    opt.progress = opt.defaultProgress;
  }
  if (self.selectedOption) {
    [self updateSliderValue:self.selectedOption.defaultProgress];
  }
  [self.collectionView reloadData];
}

- (nullable BeautyOption*)optionWithId:(BeautyOptionId)optionId {
  for (BeautyOption* opt in self.allOptions) {
    if (opt.optionId == optionId) return opt;
  }
  return nil;
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView*)collectionView
     numberOfItemsInSection:(NSInteger)section {
  return self.filteredOptions.count;
}

- (__kindof UICollectionViewCell*)collectionView:(UICollectionView*)collectionView
                          cellForItemAtIndexPath:(NSIndexPath*)indexPath {
  ToobarCollectionViewCell* cell = [collectionView
      dequeueReusableCellWithReuseIdentifier:[ToobarCollectionViewCell reuseIdentifier]
                                forIndexPath:indexPath];

  BeautyOption* opt = self.filteredOptions[indexPath.item];
  BOOL isSelected = (self.selectedOption && self.selectedOption.optionId == opt.optionId);
  [cell configureWithTitle:opt.name iconName:opt.iconName isSelected:isSelected];

  return cell;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView*)collectionView
    didSelectItemAtIndexPath:(NSIndexPath*)indexPath {
  BeautyOption* opt = self.filteredOptions[indexPath.item];
  [self selectOption:opt];
}

@end
