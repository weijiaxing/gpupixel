//
//  FilterToolbarView.h
//  demo
//
//  Created by PixPark.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BeautyCategory) {
  BeautyCategorySkin = 0,        // 美肤
  BeautyCategoryShape = 1,       // 美型
  BeautyCategoryMakeup = 2,      // 美妆
  BeautyCategoryFilter = 3,      // 滤镜
  BeautyCategorySticker = 4,     // 贴纸
  BeautyCategoryAnimSticker = 5  // 动态贴纸
};

typedef NS_ENUM(NSInteger, BeautyOptionId) {
  // 美肤
  BeautyOptionSmooth = 1,
  BeautyOptionWhite = 2,
  BeautyOptionSharpen = 3,
  // 美型
  BeautyOptionThinFace = 4,
  BeautyOptionBigEye = 5,
  // 美妆
  BeautyOptionLipstick = 6,
  BeautyOptionBlusher = 7,
  // 滤镜
  BeautyOptionFilterOrigin = 10,
  BeautyOptionFilterPink = 11,
  BeautyOptionFilterCool = 12,
  BeautyOptionFilterFilm = 13,
  BeautyOptionFilterBW = 14,
  // 贴纸
  BeautyOptionStickerNone = 20,
  BeautyOptionStickerCatEars = 21,
  BeautyOptionStickerBunnyEars = 22,
  BeautyOptionStickerCrown = 23,
  BeautyOptionStickerAngelHalo = 24,
  BeautyOptionStickerDevilHorns = 25,
  BeautyOptionStickerSunglasses = 26,
  BeautyOptionStickerHeartBlush = 27,
  BeautyOptionStickerClownNose = 28,
  BeautyOptionStickerMustache = 29,
  BeautyOptionStickerFlowerHairpin = 30,
  // 动态贴纸
  BeautyOptionAnimNone = 40,
  BeautyOptionAnimHearts = 41,
  BeautyOptionAnimCatEars = 42,
  BeautyOptionAnimCrown = 43,
  BeautyOptionAnimHalo = 44,
  BeautyOptionAnimDevil = 45,
  BeautyOptionAnimFireworks = 46,
  BeautyOptionAnimTears = 47,
  BeautyOptionAnimSteam = 48,
  BeautyOptionAnimCoins = 49,
  BeautyOptionAnimDizzy = 50
};

@interface BeautyOption : NSObject

@property(nonatomic, assign) BeautyOptionId optionId;
@property(nonatomic, copy) NSString* name;
@property(nonatomic, copy) NSString* iconName;
@property(nonatomic, assign) BeautyCategory category;
@property(nonatomic, assign) NSInteger progress;  // 0 - 100
@property(nonatomic, assign) NSInteger defaultProgress;

+ (instancetype)optionWithId:(BeautyOptionId)optionId
                        name:(NSString*)name
                    iconName:(NSString*)iconName
                    category:(BeautyCategory)category
             defaultProgress:(NSInteger)defaultProgress;

@end

@class FilterToolbarView;

@protocol FilterToolbarViewDelegate <NSObject>

@optional
- (void)beautyToolbarView:(FilterToolbarView*)toolbarView
          didSelectOption:(BeautyOption*)option;

- (void)beautyToolbarView:(FilterToolbarView*)toolbarView
           didChangeValue:(NSInteger)value
                forOption:(BeautyOption*)option;

- (void)beautyToolbarViewDidRequestDismiss:(FilterToolbarView*)toolbarView;

// Compatibility method with legacy signature if needed
- (void)filterToolbarView:(FilterToolbarView*)toolbarView
    didSelectFilterAtIndex:(NSInteger)index;

@end

@interface FilterToolbarView : UIView

@property(nonatomic, weak) id<FilterToolbarViewDelegate> delegate;
@property(nonatomic, strong, readonly) NSArray<BeautyOption*>* allOptions;
@property(nonatomic, strong, readonly, nullable) BeautyOption* selectedOption;
@property(nonatomic, assign, readonly) BeautyCategory currentCategory;

- (instancetype)initWithFrame:(CGRect)frame;

// Compatibility initializer
- (instancetype)initWithFrame:(CGRect)frame
                 filterTitles:(nullable NSArray<NSString*>*)filterTitles;

- (void)selectOption:(BeautyOption*)option;
- (void)updateSliderValue:(NSInteger)progress;
- (void)resetAllToDefaults;
- (nullable BeautyOption*)optionWithId:(BeautyOptionId)optionId;

@end

NS_ASSUME_NONNULL_END
