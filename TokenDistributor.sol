// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interface/ITextArea.sol";

contract TokenDistributor is ReentrancyGuard{
    using SafeERC20 for IERC20;
    using SafeERC20 for ITextArea;

    struct StakingPeriod {
        uint256 rewardPerBlockForStaking;
        uint256 rewardPerBlockForOthers;
        uint256 periodLengthInBlock;
    }

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    uint256 public constant PRECISION_FACTOR = 10**12;

    ITextArea public immutable textAreaToken;

    address public immutable tokenSplitter;

    uint256 public immutable NUMBER_PERIODS;

    uint256 public immutable START_BLOCK;

    uint256 public accTokenPerShare;

    uint256 public currentPhase;

    uint256 public endBlock;

    uint256 public lastRewardBlock;

    uint256 public rewardPerBlockForOthers;

    uint256 public rewardPerBlockForStaking;

    uint256 public totalAmountStaked;

    mapping(uint256 => StakingPeriod) public stakingPeriod;

    mapping(address => UserInfo) public userInfo;

    event Compound(address indexed user, uint256 harvestedAmount);
    event Deposit(address indexed user, uint256 amount, uint256 harvestedAmount);
    event NewRewardsPerBlock(
        uint256 indexed currentPhase,
        uint256 startBlock,
        uint256 rewardPerBlockForStaking,
        uint256 rewardPerBlockForOthers
    );
    event Withdraw(address indexed user, uint256 amount, uint256 harvestedAmount);

    constructor(
        address _textAreaToken,
        address _tokenSplitter,
        uint256 _startBlock,
        uint256[] memory _rewardsPerBlockForStaking,
        uint256[] memory _rewardsPerBlockForOthers,
        uint256[] memory _periodLengthesInBlocks,
        uint256 _numberPeriods
    ) {
        require(
            (_periodLengthesInBlocks.length == _numberPeriods) &&
                (_rewardsPerBlockForStaking.length == _numberPeriods) &&
                (_rewardsPerBlockForStaking.length == _numberPeriods),
            "Distributor: Lengthes must match numberPeriods"
        );

        uint256 nonCirculatingSupply = ITextArea(_textAreaToken).SUPPLY_CAP() -
            ITextArea(_textAreaToken).totalSupply();

        uint256 amountTokensToBeMinted;

        for (uint256 i = 0; i < _numberPeriods; i++) {
            amountTokensToBeMinted +=
                (_rewardsPerBlockForStaking[i] * _periodLengthesInBlocks[i]) +
                (_rewardsPerBlockForOthers[i] * _periodLengthesInBlocks[i]);

            stakingPeriod[i] = StakingPeriod({
                rewardPerBlockForStaking: _rewardsPerBlockForStaking[i],
                rewardPerBlockForOthers: _rewardsPerBlockForOthers[i],
                periodLengthInBlock: _periodLengthesInBlocks[i]
            });
        }

        require(amountTokensToBeMinted == nonCirculatingSupply, "Distributor: Wrong reward parameters");

        textAreaToken = ITextArea(_textAreaToken);
        tokenSplitter = _tokenSplitter;
        rewardPerBlockForStaking = _rewardsPerBlockForStaking[0];
        rewardPerBlockForOthers = _rewardsPerBlockForOthers[0];

        START_BLOCK = _startBlock;
        endBlock = _startBlock + _periodLengthesInBlocks[0];

        NUMBER_PERIODS = _numberPeriods;

        lastRewardBlock = _startBlock;
    }

    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "Deposit: Amount must be > 0");

        _updatePool();

        textAreaToken.safeTransferFrom(msg.sender, address(this), amount);

        uint256 pendingRewards;

        if (userInfo[msg.sender].amount > 0) {
            pendingRewards =
                ((userInfo[msg.sender].amount * accTokenPerShare) / PRECISION_FACTOR) -
                userInfo[msg.sender].rewardDebt;
        }

        userInfo[msg.sender].amount += (amount + pendingRewards);
        userInfo[msg.sender].rewardDebt = (userInfo[msg.sender].amount * accTokenPerShare) / PRECISION_FACTOR;

        totalAmountStaked += (amount + pendingRewards);

        emit Deposit(msg.sender, amount, pendingRewards);
    }

    function harvestAndCompound() external nonReentrant {
        _updatePool();

        uint256 pendingRewards = ((userInfo[msg.sender].amount * accTokenPerShare) / PRECISION_FACTOR) -
            userInfo[msg.sender].rewardDebt;

        if (pendingRewards == 0) {
            return;
        }

        userInfo[msg.sender].amount += pendingRewards;

        totalAmountStaked += pendingRewards;

        userInfo[msg.sender].rewardDebt = (userInfo[msg.sender].amount * accTokenPerShare) / PRECISION_FACTOR;

        emit Compound(msg.sender, pendingRewards);
    }

    function updatePool() external nonReentrant {
        _updatePool();
    }

    function withdraw(uint256 amount) external nonReentrant {
        require(
            (userInfo[msg.sender].amount >= amount) && (amount > 0),
            "Withdraw: Amount must be > 0 or lower than user balance"
        );

        _updatePool();

        uint256 pendingRewards = ((userInfo[msg.sender].amount * accTokenPerShare) / PRECISION_FACTOR) -
            userInfo[msg.sender].rewardDebt;

        userInfo[msg.sender].amount = userInfo[msg.sender].amount + pendingRewards - amount;
        userInfo[msg.sender].rewardDebt = (userInfo[msg.sender].amount * accTokenPerShare) / PRECISION_FACTOR;

        totalAmountStaked = totalAmountStaked + pendingRewards - amount;

        textAreaToken.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount, pendingRewards);
    }

    function withdrawAll() external nonReentrant {
        require(userInfo[msg.sender].amount > 0, "Withdraw: Amount must be > 0");

        _updatePool();

        uint256 pendingRewards = ((userInfo[msg.sender].amount * accTokenPerShare) / PRECISION_FACTOR) -
            userInfo[msg.sender].rewardDebt;

        uint256 amountToTransfer = userInfo[msg.sender].amount + pendingRewards;

        totalAmountStaked = totalAmountStaked - userInfo[msg.sender].amount;

        userInfo[msg.sender].amount = 0;
        userInfo[msg.sender].rewardDebt = 0;

        textAreaToken.safeTransfer(msg.sender, amountToTransfer);

        emit Withdraw(msg.sender, amountToTransfer, pendingRewards);
    }

    function calculatePendingRewards(address user) external view returns (uint256) {
        if ((block.number > lastRewardBlock) && (totalAmountStaked != 0)) {
            uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);

            uint256 tokenRewardForStaking = multiplier * rewardPerBlockForStaking;

            uint256 adjustedEndBlock = endBlock;
            uint256 adjustedCurrentPhase = currentPhase;

            while ((block.number > adjustedEndBlock) && (adjustedCurrentPhase < (NUMBER_PERIODS - 1))) {
                adjustedCurrentPhase++;

                uint256 adjustedRewardPerBlockForStaking = stakingPeriod[adjustedCurrentPhase].rewardPerBlockForStaking;

                uint256 previousEndBlock = adjustedEndBlock;

                adjustedEndBlock = previousEndBlock + stakingPeriod[adjustedCurrentPhase].periodLengthInBlock;

                uint256 newMultiplier = (block.number <= adjustedEndBlock)
                    ? (block.number - previousEndBlock)
                    : stakingPeriod[adjustedCurrentPhase].periodLengthInBlock;

                tokenRewardForStaking += (newMultiplier * adjustedRewardPerBlockForStaking);
            }

            uint256 adjustedTokenPerShare = accTokenPerShare +
                (tokenRewardForStaking * PRECISION_FACTOR) /
                totalAmountStaked;

            return (userInfo[user].amount * adjustedTokenPerShare) / PRECISION_FACTOR - userInfo[user].rewardDebt;
        } else {
            return (userInfo[user].amount * accTokenPerShare) / PRECISION_FACTOR - userInfo[user].rewardDebt;
        }
    }

    function _getMultiplier(uint256 from, uint256 to) internal view returns (uint256) {
        if (to <= endBlock) {
            return to - from;
        } else if (from >= endBlock) {
            return 0;
        } else {
            return endBlock - from;
        }
    }

    function _updateRewardsPerBlock(uint256 _newStartBlock) internal {
        currentPhase++;

        rewardPerBlockForStaking = stakingPeriod[currentPhase].rewardPerBlockForStaking;
        rewardPerBlockForOthers = stakingPeriod[currentPhase].rewardPerBlockForOthers;

        emit NewRewardsPerBlock(currentPhase, _newStartBlock, rewardPerBlockForStaking, rewardPerBlockForOthers);
    }

    function _updatePool() internal {
        if (block.number <= lastRewardBlock) {
            return;
        }

        if (totalAmountStaked == 0) {
            lastRewardBlock = block.number;
            return;
        }

        uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);

        uint256 tokenRewardForStaking = multiplier * rewardPerBlockForStaking;
        uint256 tokenRewardForOthers = multiplier * rewardPerBlockForOthers;

        while ((block.number > endBlock) && (currentPhase < (NUMBER_PERIODS - 1))) {
            _updateRewardsPerBlock(endBlock);

            uint256 previousEndBlock = endBlock;

            endBlock += stakingPeriod[currentPhase].periodLengthInBlock;

            uint256 newMultiplier = _getMultiplier(previousEndBlock, block.number);

            tokenRewardForStaking += (newMultiplier * rewardPerBlockForStaking);
            tokenRewardForOthers += (newMultiplier * rewardPerBlockForOthers);
        }

        if (tokenRewardForStaking > 0) {
            bool mintStatus = textAreaToken.mint(address(this), tokenRewardForStaking);
            if (mintStatus) {
                accTokenPerShare = accTokenPerShare + ((tokenRewardForStaking * PRECISION_FACTOR) / totalAmountStaked);
            }

            textAreaToken.mint(tokenSplitter, tokenRewardForOthers);
        }

        if (lastRewardBlock <= endBlock) {
            lastRewardBlock = block.number;
        }
    }
}