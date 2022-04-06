//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "hardhat/console.sol";

contract LPStaking is Ownable, Initializable {
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

    // ************** Structs ******************** //

    struct Stake {
        uint256 amount;
        uint256 enterTime;
    }

    struct StoredReward {
        uint256 lastUpdateTime;
    }

    // ************** MAPPINGs ******************** //

    mapping(address => uint256) private balances;
    mapping(address => uint256) private _lockedBalances;
    mapping(address => uint256) private _releaseTime;
    mapping(address => uint256) private _lockedReward;
    mapping(address => uint256) private _claimedReward;
    mapping(address => uint256[]) private userLastUpdateTime;
    mapping(address => uint256) private totalStoredReward;

    mapping(address => uint128) public stakeCounts;
    mapping(address => Stake[]) public stakers;

    // ************** Connected Address ******************** //

    IERC20 public LP_TOKEN;
    IERC20 public LAKRIMA_TOKEN;

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

    function initialize() public onlyOwner initializer {
        startPool = getTimestamp();
        endPool = getTimestamp() + 365 days;
        REWARD_PER_SEC = TOTAL_LAKRIMA_PER_POOL / (endPool - startPool);
    }

    function updateLPAddress(IERC20 _address) public onlyOwner {
        LP_TOKEN = _address;
    }

    function updateLakrimaAddress(IERC20 _address) public onlyOwner {
        LAKRIMA_TOKEN = _address;
    }

    // function updateEndPool(uint32 timeEnd) public onlyOwner {
    //     endPool = timeEnd;
    // }

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

        return timestamp - stakers[_address][count].enterTime; // need edit
    }

    function userShareOfPool(address _address, uint256 count)
        public
        view
        returns (uint256)
    {
        return (stakers[_address][count].amount * 1e5) / _totalSupply;
    }

    function checkUserLPBalance(address account) public view returns (uint256) {
        return LP_TOKEN.balanceOf(account);
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

    /************************* ACTION FUNCTIONS *****************************/

    function unStake() external updateReward(msg.sender) {
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
        totalStoredReward[msg.sender] = 0;

        emit UnStakeEvent(msg.sender, getTimestamp(), balance, reward);
    }

    function unStakeNow() external {
        require(_lockedBalances[msg.sender] != 0);

        uint256 amount = _lockedBalances[msg.sender];
        uint256 reward = _lockedReward[msg.sender];

        uint256 fee = (amount * FEE) / 10000;

        //Transfer ECIO
        LAKRIMA_TOKEN.transfer(msg.sender, amount - fee);
        LAKRIMA_TOKEN.transfer(msg.sender, reward);

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
        LAKRIMA_TOKEN.transfer(msg.sender, amount);
        LAKRIMA_TOKEN.transfer(msg.sender, reward);

        _lockedBalances[msg.sender] = 0;
        _lockedReward[msg.sender] = 0;
        _releaseTime[msg.sender] = 0;

        emit ClaimEvent(msg.sender, getTimestamp(), amount, reward);
    }

    function stake(uint256 amount) external updateReward(msg.sender) {
        //validate
        uint256 timestamp = getTimestamp();

        require(!isPoolClose(), "Pool is closed");
        require(amount <= checkUserLPBalance(msg.sender));
        require(_totalSupply + amount <= MAXIMUM_STAKING);
        require(balances[msg.sender] + amount >= MINIMUM_STAKING);

        _totalSupply = _totalSupply + amount;
        balances[msg.sender] = balances[msg.sender] + amount;
        stakers[msg.sender].push(Stake(amount, timestamp));
        stakeCounts[msg.sender] = stakeCounts[msg.sender] + 1;
        LP_TOKEN.transferFrom(msg.sender, address(this), amount);

        emit StakeEvent(msg.sender, timestamp, amount);
    }

    function lock(uint256 amount, uint256 reward) internal {
        _lockedBalances[msg.sender] = amount;
        _lockedReward[msg.sender] = reward;
        _releaseTime[msg.sender] = getTimestamp() + 30 days; // lock 30 days || 90 days
    }

    /************************* Reward *******************************/

    function earned(address account) public view returns (uint256) {
        if (_lockedReward[account] != 0) {
            return _lockedReward[account];
        }

        //Reward = REWARD_PER_SEC * TimeDiff(in Seconds) * ShareOfPool
        uint256 totalReward = 0;

        for (uint256 index = 0; index < stakeCounts[account]; index++) {
            uint256 reward = (REWARD_PER_SEC *
                userStakePeriod(msg.sender, index) *
                userShareOfPool(msg.sender, index)) / 1e5;
            totalReward += reward;
        }

        return totalReward - totalStoredReward[account];
    }

    modifier updateReward(address account) {
        totalStoredReward[account] += earned(account);
        _;
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
