// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TokenSplitter is Ownable, ReentrancyGuard{
    using SafeERC20 for IERC20;

    struct AccountInfo{
        uint256 shares;
        uint256 tokensDistributedToAccount;
    }

    uint256 public immutable TOTAL_SHARES;

    IERC20 public immutable textAreaToken;

    uint256 public totalTokensDistributed;

    mapping(address=>AccountInfo) public accountInfo;

    event NewSharesOwner(address indexed oldRecipient, address indexed newRecipient);
    event TokensTransferred(address indexed account, uint256 amount);

    constructor(
        address[] memory _accounts,
        uint256[] memory _shares,
        address _textAreaToken
    ) {
        require(_accounts.length == _shares.length, "Splitter: Length differ");
        require(_accounts.length > 0, "Splitter: Length must be > 0");

        uint256 currentShares;

        for (uint256 i = 0; i < _accounts.length; i++) {
            require(_shares[i] > 0, "Splitter: Shares are 0");

            currentShares += _shares[i];
            accountInfo[_accounts[i]].shares = _shares[i];
        }

        TOTAL_SHARES = currentShares;
        textAreaToken = IERC20(_textAreaToken);
    }

    function releaseTokens(address account) external nonReentrant{
        require(accountInfo[account].shares > 0, "Splitter: Account has no share");

        uint256 totalTokensReceived = textAreaToken.balanceOf(address(this)) + totalTokensDistributed;
        uint256 pendingRewards = ((totalTokensReceived * accountInfo[account].shares) / TOTAL_SHARES) -
            accountInfo[account].tokensDistributedToAccount;

        require(pendingRewards != 0, "Splitter: Nothing to transfer");

        accountInfo[account].tokensDistributedToAccount += pendingRewards;
        totalTokensDistributed += pendingRewards;

        textAreaToken.safeTransfer(account, pendingRewards);

        emit TokensTransferred(account, pendingRewards);
    }

    function updateSharesOwner(address _newRecipient, address _currentRecipient) external onlyOwner {
        require(accountInfo[_currentRecipient].shares > 0, "Owner: Current recipient has no shares");
        require(accountInfo[_newRecipient].shares == 0, "Owner: New recipient has existing shares");

        accountInfo[_newRecipient].shares = accountInfo[_currentRecipient].shares;
        accountInfo[_newRecipient].tokensDistributedToAccount = accountInfo[_currentRecipient]
            .tokensDistributedToAccount;

        accountInfo[_currentRecipient].shares = 0;
        accountInfo[_currentRecipient].tokensDistributedToAccount = 0;

        emit NewSharesOwner(_currentRecipient, _newRecipient);
    }

    function calculatePendingRewards(address account) external view returns (uint256) {
        if (accountInfo[account].shares == 0) {
            return 0;
        }

        uint256 totalTokensReceived = textAreaToken.balanceOf(address(this)) + totalTokensDistributed;
        uint256 pendingRewards = ((totalTokensReceived * accountInfo[account].shares) / TOTAL_SHARES) -
            accountInfo[account].tokensDistributedToAccount;

        return pendingRewards;
    }
}