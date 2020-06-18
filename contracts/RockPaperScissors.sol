pragma solidity 0.5.0;

import "./Stoppable.sol";
import "./SafeMath.sol";

/**
 * @title RockPaperScissors
 *
 * Two players can play the rock paper and scissors game. First player1
 * commits to a move by calling functions player1MoveCommit(...) and also
 * sets the amount of wei's to play the game.
 * Player2 then makes a move by calling player2Move(...) and paying a fee
 * equal to the required game deposit. Player1 then reveals their move by
 * calling player1MoveReveal(...). The contract then determines the result
 * of the game and re-distributes the game funds (if required).
 * Players can withdraw their winnings by calling function withdraw().
 * The winning player can withdraw the amount of twice the game deposit.
 * The losing player cannot withdraw successfully and in the
 * case of a draw each player can withdraw a sum equal to the game deposite.
 * Note: If player2 fails to make a move in a specified period then player1
 * may cancel the game and reclaim their funds by calling function
 * player1ReclaimFunds.
 * Note: If player1 fails to reveal their game move in a specified period then
 * player2 may claim all of the funds in the game by calling function
 * player2ClaimFunds.
 */
contract RockPaperScissors is Stoppable {
    using SafeMath for uint;

    // The allowed game moves
    enum GameMoves {
        None,
        Rock,
        Paper,
        Scissors
    }

    struct GameDetailsStruct {
        address player1;
        address player2;
        bytes32 commitment1;
        GameMoves gameMove2;
        uint256 gameDeposit;
        uint256 expiration;
    }

    mapping(address => uint256) balances;

    GameDetailsStruct public game;

    // Wait for a period of 10 mins
    uint256 public constant WAITPERIOD = 600;

    /**
     * @dev Check that a game move is valid.
     * @param _move - the game move.
     */
    modifier moveIsValid(GameMoves _move) {
        require(GameMoves.Rock <= _move && _move <= GameMoves.Scissors, "invalid move");
        _;
    }

    /**
     * @dev Log that RockPaperScissors contract has been created with two
     * players.
     * @param player1 - the first game player.
     * @param player2 - the second game player.
     */
    event LogGameCreation(address indexed player1, address indexed player2);

    /**
     * @dev Log that first player (player1) has commited to a move.
     * @param player - address of player commiting move.
     * @param commitment - cryptographic hash of committed move.
     * @param bet - the amount of wei player spent to play move.
     */
    event LogMoveCommitPlayer1(
        address indexed player,
        bytes32 indexed commitment,
        uint256 bet
    );

    /**
     * @dev Log that second player (player2) has made a move.
     * @param player - address of player making move.
     * @param gameMove - the game move.
     * @param bet - the amount of wei player spent to play move.
     */
    event LogMovePlayer2(
        address indexed player,
        GameMoves gameMove,
        uint256 bet
    );

    /**
     * @dev Log that a player has their game move revealed.
     * @param player - address of player revealing move.
     * @param gameMove - the revealed game move.
     */
    event LogMoveReveal(address indexed player, GameMoves gameMove);

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
     * @dev Log that a first player (player1) has cancelled the game and
     * withdrawn their funds, because the second player (player2) has not made
     * a move within the required time period.
     * @param player - address of player.
     * @param amount - the amount of wei withdrawn.
     */
    event LogPlayer1ReclaimFunds(address indexed player, uint256 amount);

    /**
     * @dev Log that a second player (player2) has cancelled the game and
     * withdrawn all of the funds, because the first player (player1) has not
     * made a revealed their move within the required time period.
     * @param player - address of player.
     * @param amount - the amount of wei withdrawn.
     */
    event LogPlayer2ClaimFunds(address indexed player, uint256 amount);

    /**
     * @dev The constructor for the rock paper scissors game.
     * @param _player1 - the address of the first player.
     * @param _player2 - the address of the second player.
     */
    constructor(address _player1, address _player2) public {
        require(_player1 != address(0), "invalid address for player1");
        require(_player2 != address(0), "invalid address for player2");
        require(_player1 != _player2, "player1 equals player2");
        game.player1 = _player1;
        game.player2 = _player2;
        emit LogGameCreation(_player1, _player2);
    }

    /**
     * @dev Generate a commitment (crytographic hash of game move).
     * @param _gameMove - the game move.
     * @param secret - secert phrase that is unique to each player and only
     * known by each player.
     * @return A commitment.
     */
    function generateCommitment(GameMoves _gameMove, bytes32 secret)
        public
        view
        moveIsValid(_gameMove)
        returns (bytes32 result)
    {
        result = keccak256(abi.encode(address(this), _gameMove, secret));
    }

    /**
     * @dev This function records the game move of the first player (player1)
     * as a commitment (cryptographic hash of game move). Player1 also
     * determines the game deposite (the funds that player2 will have to
     * deposit to play the game).
     * @param _commitment - Cryptographic hash of player's move.
     * @return true if successfull, false otherwise.
     * Emits event: LogMoveCommitPlayer1.
     */
    function player1MoveCommit(bytes32 _commitment)
        public
        payable
        ifAlive
        ifRunning
        returns (bool success)
    {
        require(_commitment != 0, "commitment should be non zero");
        require(game.player1 == msg.sender, "incorrect player");
        require(msg.value != 0, "a game deposit is required");
        require(game.commitment1 == 0, "player1 already commited to a move");
        game.commitment1 = _commitment;
        game.gameDeposit = msg.value;
        game.expiration = now + WAITPERIOD;
        emit LogMoveCommitPlayer1(msg.sender, _commitment, msg.value);
        return true;
    }

    /**
     * @dev This function records the game move of the second player (player2).
     * This function can only be called after player1MoveCommit and player2
     * has to match the funds deposited by player1 in order to play.
     * @param _gameMove - the move made by player2.
     * @return true if successfull, false otherwise.
     * Emits event: LogMovePlayer2.
     */
    function player2Move(GameMoves _gameMove)
        public
        payable
        ifAlive
        ifRunning
        moveIsValid(_gameMove)
        returns (bool success)
    {
        require(game.gameDeposit > 0, "game deposit not set");
        require(game.player2 == msg.sender, "incorrect player");
        require(msg.value == game.gameDeposit, "incorrect deposite to play game");
        require(game.gameMove2 == GameMoves.None, "player2 has already made a move");
        game.gameMove2 = _gameMove;
        game.expiration = now + WAITPERIOD;
        emit LogMovePlayer2(msg.sender, _gameMove, msg.value);
        return true;
    }

    /**
     * @dev This function will reveal player1's game move. To do this
     * it verifies that the inputs to the function can generate the required
     * commitment.
     * Note: This function also determines the result of the game and
     * redistributes the funds accordingly.
     * @param _gameMove1 - The game move of player1.
     * @param secret - The secret used to generate the commitment.
     * @return true if successfull, false otherwise.
     * Emits events: LogMoveReveal, LogGameWinner, LogGameDraw
     */
    function player1MoveReveal(GameMoves _gameMove1, bytes32 secret)
        public
        ifAlive
        ifRunning
        moveIsValid(_gameMove1)
        returns (bool success)
    {
        require(game.player1 == msg.sender, "incorrect player1");
        require(
            game.commitment1 == generateCommitment(_gameMove1, secret),
            "failed to verify commitment"
        );
        emit LogMoveReveal(msg.sender, _gameMove1);
        determineGameResult(_gameMove1, game.gameMove2);
        return true;
    }

    /**
     * @dev This functions reveals the result of the game. That is was the
     * game won or drawn. It re-distrubutes the players funds according to the
     * outcome of the game.
     * @param _gameMove1 - the move of player1.
     * @param _gameMove2 - the move of player2.
     * Emits events: LogGameWinner, LogGameDraw
     */
    function determineGameResult(GameMoves _gameMove1, GameMoves _gameMove2)
        internal
        moveIsValid(_gameMove1)
        moveIsValid(_gameMove2)
    {
        uint8 idx = gameWinner(_gameMove1, _gameMove2);
        if (idx == 0) {
            // player1 wins the game
            emit LogGameWinner(game.player1, 2 * game.gameDeposit);
            balances[game.player1] = game.gameDeposit.mul(2);
            balances[game.player2] = 0;
        } else if (idx == 1) {
            // player2 wins the game
            emit LogGameWinner(game.player2, 2 * game.gameDeposit);
            balances[game.player2] = game.gameDeposit.mul(2);
            balances[game.player1] = 0;
        } else if (idx == 2) {
            // player1 and player2 draw the game
            emit LogGameDraw(game.player1, game.player2, game.gameDeposit);
            balances[game.player1] = game.gameDeposit;
            balances[game.player2] = game.gameDeposit;
        } else {
            require(false, "unexpected winner index");
        }

        // reset game
        game.player1 = address(0);
        game.player2 = address(0);
        game.gameMove2 = GameMoves(0);
        game.commitment1 = 0;
        game.gameDeposit = 0;
        game.expiration = 0;
    }

    /**
     * @dev Given the moves made by each player determine the result of the game.
     * @param gameMove0 - the game move of first player(index 0).
     * @param gameMove1 - the game move of second player(index 1).
     * @return The index of the winning player (0 or 1) if there was a winner,
     * otherwise return 2 if game was drawn.
     */
    function gameWinner(GameMoves gameMove0, GameMoves gameMove1)
        internal
        pure
        moveIsValid(gameMove0)
        moveIsValid(gameMove1)
        returns (uint8 index)
    {
        if (gameMove0 == gameMove1) {
            index = 2;
        } else if (
            (gameMove0 == GameMoves.Rock && gameMove1 == GameMoves.Scissors)
            || (gameMove0 == GameMoves.Paper && gameMove1 == GameMoves.Rock)
            || (gameMove0 == GameMoves.Scissors && gameMove1 == GameMoves.Paper)
        ) {
            index = 0;
        } else if (
            (gameMove0 == GameMoves.Rock && gameMove1 == GameMoves.Paper)
            || (gameMove0 == GameMoves.Paper && gameMove1 == GameMoves.Scissors)
            || (gameMove0 == GameMoves.Scissors && gameMove1 == GameMoves.Rock)
        ) {
            index = 1;
        } else {
            require(false, "unexpected game result");
        }
    }

    /**
     * @dev This function allows the first player (player1) to cancel the game
     * and reclaim their funds, when the second player (player2) has not made
     * their move within the required time period.
     * @return true if successful, false otherwise.
     * Emits event: LogPlayer1ReclaimFunds.
     */
    function player1ReclaimFunds()
        public
        ifAlive
        ifRunning
        returns (bool success)
    {
        require(game.player1 == msg.sender, "incorrect player");
        require(game.gameMove2 == GameMoves.None, "player2 has made a move");
        require(now > game.expiration, "game move not yet expired");
        balances[game.player1] = game.gameDeposit;
        emit LogPlayer1ReclaimFunds(game.player1, game.gameDeposit);

        //reset game
        game.player1 = address(0);
        game.player2 = address(0);
        game.commitment1 = 0;
        game.gameDeposit = 0;
        game.expiration = 0;
        return true;
    }

    /**
     * @dev This function allows the second player (player2) to cancel the game
     * and reclaim all of the funds, when the first player (player1) has not
     * revealed their move within the required time period.
     * @return true if successful, false otherwise.
     * Emits event: LogPlayer1ReclaimFunds.
     */
    function player2ClaimFunds()
        public
        ifAlive
        ifRunning
        returns (bool success)
    {
        require(game.player2 == msg.sender, "incorrect player");
        require(game.commitment1 != 0, "player1 has not commited to a move");
        require(now > game.expiration, "game reveal not yet expired");
        balances[game.player2] = game.gameDeposit.mul(2);
        emit LogPlayer2ClaimFunds(game.player2, balances[game.player2]);

        //reset game
        game.player1 = address(0);
        game.player2 = address(0);
        game.commitment1 = 0;
        game.gameMove2 = GameMoves(0);
        game.gameDeposit = 0;
        game.expiration = 0;
        return true;
    }

    /**
     * @dev This function allows a game player to withdraw their funds.
     * @return true if successful, false otherwise.
     * Emits event: LogWithdraw
     */
    function withdraw() public returns (bool success){
        address sender = msg.sender;
        require(balances[sender] > 0, "no funds");
        uint256 amount = balances[sender];
        balances[sender] = 0;
        emit LogWithdraw(sender, amount);
        (success, ) = msg.sender.call.value(amount)("");
        require(success, "failed to transfer funds");
    }
}
