//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "hardhat/console.sol";

contract LPStakingECIOUSD is Ownable, Initializable {
    // ************** Variables ******************** //
    uint256 public startPool;

    uint256 private _totalSupply; // total staked amount
    uint256 private REWARD_PER_DAY = 1 * 1e7 * 1e18; // 1,000,000, ecio per day

    uint256 public REWARD_PER_SEC; // to be init || REWARD_PER_DAY / 86400;

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
    mapping(address => uint256) private _releaseTime;
    mapping(address => uint256) private _lockedReward;
    mapping(address => uint256) private _claimedReward;
    mapping(address => uint256) private totalStoredReward;

    mapping(address => uint128) public stakeCounts;
    mapping(address => Stake[]) public stakers;

    // ************** Connected Address ******************** //

    IERC20 public LP_TOKEN;
    IERC20 public ECIO_TOKEN;

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
        uint256 reward
    );

    // ************** Update Function ******************** //

    function initialize() public onlyOwner initializer {
        startPool = getTimestamp();
        REWARD_PER_SEC = REWARD_PER_DAY / 86400;
    }

    function updateLPAddress(IERC20 _address) public onlyOwner {
        LP_TOKEN = _address;
    }

    function updateEcioAddress(IERC20 _address) public onlyOwner {
        ECIO_TOKEN = _address;
    }

    // ************** View Functions ******************** //

    function userStakePeriod(address _address, uint256 count)
        public
        view
        returns (uint256)
    {
        return getTimestamp() - stakers[_address][count].enterTime; // need edit
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

    function status(address _account) public view returns (string memory) {
        if (balances[_account] != 0) {
            return "STAKED";
        }

        if (_lockedReward[_account] != 0) {
            return "REWARD IS LOCKED";
        }

        return "NO STAKE";
    }

    function isUnlock(address account) public view returns (bool) {
        return _releaseTime[account] <= getTimestamp();
    }

    function releaseTime(address account) public view returns (uint256) {
        return _releaseTime[account];
    }

    function stakedAmount(address account) public view returns (uint256) {
        if (balances[account] > 0) {
            return balances[account];
        } else {
            return 0;
        }
    }
    
    /************************* ACTION FUNCTIONS *****************************/

    function unStake() external updateReward(msg.sender) {
        require(balances[msg.sender] != 0);

        uint256 balance = balances[msg.sender];
        uint256 reward = earned(msg.sender) + totalStoredReward[msg.sender];

        lock(reward);

        //Pool's info
        _claimedReward[msg.sender] += reward;
        _totalSupply -= balance;

        //Transfer ECIO
        ECIO_TOKEN.transfer(msg.sender, balance);

        //Clear balance
        delete stakers[msg.sender];

        stakeCounts[msg.sender] = 0;
        balances[msg.sender] = 0;
        totalStoredReward[msg.sender] = 0;

        emit UnStakeEvent(msg.sender, getTimestamp(), balance, reward);
    }

    function claim() external {
        require(_releaseTime[msg.sender] != 0);
        require(_releaseTime[msg.sender] <= getTimestamp());

        uint256 reward = _lockedReward[msg.sender];

        //Transfer Lakrima
        ECIO_TOKEN.transfer(msg.sender, reward);

        _lockedReward[msg.sender] = 0;
        _releaseTime[msg.sender] = 0;

        emit ClaimEvent(msg.sender, getTimestamp(), reward);
    }

    function stake(uint256 amount) external updateReward(msg.sender) {
        //validate
        uint256 timestamp = getTimestamp();

        require(amount <= checkUserLPBalance(msg.sender));

        _totalSupply += amount;
        balances[msg.sender] += amount;
        stakers[msg.sender].push(Stake(amount, timestamp));
        stakeCounts[msg.sender] += 1;
        LP_TOKEN.transferFrom(msg.sender, address(this), amount);

        emit StakeEvent(msg.sender, timestamp, amount);
    }

    function lock(uint256 reward) internal {
        _lockedReward[msg.sender] = reward;
        _releaseTime[msg.sender] = getTimestamp() + 60 days; // lock 60 days
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
