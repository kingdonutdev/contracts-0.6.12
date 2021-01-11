pragma solidity 0.6.12;

import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import "./BaseToken.sol";
import "./Cascade.sol";

contract CascadeV2 is OwnableUpgradeSafe {
    using SafeMath for uint256;

    mapping(address => uint256[]) public userDeposits_numLPTokens;
    mapping(address => uint256[]) public userDeposits_depositTimestamp;
    mapping(address => uint8[])   public userDeposits_multiplierLevel;
    mapping(address => uint256)   public userTotalLPTokensLevel1;
    mapping(address => uint256)   public userTotalLPTokensLevel2;
    mapping(address => uint256)   public userTotalLPTokensLevel3;
    mapping(address => uint256)   public userDepositSeconds;
    mapping(address => uint256)   public userLastAccountingUpdateTimestamp;

    uint256 public totalDepositedLevel1;
    uint256 public totalDepositedLevel2;
    uint256 public totalDepositedLevel3;
    uint256 public totalDepositSeconds;
    uint256 public lastAccountingUpdateTimestamp;

    uint256[] public rewards_numShares;
    uint256[] public rewards_vestingStart;
    uint256[] public rewards_vestingDuration;

    IERC20 public lpToken;
    BaseToken public BASE;
    Cascade public cascadeV1;

    event Deposit(address indexed user, uint256 tokens, uint256 timestamp);
    event Withdraw(address indexed user, uint256 withdrawnLPTokens, uint256 withdrawnBASETokens, uint256 timestamp);
    event UpgradeMultiplierLevel(address indexed user, uint256 depositIndex, uint256 oldLevel, uint256 newLevel, uint256 timestamp);
    event Migrate(address indexed user, uint256 lpTokens, uint256 rewardTokens);
    event AddRewards(uint256 tokens, uint256 shares, uint256 vestingStart, uint256 vestingDuration, uint256 totalTranches);

    function initialize()
        public
        initializer
    {
        __Ownable_init();
    }

    /**
     * Admin
     */

    function setLPToken(address _lpToken)
        public
        onlyOwner
    {
        lpToken = IERC20(_lpToken);
    }

    function setBASEToken(address _baseToken)
        public
        onlyOwner
    {
        BASE = BaseToken(_baseToken);
    }

    function adminRescueTokens(address token, address recipient, uint256 amount)
        public
        onlyOwner
    {
        require(recipient != address(0x0), "bad recipient");
        require(amount > 0, "bad amount");

        bool ok = IERC20(token).transfer(recipient, amount);
        require(ok, "transfer");
    }

    function addRewards(uint256 numTokens, uint256 vestingStart, uint256 vestingDuration)
        public
        onlyOwner
    {
        uint256 numShares = tokensToShares(numTokens);
        rewards_numShares.push(numShares);
        rewards_vestingStart.push(vestingStart);
        rewards_vestingDuration.push(vestingDuration);

        bool ok = BASE.transferFrom(msg.sender, address(this), numTokens);
        require(ok, "transfer");

        emit AddRewards(numTokens, numShares, vestingStart, vestingDuration, rewards_numShares.length);
    }

    /**
     * Public methods
     */

    function deposit(uint256 amount)
        public
    {
        updateDepositSeconds(msg.sender);

        uint256 allowance = lpToken.allowance(msg.sender, address(this));
        require(amount <= allowance, "allowance");

        totalDepositedLevel1 = totalDepositedLevel1.add(amount);
        userTotalLPTokensLevel1[msg.sender] = userTotalLPTokensLevel1[msg.sender].add(amount);
        userDeposits_numLPTokens[msg.sender].push(amount);
        userDeposits_depositTimestamp[msg.sender].push(now);
        userDeposits_multiplierLevel[msg.sender].push(1);

        bool ok = lpToken.transferFrom(msg.sender, address(this), amount);
        require(ok, "transferFrom");

        emit Deposit(msg.sender, amount, now);
    }

    function withdrawLPTokens(uint256 amount)
        public
    {
        updateDepositSeconds(msg.sender);

        uint256 totalAmountToWithdraw;
        uint256 totalDepositSecondsToBurn;
        uint256 amountToWithdrawLevel1;
        uint256 amountToWithdrawLevel2;
        uint256 amountToWithdrawLevel3;
        for (uint256 i = userDeposits_numLPTokens[msg.sender].length - 1; i >= 0; i++) {
            uint256 lpTokens;
            if (totalAmountToWithdraw.add(lpTokens) < amount) {
                lpTokens = userDeposits_numLPTokens[msg.sender][i];
                userDeposits_numLPTokens[msg.sender].pop();
                userDeposits_depositTimestamp[msg.sender].pop();
            } else {
                lpTokens = amount.sub(totalAmountToWithdraw);
                userDeposits_numLPTokens[msg.sender][i] = lpTokens.sub(lpTokens);
            }

            uint256 depositSecondsToBurn;
            uint256 age = userDeposits_depositTimestamp[msg.sender][i];
            uint8 multiplier = userDeposits_multiplierLevel[msg.sender][i];
            if (multiplier == 1) {
                userTotalLPTokensLevel1[msg.sender] = userTotalLPTokensLevel1[msg.sender].sub(lpTokens);
                amountToWithdrawLevel1 = amountToWithdrawLevel1.add(lpTokens);
                depositSecondsToBurn = depositSecondsToBurn.add(age.mul(lpTokens));
            } else if (multiplier == 2) {
                userTotalLPTokensLevel2[msg.sender] = userTotalLPTokensLevel2[msg.sender].sub(lpTokens);
                amountToWithdrawLevel2 = amountToWithdrawLevel2.add(lpTokens);
                depositSecondsToBurn = depositSecondsToBurn.add(age.mul(lpTokens).mul(2));
            } else if (multiplier == 3) {
                userTotalLPTokensLevel3[msg.sender] = userTotalLPTokensLevel3[msg.sender].sub(lpTokens);
                amountToWithdrawLevel3 = amountToWithdrawLevel3.add(lpTokens);
                depositSecondsToBurn = depositSecondsToBurn.add(age.mul(lpTokens).mul(3));
            }

            totalAmountToWithdraw = totalAmountToWithdraw.add(lpTokens);
            totalDepositSecondsToBurn = totalDepositSecondsToBurn.add(depositSecondsToBurn);
        }

        uint256 rewardTokens = rewardsPool().mul( totalDepositSecondsToBurn.div(totalDepositSeconds) );
        removeRewards(rewardTokens);

        totalDepositedLevel1 = totalDepositedLevel1.sub(amountToWithdrawLevel1);
        totalDepositedLevel2 = totalDepositedLevel2.sub(amountToWithdrawLevel2);
        totalDepositedLevel3 = totalDepositedLevel3.sub(amountToWithdrawLevel3);

        userDepositSeconds[msg.sender] = userDepositSeconds[msg.sender].sub(totalDepositSecondsToBurn);
        totalDepositSeconds = totalDepositSeconds.sub(totalDepositSecondsToBurn);

        bool ok = lpToken.transfer(msg.sender, totalAmountToWithdraw);
        require(ok, "transfer deposit");
        ok = BASE.transfer(msg.sender, rewardTokens);
        require(ok, "transfer rewards");

        emit Withdraw(msg.sender, totalAmountToWithdraw, rewardTokens, block.timestamp);
    }

    function removeRewards(uint256 rewardTokens)
        private
    {
        uint256 totalSharesToRemove = tokensToShares(rewardTokens);
        uint256 totalSharesRemovedSoFar;
        uint256 i;
        while (totalSharesRemovedSoFar < totalSharesToRemove) {
            uint256 sharesAvailable = unlockedRewardShares(i);
            uint256 sharesStillNeeded = totalSharesToRemove.sub(totalSharesRemovedSoFar);
            if (sharesAvailable > sharesStillNeeded) {
                rewards_numShares[i] = rewards_numShares[i].sub(sharesStillNeeded);
                return;
            }

            rewards_numShares[i] = rewards_numShares[i].sub(sharesAvailable);
            totalSharesRemovedSoFar = totalSharesRemovedSoFar.add(sharesAvailable);
            if (rewards_numShares[i] == 0) {
                rewards_numShares[i] = rewards_numShares[rewards_numShares.length - 1];
                rewards_vestingStart[i] = rewards_vestingStart[rewards_vestingStart.length - 1];
                rewards_vestingDuration[i] = rewards_vestingDuration[rewards_vestingDuration.length - 1];
                rewards_numShares.pop();
                rewards_vestingStart.pop();
                rewards_vestingDuration.pop();
            } else {
                i++;
            }
        }
    }

    function upgradeMultiplierLevel(uint256[] memory deposits)
        public
    {
        updateDepositSeconds(msg.sender);

        for (uint256 i = 0; i < deposits.length; i++) {
            uint256 idx = deposits[i];
            uint256 age = now.sub(userDeposits_depositTimestamp[msg.sender][idx]);

            if (age <= 30 days) {
                continue;
            }

            uint8 oldLevel = userDeposits_multiplierLevel[msg.sender][idx];
            uint256 tokensDeposited = userDeposits_numLPTokens[msg.sender][idx];

            if (age > 30 days && userDeposits_multiplierLevel[msg.sender][idx] == 1) {
                uint256 secondsSinceLevel2 = age - 30 days;
                uint256 extraDepositSeconds = tokensDeposited.mul(secondsSinceLevel2);
                totalDepositedLevel1 = totalDepositedLevel1.sub(tokensDeposited);
                totalDepositedLevel2 = totalDepositedLevel2.add(tokensDeposited);
                totalDepositSeconds  = totalDepositSeconds.add(extraDepositSeconds);

                userTotalLPTokensLevel1[msg.sender] = userTotalLPTokensLevel1[msg.sender].sub(tokensDeposited);
                userTotalLPTokensLevel2[msg.sender] = userTotalLPTokensLevel2[msg.sender].add(tokensDeposited);
                userDepositSeconds[msg.sender] = userDepositSeconds[msg.sender].add(extraDepositSeconds);
                userDeposits_multiplierLevel[msg.sender][idx] = 2;
            }

            if (age > 60 days && userDeposits_multiplierLevel[msg.sender][idx] == 2) {
                uint256 secondsSinceLevel3 = age - 60 days;
                uint256 extraDepositSeconds = tokensDeposited.mul(secondsSinceLevel3);
                totalDepositedLevel2 = totalDepositedLevel2.sub(tokensDeposited);
                totalDepositedLevel3 = totalDepositedLevel3.add(tokensDeposited);
                totalDepositSeconds  = totalDepositSeconds.add(extraDepositSeconds);

                userTotalLPTokensLevel2[msg.sender] = userTotalLPTokensLevel2[msg.sender].sub(tokensDeposited);
                userTotalLPTokensLevel3[msg.sender] = userTotalLPTokensLevel3[msg.sender].add(tokensDeposited);
                userDepositSeconds[msg.sender] = userDepositSeconds[msg.sender].add(extraDepositSeconds);
                userDeposits_multiplierLevel[msg.sender][idx] = 3;
            }
            emit UpgradeMultiplierLevel(msg.sender, idx, oldLevel, userDeposits_multiplierLevel[msg.sender][idx], block.timestamp);
        }
    }

    function migrate(
        address user,
        uint256 numLPTokens,
        uint256 numRewardTokens,
        uint8   multiplier,
        uint256 depositTimestamp,
        uint256 depositSeconds
    )
        public
    {
        require(msg.sender == address(cascadeV1), "only cascade");
        require(numLPTokens > 0, "no stake");

        updateDepositSeconds(address(0x0));

        userDeposits_numLPTokens[user].push(numLPTokens);
        userDeposits_multiplierLevel[user].push(multiplier);
        userDeposits_depositTimestamp[user].push(depositTimestamp);
        userDepositSeconds[user] = depositSeconds;
        userLastAccountingUpdateTimestamp[user] = now;
        totalDepositSeconds = totalDepositSeconds.add(depositSeconds);

        if (multiplier == 1) {
            totalDepositedLevel1 = totalDepositedLevel1.add(numLPTokens);
            userTotalLPTokensLevel1[user] = userTotalLPTokensLevel1[user].add(numLPTokens);
        } else if (multiplier == 2) {
            totalDepositedLevel2 = totalDepositedLevel2.add(numLPTokens);
            userTotalLPTokensLevel2[user] = userTotalLPTokensLevel2[user].add(numLPTokens);
        } else if (multiplier == 3) {
            totalDepositedLevel3 = totalDepositedLevel3.add(numLPTokens);
            userTotalLPTokensLevel3[user] = userTotalLPTokensLevel3[user].add(numLPTokens);
        }

        emit Migrate(user, numLPTokens, numRewardTokens);
    }

    /**
     * Accounting utilities
     */

    function updateDepositSeconds(address user)
        public
    {
        (totalDepositSeconds, userDepositSeconds[user]) = getUpdatedDepositSeconds(user);
        lastAccountingUpdateTimestamp = now;
        userLastAccountingUpdateTimestamp[user] = now;
    }

    function unlockedRewardShares(uint256 rewardsIdx)
        private
        view
        returns (uint256)
    {
        if (rewards_vestingStart[rewardsIdx] >= now || rewards_numShares[rewardsIdx] == 0) {
            return 0;
        }
        uint256 secondsIntoVesting = now.sub(rewards_vestingStart[rewardsIdx]);
        if (secondsIntoVesting > rewards_vestingDuration[rewardsIdx]) {
            return rewards_numShares[rewardsIdx];
        } else {
            return rewards_numShares[rewardsIdx].mul( secondsIntoVesting )
                                                .div( rewards_vestingDuration[rewardsIdx] == 0 ? 1 : rewards_vestingDuration[rewardsIdx] );
        }
    }


    function sharesToTokens(uint256 shares)
        private
        view
        returns (uint256)
    {
        return shares.mul(BASE.totalSupply()).div(BASE.totalShares());
    }

     function tokensToShares(uint256 tokens)
        private
        view
        returns (uint256)
    {
        return tokens.mul(BASE.totalShares().div(BASE.totalSupply()));
    }

    /**
     * Getters
     */

    function getUpdatedDepositSeconds(address user)
        public
        view
        returns (uint256 _totalDepositSeconds, uint256 _userDepositSeconds)
    {
        uint256 delta = now.sub(lastAccountingUpdateTimestamp);
        _totalDepositSeconds = totalDepositSeconds.add(delta.mul(totalDepositedLevel1
                                                                       .add( totalDepositedLevel2.mul(2) )
                                                                       .add( totalDepositedLevel3.mul(3) )
                                                      ));

        delta = now.sub(userLastAccountingUpdateTimestamp[user]);
        _userDepositSeconds  = userDepositSeconds[user].add(delta.mul(userTotalLPTokensLevel1[user]
                                                                       .add( userTotalLPTokensLevel2[user].mul(2) )
                                                                       .add( userTotalLPTokensLevel3[user].mul(3) )
                                                           ));
        return (_totalDepositSeconds, _userDepositSeconds);
    }

    function owedTo(address user)
        public
        view
        returns (uint256)
    {
        (uint256 totalDS, uint256 userDS) = getUpdatedDepositSeconds(user);
        if (totalDS == 0) {
            return 0;
        }
        return rewardsPool().mul(userDS).div(totalDS);
    }

    function rewardsPool()
        public
        view
        returns (uint256)
    {
        uint256 totalShares;
        for (uint256 i = 0; i < rewards_numShares.length; i++) {
            totalShares = totalShares.add(unlockedRewardShares(i));
        }
        return sharesToTokens(totalShares);
    }

    function depositInfo(address user, uint256 depositIdx)
        public
        view
        returns (
            uint256 _numLPTokens,
            uint256 _depositTimestamp,
            uint8   _multiplierLevel,
            uint256 _userDepositSeconds,
            uint256 _totalDepositSeconds,
            uint256 _owed
        )
    {
        (_totalDepositSeconds, _userDepositSeconds) = getUpdatedDepositSeconds(user);
        return (
            userDeposits_numLPTokens[user][depositIdx],
            userDeposits_depositTimestamp[user][depositIdx],
            userDeposits_multiplierLevel[user][depositIdx],
            _userDepositSeconds,
            _totalDepositSeconds,
            owedTo(user)
        );
    }
}
