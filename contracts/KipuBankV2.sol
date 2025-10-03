// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// OpenZeppelin and Chainlink imports 
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title KipuBankV2
 * @author A. H. (Evolved)
 * @notice A multi-token, decentralized bank with a USD-denominated deposit cap and administrative roles.
 * @dev This contract manages deposits and withdrawals for both ETH and ERC-20 tokens. It uses a Chainlink
 *      oracle for a dynamic capital limit and OpenZeppelin's Ownable for access control.
 */
contract KipuBankV2 is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20; // Enabled secure methods
    
    // ==============================================================================
    // Type Declarations & Constants
    // ==============================================================================

    /**
     * @notice The special address used to represent the native token (ETH) internally.
     */
    address public constant NATIVE_TOKEN = address(0);
    
    // ==============================================================================
    // State Variables
    // ==============================================================================

    /**
     * @notice The instance of the Chainlink ETH/USD price feed oracle.
     */
    AggregatorV3Interface public priceFeed;
    
    /**
     * @notice The global deposit limit for the bank, expressed in USD with 8 decimal places.
     */
    uint256 public bankCapUSD;

    /**
     * @notice The nested mapping for multi-token accounting.
     * @dev Maps a user's address to another map of a token's address to their balance.
     *      userAddress => tokenAddress => amount
     */
    mapping(address => mapping(address => uint256)) public userBalances;

    /**
     * @notice A whitelist of supported ERC-20 token addresses.
     * @dev Maps a token address to a boolean indicating if it's supported (true) or not (false).
     *      ETH (address(0)) is always implicitly supported.
     */
    mapping(address => bool) public isTokenSupported;

    // ==============================================================================
    // Events & Custom Errors
    // ==============================================================================

    /**
     * @notice Emitted when a user successfully deposits funds.
     * @param user The address of the depositor.
     * @param token The address of the token deposited (NATIVE_TOKEN for ETH).
     * @param amount The amount of the token deposited.
     */
    event Deposit(address indexed user, address indexed token, uint256 amount);

    /**
     * @notice Emitted when a user successfully withdraws funds.
     * @param user The address of the recipient.
     * @param token The address of the token withdrawn (NATIVE_TOKEN for ETH).
     * @param amount The amount of the token withdrawn.
     */
    event Withdrawal(address indexed user, address indexed token, uint256 amount);
    
    /**
     * @notice Reverts if a deposit would cause the bank's total value to exceed its capital limit.
     * @param currentTotalValueUSD The current total value of all assets in the bank in USD.
     * @param depositValueUSD The USD value of the incoming deposit.
     * @param bankCapUSD The bank's capital limit in USD.
     */
    error BankCapExceeded(uint256 currentTotalValueUSD, uint256 depositValueUSD, uint256 bankCapUSD);

    /**
     * @notice Reverts if an invalid address is provided (e.g., address(0) for a token).
     * @param reason A description of why the address is invalid.
     */
    error InvalidAddress(string reason);

    /**
     * @notice Reverts if a user tries to withdraw more than their balance.
     * @param userBalance The user's current balance of the token.
     * @param amountToWithdraw The amount the user attempted to withdraw.
     */
    error InsufficientBalance(uint256 userBalance, uint256 amountToWithdraw);

    /**
     * @notice Reverts if a low-level token transfer fails.
     * @param reason A description of the failed transfer.
     */
    error TransferFailed(string reason);

    /**
     * @notice Reverts if the Chainlink oracle call fails or returns an invalid price.
     * @param reason A description of the oracle failure.
     */
    error OracleFailed(string reason);

    // ==============================================================================
    // Constructor
    // ==============================================================================

    /**
     * @notice Initializes the contract with the oracle address and the initial bank cap.
     * @param _priceFeedAddress The address of the Chainlink price feed contract.
     * @param _initialBankCapUSD The initial bank capital limit in USD, with 8 decimals.
     */
    constructor(address _priceFeedAddress, uint256 _initialBankCapUSD) Ownable(msg.sender) {
        priceFeed = AggregatorV3Interface(_priceFeedAddress);
        bankCapUSD = _initialBankCapUSD;
    }

    // ==============================================================================
    // Oracle & Conversion Functions
    // ==============================================================================

    /**
     * @notice Converts an amount of ETH to its USD value using the Chainlink oracle.
     * @dev Chainlink crypto/USD price feeds typically have 8 decimals.
     * @param _tokenAddress The address of the token (this implementation only supports NATIVE_TOKEN).
     * @param _amount The amount of the token in its smallest unit (e.g., wei for ETH).
     * @return valueUSD The value in USD, with 8 decimal places.
     */
    function getUSDValue(address _tokenAddress, uint256 _amount) public view  whenNotPaused returns (uint256 valueUSD) {
        if (_amount == 0) return 0;
        
        // @dev For this project, we only support ETH price conversion. A production system would
        // need a registry of oracles for different tokens.
        if (_tokenAddress != NATIVE_TOKEN) {
            return 0; // Or revert, depending on desired behavior for unsupported tokens.
        }

        (, int256 price, , , ) = priceFeed.latestRoundData();
        if (price <= 0) revert OracleFailed("Invalid oracle price");
        
        // ETH has 18 decimals, the price has 8 decimals.
        // Formula: (amount * price) / 10**18. Multiply first to preserve precision.
        // The final result will have 8 decimals.
        valueUSD = (_amount * uint256(price)) / 10**18;
    }

    // ==============================================================================
    // Administrative Functions
    // ==============================================================================

    /**
     * @notice Allows the owner to update the bank's capital limit.
     * @param _newBankCapUSD The new limit in USD, expressed with 8 decimals.
     */
    function setBankCap(uint256 _newBankCapUSD) external onlyOwner whenNotPaused {
        bankCapUSD = _newBankCapUSD;
    }
    
    /**
     * @notice Allows the owner to update the price feed oracle address.
     * @param _newPriceFeedAddress The new address of the oracle contract.
     */
    function setPriceFeed(address _newPriceFeedAddress) external onlyOwner whenNotPaused{
        if (_newPriceFeedAddress == address(0)) revert InvalidAddress("Price feed cannot be address zero");
        priceFeed = AggregatorV3Interface(_newPriceFeedAddress);
    }

    /**
     * @notice Pauses all token transfers. Can only be called by the owner.
     * @dev This public function acts as a gateway to the internal _pause() function
     *      from the Pausable contract, securing it with the onlyOwner modifier.
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract, resuming all token transfers. Can only be called by the owner.
     * @dev This public function acts as a gateway to the internal _unpause() function
     *      from the Pausable contract, securing it with the onlyOwner modifier.
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @notice Allows the owner to add a new ERC-20 token to the list of supported assets.
     * @param _tokenAddress The address of the ERC-20 token to support.
     */
    function supportNewToken(address _tokenAddress) external onlyOwner whenNotPaused{
        if (_tokenAddress == NATIVE_TOKEN) revert InvalidAddress("Native token is supported by default");
        isTokenSupported[_tokenAddress] = true;
    }

    /**
     * @notice Allows the owner to remove an ERC-20 token from the list of supported assets.
     * @dev This does not affect existing deposits of the token.
     * @param _tokenAddress The address of the ERC-20 token to remove.
     */
    function removeTokenSupport(address _tokenAddress) external onlyOwner whenNotPaused{
        isTokenSupported[_tokenAddress] = false;
    }


    // ==============================================================================
    // Deposit Functions
    // ==============================================================================

    /**
     * @notice Deposits ETH into the bank.
     * @dev Uses the NATIVE_TOKEN address (address(0)) for internal accounting.
     *      The function is payable to receive ETH.
     */
    function depositNative() external payable nonReentrant whenNotPaused{
        require(msg.value > 0, "Deposit amount must be positive");
        
        // Check against the USD cap. `address(this).balance` already includes msg.value.
        uint256 currentTotalValueUSD = getUSDValue(NATIVE_TOKEN, address(this).balance);
        if (currentTotalValueUSD > bankCapUSD) {
            uint256 depositValueUSD = getUSDValue(NATIVE_TOKEN, msg.value);
            revert BankCapExceeded(currentTotalValueUSD - depositValueUSD, depositValueUSD, bankCapUSD);
        }
        
        // Effect: Update user's native token balance.
        userBalances[msg.sender][NATIVE_TOKEN] += msg.value;
        emit Deposit(msg.sender, NATIVE_TOKEN, msg.value);
    }
    
    /**
     * @notice Deposits an ERC-20 token into the bank.
     * @dev The caller must first approve this contract to spend their tokens by calling `approve()` on the ERC-20 contract.
     * @param _tokenAddress The address of the ERC-20 token to deposit.
     * @param _amount The amount of tokens to deposit (in the token's smallest unit).
     */
    function depositToken(address _tokenAddress, uint256 _amount) external nonReentrant whenNotPaused{
        if (_tokenAddress == NATIVE_TOKEN) revert InvalidAddress("Use depositNative() for ETH");
        
        require(isTokenSupported[_tokenAddress], "Token is not supported");

        require(_amount > 0, "Deposit amount must be positive");
        

        // @dev As per design decisions, only native token value is checked against the cap.
        // Reverting for other tokens would be safer if no price feed is available.
        // For this exercise, we acknowledge the limitation. A production system would
        // require a price feed registry.
        
  
        
        // Interaction: Pull the tokens from the user to this contract.
        // @dev We use the "balance difference" pattern to accurately account for tokens that may
        // charge a fee on transfer (fee-on-transfer tokens). This involves checking the contract's
        // token balance before and after the `safeTransferFrom` call to ensure the user is only
        // credited for the amount that was actually received. This pattern necessarily places the
        // interaction before the effect, and its security against re-entrancy is guaranteed by the
        // `nonReentrant` modifier on this function.
        uint256 balanceBefore = IERC20(_tokenAddress).balanceOf(address(this));
        IERC20(_tokenAddress).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 balanceAfter = IERC20(_tokenAddress).balanceOf(address(this));
        uint256 amountReceived = balanceAfter - balanceBefore;
        
        // Effect: Update user's token balance first (Checks-Effects-Interactions).
        userBalances[msg.sender][_tokenAddress] += amountReceived;
        
        emit Deposit(msg.sender, _tokenAddress, _amount);
    }

    // ==============================================================================
    // Withdrawal Functions
    // ==============================================================================

    /**
     * @notice Withdraws ETH or an ERC-20 token from the bank.
     * @param _tokenAddress The address of the asset to withdraw (use address(0) for ETH).
     * @param _amount The amount to withdraw.
     */
    function withdraw(address _tokenAddress, uint256 _amount) external nonReentrant whenNotPaused{
        require(_amount > 0, "Withdraw amount must be positive");

        uint256 userBalance = userBalances[msg.sender][_tokenAddress];
        if (userBalance < _amount) revert InsufficientBalance(userBalance, _amount);
        
        // Effect: Update the state BEFORE the external call.
        userBalances[msg.sender][_tokenAddress] = userBalance - _amount;
        
        // Interaction: Send the funds to the user.
        if (_tokenAddress == NATIVE_TOKEN) {
            (bool success, ) = msg.sender.call{value: _amount}("");
            if (!success) revert TransferFailed("Native token transfer failed");
        } else {
            IERC20(_tokenAddress).safeTransfer(msg.sender, _amount);
        }
        
        emit Withdrawal(msg.sender, _tokenAddress, _amount);
    }

}