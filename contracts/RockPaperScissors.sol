pragma solidity 0.5.0;

import "./Stoppable.sol";

/**
 * @title RockPaperScissors
 *
 * Two players can play the rock paper and scissors game. First each player
 * commits to a move by calling function moveCommit(...) and paying a fee equal
 * to the required game deposit. Once each play has committed to a move, then
 * each player reveals the move by calling function moveReveal(...). Once each
 * player has successfully called moveReveal(...), then the contract determines
 * the result of the game and re-distributes the game funds (if required). The
 * wining player can withdraw their winning by calling function withdraw(). In
 * the event of a draw each player may successfully call withdraw(). Once all of
 * the winnings have been withdrawn the contract resets the game ready for two
 * new players.
 */
contract RockPaperScissors is Stoppable {

    uint8 constant ROCK = 1;
    uint8 constant PAPER = 2;
    uint8 constant SCISSORS = 3;

    // The value that each player has to pay to play the game.
    uint256 public gameDeposit;

    struct PlayerDetailsStruct {
        address player;
        bytes32 commitment;
        uint8 gameMove;
        uint256 balance;
    }

    PlayerDetailsStruct[2] public players;

    /**
     * @dev Check that a game move is valid.
     * @param _move - the game move.
     */
    modifier moveIsValid(uint8 _move) {
        require(ROCK <= _move && _move <= SCISSORS, "invalid move");
        _;
    }

    /**
     * @dev Log that a player has commited to a move.
     * @param player - address of player commiting move.
     * @param commitment - cryptographic hash of committed move.
     * @param bet - the amount of wei player spent to play move.
     */
    event LogMoveCommit(
        address indexed player,
        bytes32 indexed commitment,
        uint256 bet
    );

    /**
     * @dev Log that a player has their game move revealed.
     * @param player - address of player revealing move.
     * @param gameMove - the revealed game move.
     */
    event LogMoveReveal(address indexed player, uint8 gameMove);

    /**
     * @dev Log that a play has won the game.
     * @param player - address of winning player.
     * @param winnings - the amount of wei available to winning player.
     */
    event LogGameWinner(address indexed player, uint256 winnings);

    /**
     * @dev Log that a game was drawn.
     * @param player0 - address of first player.
     * @param player1 - address of second player.
     * @param winnings - the amount of wei available to both players.
     */
    event LogGameDraw(
        address indexed player0,
        address indexed player1,
        uint256 winnings
    );

    /**
     * @dev Log that a player withdraws their winnings.
     * @param sender - address of player.
     * @param amount - the amount of wei withdrawn.
     */
    event LogWithdraw(address indexed sender, uint256 amount);

    /**
     * @dev Constructor.
     * @param _gameDeposit - the value in wei required by players to play.
     */
    constructor(uint256 _gameDeposit) public {
        gameDeposit = _gameDeposit;
    }

    /**
     * @dev Generate a commitment (crytographic hash of game move).
     * @param _gameMove - the game move.
     * @param secret - secert phrase that is unique to each player and only
     * known by each player.
     * @return A commitment.
     */
    function generateCommitment(uint8 _gameMove, bytes32 secret)
        public
        view
        moveIsValid(_gameMove)
        returns (bytes32 result)
    {
        result = keccak256(abi.encode(address(this), _gameMove, secret));
    }

    /**
     * @dev This function records the game move of the calling player as a
     * commitment (cryptographic has of game move).
     * Note: This function can only be called at most once by each player during
     * the game.
     * @param _commitment - Cryptographic has of player's move.
     * @return true if successfull, false otherwise.
     * Emits event: LogMoveCommit.
     */
    function moveCommit(bytes32 _commitment)
        public
        payable
        ifAlive
        ifRunning
        returns (bool success)
    {
        require(_commitment != 0);
        require(msg.value == gameDeposit, "incorrect deposite to play game");
        require(
            (players[0].player == address(0) || players[1].player == address(0)),
            "players already exists"
        );
        if(players[0].player == address(0)){
            players[0].player = msg.sender;
            players[0].commitment = _commitment;
            players[0].balance = msg.value;
        } else if (players[1].player == address(0)) {
            require(
                players[0].player != msg.sender,
                "both players cannot be the same"
            );
            players[1].player = msg.sender;
            players[1].commitment = _commitment;
            players[1].balance = msg.value;
        } else {
            require(false, "unexpected players");
        }
        emit LogMoveCommit(msg.sender, _commitment, msg.value);
        return true;
    }

    /**
     * @dev This function will reveal the calling player's game move. To do this
     * it verifies that the inputs to the function can generate the required
     * commitment.
     * Note: This function can only be called after each player has successfully
     * called function moveCommit(...).
     * Note: After both players successfully call this functoin, it will
     * determine the result of the game and distribute the funds to the players
     * accordingly.
     * @param _gameMove - The player's game move
     * @param secret - The secret used to generate the commitment.
     * @return true if successfull, false otherwise.
     */
    function moveReveal(uint8 _gameMove, bytes32 secret)
        public
        ifAlive
        ifRunning
        moveIsValid(_gameMove)
        returns (bool success)
    {
        require(
            (players[0].player == msg.sender || players[1].player == msg.sender),
            "incorrect player"
        );
        bytes32 revealCommitment = generateCommitment(_gameMove, secret);
        require(
            (players[0].commitment == revealCommitment
            || players[1].commitment == revealCommitment),
            "failed to verify commitment"
        );
        if (players[0].commitment == revealCommitment) {
            require(players[0].gameMove == 0, "move already revealed");
            players[0].gameMove = _gameMove;
        } else if (players[1].commitment == revealCommitment) {
            require(players[1].gameMove == 0, "move already revealed");
            players[1].gameMove = _gameMove;
        } else {
            require(false, "unexpected game moves");
        }
        emit LogMoveReveal(msg.sender, _gameMove);

        // Both players have revealed, so determine the game winner
        if (players[0].gameMove != 0 && players[1].gameMove != 0) {
            uint8 idx = gameWinner(players[0].gameMove, players[1].gameMove);
            if (idx == 0 || idx == 1) {
                //players[idx.player] wins
                players[idx].balance = 2 * gameDeposit;
                players[(idx + 1) % 2].balance = 0;
                emit LogGameWinner(players[idx].player, players[idx].balance);
            } else if (idx == 2) {
                // players draw
                emit LogGameDraw(
                    players[0].player,
                    players[1].player,
                    players[0].balance
                );
            } else {
                require(false, "unxepected winner index");
            }
        }
        return success;
    }

    /**
     * @dev Given the moves made by each player determine the result of the game.
     * @param gameMove0 - the game move of first player(index 0).
     * @param gameMove1 - the game move of second player(index 1).
     * @return The index of the winning player (0 or 1) if there was a winner,
     * otherwise return 2 if game was drawn.
     */
    function gameWinner(uint8 gameMove0, uint8 gameMove1)
        internal
        pure
        moveIsValid(gameMove0)
        moveIsValid(gameMove1)
        returns (uint8 index)
    {
        if (gameMove0 == gameMove1) {
            index = 2;
        } else if (
            (gameMove0 == ROCK && gameMove1 == SCISSORS)
            || (gameMove0 == PAPER && gameMove1 == ROCK)
            || (gameMove0 == SCISSORS && gameMove1 == PAPER)
        ) {
            index = 0;
        } else if (
            (gameMove0 == ROCK && gameMove1 == PAPER)
            || (gameMove0 == PAPER && gameMove1 == SCISSORS)
            || (gameMove0 == SCISSORS && gameMove1 == ROCK)
        ) {
            index = 1;
        } else {
            require(false, "unexpected game result");
        }
    }

    /**
     * @dev Withdraw players balance at the end of the game.
     * Note: This function can only be called after each player has successfully
     * called function moveReveal(...).
     * Note: This function will check that both players have no funds remaining
     * and if so, it will reset the game (ready for the next set of players).
     * @return true if successful, false otherwise.
     * Emits event: LogWithdraw.
     */
    function withdraw()
        public
        ifAlive
        ifRunning
        moveIsValid(players[0].gameMove)
        moveIsValid(players[1].gameMove)
        returns (bool success)
    {
        require(
            (players[0].player == msg.sender || players[1].player == msg.sender),
            "incorrect player"
        );
        uint8 idx = 2;
        if (players[0].player == msg.sender) {
            idx = 0;
        } else if (players[1].player == msg.sender){
            idx = 1;
        } else {
            require(false, "invalid index");
        }
        require(players[idx].balance > 0, "no funds");
        uint256 amount = players[idx].balance;
        players[idx].balance = 0;
        emit LogWithdraw(msg.sender, amount);

        // if all players balances are zero then reset state ready for a new game
        if (players[0].balance == 0 && players[1].balance == 0) {
            delete players;
        }

        (success, ) = msg.sender.call.value(amount)("");
        require(success, "failed to transfer funds");
    }
}
