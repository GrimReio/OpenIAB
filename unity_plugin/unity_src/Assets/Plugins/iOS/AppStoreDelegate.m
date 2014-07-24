#import "AppStoreDelegate.h"
#import <StoreKit/StoreKit.h>

// Helper method to create C string copy
// By default mono string marshaler creates .Net string for returned UTF-8 C string
// and calls free for returned value, thus returned strings should be allocated on heap
char* MakeStringCopy(const char* string)
{
	if (string == NULL)
		return NULL;
	
	char* res = (char*)malloc(strlen(string) + 1);
	strcpy(res, string);
	return res;
}

// Required by Unity
extern void UnitySendMessage(const char* objectName, const char* methodName, const char* param);

const char* EventHandler = "OpenIABEventManager";

@implementation AppStoreDelegate

// Internal

NSSet* m_skus;
NSMutableArray* m_skuMap;

- (void)storePurchase:(NSString *)sku
{
    NSUserDefaults *standardUserDefaults = [NSUserDefaults standardUserDefaults];
    if (standardUserDefaults)
    {
        [standardUserDefaults setBool:YES forKey:sku];
        [standardUserDefaults synchronize];
    }
    else
        NSLog(@"Couldn't access standardUserDefaults. Purchase wasn't stored.");
}


// General

+ (AppStoreDelegate*)instance
{
	static AppStoreDelegate* instance = nil;
	if (!instance)
		instance = [[AppStoreDelegate alloc] init];
    
    return instance;
}

- (id)init
{
    self = [super init];
    [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
    return self;
}

- (void)dealloc
{
    [m_skuMap release];
    [m_skus release];
    m_skus = nil;
    m_skuMap = nil;
    [super dealloc];
}


// Public

- (BOOL)canMakePayments
{
    return [SKPaymentQueue canMakePayments];
}

- (void)requestProducts:(NSSet*)skus
{
    m_skus = [skus retain];
    SKProductsRequest *request = [[SKProductsRequest alloc] initWithProductIdentifiers:skus];
	request.delegate = self;
	[request start];
}

- (void)startPurchase:(NSString*)sku
{
    SKMutablePayment *payment = [SKMutablePayment paymentWithProductIdentifier:sku];
    [[SKPaymentQueue defaultQueue] addPayment:payment];
}

- (void)queryInventory
{
    NSMutableDictionary* inventory = [[NSMutableDictionary alloc] init];
    NSMutableArray *purchaseMap = [[NSMutableArray alloc] init];
    NSUserDefaults* standardUserDefaults = [NSUserDefaults standardUserDefaults];
    if (!standardUserDefaults)
        NSLog(@"Couldn't access purchase storage. Purchase map won't be available.");
    else
        for (NSString* sku in m_skus)
            if ([standardUserDefaults boolForKey:sku])
            {
                // TODO: Probably store all purchase information. Not only sku
                // Setup purchase
                NSDictionary* purchase = [NSDictionary dictionaryWithObjectsAndKeys:
                                          @"product", @"itemType",
                                          @"", @"orderId",
                                          @"", @"packageName",
                                          sku, @"sku",
                                          [NSNumber numberWithLong:0], @"purchaseTime",
                                          // TODO: copy constants from Android if ever needed
                                          [NSNumber numberWithInt:0], @"purchaseState",
                                          @"", @"developerPayload",
                                          @"", @"token",
                                          @"", @"originalJson",
                                          @"", @"signature",
                                          @"", @"appstoreName",
                                          nil];
                
                NSArray* entry = [NSArray arrayWithObjects:sku, purchase, nil];
                [purchaseMap addObject:entry];
            }
    
    [inventory setObject:purchaseMap forKey:@"purchaseMap"];
    [inventory setObject:m_skuMap forKey:@"skuMap"];
    
    NSError* error = nil;
    NSData* jsonData = [NSJSONSerialization dataWithJSONObject:inventory options:kNilOptions error:&error];
    NSString* message = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
	UnitySendMessage(EventHandler, "OnQueryInventorySucceeded", MakeStringCopy([message UTF8String]));
}

- (void)restorePurchases
{
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}


// SKProductsRequestDelegate Protocol

- (void)productsRequest:(SKProductsRequest*)request didReceiveResponse:(SKProductsResponse*)response
{
    m_skuMap = [[NSMutableArray alloc] init];
    
    NSArray* skProducts = response.products;
    for (SKProduct * skProduct in skProducts)
    {
        // Format the price
        NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
        [numberFormatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
        [numberFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];
        [numberFormatter setLocale:skProduct.priceLocale];
        NSString *formattedPrice = [numberFormatter stringFromNumber:skProduct.price];
        
        NSLocale *priceLocale = skProduct.priceLocale;
        NSString *currencyCode = [priceLocale objectForKey:NSLocaleCurrencyCode];
        NSNumber *productPrice = skProduct.price;
        
        // Setup sku details
        NSDictionary* skuDetails = [NSDictionary dictionaryWithObjectsAndKeys:
                                    @"product", @"itemType",
                                    skProduct.productIdentifier, @"sku",
                                    @"product", @"type",
                                    formattedPrice, @"price",
                                    currencyCode, @"currencyCode",
                                    productPrice, @"priceValue",
                                    ([skProduct.localizedTitle length] == 0) ? @"" : skProduct.localizedTitle, @"title",
                                    ([skProduct.localizedDescription length] == 0) ? @"" : skProduct.localizedDescription, @"description",
                                    @"", @"json",
                                    nil];
        
        NSArray* entry = [NSArray arrayWithObjects:skProduct.productIdentifier, skuDetails, nil];
        [m_skuMap addObject:entry];
    }
    
    UnitySendMessage(EventHandler, "OnBillingSupported", MakeStringCopy(""));
}

- (void)request:(SKRequest*)request didFailWithError:(NSError*)error
{
    UnitySendMessage(EventHandler, "OnBillingNotSupported", MakeStringCopy([[error localizedDescription] UTF8String]));
}


// SKPaymentTransactionObserver Protocol

- (void)paymentQueue:(SKPaymentQueue *)queue updatedDownloads:(NSArray *)downloads
{
    // Required by protocol
}

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions
{
	for (SKPaymentTransaction *transaction in transactions)
	{
		switch (transaction.transactionState)
		{
			case SKPaymentTransactionStateFailed:
                if (transaction.error.code == SKErrorPaymentCancelled)
                    UnitySendMessage(EventHandler, "OnPurchaseFailed", MakeStringCopy("Transaction cancelled"));
                else
                    UnitySendMessage(EventHandler, "OnPurchaseFailed", MakeStringCopy([[transaction.error localizedDescription] UTF8String]));
				[[SKPaymentQueue defaultQueue] finishTransaction:transaction];
				break;
                
            case SKPaymentTransactionStateRestored:
                [self storePurchase:transaction.payment.productIdentifier];
                UnitySendMessage(EventHandler, "OnPurchaseRestored", MakeStringCopy([transaction.originalTransaction.payment.productIdentifier UTF8String]));
                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
				break;
                
			case SKPaymentTransactionStatePurchased:
                [self storePurchase:transaction.payment.productIdentifier];
                UnitySendMessage(EventHandler, "OnPurchaseSucceeded", MakeStringCopy([transaction.payment.productIdentifier UTF8String]));
                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                break;
		}
	}
}

- (void)paymentQueue:(SKPaymentQueue*)queue restoreCompletedTransactionsFailedWithError:(NSError*)error
{
	UnitySendMessage(EventHandler, "OnRestoreFailed", MakeStringCopy([[error localizedDescription] UTF8String]));
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue*)queue
{
	UnitySendMessage(EventHandler, "OnRestoreFinished", MakeStringCopy(""));
}

@end