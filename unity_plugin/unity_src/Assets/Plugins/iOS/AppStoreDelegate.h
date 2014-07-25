#import <StoreKit/StoreKit.h>
#import <Foundation/Foundation.h>

@interface AppStoreDelegate : NSObject <SKPaymentTransactionObserver, SKProductsRequestDelegate>

/**
 * Get instance of the StoreKit delegate
 */
+ (AppStoreDelegate*)instance;

/**
 * Request sku listing from the AppStore
 */
- (void)requestSKUs:(NSSet*)skus;

/**
 * Start async purchase process
 */
- (void)startPurchase:(NSString*)sku;

/**
 * Request purchase history
 */
- (void)queryInventory;

/**
 * This is required by AppStore. 
 * Separate button for restoration should be added somewhere in the application
 */
- (void)restorePurchases;

@end
