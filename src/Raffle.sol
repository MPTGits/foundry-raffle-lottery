// SPDX-License-Identifier: MIT

// Pragma statements
// Import statements
// Events
// Errors
// Interfaces
// Libraries
// Contracts

// Inside each contract, library or interface, use the following order:

// Type declarations
// State variables
// Events
// Errors
// Modifiers
// Functions

// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private

pragma solidity ^0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title A sample Raffle contract
 * @author Martin Todorov
 * @notice A raffle contract that allows users to buy tickets and draw a winner.
 * @dev Implements Chainlink VRFv2.5 to generate a random raffle winner.
 */
contract Raffle is VRFConsumerBaseV2Plus {
    /* Errors*/
    error Raffle__NotEnoughEthToEnterRaffle();
    error Rafffle_TransferFailed();
    error Raffle_RaffleNotOpen();
    error Raffle_UpkeepNotNeeded(
        uint256 balance,
        uint256 players,
        RaffleState state
    );

    /* Type declarations */
    enum RaffleState {
        OPEN, //0
        CALCULATING //1
    }

    /* State Variables */
    uint256 private immutable i_entranceFee;
    // @dev Duration of the raffle in seconds
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint8 private constant NUM_WORDS = 1;
    uint32 private immutable i_callbackGasLimit;
    uint256 private immutable i_interval;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subId;
    address payable[] private s_players;
    address payable private s_recentWinner;
    uint256 private s_lastTimestamp;
    RaffleState private s_raffleState;

    /* Events */
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 _entranceFee,
        uint256 _interval,
        address _vrfCoordinator,
        bytes32 gasLane, // the keyHash
        uint32 _callbackGasLimit,
        uint256 subId
    ) VRFConsumerBaseV2Plus(_vrfCoordinator) {
        i_entranceFee = _entranceFee;
        i_interval = _interval;
        i_keyHash = gasLane;
        i_subId = subId;
        i_callbackGasLimit = _callbackGasLimit;

        s_lastTimestamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {
        //Option 1
        // require(msg.value >= i_entranceFee, "Not enough ETH sent");
        //Option 2
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthToEnterRaffle();
        }
        if (s_raffleState == RaffleState.CALCULATING) {
            revert Raffle_RaffleNotOpen();
        }
        //Option 3
        // require(msg.value >= i_entranceFee, NotEnoughEthToEnterRaffle());
        s_players.push(payable(msg.sender));
        emit RaffleEntered(msg.sender);
    }

    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData*/) {
        bool timeHasPassed = (block.timestamp - s_lastTimestamp) >= i_interval;
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;
        return (upkeepNeeded, "");
    }

    //1.Get a random number
    //2.User that number to pick a winner
    //3.Be automatically called when the raffle is over
    function performeUpkeep(bytes calldata /* perofrmData */) external {
        // Current aproximate time according to the blockchain
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle_UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                s_raffleState
            );
        }
        // 1. Request RNG
        // 2. Get RNG
        // It is a two transaction process
        s_raffleState = RaffleState.CALCULATING;
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });

        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);

        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords
    ) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];

        s_recentWinner = recentWinner;
        s_players = new address payable[](0);
        s_lastTimestamp = block.timestamp;
        emit WinnerPicked(s_recentWinner);

        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Rafffle_TransferFailed();
        }
        s_raffleState = RaffleState.OPEN;
    }

    function getEntranceFee() public view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimestamp;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }
}
