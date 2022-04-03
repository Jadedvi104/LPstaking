//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "hardhat/console.sol";

contract LPStakingECIOUSDTier is Ownable, Initializable {
    // ************** Variables ******************** //
    uint256 public startPool;

    uint256 private _totalSupply; // total staked amount
    uint256 private REWARD_PER_DAY = 1 * 1e7 * 1e18; // 1,000,000, ecio per day

    uint256 public REWARD_PER_SEC; // to be init || REWARD_PER_DAY / 86400;\
    uint256 public _poolClaimedReward;

    uint32 private ONE_MONTH = 0;
    uint32 private THREE_MONTH = 1;
    uint32 private SIX_MONTH = 2;
    uint32 private TWELVE_MONTH = 3;

    // ************** Structs ******************** //

    struct Stake {
        uint256 amount;
        uint256 enterTime;
    }

    struct StoredReward {
        uint256 lastUpdateTime;
    }

    // ************** MAPPINGs ******************** //

    mapping(address => mapping(uint32 => uint256)) private balances;
    mapping(address => mapping(uint32 => uint256)) private _releaseBalancesTime;
    mapping(address => mapping(uint32 => uint256)) private _lockedBalances;

    mapping(address => mapping(uint32 => uint256)) private _releaseRewardTime;
    mapping(address => mapping(uint32 => uint256)) private _lockedReward;
    mapping(address => uint256) private totalStoredRewardTier1;
    mapping(address => uint256) private totalStoredRewardTier3;
    mapping(address => uint256) private totalStoredRewardTier6;
    mapping(address => uint256) private totalStoredRewardTier12;

    mapping(address => mapping(uint32 => uint128)) public stakeCounts;
    mapping(address => mapping(uint32 => Stake[])) public stakers;
    mapping(address => mapping(uint32 => bool)) public stakersTier;

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

    function status(address _account, uint32 tier)
        public
        view
        returns (string memory)
    {
        if (balances[_account][tier] != 0) {
            return "STAKED";
        }

        if (_lockedReward[_account][tier] != 0) {
            return "REWARD IS LOCKED";
        }

        return "NO STAKE";
    }

    function isUnlock(address account, uint32 tier) public view returns (bool) {
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

    function unStake(uint32 tier) external updateReward(msg.sender, tier) {
        require(balances[msg.sender][tier] != 0);

        uint256 balance = balances[msg.sender][tier];
        uint256 reward;

        if (tier == ONE_MONTH) {
            reward =
                earned(msg.sender, tier) +
                totalStoredRewardTier1[msg.sender];

            lockReward(reward, tier);

            //Pool's info
            _poolClaimedReward += reward;

            totalStoredRewardTier1[msg.sender] = 0;
        }

        if (tier == THREE_MONTH) {
            reward =
                earned(msg.sender, tier) +
                totalStoredRewardTier3[msg.sender];

            lockReward(reward, tier);

            //Pool's info
            _poolClaimedReward += reward;

            totalStoredRewardTier3[msg.sender] = 0;
        }

        if (tier == SIX_MONTH) {
            reward =
                earned(msg.sender, tier) +
                totalStoredRewardTier6[msg.sender];

            lockReward(reward, tier);

            //Pool's info
            _poolClaimedReward += reward;

            totalStoredRewardTier6[msg.sender] = 0;
        }

        if (tier == TWELVE_MONTH) {
            reward =
                earned(msg.sender, tier) +
                totalStoredRewardTier12[msg.sender];

            lockReward(reward, tier);

            //Pool's info
            _poolClaimedReward += reward;

            totalStoredRewardTier12[msg.sender] = 0;
        }

        //Pool's info
        _totalSupply -= balance;

        //Transfer ECIO
        ECIO_TOKEN.transfer(msg.sender, balance);

        //Clear balance
        delete stakers[msg.sender][tier];

        stakeCounts[msg.sender][tier] = 0;
        balances[msg.sender][tier] = 0;

        emit UnStakeEvent(msg.sender, getTimestamp(), balance, reward);
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

    function claimReward(uint32 tier) external {
        require(_releaseRewardTime[msg.sender][tier] != 0);
        require(_releaseRewardTime[msg.sender][tier] <= getTimestamp());

        uint256 reward = _lockedReward[msg.sender][tier];

        //Transfer Lakrima
        ECIO_TOKEN.transfer(msg.sender, reward);

        _lockedReward[msg.sender][tier] = 0;
        _releaseRewardTime[msg.sender][tier] = 0;

        emit ClaimRewardEvent(msg.sender, getTimestamp(), reward);
    }

    function stake(uint256 amount, uint32 tier)
        external
        updateReward(msg.sender, tier)
    {
        //validate
        uint256 timestamp = getTimestamp();

        require(amount <= checkUserLPBalance(msg.sender));

        if (tier == ONE_MONTH) {
            _totalSupply += amount;
            balances[msg.sender][tier] += amount;
            stakers[msg.sender][ONE_MONTH].push(Stake(amount, timestamp));
            stakeCounts[msg.sender][tier] += 1;
            LP_TOKEN.transferFrom(msg.sender, address(this), amount);

            lockBlance(amount, ONE_MONTH);
        }

        if (tier == THREE_MONTH) {
            _totalSupply += amount;
            balances[msg.sender][tier] += amount;
            stakers[msg.sender][THREE_MONTH].push(Stake(amount, timestamp));
            stakeCounts[msg.sender][tier] += 1;
            LP_TOKEN.transferFrom(msg.sender, address(this), amount);

            lockBlance(amount, THREE_MONTH);
        }

        if (tier == SIX_MONTH) {
            _totalSupply += amount;
            balances[msg.sender][tier] += amount;
            stakers[msg.sender][SIX_MONTH].push(Stake(amount, timestamp));
            stakeCounts[msg.sender][tier] += 1;
            LP_TOKEN.transferFrom(msg.sender, address(this), amount);

            lockBlance(amount, SIX_MONTH);
        }

        if (tier == TWELVE_MONTH) {
            _totalSupply += amount;
            balances[msg.sender][tier] += amount;
            stakers[msg.sender][TWELVE_MONTH].push(Stake(amount, timestamp));
            stakeCounts[msg.sender][tier] += 1;
            LP_TOKEN.transferFrom(msg.sender, address(this), amount);

            lockBlance(amount, TWELVE_MONTH);
        }

        emit StakeEvent(msg.sender, timestamp, amount);
    }

    function lockBlance(uint256 balance, uint32 tier) internal {
        _lockedBalances[msg.sender][tier] = balance;

        if (tier == ONE_MONTH) {
            _releaseBalancesTime[msg.sender][ONE_MONTH] =
                getTimestamp() +
                30 days; // lock 30 days || 90 days
        }

        if (tier == THREE_MONTH) {
            _releaseBalancesTime[msg.sender][THREE_MONTH] =
                getTimestamp() +
                90 days; // lock 30 days || 90 days
        }

        if (tier == SIX_MONTH) {
            _releaseBalancesTime[msg.sender][SIX_MONTH] =
                getTimestamp() +
                180 days; // lock 30 days || 90 days
        }

        if (tier == TWELVE_MONTH) {
            _releaseBalancesTime[msg.sender][TWELVE_MONTH] =
                getTimestamp() +
                365 days; // lock 30 days || 90 days
        }
    }

    function lockReward(uint256 reward, uint32 tier) internal {
        _lockedReward[msg.sender][tier] = reward;
        _releaseRewardTime[msg.sender][tier] = getTimestamp() + 60 days; // lock 60 days
    }

    /************************* Reward *******************************/

    function earned(address account, uint32 tier)
        public
        view
        returns (uint256)
    {
        if (_lockedReward[account][tier] != 0) {
            return _lockedReward[account][tier];
        }

        //Reward = REWARD_PER_SEC * TimeDiff(in Seconds) * ShareOfPool
        uint256 totalReward = 0;
        uint256 tierStoredReward;

        if (tier == ONE_MONTH) {
            tierStoredReward = totalStoredRewardTier1[msg.sender];
            for (
                uint256 index = 0;
                index < stakeCounts[account][ONE_MONTH];
                index++
            ) {
                uint256 reward = (REWARD_PER_SEC *
                    userStakePeriod(msg.sender, tier, index) *
                    userShareOfPool(msg.sender, tier, index)) / 1e5;
                totalReward += reward;
            }
        }

        if (tier == THREE_MONTH) {
            tierStoredReward = totalStoredRewardTier3[msg.sender];
            for (
                uint256 index = 0;
                index < stakeCounts[account][THREE_MONTH];
                index++
            ) {
                uint256 reward = (((REWARD_PER_SEC *
                    userStakePeriod(msg.sender, tier, index) *
                    userShareOfPool(msg.sender, tier, index)) * 150) / 100) /
                    1e5;
                totalReward += reward;
            }
        }

        if (tier == SIX_MONTH) {
            tierStoredReward = totalStoredRewardTier6[msg.sender];
            for (
                uint256 index = 0;
                index < stakeCounts[account][SIX_MONTH];
                index++
            ) {
                uint256 reward = (
                    ((REWARD_PER_SEC *
                        userStakePeriod(msg.sender, tier, index) *
                        userShareOfPool(msg.sender, tier, index)) * 300)
                ) / 1e5;
                totalReward += reward;
            }
        }

        if (tier == TWELVE_MONTH) {
            tierStoredReward = totalStoredRewardTier12[msg.sender];
            for (
                uint256 index = 0;
                index < stakeCounts[account][TWELVE_MONTH];
                index++
            ) {
                uint256 reward = (
                    ((REWARD_PER_SEC *
                        userStakePeriod(msg.sender, tier, index) *
                        userShareOfPool(msg.sender, tier, index)) * 400)
                ) / 1e5;
                totalReward += reward;
            }
        }

        return totalReward - tierStoredReward;
    }

    modifier updateReward(address account, uint32 tier) {
        if (tier == ONE_MONTH) {
            totalStoredRewardTier1[account] += earned(account, ONE_MONTH);
        }

        if (tier == THREE_MONTH) {
            totalStoredRewardTier3[account] += earned(account, THREE_MONTH);
        }

        if (tier == SIX_MONTH) {
            totalStoredRewardTier6[account] += earned(account, SIX_MONTH);
        }

        if (tier == TWELVE_MONTH) {
            totalStoredRewardTier12[account] += earned(account, TWELVE_MONTH);
        }
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