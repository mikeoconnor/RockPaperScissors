pragma solidity 0.5.0;

import "./Ownable.sol";

contract Stoppable is Ownable {
    bool private running = true;
    bool private killed;

    event LogStopped(address indexed sender);
    event LogResumed(address indexed sender);
    event LogKilled(address indexed sender);
    event LogTransferFund(address indexed to, uint amount);

    modifier ifRunning {
        require(running, "contract not running");
        _;
    }

    modifier ifStopped {
        require(!running, "contract not stopped");
        _;
    }

    modifier ifAlive {
        require(!killed, "contract killed");
        _;
    }

    modifier ifKilled {
        require(killed, "contract still alive");
        _;
    }

    function stop() public onlyOwner ifAlive ifRunning returns(bool success){
        running = false;
        emit LogStopped(msg.sender);
        return true;
    }

    function resume() public onlyOwner ifAlive ifStopped returns(bool success){
        running = true;
        emit LogResumed(msg.sender);
        return true;
    }

    function kill() public onlyOwner ifAlive ifStopped returns(bool success){
        killed = true;
        emit LogKilled(msg.sender);
        return true;
    }

    function transferFundsFromKilledContract(address payable toAddress) public onlyOwner ifKilled returns(bool success){
        require(toAddress != address(0));
        uint amount = address(this).balance;
        require(amount > 0, "no funds");
        emit LogTransferFund(toAddress, amount);
        (bool result, ) = toAddress.call.value(amount)("");
        require(result);
        return true;
    }

    function isRunning() public view returns(bool){
        return running;
    }

    function isKilled() public view returns(bool){
        return killed;
    }
}

