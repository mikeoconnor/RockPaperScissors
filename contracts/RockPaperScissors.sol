pragma solidity 0.5.0;

import "./Stoppable.sol";

/**
 * @title RockPaperScissors
 *
 * Two players can play the rock paper and scissors game. First each player
 * commits to a move by calling functions player1MoveCommit(...) and
 * player2MoveCommit() paying a fee equal to the required game deposit. Once
 * each play has committed to a move, then each player reveals the move by
 * calling functions player1MoveReveal(...) and player2MoveReveal. Once each
 * player has successfully revealed their move, then the contract determines
 * the result of the game and re-distributes the game funds (if required).
 * Players can withdraw their winnings by calling functions player1Withdraw()
 * and player2Withdraw(). The winning player can withdraw the amount of twice
 * the game deposit. The losing player cannot withdraw successfully and in the
 * case of a draw each player can withdraw a sum equal to the game deposite.
 * Once all of the winnings have been withdrawn the contract resets the game
 * ready for two new players.
 */
contract RockPaperScissors is Stoppable {

    uint8 constant ROCK = 1;
    uint8 constant PAPER = 2;
    uint8 constant SCISSORS = 3;

    // The value that each player has to pay to play the game.
    uint256 public gameDeposit;

    struct GameDetailsStruct {
        address player1;
        address player2;
        bytes32 commitment1;
        bytes32 commitment2;
        uint8 gameMove1;
        uint8 gameMove2;
        mapping(address => uint256) balance;
    }

    GameDetailsStruct public game;

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
     * commitment (cryptographic hash of game move).
     * @param _commitment - Cryptographic hash of player's move.
     * @return true if successfull, false otherwise.
     * Emits event: LogMoveCommit.
     */
    function player1MoveCommit(bytes32 _commitment)
        public
        payable
        ifAlive
        ifRunning
        returns (bool success)
    {
        require(_commitment != 0, "commitment should be non zero");
        require(msg.value == gameDeposit, "incorrect deposite to play game");
        require(game.player1 == address(0), "player1 already exists");
        game.player1 = msg.sender;
        game.commitment1 = _commitment;
        game.balance[msg.sender] = gameDeposit;
        emit LogMoveCommit(msg.sender, _commitment, msg.value);
        return true;
    }

    /**
     * @dev This function records the game move of the calling player as a
     * commitment (cryptographic hash of game move).
     * @param _commitment - Cryptographic hash of player's move.
     * @return true if successfull, false otherwise.
     * Emits event: LogMoveCommit.
     */
    function player2MoveCommit(bytes32 _commitment)
        public
        payable
        ifAlive
        ifRunning
        returns (bool success)
    {
        require(_commitment != 0, "commitment should be non zero");
        require(msg.value == gameDeposit, "incorrect deposite to play game");
        require(game.player2 == address(0), "player2 already exists");
        game.player2 = msg.sender;
        game.commitment2 = _commitment;
        game.balance[msg.sender] = gameDeposit;
        emit LogMoveCommit(msg.sender, _commitment, msg.value);
        return true;
    }

    /**
     * @dev This function will reveal the calling player's game move. To do this
     * it verifies that the inputs to the function can generate the required
     * commitment.
     * @param _gameMove - The player's game move
     * @param secret - The secret used to generate the commitment.
     * @return true if successfull, false otherwise.
     * Emits events: LogMoveReveal, LogGameWinner, LogGameDraw
     */
    function player1MoveReveal(uint8 _gameMove, bytes32 secret)
        public
        ifAlive
        ifRunning
        moveIsValid(_gameMove)
        returns (bool success)
    {
        require(game.player1 == msg.sender, "incorrect player1");
        bytes32 revealCommitment = generateCommitment(_gameMove, secret);
        require(game.commitment1 == revealCommitment, "failed to verify commitment");
        require(game.gameMove1 == 0, "move already revealed");
        game.gameMove1 = _gameMove;
        emit LogMoveReveal(msg.sender, _gameMove);
        if ((game.gameMove1 != 0) && (game.gameMove2 != 0)) {
           determineGameResult();
        }
        return success;
    }

    /**
     * @dev This function will reveal the calling player's game move. To do this
     * it verifies that the inputs to the function can generate the required
     * commitment.
     * @param _gameMove - The player's game move
     * @param secret - The secret used to generate the commitment.
     * @return true if successfull, false otherwise.
     * Emits events: LogMoveReveal, LogGameWinner, LogGameDraw
     */
    function player2MoveReveal(uint8 _gameMove, bytes32 secret)
        public
        ifAlive
        ifRunning
        moveIsValid(_gameMove)
        returns (bool success)
    {
        require(game.player2 == msg.sender, "incorrect player2");
        bytes32 revealCommitment = generateCommitment(_gameMove, secret);
        require(game.commitment2 == revealCommitment, "failed to verify commitment");
        require(game.gameMove2 == 0, "move already revealed");
        game.gameMove2 = _gameMove;
        emit LogMoveReveal(msg.sender, _gameMove);
        if ((game.gameMove1 != 0) && (game.gameMove2 != 0 )) {
           determineGameResult();
        }
        return success;
    }

    /**
     * @dev This functions reveals the result of the game. That is was the
     * game won or drawn. It re-distrubutes the players funds according to the
     * outcome of the game.
     * Emits events: LogGameWinner, LogGameDraw
     */
    function determineGameResult()
        internal
        moveIsValid(game.gameMove1)
        moveIsValid(game.gameMove2)
    {
        uint8 idx = gameWinner(game.gameMove1, game.gameMove2);
        if (idx == 0) {
            // player1 wins the game
            emit LogGameWinner(game.player1, 2 * gameDeposit);
            game.balance[game.player1] = 2 * gameDeposit;
            game.balance[game.player2] = 0;
        } else if (idx == 1) {
            // player2 wins the game
            emit LogGameWinner(game.player2, 2 * gameDeposit);
            game.balance[game.player2] = 2 * gameDeposit;
            game.balance[game.player1] = 0;
        } else if (idx == 2) {
            // player1 and player2 draw the game
            emit LogGameDraw(game.player1, game.player2, gameDeposit);
        } else {
            require(false, "unexpected winner index");
        }
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
     * @dev Withdraw player's balance at the end of the game.
     * Note: This function can only be called after each player has successfully
     * revealed their move.
     * Note: This function will check that both players have no funds remaining
     * and if so, it will reset the game (ready for the next set of players).
     * @return true if successful, false otherwise.
     * Emits event: LogWithdraw.
     */
    function player1Withdraw()
        public
        ifAlive
        ifRunning
        moveIsValid(game.gameMove1)
        moveIsValid(game.gameMove2)
        returns (bool success)
    {
        require(game.player1 == msg.sender, "incorrect player1");
        require(game.balance[game.player1] > 0, "no funds");
        uint256 amount = game.balance[game.player1];
        game.balance[game.player1] = 0;
        emit LogWithdraw(msg.sender, amount);

        // if all players balances are zero then reset state ready for a new game
        if ((game.balance[game.player1] == 0) && (game.balance[game.player2] == 0)) {
            game.player1 = address(0);
            game.player2 = address(0);
            game.gameMove1 = 0;
            game.gameMove2 = 0;
            game.commitment1 = 0;
            game.commitment2 = 0;
        }

        (success, ) = msg.sender.call.value(amount)("");
        require(success, "failed to transfer funds");
    }

    /**
     * @dev Withdraw player's balance at the end of the game.
     * Note: This function can only be called after each player has successfully
     * revealed their move.
     * Note: This function will check that both players have no funds remaining
     * and if so, it will reset the game (ready for the next set of players).
     * @return true if successful, false otherwise.
     * Emits event: LogWithdraw.
     */
    function player2Withdraw()
        public
        ifAlive
        ifRunning
        moveIsValid(game.gameMove1)
        moveIsValid(game.gameMove2)
        returns (bool success)
    {
        require(game.player2 == msg.sender, "incorrect player2");
        require(game.balance[game.player2] > 0, "no funds");
        uint256 amount = game.balance[game.player2];
        game.balance[game.player2] = 0;
        emit LogWithdraw(msg.sender, amount);

        // if all players balances are zero then reset state ready for a new game
        if ((game.balance[game.player1] == 0) && (game.balance[game.player2] == 0)) {
            game.player1 = address(0);
            game.player2 = address(0);
            game.gameMove1 = 0;
            game.gameMove2 = 0;
            game.commitment1 = 0;
            game.commitment2 = 0;
        }

        (success, ) = msg.sender.call.value(amount)("");
        require(success, "failed to transfer funds");
    }
}
