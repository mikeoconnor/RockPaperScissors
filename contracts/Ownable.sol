pragma solidity 0.5.0;

contract Ownable {

    address private owner;

    event LogChangeOwner(address oldOwner, address newOwner);

    modifier onlyOwner {
        require(owner == msg.sender, "Not owner");
        _;
    }

    constructor() public {
        owner = msg.sender;
        emit LogChangeOwner(address(0), msg.sender);
    }

    function changeOwner(address newOwner) public onlyOwner returns(bool success){
        require(newOwner != address(0), "NewOwner is empty address");
        owner = newOwner;
        emit LogChangeOwner(msg.sender, newOwner);
        return true;
    }

    function getOwner() public view returns (address _owner){
        return owner;
    }
}
