pragma solidity 0.6.12;

import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import "./BaseToken.sol";

/**
 * @title CascadeV2 is a liquidity mining contract.
 */
contract CascadeV2 is OwnableUpgradeSafe {
    using SafeMath for uint256;

    mapping(address => uint256[]) public userDepositsNumLPTokens;
    mapping(address => uint256[]) public userDepositsDepositTimestamp;
    mapping(address => uint8[])   public userDepositsMultiplierLevel;
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
    address public cascadeV1;

    event Deposit(address indexed user, uint256 tokens, uint256 timestamp);
    event Withdraw(address indexed user, uint256 withdrawnLPTokens, uint256 withdrawnBASETokens, uint256 timestamp);
    event UpgradeMultiplierLevel(address indexed user, uint256 depositIndex, uint256 oldLevel, uint256 newLevel, uint256 timestamp);
    event Migrate(address indexed user, uint256 lpTokens, uint256 rewardTokens);
    event AddRewards(uint256 tokens, uint256 shares, uint256 vestingStart, uint256 vestingDuration, uint256 totalTranches);
    event SetBASEToken(address token);
    event SetLPToken(address token);
    event SetCascadeV1(address cascadeV1);
    event UpdateDepositSeconds(address user, uint256 totalDepositSeconds, uint256 userDepositSeconds);
    event AdminRescueTokens(address token, address recipient, uint256 amount);

    /**
     * @dev Called by the OpenZeppelin "upgrades" library to initialize the contract in lieu of a constructor.
     */
    function initialize()
        external
        initializer
    {
        __Ownable_init();
    }

    /**
     * Admin
     */

    /**
     * @notice Changes the address of the LP token for which staking is allowed.
     * @param _lpToken The address of the LP token.
     */
    function setLPToken(address _lpToken)
        external
        onlyOwner
    {
        require(_lpToken != address(0x0), "zero address");
        lpToken = IERC20(_lpToken);
        emit SetLPToken(_lpToken);
    }

    /**
     * @notice Changes the address of the BASE token.
     * @param _baseToken The address of the BASE token.
     */
    function setBASEToken(address _baseToken)
        external
        onlyOwner
    {
        require(_baseToken != address(0x0), "zero address");
        BASE = BaseToken(_baseToken);
        emit SetBASEToken(_baseToken);
    }

    /**
     * @notice Changes the address of Cascade v1 (for purposes of migration).
     * @param _cascadeV1 The address of Cascade v1.
     */
    function setCascadeV1(address _cascadeV1)
        external
        onlyOwner
    {
        require(_cascadeV1 != address(0x0), "zero address");
        cascadeV1 = _cascadeV1;
        emit SetCascadeV1(_cascadeV1);
    }

    /**
     * @notice Allows the admin to withdraw tokens mistakenly sent into the contract.
     * @param token The address of the token to rescue.
     * @param recipient The recipient that the tokens will be sent to.
     * @param amount How many tokens to rescue.
     */
    function adminRescueTokens(address token, address recipient, uint256 amount)
        external
        onlyOwner
    {
        require(token != address(0x0), "zero address");
        require(recipient != address(0x0), "bad recipient");
        require(amount > 0, "zero amount");

        bool ok = IERC20(token).transfer(recipient, amount);
        require(ok, "transfer");

        emit AdminRescueTokens(token, recipient, amount);
    }

    /**
     * @notice Allows the owner to add another tranche of rewards.
     * @param numTokens How many tokens to add to the tranche.
     * @param vestingStart The timestamp upon which vesting of this tranche begins.
     * @param vestingDuration The duration over which the tokens fully unlock.
     */
    function addRewards(uint256 numTokens, uint256 vestingStart, uint256 vestingDuration)
        external
        onlyOwner
    {
        require(numTokens > 0, "zero amount");
        require(vestingStart > 0, "zero vesting start");

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

    /**
     * @notice Allows a user to deposit LP tokens into the Cascade.
     * @param amount How many tokens to stake.
     */
    function deposit(uint256 amount)
        external
    {
        require(amount > 0, "zero amount");

        uint256 allowance = lpToken.allowance(msg.sender, address(this));
        require(amount <= allowance, "allowance");

        updateDepositSeconds(msg.sender);

        totalDepositedLevel1 = totalDepositedLevel1.add(amount);
        userTotalLPTokensLevel1[msg.sender] = userTotalLPTokensLevel1[msg.sender].add(amount);
        userDepositsNumLPTokens[msg.sender].push(amount);
        userDepositsDepositTimestamp[msg.sender].push(now);
        userDepositsMultiplierLevel[msg.sender].push(1);

        bool ok = lpToken.transferFrom(msg.sender, address(this), amount);
        require(ok, "transferFrom");

        emit Deposit(msg.sender, amount, now);
    }

    /**
     * @notice Allows a user to withdraw LP tokens from the Cascade.
     * @param amount How many tokens to unstake.
     */
    function withdrawLPTokens(uint256 amount)
        external
    {
        require(amount > 0, "zero amount");

        updateDepositSeconds(msg.sender);

        uint256 totalAmountToWithdraw;
        uint256 totalDepositSecondsToBurn;
        uint256 amountToWithdrawLevel1;
        uint256 amountToWithdrawLevel2;
        uint256 amountToWithdrawLevel3;
        for (uint256 i = userDepositsNumLPTokens[msg.sender].length - 1; i >= 0; i++) {
            uint256 lpTokens;
            if (totalAmountToWithdraw.add(lpTokens) < amount) {
                lpTokens = userDepositsNumLPTokens[msg.sender][i];
                userDepositsNumLPTokens[msg.sender].pop();
                userDepositsDepositTimestamp[msg.sender].pop();
            } else {
                lpTokens = amount.sub(totalAmountToWithdraw);
                userDepositsNumLPTokens[msg.sender][i] = lpTokens.sub(lpTokens);
            }

            uint256 depositSecondsToBurn;
            uint256 age = userDepositsDepositTimestamp[msg.sender][i];
            uint8 multiplier = userDepositsMultiplierLevel[msg.sender][i];
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

    /**
     * @notice Allows a user to upgrade their deposit-seconds multipler for the given deposits.
     * @param deposits A list of the indices of deposits to be upgraded.
     */
    function upgradeMultiplierLevel(uint256[] memory deposits)
        external
    {
        require(deposits.length > 0, "no deposits");

        updateDepositSeconds(msg.sender);

        for (uint256 i = 0; i < deposits.length; i++) {
            uint256 idx = deposits[i];
            uint256 age = now.sub(userDepositsDepositTimestamp[msg.sender][idx]);

            if (age <= 30 days || userDepositsMultiplierLevel[msg.sender][idx] == 3) {
                continue;
            }

            uint8 oldLevel = userDepositsMultiplierLevel[msg.sender][idx];
            uint256 tokensDeposited = userDepositsNumLPTokens[msg.sender][idx];

            if (age > 30 days && userDepositsMultiplierLevel[msg.sender][idx] == 1) {
                uint256 secondsSinceLevel2 = age - 30 days;
                uint256 extraDepositSeconds = tokensDeposited.mul(secondsSinceLevel2);
                totalDepositedLevel1 = totalDepositedLevel1.sub(tokensDeposited);
                totalDepositedLevel2 = totalDepositedLevel2.add(tokensDeposited);
                totalDepositSeconds  = totalDepositSeconds.add(extraDepositSeconds);

                userTotalLPTokensLevel1[msg.sender] = userTotalLPTokensLevel1[msg.sender].sub(tokensDeposited);
                userTotalLPTokensLevel2[msg.sender] = userTotalLPTokensLevel2[msg.sender].add(tokensDeposited);
                userDepositSeconds[msg.sender] = userDepositSeconds[msg.sender].add(extraDepositSeconds);
                userDepositsMultiplierLevel[msg.sender][idx] = 2;
            }

            if (age > 60 days && userDepositsMultiplierLevel[msg.sender][idx] == 2) {
                uint256 secondsSinceLevel3 = age - 60 days;
                uint256 extraDepositSeconds = tokensDeposited.mul(secondsSinceLevel3);
                totalDepositedLevel2 = totalDepositedLevel2.sub(tokensDeposited);
                totalDepositedLevel3 = totalDepositedLevel3.add(tokensDeposited);
                totalDepositSeconds  = totalDepositSeconds.add(extraDepositSeconds);

                userTotalLPTokensLevel2[msg.sender] = userTotalLPTokensLevel2[msg.sender].sub(tokensDeposited);
                userTotalLPTokensLevel3[msg.sender] = userTotalLPTokensLevel3[msg.sender].add(tokensDeposited);
                userDepositSeconds[msg.sender] = userDepositSeconds[msg.sender].add(extraDepositSeconds);
                userDepositsMultiplierLevel[msg.sender][idx] = 3;
            }
            emit UpgradeMultiplierLevel(msg.sender, idx, oldLevel, userDepositsMultiplierLevel[msg.sender][idx], block.timestamp);
        }
    }

    /**
     * @notice Called by Cascade v1 to migrate funds into Cascade v2.
     * @param user The user for whom to migrate funds.
     * @param numLPTokens How many LP tokens to migrate.
     * @param numRewardTokens How many BASE tokens to migrate.
     * @param multiplier The user's current multiplier.
     * @param depositTimestamp The timestamp of the user's v1 deposit.
     * @param depositSeconds The user's current deposit-seconds.
     */
    function migrate(
        address user,
        uint256 numLPTokens,
        uint256 numRewardTokens,
        uint8   multiplier,
        uint256 depositTimestamp,
        uint256 depositSeconds
    )
        external
    {
        require(msg.sender == cascadeV1, "only cascade v1");
        require(user != address(0x0), "zero address");
        require(numLPTokens > 0, "no stake");
        require(multiplier > 0, "zero multiplier");
        require(depositTimestamp > 0, "zero timestamp");
        require(depositSeconds > 0, "zero seconds");

        updateDepositSeconds(user);

        userDepositsNumLPTokens[user].push(numLPTokens);
        userDepositsMultiplierLevel[user].push(multiplier);
        userDepositsDepositTimestamp[user].push(depositTimestamp);
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

    /**
     * @notice Updates the global deposit-seconds accounting as well as that of the given user.
     * @param user The user for whom to update the accounting.
     */
    function updateDepositSeconds(address user)
        public
    {
        (totalDepositSeconds, userDepositSeconds[user]) = getUpdatedDepositSeconds(user);
        lastAccountingUpdateTimestamp = now;
        userLastAccountingUpdateTimestamp[user] = now;
        emit UpdateDepositSeconds(user, totalDepositSeconds, userDepositSeconds[user]);
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

    /**
     * @notice Returns the global deposit-seconds as well as that of the given user.
     * @param user The user for whom to fetch the current deposit-seconds.
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

    /**
     * @notice Returns the BASE rewards owed to the given user.
     * @param user The user for whom to fetch the current rewards.
     */
    function owedTo(address user)
        public
        view
        returns (uint256)
    {
        require(user != address(0x0), "zero address");

        (uint256 totalDS, uint256 userDS) = getUpdatedDepositSeconds(user);
        if (totalDS == 0) {
            return 0;
        }
        return rewardsPool().mul(userDS).div(totalDS);
    }

    /**
     * @notice Returns the total rewards pool.
     */
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

    /**
     * @notice Returns various statistics about the given user and deposit.
     * @param user The user to fetch.
     * @param depositIdx The index of the given user's deposit to fetch.
     */
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
        require(user != address(0x0), "zero address");

        (_totalDepositSeconds, _userDepositSeconds) = getUpdatedDepositSeconds(user);
        return (
            userDepositsNumLPTokens[user][depositIdx],
            userDepositsDepositTimestamp[user][depositIdx],
            userDepositsMultiplierLevel[user][depositIdx],
            _userDepositSeconds,
            _totalDepositSeconds,
            owedTo(user)
        );
    }
}
