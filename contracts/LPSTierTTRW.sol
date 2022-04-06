//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "hardhat/console.sol";

contract LPStakingECIOUSDTier is Ownable, Initializable {
    // ************** Variables ******************** //

    uint256 public _totalSupply; // total staked amount
    uint256 private REWARD_PER_DAY = 1 * 1e6 * 1e18; // 1,000,000, ecio per day

    uint256 public REWARD_PER_SEC; // to be init || REWARD_PER_DAY / 86400;\
    uint256 public _poolClaimedReward;

    uint32 private ONE_MONTH = 0;
    uint32 private TWO_MONTH = 1;
    uint32 private THREE_MONTH = 2;
    uint32 private FOUR_MONTH = 3;
    uint32 private EIGHT_MONTH = 4;
    uint32 private TWELVE_MONTH = 5;

    // ************** Structs ******************** //

    struct Stake {
        uint256 amount;
        uint256 enterTime;
    }

    // ************** MAPPINGs ******************** //

    mapping(address => mapping(uint32 => uint256)) public balances;
    mapping(address => mapping(uint32 => uint256)) private _releaseBalancesTime;
    mapping(address => mapping(uint32 => uint256)) private _lockedBalances;

    mapping(address => mapping(uint32 => uint256)) private _releaseRewardTime;
    mapping(address => mapping(uint32 => uint256)) private _lockedReward;
    uint32 lockRewardCount;

    mapping(address => uint256) public totalStoredReward;

    mapping(address => mapping(uint32 => uint128)) public stakeCounts;
    mapping(address => mapping(uint32 => Stake[])) private stakers;

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
        uint256 amount
    );

    event ClaimBalanceEvent(
        address indexed account,
        uint256 indexed timestamp,
        uint256 balance
    );

    event ClaimRewardEvent(
        address indexed account,
        uint256 indexed timestamp,
        uint256 reward
    );

    // ************** Update Function ******************** //

    function initialize() public onlyOwner initializer {
        REWARD_PER_SEC = REWARD_PER_DAY / 86400;
    }

    function updateLPAddress(IERC20 _address) public onlyOwner {
        LP_TOKEN = _address;
    }

    function updateEcioAddress(IERC20 _address) public onlyOwner {
        ECIO_TOKEN = _address;
    }

    // ************** View Functions ******************** //

    function userStakePeriod(
        address _address,
        uint32 tier,
        uint256 count
    ) public view returns (uint256) {
        return getTimestamp() - stakers[_address][tier][count].enterTime; // need edit
    }

    function userShareOfPool(
        address _address,
        uint32 tier,
        uint256 count
    ) public view returns (uint256) {
        return (stakers[_address][tier][count].amount * 1e5) / _totalSupply;
    }

    function checkUserLPBalance(address account) public view returns (uint256) {
        return LP_TOKEN.balanceOf(account);
    }

    function getTimestamp() public view returns (uint256) {
        return block.timestamp;
    }

    function stakingStatus(address _account, uint32 tier)
        public
        view
        returns (string memory)
    {
        if (balances[_account][tier] != 0) {
            return "STAKED";
        }

        return "NO STAKE";
    }

    function isBalancesUnlocked(address account, uint32 tier) public view returns (bool) {
        return _releaseBalancesTime[account][tier] <= getTimestamp();
    }

    function releaseTime(address account, uint32 tier)
        public
        view
        returns (uint256)
    {
        return _releaseBalancesTime[account][tier];
    }

    function stakedAmount(address account, uint32 tier)
        public
        view
        returns (uint256)
    {
        if (balances[account][tier] > 0) {
            return balances[account][tier];
        } else {
            return 0;
        }
    }

    /************************* ACTION FUNCTIONS *****************************/

    function unStake(uint32 tier) external updateReward(msg.sender) {
        require(balances[msg.sender][tier] != 0);

        uint256 balance = balances[msg.sender][tier];

        //Pool's info
        _totalSupply -= balance;

        //Transfer ECIO
        ECIO_TOKEN.transfer(msg.sender, balance);

        //Clear balance
        delete stakers[msg.sender][tier];

        stakeCounts[msg.sender][tier] = 0;
        balances[msg.sender][tier] = 0;

        emit UnStakeEvent(msg.sender, getTimestamp(), balance);
    }

    function someThingAboutReward(uint32 tier)
        external
        updateReward(msg.sender)
    {
        uint256 reward;
    }

    function claimBalance(uint32 tier) external {
        require(_releaseBalancesTime[msg.sender][tier] != 0);
        require(_releaseBalancesTime[msg.sender][tier] <= getTimestamp());

        uint256 balance = _lockedBalances[msg.sender][tier];

        //Transfer Lakrima
        ECIO_TOKEN.transfer(msg.sender, balance);

        delete stakers[msg.sender][tier];

        _lockedBalances[msg.sender][tier] = 0;
        _releaseBalancesTime[msg.sender][tier] = 0;

        emit ClaimBalanceEvent(msg.sender, getTimestamp(), balance);
    }

    function claimReward(uint32 count) external {
        require(_releaseRewardTime[msg.sender][count] != 0);
        require(_releaseRewardTime[msg.sender][count] <= getTimestamp());

        uint256 reward = _lockedReward[msg.sender][count];

        //Transfer Lakrima
        ECIO_TOKEN.transfer(msg.sender, reward);

        delete _lockedReward[msg.sender][count];
        delete _releaseRewardTime[msg.sender][count];

        emit ClaimRewardEvent(msg.sender, getTimestamp(), reward);
    }

    function stake(uint256 amount, uint32 tier) external {
        //validate
        uint256 timestamp = getTimestamp();

        require(amount <= checkUserLPBalance(msg.sender));

        if (tier == ONE_MONTH) {
            _totalSupply += amount;
            balances[msg.sender][ONE_MONTH] += amount;
            stakers[msg.sender][ONE_MONTH].push(Stake(amount, timestamp));
            stakeCounts[msg.sender][ONE_MONTH] += 1;
            LP_TOKEN.transferFrom(msg.sender, address(this), amount);

            lockBalance(amount, ONE_MONTH);
        }

        if (tier == THREE_MONTH) {
            _totalSupply += amount;
            balances[msg.sender][tier] += amount;
            stakers[msg.sender][THREE_MONTH].push(Stake(amount, timestamp));
            stakeCounts[msg.sender][tier] += 1;
            LP_TOKEN.transferFrom(msg.sender, address(this), amount);

            lockBalance(amount, THREE_MONTH);
        }

        if (tier == EIGHT_MONTH) {
            _totalSupply += amount;
            balances[msg.sender][EIGHT_MONTH] += amount;
            stakers[msg.sender][EIGHT_MONTH].push(Stake(amount, timestamp));
            stakeCounts[msg.sender][EIGHT_MONTH] += 1;
            LP_TOKEN.transferFrom(msg.sender, address(this), amount);

            lockBalance(amount, EIGHT_MONTH);
        }

        if (tier == TWELVE_MONTH) {
            _totalSupply += amount;
            balances[msg.sender][tier] += amount;
            stakers[msg.sender][TWELVE_MONTH].push(Stake(amount, timestamp));
            stakeCounts[msg.sender][tier] += 1;
            LP_TOKEN.transferFrom(msg.sender, address(this), amount);

            lockBalance(amount, TWELVE_MONTH);
        }

        emit StakeEvent(msg.sender, timestamp, amount);
    }

    function lockBalance(uint256 balance, uint32 tier) internal {
        _lockedBalances[msg.sender][tier] = balance;

        if (tier == ONE_MONTH) {
            _releaseBalancesTime[msg.sender][ONE_MONTH] =
                getTimestamp() +
                30 days; // lock 30 days || 90 days
        }

        if (tier == TWO_MONTH) {
            _releaseBalancesTime[msg.sender][TWO_MONTH] =
                getTimestamp() +
                60 days; // lock 30 days || 90 days
        }

        if (tier == THREE_MONTH) {
            _releaseBalancesTime[msg.sender][THREE_MONTH] =
                getTimestamp() +
                90 days; // lock 30 days || 90 days
        }

        if (tier == FOUR_MONTH) {
            _releaseBalancesTime[msg.sender][FOUR_MONTH] =
                getTimestamp() +
                120 days; // lock 30 days || 90 days
        }

        if (tier == EIGHT_MONTH) {
            _releaseBalancesTime[msg.sender][EIGHT_MONTH] =
                getTimestamp() +
                240 days; // lock 30 days || 90 days
        }

        if (tier == TWELVE_MONTH) {
            _releaseBalancesTime[msg.sender][TWELVE_MONTH] =
                getTimestamp() +
                360 days; // lock 30 days || 90 days
        }
    }

    function lockReward(uint256 reward) internal {
        _lockedReward[msg.sender][count] = reward;
        _releaseRewardTime[msg.sender][count] = getTimestamp() + 60 days; // lock 60 days
    }

    /************************* Reward *******************************/

    function earned(address account) public view returns (uint256) {
        if (_lockedReward[account] != 0) {
            return _lockedReward[account];
        }

        //Reward = REWARD_PER_SEC * TimeDiff(in Seconds) * ShareOfPool
        uint256 totalReward;

        for (
            uint256 index = 0;
            index < stakeCounts[account][ONE_MONTH];
            index++
        ) {
            uint256 reward = (REWARD_PER_SEC *
                userStakePeriod(msg.sender, ONE_MONTH, index) *
                userShareOfPool(msg.sender, ONE_MONTH, index)) / 1e5;
            totalReward += reward;
        }

        for (
            uint256 index = 0;
            index < stakeCounts[account][TWO_MONTH];
            index++
        ) {
            uint256 reward = (((REWARD_PER_SEC *
                userStakePeriod(msg.sender, TWO_MONTH, index) *
                userShareOfPool(msg.sender, TWO_MONTH, index)) * 150) / 100) /
                1e5;
            totalReward += reward;
        }

        for (
            uint256 index = 0;
            index < stakeCounts[account][THREE_MONTH];
            index++
        ) {
            uint256 reward = ((REWARD_PER_SEC *
                userStakePeriod(msg.sender, THREE_MONTH, index) *
                userShareOfPool(msg.sender, THREE_MONTH, index)) * 2) /
                1e5;
            totalReward += reward;
        }

        for (
            uint256 index = 0;
            index < stakeCounts[account][FOUR_MONTH];
            index++
        ) {
            uint256 reward = ((REWARD_PER_SEC *
                userStakePeriod(msg.sender, FOUR_MONTH, index) *
                userShareOfPool(msg.sender, FOUR_MONTH, index)) * 3) /
                1e5;
            totalReward += reward;
        }

        for (
            uint256 index = 0;
            index < stakeCounts[account][EIGHT_MONTH];
            index++
        ) {
            uint256 reward = (
                ((REWARD_PER_SEC *
                    userStakePeriod(msg.sender, EIGHT_MONTH, index) *
                    userShareOfPool(msg.sender, EIGHT_MONTH, index)) * 4)
            ) / 1e5;
            totalReward += reward;
        }

        for (
            uint256 index = 0;
            index < stakeCounts[account][TWELVE_MONTH];
            index++
        ) {
            uint256 reward = (
                ((REWARD_PER_SEC *
                    userStakePeriod(msg.sender, TWELVE_MONTH, index) *
                    userShareOfPool(msg.sender, TWELVE_MONTH, index)) * 5)
            ) / 1e5;
            totalReward += reward;
        }

        return totalReward;
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
