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
