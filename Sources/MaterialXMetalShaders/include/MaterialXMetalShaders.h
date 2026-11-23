#pragma once

#ifdef __OBJC__
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface NSBundle (MaterialXMetalShaders)
/// The bundle holding the [[stitchable]] node library (default.metallib).
+ (NSBundle *)materialXMetalShadersBundle;
@end
NS_ASSUME_NONNULL_END
#endif
