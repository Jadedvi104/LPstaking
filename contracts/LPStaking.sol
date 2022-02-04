//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

interface LKMIERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

contract LPStaking is Ownable {
    using Counters for Counters.Counter;

    // ************** Variables ******************** //
    uint128 stakingFee = 0.005 ether;
    uint32 endPool;

    uint256 public rewardRate = 1930000000000000000;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public totalFee;

    uint256 private _totalSupply;

    uint256 private MAXIMUM_STAKING = 50000000000000000000000; //50,000 LPtokens
    uint256 private TOTAL_LAKRIMA_PER_POOL = 16666666000000000000000000; //16,666,666 LKM
    uint256 public REWARD_RATE = 2000; // dummy reward rate
    uint256 public FEE;
    uint256 public MINIMUM_STAKING = 1000000000000000000000; // 100 LPToken is minimum

    // ************** Struct ******************** //
    struct Stake {
        uint256 amount;
        uint32 timestamp;
    }

    // ************** MAPPING ******************** //

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public tokenRewards;
    mapping(address => uint256) private _userPoolSharePercent;
    mapping(address => uint256) private balances;
    mapping(address => uint256) private _lockedBalances;
    mapping(address => uint256) private _releaseTime;
    mapping(address => uint256) private _lockedRewards;
    mapping(address => uint256) private rewards;
    mapping(address => uint256) private claimedReward;
    mapping(address => uint128) public stakeCounts;
    mapping(address => mapping(uint32 => Stake)) stakers; // edit

    // ************** Connected Address ******************** //

    address public lpTokenAddress;

    IERC20 public rewardsTokenContract;

    // ************** Modifier ******************** //

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;

        rewards[account] = earned(account);
        userRewardPerTokenPaid[account] = rewardPerTokenStored;
        _;
    }

    // ************** Event ******************** //

    // ************** Update Function ******************** //

    function initialize() public {
        lpTokenAddress = 0x97d6864A34D051914894973Af56DCF0B10d26060;
        endPool = now + 365 days;
    }

    function updateLPAddress(address lpAddress) public onlyOwner {
        lpTokenAddress = lpAddress;
    }

    function updateEndPool(uint32 timeEnd) public onlyOwner {
        endPool = timeEnd;
    }


    // ************** View Functions ******************** //

    function checkUserLPBalance(address account) public view returns (uint256) {
        return IERC20(lpTokenAddress).balanceOf(account);
    }

    function getTimestamp() public view returns (uint32) {
        return block.timestamp;
    }

    function isPoolClose() public view returns (bool) {
        return (block.timestamp >= endPool);
    }

    function status(address _account) public view returns (string memory) {
        if (balances[_account] != 0) {
            return "STAKED";
        }

        if (_lockedBalances[_account] != 0) {
            return "WAITING";
        }

        return "NO STAKE";
    }

    function isUnlock(address account) public view returns (bool) {
        return _releaseTime[account] <= getTimestamp();
    }

    function releaseTime(address _account) public view returns (uint256) {
        return _releaseTime[_account];
    }

    function remainingPool() public view returns (uint256) {
        return MAXIMUM_STAKING - _totalSupply;
    }

    function remainingReward() public view returns (uint256) {
        return TOTAL_LAKRIMA_PER_POOL - claimedReward;
    }

    function staked(address _account) public view returns (uint256) {
        if (_lockedBalances[_account] != 0) {
            return _lockedBalances[_account];
        }

        return balances[_account];
    }

    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return 0;
        }
        return
            rewardPerTokenStored +
            (((block.timestamp - lastUpdateTime) * rewardRate * 1e18) /
                _totalSupply);
    }

    function earned(address account) public view returns (uint256) {
        if (_lockedRewards[account] != 0) {
            return _lockedRewards[account];
        }

        uint32 timestamp;
        if (isPoolClose()) {
            timestamp = endPool;
        } else {
            timestamp = getTimestamp();
        }

        //Reward = Staked Amount * Reward Rate * TimeDiff(in Seconds) / RewardInterval
        uint256 totalReward = 0;
        uint256 count = stakeCounts[account];
        for (uint256 index = 0; index < count; index++) {
            uint256 reward = ((stakers[account][index].amount *
                REWARD_RATE *
                (timestamp - stakers[account][index].timestamp)) / 100) /
                (86400 * 365);
            totalReward = totalReward + reward;
        }

        return totalReward;
    }

    function rewards(address account) public view returns (uint256) {
        if (_battlePowerBalances[account] == 0) {
            return tokenRewards[account];
        }

        return
            ((_battlePowerBalances[account] *
                (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18) +
            tokenRewards[account];
    }

    function canClaimReward(address account) public view returns (bool) {
        return
            (rewards(account) >= MINIMUM_AMOUNT_CLAIM) &&
            (getTimestamp() >= accountLastClaim[account] + 10 days);
    }


    function getRank(address account) public view returns (uint256) {
        Rank[] memory results = new Rank[](ranks.length);
        for (uint256 index = 0; index < ranks.length; index++) {
            results[index] = ranks[index];
        }

        results = sort(results);

        for (uint256 index = 0; index < results.length; index++) {
            if (results[index].account == account) {
                return index + 1;
            }
        }
        return 0;
    }

    /************************* ACTION FUNCTIONS *****************************/

    function unStake() external updateReward(msg.sender) {
        require(balances[msg.sender] != 0);

        uint256 balance = balances[msg.sender];

        uint256 reward = earned(msg.sender);

        lock(balance, reward); // Lock 3 Days

        claimedReward = claimedReward + reward;

        _totalSupply = _totalSupply - balance;

        //Clear balance
        delete stakers[msg.sender];

        stakeCounts[msg.sender] = 0;

        balances[msg.sender] = 0;

        emit UnStakeEvent(msg.sender, getTimestamp(), balance, reward);
    }

    function unStakeNow() external updateReward(msg.sender) {
        require(_lockedBalances[msg.sender] != 0);

        uint256 amount = _lockedBalances[msg.sender];
        uint256 reward = _lockedRewards[msg.sender];

        uint256 fee = (amount * FEE) / 10000;

        //Transfer ECIO
        ecioToken.transfer(msg.sender, amount - fee);
        ecioToken.transfer(msg.sender, reward);

        totalFee = totalFee + fee;

        _lockedBalances[msg.sender] = 0;
        _lockedRewards[msg.sender] = 0;
        _releaseTime[msg.sender] = 0;

        emit UnStakeNowEvent(msg.sender, getTimestamp(), amount, reward, fee);
    }

    function claim() external updateReward(msg.sender) {
        require(_releaseTime[msg.sender] != 0);
        require(_releaseTime[msg.sender] <= getTimestamp());
        require(_lockedBalances[msg.sender] != 0);

        uint256 amount = _lockedBalances[msg.sender];
        uint256 reward = _lockedRewards[msg.sender];

        //Transfer ECIO
        ecioToken.transfer(msg.sender, amount);
        ecioToken.transfer(msg.sender, reward);

        _lockedBalances[msg.sender] = 0;
        _lockedRewards[msg.sender] = 0;
        _releaseTime[msg.sender] = 0;

        emit ClaimEvent(msg.sender, getTimestamp(), amount, reward);
    }

    function stake(uint256 amount) external {
        //validate
        uint256 LPBalance = checkUserLPBalance(msg.sender);
        uint256 timestamp = getTimestamp();
        require(!isPoolClose(), "Pool is closed");
        require(amount <= LPBalance);
        require(_totalSupply + amount <= MAXIMUM_STAKING);
        require(balances[msg.sender] + amount >= MINIMUM_STAKING);

        _totalSupply = _totalSupply + amount;
        balances[msg.sender] = balances[msg.sender] + amount;
        stakers[msg.sender].push(Stake(amount, timestamp)); // need to be edited
        stakeCounts[msg.sender] = stakeCounts[msg.sender] + 1;
        IERC20(lpTokenAddress).transferFrom(msg.sender, address(this), amount); // transfer ?

        emit StakeEvent(msg.sender, timestamp, amount);
    }

    function lock(uint256 amount, uint256 reward) internal {
        _lockedBalances[msg.sender] = amount;
        _lockedRewards[msg.sender] = reward;
        _releaseTime[msg.sender] = getTimestamp() + 3 days; // dummy numbers
    }

    function updateRank() private {
        if (!userHasRank[msg.sender]) {
            userRankIds[msg.sender] = ranks.length;
            ranks.push(
                Rank(
                    msg.sender,
                    _battlePowerBalances[msg.sender],
                    userStakedNFTCount[msg.sender]
                )
            );
            userHasRank[msg.sender] = true;
        } else {
            uint256 rankId = userRankIds[msg.sender];
            ranks[rankId].totalBattlePower = _battlePowerBalances[msg.sender];
            ranks[rankId].amount = userStakedNFTCount[msg.sender];
        }
    }

    function calUserShare(address userAddress) internal {
        _totalSupply

    }

    //******************** sorting **********************//
    function sort(Rank[] memory data) private pure returns (Rank[] memory) {
        quickSort(data, int256(0), int256(data.length - 1));
        return data;
    }

    function quickSort(
        Rank[] memory arr,
        int256 left,
        int256 right
    ) private pure {
        int256 i = left;
        int256 j = right;
        if (i == j) return;
        Rank memory pivot = arr[uint256(left + (right - left) / 2)];
        while (i <= j) {
            while (arr[uint256(i)].totalBattlePower > pivot.totalBattlePower)
                i++;
            while (pivot.totalBattlePower > arr[uint256(j)].totalBattlePower)
                j--;
            if (i <= j) {
                (arr[uint256(i)], arr[uint256(j)]) = (
                    arr[uint256(j)],
                    arr[uint256(i)]
                );
                i++;
                j--;
            }
        }
        if (left < j) quickSort(arr, left, j);
        if (i < right) quickSort(arr, i, right);
    }

    //*************** transfer *********************//

    function transferFee(address payable _to, uint256 _amount)
        public
        onlyOwner
    {
        (bool success, ) = _to.call{value: _amount}("");
        require(success, "Failed to send Ether");
    }

    function transferReward(
        address _contractAddress,
        address _to,
        uint256 _amount
    ) public onlyOwner {
        IERC20 _token = IERC20(_contractAddress);
        _token.transfer(_to, _amount);
    }
}
