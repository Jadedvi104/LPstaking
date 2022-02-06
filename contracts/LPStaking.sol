//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract LPStaking is Ownable {
    using Counters for Counters.Counter;

    // ************** Variables ******************** //
    uint256 startPool;
    uint256 endPool;

    uint256 public lastUpdateTime = 0; // edit
    uint256 public rewardPerTokenStored = 0; // edit
    uint256 public totalFee;

    uint256 private _totalSupply;

    uint256 private MAXIMUM_STAKING = 50000000000000000000000; //50,000 LPtokens dummy
    uint256 public MINIMUM_STAKING = 100000000000000000000; // 1000 LP dummy
    uint256 public MINIMUM_AMOUNT_CLAIM = 100; //dummy

    uint256 private TOTAL_LAKRIMA_PER_POOL = 10000000000000000000000000; //10,000,000 LKM dummy
    uint256 public REWARD_PER_SEC = 0; //TOTAL_LAKRIMA_PER_POOL(wei) / (endPool - startPool)

    uint256 public FEE = 4250; // dummy

    // ************** Structs ******************** //

    struct Stake {
        uint256 amount;
        uint256 timestamp;
    }

    // ************** MAPPINGs ******************** //

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public tokenRewards;
    mapping(address => uint256) private userRewards;
    mapping(address => uint256) private _userPoolSharePercent;
    mapping(address => uint256) private balances;
    mapping(address => uint256) private _lockedBalances;
    mapping(address => uint256) private _releaseTime;
    mapping(address => uint256) private _lockedRewards;
    mapping(address => uint256) private claimedReward;
    mapping(address => uint128) public stakeCounts;

    mapping(address => Stake[]) public stakers; // need edit

    mapping(address => uint256) public accountLastClaim;

    // ************** Connected Address ******************** //

    IERC20 public lpTokenAddress;
    IERC20 public lakrimaAddress;

    // ************** Modifier ******************** //

    modifier updateReward(address account) {
        // rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;

        userRewards[account] = earned(account);
        // userRewardPerTokenPaid[account] = rewardPerTokenStored;
        _;
    }

    // ************** Event ******************** //

    // ************** Update Function ******************** //

    function initialize() public {
        startPool = getTimestamp();
        endPool = getTimestamp() + 365 days;
        REWARD_PER_SEC = TOTAL_LAKRIMA_PER_POOL / (endPool - startPool);
    }

    function updateLPAddress(address _address) public onlyOwner {
        lpTokenAddress = IERC20(_address);
    }

    function updateLakrimaAddress(address _address) public onlyOwner {
        lakrimaAddress = IERC20(_address);
    }

    function updateEndPool(uint32 timeEnd) public onlyOwner {
        endPool = timeEnd;
    }

    // ************** View Functions ******************** //

    // Unfinished
    function userStakePeriod(address _address) public view returns (uint256) {
        uint256 count = stakeCounts[msg.sender];
        return getTimestamp() - stakers[_address][count - 1].timestamp;
    }

    function userShareOfPool(address _address) public view returns (uint256) {
        return (balances[_address] * 100000) / _totalSupply;
    }

    function checkUserLPBalance(address account) public view returns (uint256) {
        return lpTokenAddress.balanceOf(account);
    }

    function getTimestamp() public view returns (uint256) {
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

    function remainingReward(address _account) public view returns (uint256) {
        return TOTAL_LAKRIMA_PER_POOL - claimedReward[_account];
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
            (((block.timestamp - lastUpdateTime) * REWARD_PER_SEC * 1e18) /
                _totalSupply);
    }

    function earned(address account) public view returns (uint256) {
        if (_lockedRewards[account] != 0) {
            return _lockedRewards[account];
        }

        uint256 timestamp;
        if (isPoolClose()) {
            timestamp = endPool;
        } else {
            timestamp = getTimestamp();
        }

        //Reward = REWARD_PER_SEC * TimeDiff(in Seconds) * ShareOfPool

        uint256 totalReward = 0;
        uint128 count = stakeCounts[account];
        for (uint128 index = 0; index < count; index++) {
            uint256 reward = (userStakePeriod(msg.sender) *
                REWARD_PER_SEC *
                userShareOfPool(msg.sender)) / 1e5;
            totalReward = totalReward + reward;
        }

        return totalReward;
    }

    function rewards(address account) public view returns (uint256) {
        if (balances[account] == 0) {
            return tokenRewards[account];
        }

        return
            ((balances[account] *
                (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18) +
            tokenRewards[account];
    }

    function canClaimReward(address account) public view returns (bool) {
        return
            (rewards(account) >= MINIMUM_AMOUNT_CLAIM) &&
            (getTimestamp() >= accountLastClaim[account] + 10 days); // dummy
    }

    /************************* ACTION FUNCTIONS *****************************/

    function unStake() external updateReward(msg.sender) {
        require(balances[msg.sender] != 0);

        uint256 balance = balances[msg.sender];

        uint256 reward = earned(msg.sender);

        lock(balance, reward); // Lock dummy Days

        claimedReward[msg.sender] = claimedReward[msg.sender] + reward;

        _totalSupply = _totalSupply - balance;

        //Clear balance
        delete stakers[msg.sender];

        stakeCounts[msg.sender] = 0;
        balances[msg.sender] = 0;
    }

    function unStakeNow() external updateReward(msg.sender) {
        require(_lockedBalances[msg.sender] != 0);

        uint256 amount = _lockedBalances[msg.sender];
        uint256 reward = _lockedRewards[msg.sender];

        uint256 fee = (amount * FEE) / 10000;

        //Transfer ECIO
        lakrimaAddress.transfer(msg.sender, amount - fee);
        lakrimaAddress.transfer(msg.sender, reward);

        totalFee = totalFee + fee;

        _lockedBalances[msg.sender] = 0;
        _lockedRewards[msg.sender] = 0;
        _releaseTime[msg.sender] = 0;
    }

    function claim() external updateReward(msg.sender) {
        require(canClaimReward(msg.sender), "Reward: Can't claim");
        require(_releaseTime[msg.sender] != 0);
        require(_releaseTime[msg.sender] <= getTimestamp());
        require(_lockedBalances[msg.sender] != 0);

        uint256 amount = _lockedBalances[msg.sender];
        uint256 reward = _lockedRewards[msg.sender];

        //Transfer Lakrima
        lakrimaAddress.transfer(msg.sender, amount);
        lakrimaAddress.transfer(msg.sender, reward);

        _lockedBalances[msg.sender] = 0;
        _lockedRewards[msg.sender] = 0;
        _releaseTime[msg.sender] = 0;

        accountLastClaim[msg.sender] = getTimestamp();
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
        stakers[msg.sender].push(Stake(amount, timestamp));
        stakeCounts[msg.sender] = stakeCounts[msg.sender] + 1;
        lpTokenAddress.transferFrom(msg.sender, address(this), amount);
    }

    function lock(uint256 amount, uint256 reward) internal {
        _lockedBalances[msg.sender] = amount;
        _lockedRewards[msg.sender] = reward;
        _releaseTime[msg.sender] = getTimestamp() + 30 days; // lock 30 days || 90 days
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
