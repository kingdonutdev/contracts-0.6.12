pragma solidity 0.6.12;

import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";

contract DogeOracle is OwnableUpgradeSafe {

    event FunctionCalled(string instanceName, string functionName, address caller);
    event FunctionArguments(uint256[] uintVals, int256[] intVals);

    bool private _validity = true;
    uint256 private _data;
    string public name;

    constructor(string memory name_) public {
        name = name_;
    }

    function getData()
        external
        returns (uint256, bool)
    {
        emit FunctionCalled(name, "getData", msg.sender);
        uint256[] memory uintVals = new uint256[](0);
        int256[] memory intVals = new int256[](0);
        emit FunctionArguments(uintVals, intVals);
        return (_data, _validity);
    }

    function storeData(uint256 data)
        public
        onlyOwner
    {
        _data = data;
    }

    function storeValidity(bool validity)
        public
        onlyOwner
    {
        _validity = validity;
    }
}
