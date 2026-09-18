//
//  InstallationProgressViewController.m
//  IPAInstallerPro
//
//  v2.2.0 — Event-Driven Live Installation UI + Raw Log Diagnostics
//

#import "InstallationProgressViewController.h"
#import "InstallationEngine.h"
#import "JailbreakEnvironment.h"
#import "OperationLog.h"
#import "LiveOperationStream.h"
#import "IPTheme.h"
#import <objc/runtime.h>

#pragma mark - Phase Visual State

typedef NS_ENUM(NSInteger, PhaseVisualState) {
    PhaseVisualStatePending = 0,
    PhaseVisualStateActive  = 1,
    PhaseVisualStateSuccess = 2,
    PhaseVisualStateFailed  = 3
};

#pragma mark - InstallPhaseView

@interface InstallPhaseView : UIView
@property (nonatomic, strong) UILabel *iconLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIView  *pulsingDot;
@property (nonatomic, assign) PhaseVisualState phaseState;
- (void)setState:(PhaseVisualState)state animated:(BOOL)animated;


@end

@implementation InstallPhaseView

- (instancetype)initWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _iconLabel = [[UILabel alloc] init];
        _iconLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _iconLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightMedium];
        _iconLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_iconLabel];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        _titleLabel.textColor = [IPTheme textPrimaryColor];
        _titleLabel.text = title;
        [self addSubview:_titleLabel];

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        _subtitleLabel.textColor = [IPTheme textSecondaryColor];
        _subtitleLabel.text = subtitle;
        [self addSubview:_subtitleLabel];

        _pulsingDot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 6, 6)];
        _pulsingDot.translatesAutoresizingMaskIntoConstraints = NO;
        _pulsingDot.layer.cornerRadius = 3;
        _pulsingDot.backgroundColor = [IPTheme accentColor];
        _pulsingDot.hidden = YES;
        [self addSubview:_pulsingDot];

        [NSLayoutConstraint activateConstraints:@[
            [_iconLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
            [_iconLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_iconLabel.widthAnchor constraintEqualToConstant:28],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconLabel.trailingAnchor constant:12],
            [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-16],

            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2],
            [_subtitleLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10],
            [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-16],

            [_pulsingDot.leadingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor constant:8],
            [_pulsingDot.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
            [_pulsingDot.widthAnchor constraintEqualToConstant:6],
            [_pulsingDot.heightAnchor constraintEqualToConstant:6],

            [self.heightAnchor constraintGreaterThanOrEqualToConstant:48]
        ]];

        self.phaseState = PhaseVisualStatePending;
        [self updateAppearanceAnimated:NO];
    }
    return self;
}

- (void)setState:(PhaseVisualState)state animated:(BOOL)animated {
    if (_phaseState == state) return;
    _phaseState = state;
    [self updateAppearanceAnimated:animated];
}

- (void)updateAppearanceAnimated:(BOOL)animated {
    void (^updates)(void) = ^{
        switch (self.phaseState) {
            case PhaseVisualStatePending:
                self.iconLabel.text = @"\u25cb";
                self.iconLabel.textColor = [IPTheme textTertiaryColor];
                self.titleLabel.textColor = [IPTheme textSecondaryColor];
                self.subtitleLabel.textColor = [IPTheme textTertiaryColor];
                self.pulsingDot.hidden = YES;
                break;
            case PhaseVisualStateActive:
                self.iconLabel.text = @"\u25c9";
                self.iconLabel.textColor = [IPTheme accentColor];
                self.titleLabel.textColor = [IPTheme textPrimaryColor];
                self.subtitleLabel.textColor = [IPTheme textSecondaryColor];
                self.pulsingDot.hidden = NO;
                break;
            case PhaseVisualStateSuccess:
                self.iconLabel.text = @"\u2713";
                self.iconLabel.textColor = [IPTheme successColor];
                self.titleLabel.textColor = [IPTheme textPrimaryColor];
                self.subtitleLabel.textColor = [IPTheme textSecondaryColor];
                self.pulsingDot.hidden = YES;
                break;
            case PhaseVisualStateFailed:
                self.iconLabel.text = @"\u2717";
                self.iconLabel.textColor = [UIColor colorWithRed:0.9 green:0.3 blue:0.3 alpha:1.0];
                self.titleLabel.textColor = [UIColor colorWithRed:0.9 green:0.3 blue:0.3 alpha:1.0];
                self.subtitleLabel.textColor = [UIColor colorWithRed:0.7 green:0.3 blue:0.3 alpha:1.0];
                self.pulsingDot.hidden = YES;
                break;
        }
    };

    if (animated) {
        [UIView animateWithDuration:0.35 animations:updates];
    } else {
        updates();
    }

    if (self.phaseState == PhaseVisualStateActive) {
        [self startPulsing];
    } else {
        [self stopPulsing];
    }
}

- (void)startPulsing {
    self.pulsingDot.alpha = 1.0;
    [UIView animateWithDuration:0.8
                          delay:0
                        options:UIViewAnimationOptionAutoreverse | UIViewAnimationOptionRepeat | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
                         self.pulsingDot.alpha = 0.2;
                     }
                     completion:nil];
}

- (void)stopPulsing {
    [self.pulsingDot.layer removeAllAnimations];
    self.pulsingDot.alpha = 1.0;
}



@end

#pragma mark - ViewController

@interface InstallationProgressViewController ()
@property (nonatomic, strong) NSString *installedBundleID;
@property (nonatomic, strong) NSString *currentTxnID;
@property (nonatomic, assign) BOOL isDone;

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UILabel *headerLabel;
@property (nonatomic, strong) UILabel *appNameLabel;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UIStackView *phasesStack;
@property (nonatomic, strong) NSMutableArray<InstallPhaseView *> *phaseViews;
@property (nonatomic, strong) UIView *reportCard;
@property (nonatomic, strong) NSDate *installStartTime;
@property (nonatomic, assign) NSInteger currentPhaseIndex;
@property (nonatomic, assign) BOOL hasFailed;

// Raw log diagnostics
@property (nonatomic, strong) NSMutableString *rawLog;
@property (nonatomic, strong) UIButton *showLogButton;
@property (nonatomic, strong) UITextView *logTextView;
@property (nonatomic, strong) UIView *logContainer;
@property (nonatomic, strong) NSString *lastFailureMessage;

// Passive forensic stream: observes the same transaction without starting a
// second install, signing pass, or registration pass.
@property (nonatomic, strong) LiveOperationStream *liveStream;
@property (nonatomic, assign) NSUInteger lastRenderedLiveSequence;
@property (nonatomic, strong) UIView *liveOutputCard;
@property (nonatomic, strong) UILabel *liveStateLabel;
@property (nonatomic, strong) UITextView *liveOutputView;
@property (nonatomic, strong) NSMutableArray<LiveOperationEvent *> *pendingLiveCriticalEvents;
@property (nonatomic, strong) LiveOperationEvent *pendingLiveNormalLast;
@property (nonatomic, assign) NSUInteger pendingLiveNormalCount;
@property (nonatomic, assign) NSUInteger pendingLiveNormalFirstSequence;
@property (nonatomic, assign) BOOL liveRenderDrainScheduled;
@property (nonatomic, assign) NSUInteger liveRenderGeneration;
@property (nonatomic, assign) BOOL liveFinalRendered;
@property (nonatomic, strong) dispatch_queue_t liveRenderQueue;
@property (nonatomic, assign) NSUInteger lateLiveEventCount;

@end

@implementation InstallationProgressViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [IPTheme backgroundColor];
    self.title = @"\u062a\u062b\u0628\u064a\u062a \u0627\u0644\u062a\u0637\u0628\u064a\u0642";
    _rawLog = [NSMutableString string];
    _pendingLiveCriticalEvents = [NSMutableArray array];
    _liveRenderQueue = dispatch_queue_create("com.aosaid.ipainstallerpro.live-render", DISPATCH_QUEUE_SERIAL);
    [self setupUI];
    [self registerForOperationLogNotifications];
    [self startInstallation];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.liveStream close];
}

#pragma mark - Raw Log

- (void)appendLog:(NSString *)text {
    if (!text) return;
    [self.rawLog appendString:text];
    [self.rawLog appendString:@"\n"];
}

- (void)showRawLog {
    if (!self.logContainer) {
        self.logContainer = [[UIView alloc] init];
        self.logContainer.translatesAutoresizingMaskIntoConstraints = NO;
        self.logContainer.backgroundColor = [IPTheme cardColor]; self.logContainer.layer.borderWidth = 0.7; self.logContainer.layer.borderColor = [IPTheme subtleBorderColor].CGColor;
        self.logContainer.layer.cornerRadius = 18;
        [self.view addSubview:self.logContainer];

        UILabel *logTitle = [[UILabel alloc] init];
        logTitle.translatesAutoresizingMaskIntoConstraints = NO;
        logTitle.text = @"\u0627\u0644\u0644\u0648\u063a \u0627\u0644\u062e\u0627\u0645 (Raw Log)";
        logTitle.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
        logTitle.textColor = [IPTheme textPrimaryColor];
        [self.logContainer addSubview:logTitle];

        UIButton *copyLogBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        copyLogBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [copyLogBtn setTitle:@"نسخ الكل" forState:UIControlStateNormal];
        [copyLogBtn setTitleColor:[UIColor colorWithRed:0.35 green:0.75 blue:1.0 alpha:1.0] forState:UIControlStateNormal];
        copyLogBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        [copyLogBtn addTarget:self action:@selector(copyRawLog:) forControlEvents:UIControlEventTouchUpInside];
        [self.logContainer addSubview:copyLogBtn];

        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [closeBtn setTitle:@"\u0625\u063a\u0644\u0627\u0642" forState:UIControlStateNormal];
        [closeBtn setTitleColor:[UIColor colorWithRed:0.9 green:0.3 blue:0.3 alpha:1.0] forState:UIControlStateNormal];
        [closeBtn addTarget:self action:@selector(hideRawLog) forControlEvents:UIControlEventTouchUpInside];
        [self.logContainer addSubview:closeBtn];

        self.logTextView = [[UITextView alloc] init];
        self.logTextView.translatesAutoresizingMaskIntoConstraints = NO;
        self.logTextView.backgroundColor = [IPTheme secondaryCardColor];
        self.logTextView.textColor = [IPTheme successColor];
        self.logTextView.font = [UIFont fontWithName:@"Courier" size:10] ?: [UIFont systemFontOfSize:10];
        self.logTextView.editable = NO;
        self.logTextView.selectable = YES;
        self.logTextView.layer.cornerRadius = 8;
        [self.logContainer addSubview:self.logTextView];

        [NSLayoutConstraint activateConstraints:@[
            [self.logContainer.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:20],
            [self.logContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
            [self.logContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
            [self.logContainer.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20],

            [logTitle.topAnchor constraintEqualToAnchor:self.logContainer.topAnchor constant:12],
            [logTitle.leadingAnchor constraintEqualToAnchor:self.logContainer.leadingAnchor constant:16],

            [copyLogBtn.centerYAnchor constraintEqualToAnchor:logTitle.centerYAnchor],
            [copyLogBtn.trailingAnchor constraintEqualToAnchor:closeBtn.leadingAnchor constant:-12],
            [closeBtn.centerYAnchor constraintEqualToAnchor:logTitle.centerYAnchor],
            [closeBtn.trailingAnchor constraintEqualToAnchor:self.logContainer.trailingAnchor constant:-16],

            [self.logTextView.topAnchor constraintEqualToAnchor:logTitle.bottomAnchor constant:8],
            [self.logTextView.leadingAnchor constraintEqualToAnchor:self.logContainer.leadingAnchor constant:8],
            [self.logTextView.trailingAnchor constraintEqualToAnchor:self.logContainer.trailingAnchor constant:-8],
            [self.logTextView.bottomAnchor constraintEqualToAnchor:self.logContainer.bottomAnchor constant:-8]
        ]];
    }

    self.logTextView.attributedText = [self coloredLogFromString:self.rawLog];
    self.logContainer.hidden = NO;
    self.logContainer.alpha = 0;
    [UIView animateWithDuration:0.3 animations:^{
        self.logContainer.alpha = 1;
    }];
}

- (void)copyRawLog:(UIButton *)sender {
    NSString *text = self.rawLog.length ? self.rawLog.copy : (self.lastFailureMessage ?: @"");
    if (!text.length) return;
    [UIPasteboard generalPasteboard].string = text;
    [sender setTitle:@"تم النسخ ✓" forState:UIControlStateNormal];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [sender setTitle:@"نسخ الكل" forState:UIControlStateNormal];
    });
}

- (void)copyFailureDetails:(UIButton *)sender {
    NSString *text = self.lastFailureMessage.length ? self.lastFailureMessage : self.rawLog;
    if (!text.length) return;
    [UIPasteboard generalPasteboard].string = text;
    [sender setTitle:@"تم نسخ التفاصيل ✓" forState:UIControlStateNormal];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [sender setTitle:@"نسخ تفاصيل الخطأ" forState:UIControlStateNormal];
    });
}

- (void)hideRawLog {
    [UIView animateWithDuration:0.3 animations:^{
        self.logContainer.alpha = 0;
    } completion:^(BOOL finished) {
        self.logContainer.hidden = YES;
    }];
}

#pragma mark - OperationLog Notifications

- (void)registerForOperationLogNotifications {
    // LiveOperationStream is the only live source for this screen. The old
    // OperationRecord notifications remain available to other screens, but
    // are intentionally not subscribed here to prevent a second UI backlog.
}

- (NSInteger)uiPhaseIndexForOperationPhase:(OperationPhase)opPhase {
    switch (opPhase) {
        case OperationPhaseIPAOpen:      return 0;
        case OperationPhaseIPAExtract:
        case OperationPhaseAppIdentify:  return 1;
        case OperationPhaseFileCopy:
        case OperationPhaseFramework:
        case OperationPhaseDylib:
        case OperationPhaseSign:
        case OperationPhasePermission:   return 2;
        case OperationPhaseUICache:      return 3;
        case OperationPhaseVerify:
        case OperationPhaseComplete:     return 4;
        default: return -1;
    }
}

- (void)operationRecordAdded:(NSNotification *)note {
    if (self.isDone) return;
    OperationRecord *record = note.object;
    if (!record || ![record.transactionID isEqualToString:self.currentTxnID]) return;

    [self appendLog:[NSString stringWithFormat:@"[BEGIN] %@ | %@ | target:%@ | input:%@",
                     record.recordID, record.operation, record.target, record.input ?: @"-"]];

    NSInteger uiPhase = [self uiPhaseIndexForOperationPhase:record.phase];
    if (uiPhase < 0) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        for (NSInteger i = 0; i < uiPhase; i++) {
            if (self.phaseViews[i].phaseState == PhaseVisualStatePending) {
                [self.phaseViews[i] setState:PhaseVisualStateSuccess animated:YES];
            }
        }
        [self.phaseViews[uiPhase] setState:PhaseVisualStateActive animated:YES];
        self.currentPhaseIndex = uiPhase;
        float progress = (float)(uiPhase + 1) / (float)self.phaseViews.count;
        [self.progressView setProgress:progress animated:YES];
    });
}

- (BOOL)isCriticalLiveEvent:(LiveOperationEvent *)event {
    if (event.finalEvent) return YES;
    NSString *stage = event.stage.uppercaseString ?: @"";
    NSString *status = event.status.uppercaseString ?: @"";
    NSSet *criticalStages = [NSSet setWithArray:@[@"START", @"IPA_OPEN", @"IPA_EXTRACT", @"APP_IDENTIFY", @"FILE_COPY", @"UICACHE", @"VERIFY", @"LAUNCH", @"RUNTIME_MONITOR", @"CRASH_DIAGNOSTICS", @"COMPLETE"]];
    // SIGN/FRAMEWORK/DYLIB/PERMISSION/CLEANUP can generate hundreds of
    // records. Their full history stays in OperationLog; the UI keeps the
    // latest normal event and a count, while failures always bypass coalescing.
    return [criticalStages containsObject:stage] || [status isEqualToString:@"FAILED"] ||
           ([status isEqualToString:@"SUCCESS"] && ![stage isEqualToString:@"SIGN"] && ![stage isEqualToString:@"FRAMEWORK"] && ![stage isEqualToString:@"DYLIB"] && ![stage isEqualToString:@"PERMISSION"] && ![stage isEqualToString:@"CLEANUP"]);
}

- (void)renderLiveOperationEvent:(LiveOperationEvent *)event {
    if (!event || ![event.transactionID isEqualToString:self.currentTxnID]) return;
    dispatch_async(self.liveRenderQueue, ^{
        if (self.liveFinalRendered) {
            self.lateLiveEventCount += 1;
            return;
        }
        if (event.finalEvent) {
            // The final line has priority over any presentation backlog. The
            // complete OperationLog remains untouched; only UI pending items
            // are discarded here.
            [self.pendingLiveCriticalEvents removeAllObjects];
            self.pendingLiveNormalLast = nil;
            self.pendingLiveNormalCount = 0;
            self.pendingLiveNormalFirstSequence = 0;
            [self.pendingLiveCriticalEvents addObject:event];
        } else if ([self isCriticalLiveEvent:event]) {
            [self.pendingLiveCriticalEvents addObject:event];
        } else {
            if (self.pendingLiveNormalCount == 0) self.pendingLiveNormalFirstSequence = event.sequence;
            self.pendingLiveNormalCount += 1;
            self.pendingLiveNormalLast = event;
        }
        if (!self.liveRenderDrainScheduled) {
            self.liveRenderDrainScheduled = YES;
            dispatch_async(dispatch_get_main_queue(), ^{ [self drainLiveOperationEvents]; });
        }
    });
}

- (void)appendRenderedLiveLineForEvent:(LiveOperationEvent *)event note:(NSString *)note {
    if (!event || !self.liveOutputView) return;
    event.renderedAt = [NSDate date];
    event.renderLagMs = [event.renderedAt timeIntervalSinceDate:event.timestamp] * 1000.0;
    NSString *created = [NSString stringWithFormat:@"%.3f", [event.timestamp timeIntervalSince1970]];
    NSString *rendered = [NSString stringWithFormat:@"%.3f", [event.renderedAt timeIntervalSince1970]];
    NSString *line = [NSString stringWithFormat:@"%@ #%03lu %@ %@ | %@ | created:%@ rendered:%@ lag:%.1fms | target:%@ | exit:%d%@\n",
                       rendered, (unsigned long)event.sequence, event.stage ?: @"UNKNOWN", event.status ?: @"PENDING",
                       event.message ?: @"", created, rendered, event.renderLagMs, event.target.length ? event.target : @"-", event.exitStatus, note ?: @""];
    UIColor *color = [event.status isEqualToString:@"FAILED"] ? [IPTheme errorColor] :
                     ([event.status isEqualToString:@"SUCCESS"] ? [UIColor colorWithRed:0.35 green:0.95 blue:0.6 alpha:1.0] : [UIColor colorWithRed:0.45 green:0.78 blue:1.0 alpha:1.0]);
    NSDictionary *attributes = @{NSFontAttributeName: self.liveOutputView.font ?: [UIFont systemFontOfSize:10], NSForegroundColorAttributeName: color};
    [self.liveOutputView.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:line attributes:attributes]];
    NSUInteger maxLength = 120000;
    if (self.liveOutputView.textStorage.length > maxLength) [self.liveOutputView.textStorage deleteCharactersInRange:NSMakeRange(0, self.liveOutputView.textStorage.length - maxLength)];
    [self.liveOutputView scrollRangeToVisible:NSMakeRange(self.liveOutputView.textStorage.length, 0)];
}

- (void)drainLiveOperationEvents {
    if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ [self drainLiveOperationEvents]; }); return; }
    __block NSArray<LiveOperationEvent *> *critical = nil;
    __block LiveOperationEvent *normalLast = nil;
    __block NSUInteger normalCount = 0;
    dispatch_sync(self.liveRenderQueue, ^{
        critical = [self.pendingLiveCriticalEvents copy];
        normalLast = self.pendingLiveNormalLast;
        normalCount = self.pendingLiveNormalCount;
        [self.pendingLiveCriticalEvents removeAllObjects];
        self.pendingLiveNormalLast = nil;
        self.pendingLiveNormalCount = 0;
        self.pendingLiveNormalFirstSequence = 0;
        self.liveRenderDrainScheduled = NO;
    });
    for (LiveOperationEvent *event in critical) {
        if (self.liveFinalRendered) { self.lateLiveEventCount += 1; continue; }
        [self appendRenderedLiveLineForEvent:event note:nil];
        self.lastRenderedLiveSequence = event.sequence;
        UIColor *color = [event.status isEqualToString:@"FAILED"] ? [IPTheme errorColor] : [IPTheme successColor];
        self.liveStateLabel.textColor = color;
        self.liveStateLabel.text = event.finalEvent ? [NSString stringWithFormat:@"الحالة النهائية: %@ #%03lu — انتهى البث", event.status ?: @"FINAL", (unsigned long)event.sequence] : [NSString stringWithFormat:@"الحالة الحية: %@ — %@ #%03lu", event.stage ?: @"UNKNOWN", event.status ?: @"PENDING", (unsigned long)event.sequence];
        if (event.finalEvent) self.liveFinalRendered = YES;
    }
    if (!self.liveFinalRendered && normalCount > 0 && normalLast) {
        NSString *note = [NSString stringWithFormat:@" (تم تجميع %lu حدث عرض عادي)", (unsigned long)normalCount];
        [self appendRenderedLiveLineForEvent:normalLast note:note];
        self.lastRenderedLiveSequence = normalLast.sequence;
        self.liveStateLabel.text = [NSString stringWithFormat:@"الحالة الحية: %@ — %@ #%03lu", normalLast.stage ?: @"UNKNOWN", normalLast.status ?: @"PENDING", (unsigned long)normalLast.sequence];
    }
}

- (void)operationRecordUpdated:(NSNotification *)note {
    if (self.isDone) return;
    OperationRecord *record = note.object;
    if (!record || ![record.transactionID isEqualToString:self.currentTxnID]) return;

    NSString *logLine = [NSString stringWithFormat:@"[END] %@ | result:%d | exit:%d | verified:%@ | out:%@ | err:%@",
                         record.recordID,
                         (int)record.result,
                         record.exitCode,
                         record.verified ? @"YES" : @"NO",
                         record.rawOutput.length > 0 ? @"(see below)" : @"-",
                         record.rawError ?: @"-"];
    [self appendLog:logLine];

    // Show diagnostics report / rawOutput clearly in raw log
    if (record.rawOutput.length > 0) {
        [self appendLog:@"═══════════════════════════════════════════════════════════════"];
        [self appendLog:record.rawOutput];
        [self appendLog:@"═══════════════════════════════════════════════════════════════"];
    }
    if (record.context.count > 0) {
        NSArray *keys = [[record.context allKeys] sortedArrayUsingSelector:@selector(compare:)];
        NSMutableString *contextText = [NSMutableString stringWithString:@"[CONTEXT]"];
        for (NSString *key in keys) {
            [contextText appendFormat:@" %@=%@;", key, record.context[key]];
        }
        [self appendLog:contextText];
    }

    NSInteger uiPhase = [self uiPhaseIndexForOperationPhase:record.phase];
    if (uiPhase < 0) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (record.result == OperationResultSuccess ||
            record.result == OperationResultPartial ||
            record.result == OperationResultSkipped) {
            [self.phaseViews[uiPhase] setState:PhaseVisualStateSuccess animated:YES];
        } else if (record.result == OperationResultFailed) {
            [self.phaseViews[uiPhase] setState:PhaseVisualStateFailed animated:YES];
            self.hasFailed = YES;
        }
    });
}

#pragma mark - UI Setup

- (void)setupUI {
    _scrollView = [[UIScrollView alloc] init];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_scrollView];

    _containerView = [[UIView alloc] init];
    _containerView.translatesAutoresizingMaskIntoConstraints = NO;
    [_scrollView addSubview:_containerView];

    _headerLabel = [[UILabel alloc] init];
    _headerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _headerLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    _headerLabel.textColor = [IPTheme textPrimaryColor];
    _headerLabel.textAlignment = NSTextAlignmentCenter;
    _headerLabel.text = @"\u062c\u0627\u0631\u064d \u0627\u0644\u062a\u062b\u0628\u064a\u062a...";
    [_containerView addSubview:_headerLabel];

    _appNameLabel = [[UILabel alloc] init];
    _appNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _appNameLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _appNameLabel.textColor = [IPTheme textSecondaryColor];
    _appNameLabel.textAlignment = NSTextAlignmentCenter;
    _appNameLabel.text = [self.ipaPath lastPathComponent] ?: @"";
    [_containerView addSubview:_appNameLabel];

    _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _progressView.translatesAutoresizingMaskIntoConstraints = NO;
    _progressView.progressTintColor = [IPTheme accentColor];
    _progressView.trackTintColor = [IPTheme textPrimaryColor];
    _progressView.layer.cornerRadius = 2;
    _progressView.clipsToBounds = YES;
    [_containerView addSubview:_progressView];

    _liveOutputCard = [[UIView alloc] init];
    _liveOutputCard.translatesAutoresizingMaskIntoConstraints = NO;
    _liveOutputCard.backgroundColor = [IPTheme cardColor];
    _liveOutputCard.layer.cornerRadius = 12;
    _liveOutputCard.layer.borderWidth = 0.7; _liveOutputCard.layer.borderColor = [IPTheme subtleBorderColor].CGColor;

    [_containerView addSubview:_liveOutputCard];

    UILabel *liveTitle = [[UILabel alloc] init];
    liveTitle.translatesAutoresizingMaskIntoConstraints = NO;
    liveTitle.text = @"الإخراج الحي للعملية";
    liveTitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    liveTitle.textColor = [IPTheme textSecondaryColor];
    [_liveOutputCard addSubview:liveTitle];

    _liveStateLabel = [[UILabel alloc] init];
    _liveStateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _liveStateLabel.text = @"الحالة الحية: بانتظار البدء";
    _liveStateLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    _liveStateLabel.textColor = [IPTheme textSecondaryColor];
    _liveStateLabel.numberOfLines = 2;
    [_liveOutputCard addSubview:_liveStateLabel];

    _liveOutputView = [[UITextView alloc] init];
    _liveOutputView.translatesAutoresizingMaskIntoConstraints = NO;
    _liveOutputView.backgroundColor = [IPTheme secondaryCardColor];
    _liveOutputView.textColor = [UIColor colorWithRed:0.45 green:0.95 blue:0.6 alpha:1.0];
    _liveOutputView.font = [UIFont fontWithName:@"Menlo" size:10] ?: [UIFont systemFontOfSize:10];
    _liveOutputView.editable = NO;
    _liveOutputView.selectable = YES;
    _liveOutputView.text = @"لا توجد أحداث بعد...";
    _liveOutputView.layer.cornerRadius = 8;
    [_liveOutputCard addSubview:_liveOutputView];

    _phasesStack = [[UIStackView alloc] init];
    _phasesStack.translatesAutoresizingMaskIntoConstraints = NO;
    _phasesStack.axis = UILayoutConstraintAxisVertical;
    _phasesStack.spacing = 2;
    [_containerView addSubview:_phasesStack];

    _phaseViews = [NSMutableArray array];
    NSArray *phases = @[
        @[@"\u0627\u0644\u062a\u062d\u0642\u0642 \u0645\u0646 \u0645\u0644\u0641 IPA",       @"\u062c\u0627\u0631\u064d \u0627\u0644\u062a\u062d\u0642\u0642 \u0645\u0646 \u0633\u0644\u0627\u0645\u0629 \u0627\u0644\u0645\u0644\u0641..."],
        @[@"\u0627\u0633\u062a\u062e\u0631\u0627\u062c \u0627\u0644\u062a\u0637\u0628\u064a\u0642",        @"\u062c\u0627\u0631\u064d \u0641\u0643 \u0636\u063a\u0637 \u0627\u0644\u0645\u062d\u062a\u0648\u064a\u0627\u062a..."],
        @[@"\u062a\u062b\u0628\u064a\u062a \u0627\u0644\u0645\u0644\u0641\u0627\u062a",          @"\u062c\u0627\u0631\u064d \u0627\u0644\u0646\u0633\u062e \u0648\u0627\u0644\u062a\u0648\u0642\u064a\u0639..."],
        @[@"\u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062a\u0637\u0628\u064a\u0642",          @"\u062c\u0627\u0631\u064d \u0627\u0644\u062a\u0633\u062c\u064a\u0644 \u0641\u064a \u0627\u0644\u0646\u0638\u0627\u0645..."],
        @[@"\u0627\u0644\u062a\u062d\u0642\u0642 \u0627\u0644\u0646\u0647\u0627\u0626\u064a",         @"\u062c\u0627\u0631\u064d \u0627\u0644\u062a\u0623\u0643\u062f \u0645\u0646 \u0627\u0643\u062a\u0645\u0627\u0644 \u0627\u0644\u062a\u062b\u0628\u064a\u062a..."]
    ];
    for (NSArray *p in phases) {
        InstallPhaseView *pv = [[InstallPhaseView alloc] initWithTitle:p[0] subtitle:p[1]];
        [_phasesStack addArrangedSubview:pv];
        [_phaseViews addObject:pv];
    }

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [_containerView.topAnchor constraintEqualToAnchor:_scrollView.topAnchor constant:20],
        [_containerView.leadingAnchor constraintEqualToAnchor:_scrollView.leadingAnchor constant:20],
        [_containerView.trailingAnchor constraintEqualToAnchor:_scrollView.trailingAnchor constant:-20],
        [_containerView.bottomAnchor constraintEqualToAnchor:_scrollView.bottomAnchor constant:-20],
        [_containerView.widthAnchor constraintEqualToAnchor:_scrollView.widthAnchor constant:-40],

        [_headerLabel.topAnchor constraintEqualToAnchor:_containerView.topAnchor],
        [_headerLabel.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor],
        [_headerLabel.trailingAnchor constraintEqualToAnchor:_containerView.trailingAnchor],

        [_appNameLabel.topAnchor constraintEqualToAnchor:_headerLabel.bottomAnchor constant:6],
        [_appNameLabel.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor],
        [_appNameLabel.trailingAnchor constraintEqualToAnchor:_containerView.trailingAnchor],

        [_progressView.topAnchor constraintEqualToAnchor:_appNameLabel.bottomAnchor constant:20],
        [_progressView.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor],
        [_progressView.trailingAnchor constraintEqualToAnchor:_containerView.trailingAnchor],
        [_progressView.heightAnchor constraintEqualToConstant:4],

        [_liveOutputCard.topAnchor constraintEqualToAnchor:_progressView.bottomAnchor constant:16],
        [_liveOutputCard.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor],
        [_liveOutputCard.trailingAnchor constraintEqualToAnchor:_containerView.trailingAnchor],
        [_liveOutputCard.heightAnchor constraintEqualToConstant:214],

        [liveTitle.topAnchor constraintEqualToAnchor:_liveOutputCard.topAnchor constant:10],
        [liveTitle.leadingAnchor constraintEqualToAnchor:_liveOutputCard.leadingAnchor constant:12],
        [liveTitle.trailingAnchor constraintLessThanOrEqualToAnchor:_liveOutputCard.trailingAnchor constant:-12],

        [_liveStateLabel.topAnchor constraintEqualToAnchor:liveTitle.bottomAnchor constant:2],
        [_liveStateLabel.leadingAnchor constraintEqualToAnchor:liveTitle.leadingAnchor],
        [_liveStateLabel.trailingAnchor constraintEqualToAnchor:_liveOutputCard.trailingAnchor constant:-12],

        [_liveOutputView.topAnchor constraintEqualToAnchor:_liveStateLabel.bottomAnchor constant:6],
        [_liveOutputView.leadingAnchor constraintEqualToAnchor:_liveOutputCard.leadingAnchor constant:8],
        [_liveOutputView.trailingAnchor constraintEqualToAnchor:_liveOutputCard.trailingAnchor constant:-8],
        [_liveOutputView.bottomAnchor constraintEqualToAnchor:_liveOutputCard.bottomAnchor constant:-8],

        [_phasesStack.topAnchor constraintEqualToAnchor:_liveOutputCard.bottomAnchor constant:20],
        [_phasesStack.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor],
        [_phasesStack.trailingAnchor constraintEqualToAnchor:_containerView.trailingAnchor],
        [_phasesStack.bottomAnchor constraintLessThanOrEqualToAnchor:_containerView.bottomAnchor]
    ]];
}

- (void)setPhase:(NSInteger)index state:(PhaseVisualState)state {
    if (index < 0 || index >= (NSInteger)self.phaseViews.count) return;
    [self.phaseViews[index] setState:state animated:YES];
    self.currentPhaseIndex = index;
}

#pragma mark - Installation

- (void)startInstallation {
    if (!self.ipaPath) {
        [self showFinalState:NO message:@"\u0645\u0633\u0627\u0631 IPA \u063a\u064a\u0631 \u0635\u0627\u0644\u062d"];
        return;
    }

    self.isDone = NO;
    self.hasFailed = NO;
    self.lastFailureMessage = nil;
    self.installedBundleID = nil;
    self.currentTxnID = nil;
    self.currentPhaseIndex = -1;
    self.installStartTime = [NSDate date];
    [self.rawLog setString:@""];

    if (self.reportCard) {
        [self.reportCard removeFromSuperview];
        self.reportCard = nil;
    }
    if (self.showLogButton) {
        [self.showLogButton removeFromSuperview];
        self.showLogButton = nil;
    }

    self.headerLabel.text = @"\u062c\u0627\u0631\u064d \u0627\u0644\u062a\u062b\u0628\u064a\u062a...";
    self.headerLabel.textColor = [IPTheme textPrimaryColor];
    self.appNameLabel.text = [self.ipaPath lastPathComponent] ?: @"";
    [self.progressView setProgress:0.0 animated:NO];

    for (InstallPhaseView *pv in self.phaseViews) {
        [pv setState:PhaseVisualStatePending animated:NO];
    }

    InstallationEngine *engine = [InstallationEngine sharedEngine];
    // Clear only a completed/failed marker. A live installation is never
    // interrupted and remains protected by the engine lock.
    [engine resetFailedInstallationState];
    if (engine.isInstalling) {
        [self showFinalState:NO message:@"\u062a\u062b\u0628\u064a\u062a \u0622\u062e\u0631 \u0645\u0627 \u0632\u0627\u0644 \u0642\u064a\u062f \u0627\u0644\u062a\u0646\u0641\u064a\u0630"];
        return;
    }

    self.currentTxnID = [[NSUUID UUID] UUIDString];
    [engine prepareTransactionWithID:self.currentTxnID];

    self.lastRenderedLiveSequence = 0;
    self.liveOutputView.text = @"";
    self.liveStateLabel.text = @"الحالة الحية: BEGIN — انتظار أول حدث";
    self.liveStateLabel.textColor = [UIColor colorWithRed:0.35 green:0.75 blue:1.0 alpha:1.0];
    self.liveStream = [[LiveOperationStream alloc] init];
    __weak typeof(self) weakLiveSelf = self;
    [self.liveStream startForTransactionID:self.currentTxnID handler:^(LiveOperationEvent *event) {
        __strong typeof(weakLiveSelf) strongLiveSelf = weakLiveSelf;
        if (strongLiveSelf) [strongLiveSelf renderLiveOperationEvent:event];
    }];

    __weak typeof(self) weakSelf = self;
    [engine installIPA:self.ipaPath
         progressBlock:^(InstallationStage stage, NSString *statusMessage, float progress) {
    } completion:^(InstallationResult *result) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.isDone = YES;
        if (result && result.success) {
            strongSelf.installedBundleID = result.bundleID;
            [strongSelf handleCompletionSuccess:result];
        } else {
            [strongSelf handleCompletionFailure:result];
        }
    }];
}

- (void)handleCompletionSuccess:(InstallationResult *)result {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (InstallPhaseView *pv in self.phaseViews) {
            if (pv.phaseState == PhaseVisualStateActive || pv.phaseState == PhaseVisualStatePending) {
                [pv setState:PhaseVisualStateSuccess animated:YES];
            }
        }
        [self.progressView setProgress:1.0 animated:YES];
        self.headerLabel.text = @"\u0627\u0643\u062a\u0645\u0644 \u0627\u0644\u062a\u062b\u0628\u064a\u062a \u2713";
        if (self.dismissOnDuplicateSuccess) {
            // Duplicate owns this progress modal. Close the passive stream and
            // release presentation state before notifying its parent. The
            // ordinary install flow keeps the existing report-card behavior.
            [self.liveStream close];
            self.liveStream = nil;
            [self.pendingLiveCriticalEvents removeAllObjects];
            self.pendingLiveNormalLast = nil;
            self.pendingLiveNormalCount = 0;
            self.liveRenderGeneration += 1;
            IPADuplicateCompletionHandler handler = [self.duplicateCompletionHandler copy];
            self.duplicateCompletionHandler = nil;
            if (handler) handler(YES, result);
            return;
        }
        [self showReportCard:result success:YES];
    });
}

- (void)handleCompletionFailure:(InstallationResult *)result {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger failIdx = self.currentPhaseIndex >= 0 ? self.currentPhaseIndex : 0;
        if (failIdx < (NSInteger)self.phaseViews.count) {
            [self.phaseViews[failIdx] setState:PhaseVisualStateFailed animated:YES];
        }
        self.headerLabel.text = @"\u0641\u0634\u0644 \u0627\u0644\u062a\u062b\u0628\u064a\u062a \u2717";
        self.headerLabel.textColor = [UIColor colorWithRed:0.9 green:0.3 blue:0.3 alpha:1.0];
        [self showReportCard:result success:NO];
    });
}

#pragma mark - Report Card

- (void)showReportCard:(InstallationResult *)result success:(BOOL)success {
    if (self.reportCard) [self.reportCard removeFromSuperview];
    self.lastFailureMessage = success ? nil : (result.message ?: @"");

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [IPTheme cardColor];
    card.layer.cornerRadius = 16;
    card.layer.borderWidth = 0.7; card.layer.borderColor = [IPTheme subtleBorderColor].CGColor;
    [self.containerView addSubview:card];
    self.reportCard = card;

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    [card addSubview:stack];

    UILabel *statusLabel = [[UILabel alloc] init];
    statusLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    statusLabel.textAlignment = NSTextAlignmentCenter;
    statusLabel.text = success ? @"\u2713 \u062a\u0645 \u0627\u0644\u062a\u062b\u0628\u064a\u062a \u0628\u0646\u062c\u0627\u062d" : @"\u2717 \u0641\u0634\u0644 \u0627\u0644\u062a\u062b\u0628\u064a\u062a";
    statusLabel.textColor = success
        ? [IPTheme successColor]
        : [UIColor colorWithRed:0.9 green:0.3 blue:0.3 alpha:1.0];
    [stack addArrangedSubview:statusLabel];

    UIView *divider = [[UIView alloc] init];
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    divider.backgroundColor = [IPTheme textPrimaryColor];
    [divider.heightAnchor constraintEqualToConstant:1].active = YES;
    [stack addArrangedSubview:divider];

    NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:self.installStartTime];
    JailbreakEnvironment *env = [JailbreakEnvironment sharedEnvironment];
    NSString *appName = [[self.ipaPath lastPathComponent] stringByDeletingPathExtension] ?: @"-";

    [self addSectionTitle:@"\u0627\u0644\u062a\u0637\u0628\u064a\u0642" toStack:stack];
    [self addItem:[NSString stringWithFormat:@"\u0627\u0644\u0627\u0633\u0645: %@", appName] toStack:stack];
    [self addItem:[NSString stringWithFormat:@"Bundle ID: %@", result.bundleID ?: @"-"] toStack:stack];

    [self addSectionTitle:@"\u0627\u0644\u062a\u062b\u0628\u064a\u062a" toStack:stack];
    [self addItem:[NSString stringWithFormat:@"\u0627\u0644\u062d\u0627\u0644\u0629: %@", success ? @"\u0646\u062c\u0627\u062d" : @"\u0641\u0634\u0644"] toStack:stack];
    [self addItem:[NSString stringWithFormat:@"\u0627\u0644\u0645\u062f\u0629: %.1f \u062b\u0627\u0646\u064a\u0629", duration] toStack:stack];

    if (success) {
        [self addSectionTitle:@"\u0627\u0644\u062a\u062d\u0642\u0642" toStack:stack];
        [self addItem:@"IPA: \u2713 \u0635\u0627\u0644\u062d" toStack:stack];
        [self addItem:@"\u0627\u0644\u0645\u062d\u062a\u0648\u0649: \u2713 \u0645\u0643\u062a\u0645\u0644" toStack:stack];
        [self addItem:@"\u0627\u0644\u062a\u0648\u0642\u064a\u0639: \u2713 \u0645\u0648\u062c\u0648\u062f" toStack:stack];
        [self addItem:@"\u0627\u0644\u062a\u0633\u062c\u064a\u0644: \u2713 \u0645\u0643\u062a\u0645\u0644" toStack:stack];
    }

    [self addSectionTitle:@"\u0627\u0644\u0628\u064a\u0626\u0629" toStack:stack];
    [self addItem:[NSString stringWithFormat:@"\u0627\u0644\u062c\u064a\u0644\u0628\u0631\u064a\u0643: %@", env.jailbreakType ?: @"\u063a\u064a\u0631 \u0645\u0639\u0631\u0648\u0641"] toStack:stack];
    [self addItem:[NSString stringWithFormat:@"Rootless: %@", env.isRootless ? @"\u0646\u0639\u0645" : @"\u0644\u0627"] toStack:stack];

    if (!success && result.message.length > 0) {
        [self addSectionTitle:@"\u062a\u0641\u0627\u0635\u064a\u0644 \u0627\u0644\u062e\u0637\u0623" toStack:stack];
        UILabel *errLabel = [[UILabel alloc] init];
        errLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        errLabel.textColor = [UIColor colorWithRed:0.8 green:0.4 blue:0.4 alpha:1.0];
        errLabel.text = result.message;
        errLabel.numberOfLines = 0;
        errLabel.textAlignment = NSTextAlignmentNatural;
        [stack addArrangedSubview:errLabel];

        UIButton *copyErrorButton = [UIButton buttonWithType:UIButtonTypeSystem];
        copyErrorButton.translatesAutoresizingMaskIntoConstraints = NO;
        [copyErrorButton setTitle:@"نسخ تفاصيل الخطأ" forState:UIControlStateNormal];
        copyErrorButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        [copyErrorButton setTitleColor:[UIColor colorWithRed:0.35 green:0.75 blue:1.0 alpha:1.0] forState:UIControlStateNormal];
        copyErrorButton.backgroundColor = [IPTheme secondaryCardColor];
        copyErrorButton.layer.cornerRadius = 8;
        [copyErrorButton addTarget:self action:@selector(copyFailureDetails:) forControlEvents:UIControlEventTouchUpInside];
        [copyErrorButton.heightAnchor constraintEqualToConstant:40].active = YES;
        [stack addArrangedSubview:copyErrorButton];
    }

    // Raw Log Button
    UIView *spacer = [[UIView alloc] init];
    [spacer.heightAnchor constraintEqualToConstant:8].active = YES;
    [stack addArrangedSubview:spacer];

    UIButton *logBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    logBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [logBtn setTitle:@"\u0639\u0631\u0636 \u0627\u0644\u0644\u0648\u063a \u0627\u0644\u062e\u0627\u0645 (Raw Log)" forState:UIControlStateNormal];
    logBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [logBtn setTitleColor:[IPTheme accentColor] forState:UIControlStateNormal];
    logBtn.backgroundColor = [IPTheme secondaryCardColor];
    logBtn.layer.cornerRadius = 8;
    [logBtn addTarget:self action:@selector(showRawLog) forControlEvents:UIControlEventTouchUpInside];
    [logBtn.heightAnchor constraintEqualToConstant:36].active = YES;
    [stack addArrangedSubview:logBtn];
    self.showLogButton = logBtn;

    if (!success) {
        UIView *retrySpacer = [[UIView alloc] init];
        [retrySpacer.heightAnchor constraintEqualToConstant:4].active = YES;
        [stack addArrangedSubview:retrySpacer];

        UIButton *retryBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        retryBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [retryBtn setTitle:@"إعادة المحاولة" forState:UIControlStateNormal];
        retryBtn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        retryBtn.backgroundColor = [IPTheme accentColor];
        [retryBtn setTitleColor:[IPTheme textPrimaryColor] forState:UIControlStateNormal];
        retryBtn.layer.cornerRadius = 12;
        [retryBtn addTarget:self action:@selector(retryTapped:) forControlEvents:UIControlEventTouchUpInside];
        [retryBtn.heightAnchor constraintEqualToConstant:46].active = YES;
        [stack addArrangedSubview:retryBtn];
    }

    UIView *spacer2 = [[UIView alloc] init];
    [spacer2.heightAnchor constraintEqualToConstant:8].active = YES;
    [stack addArrangedSubview:spacer2];

    UIButton *doneBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    doneBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [doneBtn setTitle:@"\u062a\u0645" forState:UIControlStateNormal];
    doneBtn.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    doneBtn.backgroundColor = success
        ? [IPTheme accentColor]
        : [UIColor colorWithRed:0.6 green:0.2 blue:0.2 alpha:1.0];
    [doneBtn setTitleColor:[IPTheme textPrimaryColor] forState:UIControlStateNormal];
    doneBtn.layer.cornerRadius = 12;
    [doneBtn addTarget:self action:@selector(doneTapped:) forControlEvents:UIControlEventTouchUpInside];
    [doneBtn.heightAnchor constraintEqualToConstant:48].active = YES;
    [stack addArrangedSubview:doneBtn];

    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:self.phasesStack.bottomAnchor constant:24],
        [card.leadingAnchor constraintEqualToAnchor:self.containerView.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:self.containerView.trailingAnchor],
        [card.bottomAnchor constraintEqualToAnchor:self.containerView.bottomAnchor constant:-20],

        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:20],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-20],
    ]];

    card.alpha = 0;
    card.transform = CGAffineTransformMakeTranslation(0, 30);
    [UIView animateWithDuration:0.5 delay:0.1 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:0 animations:^{
        card.alpha = 1;
        card.transform = CGAffineTransformIdentity;
    } completion:nil];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CGRect cardFrame = [self.scrollView convertRect:card.frame fromView:self.containerView];
        [self.scrollView scrollRectToVisible:cardFrame animated:YES];
    });
}

- (void)addSectionTitle:(NSString *)title toStack:(UIStackView *)stack {
    UILabel *label = [[UILabel alloc] init];
    label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    label.textColor = [IPTheme textSecondaryColor];
    label.text = title;
    [stack addArrangedSubview:label];
}

- (void)addItem:(NSString *)text toStack:(UIStackView *)stack {
    UILabel *label = [[UILabel alloc] init];
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    label.textColor = [IPTheme textPrimaryColor];
    label.text = text;
    label.numberOfLines = 0;
    [stack addArrangedSubview:label];
}

- (void)showFinalState:(BOOL)success message:(NSString *)message {
    self.headerLabel.text = message;
    self.headerLabel.textColor = success
        ? [IPTheme successColor]
        : [UIColor colorWithRed:0.9 green:0.3 blue:0.3 alpha:1.0];
}

#pragma mark - Actions

- (void)retryTapped:(UIButton *)sender {
    InstallationEngine *engine = [InstallationEngine sharedEngine];
    if (engine.isInstalling) {
        [self showFinalState:NO message:@"تثبيت آخر ما زال قيد التنفيذ"];
        return;
    }
    [self startInstallation];
}

- (void)doneTapped:(UIButton *)sender {
    // Make dismissal idempotent: a failed/completed transaction must not leave
    // a stale marker that blocks the next installation.
    [[InstallationEngine sharedEngine] resetFailedInstallationState];
    [self dismissViewControllerAnimated:YES completion:nil];
}


- (NSAttributedString *)coloredLogFromString:(NSString *)text {
    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:text];
    NSRange full = NSMakeRange(0, text.length);
    UIFont *font = [UIFont fontWithName:@"Courier" size:10] ?: [UIFont systemFontOfSize:10];
    [attr addAttribute:NSFontAttributeName value:font range:full];
    [attr addAttribute:NSForegroundColorAttributeName value:[IPTheme successColor] range:full];

    NSArray *redKeywords = @[@"❌", @"MISSING", @"FAILED", @"FALLBACK", @"ERROR", @"CRASH", @"incomplete", @"application-identifier MISSING", @"team-identifier MISSING", @"Deep copy MISSING", @"hasAppID=NO", @"hasTeamID=NO"];
    for (NSString *word in redKeywords) {
        NSRange searchRange = NSMakeRange(0, text.length);
        NSRange found = [text rangeOfString:word options:0 range:searchRange];
        while (found.location != NSNotFound) {
            [attr addAttribute:NSForegroundColorAttributeName value:[IPTheme errorColor] range:found];
            searchRange = NSMakeRange(found.location + found.length, text.length - found.location - found.length);
            found = [text rangeOfString:word options:0 range:searchRange];
        }
    }

    NSArray *yellowKeywords = @[@"⚠️", @"WARNING", @"BLANK"];
    for (NSString *word in yellowKeywords) {
        NSRange searchRange = NSMakeRange(0, text.length);
        NSRange found = [text rangeOfString:word options:0 range:searchRange];
        while (found.location != NSNotFound) {
            [attr addAttribute:NSForegroundColorAttributeName value:[IPTheme warningColor] range:found];
            searchRange = NSMakeRange(found.location + found.length, text.length - found.location - found.length);
            found = [text rangeOfString:word options:0 range:searchRange];
        }
    }

    NSArray *blueKeywords = @[@"📊 DIAGNOSTICS REPORT", @"[ENTITLEMENTS]", @"[SIGNING COVERAGE]", @"[DEEP COPY]", @"[CRITICAL CHECKS]"];
    for (NSString *word in blueKeywords) {
        NSRange searchRange = NSMakeRange(0, text.length);
        NSRange found = [text rangeOfString:word options:0 range:searchRange];
        while (found.location != NSNotFound) {
            [attr addAttribute:NSForegroundColorAttributeName value:[IPTheme accentColor] range:found];
            searchRange = NSMakeRange(found.location + found.length, text.length - found.location - found.length);
            found = [text rangeOfString:word options:0 range:searchRange];
        }
    }

    return attr;
}

@end
