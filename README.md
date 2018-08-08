# 代理投票

## 需求

实现一个带有代理功能的投票的智能合约。

## 思路

为了支持投票，我们首先要有进行投票的提案，每个提案都会有名字和投票的计数。针对每个投票者，我们可以设置它是否进行了投票，以及投票给谁。

难点在于如何设计代理机制，我们可以给一个人指定一个代理人。但是这里有一个陷阱，因为这个代理人可能也设置了另一个代理人，因此我们需要不断地找到最初的代理人。

如果我们能够在系统中不断的更新代理人和投票，那么情况会变得更加复杂，这里我们首先是实现一个设置后不会更新的情况。

谁能够管理投票者呢？我们需要设置一个主席来管理整个投票者的状态。

于是整个流程如下：

- 基于一系列的提案创建一个投票的智能合约
- 主席可以添加多个投票人
- 每个投票人可以自己投票，或者让他人代理自己
- 我们可以统计当前最高票的提案

### 代码注解

```solidity
pragma solidity ^0.4.22;

/// @title 带有代理功能的投票协约
contract Ballot {
    // 表示一个投票人
    struct Voter {
        uint weight; // 通过代理积累权重
        bool voted;  // 是否已经投过票了？
        address delegate; // 他的代理人
        uint vote;   // 选择的提案的编号
    }

    // 表示一个提案
    struct Proposal {
        bytes32 name;   // 提案名（最多32个字符）
        uint voteCount; // 积累的投票数量
    }

    address public chairperson; // 主席

    // 保存从地址到投票人数据的映射
    mapping(address => Voter) public voters;

    // 保存提案的数组
    Proposal[] public proposals;

    /// 构建函数：基于一组提案，构建一个投票协约
    function Ballot(bytes32[] proposalNames) public {
        chairperson = msg.sender; // 协约创建人是主席
        voters[chairperson].weight = 1; // 创建人的投票权重是1

        // 针对每一个提案名，创建一个对应的提案，并且保存在Proposal中
        for (uint i = 0; i < proposalNames.length; i++) {
            // `Proposal({...})` 创建一个临时的对象
            // `proposals.push(...)` 会复制这个对象并且永久保存在proposals中
            proposals.push(Proposal({
                name: proposalNames[i],
                voteCount: 0
            }));
        }
    }

    // 主席给予一个人投票的权利
    function giveRightToVote(address voter) public {
        // 如果require的执行失败，则会终止程序，之前的所有修改都会被还原
        // 在历史的EVM版本中，这会消耗所有的gas，但现在已经被取消
        // 建议使用Require来检查函数的正确性和安全性
        // 可以选择传入第二个参数，对错误加以解释
        require(
            msg.sender == chairperson,
            "Only chairperson can give right to vote."
        );
        require(
            !voters[voter].voted,
            "The voter already voted."
        );
        require(voters[voter].weight == 0); // 注意，这里并没有创建voters[voter]
        voters[voter].weight = 1;
    }

    /// 把你的投票权代理给另一个人
    function delegate(address to) public {
        // 获得当前用户持久数据的引用
        Voter storage sender = voters[msg.sender];
        require(!sender.voted, "You already voted.");

        require(to != msg.sender, "Self-delegation is disallowed."); // 不能自己代理自己

        // 因为被代理人也可能找人代理，因此要找到最初的代理人
        // 这个循环可能很危险，因为执行时间可能很长，从而消耗大量的gas
        // 当gas被耗尽，将无法代理
        while (voters[to].delegate != address(0)) {
            to = voters[to].delegate;

            // 防止出现循环，但是并没有检查不包含sender的loop，也许不会出现呢：）
            require(to != msg.sender, "Found loop in delegation.");
        }

        // 因为sender是引用传递，因此会修改全局变量voters[msg.sender]的值
        sender.voted = true;
        sender.delegate = to;
        Voter storage delegate_ = voters[to];
        if (delegate_.voted) {
            // 如果已经投票了，增加提案的权重；QY：这里最好也能增加代理人权重
            proposals[delegate_.vote].voteCount += sender.weight;
        } else {
            // 如果没有投票，增加代理人的权重
            delegate_.weight += sender.weight;
        }
    }

    /// 进行投票
    function vote(uint proposal) public {
        Voter storage sender = voters[msg.sender];
        require(!sender.voted, "Already voted.");
        sender.voted = true;
        sender.vote = proposal;

        // 如果proposals的数组越界，会自动失败，并且还原变化
        proposals[proposal].voteCount += sender.weight;
    }

    /// @dev 计算胜出的提案，QY：如果都是0怎么办？
    function winningProposal() public view
            returns (uint winningProposal_)
    {
        uint winningVoteCount = 0;
        for (uint p = 0; p < proposals.length; p++) {
            if (proposals[p].voteCount > winningVoteCount) {
                winningVoteCount = proposals[p].voteCount;
                winningProposal_ = p;
            }
        }
    }

    // 找到胜出的提案，然后返回胜出的名字
    function winnerName() public view
            returns (bytes32 winnerName_)
    {
        winnerName_ = proposals[winningProposal()].name;
    }
}

```

我们如何支持更新代理人的情况呢？需要考虑对应的票数的变化和代理人之间关系的更改。

## 总结

- 投票方案、提案、投票者、主席四个核心概念的互动实现了智能投票
- 主席类似于管理者，推动合约的进行
- 每个投票者都可以自己投票或者让他人代理
- 我们依然没有支持动态变化的情况



------



# 公开拍卖

## 需求

请实现一个拍卖协议，在该协议中，每个用户可以提交自己的出价。如果有人出价高于当前的最高价，那么我们将会退还之前的最高价的人的金额，然后将新的最高价记录在智能合约中。

## 思路

整个流程如下：

- 我们首先要记录拍卖的基本数据：谁是受益人，什么时候结束
- 我们开启拍卖，一个出价更高的人会替代之前出价最高的人
- 当出现替代时，还要退还之前出价高的人的代币
- 出于安全的考虑，退还过程将由之前用户主动发起

### 代码注解

```solidity
pragma solidity ^0.4.22;

contract SimpleAuction {
    // 拍卖的参数
    address public beneficiary; // 拍卖的受益人
    uint public auctionEnd; // 拍卖的结束时间


    address public highestBidder; // 当前的最高出价者
    uint public highestBid; // 当前的最高出价

    mapping(address => uint) pendingReturns; // 用于取回之前的出价

    bool ended; // 拍卖是否结束

    // 发生变化时的事件
    event HighestBidIncreased(address bidder, uint amount); // 出现新的最高价
    event AuctionEnded(address winner, uint amount); // 拍卖结束

    // The following is a so-called natspec comment,
    // recognizable by the three slashes.
    // It will be shown when the user is asked to
    // confirm a transaction.

    /// 创建一个拍卖，参数为拍卖时长和受益人
    function SimpleAuction(
        uint _biddingTime,
        address _beneficiary
    ) public {
        beneficiary = _beneficiary;
        auctionEnd = now + _biddingTime;
    }

    /// 使用代币来进行拍卖
    /// 当拍卖失败时，会退回代币
    function bid() public payable {
        // 不需要参数，因为都被自动处理了
        // 当一个函数要处理Ether时，需要包含payable的修饰符

        // 如果超过了截止期，交易撤回
        require(
            now <= auctionEnd,
            "Auction already ended."
        );

        // 如果出价不够，交易撤回
        require(
            msg.value > highestBid,
            "There already is a higher bid."
        );

        if (highestBid != 0) {
            // 调用highestBidder.send(highestBid)的方式是危险的
            // 因为会执行不知道的协议
            // 因此最好让用户自己取回自己的代币
            pendingReturns[highestBidder] += highestBid;
        }
        highestBidder = msg.sender;
        highestBid = msg.value;
        emit HighestBidIncreased(msg.sender, msg.value);
    }

    /// 取回被超出的拍卖前的出资
    function withdraw() public returns (bool) {
        uint amount = pendingReturns[msg.sender];
        if (amount > 0) {
            // 需要提前设置为0，因为接收者可以在这个函数结束前再次调用它
            pendingReturns[msg.sender] = 0;

            if (!msg.sender.send(amount)) {
                // 不需要throw，直接重制代币数量即可
                pendingReturns[msg.sender] = amount;
                return false;
            }
        }
        return true;
    }

    /// 结束拍卖，将金额给予受益人
    function auctionEnd() public {
        // 与其他协议交互的最好遵循以下顺序的三个步骤：
        // 1. 检查状况
        // 2. 修改状态
        // 3. 合约交互
        // 如果这三个步骤混在一起，那么攻击者可能通过多次调用这个函数来进行攻击

        // 1. 检查状况
        require(now >= auctionEnd, "Auction not yet ended.");
        require(!ended, "auctionEnd has already been called.");

        // 2. 修改状态
        ended = true;
        emit AuctionEnded(highestBidder, highestBid);

        // 3. 合约交互
        beneficiary.transfer(highestBid);
    }
}
```

## 总结

- 安全合约核心三步骤：检查状态、修改状态、合约交互

- 通过标记返还代币的方式，实现了安全的代币返还

- 通过拍卖状态，规避了多次取现的风险

  

------



# 密封拍卖

## 需求

请实现一个拍卖协议，在该协议中，每个用户可以提交自己的出价。但是用户之间不能看到之间的出价，最后出价最高的人获得拍卖。

## 思路

如何才能让大家互相看不到出价呢？我们可以让每个人把自己的出价加密一下，然后在一段时间内大家都给出加密后的出价。再出价结束后，给出一段时间让大家揭示自己的出价，并且从中选择最高的出价。

但是，我们依然可以从你传递的代币的数量判断你的出价。因此我们一个方案是大家只是支付定金，最后要补上全额。但是这个问题是，大家可以根据已经展示的用户的出价来判断自己是否展示自己的出价。

那么我们需要设计更加复杂的出价方案。一个方法是每个人都需要把自己的出价高于一个真实的出价值。同时允许用户虚假的出价，来混淆视听。但是这个都需要用户在揭秘的时候，得到属于自己的出价。

因此，具体的流程是：

- 进入出价时刻
  - 每个人可以提交自己的出价
  - 大家可以通过标记fake来给出虚假的出价，用户只需要传递的是出价的一个hash
- 进入展示时刻
  - 每个人给出自己之前提交的hash对应的真实出价列表
  - 针对有效的出价，我们进行核算，选出胜者，退换押金

### 代码注解

```solidity
pragma solidity ^0.4.22;

// 密封拍卖协议
contract BlindAuction {
    struct Bid {
        bytes32 blindedBid;
        uint deposit;
    }

    address public beneficiary; // 受益人
    uint public biddingEnd; // 出价结束时间
    uint public revealEnd; // 揭示价格结束时间
    bool public ended; // 拍卖是否结束

    mapping(address => Bid[]) public bids; // 地址到竞标之间的映射

    address public highestBidder; // 最高出价者
    uint public highestBid;  // 最高出价

    // 允许撤回没有成功的出价
    mapping(address => uint) pendingReturns;

    event AuctionEnded(address winner, uint highestBid);  // 拍卖结束的事件

    /// 修饰符主要用于验证输入的正确定
    /// onlyBefore和onlyAfter用于验证是否大于或者小于一个时间点
    /// 其中`_`是原始程序开始执行的地方
    modifier onlyBefore(uint _time) { require(now < _time); _; }
    modifier onlyAfter(uint _time) { require(now > _time); _; }

    // 构建函数：保存受益人、竞标结束时间、公示价格结束时间
    function BlindAuction(
        uint _biddingTime,
        uint _revealTime,
        address _beneficiary
    ) public {
        beneficiary = _beneficiary;
        biddingEnd = now + _biddingTime;
        revealEnd = biddingEnd + _revealTime;
    }

    /// 给出一个秘密出价 _blindedBid = keccak256(value, fake, secret)
    /// 给出的保证金只在出价正确时给予返回
    /// 有效的出价要求出价的ether至少到达value，并且fake不是true
    /// 设置fake为true，并且给出一个错误的出价可以隐藏真实的出价
    /// 一个地址能够多次出价
    /// QY：如果是我的话，我会限制必须一个人的出价都是有效的才有进一步的操作，从而增加造假的难度
    function bid(bytes32 _blindedBid)
        public
        payable
        onlyBefore(biddingEnd)
    {
        bids[msg.sender].push(Bid({
            blindedBid: _blindedBid,
            deposit: msg.value
        }));
    }

    /// 公示你的出价，对于正确参与的出价，只要没有最终获胜，都会被归还
    function reveal(
        uint[] _values,
        bool[] _fake,
        bytes32[] _secret
    )
        public
        onlyAfter(biddingEnd)
        onlyBefore(revealEnd)
    {
        uint length = bids[msg.sender].length;
        require(_values.length == length);
        require(_fake.length == length);
        require(_secret.length == length);

        uint refund;
        for (uint i = 0; i < length; i++) {
            var bid = bids[msg.sender][i];
            var (value, fake, secret) =
                    (_values[i], _fake[i], _secret[i]);
            if (bid.blindedBid != keccak256(value, fake, secret)) {
                // bid不正确，不会退回押金
                continue;
            }
            refund += bid.deposit;
            if (!fake && bid.deposit >= value) { // 处理bid超过value的情况
                if (placeBid(msg.sender, value))
                    refund -= value;
            }
            // 防止再次claim押金
            bid.blindedBid = bytes32(0);
        }
        msg.sender.transfer(refund); // 如果之前没有置0，会有fallback风险
    }

    // 这是个内部函数，只能被协约本身调用
    function placeBid(address bidder, uint value) internal
            returns (bool success)
    {
        if (value <= highestBid) {
            return false;
        }
        if (highestBidder != 0) {
            // 返回押金给之前出价最高的人
            pendingReturns[highestBidder] += highestBid;
        }
        highestBid = value;
        highestBidder = bidder;
        return true;
    }

    /// 撤回过多的出价
    function withdraw() public {
        uint amount = pendingReturns[msg.sender];
        if (amount > 0) {
            // 一定要先置0，规避风险
            pendingReturns[msg.sender] = 0;

            msg.sender.transfer(amount);
        }
    }

    /// 结束拍卖，把代币发给受益人
    function auctionEnd()
        public
        onlyAfter(revealEnd)
    {
        require(!ended);
        emit AuctionEnded(highestBidder, highestBid);
        ended = true;
        beneficiary.transfer(highestBid);
    }
}
```

当然，我们也可以有更多的思考

- 我们可以让大家都保存一个min的金额到一个pool里面，之后给予秘密竞拍。但是这里面也会出现如果竞拍金额需要大于x的时候怎么办

## 总结

- 我们通过两阶段拍卖来解决了黑箱拍卖的难题

- 我们通过hash解决了出价不被他人知道的难题

- 我们通过fake解决了混淆视听的方法

  

------



# Ether Shrimp Farm (以太虾农庄)

每个新玩家进来，都能获得300个免费的虾，每只虾每秒钟产下1个虾籽，这些虾籽会累积起来，最多持续累积一天。

对于累计的虾籽，玩家可以选择卖掉换成以太币，或者按照86400的比例转换成一只虾。

你买入和卖出虾的价格有什么决定呢？

项目开发者怎么挣钱呢？5%的交易费会进入项目开发者的口袋。

如果推荐了新玩家加入，那么他每次把虾籽孵化为虾的时候，推荐者会收到20%的虾籽。

这个游戏的特点是，你什么都不需要支付，就可以得到免费的300只虾。于是极大的增加的玩家的参与度。当然玩家还是需要支付gas费用的。于是EOS就特别适合。

```solidity

pragma solidity ^0.4.18; // solhint-disable-line



contract ShrimpFarmer{
    //uint256 EGGS_PER_SHRIMP_PER_SECOND=1; // QY，猜想项目开发者开始想按照秒数来计算下籽的逻辑，但是后来换成了按照1天来计算的方式
    uint256 public EGGS_TO_HATCH_1SHRIMP=86400;// 通过一整天的时间（以秒为单位）计算孵化虾籽的情况
    uint256 public STARTING_SHRIMP=300; // 开始给一个人的虾的数量
    uint256 PSN=10000;
    uint256 PSNH=5000;
    bool public initialized=false; // 是否完成初始化
    address public ceoAddress; // CEO的地址
    mapping (address => uint256) public hatcheryShrimp; // 正在下籽的虾的数量
    mapping (address => uint256) public claimedEggs; // 保存用户购买的虾籽和推荐得到的虾籽总数，但是不包含池塘中的虾产下来的虾籽
    mapping (address => uint256) public lastHatch; // 最后一次操作的时间
    mapping (address => address) public referrals; // 推荐人
    uint256 public marketEggs; // 市场虾籽数的评估指标
    function ShrimpFarmer() public{
        ceoAddress=msg.sender; // 设置创建者为CEO
    }
    function hatchEggs(address ref) public{ // 把虾籽孵化为虾
        require(initialized); // 需要完成平台初始化的过程
        if(referrals[msg.sender]==0 && referrals[msg.sender]!=msg.sender){ // 当自己没有推荐人，并且自己保存的推荐人不是自己，进行更新；QY，代码有可能写错了，应该是ref!=msg.sender
            referrals[msg.sender]=ref; // 设置推荐人
        }
        uint256 eggsUsed=getMyEggs(); // 得到自己的虾籽的数量
        uint256 newShrimp=SafeMath.div(eggsUsed,EGGS_TO_HATCH_1SHRIMP); // 一天的秒数作为除数，计算孵化出来的虾的数量
        hatcheryShrimp[msg.sender]=SafeMath.add(hatcheryShrimp[msg.sender],newShrimp); //
        claimedEggs[msg.sender]=0;
        lastHatch[msg.sender]=now; // 记录最后一次孵化虾籽的时间为当前时间

        //send referral eggs
        claimedEggs[referrals[msg.sender]]=SafeMath.add(claimedEggs[referrals[msg.sender]],SafeMath.div(eggsUsed,5)); // 推荐者获得使用的虾籽的20%

        //boost market to nerf shrimp hoarding
        marketEggs=SafeMath.add(marketEggs,SafeMath.div(eggsUsed,10)); // 增加市场上虾籽的数量，增加消耗掉的虾籽数量除以10
    }
    function sellEggs() public{
        require(initialized); // 需要完成平台初始化过程
        uint256 hasEggs=getMyEggs(); // 得到虾籽的数量
        uint256 eggValue=calculateEggSell(hasEggs); // 计算虾籽的价值
        uint256 fee=devFee(eggValue); // 计算费用
        claimedEggs[msg.sender]=0; // 清空
        lastHatch[msg.sender]=now; // 更新最后的时间
        marketEggs=SafeMath.add(marketEggs,hasEggs); // 更新市场上虾的数量，增加卖掉的虾籽总数
        ceoAddress.transfer(fee); // 把费用给CEO
        msg.sender.transfer(SafeMath.sub(eggValue,fee)); // 给出售者收益
    }
    function buyEggs() public payable{
        require(initialized); // 需要完成平台初始化过程
        uint256 eggsBought=calculateEggBuy(msg.value,SafeMath.sub(this.balance,msg.value)); // 基于出价计算购买的数量
        eggsBought=SafeMath.sub(eggsBought,devFee(eggsBought)); // 减少数量
        ceoAddress.transfer(devFee(msg.value)); // ceo给自己转账
        claimedEggs[msg.sender]=SafeMath.add(claimedEggs[msg.sender],eggsBought); // 给自己添加虾籽
    }
    //magic trade balancing algorithm
    function calculateTrade(uint256 rt,uint256 rs, uint256 bs) public view returns(uint256){ // 基于卖的虾籽的数量，市场上虾籽的数量，自己的账户余额
        //(PSN*bs)/(PSNH+((PSN*rs+PSNH*rt)/rt)); // 计算公式 10000, 5000
        // bs / ( 1 + rs/rt )
        return SafeMath.div(SafeMath.mul(PSN,bs),SafeMath.add(PSNH,SafeMath.div(SafeMath.add(SafeMath.mul(PSN,rs),SafeMath.mul(PSNH,rt)),rt)));
    }
    function calculateEggSell(uint256 eggs) public view returns(uint256){ // 计算对应虾籽数量的价值
        return calculateTrade(eggs,marketEggs,this.balance);
    }
    function calculateEggBuy(uint256 eth,uint256 contractBalance) public view returns(uint256){
        return calculateTrade(eth,contractBalance,marketEggs); // 三个参数
    }
    function calculateEggBuySimple(uint256 eth) public view returns(uint256){
        return calculateEggBuy(eth,this.balance); // 传入ETH，添加自己的balance为参数
    }
    function devFee(uint256 amount) public view returns(uint256){
        return SafeMath.div(SafeMath.mul(amount,4),100); // 乘以4，除以100，也就是4%的费用
    }
    function seedMarket(uint256 eggs) public payable{ // QY，感觉payable可以不用
        require(marketEggs==0); // 市场上没有任何虾籽，初始化的过程
        initialized=true; // 已经开启了初始化过程
        marketEggs=eggs; // 设置虾籽的数量的初始值
    }
    function getFreeShrimp() public{
        require(initialized); // 需要已经完成了初始化
        require(hatcheryShrimp[msg.sender]==0); // 需要调用者的虾的数量为空
        lastHatch[msg.sender]=now; // 设置最后操作时间为当下
        hatcheryShrimp[msg.sender]=STARTING_SHRIMP; // 设置初始赠送的虾300只
    }
    function getBalance() public view returns(uint256){ // 得到账上余额
        return this.balance;
    }
    function getMyShrimp() public view returns(uint256){ // 得到调用者虾的数量
        return hatcheryShrimp[msg.sender];
    }
    function getMyEggs() public view returns(uint256){ // 得到调用者虾籽的数量，由两部分组成，自己可以claim的虾的数量和距离上次新生产出的虾籽的数量
        return SafeMath.add(claimedEggs[msg.sender],getEggsSinceLastHatch(msg.sender));
    }
    function getEggsSinceLastHatch(address adr) public view returns(uint256){
        uint256 secondsPassed=min(EGGS_TO_HATCH_1SHRIMP,SafeMath.sub(now,lastHatch[adr])); // 记录经过了多久的虾的统计时间
        return SafeMath.mul(secondsPassed,hatcheryShrimp[adr]); // 每一秒都能产生一个新的虾籽
    }
    function min(uint256 a, uint256 b) private pure returns (uint256) { // 比较两个数大小
        return a < b ? a : b;
    }
}

library SafeMath {

  /**
  * @dev Multiplies two numbers, throws on overflow.
  */
  function mul(uint256 a, uint256 b) internal pure returns (uint256) { // 安全乘法
    if (a == 0) {
      return 0;
    }
    uint256 c = a * b;
    assert(c / a == b);
    return c;
  }

  /**
  * @dev Integer division of two numbers, truncating the quotient.
  */
  function div(uint256 a, uint256 b) internal pure returns (uint256) { // 安全除法
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold
    return c;
  }

  /**
  * @dev Substracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
  */
  function sub(uint256 a, uint256 b) internal pure returns (uint256) { // 安全减法
    assert(b <= a);
    return a - b;
  }

  /**
  * @dev Adds two numbers, throws on overflow.
  */
  function add(uint256 a, uint256 b) internal pure returns (uint256) { // 安全加法
    uint256 c = a + b;
    assert(c >= a);
    return c;
  }
}

```