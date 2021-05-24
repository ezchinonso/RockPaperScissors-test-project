const { expect } = require("chai");

describe("RockpaperScissors", function() {

  let player0;
  let player1;
  let randomPlayers;
  let RPS;
  let rps;
  let FakeDai;
  let fDai;
  

  beforeEach(async function () {
    FakeDai = await ethers.getContractFactory("FakeDai");

    fDai = await FakeDai.deploy();
    await fDai.deployed()

    // Get the ContractFactory and Signers here.
    RPS = await ethers.getContractFactory("RockPaperScissors");
    [owner, player0, player1, ...randomPlayers] = await ethers.getSigners();

    // To deploy our contract, we just have to call Token.deploy() and await
    // for it to be deployed(), which happens onces its transaction has been
    // mined.
    rps = await RPS.deploy(fDai.address);
    await rps.deployed();

    const amt = 1000000
    await fDai.approve(owner.address, amt); 
    await fDai.transferFrom(owner.address, player0.address, 50)
    await fDai.transferFrom(owner.address, player1.address, 50)
    


    
  });    
  it("Should auto enroll player into match", async function() {
    let id;
    await fDai.connect(player0).approve(rps.address, 1000);
    await rps.connect(player0).matchnroll();
    id = await rps.getPlayerIndex(1, player0.address);
    console.log(`player0 index is ${id.toNumber()}`)
    await expect(id).to.be.equal(0)
    await fDai.connect(player1).approve(rps.address, 1000);
    await rps.connect(player1).matchnroll();
    id = await rps.getPlayerIndex(1, player1.address);
    console.log(`player1 index is ${id.toNumber()}`)
    await expect(id).to.be.equal(1)
    
  });
  it("Settles dispute 1 correctly", async function() {
    // player0 auto enrolls into a match and places his/her but there is no opponent after 15mins
    // ensure player0 can recover their bet whenever the settleDispute function is called
    let playerBal;

    await fDai.connect(player0).approve(rps.address, 1000);
    await rps.connect(player0).matchnroll();

    playerBal = await rps.getPlayerBalance(player0.address);
    console.log(`Balance of player0 after RPS enrollment = ${playerBal}\n`)

    // increase current block timestamp by an hour
    await network.provider.send("evm_increaseTime", [3600]);
    await network.provider.send("evm_mine");
    // anyone can settle dispute
    await rps.settleDispute(1);
    playerBal = await rps.getPlayerBalance(player0.address);
    await expect(playerBal.toNumber()).to.be.eql(10);
    console.log(`Balance of player0 after dispute settlement = ${playerBal}\n`)

  });
  it("Settles dispute 2 correctly", async function() {
    // After both player0 and player1 auto enroll for RPS match either of them becomes uncooperative
    // and unwilling to play, the defaulting player loses their bet and the total bet amount is transfered
    // to the other player who is declared winner.
    let player0Bal;
    let player1Bal;
    const id=1;

    await fDai.connect(player0).approve(rps.address, 1000);
    await rps.connect(player0).matchnroll();

    await fDai.connect(player1).approve(rps.address, 1000);
    await rps.connect(player1).matchnroll();

    // increase current block timestamp by an hour
    await network.provider.send("evm_increaseTime", [3600]);
    await network.provider.send("evm_mine");

    await expect(rps.settleDispute(id)).to.be.revertedWith("No move made");

    player0Bal = await rps.getPlayerBalance(player0.address);
    console.log(`Balance of player0 after RPS enrollment = ${player0Bal}\n`)

    player1Bal = await rps.getPlayerBalance(player1.address);
    console.log(`Balance of player1 after RPS enrollment = ${player1Bal}\n`)
    
    // player1 generates hash using helper function and plays
    const byt = await rps.generateCommitHash(1, 43);
    await rps.connect(player1).play(id, byt)

    // increase current block timestamp by an hour
    await network.provider.send("evm_increaseTime", [3600]);
    await network.provider.send("evm_mine");
    // anyone can settle dispute
    await rps.settleDispute(id);
    
    player0Bal = await rps.getPlayerBalance(player0.address);
    console.log(`Balance of player0 after dispute settlement = ${player0Bal}\n`)
    player1Bal = await rps.getPlayerBalance(player1.address);
    console.log(`Balance of player1 after dispute settlement = ${player1Bal}\n`)

    await expect(player1Bal.toNumber()).to.be.eql(20);
    await expect(player0Bal.toNumber()).to.be.eql(0);

  });
  it("Settles dispute 3 correctly", async function() {
    // After both player0 and player1 auto enroll for RPS match an both have made played/commited 
    // their move, if either player is uncooperative or unwilling to reveal their commit/move, 
    // anyone can call settle dispute function - the defaulting player loses their bet and the total bet amount is transfered
    // to the other player who is declared winner.

    let player0Bal;
    let player1Bal;
    let player0CH = 1;
    let player1CH = 2;
    let player0salt = ethers.utils.parseUnits((Math.random() * 100).toString());
    let player1salt = ethers.utils.parseUnits((Math.random() * 100).toString());
    let byt;
    const id=1;
    await fDai.connect(player0).approve(rps.address, 1000);
    await rps.connect(player0).matchnroll();

    await fDai.connect(player1).approve(rps.address, 1000);
    await rps.connect(player1).matchnroll();


    player0Bal = await rps.getPlayerBalance(player0.address);
    console.log(`Balance of player0 after RPS enrollment = ${player0Bal}\n`)

    player1Bal = await rps.getPlayerBalance(player1.address);
    console.log(`Balance of player1 after RPS enrollment = ${player1Bal}\n`)

    // player1 generates hash using helper function and plays
    byt = await rps.generateCommitHash(player0CH, player0salt);
    await rps.connect(player0).play(id, byt);

    //player2 generates hash using helper function and plays
    byt = await rps.generateCommitHash(player1CH, player1salt);
    await rps.connect(player1).play(id, byt);

    // increase current block timestamp by an hour
    await network.provider.send("evm_increaseTime", [3600]);
    await network.provider.send("evm_mine");

    await expect(rps.settleDispute(id)).to.be.revertedWith("No reveal made yet");

    await rps.connect(player0).reveal(id, player0CH, player0salt);

    // increase current block timestamp by an hour
    await network.provider.send("evm_increaseTime", [3600]);
    await network.provider.send("evm_mine");
    // anyone can settle dispute
    await rps.settleDispute(id);
    player0Bal = await rps.getPlayerBalance(player0.address);
    console.log(`Balance of player0 after dispute settlement = ${player0Bal}\n`)
    player1Bal = await rps.getPlayerBalance(player1.address);
    console.log(`Balance of player1 after dispute settlement = ${player1Bal}\n`)
    await expect(player0Bal.toNumber()).to.be.eql(20);
    await expect(player1Bal.toNumber()).to.be.eql(0);

  });
  it("Should declare correct winner", async function(){
    let player0Bal;
    let player1Bal;
    let player0CH = 1;
    let player1CH = 2;
    let player0salt = ethers.utils.parseUnits((Math.random() * 100).toString());
    let player1salt = ethers.utils.parseUnits((Math.random() * 100).toString());
    let byt;
    const id=1;
    await fDai.connect(player0).approve(rps.address, 1000);
    await rps.connect(player0).matchnroll();

    await fDai.connect(player1).approve(rps.address, 1000);
    await rps.connect(player1).matchnroll();


    player0Bal = await rps.getPlayerBalance(player0.address);
    console.log(`Balance of player0 before match = ${player0Bal}\n`)

    player1Bal = await rps.getPlayerBalance(player1.address);
    console.log(`Balance of player1 before match = ${player1Bal}\n`)

    // player1 generates hash using helper function and plays
    byt = await rps.generateCommitHash(player0CH, player0salt);
    await rps.connect(player0).play(id, byt);

    //player2 generates hash using helper function and plays
    byt = await rps.generateCommitHash(player1CH, player1salt);
    await rps.connect(player1).play(id, byt);

    await rps.connect(player0).reveal(id, player0CH, player0salt);
    await rps.connect(player1).reveal(id, player1CH, player1salt);

    await rps.declareWinner(id);
    player0Bal = await rps.getPlayerBalance(player0.address);
    console.log(`Balance of player0 after match = ${player0Bal}\n`)
    player1Bal = await rps.getPlayerBalance(player1.address);
    console.log(`Balance of player1 after match = ${player1Bal}\n`)
    await expect(await rps.getWinner(id)).to.be.eql(player1.address)
    await expect(player0Bal.toNumber()).to.be.eql(0);
    await expect(player1Bal.toNumber()).to.be.eql(20);
  })
  it("Emit correct events", async function(){
    // TODO
  })
});
