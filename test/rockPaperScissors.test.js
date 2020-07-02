const RockPaperScissors = artifacts.require("RockPaperScissors");
const truffleAssert = require('truffle-assertions');
const tm = require('ganache-time-traveler');

const {toWei, utf8ToHex} = web3.utils;

const ROCK = 1;
const PAPER = 2;
const SCISSORS = 3;

contract('RockPaperScissors - Given new contract', (accounts) => {
    const owner = accounts[0];
    const alice = accounts[4];
    const bob = accounts[5];
    const gameDeposit = toWei('5', 'finney');
    const secretAlice = utf8ToHex("secretForAlice");
    let instance = null;
    
    beforeEach('set up contract', async () => {
        instance = await RockPaperScissors.new({from: owner});
    });
    
    it('should allow allice (player1) to commit to a move', async() => {
        const commitment = await instance.generateCommitment(ROCK, secretAlice);
        const tx = await instance.player1MoveCommit(commitment, bob, {from: alice, value: gameDeposit});
        truffleAssert.eventEmitted(tx, 'LogMoveCommitPlayer1', evt => {
            return evt.player1 === alice
                && evt.player2 === bob
                && evt.commitment === commitment
                && evt.bet.toString(10) === gameDeposit.toString(10);
        });
        const waitPeriod = await instance.WAITPERIOD();
        assert.equal(waitPeriod.toString(10), '600');
    });
    
    it('should not allow bob (player2) to make a move', async() => {
        const gId = await instance.generateCommitment(PAPER, web3.utils.utf8ToHex("bob's secret"));
        await truffleAssert.reverts(
            instance.player2Move(gId, PAPER, {from: bob, value: gameDeposit}),
            "incorrect player"
        );
    });
    
    it ('should allow alice to commit to a move and then bob to make a move', async() => {
        // Alice game move commitment
        const gId = await instance.generateCommitment(ROCK, secretAlice);
        await instance.player1MoveCommit(gId, bob, {from: alice, value: gameDeposit});
        
        // Bob game move
        const tx = await instance.player2Move(gId, PAPER, {from: bob, value: gameDeposit});
        truffleAssert.eventEmitted(tx, 'LogMovePlayer2', evt => {
            return evt.player === bob
                && evt.gameId === gId
                && evt.gameMove.toString(10) === PAPER.toString(10)
                && evt.bet.toString(10) === gameDeposit.toString(10);
        });
    });
    
    it('should not allow alice to commit twice', async() => {
        const gId = await instance.generateCommitment(ROCK, secretAlice);
        await instance.player1MoveCommit(gId, bob, {from: alice, value: gameDeposit});
        await truffleAssert.reverts(
            instance.player1MoveCommit(gId, bob, {from: alice, value: gameDeposit}),
            "game id already used"
        );
    });
});

describe('RockPaperScissors - Given game where alice has commited to a move', () =>{
    contract('Before expiration', (accounts) => {
        const owner = accounts[0];
        const alice = accounts[4];
        const bob = accounts[5];
        const gameDeposit = toWei('5', 'finney');
        const secretAlice = utf8ToHex("secretForAlice");
        let instance = null;
        let gId = null;

        beforeEach('set up contract and alice commit to a move', async () => {
            instance = await RockPaperScissors.new({from: owner});
            gId = await instance.generateCommitment(ROCK, secretAlice);
            await instance.player1MoveCommit(gId, bob, {from: alice, value: gameDeposit});
        });

        it('should allow bob to make a move, but not two moves', async() => {
            const tx = await instance.player2Move(gId, PAPER, {from: bob, value: gameDeposit});
            truffleAssert.eventEmitted(tx, 'LogMovePlayer2', evt => {
                return evt.player === bob
                    && evt.gameId === gId
                    && evt.gameMove.toString(10) === PAPER.toString(10)
                    && evt.bet.toString(10) === gameDeposit.toString(10);
            });
            await truffleAssert.reverts(
                instance.player2Move(gId, PAPER, {from: bob, value: gameDeposit}),
                "player2 has already made a move"
            );
        });

        it('should not allow alice to reclaim funds before expiration period', async() => {
            await truffleAssert.reverts(
                instance.player1ReclaimFunds(gId, {from: alice}),
                "game move not yet expired"
            );
        });

        it('should not allow alice to reveal move', async() => {
            await truffleAssert.reverts(
                instance.player1MoveReveal(ROCK, secretAlice, {from: alice}),
                "player2 has not made a move"
            );
        });

    });

    contract('After expriation', (accounts) => {
        const owner = accounts[0];
        const alice = accounts[4];
        const bob = accounts[5];
        const gameDeposit = toWei('5', 'finney');
        const secretAlice = utf8ToHex("secretForAlice");
        let gId = null;
        let instance = null;

        before('set up contract and alice commit to a move', async () => {
            instance = await RockPaperScissors.new({from: owner});
            gId = await instance.generateCommitment(ROCK, secretAlice);
            await instance.player1MoveCommit(gId, bob, {from: alice, value: gameDeposit});
            snapshotId = (await tm.takeSnapshot()).result;
        });

        after("restore snapshot", async() => {
            await tm.revertToSnapshot(snapshotId);
        });

        it('should allow alice to reclaim funds after move expiration period', async() => {
            const SKIP_FORWARD_PERIOD = 15 * 60; //15 mins
            await tm.advanceTimeAndBlock(SKIP_FORWARD_PERIOD);
            const tx = await instance.player1ReclaimFunds(gId, {from: alice});
            truffleAssert.eventEmitted(tx, 'LogPlayer1ReclaimFunds', evt => {
                return evt.player === alice
                    && evt.gameId === gId
                    && evt.amount.toString(10) === gameDeposit.toString(10);
            });
        });

        it('should then not allow bob to make a move', async() => {
            await truffleAssert.reverts(
                instance.player2Move(gId, PAPER, {from: bob, value: gameDeposit}),
                "incorrect player"
            );
        });

        it('should then allow alice to withdraw initial funds', async() => {
            const tx = await instance.withdraw({from: alice})
            truffleAssert.eventEmitted(tx, 'LogWithdraw', evt => {
                return evt.sender === alice
                    && evt.amount.toString(10) === gameDeposit.toString(10);
            });
        });
    });

    contract('After expiration', (accounts) => {
        const owner = accounts[0];
        const alice = accounts[4];
        const bob = accounts[5];
        const gameDeposit = toWei('5', 'finney');
        const secretAlice = utf8ToHex("secretForAlice");
        let gId = null;
        let instance = null;

        before('set up contract and alice commit to a move', async () => {
            instance = await RockPaperScissors.new({from: owner});
            gId = await instance.generateCommitment(ROCK, secretAlice);
            await instance.player1MoveCommit(gId, bob, {from: alice, value: gameDeposit});
            snapshotId = (await tm.takeSnapshot()).result;
        });

        after('restore snapshot', async() => {
            await tm.revertToSnapshot(snapshotId);
        });

        it('should not allow bob to reclaim funds after expiration', async() => {
            const SKIP_FORWARD_PERIOD = 15 * 60; //15 mins
            await tm.advanceTimeAndBlock(SKIP_FORWARD_PERIOD);
            await truffleAssert.reverts(
                instance.player2ClaimFunds(gId, {from: bob}),
                "player2 has not made a move"
            );
        });
    });
});

describe(
    'RockPaperScissors - Given game where alice has commited to a move and then bob has made a move', () =>{
    contract('Before player1 move reveal expiration', (accounts) => {
        const owner = accounts[0];
        const alice = accounts[4];
        const bob = accounts[5];
        const gameDeposit = toWei('5', 'finney');
        const secretAlice = utf8ToHex("secretForAlice");
        let gId = null;
        let instance = null;

        beforeEach('set up contract and moves', async() => {
            instance = await RockPaperScissors.new({from: owner});
            gId = await instance.generateCommitment(ROCK, secretAlice);
            await instance.player1MoveCommit(gId, bob, {from: alice, value: gameDeposit});
            await instance.player2Move(gId, PAPER, {from: bob, value: gameDeposit});
        });

        it('should not allow bob to claim funds before reveal expiration', async() => {
            await truffleAssert.reverts(
                instance.player2ClaimFunds(gId, {from: bob}),
                "game reveal not yet expired"
            );
        });

        it('should not allow alice to reclaim funds', async() => {
            await truffleAssert.reverts(
                instance.player1ReclaimFunds(gId, {from: alice}),
                "player2 has made a move"
            );
        });

        it('should not allow bob to make move', async() => {
            await truffleAssert.reverts(
                instance.player2Move(gId, PAPER, {from: bob, value: gameDeposit}),
                "player2 has already made a move"
            );
        });

        it('should not allow alice to make commitment to a move', async() => {
            const commitment = await instance.generateCommitment(ROCK, secretAlice);
            await truffleAssert.reverts(
                instance.player1MoveCommit(commitment, bob, {from: alice, value: gameDeposit}),
                "game id already used"
            );
        });
    });

    contract('After player1 move reveal expiration', (accounts) => {
        const owner = accounts[0];
        const alice = accounts[4];
        const bob = accounts[5];
        const gameDeposit = toWei('5', 'finney');
        const secretAlice = utf8ToHex("secretForAlice");
        let gId = null;
        let instance = null;

        before('set up contract and moves', async () => {
            instance = await RockPaperScissors.new({from: owner});
            gId = await instance.generateCommitment(ROCK, secretAlice);
            await instance.player1MoveCommit(gId, bob, {from: alice, value: gameDeposit});
            await instance.player2Move(gId, PAPER, {from: bob, value: gameDeposit});
            snapshotId = (await tm.takeSnapshot()).result;
        });

        after('restore snapsht', async() => {
            await tm.revertToSnapshot(snapshotId);
        });

        it('should allow bob to claim the funds after reveal expiration period', async() => {
            const SKIP_FORWARD_PERIOD = 15 * 60; //15 mins
            await tm.advanceTimeAndBlock(SKIP_FORWARD_PERIOD);
            const tx = await instance.player2ClaimFunds(gId, {from: bob});
            truffleAssert.eventEmitted(tx, 'LogPlayer2ClaimFunds', evt => {
                return evt.player === bob
                    && evt.gameId === gId
                    && evt.amount.toString(10) === (gameDeposit*2).toString(10);
            });

            // Assert that game has been reset
            const game = await instance.games(gId);
            assert.equal(game.player2, 0);
            assert.equal(game.gameMove2.toString(10), '0');
            assert.equal(game.gameDeposit, 0);
            assert.equal(game.expiration, 0);
        });

        it('should then allow bob to withdraw the funds', async() => {
            const tx = await instance.withdraw({from: bob})
            truffleAssert.eventEmitted(tx, 'LogWithdraw', evt => {
                return evt.sender === bob
                    && evt.amount.toString(10) === (gameDeposit * 2).toString(10);
            });
        });
    });
});

contract(
    'RockPaperScissors - Given game where alice has commited to a move and bob has made a different (winning) move',
    (accounts) => {
    const owner = accounts[0];
    const alice = accounts[4];
    const bob = accounts[5];
    const {toBN} = web3.utils;
    const gameDeposit = toWei('5', 'finney');
    const secretAlice = utf8ToHex("secretForAlice");
    let gId = null;
    let instance = null;
    
    beforeEach('set up contract and moves', async () => {
        instance = await RockPaperScissors.new({from: owner});
        gId = await instance.generateCommitment(ROCK, secretAlice);
        await instance.player1MoveCommit(gId, bob, {from: alice, value: gameDeposit});
        await instance.player2Move(gId, PAPER, {from: bob, value: gameDeposit});
    });
    
    it('should allow alice to reveal move', async() => {
        const tx = await instance.player1MoveReveal(ROCK, secretAlice, {from: alice});
        truffleAssert.eventEmitted(tx, 'LogMoveReveal', evt => {
            return evt.player === alice
                && evt.gameId === gId
                && evt.gameMove.toString(10) === ROCK.toString(10);
        });

        // bob wins game because PAPER beats ROCK
        truffleAssert.eventEmitted(tx, 'LogGameWinner', evt => {
            return evt.player === bob
                && evt.gameId === gId
                && evt.winnings.toString(10) === (gameDeposit*2).toString(10);
        });
    });

    it('should not allow alice to reclaim funds', async() => {
        await truffleAssert.reverts(
            instance.player1ReclaimFunds(gId, {from: alice}),
            "player2 has made a move"
        );
    });

    it('should allow alice reveal move and bob to claim winnings', async() => {
        await instance.player1MoveReveal(ROCK, secretAlice, {from: alice});
        
        // bob can withdraw winnings
        const bobBalanceBefore = web3.utils.toBN(await web3.eth.getBalance(bob));
        const tx = await instance.withdraw({from: bob});
        truffleAssert.eventEmitted(tx, 'LogWithdraw', evt => {
            return evt.sender === bob
                && evt.amount.toString(10) === (gameDeposit*2).toString(10);
        });
        const bobBalanceAfter = toBN(await web3.eth.getBalance(bob));
        const trans = await web3.eth.getTransaction(tx.tx);
        const gasPrice = toBN(trans.gasPrice);
        const gasUsed = toBN(tx.receipt.gasUsed);
        const gasCost = gasPrice.mul(gasUsed);
        const amountWon = toBN(2*gameDeposit);
        assert.isTrue(bobBalanceAfter.eq(bobBalanceBefore.add(amountWon).sub(gasCost)));

        // Assert that game has been reset
        const game = await instance.games(gId);
        assert.equal(game.player2, 0);
        assert.equal(game.gameMove2.toString(10), '0');
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
    const gameDeposit = toWei('5', 'finney');
    const secretAlice = utf8ToHex("secretForAlice");
    let gId = null;
    let instance = null;
    
    beforeEach('set up contract and moves', async () => {
        instance = await RockPaperScissors.new({from: owner});
        gId = await instance.generateCommitment(ROCK, secretAlice);
        await instance.player1MoveCommit(gId, bob, {from: alice, value: gameDeposit});
        await instance.player2Move(gId, ROCK, {from: bob, value: gameDeposit});
    });
    
    it('should allow alice to reveal move', async() => {
        const tx = await instance.player1MoveReveal(ROCK, secretAlice, {from: alice});
        truffleAssert.eventEmitted(tx, 'LogMoveReveal', evt => {
            return evt.player === alice
                && evt.gameId === gId
                && evt.gameMove.toString(10) === ROCK.toString(10);
        });

        // game is a draw because ROCK draws with ROCK
        truffleAssert.eventEmitted(tx, 'LogGameDraw', evt => {
            return evt.player0 === alice
                && evt.player1 === bob
                && evt.gameId === gId
                && evt.winnings.toString(10) === gameDeposit.toString(10);
        });
    });

    it('should not allow alice to reclaim funds', async() => {
        await truffleAssert.reverts(
            instance.player1ReclaimFunds(gId, {from: alice}),
            "player2 has made a move"
        );
    });

    it('should allow alice reveal move and then both alice and bob to claim winnings', async() => {
        await instance.player1MoveReveal(ROCK, secretAlice, {from: alice});

        // bob can withdraw winnings
        const tx = await instance.withdraw({from: bob});
        truffleAssert.eventEmitted(tx, 'LogWithdraw', evt => {
            return evt.sender === bob
                && evt.amount.toString(10) === gameDeposit.toString(10);
        });
        
        // alice can withdraw winnings
        const tx2 = await instance.withdraw({from: alice});
        truffleAssert.eventEmitted(tx2, 'LogWithdraw', evt => {
            return evt.sender === alice
                && evt.amount.toString(10) === gameDeposit.toString(10);
        });

        // Assert that game has been reset
        const game = await instance.games(gId);
        assert.equal(game.player2, 0);
        assert.equal(game.gameMove2.toString(10), '0');
        assert.equal(game.gameDeposit, 0);
        assert.equal(game.expiration, 0);

        // alice should not be allowed to reclaim funds
        await truffleAssert.reverts(
            instance.player1ReclaimFunds(gId, {from: alice}),
            "no funds"
        );

        // bob should not be allowed to claim funds
        await truffleAssert.reverts(
            instance.player2ClaimFunds(gId, {from: bob}),
            "incorrect player"
        );
    });
});

contract(
    'RockPaperScissors - Given two diffrenet games where alice wins when her move is revealed',
    (accounts) => {
    const owner = accounts[0];
    const alice = accounts[4];
    const bob = accounts[5];
    const carol = accounts[6];
    const gameDeposit = toWei('5', 'finney');
    const secretAlice = utf8ToHex("secretForAlice");
    const secretAlice2 = utf8ToHex("anotherscret");
    let gId1 = null;
    let gId2 = null;
    let instance = null

    before('set up contract and moves', async () => {
        instance = await RockPaperScissors.new({from: owner});
        gId1 = await instance.generateCommitment(PAPER, secretAlice);
        await instance.player1MoveCommit(gId1, bob, {from: alice, value: gameDeposit});
        await instance.player2Move(gId1, ROCK, {from: bob, value: gameDeposit});
        gId2 = await instance.generateCommitment(PAPER, secretAlice2);
        await instance.player1MoveCommit(gId2, carol, {from: alice, value: gameDeposit});
        await instance.player2Move(gId2, ROCK, {from: carol, value: gameDeposit});
    });

    it('should allow alice to reveal move and win game1', async() => {
        const tx = await instance.player1MoveReveal(PAPER, secretAlice, {from: alice});
        truffleAssert.eventEmitted(tx, 'LogMoveReveal', evt => {
            return evt.player === alice
                && evt.gameId === gId1
                && evt.gameMove.toString(10) === PAPER.toString(10);
        });

        // alice wins game1 because PAPER beats ROCK
        truffleAssert.eventEmitted(tx, 'LogGameWinner', evt => {
            return evt.player === alice
                && evt.gameId === gId1
                && evt.winnings.toString(10) === (gameDeposit*2).toString(10);
        });

        // Assert that game1 has been reset
        const game = await instance.games(gId1);
        assert.equal(game.player2, 0);
        assert.equal(game.gameMove2.toString(10), '0');
        assert.equal(game.gameDeposit, 0);
        assert.equal(game.expiration, 0);
    });

    it('should then allow alice to reveal move and win game2', async() => {
        const tx = await instance.player1MoveReveal(PAPER, secretAlice2, {from: alice});
        truffleAssert.eventEmitted(tx, 'LogMoveReveal', evt => {
            return evt.player === alice
                && evt.gameId === gId2
                && evt.gameMove.toString(10) === PAPER.toString(10);
        });

        // alice wins game2 because PAPER beats ROCK
        truffleAssert.eventEmitted(tx, 'LogGameWinner', evt => {
            return evt.player === alice
                && evt.gameId === gId2
                && evt.winnings.toString(10) === (gameDeposit*2).toString(10);
        });

        // Assert that game2 has been reset
        const game = await instance.games(gId2);
        assert.equal(game.player2, 0);
        assert.equal(game.gameMove2.toString(10), '0');
        assert.equal(game.gameDeposit, 0);
        assert.equal(game.expiration, 0);
    });

    it('should then allow alice to withdraw winnings', async() => {
        const tx = await instance.withdraw({from: alice});
        truffleAssert.eventEmitted(tx, 'LogWithdraw', evt => {
            return evt.sender === alice
                && evt.amount.toString(10) === (gameDeposit*4).toString(10);
        });
    });
});
