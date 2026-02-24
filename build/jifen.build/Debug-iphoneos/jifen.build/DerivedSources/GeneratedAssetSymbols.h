#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"com.bolo.jifen";

/// The "AccentColor" asset catalog color resource.
static NSString * const ACColorNameAccentColor AC_SWIFT_PRIVATE = @"AccentColor";

/// The "LaunchScreenBackground" asset catalog color resource.
static NSString * const ACColorNameLaunchScreenBackground AC_SWIFT_PRIVATE = @"LaunchScreenBackground";

/// The "LaunchScreenLogo" asset catalog image resource.
static NSString * const ACImageNameLaunchScreenLogo AC_SWIFT_PRIVATE = @"LaunchScreenLogo";

/// The "ShareCardAppIcon" asset catalog image resource.
static NSString * const ACImageNameShareCardAppIcon AC_SWIFT_PRIVATE = @"ShareCardAppIcon";

#undef AC_SWIFT_PRIVATE
