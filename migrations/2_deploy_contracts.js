const RockPaperScissors = artifacts.require("RockPaperScissors");

module.exports = function(deployer) {
    // Use gameDeposite of 0.005 ether = 5000000000000000 wei = 5 finney
    deployer.deploy(RockPaperScissors, "5000000000000000");
};
