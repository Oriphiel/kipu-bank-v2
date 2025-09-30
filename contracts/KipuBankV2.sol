// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// OpenZeppelin and Chainlink imports 
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title KipuBankV2
 * @author A. H. (Evolved)
 * @notice A multi-token, decentralized bank with a USD-denominated deposit cap and administrative roles.
 * @dev This contract manages deposits and withdrawals for both ETH and ERC-20 tokens. It uses a Chainlink
 *      oracle for a dynamic capital limit and OpenZeppelin's Ownable for access control.
 */
contract KipuBankV2 is Ownable, ReentrancyGuard {
    
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

}