pragma solidity 0.6.12;

import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";

contract DogeOracle is OwnableUpgradeSafe {

    bool private _validity = true;
    uint256 private _data;
    string public name;

    constructor(string memory name_) public {
        __Ownable_init();
        name = name_;
    }

    function getData()
        external
        view
        returns (uint256, bool)
    {
        uint256[] memory uintVals = new uint256[](0);
        int256[] memory intVals = new int256[](0);
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
