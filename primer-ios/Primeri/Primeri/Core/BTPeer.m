//
//  BTPeer.m
//  Primeri
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
//
//  Copyright (c) 2013-2014 Aaron Voisine <voisine@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import "BTPeer.h"
#import "BTTx.h"
#import "BTBlock.h"
#import <arpa/inet.h>
#import "Reachability.h"
#import "BTSettings.h"
#import "BTPeerProvider.h"
#import "BTTxProvider.h"
#import "BTScript.h"
#import "BTBlockChain.h"
#import "BTPeerManager.h"
#import "BTOut.h"
#import "BTAddressManager.h"
#import "BTIn.h"

#define GET_BLOCK_DATA_PIECE_SIZE (5)
#define MAX_PEER_MANAGER_WAITING_TASK_COUNT (5)
#define PEER_MANAGER_MAX_TASK_CHECKING_INTERVAL (0.1)
#define BLOOMFILTER_UPDATE_BLOCK_INTERVAL (100)


typedef enum {
    error = 0,
    tx,
    block,
    merkleblock
} inv_t;

@interface BTPeer () {
    BOOL _bloomFilterSent;
    uint32_t _incrementalBlockHeight;
    int _unrelatedTxRelayCount;
    NSString *_host;
    BOOL _synchronising;
    BOOL _relayTxesBeforeFilter;
    uint32_t _syncStartBlockNo;
    uint32_t _syncStartPeerBlockNo;
    uint32_t _synchronisingBlockCount;
}

@property(nonatomic, strong) NSInputStream *inputStream;
@property(nonatomic, strong) NSOutputStream *outputStream;
@property(nonatomic, strong) NSMutableData *msgHeader, *msgPayload, *outputBuffer;
@property(nonatomic, assign) BOOL sentVerAck, gotVerAck;
@property(nonatomic, strong) Reachability *reachability;
@property(nonatomic, strong) id reachabilityObserver;
@property(nonatomic, assign) uint64_t localNonce;
@property(nonatomic, assign) NSTimeInterval startTime;
@property(nonatomic, strong) BTBlock *currentBlock;
@property(nonatomic, strong) NSMutableOrderedSet *currentBlockHashes, *currentTxHashes, *knownTxHashes;
@property(nonatomic, strong) NSMutableArray *syncBlocks;
@property(nonatomic, strong) NSMutableArray *syncBlockHashes;
@property(nonatomic, strong) NSMutableArray *invBlockHashes;
@property(nonatomic, strong) NSCountedSet *requestedBlockHashes;
@property(nonatomic, assign) uint32_t filterBlockCount;
@property(nonatomic, strong) NSRunLoop *runLoop;
@property(nonatomic, strong) dispatch_queue_t q;
@property(nonatomic, strong) NSMutableDictionary *needToRequestDependencyDict;
//@property(nonatomic, strong) NSString *sendType;
@end

@implementation BTPeer

- (instancetype)initWithAddress:(uint32_t)address port:(uint16_t)port timestamp:(NSTimeInterval)timestamp
                       services:(uint64_t)services {
    if (!(self = [self init])) return nil;

    _peerAddress = address;
    _peerPort = ((port == 0) ? (uint16_t) BITCOIN_STANDARD_PORT : port);
    _timestamp = timestamp;
    _peerServices = services;
    _peerConnectedCnt = 0;
    _relayTxesBeforeFilter = YES;

    return self;
}

- (void)dealloc {
    [self.reachability stopNotifier];
    if (self.reachabilityObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.reachabilityObserver];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (NSString *)host {
    if (_host == nil) {
        struct in_addr addr = {CFSwapInt32HostToBig(self.peerAddress)};
        char s[INET_ADDRSTRLEN];

        _host = [NSString stringWithUTF8String:inet_ntop(AF_INET, &addr, s, INET_ADDRSTRLEN)];
    }
    return _host;
}

- (void)connectPeer {//连接节点
    if (self.status != BTPeerStatusDisconnected) return;

    if (!self.reachability) self.reachability = [Reachability reachabilityWithHostname:self.host];

    if (self.reachability.currentReachabilityStatus == NotReachable) { // delay connect until network is reachable
        if (self.reachabilityObserver) return;

        self.reachabilityObserver =
                [[NSNotificationCenter defaultCenter] addObserverForName:kReachabilityChangedNotification
                                                                  object:self.reachability queue:nil usingBlock:^(NSNotification *note) {
                            if (self.reachability.currentReachabilityStatus != NotReachable) [self connectPeer];
                        }];

        [self.reachability startNotifier];//监听网络状态
    }
    else if (self.reachabilityObserver) {
        [self.reachability stopNotifier];
        [[NSNotificationCenter defaultCenter] removeObserver:self.reachabilityObserver];
        self.reachabilityObserver = nil;
    }

    _status = BTPeerStatusConnecting;
    _pingTime = DBL_MAX;
    self.msgHeader = [NSMutableData data];
    self.msgPayload = [NSMutableData data];
    self.outputBuffer = [NSMutableData data];
    self.knownTxHashes = [NSMutableOrderedSet orderedSet];
    self.currentBlockHashes = [NSMutableOrderedSet orderedSet];
    self.requestedBlockHashes = [NSCountedSet set];
    self.needToRequestDependencyDict = [NSMutableDictionary new];
    self.invBlockHashes = [NSMutableArray new];
    _synchronising = NO;

    NSString *label = [NSString stringWithFormat:@"net.bither.peer.%@:%d", self.host, self.peerPort];
    _bloomFilterSent = NO;
    // use a private serial queue for processing socket io
    dispatch_async(dispatch_queue_create(label.UTF8String, NULL), ^{
        CFReadStreamRef readStream = NULL;
        CFWriteStreamRef writeStream = NULL;

        DDLogDebug(@"%@:%u connecting", self.host, self.peerPort);
        //建立连接
        CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef) self.host, self.peerPort, &readStream, &writeStream);
        self.inputStream = CFBridgingRelease(readStream);
        self.outputStream = CFBridgingRelease(writeStream);
        self.inputStream.delegate = self.outputStream.delegate = self;//设置代理

        //添加到runloop
        self.runLoop = [NSRunLoop currentRunLoop];
        [self.inputStream scheduleInRunLoop:self.runLoop forMode:NSRunLoopCommonModes];
        [self.outputStream scheduleInRunLoop:self.runLoop forMode:NSRunLoopCommonModes];

        // after the reachablity check, the radios should be warmed up and we can set a short socket connect timeout
        [self checkTimeOut];

        //打开
        [self.inputStream open];
        [self.outputStream open];

        [self sendVersionMessage];
        [self.runLoop run]; // this doesn't return until the runloop is stopped
    });
}

- (void)disconnectPeer {
    [self disconnectWithError:nil];
}

- (void)disconnectWithError:(NSError *)error {//消息返回错误处理
    DDLogWarn(@"%@:%d disconnected%@%@", self.host, self.peerPort, error ? @", " : @"", error ?: @"");
    [NSObject cancelPreviousPerformRequestsWithTarget:self]; // cancel connect timeout

    _status = BTPeerStatusDisconnected;

    if (!self.runLoop) return;

    // can't use dispatch_async here because the runloop blocks the queue, so schedule on the runloop instead
    CFRunLoopPerformBlock([self.runLoop getCFRunLoop], kCFRunLoopCommonModes, ^{
        [self.inputStream close];
        [self.outputStream close];

        [self.inputStream removeFromRunLoop:self.runLoop forMode:NSRunLoopCommonModes];
        [self.outputStream removeFromRunLoop:self.runLoop forMode:NSRunLoopCommonModes];

        CFRunLoopStop([self.runLoop getCFRunLoop]);

        self.gotVerAck = self.sentVerAck = NO;
        _status = BTPeerStatusDisconnected;
        [self.delegate peer:self disconnectedWithError:error];
    });
    CFRunLoopWakeUp([self.runLoop getCFRunLoop]);
}

- (void)error:(NSString *)message, ... {
    [self disconnectWithError:[NSError errorWithDomain:@"primeri"
                                                  code:ERR_PEER_DISCONNECT_CODE
                                              userInfo:@{NSLocalizedDescriptionKey :
                                                             @"error nodes"}]];
}

- (void)didConnect {
    if (self.status != BTPeerStatusConnecting || !self.sentVerAck || !self.gotVerAck) return;

    DDLogDebug(@"%@:%d handshake completed lastblock:%d", self.host, self.peerPort, self.versionLastBlock);
    [NSObject cancelPreviousPerformRequestsWithTarget:self]; // cancel pending handshake timeout取消待定握手超时
    _status = BTPeerStatusConnected;
    if (_status == BTPeerStatusConnected) [self.delegate peerConnected:self];
}

- (BOOL)synchronising {
    return _synchronising;
}

- (void)setSynchronising:(BOOL)synchronising {
    if (synchronising && !_synchronising) {
        _syncStartBlockNo = [BTBlockChain instance].lastBlock.blockNo;
        _syncStartPeerBlockNo = self.displayLastBlock;
        _synchronisingBlockCount = 0;
        self.syncBlocks = [NSMutableArray new];
        self.syncBlockHashes = [NSMutableArray new];

        _synchronising = synchronising;
    } else if (!synchronising && _synchronising) {
        _incrementalBlockHeight = [BTBlockChain instance].lastBlock.blockNo - self.versionLastBlock;
        _synchronisingBlockCount = 0;

        _synchronising = synchronising;
    }
}

#pragma mark - send

- (void)sendMessage:(NSData *)message type:(NSString *)type {
    NSLog(@"发送-----------%@",type);
    if (message.length > MAX_MSG_LENGTH) {
        DDLogWarn(@"%@:%d failed to send %@, length %d is too long", self.host, self.peerPort, type, (int) message.length);
#if DEBUG
        abort();
#endif
        return;
    }

    if (!self.runLoop) return;

    CFRunLoopPerformBlock([self.runLoop getCFRunLoop], kCFRunLoopCommonModes, ^{
        DDLogDebug(@"%@:%d sending %@", self.host, self.peerPort, type);

        [self.outputBuffer appendMessage:message type:type];
        //发送消息
        while (self.outputBuffer.length > 0 && [self.outputStream hasSpaceAvailable]) {
            NSInteger l = [self.outputStream write:self.outputBuffer.bytes maxLength:self.outputBuffer.length];
            if (l > 0) [self.outputBuffer replaceBytesInRange:NSMakeRange(0, l) withBytes:NULL length:0];
//            if (self.outputBuffer.length == 0) DDLogDebug(@"%@:%d output buffer cleared", self.host, self.peerPort);
        }
    });
    CFRunLoopWakeUp([self.runLoop getCFRunLoop]);
}
//当一个节点收到连接请求时，它立即宣告其版本。远程节点会以自己的版本响应，在通信双方都得到对方版本之前，不会有其他通信。

- (void)sendVersionMessage {
    NSMutableData *msg = [NSMutableData data];

    [msg appendUInt32:PROTOCOL_VERSION]; // version
    [msg appendUInt64:ENABLED_SERVICES]; // services
    [msg appendUInt64:(uint64_t) ([NSDate timeIntervalSinceReferenceDate] + NSTimeIntervalSince1970)]; // timestamp
    [msg appendNetAddress:self.peerAddress port:self.peerPort services:self.peerServices]; // address of remote peer
    [msg appendNetAddress:LOCAL_HOST port:BITCOIN_STANDARD_PORT services:ENABLED_SERVICES]; // address of local peer
    self.localNonce = (((uint64_t) mrand48() << 32) | (uint32_t) mrand48()); // random nonce
    [msg appendUInt64:self.localNonce];
    [msg appendString:USERAGENT]; // user agent
    [msg appendUInt32:0]; // last block received
    [msg appendUInt8:0]; // relay transactions (no for SPV bloom filter mode)
    self.startTime = [NSDate timeIntervalSinceReferenceDate];
    [self sendMessage:msg type:MSG_VERSION];
}
//版本不低于209的客户端在应答version消息时发送verack消息。这个消息仅包含一个command为"verack"的消息头
- (void)sendVerAckMessage {
    [self sendMessage:[NSData data] type:MSG_VERACK];
    self.sentVerAck = YES;
    [self didConnect];
}
//filterload消息告诉接收方需要过滤所有转发的交易，并通过提供的过滤器请求merkle块。 这允许客户接收与其钱包相关的交易。
- (void)sendFilterLoadMessage:(NSData *)filter {
    self.filterBlockCount = 0;
    [self sendMessage:filter type:MSG_FILTERLOAD];
    _bloomFilterSent = YES;
}
//向节点发送请求，询问已经通过验证但没有确认的交易信息
- (void)sendMemPoolMessage {
    [self sendMessage:[NSData data] type:MSG_MEMPOOL];
}
//addr（IP地址）消息用来表示网络上节点的连接信息。 每个想要接受传入连接的节点创建一个addr消息，提供其连接信息，然后将该消息发送给未经请求的节点，当接收端收到此命令后把接收到的地址添加到节点的地址管理器中，发送、接收的地址数量最多1000个。
- (void)sendAddrMessage {
    NSMutableData *msg = [NSMutableData data];

    //TODO: send peer addresses we know about
    [msg appendVarInt:0];
    [self sendMessage:msg type:MSG_ADDR];
}
#pragma mark - 原理
// the standard blockchain download protocol works as follows (for SPV mode):
// - local peer sends getblocks
// - remote peer reponds with inv containing up to 500 block hashes
// - local peer sends getdata with the block hashes
// - remote peer responds with multiple merkleblock and tx messages
// - remote peer sends inv containg 1 hash, of the most recent block
// - local peer sends getdata with the most recent block hash
// - remote peer responds with merkleblock
// - if local peer can't connect the most recent block to the chain (because it started more than 500 blocks behind), go
//   back to first step and repeat until entire chain is downloaded
//
// we modify this sequence to improve sync performance and handle adding bip32 addresses to the bloom filter as needed:
// - local peer sends getheaders
// - remote peer responds with up to 2000 headers
// - local peer immediately sends getheaders again and then processes the headers
// - previous two steps repeat until a header within a week of earliestKeyTime is reached (further headers are ignored)
// - local peer sends getblocks
// - remote peer responds with inv containing up to 500 block hashes
// - if there are 500, local peer immediately sends getblocks again, followed by getdata with the block hashes
// - remote peer responds with inv containing up to 500 block hashes, followed by multiple merkleblock and tx messages
// - previous two steps repeat until an inv with fewer than 500 block hashes is received
// - local peer sends just getdata for the final set of fewer than 500 block hashes
// - remote peer responds with multiple merkleblock and tx messages
// - if at any point tx messages consume enough wallet addresses to drop below the bip32 chain gap limit, more addresses
//   are generated and local peer sends filterload with an updated bloom filter
// - after filterload is sent, getdata is sent to refetch recent blocks that may contain new tx matching the filter
//标准区块链下载协议的工作原理如下（对于SPV模式）：
// - 本地节点发送getblocks
// - 包含最多500个块哈希的inv的远程节点项响应
// - 本地节点使用块哈希发送getdata
// - 远程节点响应多个merkleblock和tx消息
// - 远程节点发送包含最新块的1个哈希的inv
// - 本地节点使用最新的块哈希发送getdata
// - 远程节点用merkleblock响应
// - 如果本地节点方无法将最新的块连接到链（因为它后面启动了超过500个块），请转到
//返回第一步并重复直到下载整个链
//
//我们修改此序列以提高同步性能，并根据需要处理将bloom32地址添加到bloom过滤器：
// - 本地节点发送getheaders
// - 远程节点最多响应2000个头
// - 本地节点立即再次发送getheaders，然后处理标头
// - 前两个步骤重复，直到达到earliestKeyTime一周内的标题（忽略更多标题）
// - 本地节点发送getblocks
// - 远程节点响应包含最多500个块哈希的inv
// - 如果有500，本地节点会立即再次发送getblocks，然后是带有块哈希的getdata
// - 远程节点使用包含多达500个块哈希的inv响应，然后是多个merkleblock和tx消息
// - 前两个步骤重复，直到收到少于500个块哈希的inv
// - 本地节点只发送少于500个块哈希的最终集合的getdata
// - 远程节点响应多个merkleblock和tx消息
// - 如果在任何时候tx消息占用足够的钱包地址以低于bip32链间隙限制，则会有更多地址
//生成并且本地节点使用更新的bloom过滤器发送filterload
// - 发送filterload后，发送getdata以重新获取可能包含与过滤器匹配的新tx的最新块

/*getheaders消息请求 headers 消息，该消息提供从块链中的特定点开始的块 header。接收到此命令后，获取指定的范围的区块的头，将 headers消息发送给源节点。
/getheaders消息几乎与getblocks消息相同，只有一点区别：对getblocks消息的inv回复将包含不超过500个块头hash; headers 回复 getheaders 消息将包含多达2000个块 headers*/
- (void)sendGetHeadersMessageWithLocators:(NSArray *)locators andHashStop:(NSData *)hashStop {
    NSMutableData *msg = [NSMutableData data];

    [msg appendUInt32:PROTOCOL_VERSION];
    [msg appendVarInt:locators.count];

    for (NSData *hash in locators) {
        [msg appendData:hash];
    }

    [msg appendData:hashStop ?: ZERO_HASH];
    DDLogDebug(@"%@:%u calling get headers with locators: %@,%@", self.host, self.peerPort,
            [NSString hexWithHash:locators.firstObject], [NSString hexWithHash:locators.lastObject]);
    [self sendMessage:msg type:MSG_GETHEADERS];
}
/*
 getblocks消息请求一个inv消息，该消息提供从块链中的特定点开始的块头hash。区块同步时，发送此命令，发送时需要指定区块范围(PushGetBlocks)。接收到此命令后，根据区块范围，获取相应的区块，反馈回去。接收的数据中包含区块范围的开始区块的定位信息(CBlockLocator)、结束区块的索引，从开始区块的下一个区块开始。每次最多获取500个区块信息。满500个时，记录获取的最后一个区块的hahs值，保存到源节点的hashContinue中
 */
- (void)sendGetBlocksMessageWithLocators:(NSArray *)locators andHashStop:(NSData *)hashStop {
    NSMutableData *msg = [NSMutableData data];

    [msg appendUInt32:PROTOCOL_VERSION];
    [msg appendVarInt:locators.count];

    for (NSData *hash in locators) {
        [msg appendData:hash];
    }

    [msg appendData:hashStop ?: ZERO_HASH];
    DDLogDebug(@"%@:%u calling get blocks with locators: %@,%@", self.host, self.peerPort,
            [NSString hexWithHash:locators.firstObject], [NSString hexWithHash:locators.lastObject]);
    [self sendMessage:msg type:MSG_GETBLOCKS];
}
//节点通过此消息可以宣告它拥有的对象信息。这个消息可以主动发送，也可以用于应答getblocks消息
- (void)sendInvMessageWithTxHash:(NSData *)txHash {//发布交易信息
    NSMutableData *msg = [NSMutableData data];

    [msg appendVarInt:1];//数据负载地址数，最多1000 
    [msg appendUInt32:tx];//交易数据格式版本
    [msg appendData:txHash];//交易哈希
    [self sendMessage:msg type:MSG_INV];//发送inv消息
    [self.knownTxHashes addObject:txHash];
}
/*
 getdata用于应答inv消息来获取指定对象，它通常在接收到inv包，并且过滤掉已知元素后发送。可用于获得交易，但当且仅当他们在内存池或转发集合中－为了避免某些节点开始依赖具有全部交易索引的节点（现代节点不会），所以任意访问块链中的交易是不允许的，
 */
- (void)sendGetDataMessageWithTxHashes:(NSArray *)txHashes andBlockHashes:(NSArray *)blockHashes {
    // limit total hash count to MAX_GETDATA_HASHES
    if (txHashes.count + blockHashes.count > MAX_GETDATA_HASHES) {
        DDLogWarn(@"%@:%d couldn't send get data, %u is too many items, max is %u", self.host, self.peerPort,
                (int) txHashes.count + (int) blockHashes.count, MAX_GETDATA_HASHES);
        return;
    }

    NSMutableData *msg = [NSMutableData data];

    [msg appendVarInt:txHashes.count + blockHashes.count];

    for (NSData *hash in txHashes) {
        [msg appendUInt32:tx];
        [msg appendData:hash];
    }

    for (NSData *hash in blockHashes) {
        [msg appendUInt32:merkleblock];
        [msg appendData:hash];
    }

    [self.requestedBlockHashes addObjectsFromArray:blockHashes];

    if (self.filterBlockCount + blockHashes.count > BLOOMFILTER_UPDATE_BLOCK_INTERVAL) {
        DDLogDebug(@"%@:%d rebuilding bloom filter after %d blocks", self.host, self.peerPort, self.filterBlockCount);
        [self.delegate requestBloomFilterRecalculate];
        [self sendFilterLoadMessage:[self.delegate peerBloomFilter:self]];
    }

    self.filterBlockCount += (uint32_t) blockHashes.count;
    [self sendMessage:msg type:MSG_GETDATA];
}
/*
 getaddr消息向一个节点发送获取已知活动节点的请求，以发现网络节点。回应这个消息的方法是发送addr消息，包含一个或多个节点信息。活动节点的一般假设是3小时内发送过消息。
 */
- (void)sendGetAddrMessage {
    [self sendMessage:[NSData data] type:MSG_GETADDR];
}
//ping消息主要用于确认TCP/IP连接的可用性。传输错误被假定为已经关闭的连接，并且IP地址已经变为当前的节点。
- (void)sendPingMessage {
    NSMutableData *msg = [NSMutableData data];

    [msg appendUInt64:self.localNonce];
    self.startTime = [NSDate timeIntervalSinceReferenceDate];
    [self sendMessage:msg type:MSG_PING];
}

// refetch blocks starting from blockHash, useful for getting any additional transactions after a bloom filter update
//重新获取从blockHash开始的块，对于在bloom过滤器更新后获取任何其他事务非常有用
- (void)refetchBlocksFrom:(NSData *)blockHash {
    CFRunLoopPerformBlock([self.runLoop getCFRunLoop], kCFRunLoopCommonModes, ^{
        NSUInteger i = [self.currentBlockHashes indexOfObject:blockHash];

        if (i != NSNotFound) {
            [self.currentBlockHashes removeObjectsInRange:NSMakeRange(0, i + 1)];
            DDLogDebug(@"%@:%d refetching %d blocks", self.host, self.peerPort, (int) self.currentBlockHashes.count);
            [self sendGetDataMessageWithTxHashes:@[] andBlockHashes:self.currentBlockHashes.array];
        }
    });
    CFRunLoopWakeUp([self.runLoop getCFRunLoop]);
}

#pragma mark - accept
//处理返回数据
- (void)acceptMessage:(NSData *)message type:(NSString *)type {
    NSLog(@"返回-----------%@",type);
    CFRunLoopPerformBlock([self.runLoop getCFRunLoop], kCFRunLoopCommonModes, ^{
        if (self.currentBlock && ![MSG_TX isEqual:type]) { // if we receive a non-tx message, the merkleblock is done
            self.currentBlock = nil;
            self.currentTxHashes = nil;
            [self error:@"incomplete merkleblock %@, expected %u more tx", [NSString hexWithHash:self.currentBlock.blockHash]
                    , (int) self.currentTxHashes.count];
            return;
        }

        if ([MSG_VERSION isEqual:type]) [self acceptVersionMessage:message];//版本响应
        else if ([MSG_VERACK isEqual:type]) [self acceptVerAckMessage:message];//应答version
        else if ([MSG_ADDR isEqual:type]) [self acceptAddrMessage:message];//已知节点 应答getaddr
        else if ([MSG_INV isEqual:type]) [self acceptInvMessage:message];//宣告拥有的对象信息
        else if ([MSG_TX isEqual:type]) [self acceptTxMessage:message];//描述交易 应答getblock
        else if ([MSG_HEADERS isEqual:type]) [self acceptHeadersMessage:message];//应答getheaders
        else if ([MSG_GETADDR isEqual:type]) [self acceptGetAddrMessage:message];//发送已知节点
        else if ([MSG_GETDATA isEqual:type]) [self acceptGetDataMessage:message];//应答inv消息来获取指定对象
        else if ([MSG_NOTFOUND isEqual:type]) [self acceptNotFoundMessage:message];//对getdata消息的回应，如果要求的数据项不能被转发则发送该信息
        else if ([MSG_PING isEqual:type]) [self acceptPingMessage:message];//确认TCP/IP连接的可用性
        else if ([MSG_PONG isEqual:type]) [self acceptPongMessage:message];//回应ping消息
        else if ([MSG_MERKLEBLOCK isEqual:type]) [self acceptMerkleBlockMessage:message];//连接的Bloom过滤相关
        else if ([MSG_REJECT isEqual:type]) [self acceptRejectMessage:message];//拒绝消息
        else
            DDLogWarn(@"%@:%d dropping %@, length %u, not implemented", self.host, self.peerPort, type, (int) message.length);
    });
    CFRunLoopWakeUp([self.runLoop getCFRunLoop]);
}

- (void)acceptVersionMessage:(NSData *)message {
    NSUInteger l = 0;

    if (message.length < 85) {
        [self error:@"malformed version message, length is %u, should be > 84", (int) message.length];
        return;
    }

    _version = [message UInt32AtOffset:0];

    if (self.version < MIN_PROTO_VERSION) {
        [self error:@"protocol version %u not supported", self.version];
        return;
    }

    _peerServices = [message UInt64AtOffset:4];
    _peerTimestamp = [message UInt64AtOffset:12] - NSTimeIntervalSince1970;
    _userAgent = [message stringAtOffset:80 length:&l];

    if (message.length < 80 + l + sizeof(uint32_t)) {
        [self error:@"malformed version message, length is %u, should be %lu", (int) message.length, 80 + l + 4];
        return;
    }

    _versionLastBlock = [message UInt32AtOffset:80 + l];
    
    if (message.length < 80 + l + sizeof(uint32_t) + 1){
        _relayTxesBeforeFilter = YES;
    } else {
        _relayTxesBeforeFilter = ((Byte *) message.bytes)[80 + l + sizeof(uint32_t)] != 0;
        if(!self.canRelayTx){
            [self error:@"%@:%d can NOT relay tx, got version %d, useragent:\"%@\", %@", self.host, self.peerPort, self.version, self.userAgent];
            return;
        }
    }

    DDLogDebug(@"%@:%d got version %d, useragent:\"%@\", %@", self.host, self.peerPort, self.version, self.userAgent, self.canRelayTx ? @"can relay tx" : @"can NOT relay tx");
    
    if ((_peerServices & NODE_BITCOIN_CASH) == NODE_BITCOIN_CASH) {
        DDLogWarn(@"%@: Peer follows an incompatible block chain.", self);
        return;
    }
    
    [self sendVerAckMessage];//回应version
}

- (void)acceptVerAckMessage:(NSData *)message {
    if (self.gotVerAck) {
        DDLogWarn(@"%@:%d got unexpected verack", self.host, self.peerPort);
        return;
    }

    _pingTime = [NSDate timeIntervalSinceReferenceDate] - self.startTime; // use verack time as initial ping time
    self.startTime = 0;

    DDLogDebug(@"%@:%u got verack in %fs", self.host, self.peerPort, self.pingTime);
    [NSObject cancelPreviousPerformRequestsWithTarget:self]; // cancel pending verack timeout
    self.gotVerAck = YES;
    [self didConnect];
}

//NOTE: since we connect only intermitently, a hostile node could flush the address list with bad values that would take
// several minutes to clear, after which we would fall back on DNS seeding.
// TODO: keep around at least 1000 nodes we've personally connected to.
// TODO: relay addresses
- (void)acceptAddrMessage:(NSData *)message {
    if (message.length > 0 && [message UInt8AtOffset:0] == 0) {
        DDLogDebug(@"%@:%d got addr with 0 addresses", self.host, self.peerPort);
        return;
    }
    else if (message.length < 5) {
        [self error:@"malformed addr message, length %u is too short", (int) message.length];
        return;
    }

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSUInteger l, count = [message varIntAtOffset:0 length:&l];
    NSMutableArray *peers = [NSMutableArray array];

    if (count > 1000) {
        DDLogDebug(@"%@:%d dropping addr message, %u is too many addresses (max 1000)", self.host, self.peerPort, (int) count);
        return;
    }
    else if (message.length < l + count * 30) {
        [self error:@"malformed addr message, length is %u, should be %u for %u addresses", (int) message.length,
                    (int) (l + count * 30), (int) count];
        return;
    }
    else
        DDLogDebug(@"%@:%d got addr with %u addresses", self.host, self.peerPort, (int) count);

    for (NSUInteger off = l; off < l + 30 * count; off += 30) {
        NSTimeInterval timestamp = [message UInt32AtOffset:off] - NSTimeIntervalSince1970;
        uint64_t services = [message UInt64AtOffset:off + sizeof(uint32_t)];
        uint32_t address = CFSwapInt32BigToHost(*(const uint32_t *) ((const uint8_t *) message.bytes + off +
                sizeof(uint32_t) + 20));
        uint16_t port = CFSwapInt16BigToHost(*(const uint16_t *) ((const uint8_t *) message.bytes + off +
                sizeof(uint32_t) * 2 + 20));

        // if address time is more than 10 min in the future or older than reference date, set to 5 days old
        if (timestamp > now + 10 * 60 || timestamp < 0) timestamp = now - 5 * 24 * 60 * 60;

        // subtract two hours and add it to the list
        [peers addObject:[[BTPeer alloc] initWithAddress:address port:port timestamp:timestamp - 2 * 60 * 60
                                                services:services]];
    }

    if (_status == BTPeerStatusConnected) [self.delegate peer:self relayedPeers:peers];
}

- (void)acceptInvMessage:(NSData *)message {//处理inv消息
    NSUInteger l;
    uint64_t count = [message varIntAtOffset:0 length:&l];
    NSMutableOrderedSet *txHashes = [NSMutableOrderedSet orderedSet], *blockHashes = [NSMutableOrderedSet orderedSet];

    if (l == 0 || message.length < l + count * 36) {
        [self error:@"malformed inv message, length is %u, should be %u for %u items", (int) message.length,
                    (int) ((l == 0) ? 1 : l) + (int) count * 36, (int) count];
        return;
    }
    else if (count > MAX_GETDATA_HASHES) {
        DDLogDebug(@"%@:%u dropping inv message, %u is too many items, max is %d", self.host, self.peerPort, (int) count,
                MAX_GETDATA_HASHES);
        return;
    }
    if (!_bloomFilterSent) {
        DDLogDebug(@"%@:%d received inv. But we didn't send bloomfilter. Ignore", self.host, self.peerPort);
        return;
    }

    for (NSUInteger off = l; off < l + 36 * count; off += 36) {
        inv_t type = (inv_t) [message UInt32AtOffset:off];
        NSData *hash = [message hashAtOffset:off + sizeof(uint32_t)];

        if (!hash) continue;

        switch (type) {
            case tx:
                [txHashes addObject:hash];
                break;
            case block:
            case merkleblock:
                [blockHashes addObject:hash];
                break;
            default:
                break;
        }
    }

    DDLogDebug(@"%@:%u got inv with %u items %u tx %u block", self.host, self.peerPort, (int) count, (int) txHashes.count, (int) blockHashes.count);

    [blockHashes removeObjectsInArray:self.invBlockHashes];//移除已知的block

    if (txHashes.count > 10000) { // this was happening on testnet, some sort of DOS/spam attack?
        DDLogDebug(@"%@:%u too many transactions, disconnecting", self.host, self.peerPort);
        [self error:@"too many transactions"];
//        [self disconnectPeer]; // disconnecting seems to be the easiest way to mitigate it
        return;
    }
    // to improve chain download performance, if we received 500 block hashes, we request the next 500 block hashes
    // immediately before sending the getdata request
//    if (blockHashes.count >= 500) {
//        [self sendGetBlocksMessageWithLocators:@[blockHashes.lastObject, blockHashes.firstObject] andHashStop:nil];
//    }

    [self.invBlockHashes addObjectsFromArray:blockHashes.array];//添加最新块的哈希表

    [txHashes minusOrderedSet:self.knownTxHashes];//减去已知的交易哈希表
    [self.knownTxHashes unionOrderedSet:txHashes];//添加最新的交易哈希表

    [self sendGetBlocksDataNextPieceWith:txHashes.array];//发送getblockdata消息

    if (([BTPeerManager instance].downloadPeer == nil || [self isEqual:[BTPeerManager instance].downloadPeer]) && blockHashes.count == 1) {
        [self sendPingMessage];
    }

    if (blockHashes.count > 0) {
        [self increaseBlockNo:blockHashes.count];
    }
}

- (void)sendGetBlocksDataNextPiece;{
    [self sendGetBlocksDataNextPieceWith:[NSArray new]];
}

- (void)sendGetBlocksDataNextPieceWith:(NSArray *)txHashes;{
    NSArray *blockHashesPiece = [self.invBlockHashes subarrayWithRange:NSMakeRange(0, MIN(GET_BLOCK_DATA_PIECE_SIZE, [self.invBlockHashes count]))];//
    [self.invBlockHashes removeObjectsInArray:blockHashesPiece];

    if ([BTPeerManager instance].downloadPeer == nil || [self isEqual:[BTPeerManager instance].downloadPeer]) {
        [self sendGetDataMessageWithTxHashes:txHashes andBlockHashes:blockHashesPiece];
    } else if ([txHashes count] > 0) {
        [self sendGetDataMessageWithTxHashes:txHashes andBlockHashes:[NSArray new]];
    }
    if (blockHashesPiece.count > 0) {
        [self.currentBlockHashes addObjectsFromArray:blockHashesPiece];
        if (self.currentBlockHashes.count > MAX_GETDATA_HASHES) {
            [self.currentBlockHashes
                    removeObjectsInRange:NSMakeRange(0, self.currentBlockHashes.count - MAX_GETDATA_HASHES / 2)];
        }
        if (self.synchronising)
            [self.syncBlockHashes addObjectsFromArray:blockHashesPiece];
    }
}

- (void)increaseBlockNo:(int)blockCount; {
    if (self.synchronising) {
        _synchronisingBlockCount += blockCount;
    } else {
        _incrementalBlockHeight += blockCount;
    }
}

- (void)acceptTxMessage:(NSData *)message {//验证消息
    BTTx *tx = [BTTx transactionWithMessage:message];

    if (!tx) {
        [self error:@"malformed tx message: %@", message];
        return;
    }

    DDLogDebug(@"%@:%u got tx %@", self.host, self.peerPort, [NSString hexWithHash:tx.txHash]);

    if (self.currentBlock) { // we're collecting tx messages for a merkleblock我们正在为merkleblock收集tx消息
        if (_status == BTPeerStatusConnected) [self.delegate peer:self relayedTransaction:tx confirmed:YES];//验证交易
        [self.currentTxHashes removeObject:tx.txHash];

        if (self.currentTxHashes.count == 0) { // we received the entire block including all matched tx我们收到了整个区块，包括所有匹配的tx
            BTBlock *block = self.currentBlock;

            self.currentBlock = nil;
            self.currentTxHashes = nil;

            if (_status == BTPeerStatusConnected) {
                if (self.synchronising && [self.syncBlockHashes containsObject:block.blockHash]) {
                    [self.syncBlockHashes removeObject:block.blockHash];
                    [self.syncBlocks addObject:block];//添加到本地区块中
                    if (self.syncBlockHashes.count == 0 && self.syncBlocks.count > 0) {
                        [self.delegate peer:self relayedBlocks:self.syncBlocks];
                        [self.syncBlocks removeAllObjects];
                    } else if (self.syncBlocks.count >= RELAY_BLOCK_COUNT_WHEN_SYNC) {
                        [self.delegate peer:self relayedBlocks:self.syncBlocks];
                        [self.syncBlocks removeAllObjects];
                    }
                } else {
                    [self.delegate peer:self relayedBlock:block];//重组本地区块链
                }

            }
        }
    } else {
        if ([[BTAddressManager instance] isTxRelated:tx]) {
            _unrelatedTxRelayCount = 0;
        } else {
            _unrelatedTxRelayCount += 1;
            if (_unrelatedTxRelayCount > MAX_UNRELATED_TX_RELAY_COUNT) {
                [self disconnectWithError:[NSError errorWithDomain:@"primeri" code:ERR_PEER_RELAY_TO_MUCH_UNRELAY_TX
                                                          userInfo:@{NSLocalizedDescriptionKey : @"connect timeout"}]];
                return;
            }
        }

        BOOL valid = YES;
        valid &= [tx verify];
        if (valid && ![tx hasDustOut]) {
            if (_status == BTPeerStatusConnected) [self.delegate peer:self relayedTransaction:tx confirmed:NO];
//            [self checkDependencyWith:tx];
        }
        // do not check dependency now, may check it in future
        /*
        if (self.needToRequestDependencyDict[tx.txHash] == nil || ((NSArray *)self.needToRequestDependencyDict[tx.txHash]).count == 0) {
            if ([[BTAddressManager instance] isTxRelated:tx]) {
                _unrelatedTxRelayCount = 0;
            } else {
                _unrelatedTxRelayCount += 1;
                if (_unrelatedTxRelayCount > MAX_UNRELATED_TX_RELAY_COUNT) {
                    [self disconnectWithError:[NSError errorWithDomain:@"primeri" code:ERR_PEER_RELAY_TO_MUCH_UNRELAY_TX
                                                                              userInfo:@{NSLocalizedDescriptionKey : @"connect timeout"}]];
                    return;
                }
            }
        }

        // check dependency
        NSDictionary *dependency = [[BTTxProvider instance] getTxDependencies:tx];
        NSMutableArray *needToRequest = [NSMutableArray new];
        BOOL valid = YES;
        for (NSUInteger i = 0; i < tx.inputIndexes.count; i++) {
            BTTx *prevTx = dependency[tx.inputHashes[i]];
            if (prevTx == nil) {
                [needToRequest addObject:tx.inputHashes[i]];
            } else {
                if (prevTx.outs.count <= [tx.inputIndexes[i] unsignedIntegerValue]){
                    valid = NO;
                    break;
                }
                NSData *outScript = ((BTOut *)prevTx.outs[[tx.inputIndexes[i] unsignedIntegerValue]]).outScript;
                BTScript *pubKeyScript = [[BTScript alloc] initWithProgram:outScript];
                BTScript *script = [[BTScript alloc] initWithProgram:tx.inputSignatures[i]];
                script.tx = tx;
                script.index = i;
                valid &= [script correctlySpends:pubKeyScript and:YES];

                if (!valid)
                    break;
            }
        }
        valid &= [tx verify];
        if (valid && needToRequest.count == 0) {
            if (_status == BTPeerStatusConnected) [self.delegate peer:self relayedTransaction:tx];
            [self checkDependencyWith:tx];
        } else if (valid && needToRequest.count > 0) {
            for (NSData *txHash in needToRequest) {
                if (self.needToRequestDependencyDict[txHash] == nil) {
                    NSMutableArray *txs = [NSMutableArray new];
                    [txs addObject:tx];
                    self.needToRequestDependencyDict[txHash] = txs;
                } else {
                    NSMutableArray *txs = self.needToRequestDependencyDict[txHash];
                    [txs addObject:tx];
                }
            }
            [self sendGetDataMessageWithTxHashes:needToRequest andBlockHashes:@[]];
        }
        */
    }
}

- (void)checkDependencyWith:(BTTx *)tx; {//检查tx是否有效
    NSArray *needCheckDependencyTxs = self.needToRequestDependencyDict[tx.txHash];
    if (needCheckDependencyTxs == nil) {
        return;
    } else {
        [self.needToRequestDependencyDict removeObjectForKey:tx.txHash];
    }
    NSMutableArray *invalidTxs = [NSMutableArray new];
    NSMutableArray *checkedTxs = [NSMutableArray new];
    for (BTTx *eachTx in needCheckDependencyTxs) {
        BOOL valid = YES;
        for (BTIn *btIn in eachTx.ins) {
            if ([btIn.prevTxHash isEqualToData:tx.txHash]) {
                if ([tx getOut:btIn.prevOutSn] != nil) {
                    BTOut *out = [tx getOut:btIn.prevOutSn];
                    NSData *outScript = out.outScript;
                    BTScript *pubKeyScript = [[BTScript alloc] initWithProgram:outScript];
                    BTScript *script = [[BTScript alloc] initWithProgram:btIn.inSignature];
                    script.tx = eachTx;
                    script.index = btIn.prevOutSn;
                    valid &= [script correctlySpends:pubKeyScript and:YES];
                } else {
                    valid = NO;
                }
                if (!valid)
                    break;
            }
        }
        if (valid) {
            BOOL stillNeedDependency = NO;
            for (NSArray *array in self.needToRequestDependencyDict.allValues) {
                if ([array containsObject:eachTx]) {
                    stillNeedDependency = YES;
                    break;
                }
            }
            if (!stillNeedDependency) {
                if (_status == BTPeerStatusConnected) [self.delegate peer:self relayedTransaction:eachTx confirmed:NO];
                [checkedTxs addObject:eachTx];
            }
        } else {
            [invalidTxs addObject:eachTx];
        }
    }
    for (BTTx *eachTx in invalidTxs) {
        DDLogWarn(@"%@:%u tx:[%@] is invalid.", self.host, self.peerPort, [NSString hexWithHash:eachTx.txHash]);
        [self clearInvalidTxFromDependencyDict:eachTx];
    }
    for (BTTx *eachTx in checkedTxs) {
        [self checkDependencyWith:eachTx];
    }
}

- (void)checkDependencyWithNotFoundMsg:(NSData *)txHash; {
    // when receive not found msg, we consider this tx is confirmed.
    NSArray *needCheckDependencyTxs = self.needToRequestDependencyDict[txHash];
    if (needCheckDependencyTxs == nil) {
        return;
    } else {
        [self.needToRequestDependencyDict removeObjectForKey:txHash];
    }
    NSMutableArray *checkedTxs = [NSMutableArray new];
    for (BTTx *eachTx in needCheckDependencyTxs) {
        BOOL stillNeedDependency = NO;
        for (NSArray *array in self.needToRequestDependencyDict.allValues) {
            if ([array containsObject:eachTx]) {
                stillNeedDependency = YES;
                break;
            }
        }
        if (!stillNeedDependency) {
            if (_status == BTPeerStatusConnected) [self.delegate peer:self relayedTransaction:eachTx confirmed:NO];
            [checkedTxs addObject:eachTx];
        }
    }
    for (BTTx *eachTx in checkedTxs) {
        [self checkDependencyWith:eachTx];
    }
}

- (void)clearInvalidTxFromDependencyDict:(BTTx *)tx; {
    for (NSMutableArray *array in self.needToRequestDependencyDict.allValues) {
        if ([array containsObject:tx]) {
            [array removeObject:tx];
        }
    }
    NSArray *subTxs = self.needToRequestDependencyDict[tx.txHash];
    if (subTxs != nil) {
        [self.needToRequestDependencyDict removeObjectForKey:tx.txHash];
        for (BTTx *eachTx in subTxs) {
            [self clearInvalidTxFromDependencyDict:eachTx];
        }
    }
}

- (void)acceptHeadersMessage:(NSData *)message {
    NSUInteger l, count = (NSUInteger) [message varIntAtOffset:0 length:&l], off;
    
    if (message.length < l + 81 * count) {
        [self error:@"malformed headers message, length is %u, should be %u for %u items", (int) message.length,
         (int) ((l == 0) ? 1 : l) + (int) count * 81, (int) count];
        return;
    }
    
    // To improve chain download performance, if this message contains 2000 headers then request the next 2000 headers
    // immediately, and switching to requesting blocks when we receive a header newer than earliestKeyTime
    
    
    DDLogDebug(@"%@:%u got %u headers", self.host, self.peerPort, (int) count);
    
    // schedule this on the runloop to ensure the above get message is sent first for faster chain download
    CFRunLoopPerformBlock([self.runLoop getCFRunLoop], kCFRunLoopCommonModes, ^{
        NSMutableArray *headers = [NSMutableArray new];
        for (NSUInteger off = l; off < message.length; off += 81) {
            BTBlock *block = [BTBlock blockWithMessage:[message subdataWithRange:NSMakeRange(off, message.length-off)]];
            off +=block.bigNumLen+1;
//            if (!block.valid) {
//                [self error:@"invalid block header %@", [NSString hexWithHash:block.blockHash]];
//                return;
//            }
            [headers addObject:block];
        }
        if (headers.count == count) {
            NSMutableData *data1 = [NSMutableData data];
            NSMutableData *data2 = [NSMutableData data];
            for (int i= 31; i>=0; i--) {
                [data1 appendData:[[[headers objectAtIndex:0] blockHash] subdataWithRange:NSMakeRange(i, 1)]];
                [data2 appendData:[[[headers objectAtIndex:headers.count-1] blockHash] subdataWithRange:NSMakeRange(i, 1)]];
            }
            NSData *firstHash = data1,
            *lastHash = data2;
            [self sendGetHeadersMessageWithLocators:@[lastHash, firstHash] andHashStop:nil];
        }
        if (self->_status == BTPeerStatusConnected)
            [self.delegate peer:self relayedHeaders:headers];
    });
    CFRunLoopWakeUp([self.runLoop getCFRunLoop]);
}

- (void)acceptGetAddrMessage:(NSData *)message {
    DDLogDebug(@"%@:%u got getaddr", self.host, self.peerPort);

    [self sendAddrMessage];//回应headers
}

- (void)acceptGetDataMessage:(NSData *)message {
    NSUInteger l, count = (NSUInteger) [message varIntAtOffset:0 length:&l];

    if (l == 0 || message.length < l + count * 36) {
        [self error:@"malformed getdata message, length is %u, should be %u for %u items", (int) message.length,
                    (int) ((l == 0) ? 1 : l) + (int) count * 36, (int) count];
        return;
    }
    else if (count > MAX_GETDATA_HASHES) {
        DDLogWarn(@"%@:%u dropping getdata message, %u is too many items, max is %d", self.host, self.peerPort, (int) count,
                MAX_GETDATA_HASHES);
        return;
    }

    DDLogDebug(@"%@:%u got getdata with %u items", self.host, self.peerPort, (int) count);

    NSMutableData *notFound = [NSMutableData data];

    for (NSUInteger off = l; off < l + count * 36; off += 36) {
        inv_t type = [message UInt32AtOffset:off];
        NSData *hash = [message hashAtOffset:off + sizeof(uint32_t)];
        BTTx *transaction = nil;

        if (!hash) continue;

        switch (type) {
            case tx:
                transaction = [self.delegate peer:self requestedTransaction:hash];

                if (transaction) {
                    [self sendMessage:[transaction toData] type:MSG_TX];
                    break;
                }

                // fall through
            default:
                [notFound appendUInt32:type];
                [notFound appendData:hash];
                break;
        }
    }

    if (notFound.length > 0) {
        NSMutableData *msg = [NSMutableData data];

        [msg appendVarInt:notFound.length / 36];
        [msg appendData:notFound];
        [self sendMessage:msg type:MSG_NOTFOUND];//发送“没有获取相匹配的数据”
    }
}

- (void)acceptNotFoundMessage:(NSData *)message {
    NSUInteger l, count = [message varIntAtOffset:0 length:&l];

    if (l == 0 || message.length < l + count * 36) {
        [self error:@"malformed notfount message, length is %u, should be %u for %u items", (int) message.length,
                    (int) ((l == 0) ? 1 : l) + (int) count * 36, (int) count];
        return;
    }
    for (NSUInteger off = l; off < l + count * 36; off += 36) {
        inv_t type = [message UInt32AtOffset:off];
        NSData *hash = [message hashAtOffset:off + sizeof(uint32_t)];
        if (type == tx) {
            [self checkDependencyWithNotFoundMsg:hash];
        }
    }

    DDLogDebug(@"%@:%u got notfound with %u items", self.host, self.peerPort, (int) count);
}

- (void)acceptPingMessage:(NSData *)message {
    if (message.length < sizeof(uint64_t)) {
        [self error:@"malformed ping message, length is %u, should be 4", (int) message.length];
        return;
    }

    DDLogDebug(@"%@:%u got ping", self.host, self.peerPort);

    [self sendMessage:message type:MSG_PONG];
}

- (void)acceptPongMessage:(NSData *)message {
    if (message.length < sizeof(uint64_t)) {
        [self error:@"malformed pong message, length is %u, should be 4", (int) message.length];
        return;
    }
    else if ([message UInt64AtOffset:0] != self.localNonce) {
        [self error:@"pong message contained wrong nonce: %llu, expected: %llu", [message UInt64AtOffset:0],
                    self.localNonce];
        return;
    }
    else if (self.startTime < 1) {
        DDLogDebug(@"%@:%d got unexpected pong", self.host, self.peerPort);
        return;
    }

    NSTimeInterval pingTime = [NSDate timeIntervalSinceReferenceDate] - self.startTime;

    // 50% low pass filter on current ping time
    _pingTime = self.pingTime * 0.5 + pingTime * 0.5;
    self.startTime = 0;

    DDLogDebug(@"%@:%u got pong in %fs", self.host, self.peerPort, self.pingTime);
}

- (void)acceptMerkleBlockMessage:(NSData *)message {
    // Bitcoin nodes don't support querying arbitrary transactions, only transactions not yet accepted in a block. After
    // a merkle block message, the remote node is expected to send tx messages for the tx referenced in the block. When a
    // non-tx message is received we should have all the tx in the merkle block.

    BTBlock *block = [BTBlock blockWithMessage:message];

//    if (!block.valid) {
//        [self error:@"invalid merkleblock: %@", [NSString hexWithHash:block.blockHash]];
//        return;
//    }
//    else {
//        DDLogDebug(@"%@:%u got merkleblock %@ %lu txs", self.host, self.peerPort, [NSString hexWithHash:block.blockHash], (unsigned long) block.txHashes.count);
//    }

    [self.currentBlockHashes removeObject:block.blockHash];//添加获取到的blockhash
    [self.requestedBlockHashes removeObject:block.blockHash];
    if ([self.requestedBlockHashes countForObject:block.blockHash] > 0) {
        // block was refetched, drop this one
        DDLogDebug(@"%@:%d dropping refetched block %@", self.host, self.peerPort, [NSString hexWithHash:block.blockHash]);
        return;
    }

    NSMutableOrderedSet *txHashes = [NSMutableOrderedSet orderedSetWithArray:block.txHashes];

//    [txHashes minusOrderedSet:self.knownTxHashes];

    // wait util we get all the tx messages before processing the block
    if (txHashes.count > 0) {
        self.currentBlock = block;
        self.currentTxHashes = txHashes;
    }
    else {
        if (_status == BTPeerStatusConnected) {
            if (self.synchronising && [self.syncBlockHashes containsObject:block.blockHash]) {
                [self.syncBlockHashes removeObject:block.blockHash];
                [self.syncBlocks addObject:block];
                if (self.syncBlockHashes.count == 0 && self.syncBlocks.count > 0) {
                    [self.delegate peer:self relayedBlocks:self.syncBlocks];
                    [self.syncBlocks removeAllObjects];
                } else if (self.syncBlocks.count >= RELAY_BLOCK_COUNT_WHEN_SYNC) {
                    [self.delegate peer:self relayedBlocks:self.syncBlocks];
                    [self.syncBlocks removeAllObjects];
                }
            } else {
                [self.delegate peer:self relayedBlock:block];
            }
        }
    }
    if (self.currentBlockHashes.count == 0) {
        BOOL waitingLogged = NO;
        while ([[BTPeerManager instance] waitingTaskCount] > MAX_PEER_MANAGER_WAITING_TASK_COUNT) {
            if (!waitingLogged) {
                DDLogDebug(@"%@:%u waiting for PeerManager task count %d", self.host, self.peerPort, [[BTPeerManager instance] waitingTaskCount]);
                waitingLogged = YES;
            }
            [NSThread sleepForTimeInterval:PEER_MANAGER_MAX_TASK_CHECKING_INTERVAL];
        }
        if (self.invBlockHashes.count > 0) {
            [self sendGetBlocksDataNextPiece];
        } else {
            [self sendGetBlocksMessageWithLocators:@[block.blockHash, [BTBlockChain instance].blockLocatorArray.firstObject] andHashStop:nil];
        }
    }
}

// described in BIP61: https://gist.github.com/gavinandresen/7079034
- (void)acceptRejectMessage:(NSData *)message {
    NSUInteger off = 0, l = 0;
    NSString *type = [message stringAtOffset:0 length:&off];
    uint8_t code = [message UInt8AtOffset:off++];
    NSString *reason = [message stringAtOffset:off length:&l];
    NSData *txHash = ([MSG_TX isEqual:type]) ? [message hashAtOffset:off + l] : nil;

    NSLog(@"%@:%u rejected %@ code: 0x%x reason: \"%@\"%@%@", self.host, self.peerPort, type, code, reason,
            txHash ? @" txid: " : @"", txHash ? [NSString hexWithHash:txHash] : @"");
}

#pragma mark - hash

#define FNV32_PRIME  0x01000193u
#define FNV32_OFFSET 0x811C9dc5u

// FNV32-1a hash of the ip address and port number: http://www.isthe.com/chongo/tech/comp/fnv/index.html#FNV-1a
- (NSUInteger)hash {
    uint32_t hash = FNV32_OFFSET;

    hash = (hash ^ ((self.peerAddress >> 24) & 0xff)) * FNV32_PRIME;
    hash = (hash ^ ((self.peerAddress >> 16) & 0xff)) * FNV32_PRIME;
    hash = (hash ^ ((self.peerAddress >> 8) & 0xff)) * FNV32_PRIME;
    hash = (hash ^ (self.peerAddress & 0xff)) * FNV32_PRIME;
    hash = (hash ^ ((self.peerPort >> 8) & 0xff)) * FNV32_PRIME;
    hash = (hash ^ (self.peerPort & 0xff)) * FNV32_PRIME;

    return hash;
}

// two peer objects are equal if they share an ip address and port number
- (BOOL)isEqual:(id)object {
    return self == object || ([object isKindOfClass:[BTPeer class]] && self.peerAddress == [(BTPeer *) object peerAddress]);
}

#pragma mark - NSStreamDelegate//socket代理

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
    switch (eventCode) {
        case NSStreamEventOpenCompleted://建立连接完成
            DDLogDebug(@"%@:%d %@ stream connected in %fs", self.host, self.peerPort,
                    aStream == self.inputStream ? @"input" : aStream == self.outputStream ? @"output" : @"unkown",
                    [NSDate timeIntervalSinceReferenceDate] - self.startTime);

            if (aStream == self.outputStream) {
                self.startTime = [NSDate timeIntervalSinceReferenceDate]; // don't count connect time in ping time
                [self refreshCheckTimeOut];
            }

            // fall through to send any queued output
        case NSStreamEventHasSpaceAvailable:// 可以使用输出流的空间，此时可以发送数据给服务器
            if (aStream != self.outputStream) return;

            //如果消息有内容 消息输出有空间 开始发送消息，之后剔除发送过的消息
            while (self.outputBuffer.length > 0 && [self.outputStream hasSpaceAvailable]) {
                NSInteger l = [self.outputStream write:self.outputBuffer.bytes maxLength:self.outputBuffer.length];

                if (l > 0) [self.outputBuffer replaceBytesInRange:NSMakeRange(0, l) withBytes:NULL length:0];
//                if (self.outputBuffer.length == 0) DDLogDebug(@"%@:%d output buffer cleared", self.host, self.peerPort);
            }

            break;

        case NSStreamEventHasBytesAvailable:// 有可读的字节，接收到了数据，可以读了
            if (aStream != self.inputStream) return;

            while ([self.inputStream hasBytesAvailable]) {
                NSData *message = nil;
                NSString *type = nil;
                NSInteger headerLen = self.msgHeader.length, payloadLen = self.msgPayload.length, l = 0;
                uint32_t length = 0, checksum = 0;

                if (headerLen < HEADER_LENGTH) { // 读取消息头
                    self.msgHeader.length = HEADER_LENGTH;
                    l = [self.inputStream read:(uint8_t *) self.msgHeader.mutableBytes + headerLen
                                     maxLength:self.msgHeader.length - headerLen];

                    if (l < 0) {
                        DDLogDebug(@"%@:%u error reading message", self.host, self.peerPort);
                          goto reset;
                    }

                    self.msgHeader.length = headerLen + l;

                    // consume one byte at a time, up to the magic number that starts a new message header
                    //一次消耗一个字节，直到启动新消息头的幻数
                    while (self.msgHeader.length >= sizeof(uint32_t) &&
                            [self.msgHeader UInt32AtOffset:0] != BITCOIN_MAGIC_NUMBER) {
#if DEBUG
                        printf("%c", *(const char *) self.msgHeader.bytes);
#endif
                        [self.msgHeader replaceBytesInRange:NSMakeRange(0, 1) withBytes:NULL length:0];
                    }

                    if (self.msgHeader.length < HEADER_LENGTH) continue; // wait for more stream input
                }

                if ([self.msgHeader UInt8AtOffset:15] != 0) { // verify msg type field is null terminated验证msg类型字段为空终止
                    [self error:@"malformed message header: %@", self.msgHeader];
                    goto reset;
                }

                type = [NSString stringWithUTF8String:(const char *) self.msgHeader.bytes + 4];
                length = [self.msgHeader UInt32AtOffset:16];
                checksum = [self.msgHeader UInt32AtOffset:20];

                if (length > MAX_MSG_LENGTH) { // check message length
                    [self error:@"error reading %@, message length %u is too long", type, length];
                    goto reset;
                }

                if (payloadLen < length) { // read message payload读取消息的有效载荷
                    self.msgPayload.length = length;
                    l = [self.inputStream read:(uint8_t *) self.msgPayload.mutableBytes + payloadLen
                                     maxLength:self.msgPayload.length - payloadLen];

                    if (l < 0) {
                        DDLogError(@"%@:%u error reading %@", self.host, self.peerPort, type);
                        goto reset;
                    }

                    self.msgPayload.length = payloadLen + l;
                    if (self.msgPayload.length < length) continue; // wait for more stream input
                }

                if (*(const uint32_t *) self.msgPayload.SHA256_2.bytes != checksum) { // verify checksum
                    [self error:@"error reading %@, invalid checksum %x, expected %x, payload length:%u, expected "
                                        "length:%u, SHA256_2:%@", type, *(const uint32_t *) self.msgPayload.SHA256_2.bytes, checksum,
                                (int) self.msgPayload.length, length, self.msgPayload.SHA256_2];
                    goto reset;
                }

                message = self.msgPayload;
                self.msgPayload = [NSMutableData data];
                [self acceptMessage:message type:type]; // process message处理消息

                reset:          // reset for next message
                self.msgHeader.length = self.msgPayload.length = 0;
            }

            break;

        case NSStreamEventErrorOccurred:// 发生错误
            DDLogWarn(@"%@:%u error connecting, %@", self.host, self.peerPort, aStream.streamError);
            [self disconnectWithError:aStream.streamError];
            break;

        case NSStreamEventEndEncountered:// 流结束事件，在此事件中负责做销毁工作
            DDLogWarn(@"%@:%u connection closed", self.host, self.peerPort);
            [self disconnectWithError:nil];
            break;

        default:
            DDLogWarn(@"%@:%u unknown network stream eventCode:%u", self.host, self.peerPort, (int) eventCode);
    }
}

#pragma mark - help method

- (void)checkTimeOut {
    [self performSelector:@selector(disconnectWithError:)
               withObject:[NSError errorWithDomain:@"primeri" code:ERR_PEER_TIMEOUT_CODE
                                          userInfo:@{NSLocalizedDescriptionKey : @"connect timeout"}]
               afterDelay:CONNECT_TIMEOUT];
}

- (void)refreshCheckTimeOut {
    [NSObject cancelPreviousPerformRequestsWithTarget:self]; // cancel pending socket connect timeout
    [self checkTimeOut];
}

- (void)connectFail; {
    [[BTPeerProvider instance] removePeer:self.peerAddress];
}

- (void)connectSucceed; {
    self.peerConnectedCnt = 1;
    self.timestamp = [[NSDate new] timeIntervalSinceReferenceDate];
    [[BTPeerProvider instance] connectSucceed:self.peerAddress];
}

- (void)connectError; {
    [[BTPeerProvider instance] removePeer:self.peerAddress];
}

- (uint32_t)displayLastBlock {
    return self.versionLastBlock + _incrementalBlockHeight;
}

- (BOOL)relayTxesBeforeFilter{
    return _relayTxesBeforeFilter;
}

- (BOOL)canRelayTx{
    return self.relayTxesBeforeFilter;
}
@end
