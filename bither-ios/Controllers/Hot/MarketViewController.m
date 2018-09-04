//  MarketViewController.m
//  bither-ios
//
//  Copyright 2014 http://Bither.net
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

#import "MarketViewController.h"
#import "MarketListCell.h"
#import "MarketUtil.h"
#import "NSString+Size.h"
#import "BitherTime.h"
#import "TrendingGraphicView.h"
#import "BackgroundTransitionView.h"
#import "NTicker.h"
#define DEFAULT_DISPALY_PRICE @"--"

@interface MarketViewController () <UITableViewDataSource, UITableViewDelegate> {
    BOOL _isCheckAnimation;
    BOOL _isAppear;
}
@property(weak, nonatomic) IBOutlet UITableView *tableView;
@property(weak, nonatomic) IBOutlet UILabel *lbMarketName;
@property(weak, nonatomic) IBOutlet UILabel *lbNew;
@property(weak, nonatomic) IBOutlet UILabel *lbHigh;
@property(weak, nonatomic) IBOutlet UILabel *lbLow;
@property(weak, nonatomic) IBOutlet UILabel *lbAmount;
@property(weak, nonatomic) IBOutlet UILabel *lbBuy;
@property(weak, nonatomic) IBOutlet UILabel *lbSell;
@property(weak, nonatomic) IBOutlet BackgroundTransitionView *matketDetailView;
@property(weak, nonatomic) IBOutlet UILabel *lbSymbol;
@property(weak, nonatomic) IBOutlet UIView *vAmountContainer;
@property(weak, nonatomic) IBOutlet UIView *vLeftContainer;
@property(weak, nonatomic) IBOutlet UIView *vRightContainer;
@property(weak, nonatomic) IBOutlet UILabel *lbl24H;
@property(weak, nonatomic) IBOutlet UIImageView *ivProgress;
@property(weak, nonatomic) IBOutlet TrendingGraphicView *vTrending;

@property(weak, nonatomic) Market *market;

@end

@implementation MarketViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
    }
    return self;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.market.nticker == nil) {
        [[BitherTime instance] resume];
    }
    [self reload];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupTableView];
    self.market = [MarketUtil getDefaultMarket];
    [self reload];
    [self.vTrending setData:nil];
    _isCheckAnimation = NO;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(notificationReload) name:BitherMarketUpdateNotification object:nil];
}

- (void)setupTableView
{
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    if ([self.tableView respondsToSelector:@selector(setLayoutMargins:)]) {
        self.tableView.layoutMargins = UIEdgeInsetsZero;
    }
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _isAppear = YES;
    if (_isCheckAnimation) {
        [self moveProgress];
    }
    self.vTrending.marketType = self.market.marketType;
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    _isAppear = NO;
}

- (void)notificationReload {
    [self reload];
    _isCheckAnimation = YES;
    if (_isAppear) {
        [self moveProgress];
    }
}

- (void)reload {
    [self.tableView reloadData];
    self.lbMarketName.text = self.market.nticker.data.name;
    if (_isAppear) {
        self.matketDetailView.backgroundColor = [GroupUtil getMarketColor:self.market.marketType];
    } else {
        [self.matketDetailView setBackgroundColorWithoutTransition:[GroupUtil getMarketColor:self.market.marketType]];
    }
    if (self.market.nticker) {
        NTicker *nticker = self.market.nticker;
        NTickerConvert *conDetl = nticker.data.quotes.USD;
        if ([[UserDefaultsUtil instance] getDefaultCurrency] == CNY) {
            conDetl = nticker.data.quotes.CNY;
        }
        self.lbSymbol.text = [BitherSetting getCurrencySymbol:[[UserDefaultsUtil instance] getDefaultCurrency]];
        self.lbNew.text = [StringUtil formatDouble:[conDetl.price doubleValue]];
//        self.lbHigh.text = [StringUtil formatPrice:[conDetl.price doubleValue]*(1+[nticker.data.quotes.USD.percent_change_24h doubleValue]/100)];
        
//        self.lbLow.text = [StringUtil formatPrice:[conDetl.price doubleValue]];
        self.lbAmount.text = [NSString stringWithFormat:@"%.2f",[self.market.nticker.data.total_supply doubleValue]];
//        self.lbBuy.text = [NSString stringWithFormat:NSLocalizedString(@"Buy: %@", nil), [StringUtil formatPrice:[nticker.data.circulating_supply doubleValue]]];
//        self.lbSell.text = [NSString stringWithFormat:NSLocalizedString(@"Sell: %@", nil), [StringUtil formatPrice:[nticker.data.circulating_supply doubleValue]]];
        self.lbHigh.text = @"";
        self.lbl24H.text = @"";
        self.lbLow.text = @"";
        self.lbBuy.text = @"";
        self.lbSell.text = @"";
    } else {
        self.lbSymbol.text = @"";
        self.lbNew.text = DEFAULT_DISPALY_PRICE;
        self.lbHigh.text = @"";
        self.lbLow.text = @"";
        self.lbAmount.text = DEFAULT_DISPALY_PRICE;
        self.lbBuy.text = @"";
        self.lbSell.text = @"";
    }
    [self positionViews];
    if (_isAppear) {
        self.vTrending.marketType = self.market.marketType;
    }

}

- (void)positionViews {
    CGRect frame = self.lbNew.frame;
    CGFloat width = [self.lbNew.text sizeWithRestrict:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX) font:self.lbNew.font].width;
    frame.origin.x = frame.origin.x - (width - frame.size.width);
    frame.size.width = width;
    self.lbNew.frame = frame;
    frame = self.lbSymbol.frame;
    frame.origin.x = self.lbNew.frame.origin.x - frame.size.width - 5;
    self.lbSymbol.frame = frame;

    frame = self.vLeftContainer.frame;
    frame.size.width = MAX([self.lbHigh.text sizeWithRestrict:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX) font:self.lbHigh.font].width, [self.lbLow.text sizeWithRestrict:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX) font:self.lbLow.font].width) + self.lbl24H.frame.size.width;
    self.vLeftContainer.frame = frame;

    frame = self.vAmountContainer.frame;
    width = [self.lbAmount.text sizeWithRestrict:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX) font:self.lbAmount.font].width + self.lbAmount.frame.origin.x;
    frame.origin.x = frame.origin.x - (width - frame.size.width);
    frame.size.width = width;
    self.vAmountContainer.frame = frame;

    frame = self.vRightContainer.frame;
    width = MAX(MAX([self.lbBuy.text sizeWithRestrict:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX) font:self.lbBuy.font].width, [self.lbSell.text sizeWithRestrict:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX) font:self.lbSell.font].width), self.vAmountContainer.frame.size.width);
    frame.origin.x = frame.origin.x - (width - frame.size.width);
    frame.size.width = width;
    self.vRightContainer.frame = frame;

    self.vTrending.frame = CGRectMake(CGRectGetMaxX(self.vLeftContainer.frame), self.vLeftContainer.frame.origin.y-16, self.vRightContainer.frame.origin.x - CGRectGetMaxX(self.vLeftContainer.frame), self.vLeftContainer.frame.size.height);
}

- (void)moveProgress {
    self.ivProgress.hidden = NO;
    __weak typeof(self) weakSelf = self;
     [UIView animateWithDuration:1.2f animations:^{
        weakSelf.ivProgress.frame = CGRectMake(300 - 17, 0, weakSelf.ivProgress.frame.size.width, weakSelf.ivProgress.frame.size.height);
    } completion:^(BOOL finished) {
        weakSelf.ivProgress.hidden = YES;
        _isCheckAnimation = NO;
        weakSelf.ivProgress.frame = CGRectMake(0, 0, weakSelf.ivProgress.frame.size.width, weakSelf.ivProgress.frame.size.height);
    }];
}

#pragma mark ------ tableView delegate and datasource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
//    return [MarketUtil getMarkets].count;
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    MarketListCell *cell = (MarketListCell *) [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    [cell setMarket:self.market];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    self.market = [[MarketUtil getMarkets] objectAtIndex:indexPath.row];
    [self reload];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:BitherMarketUpdateNotification object:nil];
}

@end
