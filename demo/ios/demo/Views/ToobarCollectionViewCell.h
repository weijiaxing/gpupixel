//
//  ToobarCollectionViewCell.h
//  demo
//
//  Created by PixPark.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ToobarCollectionViewCell : UICollectionViewCell

@property(nonatomic, strong, readonly) UIView* circleContainer;
@property(nonatomic, strong, readonly) UIImageView* iconImageView;
@property(nonatomic, strong, readonly) UILabel* titleLabel;

+ (NSString*)reuseIdentifier;

- (void)configureWithTitle:(NSString*)title
                  iconName:(NSString*)iconName
                isSelected:(BOOL)isSelected;

@end

NS_ASSUME_NONNULL_END
