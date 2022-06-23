// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./TokenDistributor.sol";

contract MintSharingSystem is ReentrancyGuard, Ownable{
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 shares; 
        uint256 userRewardPerTokenPaid;
        uint256 rewards;
    }

    uint256 public constant PRECISION_FACTOR = 10**18;

    IERC20 public immutable textAreaToken;

    IERC20 public immutable rewardToken;

    TokenDistributor public immutable tokenDistributor;

    uint256 public currentRewardPerBlock;

    uint256 public lastRewardAdjustment;

    uint256 public lastUpdateBlock;

    uint256 public periodEndBlock;

    uint256 public rewardPerTokenStored;

    uint256 public totalShares;

    mapping(address => UserInfo) public userInfo;

    mapping(address => bool) public updateRewardUser;

    event Deposit(address indexed user, uint256 amount, uint256 harvestedAmount);
    event Harvest(address indexed user, uint256 harvestedAmount);
    event NewRewardPeriod(uint256 numberBlocks, uint256 rewardPerBlock, uint256 reward);
    event Withdraw(address indexed user, uint256 amount, uint256 harvestedAmount);

    constructor(
        address _textAreaToken,
        address _rewardToken,
        address _tokenDistributor
    ) {
        rewardToken = IERC20(_rewardToken);
        textAreaToken = IERC20(_textAreaToken);
        tokenDistributor = TokenDistributor(_tokenDistributor);

        updateRewardUser[msg.sender] = true;
    }

    function deposit(uint256 amount, bool claimRewardToken) external nonReentrant {
        require(amount >= PRECISION_FACTOR, "Deposit: Amount must be >= 1 TEXT");

        tokenDistributor.harvestAndCompound();

        _updateReward(msg.sender);

        (uint256 totalAmountStaked, ) = tokenDistributor.userInfo(address(this));

        textAreaToken.safeTransferFrom(msg.sender, address(this), amount);

        uint256 currentShares;

        if (totalShares != 0) {
            currentShares = (amount * totalShares) / totalAmountStaked;
            require(currentShares != 0, "Deposit: Fail");
        } else {
            currentShares = amount;
        }

        userInfo[msg.sender].shares += currentShares;
        totalShares += currentShares;

        uint256 pendingRewards;

        if (claimRewardToken) {
            pendingRewards = userInfo[msg.sender].rewards;

            if (pendingRewards > 0) {
                userInfo[msg.sender].rewards = 0;
                rewardToken.safeTransfer(msg.sender, pendingRewards);
            }
        }

        _checkAndAdjustTEXTTokenAllowanceIfRequired(amount, address(tokenDistributor));

        tokenDistributor.deposit(amount);

        emit Deposit(msg.sender, amount, pendingRewards);
    }

    function harvest() external nonReentrant {
        tokenDistributor.harvestAndCompound();

        _updateReward(msg.sender);

        uint256 pendingRewards = userInfo[msg.sender].rewards;

        require(pendingRewards > 0, "Harvest: Pending rewards must be > 0");

        userInfo[msg.sender].rewards = 0;

        rewardToken.safeTransfer(msg.sender, pendingRewards);

        emit Harvest(msg.sender, pendingRewards);
    }

    function withdraw(uint256 shares, bool claimRewardToken) external nonReentrant {
        require(
            (shares > 0) && (shares <= userInfo[msg.sender].shares),
            "Withdraw: Shares equal to 0 or larger than user shares"
        );

        _withdraw(shares, claimRewardToken);
    }

    function withdrawAll(bool claimRewardToken) external nonReentrant {
        _withdraw(userInfo[msg.sender].shares, claimRewardToken);
    }

    function setUpdateRewardUser(address user, bool set) external onlyOwner{
        updateRewardUser[user] = set;
    }

    function updateRewards(uint256 reward, uint256 rewardDurationInBlocks) external {
        require(updateRewardUser[msg.sender], "sender can not update.");

        if (block.number >= periodEndBlock) {
            currentRewardPerBlock = reward / rewardDurationInBlocks;
        } else {
            currentRewardPerBlock =
                (reward + ((periodEndBlock - block.number) * currentRewardPerBlock)) /
                rewardDurationInBlocks;
        }

        lastUpdateBlock = block.number;
        periodEndBlock = block.number + rewardDurationInBlocks;

        emit NewRewardPeriod(rewardDurationInBlocks, currentRewardPerBlock, reward);
    }

    function calculatePendingRewards(address user) external view returns (uint256) {
        return _calculatePendingRewards(user);
    }

    function calculateSharesValueInTEXT(address user) external view returns (uint256) {
        (uint256 totalAmountStaked, ) = tokenDistributor.userInfo(address(this));

        totalAmountStaked += tokenDistributor.calculatePendingRewards(address(this));

        return userInfo[user].shares == 0 ? 0 : (totalAmountStaked * userInfo[user].shares) / totalShares;
    }

    function calculateSharePriceInTEXT() external view returns (uint256) {
        (uint256 totalAmountStaked, ) = tokenDistributor.userInfo(address(this));

        totalAmountStaked += tokenDistributor.calculatePendingRewards(address(this));

        return totalShares == 0 ? PRECISION_FACTOR : (totalAmountStaked * PRECISION_FACTOR) / (totalShares);
    }

    function lastRewardBlock() external view returns (uint256) {
        return _lastRewardBlock();
    }


    function _calculatePendingRewards(address user) internal view returns (uint256) {
        return
            ((userInfo[user].shares * (_rewardPerToken() - (userInfo[user].userRewardPerTokenPaid))) /
                PRECISION_FACTOR) + userInfo[user].rewards;
    }

    function _checkAndAdjustTEXTTokenAllowanceIfRequired(uint256 _amount, address _to) internal {
        if (textAreaToken.allowance(address(this), _to) < _amount) {
            textAreaToken.approve(_to, type(uint256).max);
        }
    }

    function _lastRewardBlock() internal view returns (uint256) {
        return block.number < periodEndBlock ? block.number : periodEndBlock;
    }

    function _rewardPerToken() internal view returns (uint256) {
        if (totalShares == 0) {
            return rewardPerTokenStored;
        }

        return
            rewardPerTokenStored +
            ((_lastRewardBlock() - lastUpdateBlock) * (currentRewardPerBlock * PRECISION_FACTOR)) /
            totalShares;
    }

    function _updateReward(address _user) internal {
        if (block.number != lastUpdateBlock) {
            rewardPerTokenStored = _rewardPerToken();
            lastUpdateBlock = _lastRewardBlock();
        }

        userInfo[_user].rewards = _calculatePendingRewards(_user);
        userInfo[_user].userRewardPerTokenPaid = rewardPerTokenStored;
    }

    function _withdraw(uint256 shares, bool claimRewardToken) internal {
        tokenDistributor.harvestAndCompound();

        _updateReward(msg.sender);

        (uint256 totalAmountStaked, ) = tokenDistributor.userInfo(address(this));
        uint256 currentAmount = (totalAmountStaked * shares) / totalShares;

        userInfo[msg.sender].shares -= shares;
        totalShares -= shares;

        tokenDistributor.withdraw(currentAmount);

        uint256 pendingRewards;

        if (claimRewardToken) {
            pendingRewards = userInfo[msg.sender].rewards;

            if (pendingRewards > 0) {
                userInfo[msg.sender].rewards = 0;
                rewardToken.safeTransfer(msg.sender, pendingRewards);
            }
        }

        textAreaToken.safeTransfer(msg.sender, currentAmount);

        emit Withdraw(msg.sender, currentAmount, pendingRewards);
    }
}