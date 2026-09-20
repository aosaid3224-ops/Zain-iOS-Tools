#import <UIKit/UIKit.h>
#import "../Core/IPAExtractor.h"

@interface MainViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<IPAExtractedInfo *> *ipaFiles;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *ipaMetadataCache;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *ipaIconCache;
@property (nonatomic, strong) dispatch_queue_t ipaCacheQueue;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIView *dashboardView;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, assign) NSUInteger ipaLoadGeneration;
@end
