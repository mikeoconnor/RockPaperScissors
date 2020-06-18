const RockPaperScissors = artifacts.require("RockPaperScissors");
const truffleAssert = require('truffle-assertions');
const tm = require('ganache-time-traveler');

let instance = null;
let tx = null;
const ROCK = 1;
const PAPER = 2;
const SCISSORS = 3;

contract('RockPaperScissors - Given new contract', (accounts) => {
    const owner = accounts[0];
    const alice = accounts[4];
    const bob = accounts[5];
    const GameDeposit = web3.utils.toWei('5', 'finney');
    const secretAlice = web3.utils.utf8ToHex("secretForAlice");
    
    beforeEach('set up contract', async () => {
        instance = await RockPaperScissors.new(alice, bob, {from: owner});
    });
    
    it('should allow allice (player1) to commit to a move', async() => {
        let commitment = await instance.generateCommitment(ROCK, secretAlice);
        tx = await instance.player1MoveCommit(commitment, {from: alice, value: GameDeposit});
        truffleAssert.eventEmitted(tx, 'LogMoveCommitPlayer1', evt => {
            return evt.player === alice 
                && evt.commitment === commitment
                && evt.bet.toString(10) === GameDeposit.toString(10);
        });
        let waitPeriod = await instance.WAITPERIOD();
        assert.equal(waitPeriod.toString(10), '600');
    });
    
    it('should not allow bob (player2) to make a move', async() => {
        await truffleAssert.reverts(
            instance.player2Move(PAPER, {from: bob, value: GameDeposit}),
            "game deposit not set"
        );
    });
    
    it ('should allow alice to commit to a move and then bob to make a move', async() => {
        // Alice game move commitment
        let commitment = await instance.generateCommitment(ROCK, secretAlice);
        tx = await instance.player1MoveCommit(commitment, {from: alice, value: GameDeposit});
        truffleAssert.eventEmitted(tx, 'LogMoveCommitPlayer1', evt => {
            return evt.player === alice 
                && evt.commitment === commitment
                && evt.bet.toString(10) === GameDeposit.toString(10);
        });
        
        // Bob game move
        tx = await instance.player2Move(PAPER, {from: bob, value: GameDeposit});
        truffleAssert.eventEmitted(tx, 'LogMovePlayer2', evt => {
            return evt.player === bob 
                && evt.gameMove.toString(10) === PAPER.toString(10)
                && evt.bet.toString(10) === GameDeposit.toString(10);
        });
    });
    
    it('should not allow alice to commit twice', async() => {
        let commitment = await instance.generateCommitment(ROCK, secretAlice);
        tx = await instance.player1MoveCommit(commitment, {from: alice, value: GameDeposit});
        truffleAssert.eventEmitted(tx, 'LogMoveCommitPlayer1', evt => {
            return evt.player === alice 
                && evt.commitment === commitment
                && evt.bet.toString(10) === GameDeposit.toString(10);
        });
        await truffleAssert.reverts(
            instance.player1MoveCommit(commitment, {from: alice, value: GameDeposit}),
            "player1 already commited to a move"
        );
    });
});

contract('RockPaperScissors - Given game where alice has commited to a move', (accounts) => {
    const owner = accounts[0];
    const alice = accounts[4];
    const bob = accounts[5];
    const GameDeposit = web3.utils.toWei('5', 'finney');
    const secretAlice = web3.utils.utf8ToHex("secretForAlice");

    beforeEach('set up contract and alice commit to a move', async () => {
        instance = await RockPaperScissors.new(alice, bob, {from: owner});
        let commitment = await instance.generateCommitment(ROCK, secretAlice);
        await instance.player1MoveCommit(commitment, {from: alice, value: GameDeposit});
    });

    it('should allow bob to make a move, but not two moves', async() => {
        tx = await instance.player2Move(PAPER, {from: bob, value: GameDeposit});
        truffleAssert.eventEmitted(tx, 'LogMovePlayer2', evt => {
            return evt.player === bob
                && evt.gameMove.toString(10) === PAPER.toString(10)
                && evt.bet.toString(10) === GameDeposit.toString(10);
        });
        await truffleAssert.reverts(
            instance.player2Move(PAPER, {from: bob, value: GameDeposit}),
            "player2 has already made a move"
        );
    });

    it('should not allow alice to reclaim funds before expiration period', async() => {
        await truffleAssert.reverts(
            instance.player1ReclaimFunds({from: alice}),
            "game move not yet expired"
        );
    });

});

contract('RockPaperScissors - Given game where alice has commited to a move', (accounts) => {
    const owner = accounts[0];
    const alice = accounts[4];
    const bob = accounts[5];
    const GameDeposit = web3.utils.toWei('5', 'finney');
    const secretAlice = web3.utils.utf8ToHex("secretForAlice");

    before('set up contract and alice commit to a move', async () => {
        instance = await RockPaperScissors.new(alice, bob, {from: owner});
        let commitment = await instance.generateCommitment(ROCK, secretAlice);
        await instance.player1MoveCommit(commitment, {from: alice, value: GameDeposit});
        let snapshot = await tm.takeSnapshot();
        snapshotId = snapshot.result;
    });

    after(async() => {
        await tm.revertToSnapshot(snapshotId);
    });

    it('should allow alice to reclaim funds after move expiration period', async() => {
        let SKIP_FORWARD_PERIOD = 15 * 60; //15 mins
        await tm.advanceTimeAndBlock(SKIP_FORWARD_PERIOD);
        tx = await instance.player1ReclaimFunds({from: alice});
        truffleAssert.eventEmitted(tx, 'LogPlayer1ReclaimFunds', evt => {
            return evt.player === alice
                && evt.amount.toString(10) === GameDeposit.toString(10);
        });
    });

    it('should then not allow bob to make a move', async() => {
        await truffleAssert.reverts(
            instance.player2Move(PAPER, {from: bob, value: GameDeposit}),
            "game deposit not set"
        );
    });

    it('should then allow alice to withdraw initial funds', async() => {
        tx = await instance.withdraw({from: alice})
        truffleAssert.eventEmitted(tx, 'LogWithdraw', evt => {
            return evt.sender === alice
                && evt.amount.toString(10) === GameDeposit.toString(10);
        });
    });
});

contract(
    'RockPaperScissors - Given game where alice has commited to a move and then bob has made a move',
    (accounts) => {
    const owner = accounts[0];
    const alice = accounts[4];
    const bob = accounts[5];
    const GameDeposit = web3.utils.toWei('5', 'finney');
    const secretAlice = web3.utils.utf8ToHex("secretForAlice");

    beforeEach('set up contract and moves', async() => {
        instance = await RockPaperScissors.new(alice, bob, {from: owner});
        let commitment = await instance.generateCommitment(ROCK, secretAlice);
        await instance.player1MoveCommit(commitment, {from: alice, value: GameDeposit});
        await instance.player2Move(PAPER, {from: bob, value: GameDeposit});
    });

    it('should not allow bob to claim funds before reveal expiration', async() => {
        await truffleAssert.reverts(
            instance.player2ClaimFunds({from: bob}),
            "game reveal not yet expired"
        );
    });

    it('should not allow bob to make move', async() => {
        await truffleAssert.reverts(
            instance.player2Move(PAPER, {from: bob, value: GameDeposit}),
            "player2 has already made a move"
        );
    });

    it('should not allow alice to make commitment to a move', async() => {
        let commitment = await instance.generateCommitment(ROCK, secretAlice);
        await truffleAssert.reverts(
            instance.player1MoveCommit(commitment, {from: alice, value: GameDeposit}),
            "player1 already commited to a move"
        );
    });
});

contract(
    'RockPaperScissors - Given game where alice has commited to a move and then bob has made a move',
    (accounts) => {
    const owner = accounts[0];
    const alice = accounts[4];
    const bob = accounts[5];
    const GameDeposit = web3.utils.toWei('5', 'finney');
    const secretAlice = web3.utils.utf8ToHex("secretForAlice");

    before('set up contract and moves', async () => {
        instance = await RockPaperScissors.new(alice, bob, {from: owner});
        let commitment = await instance.generateCommitment(ROCK, secretAlice);
        await instance.player1MoveCommit(commitment, {from: alice, value: GameDeposit});
        await instance.player2Move(PAPER, {from: bob, value: GameDeposit});
        let snapshot = await tm.takeSnapshot();
        snapshotId = snapshot.result;
    });

    after(async() => {
        await tm.revertToSnapshot(snapshotId);
    });

    it('should allow bob to claim the funds after reveal expiration period', async() => {
        let SKIP_FORWARD_PERIOD = 15 * 60; //15 mins
        await tm.advanceTimeAndBlock(SKIP_FORWARD_PERIOD);
        tx = await instance.player2ClaimFunds({from: bob});
        truffleAssert.eventEmitted(tx, 'LogPlayer2ClaimFunds', evt => {
            return evt.player === bob
                && evt.amount.toString(10) === (GameDeposit*2).toString(10);
        });

        // Assert that game has been reset
        let game = await instance.game();
        assert.equal(game.player1, 0);
        assert.equal(game.player2, 0);
        assert.equal(game.gameMove2.toString(10), '0');
        assert.equal(game.commitment1, 0);
        assert.equal(game.gameDeposit, 0);
        assert.equal(game.expiration, 0);
    });

    it('should then allow bob to withdraw the funds', async() => {
        tx = await instance.withdraw({from: bob})
        truffleAssert.eventEmitted(tx, 'LogWithdraw', evt => {
            return evt.sender === bob
                && evt.amount.toString(10) === (GameDeposit * 2).toString(10);
        });
    });
});

contract(
    'RockPaperScissors - Given game where alice has commited to a move and bob has made a different (winning) move',
    (accounts) => {
    const owner = accounts[0];
    const alice = accounts[4];
    const bob = accounts[5];
    const GameDeposit = web3.utils.toWei('5', 'finney');
    const secretAlice = web3.utils.utf8ToHex("secretForAlice");
    
    beforeEach('set up contract and moves', async () => {
        instance = await RockPaperScissors.new(alice, bob, {from: owner});
        let commitment = await instance.generateCommitment(ROCK, secretAlice);
        await instance.player1MoveCommit(commitment, {from: alice, value: GameDeposit});
        await instance.player2Move(PAPER, {from: bob, value: GameDeposit});
    });
    
    it('should allow alice to reveal move', async() => {
        tx = await instance.player1MoveReveal(ROCK, secretAlice, {from: alice});
        truffleAssert.eventEmitted(tx, 'LogMoveReveal', evt => {
            return evt.player === alice 
                && evt.gameMove.toString(10) === ROCK.toString(10);
        });
    });

    it('should allow alice reveal move and bob to claim winnings', async() => {
        tx = await instance.player1MoveReveal(ROCK, secretAlice, {from: alice});
        truffleAssert.eventEmitted(tx, 'LogMoveReveal', evt => {
            return evt.player === alice 
                && evt.gameMove.toString(10) === ROCK.toString(10);
        });
        
        // bob wins game because PAPER beats ROCK
        truffleAssert.eventEmitted(tx, 'LogGameWinner', evt => {
            return evt.player === bob 
                && evt.winnings.toString(10) === (GameDeposit*2).toString(10);
        });
        
        // bob can withdraw winnings
        let bobBalanceBefore = web3.utils.toBN(await web3.eth.getBalance(bob));
        tx = await instance.withdraw({from: bob});
        truffleAssert.eventEmitted(tx, 'LogWithdraw', evt => {
            return evt.sender === bob
                && evt.amount.toString(10) === (GameDeposit*2).toString(10);
        });
        let bobBalanceAfter = web3.utils.toBN(await web3.eth.getBalance(bob));
        let trans = await web3.eth.getTransaction(tx.tx);
        let gasPrice = web3.utils.toBN(trans.gasPrice);
        let gasUsed = web3.utils.toBN(tx.receipt.gasUsed);
        let gasCost = gasPrice.mul(gasUsed);
        let amountWon = web3.utils.toBN(2*GameDeposit);
        assert.isTrue(bobBalanceAfter.eq(bobBalanceBefore.add(amountWon).sub(gasCost)));

        // Assert that game has been reset
        let game = await instance.game();
        assert.equal(game.player1, 0);
        assert.equal(game.player2, 0);
        assert.equal(game.gameMove2.toString(10), '0');
        assert.equal(game.commitment1, 0);
        assert.equal(game.gameDeposit, 0);
        assert.equal(game.expiration, 0);
    });
});

contract(
    'RockPaperScissors - Given game where alice has commited to a move and bob has made the same move',
    (accounts) => {
    const owner = accounts[0];
    const alice = accounts[4];
    const bob = accounts[5];
    const GameDeposit = web3.utils.toWei('5', 'finney');
    const secretAlice = web3.utils.utf8ToHex("secretForAlice");
    
    beforeEach('set up contract and moves', async () => {
        instance = await RockPaperScissors.new(alice, bob, {from: owner});
        let commitment = await instance.generateCommitment(ROCK, secretAlice);
        await instance.player1MoveCommit(commitment, {from: alice, value: GameDeposit});
        await instance.player2Move(ROCK, {from: bob, value: GameDeposit});
    });
    
    it('should allow alice to reveal move', async() => {
        tx = await instance.player1MoveReveal(ROCK, secretAlice, {from: alice});
        truffleAssert.eventEmitted(tx, 'LogMoveReveal', evt => {
            return evt.player === alice 
                && evt.gameMove.toString(10) === ROCK.toString(10);
        });
    });

    it('should allow alice reveal move and then both alice and bob to claim winnings', async() => {
        tx = await instance.player1MoveReveal(ROCK, secretAlice, {from: alice});
        truffleAssert.eventEmitted(tx, 'LogMoveReveal', evt => {
            return evt.player === alice 
                && evt.gameMove.toString(10) === ROCK.toString(10);
        });
        
        // game is a draw because ROCK draws with ROCK
        truffleAssert.eventEmitted(tx, 'LogGameDraw', evt => {
            return evt.player0 === alice
                && evt.player1 === bob
                && evt.winnings.toString(10) === GameDeposit.toString(10);
        });
        
        // bob can withdraw winnings
        tx = await instance.withdraw({from: bob});
        truffleAssert.eventEmitted(tx, 'LogWithdraw', evt => {
            return evt.sender === bob
                && evt.amount.toString(10) === GameDeposit.toString(10);
        });
        
        // alice can withdraw winnings
        tx = await instance.withdraw({from: alice});
        truffleAssert.eventEmitted(tx, 'LogWithdraw', evt => {
            return evt.sender === alice
                && evt.amount.toString(10) === GameDeposit.toString(10);
        });

        // Assert that game has been reset
        let game = await instance.game();
        assert.equal(game.player1, 0);
        assert.equal(game.player2, 0);
        assert.equal(game.gameMove2.toString(10), '0');
        assert.equal(game.commitment1, 0);
        assert.equal(game.gameDeposit, 0);
        assert.equal(game.expiration, 0);
    });
});
