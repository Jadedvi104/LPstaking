//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract LPStaking is Ownable {
    // ************** Variables ******************** //
    uint256 public startPool;
    uint256 public endPool;

    uint256 public totalFee; // need number

    uint256 private _totalSupply;

    uint256 private MAXIMUM_STAKING = 50000000000000000000000; //50,000 LPtokens dummy

    uint256 public MINIMUM_STAKING = 100000000000000000000; // 1000 LP dummy

    uint256 public MINIMUM_AMOUNT_CLAIM = 100; //dummy

    uint256 private TOTAL_LAKRIMA_PER_POOL = 10000000000000000000000000; //10,000,000 LKM dummy

    uint256 public REWARD_PER_SEC = 0; //TOTAL_LAKRIMA_PER_POOL(wei) / (endPool - startPool)

    uint256 public FEE = 4250; // dummy

    uint256 public lastUpdateTime;
    uint256 public addressCount;

    // ************** Structs ******************** //

    struct Stake {
        uint256 amount;
        uint256 timestamp;
    }

    struct StoredReward {
        uint256 updateTime;
        uint256 storedReward;
    }

    // ************** MAPPINGs ******************** //

    mapping(address => uint256) private balances;
    mapping(address => uint256) private _lockedBalances;
    mapping(address => uint256) private _releaseTime;
    mapping(address => uint256) private _lockedReward;
    mapping(address => uint256) private _claimedReward;
    mapping(address => StoredReward[]) private userStoreReward;
    mapping(address => uint256) private totalStoredReward;

    mapping(address => uint128) public stakeCounts;
    mapping(address => Stake[]) public stakers;
    mapping(address => uint256) public accountLastClaim;

    // ************** Connected Address ******************** //

    IERC20 public lpTokenAddress;
    IERC20 public lakrimaAddress;

    // ************** Event ******************** //

    event StakeEvent(
        address indexed account,
        uint256 indexed timestamp,
        uint256 amount
    );
    event UnStakeEvent(
        address indexed account,
        uint256 indexed timestamp,
        uint256 amount,
        uint256 reward
    );
    event UnStakeNowEvent(
        address indexed account,
        uint256 indexed timestamp,
        uint256 amount,
        uint256 reward,
        uint256 fee
    );
    event ClaimEvent(
        address indexed account,
        uint256 indexed timestamp,
        uint256 amount,
        uint256 reward
    );

    // ************** Update Function ******************** //

    function initialize() public onlyOwner {
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

    function userStakePeriod(address _address, uint256 count)
        public
        view
        returns (uint256)
    {
        uint256 timestamp;
        if (isPoolClose()) {
            timestamp = endPool;
        } else {
            timestamp = getTimestamp();
        }

        return timestamp - stakers[_address][count].timestamp; // need edit
    }

    function userShareOfPool(address _address, uint256 count)
        public
        view
        returns (uint256)
    {
        return (stakers[_address][count].amount * 1e5) / _totalSupply;
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
        return TOTAL_LAKRIMA_PER_POOL - _claimedReward[_account];
    }

    function staked(address _account) public view returns (uint256) {
        if (_lockedBalances[_account] != 0) {
            return _lockedBalances[_account];
        }

        return balances[_account];
    }

    function earned(address account) public view returns (uint256) {
        if (_lockedReward[account] != 0) {
            return _lockedReward[account];
        }

        //Reward = REWARD_PER_SEC * TimeDiff(in Seconds) * ShareOfPool
        uint256 totalReward = 0;
        uint128 count = stakeCounts[account];

        for (uint256 index = 0; index < count; index++) {
            uint256 reward = (REWARD_PER_SEC *
                userStakePeriod(msg.sender, index) *
                userShareOfPool(msg.sender, index)) / 1e5;
            totalReward = totalReward + reward;
        }

        return totalReward - totalStoredReward[account];
    }

    
    /************************* ACTION FUNCTIONS *****************************/

    function updateReward(address account) external {
        uint128 count = stakeCounts[account];
        uint256 reward = earned(account);
        userStoreReward[account][count] = StoredReward(
                getTimestamp(),
                reward
        );
            totalStoredReward[account] = totalStoredReward[account] + reward;
    }
    
    function unStake() external {
        require(balances[msg.sender] != 0);

        uint256 balance = balances[msg.sender];

        uint256 reward = earned(msg.sender) + totalStoredReward[msg.sender];

        lock(balance, reward); // Lock dummy Days

        _claimedReward[msg.sender] = _claimedReward[msg.sender] + reward;

        _totalSupply = _totalSupply - balance;

        //Clear balance
        delete stakers[msg.sender];

        stakeCounts[msg.sender] = 0;
        balances[msg.sender] = 0;

        emit UnStakeEvent(msg.sender, getTimestamp(), balance, reward);
    }

    function unStakeNow() external {
        require(_lockedBalances[msg.sender] != 0);

        uint256 amount = _lockedBalances[msg.sender];
        uint256 reward = _lockedReward[msg.sender];

        uint256 fee = (amount * FEE) / 10000;

        //Transfer ECIO
        lakrimaAddress.transfer(msg.sender, amount - fee);
        lakrimaAddress.transfer(msg.sender, reward);

        totalFee = totalFee + fee;

        _lockedBalances[msg.sender] = 0;
        _lockedReward[msg.sender] = 0;
        _releaseTime[msg.sender] = 0;

        emit UnStakeNowEvent(msg.sender, getTimestamp(), amount, reward, fee);
    }

    function claim() external {
        require(_releaseTime[msg.sender] != 0);
        require(_releaseTime[msg.sender] <= getTimestamp());
        require(_lockedBalances[msg.sender] != 0);

        uint256 amount = _lockedBalances[msg.sender];
        uint256 reward = _lockedReward[msg.sender];

        //Transfer Lakrima
        lakrimaAddress.transfer(msg.sender, amount);
        lakrimaAddress.transfer(msg.sender, reward);

        _lockedBalances[msg.sender] = 0;
        _lockedReward[msg.sender] = 0;
        _releaseTime[msg.sender] = 0;

        accountLastClaim[msg.sender] = getTimestamp();

        emit ClaimEvent(msg.sender, getTimestamp(), amount, reward);
    }

    function stake(uint256 amount) external {
        //validate
        uint256 lpBalance = checkUserLPBalance(msg.sender);
        uint256 timestamp = getTimestamp();

        require(!isPoolClose(), "Pool is closed");
        require(amount <= lpBalance);
        require(_totalSupply + amount <= MAXIMUM_STAKING);
        require(balances[msg.sender] + amount >= MINIMUM_STAKING);

        _totalSupply = _totalSupply + amount;
        balances[msg.sender] = balances[msg.sender] + amount;
        stakers[msg.sender].push(Stake(amount, timestamp));
        stakeCounts[msg.sender] = stakeCounts[msg.sender] + 1;
        lpTokenAddress.transferFrom(msg.sender, address(this), amount);

        emit StakeEvent(msg.sender, timestamp, amount);
    }

    function lock(uint256 amount, uint256 reward) internal {
        _lockedBalances[msg.sender] = amount;
        _lockedReward[msg.sender] = reward;
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

    function transferToken(
        address _contractAddress,
        address _to,
        uint256 _amount
    ) public onlyOwner {
        IERC20 _token = IERC20(_contractAddress);
        _token.transfer(_to, _amount);
    }
}
