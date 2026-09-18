#import "IPAArchiveBrowserViewController.h"
#import "IPTheme.h"

@interface IPAArchiveBrowserViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *rootPath;
@property (nonatomic, copy) NSString *currentPath;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *items;
@end

@implementation IPAArchiveBrowserViewController

- (instancetype)initWithRootPath:(NSString *)rootPath {
    self = [super init];
    if (self) {
        _rootPath = [rootPath copy];
        _currentPath = [rootPath copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [IPTheme backgroundColor];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(doneTapped:)];
    self.navigationItem.leftBarButtonItem.tintColor = [IPTheme textPrimaryColor];
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 64;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"ArchiveCell"];
    [self.view addSubview:self.tableView];
    [self loadDirectory];
}

- (void)loadDirectory {
    self.title = self.currentPath.lastPathComponent.length > 0 ? self.currentPath.lastPathComponent : @"محتويات IPA";
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray<NSString *> *names = [fm contentsOfDirectoryAtPath:self.currentPath error:&error];
    if (error) names = @[];
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:names.count];
    for (NSString *name in names) {
        if ([name hasPrefix:@"."]) continue;
        NSString *path = [self.currentPath stringByAppendingPathComponent:name];
        BOOL directory = NO;
        [fm fileExistsAtPath:path isDirectory:&directory];
        NSDictionary *attributes = [fm attributesOfItemAtPath:path error:nil] ?: @{};
        [items addObject:@{ @"name": name, @"path": path, @"directory": @(directory), @"size": attributes[NSFileSize] ?: @0 }];
    }
    [items sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        BOOL aDir = [a[@"directory"] boolValue], bDir = [b[@"directory"] boolValue];
        if (aDir != bDir) return aDir ? NSOrderedAscending : NSOrderedDescending;
        return [a[@"name"] compare:b[@"name"] options:NSCaseInsensitiveSearch];
    }];
    self.items = items;
    [self installApplicationSummaryHeaderIfNeeded];
    [self.tableView reloadData];
}

- (void)installApplicationSummaryHeaderIfNeeded {
    NSString *payload = [self.rootPath stringByAppendingPathComponent:@"Payload"];
    NSArray<NSString *> *payloadItems = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:payload error:nil];
    NSString *appPath = nil;
    for (NSString *name in payloadItems) {
        if (name.pathExtension.lowercaseString.length > 0 && [name.pathExtension.lowercaseString isEqualToString:@"app"]) {
            appPath = [payload stringByAppendingPathComponent:name];
            break;
        }
    }
    if (!appPath) return;
    NSString *plistPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    if (![plist isKindOfClass:NSDictionary.class]) return;
    NSString *bundleID = [plist[@"CFBundleIdentifier"] isKindOfClass:NSString.class] ? plist[@"CFBundleIdentifier"] : @"غير معروف";
    NSString *version = [plist[@"CFBundleShortVersionString"] isKindOfClass:NSString.class] ? plist[@"CFBundleShortVersionString"] : @"غير معروف";
    NSString *executable = [plist[@"CFBundleExecutable"] isKindOfClass:NSString.class] ? plist[@"CFBundleExecutable"] : @"غير معروف";
    unsigned long long size = 0;
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:appPath];
    NSString *relative;
    while ((relative = [enumerator nextObject])) {
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:[appPath stringByAppendingPathComponent:relative] error:nil];
        size += [attrs[NSFileSize] unsignedLongLongValue];
    }
    UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 92)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    header.backgroundColor = [IPTheme cardColor]; header.layer.cornerRadius = 16; header.layer.masksToBounds = YES;
    header.textColor = UIColor.whiteColor;
    header.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    header.numberOfLines = 0;
    header.textAlignment = NSTextAlignmentNatural;
    header.text = [NSString stringWithFormat:@"  Bundle ID: %@\n  Version: %@\n  Executable: %@\n  App Size: %@", bundleID, version, executable, [self formattedSize:size]];
    self.tableView.tableHeaderView = header;
}

- (NSString *)formattedSize:(unsigned long long)bytes {
    if (bytes < 1024) return [NSString stringWithFormat:@"%llu B", bytes];
    if (bytes < 1024ULL * 1024ULL) return [NSString stringWithFormat:@"%.1f KB", bytes / 1024.0];
    if (bytes < 1024ULL * 1024ULL * 1024ULL) return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024.0)];
    return [NSString stringWithFormat:@"%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0)];
}

- (void)doneTapped:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)isTextFile:(NSString *)path {
    NSString *extension = path.pathExtension.lowercaseString;
    return [@[@"plist", @"xml", @"json", @"txt", @"strings", @"md", @"log", @"entitlements"] containsObject:extension];
}

- (void)showTextFile:(NSString *)path title:(NSString *)title {
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    NSString *text = data.length > 0 ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    if (text.length == 0) {
        [self showMessage:@"تعذر عرض هذا الملف كنص."];
        return;
    }
    UIViewController *viewer = [[UIViewController alloc] init];
    viewer.view.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];
    viewer.title = title;
    UITextView *textView = [[UITextView alloc] initWithFrame:viewer.view.bounds];
    textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    textView.backgroundColor = UIColor.clearColor;
    textView.textColor = [IPTheme mutedTextColor];
    textView.font = [UIFont fontWithName:@"Menlo" size:12] ?: [UIFont systemFontOfSize:12];
    textView.editable = NO;
    textView.text = text;
    [viewer.view addSubview:textView];
    [self.navigationController pushViewController:viewer animated:YES];
}

- (void)showMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"المجلد" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"حسنًا" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.items.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ArchiveCell" forIndexPath:indexPath];
    NSDictionary *item = self.items[indexPath.row];
    BOOL directory = [item[@"directory"] boolValue];
    cell.textLabel.text = item[@"name"];
    cell.textLabel.textColor = UIColor.whiteColor;
    cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    cell.detailTextLabel.text = directory ? @"مجلد" : [NSString stringWithFormat:@"%@ بايت", item[@"size"]];
    cell.imageView.image = [[UIImage systemImageNamed:directory ? @"folder.fill" : @"doc"] imageWithTintColor:directory ? [UIColor colorWithRed:0.4 green:0.5 blue:0.9 alpha:1.0] : [UIColor colorWithWhite:0.55 alpha:1.0]];
    cell.accessoryType = directory ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = self.items[indexPath.row];
    NSString *path = item[@"path"];
    if ([item[@"directory"] boolValue]) {
        IPAArchiveBrowserViewController *next = [[IPAArchiveBrowserViewController alloc] initWithRootPath:path];
        [self.navigationController pushViewController:next animated:YES];
    } else if ([self isTextFile:path]) {
        [self showTextFile:path title:item[@"name"]];
    } else {
        [self showMessage:@"هذا الملف موجود داخل الناتج، لكن عرضه المباشر غير متاح لهذا النوع."];
    }
}

@end
