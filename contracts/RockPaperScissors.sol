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
        GameMoves gameMove2;
        uint256 gameDeposit;
        uint256 expiration;
    }

    mapping(address => uint256) public balances;

    // mapping of commitment to game, i.e. 'game id' is
    // equal to commitment submitted by player1
    mapping(bytes32 => GameDetailsStruct) public games;

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
     * @dev Log that first player (player1) has commited to a move.
     * @param player1 - address of first player commiting move.
     * @param player2 - the address of second player.
     * @param commitment - cryptographic hash of committed move.
     * @param bet - the amount of wei player spent to play move.
     */
    event LogMoveCommitPlayer1(
        address indexed player1,
        address indexed player2,
        bytes32 indexed commitment,
        uint256 bet
    );

    /**
     * @dev Log that second player (player2) has made a move.
     * @param player - address of player making move.
     * @param gameId - the game ID.
     * @param gameMove - the game move.
     * @param bet - the amount of wei player spent to play move.
     */
    event LogMovePlayer2(
        address indexed player,
        bytes32 indexed gameId,
        GameMoves gameMove,
        uint256 bet
    );

    /**
     * @dev Log that a player has their game move revealed.
     * @param player - address of player revealing move.
     * @param gameId - the game ID.
     * @param gameMove - the revealed game move.
     */
    event LogMoveReveal(
        address indexed player,
        bytes32 indexed gameId,
        GameMoves gameMove
    );

    /**
     * @dev Log that a play has won the game.
     * @param player - address of winning player.
     * @param gameId - the game ID.
     * @param winnings - the amount of wei available to winning player.
     */
    event LogGameWinner(
        address indexed player,
        bytes32 indexed gameId,
        uint256 winnings
    );

    /**
     * @dev Log that a game was drawn.
     * @param player0 - address of first player.
     * @param player1 - address of second player.
     * @param gameId - the game ID.
     * @param winnings - the amount of wei available to both players.
     */
    event LogGameDraw(
        address indexed player0,
        address indexed player1,
        bytes32 indexed gameId,
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
     * @param gameId - the game ID.
     * @param amount - the amount of wei withdrawn.
     */
    event LogPlayer1ReclaimFunds(
        address indexed player,
        bytes32 indexed gameId,
        uint256 amount
    );

    /**
     * @dev Log that a second player (player2) has cancelled the game and
     * withdrawn all of the funds, because the first player (player1) has not
     * made a revealed their move within the required time period.
     * @param player - address of player.
     * @param amount - the amount of wei withdrawn.
     */
    event LogPlayer2ClaimFunds(
        address indexed player,
        bytes32 indexed gameId,
        uint256 amount
    );

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
     * @dev This function starts a particulate game by registering both
     * of the addresses of the first and second players. It then records the
     * game move of the first player (player1) as a commitment (cryptographic
     * hash of game move). Player1 also determines the game deposite (the funds
     * that player2 will have to deposit to play the game).
     * @param _commitment - Cryptographic hash of player's move.
     * @param _player2 - the address of second player.
     * @return true if successfull, false otherwise.
     * Emits event: LogMoveCommitPlayer1.
     */
    function player1MoveCommit(bytes32 _commitment, address _player2)
        public
        payable
        ifAlive
        ifRunning
        returns (bool success)
    {
        require(_commitment != 0, "commitment should be non zero");
        require(games[_commitment].player1 == address(0), "game id already used");
        require(msg.value != 0, "a game deposit is required");
        require(_player2 != msg.sender, "both players cannot be the same");
        games[_commitment].player1 = msg.sender;
        games[_commitment].player2 = _player2;
        games[_commitment].gameDeposit = msg.value;
        games[_commitment].expiration = now.add(WAITPERIOD);
        emit LogMoveCommitPlayer1(msg.sender, _player2, _commitment, msg.value);
        return true;
    }

    /**
     * @dev This function records the game move of the second player (player2).
     * This function can only be called after player1MoveCommit and player2
     * has to match the funds deposited by player1 in order to play.
     * @param _gameId - the game ID.
     * @param _gameMove - the move made by player2.
     * @return true if successfull, false otherwise.
     * Emits event: LogMovePlayer2.
     */
    function player2Move(bytes32 _gameId, GameMoves _gameMove)
        public
        payable
        ifAlive
        ifRunning
        moveIsValid(_gameMove)
        returns (bool success)
    {
        require(_gameId != 0, "invalid game Id");
        require(games[_gameId].player2 == msg.sender, "incorrect player");
        require(
            msg.value == games[_gameId].gameDeposit,
            "incorrect deposite to play game"
        );
        require(
            games[_gameId].gameMove2 == GameMoves.None,
            "player2 has already made a move"
        );
        games[_gameId].gameMove2 = _gameMove;
        games[_gameId].expiration = now.add(WAITPERIOD);
        emit LogMovePlayer2(msg.sender, _gameId, _gameMove, msg.value);
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
    function player1MoveReveal(
        GameMoves _gameMove1,
        bytes32 secret
    )
        public
        ifAlive
        ifRunning
        moveIsValid(_gameMove1)
        returns (bool success)
    {
        bytes32 _gameId = generateCommitment(_gameMove1, secret);
        require(games[_gameId].player1 == msg.sender, "incorrect player1");
        GameMoves gameMove2 = games[_gameId].gameMove2;
        require(gameMove2 != GameMoves.None, "player2 has not made a move");
        emit LogMoveReveal(msg.sender, _gameId, _gameMove1);
        determineGameResult(_gameId, _gameMove1, gameMove2);
        return true;
    }

    /**
     * @dev This functions reveals the result of the game. That is was the
     * game won or drawn. It re-distrubutes the players funds according to the
     * outcome of the game.
     * @param _gameId - the game ID.
     * @param _gameMove1 - the move of player1.
     * @param _gameMove2 - the move of player2.
     * Emits events: LogGameWinner, LogGameDraw
     */
    function determineGameResult(
        bytes32 _gameId,
        GameMoves _gameMove1,
        GameMoves _gameMove2
    )
        internal
        moveIsValid(_gameMove1)
        moveIsValid(_gameMove2)
    {
        uint8 idx = gameWinner(_gameMove1, _gameMove2);
        uint256 deposit = games[_gameId].gameDeposit;
        if (idx == 0) {
            // player1 wins the game
            emit LogGameWinner(msg.sender, _gameId, deposit.mul(2));
            balances[msg.sender] = balances[msg.sender].add(deposit.mul(2));
        } else if (idx == 1) {
            // player2 wins the game
            address player2 = games[_gameId].player2;
            emit LogGameWinner(player2, _gameId, deposit.mul(2));
            balances[player2] = balances[player2].add(deposit.mul(2));
        } else if (idx == 2) {
            // player1 and player2 draw the game
            address player2 = games[_gameId].player2;
            emit LogGameDraw(msg.sender, player2, _gameId, deposit);
            balances[msg.sender] = balances[msg.sender].add(deposit);
            balances[player2] = balances[player2].add(deposit);
        } else {
            require(false, "unexpected winner index");
        }

        // reset game
        games[_gameId].player2 = address(0);
        games[_gameId].gameMove2 = GameMoves(0);
        games[_gameId].gameDeposit = 0;
        games[_gameId].expiration = 0;
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
        index = uint8((uint(gameMove0).add(2)).sub(uint(gameMove1)) % 3);
    }

    /**
     * @dev This function allows the first player (player1) to cancel the game
     * and reclaim their funds, when the second player (player2) has not made
     * their move within the required time period.
     * @param _gameId - the game ID.
     * @return true if successful, false otherwise.
     * Emits event: LogPlayer1ReclaimFunds.
     */
    function player1ReclaimFunds(bytes32 _gameId)
        public
        ifAlive
        ifRunning
        returns (bool success)
    {
        require(_gameId != 0, "invalid game Id");
        require(games[_gameId].player1 == msg.sender, "incorrect player");
        require(
            games[_gameId].gameMove2 == GameMoves.None,
            "player2 has made a move"
        );
        require(games[_gameId].gameDeposit != 0, "no funds");
        require(now > games[_gameId].expiration, "game move not yet expired");
        balances[games[_gameId].player1] = balances[games[_gameId].player1]
            .add(games[_gameId].gameDeposit);
        emit LogPlayer1ReclaimFunds(
            games[_gameId].player1,
            _gameId,
            games[_gameId].gameDeposit
        );

        //reset game
        games[_gameId].player2 = address(0);
        games[_gameId].gameDeposit = 0;
        games[_gameId].expiration = 0;
        return true;
    }

    /**
     * @dev This function allows the second player (player2) to cancel the game
     * and reclaim all of the funds, when the first player (player1) has not
     * revealed their move within the required time period.
     * @param _gameId - the game ID.
     * @return true if successful, false otherwise.
     * Emits event: LogPlayer1ReclaimFunds.
     */
    function player2ClaimFunds(bytes32 _gameId)
        public
        ifAlive
        ifRunning
        returns (bool success)
    {
        require(_gameId != 0, "invalid game Id");
        require(games[_gameId].player2 == msg.sender, "incorrect player");
        require(games[_gameId].gameMove2 != GameMoves.None, "player2 has not made a move");
        require(
            now > games[_gameId].expiration,
            "game reveal not yet expired"
        );
        balances[games[_gameId].player2] = balances[games[_gameId].player2]
            .add(games[_gameId].gameDeposit.mul(2));
        emit LogPlayer2ClaimFunds(
            games[_gameId].player2,
            _gameId,
            games[_gameId].gameDeposit.mul(2)
        );

        //reset game
        games[_gameId].player2 = address(0);
        games[_gameId].gameMove2 = GameMoves(0);
        games[_gameId].gameDeposit = 0;
        games[_gameId].expiration = 0;
        return true;
    }

    /**
     * @dev This function allows a game player to withdraw their funds.
     * @return true if successful, false otherwise.
     * Emits event: LogWithdraw
     */
    function withdraw() public returns (bool success){
        require(balances[msg.sender] > 0, "no funds");
        uint256 amount = balances[msg.sender];
        balances[msg.sender] = 0;
        emit LogWithdraw(msg.sender, amount);
        (success, ) = msg.sender.call.value(amount)("");
        require(success, "failed to transfer funds");
    }
}
